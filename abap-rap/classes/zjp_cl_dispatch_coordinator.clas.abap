" Phase 5.2g - the post-commit dispatch coordinator.

"

" This is the object ADR-006 and ARCHITECTURE's transaction-boundary section have

" been describing since Phase 1: "claim through EML, commit, send using a released

" HTTP client, then record the receipt through EML and commit." It runs OUTSIDE

" every behavior handler, which is what makes the HTTP call legal at all - a

" remote call inside a RAP action risks a remote change surviving a failed local

" transaction, and holds the BO lock for the length of a network round trip.

"

" THREE BOUNDARIES, AND THEY ARE THE POINT OF THE CLASS.

"

"   TRANSACTION A  claim one eligible persisted intent under a lease,

"                  DispatchState -> IN_FLIGHT, then COMMIT.

"   NETWORK        reconstruct the delivery from the PERSISTED snapshot, map it,

"                  mint a correlation id, POST. No database work at all.

"   TRANSACTION B  write the classified outcome onto the intent, drive the

"                  PurchaseOrder through recordDeliveryResult, then COMMIT.

"

" The commit in A is not a detail. It is the reason the outbox exists: once

" IN_FLIGHT is durable, a coordinator that dies mid-POST leaves a row that says

" so, and the lease is what lets a later run tell "in progress" from "abandoned".

"

" WHAT IT DISPATCHES IS WHAT WAS APPROVED. The body comes from

" ZJP_PO_DLV-PayloadSnapshot through ZJP_CL_DLV_SNAPSHOT_READER. The coordinator

" never reads PurchaseOrder to build a payload and never touches the snapshot or

" its hash. Phase 5.2f froze them with the approval; re-deriving them here would

" dispatch whatever the order happens to say now, which is the exact failure the

" immutable snapshot exists to prevent.

"

" IT NEVER BLIND-RETRIES A TERMINAL OR AMBIGUOUS OUTCOME. Phase 7.4 adds a

" durable bounded policy only for retryable PENDING outcomes: four total transport

" attempts, persisted due times, and a 15-minute retry-cycle window. FAILED and

" UNKNOWN are never returned to PENDING by this coordinator; reconciliation or an

" explicit operator action remains responsible for those states.

"

" TRANSPORT IS INJECTED THROUGH THE SEAM, never constructed here. That is what

" lets the whole claim/classify/record contract be tested with the deterministic

" fake and no network, while the console runner supplies the real adapter.

"

" SAP RUNTIME-VERIFIED in Phase 5.2g, across the whole A-J matrix. The real run

" posted to the deployed CAP portal and came back 201: the intent went DELIVERED,

" the order went APPROVED -> SENT, the receipt identity was stored and the lease

" was released, with the persisted snapshot, its hash and the approval evidence

" all untouched.

"

" Two target-specific facts were learned by failing first, and both are recorded

" at their call sites rather than here: XCO's WRITE_TO is TERMINAL and cannot be

" chained, and CL_SYSTEM_UUID's C36 -> X16 conversion CORRUPTS LOWERCASE INPUT

" WITHOUT RAISING. The second one produced a passing 201 with a broken receipt

" identity, which is exactly the kind of failure a green test hides.

CLASS zjp_cl_dispatch_coordinator DEFINITION

  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    " The dispatch-state vocabulary, deliberately the same words as the header's

    " IntegrationStatus so the two never need translating (ZJP_I_DeliveryIntent).

    CONSTANTS:

      BEGIN OF state,

        pending   TYPE string VALUE 'PENDING',

        in_flight TYPE string VALUE 'IN_FLIGHT',

        delivered TYPE string VALUE 'DELIVERED',

        failed    TYPE string VALUE 'FAILED',

        unknown   TYPE string VALUE 'UNKNOWN',

      END OF state.

    " Why a run did nothing. A coordinator that declines to act is the normal

    " case, not an error, so it is reported as a reason rather than as a failure.

    CONSTANTS:

      BEGIN OF skipped,

        none_eligible  TYPE string VALUE 'NONE_ELIGIBLE',

        not_found      TYPE string VALUE 'INTENT_NOT_FOUND',

        lease_live     TYPE string VALUE 'LEASE_LIVE',

        state_final    TYPE string VALUE 'STATE_NOT_CLAIMABLE',

        claim_failed   TYPE string VALUE 'CLAIM_FAILED',

        claim_lost            TYPE string VALUE 'CLAIM_LOST_TO_OTHER_RUN',

        before_due            TYPE string VALUE 'BEFORE_DUE',

        retry_exhausted       TYPE string VALUE 'RETRY_EXHAUSTED',

        retry_window_blocked  TYPE string VALUE 'RETRY_WINDOW_BLOCKED',

      END OF skipped.

    TYPES:

      BEGIN OF ty_outcome,

        " Did this run take ownership of an intent at all?

        claimed             TYPE abap_bool,

        skip_reason         TYPE string,

        " Identity. delivery_uuid is the wire deliveryId and never changes.

        delivery_uuid       TYPE sysuuid_x16,

        purchase_order_uuid TYPE sysuuid_x16,

        order_revision      TYPE i,

        " Who held the lease and until when, as committed in transaction A.

        run_uuid            TYPE sysuuid_x16,

        lease_expires_at    TYPE zjp_po_dlv-lease_expires_at,

        " One per HTTP attempt. A retry gets a new one; deliveryId does not.

        correlation_uuid    TYPE sysuuid_x16,

        " Was the outbound transport seam invoked for this run? This does not prove

        " bytes reached the network: Phase 7.4 certainty may report NOT_SENT.

        dispatched          TYPE abap_bool,

        answered            TYPE abap_bool,

        http_status         TYPE i,

        " Phase 7.3 / 7.4. Durable count of transport post() attempts.

        " Every invocation counts, including a proven NOT_SENT outcome. Skips do not.

        attempt_count       TYPE i,

        " Phase 7.4 durable retry policy state written in transaction B.

        next_attempt_at         TYPE zjp_po_dlv-next_attempt_at,

        retry_window_started_at TYPE zjp_po_dlv-retry_window_started_at,

        " The classification, and what was written because of it.

        final_state         TYPE string,

        business_status     TYPE string,

        portal_order_uuid   TYPE sysuuid_x16,

        recorded            TYPE abap_bool,

        error_code          TYPE string,

        error_text          TYPE string,

      END OF ty_outcome.

    " lease_seconds is an EXPLICIT INPUT and has no default here on purpose.

    " Phase 5.2g deliberately introduces no production lease timeout and no

    " configuration object; the runner or the test supplies a value, and where

    " that value eventually comes from is a later decision.

    "

    " run_uuid is optional so a test can pin a run identity and assert on it.

    " Left out, the constructor mints one - ONE per coordinator instance, which

    " is what "a per-run execution identity rather than a user" means.

    METHODS constructor

      IMPORTING transport           TYPE REF TO zjp_if_outbound_transport

                lease_seconds       TYPE i

                run_uuid            TYPE sysuuid_x16 OPTIONAL

                jitter_milliseconds TYPE i OPTIONAL

                policy_timestamp    TYPE timestampl OPTIONAL.

    METHODS get_run_uuid

      RETURNING VALUE(uuid) TYPE sysuuid_x16.

    " The whole flow for ONE intent. Without delivery_uuid it selects the oldest

    " eligible one; with it, that one and only that one - which is how the tests

    " drive a specific fixture instead of whatever the table happens to hold.

    METHODS run_once

      IMPORTING delivery_uuid  TYPE sysuuid_x16 OPTIONAL

      RETURNING VALUE(outcome) TYPE ty_outcome.

    " Exposed so a runner can report what it would work on without claiming it.

    " Read-only, and it takes no lease.

    METHODS find_eligible

      RETURNING VALUE(delivery_uuid) TYPE sysuuid_x16.

    " TRANSACTION A on its own. Public because ARCHITECTURE describes the two

    " commits as separately runnable steps with a durable row in between that

    " can be inspected - "this makes the commit boundaries observable". It is

    " also what lets the lease contract be tested without a network call.

    METHODS claim_intent

      IMPORTING delivery_uuid  TYPE sysuuid_x16

      RETURNING VALUE(outcome) TYPE ty_outcome.

  PRIVATE SECTION.

    " The Integration Suite route, owned here since Phase 6.4b because the

    " mapper that used to own it is no longer on this path. Deliberately a

    " constant and not a constructor parameter: Phase 5.2g introduced no

    " configuration object and this phase introduces none either, so the route

    " sits where ZJP_CL_CAP_ORDER_MAPPER's ingestion_path always sat. The

    " path-less destination supplies everything else.

    "

    " SM59 destination ZJP_CI_ORDER_DELIVERY, runtime-verified in Phase 6.4a,

    " carries the Integration Suite host, port 443, TLS and OAuth 2.0 client

    " credentials, with its Path Prefix EMPTY so that this value is the whole

    " application route.

    CONSTANTS ci_delivery_path TYPE string VALUE '/http/pih/v1/order-deliveries'.

    CONSTANTS content_type     TYPE string VALUE 'application/json'.

    DATA transport                TYPE REF TO zjp_if_outbound_transport.

    DATA lease_seconds            TYPE i.

    DATA run_uuid                 TYPE sysuuid_x16.

    " Optional deterministic Phase 7.4c test seams. Production callers omit them.

    DATA jitter_override_supplied TYPE abap_bool.

    DATA jitter_override_ms       TYPE i.

    DATA time_override_supplied   TYPE abap_bool.

    DATA time_override            TYPE timestampl.

    TYPES:

      BEGIN OF ty_intent_row,

        delivery_uuid       TYPE zjp_po_dlv-delivery_uuid,

        purchase_order_uuid TYPE zjp_po_dlv-purchase_order_uuid,

        order_revision      TYPE zjp_po_dlv-order_revision,

        dispatch_state      TYPE zjp_po_dlv-dispatch_state,

        lease_owner         TYPE zjp_po_dlv-lease_owner,

        lease_expires_at    TYPE zjp_po_dlv-lease_expires_at,

        payload_snapshot          TYPE zjp_po_dlv-payload_snapshot,

        attempt_count             TYPE zjp_po_dlv-attempt_count,

        next_attempt_at           TYPE zjp_po_dlv-next_attempt_at,

        retry_window_started_at   TYPE zjp_po_dlv-retry_window_started_at,

      END OF ty_intent_row.

    TYPES:

      BEGIN OF ty_retry_timing,

        next_attempt_at         TYPE zjp_po_dlv-next_attempt_at,

        retry_window_started_at TYPE zjp_po_dlv-retry_window_started_at,

      END OF ty_retry_timing.

    " The CAP ingestion receipt, bound the same way the snapshot is.

    TYPES:

      BEGIN OF ty_receipt,

        delivery_id     TYPE string,

        source_order_id TYPE string,

        portal_order_id TYPE string,

        status          TYPE string,

        received_at     TYPE string,

      END OF ty_receipt.

    " TRANSACTION A, as used internally by run_once.

    METHODS claim

      IMPORTING delivery_uuid  TYPE sysuuid_x16

      CHANGING  outcome        TYPE ty_outcome

      RETURNING VALUE(success) TYPE abap_bool.

    " TRANSACTION B.

    METHODS record

      IMPORTING row            TYPE ty_intent_row

      CHANGING  outcome        TYPE ty_outcome

      RETURNING VALUE(success) TYPE abap_bool.

    " Read-only. Justified and documented: RAP has no query for "every intent in

    " this state", the rows are read and never written here, and every WRITE in

    " this class goes through EML. The same justification the Phase 5.2f handler

    " records for its own SELECT on this table.

    METHODS read_intent

      IMPORTING delivery_uuid TYPE sysuuid_x16

      EXPORTING row           TYPE ty_intent_row

      RETURNING VALUE(found)  TYPE abap_bool.

    " Phase 7.4c retry timing. Jitter is whole milliseconds and never shortens

    " the frozen 5s / 30s / 120s base delays. Transaction B persists the chosen

    " timing so a later process sees the same due time. The target compiler/runtime

    " probe also proved UTC DATE/TIME -> TIMESTAMPL conversion for IMF-fixdate.

    METHODS retry_jitter_ms

      IMPORTING max_milliseconds TYPE i

      RETURNING VALUE(jitter_ms) TYPE i.

    METHODS retry_delay_ms

      IMPORTING attempt_count   TYPE i

      RETURNING VALUE(delay_ms) TYPE i.

    METHODS calculate_retry_timing

      IMPORTING row            TYPE ty_intent_row

                current        TYPE timestampl

                attempt_count  TYPE i

      RETURNING VALUE(timing)  TYPE ty_retry_timing.

    " Phase 7.4c retry eligibility for a PENDING row. Initial means eligible.

    " Precedence is fixed: exhausted -> retry-window blocked -> before due.

    " The helper is deliberately pure/read-only. It does not claim or persist.

    METHODS pending_skip_reason

      IMPORTING row            TYPE ty_intent_row

                current        TYPE timestampl

      RETURNING VALUE(reason)  TYPE string.

    " Phase 7.4c Retry-After parsing. The transport seam exposes only the raw

    " bounded header. Delta-seconds and strict canonical IMF-fixdate are accepted;

    " malformed/overflowing values return initial and are ignored by policy.

    METHODS retry_after_due

      IMPORTING raw_value  TYPE string

                current    TYPE timestampl

      RETURNING VALUE(due) TYPE zjp_po_dlv-next_attempt_at.

    METHODS parse_imf_fixdate

      IMPORTING raw_value        TYPE string

      RETURNING VALUE(parsed_at) TYPE zjp_po_dlv-next_attempt_at.

    " Section 6.4's table, applied to the transport's own result fields.

    METHODS classify

      IMPORTING response           TYPE zjp_if_outbound_transport=>ty_response

      RETURNING VALUE(final_state) TYPE string.

    METHODS business_status_for

      IMPORTING final_state    TYPE string

      RETURNING VALUE(status)  TYPE string.

    METHODS uuid_text

      IMPORTING uuid        TYPE sysuuid_x16

      RETURNING VALUE(text) TYPE string.

    " The second of the two WRITE_TO bindings in Phase 5.2g. If ADT rejects the

    " XCO chain, this method and ZJP_CL_DLV_SNAPSHOT_READER=>BIND_SOURCE are the

    " only two places that change.

    METHODS read_receipt

      IMPORTING body           TYPE string

      EXPORTING receipt        TYPE ty_receipt

      RETURNING VALUE(success) TYPE abap_bool.

    METHODS now

      RETURNING VALUE(stamp) TYPE timestampl.

ENDCLASS.


CLASS zjp_cl_dispatch_coordinator IMPLEMENTATION.

  METHOD constructor.

    me->transport     = transport.

    me->lease_seconds = lease_seconds.

    IF jitter_milliseconds IS SUPPLIED.

      jitter_override_supplied = abap_true.

      jitter_override_ms = jitter_milliseconds.

    ENDIF.

    IF policy_timestamp IS SUPPLIED AND policy_timestamp IS NOT INITIAL.

      time_override_supplied = abap_true.

      time_override = policy_timestamp.

    ENDIF.

    IF run_uuid IS SUPPLIED AND run_uuid IS NOT INITIAL.

      me->run_uuid = run_uuid.

    ELSE.

      " P14, SAP-verified: returns sysuuid_x16 directly, which is exactly the

      " type ZJP_PO_DLV-lease_owner stores. Minted ONCE per instance.

      me->run_uuid = cl_system_uuid=>create_uuid_x16_static( ).

    ENDIF.

  ENDMETHOD.


  METHOD get_run_uuid.

    uuid = run_uuid.

  ENDMETHOD.


  METHOD claim_intent.

    claim( EXPORTING delivery_uuid = delivery_uuid

           CHANGING  outcome       = outcome ).

  ENDMETHOD.


  METHOD now.

    IF time_override_supplied = abap_true.

      stamp = time_override.

      RETURN.

    ENDIF.

    GET TIME STAMP FIELD stamp.

  ENDMETHOD.


  METHOD uuid_text.

    " P5, SAP-verified.

    DATA uuid_c36 TYPE sysuuid_c36.

    cl_system_uuid=>convert_uuid_x16_static(

      EXPORTING uuid     = uuid

      IMPORTING uuid_c36 = uuid_c36 ).

    text = uuid_c36.

  ENDMETHOD.


  METHOD retry_jitter_ms.

    CLEAR jitter_ms.

    IF max_milliseconds <= 0.

      RETURN.

    ENDIF.

    " Tests may pin one exact jitter value. Clamp only the test seam to the

    " legal range for the current attempt. Production callers never supply it.

    IF jitter_override_supplied = abap_true.

      jitter_ms = jitter_override_ms.

      IF jitter_ms < 0.

        CLEAR jitter_ms.

      ELSEIF jitter_ms > max_milliseconds.

        jitter_ms = max_milliseconds.

      ENDIF.

      RETURN.

    ENDIF.

    TRY.

        DATA(generator) = cl_abap_random_int=>create(

                            seed = cl_abap_random=>seed( )

                            min  = 0

                            max  = max_milliseconds ).

        jitter_ms = generator->get_next( ).

      CATCH cx_abap_random.

        " Zero is itself a valid member of the frozen positive-only jitter

        " interval, so a generator failure never shortens the base delay.

        CLEAR jitter_ms.

    ENDTRY.

  ENDMETHOD.


  METHOD retry_delay_ms.

    CLEAR delay_ms.

    CASE attempt_count.

      WHEN 1.

        delay_ms = 5000 + retry_jitter_ms( 1000 ).

      WHEN 2.

        delay_ms = 30000 + retry_jitter_ms( 6000 ).

      WHEN 3.

        delay_ms = 120000 + retry_jitter_ms( 24000 ).

      WHEN OTHERS.

        " Attempt 4 exhausts the automatic budget; there is no fifth due time.

        CLEAR delay_ms.

    ENDCASE.

  ENDMETHOD.


  METHOD calculate_retry_timing.

    CLEAR timing.

    timing-retry_window_started_at = row-retry_window_started_at.

    " The anchor is created exactly once: on the first transient outcome handled

    " by Phase 7.4. Legacy rows therefore keep their historical attempt count

    " but start a retry window only when a new transient is observed.

    IF timing-retry_window_started_at IS INITIAL.

      timing-retry_window_started_at = current.

    ENDIF.

    " Four TOTAL transport attempts. Once attempt 4 has happened, keep PENDING

    " but persist no deferred fifth attempt. Eligibility blocks by AttemptCount.

    IF attempt_count >= 4.

      CLEAR timing-next_attempt_at.

      RETURN.

    ENDIF.

    DATA(delay_ms) = retry_delay_ms( attempt_count ).

    IF delay_ms <= 0.

      CLEAR timing-next_attempt_at.

      RETURN.

    ENDIF.

    DATA delay_seconds TYPE p LENGTH 8 DECIMALS 3.

    delay_seconds = CONV decfloat34( delay_ms ) / 1000.

    TRY.

        timing-next_attempt_at = cl_abap_tstmp=>add(

                                   tstmp = current

                                   secs  = delay_seconds ).

      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.

        " With a current timestamp and a bounded <=144s delay this should not

        " occur with a system timestamp and a bounded <=144s delay. Leave the

        " due time initial; the network-free policy harness will exercise every

        " normal boundary before any real transport acceptance.

        CLEAR timing-next_attempt_at.

    ENDTRY.

  ENDMETHOD.


   METHOD parse_imf_fixdate.

    CLEAR parsed_at.

    " IMF-fixdate canonical form:
    "
    "   Sun, 06 Nov 1994 08:49:37 GMT
    "
    " IMPORTANT:
    " Do not validate the spaces with expressions such as
    " raw_value+7(1) = ' '.
    "
    " raw_value is STRING while a text literal such as ' ' is type C.
    " On this target the C -> STRING comparison loses trailing blanks,
    " which caused a valid canonical IMF-fixdate to be rejected.
    "
    " Use one exact regex for the lexical structure instead.

    IF strlen( raw_value ) <> 29.
      RETURN.
    ENDIF.

    FIND REGEX
      '^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$'
      IN raw_value.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.


    " ============================================================
    " Extract the already structurally validated components.
    " ============================================================

    DATA(weekday)     = raw_value+0(3).
    DATA(day_text)    = raw_value+5(2).
    DATA(month_text)  = raw_value+8(3).
    DATA(year_text)   = raw_value+12(4).
    DATA(hour_text)   = raw_value+17(2).
    DATA(minute_text) = raw_value+20(2).
    DATA(second_text) = raw_value+23(2).


    " ============================================================
    " Numeric components.
    " ============================================================

    DATA(numeric_parts) =
        year_text
      && day_text
      && hour_text
      && minute_text
      && second_text.

    FIND REGEX '^[0-9]{12}$'
      IN numeric_parts.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.


    " ============================================================
    " Canonical English month abbreviation.
    " ============================================================

    DATA month_number TYPE c LENGTH 2.

    CASE month_text.

      WHEN 'Jan'.
        month_number = '01'.

      WHEN 'Feb'.
        month_number = '02'.

      WHEN 'Mar'.
        month_number = '03'.

      WHEN 'Apr'.
        month_number = '04'.

      WHEN 'May'.
        month_number = '05'.

      WHEN 'Jun'.
        month_number = '06'.

      WHEN 'Jul'.
        month_number = '07'.

      WHEN 'Aug'.
        month_number = '08'.

      WHEN 'Sep'.
        month_number = '09'.

      WHEN 'Oct'.
        month_number = '10'.

      WHEN 'Nov'.
        month_number = '11'.

      WHEN 'Dec'.
        month_number = '12'.

      WHEN OTHERS.
        RETURN.

    ENDCASE.


    " ============================================================
    " Numeric range validation.
    " ============================================================

    TRY.

        DATA(day_number) =
          CONV i( day_text ).

        DATA(hour_number) =
          CONV i( hour_text ).

        DATA(minute_number) =
          CONV i( minute_text ).

        DATA(second_number) =
          CONV i( second_text ).

        IF day_number < 1
           OR day_number > 31
           OR hour_number > 23
           OR minute_number > 59
           OR second_number > 59.

          RETURN.

        ENDIF.

      CATCH cx_root.
        RETURN.

    ENDTRY.


    " ============================================================
    " Build UTC date/time.
    " ============================================================

    DATA date_text TYPE c LENGTH 8.
    DATA time_text TYPE c LENGTH 6.

    CONCATENATE
      year_text
      month_number
      day_text
      INTO date_text.

    CONCATENATE
      hour_text
      minute_text
      second_text
      INTO time_text.


    DATA parsed_date TYPE d.
    DATA parsed_time TYPE t.

    parsed_date = date_text.
    parsed_time = time_text.


    CONVERT DATE parsed_date
            TIME parsed_time
            INTO TIME STAMP parsed_at
            TIME ZONE 'UTC'.

    IF sy-subrc <> 0
       OR parsed_at IS INITIAL.

      CLEAR parsed_at.
      RETURN.

    ENDIF.


    " ============================================================
    " Verify the weekday.
    "
    " 1970-01-04 was a Sunday. This prevents accepting a lexical
    " IMF-fixdate whose weekday contradicts its actual calendar date.
    " ============================================================

    DATA sunday TYPE d VALUE '19700104'.

    DATA day_difference TYPE i.
    DATA weekday_index  TYPE i.

    day_difference =
      parsed_date - sunday.

    weekday_index =
      day_difference MOD 7.

    IF weekday_index < 0.
      weekday_index = weekday_index + 7.
    ENDIF.


    DATA expected_weekday TYPE c LENGTH 3.

    CASE weekday_index.

      WHEN 0.
        expected_weekday = 'Sun'.

      WHEN 1.
        expected_weekday = 'Mon'.

      WHEN 2.
        expected_weekday = 'Tue'.

      WHEN 3.
        expected_weekday = 'Wed'.

      WHEN 4.
        expected_weekday = 'Thu'.

      WHEN 5.
        expected_weekday = 'Fri'.

      WHEN 6.
        expected_weekday = 'Sat'.

      WHEN OTHERS.
        CLEAR parsed_at.
        RETURN.

    ENDCASE.


    IF weekday <> expected_weekday.
      CLEAR parsed_at.
    ENDIF.

  ENDMETHOD.


  METHOD retry_after_due.

    CLEAR due.

    IF raw_value IS INITIAL OR strlen( raw_value ) > 128.

      RETURN.

    ENDIF.

    " RFC delta-seconds: one or more decimal digits, no sign, exponent or hex.

    FIND REGEX '^[0-9]+$' IN raw_value.

    IF sy-subrc = 0.

      TRY.

          DATA delta_seconds TYPE p LENGTH 16 DECIMALS 0.

          delta_seconds = raw_value.

          due = cl_abap_tstmp=>add(

                  tstmp = current

                  secs  = delta_seconds ).

        CATCH cx_root.

          CLEAR due.

      ENDTRY.

      RETURN.

    ENDIF.

    " The only date form accepted by Phase 7.4 is strict canonical IMF-fixdate.

    due = parse_imf_fixdate( raw_value ).

  ENDMETHOD.


  METHOD pending_skip_reason.

    CLEAR reason.

    " Four total transport attempts. Once the durable count reaches four,

    " a PENDING intent stays PENDING for operator review and is never selected

    " automatically again.

    IF row-attempt_count >= 4.

      reason = skipped-retry_exhausted.

      RETURN.

    ENDIF.

    TRY.

        " The retry-cycle anchor is initial for legacy rows and for deliveries

        " that have not yet entered the Phase 7.4 transient retry cycle.

        IF row-retry_window_started_at IS NOT INITIAL.

          DATA(window_end) = cl_abap_tstmp=>add(

                               tstmp = row-retry_window_started_at

                               secs  = 900 ).

          DATA(window_compare) = cl_abap_tstmp=>compare(

                                   tstmp1 = current

                                   tstmp2 = window_end ).

          " Boundary is inclusive: current = window_end is still allowed.

          IF window_compare > 0.

            reason = skipped-retry_window_blocked.

            RETURN.

          ENDIF.

          IF row-next_attempt_at IS NOT INITIAL.

            DATA(due_window_compare) = cl_abap_tstmp=>compare(

                                         tstmp1 = row-next_attempt_at

                                         tstmp2 = window_end ).

            " A candidate whose persisted due time lies beyond the 15-minute

            " retry window is blocked even before that due time arrives.

            IF due_window_compare > 0.

              reason = skipped-retry_window_blocked.

              RETURN.

            ENDIF.

          ENDIF.

        ENDIF.

        IF row-next_attempt_at IS NOT INITIAL.

          DATA(due_now_compare) = cl_abap_tstmp=>compare(

                                    tstmp1 = row-next_attempt_at

                                    tstmp2 = current ).

          IF due_now_compare > 0.

            reason = skipped-before_due.

            RETURN.

          ENDIF.

        ENDIF.

      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.

        " Persisted retry timing that cannot be compared safely must never

        " cause an automatic dispatch. Keep the intent for operator review.

        reason = skipped-retry_window_blocked.

    ENDTRY.

  ENDMETHOD.


  METHOD find_eligible.

    DATA(current) = now( ).

    " Read every potentially claimable row in creation order and evaluate the

    " durable retry predicates in ABAP. UP TO 1 is intentionally forbidden here:

    " one old blocked PENDING row must not starve a later eligible row.

    SELECT delivery_uuid,

           dispatch_state,

           lease_expires_at,

           attempt_count,

           next_attempt_at,

           retry_window_started_at

      FROM zjp_po_dlv

      WHERE dispatch_state = @state-pending

         OR ( dispatch_state = @state-in_flight AND lease_expires_at <= @current )

      ORDER BY created_at

      INTO TABLE @DATA(candidates).

    LOOP AT candidates INTO DATA(candidate).

      IF candidate-dispatch_state = state-pending.

        DATA(candidate_row) = VALUE ty_intent_row(

          delivery_uuid             = candidate-delivery_uuid

          dispatch_state            = candidate-dispatch_state

          lease_expires_at          = candidate-lease_expires_at

          attempt_count             = candidate-attempt_count

          next_attempt_at           = candidate-next_attempt_at

          retry_window_started_at   = candidate-retry_window_started_at ).

        IF pending_skip_reason( row     = candidate_row

                                current = current ) IS INITIAL.

          delivery_uuid = candidate-delivery_uuid.

          RETURN.

        ENDIF.

      ELSEIF candidate-dispatch_state = state-in_flight.

        " The WHERE clause already proved the lease expired. Recovery preserves

        " the Phase 5/7.3 behavior, but may not evade the durable four-attempt

        " budget. Due/window predicates belong to PENDING scheduling, not to a

        " stale IN_FLIGHT recovery.

        IF candidate-attempt_count < 4.

          delivery_uuid = candidate-delivery_uuid.

          RETURN.

        ENDIF.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  METHOD read_intent.

    found = abap_false.

    CLEAR row.

    SELECT SINGLE delivery_uuid,

                  purchase_order_uuid,

                  order_revision,

                  dispatch_state,

                  lease_owner,

                  lease_expires_at,

                  payload_snapshot,

                  attempt_count,

                  next_attempt_at,

                  retry_window_started_at

      FROM zjp_po_dlv

      WHERE delivery_uuid = @delivery_uuid

      INTO CORRESPONDING FIELDS OF @row.

    found = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD classify.

    " Answered status always wins. Certainty is meaningful only when no HTTP

    " response exists. Initial, unknown or future certainty values are therefore

    " conservative MAY_APPLY / UNKNOWN.

    IF response-answered = abap_false.

      IF response-certainty =

           zjp_if_outbound_transport=>co_certainty_not_sent.

        final_state = state-pending.

      ELSE.

        final_state = state-unknown.

      ENDIF.

      RETURN.

    ENDIF.

    " Frozen Phase 7.4 table: every answered 2xx is success.

    IF response-status >= 200 AND response-status <= 299.

      final_state = state-delivered.

      RETURN.

    ENDIF.

    CASE response-status.

      WHEN 400 OR 401 OR 403 OR 404 OR 409 OR 412 OR 413.

        final_state = state-failed.

      WHEN 429 OR 502 OR 503.

        final_state = state-pending.

      WHEN 500 OR 504.

        final_state = state-unknown.

      WHEN OTHERS.

        IF response-status >= 500.

          final_state = state-unknown.

        ELSE.

          final_state = state-failed.

        ENDIF.

    ENDCASE.

  ENDMETHOD.


  METHOD business_status_for.

    " The domain model's transition table, and nothing invented:

    "   APPROVED + positive receipt            -> SENT

    "   APPROVED + definite failure or timeout -> ERROR

    " A retryable PENDING is neither, so the order stays where it is.

    CASE final_state.

      WHEN state-delivered.

        status = 'SENT'.

      WHEN state-failed OR state-unknown.

        status = 'ERROR'.

      WHEN OTHERS.

        CLEAR status.

    ENDCASE.

  ENDMETHOD.


  METHOD read_receipt.

    success = abap_false.

    CLEAR receipt.

    TRY.

        " Same order as the snapshot reader, and for the same compiler reason:

        " WRITE_TO has NO RETURNING parameter on this target and is TERMINAL, so

        " it cannot sit inside an expression chain. FROM_STRING -> APPLY -> WRITE_TO.

        DATA(json_data) = xco_cp_json=>data->from_string( body ).

        DATA(transformed_data) = json_data->apply(

          VALUE #( ( xco_cp_json=>transformation->camel_case_to_underscore ) ) ).

        transformed_data->write_to( REF #( receipt ) ).

        success = abap_true.

      CATCH cx_root.

        CLEAR receipt.

    ENDTRY.

  ENDMETHOD.


  METHOD claim.

    " ============ TRANSACTION A ============

    success = abap_false.

    DATA row TYPE ty_intent_row.

    IF read_intent( EXPORTING delivery_uuid = delivery_uuid

                    IMPORTING row           = row ) = abap_false.

      outcome-skip_reason = skipped-not_found.

      RETURN.

    ENDIF.

    outcome-delivery_uuid       = row-delivery_uuid.

    outcome-purchase_order_uuid = row-purchase_order_uuid.

    outcome-order_revision      = row-order_revision.

    DATA(current) = now( ).

    " Enforce the same durable policy here as in find_eligible. This duplicate

    " enforcement is intentional: run_once( uuid ) bypasses find_eligible.

    CASE row-dispatch_state.

      WHEN state-pending.

        DATA(pending_reason) = pending_skip_reason(

                                 row     = row

                                 current = current ).

        IF pending_reason IS NOT INITIAL.

          outcome-skip_reason = pending_reason.

          RETURN.

        ENDIF.

      WHEN state-in_flight.

        IF row-lease_expires_at > current.

          outcome-skip_reason = skipped-lease_live.

          RETURN.

        ENDIF.

        " An expired lease may be reclaimed, but never above the durable budget.

        IF row-attempt_count >= 4.

          outcome-skip_reason = skipped-retry_exhausted.

          RETURN.

        ENDIF.

      WHEN OTHERS.

        outcome-skip_reason = skipped-state_final.

        RETURN.

    ENDCASE.

    " P16, SAP-verified: CL_ABAP_TSTMP=>ADD on a short timestamp, whose result

    " assigns directly to lease_expires_at. The fractional seconds are lost and

    " that loss is accepted for lease semantics - a lease is a coarse deadline.

    DATA(expiry) = cl_abap_tstmp=>add( tstmp = CONV timestamp( current )

                                       secs  = lease_seconds ).

    " Every immutable field is absent from this UPDATE by construction:

    " PayloadSnapshot, PayloadHash, ApprovedBy, ApprovedAt, DeliveryUUID,

    " PurchaseOrderUUID and OrderRevision are not listed and cannot be written.

    MODIFY ENTITIES OF ZJP_I_DeliveryIntent

      ENTITY DeliveryIntent

        UPDATE FIELDS ( DispatchState LeaseOwner LeaseExpiresAt )

        WITH VALUE #( ( DeliveryUUID   = row-delivery_uuid

                        DispatchState  = state-in_flight

                        LeaseOwner     = run_uuid

                        LeaseExpiresAt = expiry ) )

      FAILED DATA(claim_failed)

      REPORTED DATA(claim_reported).

    IF claim_failed IS NOT INITIAL.

      ROLLBACK ENTITIES.

      outcome-skip_reason = skipped-claim_failed.

      outcome-error_text  = 'The lease claim was refused by the framework.'.

      RETURN.

    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_DeliveryIntent

      FAILED DATA(commit_failed)

      REPORTED DATA(commit_reported).

    IF sy-subrc <> 0 OR commit_failed IS NOT INITIAL.

      ROLLBACK ENTITIES.

      outcome-skip_reason = skipped-claim_failed.

      outcome-error_text  = 'The lease claim could not be committed.'.

      RETURN.

    ENDIF.

    " Post-commit ownership check. RAP's instance lock serialises two genuinely

    " simultaneous LUWs, but it is released at commit, so a race decided in the

    " microseconds between the read and the write would leave the loser believing

    " it holds the lease. Re-reading the committed row is what makes the loss

    " visible instead of silent, and a loser must not dispatch.

    DATA verify TYPE ty_intent_row.

    IF read_intent( EXPORTING delivery_uuid = row-delivery_uuid

                    IMPORTING row           = verify ) = abap_false

       OR verify-lease_owner <> run_uuid.

      outcome-skip_reason = skipped-claim_lost.

      RETURN.

    ENDIF.

    outcome-claimed          = abap_true.

    outcome-run_uuid         = run_uuid.

    outcome-lease_expires_at = verify-lease_expires_at.

    CLEAR outcome-skip_reason.

    success = abap_true.

  ENDMETHOD.


  METHOD record.

    " ============ TRANSACTION B ============

    success = abap_false.

    " The intent first. The lease is always cleared, whatever the outcome: a

    " terminal or returned intent that still advertises an owner and a future

    " expiry would block the next run for no reason.

    MODIFY ENTITIES OF ZJP_I_DeliveryIntent

      ENTITY DeliveryIntent

        UPDATE FIELDS ( DispatchState LastCorrelationId PortalOrderUUID

                        AttemptCount NextAttemptAt RetryWindowStartedAt

                        LeaseOwner LeaseExpiresAt )

        WITH VALUE #( ( DeliveryUUID          = row-delivery_uuid

                        DispatchState         = outcome-final_state

                        LastCorrelationId     = outcome-correlation_uuid

                        PortalOrderUUID       = outcome-portal_order_uuid

                        AttemptCount          = outcome-attempt_count

                        NextAttemptAt         = outcome-next_attempt_at

                        RetryWindowStartedAt  = outcome-retry_window_started_at

                        LeaseOwner            = VALUE sysuuid_x16( )

                        LeaseExpiresAt        = VALUE zjp_po_dlv-lease_expires_at( ) ) )

      FAILED DATA(intent_failed)

      REPORTED DATA(intent_reported).

    IF intent_failed IS NOT INITIAL.

      ROLLBACK ENTITIES.

      outcome-error_code = 'INTENT_RESULT_NOT_WRITTEN'.

      outcome-error_text = 'The delivery outcome could not be written to the intent.'.

      RETURN.

    ENDIF.

    " Then the PurchaseOrder, through the RAP action - never by SQL, and never

    " by an external EML update, because every one of these header fields is

    " declared `field ( readonly )` and only a handler in local mode may write

    " them. Both writes are in ONE LUW and commit together below.

    " The key comes from a READ rather than being assembled by hand. Reading the

    " order for its transactional key is not the same thing as reading it for a

    " payload - the payload still comes only from the persisted snapshot - and it

    " reuses the %tky shape every other EML consumer in this project uses.

    READ ENTITIES OF ZJP_I_PurchaseOrder

      ENTITY PurchaseOrder

        FIELDS ( PurchaseOrderUUID )

        WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off

                        PurchaseOrderUUID = row-purchase_order_uuid ) )

        RESULT DATA(orders)

      FAILED DATA(order_read_failed).

    IF order_read_failed IS NOT INITIAL OR lines( orders ) <> 1.

      ROLLBACK ENTITIES.

      outcome-error_code = 'ORDER_NOT_READABLE'.

      outcome-error_text = 'The order behind the intent could not be read.'.

      RETURN.

    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder

      ENTITY PurchaseOrder

        EXECUTE recordDeliveryResult

        FROM VALUE #( ( %tky                     = orders[ 1 ]-%tky

                        %param-DeliveryUUID      = row-delivery_uuid

                        %param-OrderRevision     = row-order_revision

                        %param-IntegrationStatus = outcome-final_state

                        %param-CorrelationId     = outcome-correlation_uuid

                        %param-ErrorCode         = outcome-error_code

                        %param-ErrorMessage      = outcome-error_text ) )

      FAILED DATA(order_failed)

      REPORTED DATA(order_reported).

    IF order_failed IS NOT INITIAL.

      ROLLBACK ENTITIES.

      outcome-error_code = 'ORDER_RESULT_NOT_RECORDED'.

      outcome-error_text = 'recordDeliveryResult refused the delivery outcome.'.

      RETURN.

    ENDIF.

    " One commit for both business objects. COMMIT ENTITIES commits the whole

    " LUW; the RESPONSE OF clause only chooses whose failures are surfaced.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder

      FAILED DATA(commit_failed)

      REPORTED DATA(commit_reported).

    IF sy-subrc <> 0 OR commit_failed IS NOT INITIAL.

      ROLLBACK ENTITIES.

      outcome-error_code = 'RESULT_COMMIT_FAILED'.

      outcome-error_text = 'The delivery outcome could not be committed.'.

      RETURN.

    ENDIF.

    outcome-recorded = abap_true.

    success = abap_true.

  ENDMETHOD.


  METHOD run_once.

    DATA(target) = delivery_uuid.

    IF target IS INITIAL.

      target = find_eligible( ).

      IF target IS INITIAL.

        outcome-skip_reason = skipped-none_eligible.

        RETURN.

      ENDIF.

    ENDIF.

    " ---------- TRANSACTION A ----------

    IF claim( EXPORTING delivery_uuid = target

              CHANGING  outcome       = outcome ) = abap_false.

      RETURN.

    ENDIF.

    " Re-read AFTER the claim commit, so the snapshot that goes on the wire is

    " the committed one rather than anything held across the boundary.

    DATA row TYPE ty_intent_row.

    IF read_intent( EXPORTING delivery_uuid = target

                    IMPORTING row           = row ) = abap_false.

      outcome-final_state = state-failed.

      outcome-error_code  = 'INTENT_VANISHED'.

      outcome-error_text  = 'The claimed intent could not be re-read.'.

      record( EXPORTING row = row CHANGING outcome = outcome ).

      RETURN.

    ENDIF.

    " Phase 7.3. Carry the persisted count forward the moment the row is known,

    " so every path that reaches transaction B from here writes back what is

    " already there. Only a run that actually posts adds to it, below. This is

    " deliberately BEFORE the EMPTY_SNAPSHOT branch: that branch sends nothing

    " and must not disturb the count.

    outcome-attempt_count = row-attempt_count.

    " ---------- NETWORK ----------

    " No database work from here until transaction B.

    "

    " PHASE 6.4b CUTOVER. The persisted snapshot now goes on the wire VERBATIM.

    "

    " Until 6.4a this section reconstructed a DTO with ZJP_CL_DLV_SNAPSHOT_READER

    " and re-shaped it into the CAP contract with ZJP_CL_CAP_ORDER_MAPPER. Both

    " still exist, are unchanged, and remain SAP runtime-verified - they are the

    " Phase 5 fallback and the mapping-parity reference, and ZJP_CL_PO_DISPATCH_TEST

    " test D still exercises them directly. They are simply no longer on this path.

    "

    " This is ADR-032's two-hop split paying off rather than a shortcut. The

    " snapshot was deliberately frozen as the SOURCE ORDER DELIVERY in SAP-native

    " values, precisely so that it would outlive the endpoint; Cloud Integration

    " now owns the mapping hop that Phase 5 had to perform here. The snapshot's

    " member set is the CI source contract, so no adaptation is correct here -

    " and any adaptation would be a second, divergent mapping of a payload whose

    " whole purpose is to be immutable.

    "

    " DO NOT deserialize and re-serialize the snapshot "to be safe". A round trip

    " through the reader and ZJP_CL_DLV_SNAPSHOT_JSON is byte-identical today, so

    " it would buy nothing, and it would put a transformation back in the path

    " that could drift from the bytes whose SHA-256 was recorded with the

    " approval. What was approved is what is sent.

    " Nothing was sent, so nothing can have been delivered. An intent with no

    " snapshot will not grow one on a retry, so this is FAILED rather than

    " UNKNOWN - the same reasoning the reader's failure branch used before the

    " cutover, kept because removing the reader must not silently turn a

    " definite non-delivery into an ambiguous one.

    IF row-payload_snapshot IS INITIAL.

      outcome-final_state     = state-failed.

      outcome-error_code      = 'EMPTY_SNAPSHOT'.

      outcome-error_text      = 'The persisted PayloadSnapshot is empty; nothing was sent.'.

      outcome-business_status = business_status_for( outcome-final_state ).

      record( EXPORTING row = row CHANGING outcome = outcome ).

      RETURN.

    ENDIF.

    " A FRESH correlation id for THIS attempt. The delivery identity is

    " untouched: "a retry may get a new correlation ID while preserving the

    " business delivery ID". Unchanged by the cutover - CI propagates this value

    " and mints nothing, so attempt identity still belongs to this coordinator.

    outcome-correlation_uuid = cl_system_uuid=>create_uuid_x16_static( ).

    " The mapper used to own every wire concern, so with it off the path the

    " route and the content type move here, to the one object that now knows

    " where a delivery is sent. The destination still owns host, port, TLS and

    " OAuth and carries NO path, exactly as P15 settled in Phase 5.2e, so the

    " seam and the transport adapter needed no change at all for this cutover.

    "

    " NO Idempotency-Key. Phase 6.3 proved CAP deduplicates on the deliveryId in

    " the BODY - integration-service.cds calls it the "Idempotency-Key

    " equivalent" - and that CI never sends the header. Adding one here would

    " ship a header nothing reads.

    DATA request TYPE zjp_if_outbound_transport=>ty_request.

    request-path = ci_delivery_path.

    request-body = row-payload_snapshot.

    request-headers = VALUE #(

      ( name = 'Content-Type'     value = content_type )

      ( name = 'X-Correlation-ID' value = uuid_text( outcome-correlation_uuid ) ) ).

    outcome-dispatched = abap_true.

    DATA(response) = transport->post( request ).

    " Completion time, not claim time, anchors the next deferred attempt. Tests

    " may pin now() through the optional policy_timestamp constructor seam.

    DATA(completed_at) = now( ).

    " One durable count increment per transport post() invocation. A NOT_SENT

    " result still consumed one automatic attempt; rows skipped before post() do

    " not change the count.

    outcome-attempt_count = row-attempt_count + 1.

    outcome-answered    = response-answered.

    outcome-http_status = response-status.

    outcome-final_state = classify( response ).

    " Terminal and ambiguous outcomes clear retry timing. Only a transient

    " PENDING result creates/preserves the durable retry-cycle fields.

    CLEAR outcome-next_attempt_at.

    CLEAR outcome-retry_window_started_at.

    IF outcome-final_state = state-pending.

      DATA(retry_timing) = calculate_retry_timing(

                             row           = row

                             current       = completed_at

                             attempt_count = outcome-attempt_count ).

      outcome-next_attempt_at = retry_timing-next_attempt_at.

      outcome-retry_window_started_at =

        retry_timing-retry_window_started_at.

      " For attempts 1..3 the normal due time must exist. If timestamp policy

      " arithmetic unexpectedly fails, stop automatic replay conservatively.

      IF outcome-attempt_count < 4

         AND outcome-next_attempt_at IS INITIAL.

        outcome-final_state = state-unknown.

        CLEAR outcome-next_attempt_at.

        CLEAR outcome-retry_window_started_at.

        outcome-error_code = 'RETRY_TIMING_FAILED'.

        outcome-error_text =

          'Retry timing could not be calculated; automatic retry was stopped.'.

      ELSEIF outcome-attempt_count < 4

         AND response-answered = abap_true

         AND ( response-status = 429

            OR response-status = 502

            OR response-status = 503 )

         AND response-retry_after IS NOT INITIAL.

        " Retry-After may postpone the normal due time, never accelerate it.

        " Malformed, overflowing, past or earlier values are simply ignored.

        DATA(header_due) = retry_after_due(

                             raw_value = response-retry_after

                             current   = completed_at ).

        IF header_due IS NOT INITIAL.

          TRY.

              DATA(header_compare) = cl_abap_tstmp=>compare(

                                       tstmp1 = header_due

                                       tstmp2 = outcome-next_attempt_at ).

              IF header_compare > 0.

                outcome-next_attempt_at = header_due.

              ENDIF.

            CATCH cx_parameter_invalid_range cx_parameter_invalid_type.

              " Optional Retry-After evidence must never weaken the normal delay.

          ENDTRY.

        ENDIF.

      ENDIF.

    ENDIF.

    IF outcome-final_state = state-delivered.

      " The receipt carries the portalOrderId, which lives on the INTENT rather

      " than on the header: a receipt is the outcome of one delivery, not a

      " property of an order that may be delivered again at a later revision.

      DATA receipt TYPE ty_receipt.

      IF read_receipt( EXPORTING body    = response-body

                       IMPORTING receipt = receipt ) = abap_true

         AND receipt-portal_order_id IS NOT INITIAL.

        " ===================================================================

        " THE CAP UUID BOUNDARY. THIS IS NOT DEBUG CODE. DO NOT SIMPLIFY IT.

        " ===================================================================

        " CAP/Node returns portalOrderId as a LOWERCASE canonical UUID, e.g.

        " 93933dd0-aad3-49ff-bc92-... On this SAP target,

        " CL_SYSTEM_UUID=>CONVERT_UUID_C36_STATIC accepts that lowercase input,

        " RAISES NOTHING, and returns a SILENTLY TRUNCATED X16: the observed

        " result was 93933000000000000000000000000000, the conversion having

        " effectively stopped at the first lowercase hex letter.

        "

        " A run therefore reached HTTP 201 and persisted a corrupt receipt

        " identity while every status code and every exception handler said the

        " delivery had succeeded. Debugging proved the CAP body and the XCO

        " binding were both correct and that the damage happened only in this

        " conversion.

        "

        " Two defences, and both are required. TRANSLATE TO UPPER CASE fixes the

        " cause. The X16 -> C36 round trip is the belt to that braces: this API

        " has already demonstrated that it will return a wrong answer without an

        " exception, so "it did not dump" is not evidence that it worked. If the

        " value does not survive a round trip it is discarded rather than stored,

        " because an absent receipt identity is recoverable and a wrong one is a

        " lie the rest of the system would believe.

        DATA uuid_c36   TYPE sysuuid_c36.

        DATA uuid_check TYPE sysuuid_c36.

        uuid_c36 = receipt-portal_order_id.

        TRANSLATE uuid_c36 TO UPPER CASE.

        TRY.

            cl_system_uuid=>convert_uuid_c36_static(

              EXPORTING uuid     = uuid_c36

              IMPORTING uuid_x16 = outcome-portal_order_uuid ).

            " Defensive round-trip: do not trust a successful return alone.

            cl_system_uuid=>convert_uuid_x16_static(

              EXPORTING uuid     = outcome-portal_order_uuid

              IMPORTING uuid_c36 = uuid_check ).

            IF uuid_check <> uuid_c36.

              CLEAR outcome-portal_order_uuid.

            ENDIF.

          CATCH cx_root.

            CLEAR outcome-portal_order_uuid.

        ENDTRY.

      ENDIF.

    ELSE.

      " Failure evidence, from the transport's own fields. No stack, no URL.

      " A policy-internal safety error already set above is preserved.

      IF outcome-error_code IS INITIAL.

        outcome-error_code = |HTTP_{ response-status }|.

        IF response-answered = abap_false.

          outcome-error_code = 'NO_ANSWER'.

          outcome-error_text = response-failure_text.

        ELSE.

          outcome-error_text = response-body.

        ENDIF.

      ENDIF.

    ENDIF.

    outcome-business_status = business_status_for( outcome-final_state ).

    " ---------- TRANSACTION B ----------

    record( EXPORTING row = row CHANGING outcome = outcome ).

  ENDMETHOD.

ENDCLASS.