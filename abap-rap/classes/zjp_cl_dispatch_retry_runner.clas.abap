" Phase 7.3 RUNTIME RECOVERY HARNESS. Read this before changing anything.
"
" WHAT THIS IS NOT. This class is NOT `retryDelivery`. retryDelivery is the
" planned production capability for returning a failed delivery to the outbox,
" and it REMAINS UNIMPLEMENTED: the only mention of it anywhere in this
" repository is a comment in ZJP_CL_DISPATCH_COORDINATOR. Nothing here should be
" read as that capability arriving early, and nothing here should be promoted
" into production. When retryDelivery is built, this class is deleted.
"
" WHY IT EXISTS. The Phase 7.3 outbound acceptance ran correctly and the
" coordinator behaved exactly as designed, but the CAP application happened to
" be STOPPED. The Cloud Foundry router answered HTTP 404 "Requested route ...
" does not exist", which is an ANSWERED deterministic refusal - fault category B
" - so the coordinator correctly classified it FAILED and drove the order to
" ERROR. That is right. It is an ENVIRONMENTAL failure, not a defect, and the
" durable delivery identity survived it intact.
"
" WHY THE NORMAL PATH CANNOT RECOVER IT. sendToSupplier is the only production
" way back to PENDING, and it refuses this order: it requires business
" Status = 'APPROVED' and the order is now 'ERROR'. The coordinator will not
" pick the intent up either - claim treats FAILED as final and skips it with
" CLAIM_SKIPPED_STATE_FINAL, deliberately, because "only sendToSupplier may
" return them to PENDING". So a one-off harness is the honest way to finish the
" acceptance run without inventing the production capability.
"
" WHY IT IS SAFE TO FINISH THIS WAY. recordDeliveryResult already accepts a
" positive DELIVERED result while the order is in ERROR and moves it ERROR ->
" SENT; its own handler allows current_status APPROVED, ERROR or SENT for a
" DELIVERED result. So the second attempt closes the business transaction
" through the ordinary production action, not through a manual repair.
"
" HARD LIMITS, all enforced below:
"   - it handles EXACTLY ONE pinned fixture and searches for nothing;
"   - it never calls find_eligible, never picks newest or oldest;
"   - it never calls sendToSupplier;
"   - it never creates an order, an intent or a new delivery identity;
"   - it never regenerates the payload snapshot or its hash;
"   - it never touches the PurchaseOrder header before the retry;
"   - direct SQL INSERT / UPDATE / DELETE is forbidden - SELECT only, and every
"     mutation goes through EML;
"   - the ONLY mutation before the network is one EML DispatchState reset;
"   - the ONLY external HTTP attempt is one coordinator->run_once.
CLASS zjp_cl_dispatch_retry_runner DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " ---------- THE PINNED FIXTURE ----------
    " Intentionally fixture-specific. These four values are the runtime identity
    " of the one delivery this harness may touch. The hex-literal form is the
    " one ZJP_CL_BUILDER_TEST already activates.
    CONSTANTS fixture_order_uuid TYPE sysuuid_x16
      VALUE '37FC3FA8EB2D1FD1ADC2A13257140EFD'.
    CONSTANTS fixture_delivery_uuid TYPE sysuuid_x16
      VALUE '37FC3FA8EB2D1FD1ADC3229323ECD083'.
    CONSTANTS fixture_first_correlation TYPE sysuuid_x16
      VALUE '37FC3FA8EB2D1FD1ADC322B88186F083'.
    CONSTANTS fixture_order_number TYPE zjp_po_h-purchase_order_number
      VALUE 'PO00000160'.
    CONSTANTS runtime_supplier TYPE zjp_po_h-supplier VALUE 'RTTEST001'.

    " The Integration Suite destination, the same one the runner and the
    " dispatch test use. Host, port, TLS and OAuth live there; no credential and
    " no destination configuration is introduced here.
    CONSTANTS destination TYPE rfcdest VALUE 'ZJP_CI_ORDER_DELIVERY'.

    " The SAME injected value the other harnesses use, and still NOT a
    " production default.
    CONSTANTS lease_seconds TYPE i VALUE 300.

    CONSTANTS state_pending   TYPE string VALUE 'PENDING'.
    CONSTANTS state_failed    TYPE string VALUE 'FAILED'.
    CONSTANTS state_delivered TYPE string VALUE 'DELIVERED'.
    CONSTANTS status_error    TYPE string VALUE 'ERROR'.
    CONSTANTS status_sent     TYPE string VALUE 'SENT'.

    TYPES:
      BEGIN OF ty_header,
        found                 TYPE abap_bool,
        purchase_order_uuid   TYPE zjp_po_h-purchase_order_uuid,
        purchase_order_number TYPE zjp_po_h-purchase_order_number,
        status                TYPE zjp_po_h-status,
        supplier              TYPE zjp_po_h-supplier,
        order_revision        TYPE zjp_po_h-order_revision,
        integration_status    TYPE zjp_po_h-integration_status,
        delivery_id           TYPE zjp_po_h-delivery_id,
        last_correlation_id   TYPE zjp_po_h-last_correlation_id,
      END OF ty_header.

    TYPES:
      BEGIN OF ty_intent,
        found               TYPE abap_bool,
        delivery_uuid       TYPE zjp_po_dlv-delivery_uuid,
        purchase_order_uuid TYPE zjp_po_dlv-purchase_order_uuid,
        order_revision      TYPE zjp_po_dlv-order_revision,
        dispatch_state      TYPE zjp_po_dlv-dispatch_state,
        attempt_count       TYPE zjp_po_dlv-attempt_count,
        last_correlation_id TYPE zjp_po_dlv-last_correlation_id,
        portal_order_uuid   TYPE zjp_po_dlv-portal_order_uuid,
        lease_owner         TYPE zjp_po_dlv-lease_owner,
        lease_expires_at    TYPE zjp_po_dlv-lease_expires_at,
        payload_hash        TYPE zjp_po_dlv-payload_hash,
        payload_snapshot    TYPE zjp_po_dlv-payload_snapshot,
      END OF ty_intent.

    METHODS stop
      IMPORTING text TYPE string.

    METHODS save_all
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS read_header
      RETURNING VALUE(row) TYPE ty_header.

    METHODS report_header
      IMPORTING label TYPE string
                row   TYPE ty_header.

    METHODS intent_row
      RETURNING VALUE(row) TYPE ty_intent.

    " The snapshot is measured, never printed.
    METHODS report_intent
      IMPORTING label TYPE string
                row   TYPE ty_intent.

ENDCLASS.


CLASS zjp_cl_dispatch_retry_runner IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write( '=== Phase 7.3 retry runner - ONE pinned fixture ===' ).
    out->write( '*** THIS IS NOT retryDelivery. retryDelivery is NOT implemented. ***' ).
    out->write( '*** This is a one-off runtime recovery harness for a single fixture ***' ).
    out->write( '*** whose first attempt hit a STOPPED CAP route (answered HTTP 404). ***' ).
    out->write( |*** It makes AT MOST ONE real HTTP POST over { destination }. ***| ).
    out->write( 'It never calls sendToSupplier, never calls find_eligible, and never' ).
    out->write( 'creates an order, an intent or a new delivery identity.' ).
    out->write( |Injected lease_seconds = { lease_seconds } (runtime value, not a default).| ).
    out->write( '' ).
    console->write( name = 'PINNED PurchaseOrderUUID' data = fixture_order_uuid ).
    console->write( name = 'PINNED DeliveryUUID'      data = fixture_delivery_uuid ).
    console->write( name = 'PINNED first correlation' data = fixture_first_correlation ).
    console->write( |PINNED PurchaseOrderNumber { fixture_order_number } supplier { runtime_supplier }| ).
    out->write( '' ).

    " ---------- 1. HEADER PRECHECK - READ ONLY ----------
    DATA(header_before) = read_header( ).
    IF header_before-found = abap_false.
      stop( 'the pinned PurchaseOrder could not be read; nothing was changed.' ).
      RETURN.
    ENDIF.
    report_header( label = 'HEADER BEFORE' row = header_before ).

    IF header_before-purchase_order_uuid <> fixture_order_uuid.
      stop( 'the header UUID is not the pinned fixture; nothing was changed.' ).
      RETURN.
    ENDIF.
    IF header_before-purchase_order_number <> fixture_order_number.
      stop( |PurchaseOrderNumber is { header_before-purchase_order_number }, not { fixture_order_number }.| ).
      RETURN.
    ENDIF.
    IF header_before-supplier <> runtime_supplier.
      stop( |the supplier is { header_before-supplier }, not { runtime_supplier }.| ).
      RETURN.
    ENDIF.
    IF header_before-status <> status_error.
      stop( |the order is { header_before-status }, not ERROR. This harness only recovers the ERROR case.| ).
      RETURN.
    ENDIF.
    IF header_before-integration_status <> state_failed.
      stop( |IntegrationStatus is { header_before-integration_status }, not FAILED.| ).
      RETURN.
    ENDIF.
    IF header_before-delivery_id <> fixture_delivery_uuid.
      stop( 'the header DeliveryId is not the pinned DeliveryUUID; nothing was changed.' ).
      RETURN.
    ENDIF.

    " ---------- 2. INTENT PRECHECK - READ ONLY ----------
    DATA(before) = intent_row( ).
    IF before-found = abap_false.
      stop( 'the pinned DeliveryIntent could not be read; nothing was changed.' ).
      RETURN.
    ENDIF.
    report_intent( label = 'INTENT BEFORE RESET' row = before ).

    IF before-delivery_uuid <> fixture_delivery_uuid.
      stop( 'the intent key is not the pinned DeliveryUUID; nothing was changed.' ).
      RETURN.
    ENDIF.
    IF before-purchase_order_uuid <> fixture_order_uuid.
      stop( 'the intent belongs to a different order; nothing was changed.' ).
      RETURN.
    ENDIF.
    IF before-dispatch_state <> state_failed.
      stop( |the intent is { before-dispatch_state }, not FAILED. Nothing was changed.| ).
      RETURN.
    ENDIF.
    IF before-attempt_count <> 1.
      stop( |AttemptCount is { before-attempt_count }, not 1. This is not the state this harness expects.| ).
      RETURN.
    ENDIF.
    IF before-last_correlation_id <> fixture_first_correlation.
      stop( 'the persisted correlation id is not the pinned first attempt; nothing was changed.' ).
      RETURN.
    ENDIF.
    IF before-portal_order_uuid IS NOT INITIAL.
      stop( 'the intent already carries a PortalOrderUUID; the first attempt was not a clean refusal.' ).
      RETURN.
    ENDIF.
    IF before-lease_owner IS NOT INITIAL OR before-lease_expires_at IS NOT INITIAL.
      stop( 'the intent advertises a lease; another run may hold it. Nothing was changed.' ).
      RETURN.
    ENDIF.
    IF before-payload_snapshot IS INITIAL.
      stop( 'the intent has no PayloadSnapshot; there is nothing to replay.' ).
      RETURN.
    ENDIF.
    " recordDeliveryResult refuses a result whose revision differs from the
    " header's, so a mismatch here would waste the send.
    IF before-order_revision <> header_before-order_revision.
      stop( |intent revision { before-order_revision } and header revision | &&
            |{ header_before-order_revision } disagree; nothing was changed.| ).
      RETURN.
    ENDIF.

    " ---------- 3. THE ONLY PRE-NETWORK MUTATION ----------
    " DispatchState and NOTHING else. The snapshot, the hash, the counter, the
    " correlation id, the revision, the identity and the header are all left
    " exactly as they are: the whole point of a replay is that it carries the
    " approved bytes and the same delivery identity.
    "
    " This is the shape ZJP_CL_PO_DISPATCH_TEST-force_dispatch_state already
    " activates, used here for the same reason it exists there: to stand in for
    " an operator-requested retry that production cannot yet express.
    console->write( '' ).
    console->write( 'Resetting DispatchState FAILED -> PENDING. No other field is written.' ).

    MODIFY ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        UPDATE FIELDS ( DispatchState )
        WITH VALUE #( ( DeliveryUUID  = fixture_delivery_uuid
                        DispatchState = state_pending ) )
      FAILED DATA(failed_reset)
      REPORTED DATA(reported_reset).

    IF failed_reset IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( name = 'reset FAILED'   data = failed_reset ).
      console->write( name = 'reset REPORTED' data = reported_reset ).
      stop( 'the DispatchState reset was refused; nothing was committed and nothing was sent.' ).
      RETURN.
    ENDIF.

    IF save_all( ) = abap_false.
      stop( 'the DispatchState reset could not be committed; nothing was sent.' ).
      RETURN.
    ENDIF.

    " ---------- 4. POST-RESET GATE ----------
    DATA(after_reset) = intent_row( ).
    IF after_reset-found = abap_false.
      stop( 'the intent could not be re-read after the reset; nothing was sent.' ).
      RETURN.
    ENDIF.
    report_intent( label = 'INTENT AFTER RESET' row = after_reset ).

    IF after_reset-dispatch_state <> state_pending.
      stop( |after the reset the intent is { after_reset-dispatch_state }, not PENDING; nothing was sent.| ).
      RETURN.
    ENDIF.
    " The counter must NOT have moved. A reset is not an attempt.
    IF after_reset-attempt_count <> before-attempt_count.
      stop( |the reset changed AttemptCount { before-attempt_count } -> { after_reset-attempt_count }; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF after_reset-delivery_uuid <> before-delivery_uuid.
      stop( 'the reset changed the delivery identity; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_reset-purchase_order_uuid <> before-purchase_order_uuid.
      stop( 'the reset changed the owning order; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_reset-order_revision <> before-order_revision.
      stop( 'the reset changed OrderRevision; nothing was sent.' ).
      RETURN.
    ENDIF.
    " Byte-identical, not merely "about the same length". The approved bytes are
    " what CAP hashes and what the receipt is compared against.
    IF after_reset-payload_snapshot <> before-payload_snapshot.
      stop( 'the reset changed the PayloadSnapshot; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_reset-payload_hash <> before-payload_hash.
      stop( 'the reset changed the PayloadHash; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_reset-last_correlation_id <> fixture_first_correlation.
      stop( 'the reset changed the correlation id; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_reset-portal_order_uuid IS NOT INITIAL.
      stop( 'the reset assigned a PortalOrderUUID; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_reset-lease_owner IS NOT INITIAL OR after_reset-lease_expires_at IS NOT INITIAL.
      stop( 'the reset assigned a lease; nothing was sent.' ).
      RETURN.
    ENDIF.

    " The header must be UNTOUCHED by the reset. The intent is PENDING while the
    " order still says ERROR/FAILED, and that mismatch is EXPECTED for this
    " harness: production retryDelivery, which would reconcile both, does not
    " exist yet. Do NOT "fix" the header by hand - the second attempt's
    " recordDeliveryResult is what legitimately moves ERROR -> SENT.
    DATA(header_after_reset) = read_header( ).
    IF header_after_reset-found = abap_false.
      stop( 'the header could not be re-read after the reset; nothing was sent.' ).
      RETURN.
    ENDIF.
    report_header( label = 'HEADER AFTER RESET' row = header_after_reset ).

    IF header_after_reset-status <> status_error.
      stop( |the reset changed the header to { header_after_reset-status }; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF header_after_reset-integration_status <> state_failed.
      stop( |the reset changed IntegrationStatus to { header_after_reset-integration_status }; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF header_after_reset-delivery_id <> fixture_delivery_uuid.
      stop( 'the reset changed the header DeliveryId; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF header_after_reset-purchase_order_number <> fixture_order_number.
      stop( 'the reset changed the PurchaseOrderNumber; nothing was sent.' ).
      RETURN.
    ENDIF.

    console->write( '' ).
    console->write( 'Intent PENDING while the header still reads ERROR/FAILED.' ).
    console->write( 'That mismatch is EXPECTED here and is not repaired by hand.' ).

    " ---------- 5. THE ONE REAL RETRY ----------
    console->write( '' ).
    console->write( 'All gates passed. Dispatching EXACTLY ONE request.' ).

    " Declared and assigned SEPARATELY rather than constructed inline: the SAP
    " parser rejected the nested NEW form in this context in Phase 5.2g.
    DATA real_transport TYPE REF TO zjp_if_outbound_transport.

    real_transport = NEW zjp_cl_outbound_transport( destination_name = destination ).

    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = real_transport
      lease_seconds = lease_seconds ).

    " EXACTLY ONCE, with the PINNED DeliveryUUID. No loop. No retry.
    DATA(outcome) = coordinator->run_once( fixture_delivery_uuid ).

    " ---------- 6. EVIDENCE ----------
    console->write( '' ).
    console->write( |OUTCOME claimed={ outcome-claimed } dispatched={ outcome-dispatched } | &&
                    |answered={ outcome-answered } http_status={ outcome-http_status }| ).
    console->write( |OUTCOME final_state={ outcome-final_state } attempt_count={ outcome-attempt_count } | &&
                    |recorded={ outcome-recorded } skip_reason={ outcome-skip_reason }| ).
    console->write( name = 'OUTCOME correlation_uuid'  data = outcome-correlation_uuid ).
    console->write( name = 'OUTCOME portal_order_uuid' data = outcome-portal_order_uuid ).
    console->write( |OUTCOME error_code={ outcome-error_code }| ).

    " Truncated deliberately. The coordinator puts the response body here on a
    " failure; it carries no header and no credential, and a cap keeps an
    " unexpected payload out of the console in full.
    DATA(safe_error) = outcome-error_text.
    IF strlen( safe_error ) > 200.
      safe_error = safe_error(200).
    ENDIF.
    console->write( |OUTCOME error_text={ safe_error }| ).

    DATA(after) = intent_row( ).
    report_intent( label = 'INTENT AFTER SEND' row = after ).

    DATA(header_final) = read_header( ).
    report_header( label = 'HEADER FINAL' row = header_final ).

    console->write( '' ).
    console->write( |DELTA DispatchState { before-dispatch_state } -> { after_reset-dispatch_state } -> { after-dispatch_state }| ).
    console->write( |DELTA AttemptCount  { before-attempt_count } -> { after-attempt_count }| ).
    console->write( |DELTA Header Status { header_before-status } -> { header_final-status }| ).
    console->write( |DELTA Integration   { header_before-integration_status } -> { header_final-integration_status }| ).

    " ---------- 7. ASSERTIONS - REPORT ONLY, NEVER A SECOND SEND ----------
    IF outcome-dispatched = abap_false.
      stop( |nothing was dispatched; skip_reason { outcome-skip_reason }. This harness does NOT try again.| ).
      RETURN.
    ENDIF.
    IF after-attempt_count <> 2.
      stop( |AttemptCount is { after-attempt_count }, expected 2. Investigate; this harness does NOT send again.| ).
      RETURN.
    ENDIF.
    IF outcome-attempt_count <> after-attempt_count.
      stop( |the reported attempt count { outcome-attempt_count } does not match the persisted { after-attempt_count }.| ).
      RETURN.
    ENDIF.
    " The identity that must survive a replay.
    IF after-delivery_uuid <> fixture_delivery_uuid.
      stop( 'the replay minted a new delivery identity.' ).
      RETURN.
    ENDIF.
    IF after-purchase_order_uuid <> fixture_order_uuid.
      stop( 'the replay changed the owning order.' ).
      RETURN.
    ENDIF.
    IF after-order_revision <> before-order_revision.
      stop( 'the replay changed OrderRevision.' ).
      RETURN.
    ENDIF.
    IF after-payload_snapshot <> before-payload_snapshot.
      stop( 'the replay changed the PayloadSnapshot.' ).
      RETURN.
    ENDIF.
    IF after-payload_hash <> before-payload_hash.
      stop( 'the replay changed the PayloadHash.' ).
      RETURN.
    ENDIF.
    " A retry gets a NEW correlation id while the delivery identity does not.
    IF after-last_correlation_id IS INITIAL.
      stop( 'no correlation id was persisted for the second attempt.' ).
      RETURN.
    ENDIF.
    IF after-last_correlation_id = fixture_first_correlation.
      stop( 'the second attempt reused the first attempt correlation id.' ).
      RETURN.
    ENDIF.
    IF after-dispatch_state <> state_delivered.
      stop( |DispatchState is { after-dispatch_state }, not DELIVERED. | &&
            |The intent keeps its identity and stays replayable; this harness does NOT send again.| ).
      RETURN.
    ENDIF.
    IF after-portal_order_uuid IS INITIAL.
      stop( 'no PortalOrderUUID was persisted; inspect the receipt before using this fixture inbound.' ).
      RETURN.
    ENDIF.
    IF header_final-status <> status_sent.
      stop( |the header is { header_final-status }, not SENT.| ).
      RETURN.
    ENDIF.
    IF header_final-integration_status <> state_delivered.
      stop( |the header IntegrationStatus is { header_final-integration_status }, not DELIVERED.| ).
      RETURN.
    ENDIF.
    IF header_final-delivery_id <> fixture_delivery_uuid.
      stop( 'the header DeliveryId changed across the replay.' ).
      RETURN.
    ENDIF.

    console->write( '' ).
    console->write( 'PASS: same delivery identity, AttemptCount 1 -> 2, fresh correlation,' ).
    console->write( 'snapshot and hash unchanged, intent DELIVERED, header ERROR -> SENT.' ).
    console->write( 'Inspect the PortalOrderUUID above: it must be 32 hex characters and must NOT' ).
    console->write( 'stop at the first lowercase letter of the CAP portalOrderId.' ).

  ENDMETHOD.


  METHOD read_header.

    CLEAR row.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        FIELDS ( PurchaseOrderUUID PurchaseOrderNumber Status Supplier
                 OrderRevision IntegrationStatus DeliveryId LastCorrelationId )
        WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                        PurchaseOrderUUID = fixture_order_uuid ) )
        RESULT DATA(orders)
      FAILED DATA(failed_read).

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1.
      RETURN.
    ENDIF.

    row-found                 = abap_true.
    row-purchase_order_uuid   = orders[ 1 ]-PurchaseOrderUUID.
    row-purchase_order_number = orders[ 1 ]-PurchaseOrderNumber.
    row-status                = orders[ 1 ]-Status.
    row-supplier              = orders[ 1 ]-Supplier.
    row-order_revision        = orders[ 1 ]-OrderRevision.
    row-integration_status    = orders[ 1 ]-IntegrationStatus.
    row-delivery_id           = orders[ 1 ]-DeliveryId.
    row-last_correlation_id   = orders[ 1 ]-LastCorrelationId.

  ENDMETHOD.


  METHOD report_header.
    console->write( |{ label } number={ row-purchase_order_number } status={ row-status } | &&
                    |integration={ row-integration_status } rev={ row-order_revision } | &&
                    |supplier={ row-supplier }| ).
    console->write( name = |{ label } PurchaseOrderUUID| data = row-purchase_order_uuid ).
    console->write( name = |{ label } DeliveryId|        data = row-delivery_id ).
    console->write( name = |{ label } LastCorrelationId| data = row-last_correlation_id ).
  ENDMETHOD.


  METHOD intent_row.

    CLEAR row.

    SELECT SINGLE delivery_uuid, purchase_order_uuid, order_revision,
                  dispatch_state, attempt_count, last_correlation_id,
                  portal_order_uuid, lease_owner, lease_expires_at,
                  payload_hash, payload_snapshot
      FROM zjp_po_dlv
      WHERE delivery_uuid = @fixture_delivery_uuid
      INTO CORRESPONDING FIELDS OF @row.

    row-found = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD report_intent.
    console->write( |{ label } DispatchState={ row-dispatch_state } AttemptCount={ row-attempt_count } | &&
                    |OrderRevision={ row-order_revision } SnapshotChars={ strlen( row-payload_snapshot ) } | &&
                    |PayloadHash={ row-payload_hash }| ).
    console->write( name = |{ label } DeliveryUUID|      data = row-delivery_uuid ).
    console->write( name = |{ label } PurchaseOrderUUID| data = row-purchase_order_uuid ).
    console->write( name = |{ label } LastCorrelationId| data = row-last_correlation_id ).
    console->write( name = |{ label } PortalOrderUUID|   data = row-portal_order_uuid ).
    console->write( name = |{ label } LeaseOwner|        data = row-lease_owner ).
  ENDMETHOD.


  METHOD stop.
    console->write( |STOP: { text }| ).
  ENDMETHOD.


  METHOD save_all.
    " COMMIT ENTITIES commits the whole LUW; RESPONSE OF only chooses whose
    " failures are surfaced.
    COMMIT ENTITIES RESPONSE OF ZJP_I_DeliveryIntent
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.

    success = xsdbool( save_subrc = 0 AND failed_save IS INITIAL ).
    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( name = 'COMMIT sy-subrc' data = save_subrc ).
      console->write( name = 'Save FAILED'     data = failed_save ).
      console->write( 'Save did not succeed; buffer rolled back. Nothing was sent.' ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
