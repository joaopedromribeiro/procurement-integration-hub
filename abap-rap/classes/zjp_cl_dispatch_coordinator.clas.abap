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
" IT NEVER RETRIES A FAILURE BY ITSELF. Only PENDING intents and stale IN_FLIGHT
" leases are eligible. Returning a FAILED or UNKNOWN intent to PENDING is
" sendToSupplier's explicit, operator-requested job, and 6.4's "never a blind
" retry" is addressed to this class specifically.
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
        claim_lost     TYPE string VALUE 'CLAIM_LOST_TO_OTHER_RUN',
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

        " Was a request actually put on the wire?
        dispatched          TYPE abap_bool,
        answered            TYPE abap_bool,
        http_status         TYPE i,

        " Phase 7.3. Durable count of real outbound transport attempts.
        " Incremented only when this run actually dispatched the request.
        attempt_count       TYPE i,

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
      IMPORTING transport     TYPE REF TO zjp_if_outbound_transport
                lease_seconds TYPE i
                run_uuid      TYPE sysuuid_x16 OPTIONAL.

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

    DATA transport     TYPE REF TO zjp_if_outbound_transport.
    DATA lease_seconds TYPE i.
    DATA run_uuid      TYPE sysuuid_x16.

    TYPES:
      BEGIN OF ty_intent_row,
        delivery_uuid       TYPE zjp_po_dlv-delivery_uuid,
        purchase_order_uuid TYPE zjp_po_dlv-purchase_order_uuid,
        order_revision      TYPE zjp_po_dlv-order_revision,
        dispatch_state      TYPE zjp_po_dlv-dispatch_state,
        lease_owner         TYPE zjp_po_dlv-lease_owner,
        lease_expires_at    TYPE zjp_po_dlv-lease_expires_at,
        payload_snapshot    TYPE zjp_po_dlv-payload_snapshot,
        attempt_count       TYPE zjp_po_dlv-attempt_count,
      END OF ty_intent_row.

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


  METHOD find_eligible.

    DATA(current) = now( ).

    " Two eligible shapes and no others. FAILED and UNKNOWN are deliberately
    " absent: returning them to PENDING is sendToSupplier's explicit job, so a
    " coordinator run can never resurrect a failure on its own.
    SELECT delivery_uuid
      FROM zjp_po_dlv
      WHERE dispatch_state = @state-pending
         OR ( dispatch_state = @state-in_flight AND lease_expires_at <= @current )
      ORDER BY created_at
      INTO TABLE @DATA(candidates)
      UP TO 1 ROWS.

    IF lines( candidates ) = 1.
      delivery_uuid = candidates[ 1 ]-delivery_uuid.
    ENDIF.

  ENDMETHOD.


  METHOD read_intent.

    found = abap_false.
    CLEAR row.

    SELECT SINGLE delivery_uuid, purchase_order_uuid, order_revision,
                  dispatch_state, lease_owner, lease_expires_at, payload_snapshot,
                  attempt_count
      FROM zjp_po_dlv
      WHERE delivery_uuid = @delivery_uuid
      INTO CORRESPONDING FIELDS OF @row.

    found = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD classify.

    " Section 6.4, applied to the transport's OWN fields rather than to a
    " flattened "did it work" flag. `answered` and `status` mean different
    " things and collapsing them is how a system mints a second delivery for an
    " order CAP already committed.
    IF response-answered = abap_false.
      " A timeout never proves non-delivery. Replay the SAME deliveryId.
      final_state = state-unknown.
      RETURN.
    ENDIF.

    CASE response-status.

        " 201 first delivery, 200 idempotent replay returning the stored
        " original receipt. Phase 4.3 verified both, and 6.4 gives them
        " identical handling - that is what makes a replay safe.
      WHEN 201 OR 200.
        final_state = state-delivered.

        " 409 is a payload collision and is NOT success. Either content changed
        " under one deliveryId or the source order was already ingested under a
        " different one; both are reconciliation, never a blind retry.
      WHEN 400 OR 401 OR 403 OR 409 OR 413.
        final_state = state-failed.

        " Retryable congestion. The intent goes back to PENDING so a later run
        " may pick it up; the business status is not touched. A bounded retry
        " budget needs attempt_count, which 4.6 defers to retryDelivery.
      WHEN 429 OR 502 OR 503.
        final_state = state-pending.

        " Ambiguous: the server may have committed before failing.
      WHEN 500.
        final_state = state-unknown.

      WHEN OTHERS.
        " Not in the table. Split by class rather than guessed: a 5xx may have
        " been delivered, so it is UNKNOWN and replays; anything else was
        " answered with a refusal and is FAILED.
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

    " Eligibility, exactly as the lease contract states it.
    CASE row-dispatch_state.

      WHEN state-pending.
        " Claimable.

      WHEN state-in_flight.
        IF row-lease_expires_at > current.
          " A LIVE lease. Another run owns this intent; leave it completely
          " untouched. This is the only protection that works across separate
          " LUWs, because no database lock survives the first run's commit.
          outcome-skip_reason = skipped-lease_live.
          RETURN.
        ENDIF.
        " Otherwise the lease has expired: the owner died or stalled, and this
        " run may reclaim it. The delivery identity is unchanged, so a reclaim
        " replays the same deliveryId rather than minting a new one.

      WHEN OTHERS.
        " DELIVERED is never claimed. FAILED and UNKNOWN are not claimed either:
        " only sendToSupplier may return them to PENDING.
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
                        AttemptCount LeaseOwner LeaseExpiresAt )
        WITH VALUE #( ( DeliveryUUID      = row-delivery_uuid
                        DispatchState     = outcome-final_state
                        LastCorrelationId = outcome-correlation_uuid
                        PortalOrderUUID   = outcome-portal_order_uuid
                        AttemptCount      = outcome-attempt_count
                        LeaseOwner        = VALUE sysuuid_x16( )
                        LeaseExpiresAt    = VALUE zjp_po_dlv-lease_expires_at( ) ) )
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

    " Phase 7.3. One increment per request that actually went on the wire,
    " whatever came back - 2xx, a refusal, a retryable status, or no answer at
    " all. It is NOT a count of record() calls: the two paths above reach
    " transaction B without dispatching anything and leave the count alone.
    outcome-attempt_count = row-attempt_count + 1.

    outcome-answered    = response-answered.
    outcome-http_status = response-status.
    outcome-final_state = classify( response ).

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
      outcome-error_code = |HTTP_{ response-status }|.
      IF response-answered = abap_false.
        outcome-error_code = 'NO_ANSWER'.
        outcome-error_text = response-failure_text.
      ELSE.
        outcome-error_text = response-body.
      ENDIF.
    ENDIF.

    outcome-business_status = business_status_for( outcome-final_state ).

    " ---------- TRANSACTION B ----------
    record( EXPORTING row = row CHANGING outcome = outcome ).

  ENDMETHOD.

ENDCLASS.
