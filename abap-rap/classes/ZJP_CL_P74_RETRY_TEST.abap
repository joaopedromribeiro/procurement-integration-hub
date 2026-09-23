" Phase 7.4c-5a/5b-1 - network-free retry policy harness.
"
" IMPORTANT:
" - This class NEVER constructs ZJP_CL_OUTBOUND_TRANSPORT.
" - Every coordinator receives either ZJP_CL_TRANSPORT_FAKE or the network-free
"   ZJP_CL_P74_TRANSPORT_SCRIPT.
" - No HTTP request can leave the SAP system from this class.
" - The class DOES create and commit test PurchaseOrders and DeliveryIntents.
"
" Scope of 7.4c-5a:
" - immediate first attempt
" - 5 / 30 / 120 second base delays
" - pre-due skip and exact-due eligibility
" - four total attempts and no fifth attempt
" - maximum jitter boundaries 1 / 6 / 24 seconds
" - inclusive 15-minute retry-window boundary
" - blocked retry window
" - legacy PENDING rows with initial timing
" - NOT_SENT versus MAY_APPLY
" - answered Retry-After delta-seconds postponement
" - skipped runs do not increment AttemptCount
"
" 5b-1 adds scripted answered-status classification, certainty precedence,
" Retry-After edge cases, millisecond jitter, lease recovery and timing cleanup.
" Shared-table find_eligible starvation remains a separately isolated gate: this
" harness never mutates unrelated existing outbox rows merely to make ordering deterministic.

CLASS zjp_cl_p74_retry_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS lease_seconds TYPE i VALUE 300.

    DATA console TYPE REF TO if_oo_adt_classrun_out.

    TYPES:
      BEGIN OF ty_fixture,
        order_uuid    TYPE sysuuid_x16,
        delivery_uuid TYPE sysuuid_x16,
      END OF ty_fixture.

    TYPES:
      BEGIN OF ty_intent,
        delivery_uuid             TYPE zjp_po_dlv-delivery_uuid,
        dispatch_state            TYPE zjp_po_dlv-dispatch_state,
        payload_snapshot          TYPE zjp_po_dlv-payload_snapshot,
        payload_hash              TYPE zjp_po_dlv-payload_hash,
        approved_by               TYPE zjp_po_dlv-approved_by,
        approved_at               TYPE zjp_po_dlv-approved_at,
        last_correlation_id       TYPE zjp_po_dlv-last_correlation_id,
        lease_owner               TYPE zjp_po_dlv-lease_owner,
        lease_expires_at          TYPE zjp_po_dlv-lease_expires_at,
        attempt_count             TYPE zjp_po_dlv-attempt_count,
        next_attempt_at           TYPE zjp_po_dlv-next_attempt_at,
        retry_window_started_at   TYPE zjp_po_dlv-retry_window_started_at,
      END OF ty_intent.

    TYPES ty_seconds TYPE p LENGTH 8 DECIMALS 3.

    TYPES:
      BEGIN OF ty_header,
        status             TYPE zjp_po_h-status,
        integration_status TYPE zjp_po_h-integration_status,
      END OF ty_header.

    METHODS stop
      IMPORTING text TYPE string.

    METHODS save_all
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS make_fixture
      IMPORTING supplier       TYPE zjp_po_h-supplier
      RETURNING VALUE(fixture) TYPE ty_fixture.

    METHODS intent_row
      IMPORTING delivery_uuid TYPE sysuuid_x16
      RETURNING VALUE(row)    TYPE ty_intent.

    METHODS header_row
      IMPORTING order_uuid TYPE sysuuid_x16
      RETURNING VALUE(row) TYPE ty_header.

    METHODS force_policy
      IMPORTING delivery_uuid          TYPE sysuuid_x16
                attempt_count          TYPE i
                next_attempt_at        TYPE zjp_po_dlv-next_attempt_at
                retry_window_started_at TYPE zjp_po_dlv-retry_window_started_at
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS add_seconds
      IMPORTING base          TYPE timestampl
                seconds       TYPE ty_seconds
      RETURNING VALUE(result) TYPE zjp_po_dlv-next_attempt_at.

    METHODS same_immutable_evidence
      IMPORTING before        TYPE ty_intent
                after         TYPE ty_intent
      RETURNING VALUE(same)   TYPE abap_bool.

    METHODS test_base_schedule
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_max_jitter
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_retry_window
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_legacy_initial_timing
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_certainty
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_retry_after_delta
      RETURNING VALUE(success) TYPE abap_bool.


    " Phase 7.4c-5b-1 deterministic scripted-transport coverage.
    METHODS success_body
      RETURNING VALUE(body) TYPE string.

    METHODS run_script_case
      IMPORTING response        TYPE zjp_if_outbound_transport=>ty_response
                expected_state  TYPE string
                test_time       TYPE timestampl
                expected_due    TYPE zjp_po_dlv-next_attempt_at
                expected_anchor TYPE zjp_po_dlv-retry_window_started_at
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS force_in_flight
      IMPORTING delivery_uuid           TYPE sysuuid_x16
                attempt_count           TYPE i
                lease_owner             TYPE sysuuid_x16
                lease_expires_at        TYPE zjp_po_dlv-lease_expires_at
                next_attempt_at         TYPE zjp_po_dlv-next_attempt_at
                retry_window_started_at TYPE zjp_po_dlv-retry_window_started_at
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_status_matrix
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_certainty_edges
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_retry_after_edges
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_jitter_precision
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_lease_edges
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_terminal_clears_timing
      RETURNING VALUE(success) TYPE abap_bool.

ENDCLASS.


CLASS zjp_cl_p74_retry_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    console = out.

    out->write( '=== Phase 7.4c-5a - network-free SAP retry policy ===' ).
    out->write( 'No real HTTP adapter is constructed by this class.' ).
    out->write( 'The run DOES create and commit test PurchaseOrders and DeliveryIntents.' ).
    out->write( '' ).

    IF test_base_schedule( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_max_jitter( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_retry_window( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_legacy_initial_timing( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_certainty( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_retry_after_delta( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( '' ).
    out->write( 'PASS: Phase 7.4c-5a network-free retry policy verified.' ).
    out->write( '' ).
    out->write( '=== Phase 7.4c-5b-1 - scripted transport edge coverage ===' ).

    IF test_status_matrix( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_certainty_edges( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_retry_after_edges( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_jitter_precision( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_lease_edges( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_terminal_clears_timing( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( '' ).
    out->write( 'PASS: Phase 7.4c-5b-1 deterministic network-free edge coverage verified.' ).
  ENDMETHOD.


  METHOD stop.
    console->write( |STOP: { text }| ).
  ENDMETHOD.


  METHOD save_all.
    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).

    DATA(save_subrc) = sy-subrc.

    success = xsdbool( save_subrc = 0 AND failed_save IS INITIAL ).

    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( name = 'COMMIT sy-subrc' data = save_subrc ).
      console->write( name = 'Save FAILED' data = failed_save ).
      stop( 'the test LUW could not be committed.' ).
    ENDIF.
  ENDMETHOD.


  METHOD make_fixture.
    CLEAR fixture.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid        = 'P74_ROOT'
                        Supplier    = supplier
                        CompanyCode = '1000'
                        Currency    = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'P74_ROOT'
          %target = VALUE #( ( %cid = 'P74_ITEM'
                               ItemNumber = '00010'
                               Material = 'MAT001'
                               Quantity = 2
                               UnitOfMeasure = 'EA'
                               NetPrice = '750.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_create)
      FAILED DATA(failed_create).

    IF failed_create IS NOT INITIAL
       OR NOT line_exists( mapped_create-purchaseorder[ %cid = 'P74_ROOT' ] ).
      ROLLBACK ENTITIES.
      stop( 'fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(order_uuid) =
      mapped_create-purchaseorder[ %cid = 'P74_ROOT' ]-PurchaseOrderUUID.

    IF save_all( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        FIELDS ( Status )
        WITH VALUE #( ( %is_draft = if_abap_behv=>mk-off
                        PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(orders)
      FAILED DATA(failed_read).

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1.
      stop( 'fixture could not be read after creation.' ).
      RETURN.
    ENDIF.

    DATA(order_key) = orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_submit).

    IF failed_submit IS NOT INITIAL OR save_all( ) = abap_false.
      ROLLBACK ENTITIES.
      stop( 'fixture could not be submitted.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_approve).

    IF failed_approve IS NOT INITIAL OR save_all( ) = abap_false.
      ROLLBACK ENTITIES.
      stop( 'fixture could not be approved.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE sendToSupplier FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_send).

    IF failed_send IS NOT INITIAL OR save_all( ) = abap_false.
      ROLLBACK ENTITIES.
      stop( 'sendToSupplier failed while creating the retry fixture.' ).
      RETURN.
    ENDIF.

    SELECT SINGLE delivery_uuid, dispatch_state, attempt_count,
                  next_attempt_at, retry_window_started_at
      FROM zjp_po_dlv
      WHERE purchase_order_uuid = @order_uuid
      INTO @DATA(created_intent).

    IF sy-subrc <> 0
       OR created_intent-dispatch_state <> 'PENDING'
       OR created_intent-attempt_count <> 0
       OR created_intent-next_attempt_at IS NOT INITIAL
       OR created_intent-retry_window_started_at IS NOT INITIAL.
      stop( 'new fixture does not have the expected PENDING / attempt 0 / initial timing state.' ).
      RETURN.
    ENDIF.

    fixture-order_uuid    = order_uuid.
    fixture-delivery_uuid = created_intent-delivery_uuid.
  ENDMETHOD.


  METHOD intent_row.
    SELECT SINGLE delivery_uuid,
                  dispatch_state,
                  payload_snapshot,
                  payload_hash,
                  approved_by,
                  approved_at,
                  last_correlation_id,
                  lease_owner,
                  lease_expires_at,
                  attempt_count,
                  next_attempt_at,
                  retry_window_started_at
      FROM zjp_po_dlv
      WHERE delivery_uuid = @delivery_uuid
      INTO CORRESPONDING FIELDS OF @row.
  ENDMETHOD.


  METHOD header_row.
    SELECT SINGLE status, integration_status
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO CORRESPONDING FIELDS OF @row.
  ENDMETHOD.


  METHOD force_policy.
    MODIFY ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        UPDATE FIELDS ( DispatchState AttemptCount NextAttemptAt
                        RetryWindowStartedAt LeaseOwner LeaseExpiresAt )
        WITH VALUE #( ( DeliveryUUID          = delivery_uuid
                        DispatchState         = 'PENDING'
                        AttemptCount          = attempt_count
                        NextAttemptAt         = next_attempt_at
                        RetryWindowStartedAt  = retry_window_started_at
                        LeaseOwner            = VALUE sysuuid_x16( )
                        LeaseExpiresAt        = VALUE zjp_po_dlv-lease_expires_at( ) ) )
      FAILED DATA(failed_force)
      REPORTED DATA(reported_force).

    IF failed_force IS NOT INITIAL.
      ROLLBACK ENTITIES.
      stop( 'test policy state could not be written through EML.' ).
      RETURN.
    ENDIF.

    success = save_all( ).
  ENDMETHOD.


  METHOD add_seconds.
    CLEAR result.

    TRY.
        result = cl_abap_tstmp=>add(
                   tstmp = base
                   secs  = seconds ).
      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.


  METHOD same_immutable_evidence.
    same = xsdbool(
      before-payload_snapshot = after-payload_snapshot
      AND before-payload_hash = after-payload_hash
      AND before-approved_by = after-approved_by
      AND before-approved_at = after-approved_at ).
  ENDMETHOD.


  METHOD test_base_schedule.
    success = abap_false.
    console->write( '--- 5a-1: base delays, due gating, four-attempt budget ---' ).

    DATA(fixture) = make_fixture( 'SUP074A' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(before) = intent_row( fixture-delivery_uuid ).
    DATA(t0) = CONV timestampl( '20200101120000.0000000' ).

    DATA retry_transport TYPE REF TO zjp_if_outbound_transport.
    retry_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-retryable ).

    DATA(worker_1) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t0 ).

    DATA(first) = worker_1->run_once( fixture-delivery_uuid ).
    DATA(row_1) = intent_row( fixture-delivery_uuid ).
    DATA(due_1) = add_seconds( base = t0 seconds = 5 ).

    IF first-final_state <> 'PENDING'
       OR row_1-attempt_count <> 1
       OR row_1-next_attempt_at <> due_1
       OR row_1-retry_window_started_at <> t0
       OR row_1-lease_owner IS NOT INITIAL
       OR row_1-lease_expires_at IS NOT INITIAL.
      console->write( name = 'Attempt 1 outcome' data = first ).
      console->write( name = 'Attempt 1 row' data = row_1 ).
      stop( 'attempt 1 did not persist PENDING + 5s + anchor + cleared lease.' ).
      RETURN.
    ENDIF.

    IF same_immutable_evidence( before = before after = row_1 ) = abap_false.
      stop( 'attempt 1 changed immutable delivery evidence.' ).
      RETURN.
    ENDIF.

    DATA(before_skip) = row_1.
    DATA(t_before_due) = add_seconds( base = t0 seconds = 4 ).

    DATA(worker_before_due) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t_before_due ).

    DATA(skipped) = worker_before_due->run_once( fixture-delivery_uuid ).
    DATA(after_skip) = intent_row( fixture-delivery_uuid ).

    IF skipped-claimed = abap_true
       OR skipped-dispatched = abap_true
       OR skipped-skip_reason <> zjp_cl_dispatch_coordinator=>skipped-before_due
       OR after_skip-attempt_count <> before_skip-attempt_count
       OR after_skip-next_attempt_at <> before_skip-next_attempt_at
       OR after_skip-retry_window_started_at <> before_skip-retry_window_started_at.
      console->write( name = 'Pre-due outcome' data = skipped ).
      stop( 'a pinned UUID bypassed BEFORE_DUE or changed durable retry state.' ).
      RETURN.
    ENDIF.

    DATA(worker_2) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = due_1 ).

    DATA(second) = worker_2->run_once( fixture-delivery_uuid ).
    DATA(row_2) = intent_row( fixture-delivery_uuid ).
    DATA(due_2) = add_seconds( base = due_1 seconds = 30 ).

    IF second-dispatched <> abap_true
       OR row_2-attempt_count <> 2
       OR row_2-next_attempt_at <> due_2
       OR row_2-retry_window_started_at <> t0.
      console->write( name = 'Attempt 2 outcome' data = second ).
      console->write( name = 'Attempt 2 row' data = row_2 ).
      stop( 'exact due time was not eligible or attempt 2 did not persist +30s.' ).
      RETURN.
    ENDIF.

    DATA(worker_3) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = due_2 ).

    DATA(third) = worker_3->run_once( fixture-delivery_uuid ).
    DATA(row_3) = intent_row( fixture-delivery_uuid ).
    DATA(due_3) = add_seconds( base = due_2 seconds = 120 ).

    IF row_3-attempt_count <> 3
       OR row_3-next_attempt_at <> due_3
       OR row_3-retry_window_started_at <> t0.
      console->write( name = 'Attempt 3 outcome' data = third ).
      console->write( name = 'Attempt 3 row' data = row_3 ).
      stop( 'attempt 3 did not persist +120s while preserving the original anchor.' ).
      RETURN.
    ENDIF.

    DATA(worker_4) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = due_3 ).

    DATA(fourth) = worker_4->run_once( fixture-delivery_uuid ).
    DATA(row_4) = intent_row( fixture-delivery_uuid ).

    IF row_4-dispatch_state <> 'PENDING'
       OR row_4-attempt_count <> 4
       OR row_4-next_attempt_at IS NOT INITIAL
       OR row_4-retry_window_started_at <> t0.
      console->write( name = 'Attempt 4 outcome' data = fourth ).
      console->write( name = 'Attempt 4 row' data = row_4 ).
      stop( 'attempt 4 did not exhaust the automatic budget with no fifth due time.' ).
      RETURN.
    ENDIF.

    DATA(after_fourth_time) = add_seconds( base = due_3 seconds = 1 ).
    DATA(worker_5) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = after_fourth_time ).

    DATA(fifth) = worker_5->run_once( fixture-delivery_uuid ).
    DATA(row_5) = intent_row( fixture-delivery_uuid ).

    IF fifth-claimed = abap_true
       OR fifth-dispatched = abap_true
       OR fifth-skip_reason <> zjp_cl_dispatch_coordinator=>skipped-retry_exhausted
       OR row_5-attempt_count <> 4.
      console->write( name = 'Fifth-run outcome' data = fifth ).
      stop( 'a fifth automatic transport attempt was allowed.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: base 5/30/120s, pre-due skip, exact-due, attempt 4 exhaustion, no fifth attempt.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_max_jitter.
    success = abap_false.
    console->write( '--- 5a-2: maximum positive jitter boundaries ---' ).

    DATA(fixture) = make_fixture( 'SUP074B' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(t0) = CONV timestampl( '20200101130000.0000000' ).

    DATA retry_transport TYPE REF TO zjp_if_outbound_transport.
    retry_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-retryable ).

    " A single very large override is clamped independently to the legal max of
    " each attempt: 1000ms, 6000ms, 24000ms.
    DATA(worker_1) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 24000
      policy_timestamp    = t0 ).

    DATA(out_1) = worker_1->run_once( fixture-delivery_uuid ).
    DATA(row_1) = intent_row( fixture-delivery_uuid ).
    DATA(due_1) = add_seconds( base = t0 seconds = 6 ).

    IF row_1-attempt_count <> 1 OR row_1-next_attempt_at <> due_1.
      console->write( name = 'Jitter attempt 1' data = row_1 ).
      stop( 'attempt 1 did not use the 1000ms maximum jitter boundary.' ).
      RETURN.
    ENDIF.

    DATA(worker_2) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 24000
      policy_timestamp    = due_1 ).

    DATA(out_2) = worker_2->run_once( fixture-delivery_uuid ).
    DATA(row_2) = intent_row( fixture-delivery_uuid ).
    DATA(due_2) = add_seconds( base = due_1 seconds = 36 ).

    IF row_2-attempt_count <> 2 OR row_2-next_attempt_at <> due_2.
      console->write( name = 'Jitter attempt 2' data = row_2 ).
      stop( 'attempt 2 did not use the 6000ms maximum jitter boundary.' ).
      RETURN.
    ENDIF.

    DATA(worker_3) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 24000
      policy_timestamp    = due_2 ).

    DATA(out_3) = worker_3->run_once( fixture-delivery_uuid ).
    DATA(row_3) = intent_row( fixture-delivery_uuid ).
    DATA(due_3) = add_seconds( base = due_2 seconds = 144 ).

    IF row_3-attempt_count <> 3 OR row_3-next_attempt_at <> due_3.
      console->write( name = 'Jitter attempt 3' data = row_3 ).
      stop( 'attempt 3 did not use the 24000ms maximum jitter boundary.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: maximum jitter boundaries are +1s, +6s and +24s and never shorten the base delay.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_retry_window.
    success = abap_false.
    console->write( '--- 5a-3: inclusive and blocked 15-minute retry window ---' ).

    DATA(t0) = CONV timestampl( '20200101140000.0000000' ).
    DATA(boundary) = add_seconds( base = t0 seconds = 900 ).

    " Inclusive boundary: now == anchor + 900 and due == boundary is allowed.
    DATA(fixture_ok) = make_fixture( 'SUP074C' ).
    IF fixture_ok-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    IF force_policy(
         delivery_uuid           = fixture_ok-delivery_uuid
         attempt_count           = 1
         next_attempt_at         = boundary
         retry_window_started_at = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA success_transport TYPE REF TO zjp_if_outbound_transport.
    success_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-created ).

    DATA(boundary_worker) = NEW zjp_cl_dispatch_coordinator(
      transport        = success_transport
      lease_seconds    = lease_seconds
      policy_timestamp = boundary ).

    DATA(boundary_outcome) = boundary_worker->run_once( fixture_ok-delivery_uuid ).

    IF boundary_outcome-dispatched <> abap_true
       OR boundary_outcome-final_state <> 'DELIVERED'.
      console->write( name = 'Boundary outcome' data = boundary_outcome ).
      stop( 'the exact 15-minute retry-window boundary was not inclusive.' ).
      RETURN.
    ENDIF.

    " A persisted due time beyond the window is blocked even before that due.
    DATA(fixture_due_blocked) = make_fixture( 'SUP074D' ).
    IF fixture_due_blocked-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(after_window_due) = add_seconds( base = t0 seconds = 901 ).
    IF force_policy(
         delivery_uuid           = fixture_due_blocked-delivery_uuid
         attempt_count           = 1
         next_attempt_at         = after_window_due
         retry_window_started_at = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(now_before_window_end) = add_seconds( base = t0 seconds = 100 ).
    DATA(blocked_worker_1) = NEW zjp_cl_dispatch_coordinator(
      transport        = success_transport
      lease_seconds    = lease_seconds
      policy_timestamp = now_before_window_end ).

    DATA(blocked_due_outcome) = blocked_worker_1->run_once(
                                  fixture_due_blocked-delivery_uuid ).
    DATA(blocked_due_row) = intent_row( fixture_due_blocked-delivery_uuid ).

    IF blocked_due_outcome-dispatched = abap_true
       OR blocked_due_outcome-skip_reason <>
            zjp_cl_dispatch_coordinator=>skipped-retry_window_blocked
       OR blocked_due_row-attempt_count <> 1.
      console->write( name = 'Due beyond window outcome' data = blocked_due_outcome ).
      stop( 'a due time beyond the retry window was not blocked.' ).
      RETURN.
    ENDIF.

    " Current time beyond the window is blocked even if due itself was inside it.
    DATA(fixture_now_blocked) = make_fixture( 'SUP074E' ).
    IF fixture_now_blocked-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(due_inside_window) = add_seconds( base = t0 seconds = 100 ).
    IF force_policy(
         delivery_uuid           = fixture_now_blocked-delivery_uuid
         attempt_count           = 1
         next_attempt_at         = due_inside_window
         retry_window_started_at = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(now_after_window) = add_seconds( base = t0 seconds = 901 ).
    DATA(blocked_worker_2) = NEW zjp_cl_dispatch_coordinator(
      transport        = success_transport
      lease_seconds    = lease_seconds
      policy_timestamp = now_after_window ).

    DATA(blocked_now_outcome) = blocked_worker_2->run_once(
                                  fixture_now_blocked-delivery_uuid ).
    DATA(blocked_now_row) = intent_row( fixture_now_blocked-delivery_uuid ).

    IF blocked_now_outcome-dispatched = abap_true
       OR blocked_now_outcome-skip_reason <>
            zjp_cl_dispatch_coordinator=>skipped-retry_window_blocked
       OR blocked_now_row-attempt_count <> 1.
      console->write( name = 'Now beyond window outcome' data = blocked_now_outcome ).
      stop( 'a retry cycle older than 15 minutes was not blocked.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: boundary inclusive; due beyond window and now beyond window are blocked without spending attempts.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_legacy_initial_timing.
    success = abap_false.
    console->write( '--- 5a-4: legacy PENDING row with initial timing ---' ).

    DATA(fixture) = make_fixture( 'SUP074F' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    IF force_policy(
         delivery_uuid           = fixture-delivery_uuid
         attempt_count           = 3
         next_attempt_at         = VALUE zjp_po_dlv-next_attempt_at( )
         retry_window_started_at = VALUE zjp_po_dlv-retry_window_started_at( ) ) = abap_false.
      RETURN.
    ENDIF.

    DATA(t0) = CONV timestampl( '20200101150000.0000000' ).

    DATA retry_transport TYPE REF TO zjp_if_outbound_transport.
    retry_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-retryable ).

    DATA(worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t0 ).

    DATA(outcome) = worker->run_once( fixture-delivery_uuid ).
    DATA(after) = intent_row( fixture-delivery_uuid ).

    IF outcome-dispatched <> abap_true
       OR after-attempt_count <> 4
       OR after-dispatch_state <> 'PENDING'
       OR after-next_attempt_at IS NOT INITIAL
       OR after-retry_window_started_at <> t0.
      console->write( name = 'Legacy outcome' data = outcome ).
      console->write( name = 'Legacy row' data = after ).
      stop( 'legacy initial timing did not allow one eligible attempt while preserving historical count.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: legacy count 3 + initial timing was immediately eligible once and became exhausted at count 4.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_certainty.
    success = abap_false.
    console->write( '--- 5a-5: NOT_SENT versus MAY_APPLY ---' ).

    DATA(t0) = CONV timestampl( '20200101160000.0000000' ).

    DATA(not_sent_fixture) = make_fixture( 'SUP074G' ).
    IF not_sent_fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA not_sent_transport TYPE REF TO zjp_if_outbound_transport.
    not_sent_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-not_sent ).

    DATA(not_sent_worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = not_sent_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t0 ).

    DATA(not_sent_outcome) = not_sent_worker->run_once(
                               not_sent_fixture-delivery_uuid ).
    DATA(not_sent_row) = intent_row( not_sent_fixture-delivery_uuid ).
    DATA(not_sent_header) = header_row( not_sent_fixture-order_uuid ).
    DATA(not_sent_due) = add_seconds( base = t0 seconds = 5 ).

    IF not_sent_outcome-final_state <> 'PENDING'
       OR not_sent_row-attempt_count <> 1
       OR not_sent_row-next_attempt_at <> not_sent_due
       OR not_sent_row-retry_window_started_at <> t0
       OR not_sent_header-status <> 'APPROVED'.
      console->write( name = 'NOT_SENT outcome' data = not_sent_outcome ).
      console->write( name = 'NOT_SENT row' data = not_sent_row ).
      stop( 'proven NOT_SENT was not treated as transient PENDING.' ).
      RETURN.
    ENDIF.

    DATA(may_apply_fixture) = make_fixture( 'SUP074H' ).
    IF may_apply_fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA may_apply_transport TYPE REF TO zjp_if_outbound_transport.
    may_apply_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-unanswered ).

    DATA(may_apply_worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = may_apply_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t0 ).

    DATA(may_apply_outcome) = may_apply_worker->run_once(
                                may_apply_fixture-delivery_uuid ).
    DATA(may_apply_row) = intent_row( may_apply_fixture-delivery_uuid ).
    DATA(may_apply_header) = header_row( may_apply_fixture-order_uuid ).

    IF may_apply_outcome-final_state <> 'UNKNOWN'
       OR may_apply_row-dispatch_state <> 'UNKNOWN'
       OR may_apply_row-attempt_count <> 1
       OR may_apply_row-next_attempt_at IS NOT INITIAL
       OR may_apply_row-retry_window_started_at IS NOT INITIAL
       OR may_apply_header-status <> 'ERROR'.
      console->write( name = 'MAY_APPLY outcome' data = may_apply_outcome ).
      console->write( name = 'MAY_APPLY row' data = may_apply_row ).
      stop( 'MAY_APPLY was not conservatively classified UNKNOWN with retry timing cleared.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: NOT_SENT -> PENDING; MAY_APPLY -> UNKNOWN; both consume exactly one transport attempt.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_retry_after_delta.
    success = abap_false.
    console->write( '--- 5a-6: answered Retry-After delta-seconds postpones but never accelerates ---' ).

    DATA(fixture) = make_fixture( 'SUP074I' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(t0) = CONV timestampl( '20200101170000.0000000' ).

    DATA retry_after_transport TYPE REF TO zjp_if_outbound_transport.
    retry_after_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-retry_after ).

    DATA(worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = retry_after_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t0 ).

    DATA(outcome) = worker->run_once( fixture-delivery_uuid ).
    DATA(after) = intent_row( fixture-delivery_uuid ).
    DATA(header_due) = add_seconds( base = t0 seconds = 120 ).

    IF outcome-final_state <> 'PENDING'
       OR outcome-http_status <> 503
       OR after-attempt_count <> 1
       OR after-next_attempt_at <> header_due
       OR after-retry_window_started_at <> t0.
      console->write( name = 'Retry-After outcome' data = outcome ).
      console->write( name = 'Retry-After row' data = after ).
      stop( 'Retry-After 120 did not postpone the normal +5s due time to +120s.' ).
      RETURN.
    ENDIF.

    DATA(before_due) = add_seconds( base = t0 seconds = 119 ).
    DATA(before_worker) = NEW zjp_cl_dispatch_coordinator(
      transport        = retry_after_transport
      lease_seconds    = lease_seconds
      policy_timestamp = before_due ).

    DATA(skipped) = before_worker->run_once( fixture-delivery_uuid ).
    DATA(after_skip) = intent_row( fixture-delivery_uuid ).

    IF skipped-dispatched = abap_true
       OR skipped-skip_reason <> zjp_cl_dispatch_coordinator=>skipped-before_due
       OR after_skip-attempt_count <> 1
       OR after_skip-next_attempt_at <> header_due.
      console->write( name = 'Retry-After pre-due outcome' data = skipped ).
      stop( 'Retry-After persisted due time was not enforced by pinned run_once.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: answered 503 Retry-After=120 postponed the due time and its pre-due guard spent no attempt.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD success_body.
    body = '{"deliveryId":"00000000-0000-0000-0000-000000000001",'
        && '"sourceOrderId":"00000000-0000-0000-0000-000000000002",'
        && '"portalOrderId":"11111111-1111-1111-1111-111111111111",'
        && '"status":"RECEIVED","receivedAt":"2020-01-01T00:00:00Z"}'.
  ENDMETHOD.


  METHOD run_script_case.
    success = abap_false.

    DATA(fixture) = make_fixture( 'SUP074A' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(scripted_response) = response.

    IF expected_state = 'DELIVERED'
       AND scripted_response-body IS INITIAL.
      scripted_response-body = success_body( ).
    ELSEIF scripted_response-answered = abap_true
       AND scripted_response-body IS INITIAL.
      scripted_response-body = '{"error":{"code":"SCRIPTED_TEST"}}'.
    ELSEIF scripted_response-answered = abap_false
       AND scripted_response-failure_text IS INITIAL.
      scripted_response-failure_text = 'scripted unanswered transport'.
    ENDIF.

    DATA(script) = NEW zjp_cl_p74_transport_script(
      scripted_response = scripted_response ).

    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = script.

    DATA(worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = test_time ).

    DATA(outcome) = worker->run_once( fixture-delivery_uuid ).
    DATA(after) = intent_row( fixture-delivery_uuid ).
    DATA(header) = header_row( fixture-order_uuid ).

    IF outcome-claimed <> abap_true
       OR outcome-dispatched <> abap_true
       OR script->get_post_count( ) <> 1
       OR outcome-answered <> scripted_response-answered
       OR outcome-http_status <> scripted_response-status
       OR outcome-final_state <> expected_state
       OR after-dispatch_state <> expected_state
       OR after-attempt_count <> 1
       OR after-next_attempt_at <> expected_due
       OR after-retry_window_started_at <> expected_anchor
       OR after-lease_owner IS NOT INITIAL
       OR after-lease_expires_at IS NOT INITIAL.
      console->write( name = 'Scripted response' data = scripted_response ).
      console->write( name = 'Scripted outcome' data = outcome ).
      console->write( name = 'Scripted row' data = after ).
      stop( 'scripted response case did not persist the expected classification/timing.' ).
      RETURN.
    ENDIF.

    CASE expected_state.
      WHEN 'PENDING'.
        IF header-status <> 'APPROVED'.
          stop( 'PENDING scripted result changed the business order status.' ).
          RETURN.
        ENDIF.
      WHEN 'DELIVERED'.
        IF header-status <> 'SENT'.
          stop( 'DELIVERED scripted result did not move the business order to SENT.' ).
          RETURN.
        ENDIF.
      WHEN 'FAILED' OR 'UNKNOWN'.
        IF header-status <> 'ERROR'.
          stop( 'FAILED/UNKNOWN scripted result did not move the business order to ERROR.' ).
          RETURN.
        ENDIF.
      WHEN OTHERS.
        stop( 'test helper received an unsupported expected state.' ).
        RETURN.
    ENDCASE.

    success = abap_true.
  ENDMETHOD.


  METHOD force_in_flight.
    MODIFY ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        UPDATE FIELDS ( DispatchState AttemptCount LeaseOwner LeaseExpiresAt
                        NextAttemptAt RetryWindowStartedAt )
        WITH VALUE #( ( DeliveryUUID          = delivery_uuid
                        DispatchState         = 'IN_FLIGHT'
                        AttemptCount          = attempt_count
                        LeaseOwner            = lease_owner
                        LeaseExpiresAt        = lease_expires_at
                        NextAttemptAt         = next_attempt_at
                        RetryWindowStartedAt  = retry_window_started_at ) )
      FAILED DATA(failed_force)
      REPORTED DATA(reported_force).

    IF failed_force IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( name = 'force IN_FLIGHT FAILED' data = failed_force ).
      stop( 'test IN_FLIGHT state could not be written through EML.' ).
      RETURN.
    ENDIF.

    success = save_all( ).
  ENDMETHOD.


  METHOD test_status_matrix.
    success = abap_false.
    console->write( '--- 5b-1: complete answered HTTP classification matrix ---' ).

    TYPES:
      BEGIN OF ty_case,
        status         TYPE i,
        expected_state TYPE string,
      END OF ty_case.

    DATA cases TYPE STANDARD TABLE OF ty_case WITH EMPTY KEY.
    cases = VALUE #(
      ( status = 200 expected_state = 'DELIVERED' )
      ( status = 204 expected_state = 'DELIVERED' )
      ( status = 299 expected_state = 'DELIVERED' )
      ( status = 400 expected_state = 'FAILED' )
      ( status = 401 expected_state = 'FAILED' )
      ( status = 403 expected_state = 'FAILED' )
      ( status = 404 expected_state = 'FAILED' )
      ( status = 409 expected_state = 'FAILED' )
      ( status = 412 expected_state = 'FAILED' )
      ( status = 413 expected_state = 'FAILED' )
      ( status = 418 expected_state = 'FAILED' )
      ( status = 429 expected_state = 'PENDING' )
      ( status = 502 expected_state = 'PENDING' )
      ( status = 503 expected_state = 'PENDING' )
      ( status = 500 expected_state = 'UNKNOWN' )
      ( status = 504 expected_state = 'UNKNOWN' )
      ( status = 507 expected_state = 'UNKNOWN' ) ).

    DATA(t0) = CONV timestampl( '20200102100000.0000000' ).
    DATA(normal_due) = add_seconds( base = t0 seconds = 5 ).

    LOOP AT cases INTO DATA(case_row).
      DATA(response) = VALUE zjp_if_outbound_transport=>ty_response(
        answered = abap_true
        status   = case_row-status ).

      DATA expected_due TYPE zjp_po_dlv-next_attempt_at.
      DATA expected_anchor TYPE zjp_po_dlv-retry_window_started_at.

      CLEAR expected_due.
      CLEAR expected_anchor.

      IF case_row-expected_state = 'PENDING'.
        expected_due = normal_due.
        expected_anchor = t0.
      ENDIF.

      IF run_script_case(
           response        = response
           expected_state  = case_row-expected_state
           test_time       = t0
           expected_due    = expected_due
           expected_anchor = expected_anchor ) = abap_false.
        console->write( |HTTP matrix failed at status { case_row-status }.| ).
        RETURN.
      ENDIF.
    ENDLOOP.

    console->write( 'PASS: all answered HTTP classes follow the frozen 7.4 matrix, including 204/299, 404/412/413, 429, 500/504 and other 5xx.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_certainty_edges.
    success = abap_false.
    console->write( '--- 5b-2: conservative certainty defaults and answered precedence ---' ).

    DATA(t0) = CONV timestampl( '20200102120000.0000000' ).
    DATA(normal_due) = add_seconds( base = t0 seconds = 5 ).

    " Missing/initial certainty on an unanswered result is conservative UNKNOWN.
    DATA(initial_certainty) = VALUE zjp_if_outbound_transport=>ty_response(
      answered     = abap_false
      failure_text = 'no answer' ).

    IF run_script_case(
         response        = initial_certainty
         expected_state  = 'UNKNOWN'
         test_time       = t0
         expected_due    = VALUE zjp_po_dlv-next_attempt_at( )
         expected_anchor = VALUE zjp_po_dlv-retry_window_started_at( ) ) = abap_false.
      RETURN.
    ENDIF.

    " Unknown/future certainty values also fail conservatively to UNKNOWN.
    DATA(unknown_certainty) = VALUE zjp_if_outbound_transport=>ty_response(
      answered     = abap_false
      certainty    = 'FUTURE_CERTAINTY'
      failure_text = 'no answer' ).

    IF run_script_case(
         response        = unknown_certainty
         expected_state  = 'UNKNOWN'
         test_time       = t0
         expected_due    = VALUE zjp_po_dlv-next_attempt_at( )
         expected_anchor = VALUE zjp_po_dlv-retry_window_started_at( ) ) = abap_false.
      RETURN.
    ENDIF.

    " Answered status wins even if certainty contradicts it.
    DATA(answered_not_sent) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 500
      certainty   = zjp_if_outbound_transport=>co_certainty_not_sent
      retry_after = '120' ).

    IF run_script_case(
         response        = answered_not_sent
         expected_state  = 'UNKNOWN'
         test_time       = t0
         expected_due    = VALUE zjp_po_dlv-next_attempt_at( )
         expected_anchor = VALUE zjp_po_dlv-retry_window_started_at( ) ) = abap_false.
      RETURN.
    ENDIF.

    DATA(answered_may_apply) = VALUE zjp_if_outbound_transport=>ty_response(
      answered  = abap_true
      status    = 503
      certainty = zjp_if_outbound_transport=>co_certainty_may_apply ).

    IF run_script_case(
         response        = answered_may_apply
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    console->write( 'PASS: initial/unknown unanswered certainty -> UNKNOWN; answered HTTP status ignores contradictory certainty.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_retry_after_edges.
    success = abap_false.
    console->write( '--- 5b-3: Retry-After malformed/overflow/IMF-fixdate/window edges ---' ).

    DATA(t0) = CONV timestampl( '19941106084930.0000000' ).
    DATA(normal_due) = add_seconds( base = t0 seconds = 5 ).
    DATA(imf_due) = add_seconds( base = t0 seconds = 7 ).

    " A shorter valid delta may never accelerate the normal +5s policy delay.
    DATA(delta_short) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = '1' ).

    IF run_script_case(
         response        = delta_short
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(malformed) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = 'abc' ).

    IF run_script_case(
         response        = malformed
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(overflowing) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = '9999999999999999999999999999999999999999' ).

    IF run_script_case(
         response        = overflowing
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA overlong_raw TYPE string.
    DO 129 TIMES.
      overlong_raw &&= '9'.
    ENDDO.

    DATA(overlong) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = overlong_raw ).

    IF run_script_case(
         response        = overlong
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(imf_valid) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = 'Sun, 06 Nov 1994 08:49:37 GMT' ).

    IF run_script_case(
         response        = imf_valid
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = imf_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(imf_bad_weekday) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = 'Mon, 06 Nov 1994 08:49:37 GMT' ).

    IF run_script_case(
         response        = imf_bad_weekday
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(imf_past) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = 'Sun, 06 Nov 1994 08:49:31 GMT' ).

    IF run_script_case(
         response        = imf_past
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    " Retry-After is ignored on unanswered NOT_SENT and on non-transient 500.
    DATA(unanswered_header) = VALUE zjp_if_outbound_transport=>ty_response(
      answered     = abap_false
      certainty    = zjp_if_outbound_transport=>co_certainty_not_sent
      retry_after  = '120'
      failure_text = 'not sent' ).

    IF run_script_case(
         response        = unanswered_header
         expected_state  = 'PENDING'
         test_time       = t0
         expected_due    = normal_due
         expected_anchor = t0 ) = abap_false.
      RETURN.
    ENDIF.

    DATA(non_transient_header) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 500
      retry_after = '120' ).

    IF run_script_case(
         response        = non_transient_header
         expected_state  = 'UNKNOWN'
         test_time       = t0
         expected_due    = VALUE zjp_po_dlv-next_attempt_at( )
         expected_anchor = VALUE zjp_po_dlv-retry_window_started_at( ) ) = abap_false.
      RETURN.
    ENDIF.

    " A valid Retry-After beyond the 15-minute window is persisted as evidence,
    " then blocked by eligibility without spending another attempt.
    DATA(window_fixture) = make_fixture( 'SUP074A' ).
    IF window_fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(window_t0) = CONV timestampl( '20200102130000.0000000' ).
    DATA(window_due) = add_seconds( base = window_t0 seconds = 1000 ).

    DATA(window_response) = VALUE zjp_if_outbound_transport=>ty_response(
      answered    = abap_true
      status      = 503
      retry_after = '1000'
      body        = '{"error":{"code":"SCRIPTED_TEST"}}' ).

    DATA(window_script) = NEW zjp_cl_p74_transport_script(
      scripted_response = window_response ).
    DATA window_transport TYPE REF TO zjp_if_outbound_transport.
    window_transport = window_script.

    DATA(window_worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = window_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = window_t0 ).

    DATA(window_first) = window_worker->run_once( window_fixture-delivery_uuid ).
    DATA(window_row) = intent_row( window_fixture-delivery_uuid ).

    IF window_first-final_state <> 'PENDING'
       OR window_row-attempt_count <> 1
       OR window_row-next_attempt_at <> window_due
       OR window_row-retry_window_started_at <> window_t0
       OR window_script->get_post_count( ) <> 1.
      console->write( name = 'Beyond-window first outcome' data = window_first ).
      console->write( name = 'Beyond-window row' data = window_row ).
      stop( 'Retry-After beyond the window was not persisted as evidence.' ).
      RETURN.
    ENDIF.

    DATA(window_check_time) = add_seconds( base = window_t0 seconds = 100 ).
    DATA(window_worker_2) = NEW zjp_cl_dispatch_coordinator(
      transport        = window_transport
      lease_seconds    = lease_seconds
      policy_timestamp = window_check_time ).

    DATA(window_second) = window_worker_2->run_once( window_fixture-delivery_uuid ).
    DATA(window_row_2) = intent_row( window_fixture-delivery_uuid ).

    IF window_second-dispatched = abap_true
       OR window_second-skip_reason <>
            zjp_cl_dispatch_coordinator=>skipped-retry_window_blocked
       OR window_script->get_post_count( ) <> 1
       OR window_row_2-attempt_count <> 1
       OR window_row_2-next_attempt_at <> window_due.
      console->write( name = 'Beyond-window second outcome' data = window_second ).
      stop( 'Retry-After due beyond the retry window was not blocked without another post.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: Retry-After never accelerates, malformed/overflow/overlong are ignored, strict IMF-fixdate works, and >window due is persisted then blocked.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_jitter_precision.
    success = abap_false.
    console->write( '--- 5b-4: millisecond jitter precision ---' ).

    DATA(fixture) = make_fixture( 'SUP074A' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(t0) = CONV timestampl( '20200102140000.0000000' ).
    DATA(expected_due) = add_seconds(
      base    = t0
      seconds = CONV ty_seconds( '5.123' ) ).

    DATA(response) = VALUE zjp_if_outbound_transport=>ty_response(
      answered = abap_true
      status   = 503
      body     = '{"error":{"code":"SCRIPTED_TEST"}}' ).

    DATA(script) = NEW zjp_cl_p74_transport_script(
      scripted_response = response ).
    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = script.

    DATA(worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 123
      policy_timestamp    = t0 ).

    DATA(outcome) = worker->run_once( fixture-delivery_uuid ).
    DATA(after) = intent_row( fixture-delivery_uuid ).

    IF outcome-final_state <> 'PENDING'
       OR after-attempt_count <> 1
       OR after-next_attempt_at <> expected_due
       OR after-retry_window_started_at <> t0
       OR script->get_post_count( ) <> 1.
      console->write( name = '123ms jitter outcome' data = outcome ).
      console->write( name = '123ms jitter row' data = after ).
      stop( '123ms jitter was not preserved exactly in durable NextAttemptAt.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: +123ms jitter persisted exactly as +5.123s; millisecond precision is preserved.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_lease_edges.
    success = abap_false.
    console->write( '--- 5b-5: live/stale IN_FLIGHT lease behavior and budget ---' ).

    DATA(t0) = CONV timestampl( '20200102150000.0000000' ).
    DATA(owner) = cl_system_uuid=>create_uuid_x16_static( ).

    DATA(response) = VALUE zjp_if_outbound_transport=>ty_response(
      answered = abap_true
      status   = 503
      body     = '{"error":{"code":"SCRIPTED_TEST"}}' ).

    " Live lease: no claim and no post.
    DATA(live_fixture) = make_fixture( 'SUP074A' ).
    IF live_fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(live_expiry) = add_seconds( base = t0 seconds = 60 ).
    IF force_in_flight(
         delivery_uuid           = live_fixture-delivery_uuid
         attempt_count           = 1
         lease_owner             = owner
         lease_expires_at        = live_expiry
         next_attempt_at         = VALUE zjp_po_dlv-next_attempt_at( )
         retry_window_started_at = VALUE zjp_po_dlv-retry_window_started_at( ) ) = abap_false.
      RETURN.
    ENDIF.

    DATA(live_script) = NEW zjp_cl_p74_transport_script(
      scripted_response = response ).
    DATA live_transport TYPE REF TO zjp_if_outbound_transport.
    live_transport = live_script.

    DATA(live_worker) = NEW zjp_cl_dispatch_coordinator(
      transport        = live_transport
      lease_seconds    = lease_seconds
      policy_timestamp = t0 ).

    DATA(live_outcome) = live_worker->run_once( live_fixture-delivery_uuid ).
    DATA(live_after) = intent_row( live_fixture-delivery_uuid ).

    IF live_outcome-claimed = abap_true
       OR live_outcome-dispatched = abap_true
       OR live_outcome-skip_reason <> zjp_cl_dispatch_coordinator=>skipped-lease_live
       OR live_script->get_post_count( ) <> 0
       OR live_after-attempt_count <> 1.
      console->write( name = 'Live lease outcome' data = live_outcome ).
      stop( 'a live IN_FLIGHT lease was reclaimed or spent an attempt.' ).
      RETURN.
    ENDIF.

    " Clean up to a safely exhausted PENDING row so no real runner can reclaim it.
    IF force_policy(
         delivery_uuid           = live_fixture-delivery_uuid
         attempt_count           = 4
         next_attempt_at         = VALUE zjp_po_dlv-next_attempt_at( )
         retry_window_started_at = t0 ) = abap_false.
      RETURN.
    ENDIF.

    " Stale lease below budget is reclaimed even if its old PENDING due would
    " have been in the future; due/window scheduling belongs to PENDING only.
    DATA(stale_fixture) = make_fixture( 'SUP074A' ).
    IF stale_fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(stale_expiry) = CONV timestampl( '20200102145959.0000000' ).
    DATA(old_anchor) = CONV timestampl( '20200102145820.0000000' ).
    DATA(old_future_due) = add_seconds( base = t0 seconds = 500 ).

    IF force_in_flight(
         delivery_uuid           = stale_fixture-delivery_uuid
         attempt_count           = 2
         lease_owner             = owner
         lease_expires_at        = stale_expiry
         next_attempt_at         = old_future_due
         retry_window_started_at = old_anchor ) = abap_false.
      RETURN.
    ENDIF.

    DATA(stale_script) = NEW zjp_cl_p74_transport_script(
      scripted_response = response ).
    DATA stale_transport TYPE REF TO zjp_if_outbound_transport.
    stale_transport = stale_script.

    DATA(stale_worker) = NEW zjp_cl_dispatch_coordinator(
      transport           = stale_transport
      lease_seconds       = lease_seconds
      jitter_milliseconds = 0
      policy_timestamp    = t0 ).

    DATA(stale_outcome) = stale_worker->run_once( stale_fixture-delivery_uuid ).
    DATA(stale_after) = intent_row( stale_fixture-delivery_uuid ).
    DATA(stale_due) = add_seconds( base = t0 seconds = 120 ).

    IF stale_outcome-dispatched <> abap_true
       OR stale_script->get_post_count( ) <> 1
       OR stale_after-attempt_count <> 3
       OR stale_after-dispatch_state <> 'PENDING'
       OR stale_after-next_attempt_at <> stale_due
       OR stale_after-retry_window_started_at <> old_anchor.
      console->write( name = 'Stale lease outcome' data = stale_outcome ).
      console->write( name = 'Stale lease row' data = stale_after ).
      stop( 'an expired IN_FLIGHT lease below budget was not safely reclaimed.' ).
      RETURN.
    ENDIF.

    " Stale lease at the durable budget may not be reclaimed.
    DATA(exhausted_fixture) = make_fixture( 'SUP074A' ).
    IF exhausted_fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    IF force_in_flight(
         delivery_uuid           = exhausted_fixture-delivery_uuid
         attempt_count           = 4
         lease_owner             = owner
         lease_expires_at        = stale_expiry
         next_attempt_at         = VALUE zjp_po_dlv-next_attempt_at( )
         retry_window_started_at = old_anchor ) = abap_false.
      RETURN.
    ENDIF.

    DATA(exhausted_script) = NEW zjp_cl_p74_transport_script(
      scripted_response = response ).
    DATA exhausted_transport TYPE REF TO zjp_if_outbound_transport.
    exhausted_transport = exhausted_script.

    DATA(exhausted_worker) = NEW zjp_cl_dispatch_coordinator(
      transport        = exhausted_transport
      lease_seconds    = lease_seconds
      policy_timestamp = t0 ).

    DATA(exhausted_outcome) = exhausted_worker->run_once(
                                exhausted_fixture-delivery_uuid ).

    IF exhausted_outcome-dispatched = abap_true
       OR exhausted_outcome-skip_reason <>
            zjp_cl_dispatch_coordinator=>skipped-retry_exhausted
       OR exhausted_script->get_post_count( ) <> 0.
      console->write( name = 'Stale exhausted outcome' data = exhausted_outcome ).
      stop( 'an expired IN_FLIGHT row at AttemptCount 4 was reclaimed.' ).
      RETURN.
    ENDIF.

    IF force_policy(
         delivery_uuid           = exhausted_fixture-delivery_uuid
         attempt_count           = 4
         next_attempt_at         = VALUE zjp_po_dlv-next_attempt_at( )
         retry_window_started_at = old_anchor ) = abap_false.
      RETURN.
    ENDIF.

    console->write( 'PASS: live lease skips with zero posts; stale lease below budget reclaims; stale AttemptCount 4 is exhausted.' ).
    success = abap_true.
  ENDMETHOD.


  METHOD test_terminal_clears_timing.
    success = abap_false.
    console->write( '--- 5b-6: terminal and UNKNOWN outcomes clear retry timing ---' ).

    TYPES:
      BEGIN OF ty_case,
        status         TYPE i,
        expected_state TYPE string,
      END OF ty_case.

    DATA cases TYPE STANDARD TABLE OF ty_case WITH EMPTY KEY.
    cases = VALUE #(
      ( status = 204 expected_state = 'DELIVERED' )
      ( status = 400 expected_state = 'FAILED' )
      ( status = 500 expected_state = 'UNKNOWN' ) ).

    DATA(t0) = CONV timestampl( '20200102160000.0000000' ).
    DATA(anchor) = CONV timestampl( '20200102155820.0000000' ).

    LOOP AT cases INTO DATA(case_row).
      DATA(fixture) = make_fixture( 'SUP074A' ).
      IF fixture-delivery_uuid IS INITIAL.
        RETURN.
      ENDIF.

      IF force_policy(
           delivery_uuid           = fixture-delivery_uuid
           attempt_count           = 1
           next_attempt_at         = t0
           retry_window_started_at = anchor ) = abap_false.
        RETURN.
      ENDIF.

      DATA(response) = VALUE zjp_if_outbound_transport=>ty_response(
        answered = abap_true
        status   = case_row-status ).

      IF case_row-expected_state = 'DELIVERED'.
        response-body = success_body( ).
      ELSE.
        response-body = '{"error":{"code":"SCRIPTED_TEST"}}'.
      ENDIF.

      DATA(script) = NEW zjp_cl_p74_transport_script(
        scripted_response = response ).
      DATA transport TYPE REF TO zjp_if_outbound_transport.
      transport = script.

      DATA(worker) = NEW zjp_cl_dispatch_coordinator(
        transport        = transport
        lease_seconds    = lease_seconds
        policy_timestamp = t0 ).

      DATA(outcome) = worker->run_once( fixture-delivery_uuid ).
      DATA(after) = intent_row( fixture-delivery_uuid ).

      IF outcome-final_state <> case_row-expected_state
         OR after-attempt_count <> 2
         OR after-next_attempt_at IS NOT INITIAL
         OR after-retry_window_started_at IS NOT INITIAL
         OR script->get_post_count( ) <> 1.
        console->write( name = 'Timing-clear outcome' data = outcome ).
        console->write( name = 'Timing-clear row' data = after ).
        stop( 'a non-PENDING result retained stale retry timing.' ).
        RETURN.
      ENDIF.
    ENDLOOP.

    console->write( 'PASS: DELIVERED, FAILED and UNKNOWN all clear NextAttemptAt and RetryWindowStartedAt.' ).
    success = abap_true.
  ENDMETHOD.

ENDCLASS.
