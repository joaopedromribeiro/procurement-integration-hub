" Phase 7.3. A narrow operator runner for ONE delivery, and nothing else.
"
" It exists because the production sequence "submit, approve, request delivery,
" then dispatch it" has no standalone entry point. `sendToSupplier` is declared
" only on the base behaviour ZJP_I_PurchaseOrder and is exposed by neither
" projection, so it is reachable only through EML; and `run_once` is public on
" the coordinator but was called from nowhere except ZJP_CL_PO_DISPATCH_TEST,
" whose class-run executes nine scenarios and three real HTTP sends with no
" selector.
"
" REVISION. The first version started from an APPROVED order, on the assumption
" that submit and approve would be driven from the Fiori Elements preview. The
" preview does not render those actions, so the runner now drives the whole
" business lifecycle itself: DRAFT -> submit -> SUBMITTED -> approve ->
" APPROVED -> sendToSupplier -> PENDING intent -> one dispatch. Each step is the
" SAME EML call ZJP_CL_PO_DISPATCH_TEST's make_fixture already uses, in the same
" order, with a commit between each.
"
" ONE execution of this class performs AT MOST ONE real HTTP POST. submit,
" approve and sendToSupplier are SAP transactions and issue no HTTP at all; the
" only external call is the single coordinator->run_once below. There is no
" loop, no retry, no second run_once and no scenario suite.
"
" It deliberately does NOT call find_eligible for the dispatch. find_eligible
" returns the oldest eligible row in the whole table, which could be an
" unrelated intent; this runner dispatches only the DeliveryUUID created for the
" PurchaseOrderUUID it selected, and passes it explicitly.
CLASS zjp_cl_dispatch_runner DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " The Integration Suite destination, the same one ZJP_CL_PO_DISPATCH_TEST
    " uses. Host, port, TLS and OAuth live there and its Path Prefix is EMPTY,
    " so the coordinator supplies the whole application route. No credential and
    " no destination configuration is introduced here.
    CONSTANTS destination TYPE rfcdest VALUE 'ZJP_CI_ORDER_DELIVERY'.

    " The SAME injected value ZJP_CL_PO_DISPATCH_TEST uses, and still NOT a
    " production default: Phase 5.2g introduced no lease timeout and no
    " configuration object, and this runner introduces neither.
    CONSTANTS lease_seconds TYPE i VALUE 300.

    " A DEPLOYED PREREQUISITE of the CAP portal rather than a preference. The
    " first real run used SUP041 and the portal answered HTTP 400
    " UNKNOWN_SUPPLIER, correctly: production CAP HANA carries no local fixture
    " data. If RTTEST001 is missing or inactive the fix is to restore it.
    CONSTANTS runtime_supplier TYPE zjp_po_h-supplier VALUE 'RTTEST001'.

    " The expected fixture shape, mirroring make_fixture exactly.
    CONSTANTS fixture_company  TYPE zjp_po_h-company_code VALUE '1000'.
    CONSTANTS fixture_currency TYPE zjp_po_h-currency     VALUE 'EUR'.
    CONSTANTS fixture_total    TYPE string VALUE '1500.00'.
    CONSTANTS fixture_item     TYPE string VALUE '00010'.
    CONSTANTS fixture_material TYPE string VALUE 'MAT001'.
    CONSTANTS fixture_uom      TYPE string VALUE 'EA'.
    CONSTANTS fixture_price    TYPE string VALUE '750.00'.

    CONSTANTS status_draft     TYPE string VALUE 'DRAFT'.
    CONSTANTS status_submitted TYPE string VALUE 'SUBMITTED'.
    CONSTANTS status_approved  TYPE string VALUE 'APPROVED'.
    CONSTANTS state_pending    TYPE string VALUE 'PENDING'.
    CONSTANTS integration_fresh TYPE string VALUE 'NOT_REQUESTED'.

    TYPES:
      BEGIN OF ty_header,
        found                 TYPE abap_bool,
        purchase_order_uuid   TYPE zjp_po_h-purchase_order_uuid,
        purchase_order_number TYPE zjp_po_h-purchase_order_number,
        status                TYPE zjp_po_h-status,
        supplier              TYPE zjp_po_h-supplier,
        company_code          TYPE zjp_po_h-company_code,
        currency              TYPE zjp_po_h-currency,
        total_amount          TYPE zjp_po_h-total_amount,
        order_revision        TYPE zjp_po_h-order_revision,
        integration_status    TYPE zjp_po_h-integration_status,
        delivery_id           TYPE zjp_po_h-delivery_id,
        last_correlation_id   TYPE zjp_po_h-last_correlation_id,
      END OF ty_header.

    TYPES:
      BEGIN OF ty_intent,
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

    " The selection gate. Returns an initial UUID and explains itself whenever
    " the choice is not unambiguous.
    METHODS select_candidate
      RETURNING VALUE(order_uuid) TYPE sysuuid_x16.

    " Reads the ACTIVE instance through EML, never the draft one.
    METHODS read_header
      IMPORTING order_uuid TYPE sysuuid_x16
      RETURNING VALUE(row) TYPE ty_header.

    METHODS report_header
      IMPORTING label TYPE string
                row   TYPE ty_header.

    METHODS intent_row
      IMPORTING delivery_uuid TYPE sysuuid_x16
      RETURNING VALUE(row)    TYPE ty_intent.

    " Read-only reporting. The snapshot is never printed, only measured.
    METHODS report_intent
      IMPORTING label TYPE string
                row   TYPE ty_intent.

ENDCLASS.


CLASS zjp_cl_dispatch_runner IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write( '=== Phase 7.3 - single delivery dispatch runner ===' ).
    out->write( '*** THIS CLASS MAKES AT MOST ONE REAL HTTP POST through Integration Suite ***' ).
    out->write( |*** over destination { destination }, reaching the CAP portal downstream. ***| ).
    out->write( 'It drives DRAFT -> submit -> approve -> sendToSupplier -> ONE dispatch.' ).
    out->write( 'submit, approve and sendToSupplier issue NO HTTP. Only run_once does.' ).
    out->write( 'It creates no order, runs no scenario suite, and never retries.' ).
    out->write( |Injected lease_seconds = { lease_seconds } (runtime value, not a default).| ).
    out->write( '' ).

    " ---------- 1. SELECTION ----------
    DATA(order_uuid) = select_candidate( ).
    IF order_uuid IS INITIAL.
      RETURN.
    ENDIF.

    " The %tky is taken ONCE from the active instance and reused for every
    " action, exactly as make_fixture does. It survives the commits between
    " steps, because the key is the UUID plus the draft indicator.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        FIELDS ( PurchaseOrderUUID Status )
        WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                        PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(orders)
      ENTITY PurchaseOrder BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                        PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(items)
      FAILED DATA(failed_read).

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1.
      stop( 'the selected order could not be read as an ACTIVE instance; nothing was changed.' ).
      RETURN.
    ENDIF.

    DATA(order_key) = orders[ 1 ]-%tky.

    " ---------- 2. FIXTURE CONTENT GATE ----------
    " Cheap, read-only, and it runs BEFORE the first mutation. It is not a
    " substitute for the exactly-one-candidate rule above; it is a second
    " witness that the order in hand is the one that was created for this run.
    DATA(before_header) = read_header( order_uuid ).
    IF before_header-found = abap_false.
      stop( 'the active header could not be read; nothing was changed.' ).
      RETURN.
    ENDIF.
    report_header( label = 'SELECTED' row = before_header ).

    IF before_header-status <> status_draft.
      stop( |the selected order is { before_header-status }, not DRAFT; nothing was changed.| ).
      RETURN.
    ENDIF.
    IF before_header-supplier <> runtime_supplier.
      stop( |the selected order supplier is { before_header-supplier }, not { runtime_supplier }.| ).
      RETURN.
    ENDIF.
    IF before_header-purchase_order_number IS NOT INITIAL.
      stop( 'the selected order already carries a PurchaseOrderNumber; it is not a fresh DRAFT.' ).
      RETURN.
    ENDIF.
    IF before_header-delivery_id IS NOT INITIAL.
      stop( 'the selected order already carries a DeliveryId; nothing was changed.' ).
      RETURN.
    ENDIF.
    IF before_header-integration_status <> integration_fresh.
      stop( |IntegrationStatus is { before_header-integration_status }, not { integration_fresh }.| ).
      RETURN.
    ENDIF.
    IF before_header-company_code <> fixture_company.
      stop( |CompanyCode is { before_header-company_code }, not { fixture_company }.| ).
      RETURN.
    ENDIF.
    IF before_header-currency <> fixture_currency.
      stop( |Currency is { before_header-currency }, not { fixture_currency }.| ).
      RETURN.
    ENDIF.
    IF before_header-total_amount <> fixture_total.
      stop( |TotalAmount is { before_header-total_amount }, not { fixture_total }.| ).
      RETURN.
    ENDIF.

    IF lines( items ) <> 1.
      stop( |expected exactly one item, found { lines( items ) }; nothing was changed.| ).
      RETURN.
    ENDIF.
    DATA(item) = items[ 1 ].
    console->write( |ITEM { item-ItemNumber } { item-Material } qty { item-Quantity } | &&
                    |{ item-UnitOfMeasure } @ { item-NetPrice } { item-Currency }| ).

    IF item-ItemNumber <> fixture_item OR item-Material <> fixture_material
       OR item-UnitOfMeasure <> fixture_uom OR item-Currency <> fixture_currency
       OR item-Quantity <> 2 OR item-NetPrice <> fixture_price.
      stop( 'the single item does not match the intended fixture; nothing was changed.' ).
      RETURN.
    ENDIF.

    " ---------- 3. submit - SAP ONLY, NO HTTP ----------
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_submit)
      REPORTED DATA(reported_submit).

    IF failed_submit IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( name = 'submit FAILED'   data = failed_submit ).
      console->write( name = 'submit REPORTED' data = reported_submit ).
      stop( 'submit was refused; nothing was committed and nothing was sent.' ).
      RETURN.
    ENDIF.

    IF save_all( ) = abap_false.
      stop( 'submit could not be committed; nothing was sent.' ).
      RETURN.
    ENDIF.

    DATA(after_submit) = read_header( order_uuid ).
    report_header( label = 'AFTER submit' row = after_submit ).

    IF after_submit-found = abap_false.
      stop( 'the order could not be re-read after submit; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_submit-status <> status_submitted.
      stop( |after submit the order is { after_submit-status }, not SUBMITTED. NO approve, NO send.| ).
      RETURN.
    ENDIF.
    " submit is the ONLY point in the lifecycle that draws a number.
    IF after_submit-purchase_order_number IS INITIAL.
      stop( 'submit drew no PurchaseOrderNumber. NO approve, NO send.' ).
      RETURN.
    ENDIF.
    IF after_submit-delivery_id IS NOT INITIAL.
      stop( 'submit unexpectedly assigned a DeliveryId. NO approve, NO send.' ).
      RETURN.
    ENDIF.
    IF after_submit-integration_status <> integration_fresh.
      stop( |submit moved IntegrationStatus to { after_submit-integration_status }. NO approve, NO send.| ).
      RETURN.
    ENDIF.

    " ---------- 4. approve - SAP ONLY, NO HTTP ----------
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_approve)
      REPORTED DATA(reported_approve).

    IF failed_approve IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( name = 'approve FAILED'   data = failed_approve ).
      console->write( name = 'approve REPORTED' data = reported_approve ).
      stop( 'approve was refused; nothing was committed and nothing was sent.' ).
      RETURN.
    ENDIF.

    IF save_all( ) = abap_false.
      stop( 'approve could not be committed; nothing was sent.' ).
      RETURN.
    ENDIF.

    DATA(after_approve) = read_header( order_uuid ).
    report_header( label = 'AFTER approve' row = after_approve ).

    IF after_approve-found = abap_false.
      stop( 'the order could not be re-read after approve; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_approve-status <> status_approved.
      stop( |after approve the order is { after_approve-status }, not APPROVED. NO send.| ).
      RETURN.
    ENDIF.
    IF after_approve-purchase_order_number <> after_submit-purchase_order_number.
      stop( 'the PurchaseOrderNumber changed across approve. NO send.' ).
      RETURN.
    ENDIF.
    IF after_approve-delivery_id IS NOT INITIAL.
      stop( 'approve unexpectedly assigned a DeliveryId. NO send.' ).
      RETURN.
    ENDIF.
    IF after_approve-integration_status <> integration_fresh.
      stop( |approve moved IntegrationStatus to { after_approve-integration_status }. NO send.| ).
      RETURN.
    ENDIF.

    " ---------- 5. sendToSupplier - SAP ONLY, NO HTTP ----------
    " This action creates the durable intent and marks the header. It performs
    " no HTTP, no COMMIT and no ROLLBACK; transaction completion is this
    " caller's job, which is why the commit is a separate step below.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE sendToSupplier FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_send)
      REPORTED DATA(reported_send).

    IF failed_send IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( name = 'sendToSupplier FAILED'   data = failed_send ).
      console->write( name = 'sendToSupplier REPORTED' data = reported_send ).
      stop( 'sendToSupplier was refused; nothing was committed and nothing was sent.' ).
      RETURN.
    ENDIF.

    " The coordinator re-reads the intent from the DATABASE, so the intent must
    " be committed before run_once or read_intent would find nothing.
    IF save_all( ) = abap_false.
      stop( 'the delivery intent could not be committed; nothing was sent.' ).
      RETURN.
    ENDIF.

    " ---------- 6. LOCATE THE ONE NEW INTENT ----------
    SELECT delivery_uuid, dispatch_state
      FROM zjp_po_dlv
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(intents).

    IF lines( intents ) <> 1.
      stop( |expected exactly one delivery intent for this order, found { lines( intents ) }; nothing was sent.| ).
      RETURN.
    ENDIF.

    DATA(delivery_uuid) = intents[ 1 ]-delivery_uuid.

    DATA(after_request) = read_header( order_uuid ).
    report_header( label = 'AFTER sendToSupplier' row = after_request ).

    IF after_request-found = abap_false.
      stop( 'the order could not be re-read after sendToSupplier; nothing was sent.' ).
      RETURN.
    ENDIF.
    " Two independent reads agreeing is what rules out dispatching something
    " this run did not create.
    IF after_request-delivery_id <> delivery_uuid.
      stop( 'the header DeliveryId does not match the created intent; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF after_request-integration_status <> state_pending.
      stop( |IntegrationStatus is { after_request-integration_status }, not PENDING; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF after_request-status <> status_approved.
      stop( |the order is { after_request-status }, not APPROVED; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF after_request-purchase_order_number <> after_submit-purchase_order_number.
      stop( 'the PurchaseOrderNumber changed across sendToSupplier; nothing was sent.' ).
      RETURN.
    ENDIF.

    " ---------- 7. PRE-NETWORK GATES ----------
    DATA(before) = intent_row( delivery_uuid ).
    report_intent( label = 'BEFORE' row = before ).

    " Informational only. It cannot affect this run, because run_once is given
    " an explicit DeliveryUUID and never consults find_eligible for it.
    SELECT COUNT( * ) FROM zjp_po_dlv
      WHERE dispatch_state = @state_pending
      INTO @DATA(pending_total).
    console->write( |PENDING intents in table: { pending_total } (not a gate; this run targets one explicit DeliveryUUID)| ).

    IF before-delivery_uuid IS INITIAL.
      stop( 'the intent has no DeliveryUUID; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF before-purchase_order_uuid <> order_uuid.
      stop( 'the intent belongs to a different order; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF before-dispatch_state <> state_pending.
      stop( |the intent is { before-dispatch_state }, not PENDING; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF before-attempt_count <> 0.
      stop( |the intent already has AttemptCount { before-attempt_count }; nothing was sent.| ).
      RETURN.
    ENDIF.
    IF before-portal_order_uuid IS NOT INITIAL.
      stop( 'the intent already carries a PortalOrderUUID; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF before-last_correlation_id IS NOT INITIAL.
      stop( 'the intent already carries a correlation id; nothing was sent.' ).
      RETURN.
    ENDIF.
    IF before-lease_owner IS NOT INITIAL OR before-lease_expires_at IS NOT INITIAL.
      stop( 'the intent advertises a lease; another run may hold it. Nothing was sent.' ).
      RETURN.
    ENDIF.
    " Without a snapshot run_once takes the EMPTY_SNAPSHOT branch, which sends
    " nothing and proves nothing. Stopping here saves a wasted fixture.
    IF before-payload_snapshot IS INITIAL.
      stop( 'the intent has no PayloadSnapshot; nothing was sent.' ).
      RETURN.
    ENDIF.

    " ---------- 8. THE SINGLE REAL SEND ----------
    console->write( '' ).
    console->write( 'All pre-network gates passed. Dispatching EXACTLY ONE request.' ).

    " Declared and assigned SEPARATELY rather than constructed inline: the SAP
    " parser rejected the nested NEW form in this context in Phase 5.2g, and the
    " split also keeps the seam visible.
    DATA real_transport TYPE REF TO zjp_if_outbound_transport.

    real_transport = NEW zjp_cl_outbound_transport( destination_name = destination ).

    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = real_transport
      lease_seconds = lease_seconds ).

    " EXACTLY ONCE, with an EXPLICIT DeliveryUUID. No loop. No retry.
    DATA(outcome) = coordinator->run_once( delivery_uuid ).

    " ---------- 9. EVIDENCE ----------
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

    DATA(after) = intent_row( delivery_uuid ).
    report_intent( label = 'AFTER' row = after ).

    DATA(final_header) = read_header( order_uuid ).
    report_header( label = 'FINAL' row = final_header ).

    console->write( '' ).
    console->write( |DELTA Status        { before_header-status } -> { final_header-status }| ).
    console->write( |DELTA Integration   { before_header-integration_status } -> { final_header-integration_status }| ).
    console->write( |DELTA DispatchState { before-dispatch_state } -> { after-dispatch_state }| ).
    console->write( |DELTA AttemptCount  { before-attempt_count } -> { after-attempt_count }| ).

    " ---------- 10. ASSERTIONS - REPORT ONLY, NEVER A SECOND SEND ----------
    IF outcome-dispatched = abap_false.
      stop( |nothing was dispatched; skip_reason { outcome-skip_reason }. This runner does NOT try again.| ).
      RETURN.
    ENDIF.
    IF after-attempt_count <> 1.
      stop( |AttemptCount is { after-attempt_count }, expected 1. Investigate; this runner does NOT send again.| ).
      RETURN.
    ENDIF.
    IF outcome-attempt_count <> after-attempt_count.
      stop( |the reported attempt count { outcome-attempt_count } does not match the persisted { after-attempt_count }.| ).
      RETURN.
    ENDIF.
    IF after-dispatch_state <> 'DELIVERED'.
      stop( |DispatchState is { after-dispatch_state }, not DELIVERED. The intent keeps its identity and stays replayable.| ).
      RETURN.
    ENDIF.
    IF after-last_correlation_id IS INITIAL.
      stop( 'no correlation id was persisted.' ).
      RETURN.
    ENDIF.
    IF after-portal_order_uuid IS INITIAL.
      stop( 'no PortalOrderUUID was persisted; inspect the receipt before using this fixture inbound.' ).
      RETURN.
    ENDIF.
    IF final_header-status <> 'SENT'.
      stop( |the header is { final_header-status }, not SENT.| ).
      RETURN.
    ENDIF.
    IF final_header-integration_status <> 'DELIVERED'.
      stop( |the header IntegrationStatus is { final_header-integration_status }, not DELIVERED.| ).
      RETURN.
    ENDIF.

    console->write( '' ).
    console->write( 'PASS: DRAFT -> SUBMITTED -> APPROVED -> SENT, one dispatched attempt,' ).
    console->write( 'AttemptCount 0 -> 1, intent DELIVERED.' ).
    console->write( 'Inspect the PortalOrderUUID above: it must be 32 hex characters and must NOT' ).
    console->write( 'stop at the first lowercase letter of the CAP portalOrderId.' ).

  ENDMETHOD.


  METHOD select_candidate.

    CLEAR order_uuid.

    " ZJP_PO_H holds ACTIVE instances only. A Fiori order still open as a
    " technical draft lives in the generated draft table and is invisible here,
    " which is exactly what is wanted: submit refuses a draft instance, and this
    " runner must never try to activate one.
    "
    " Status and Supplier narrow the set. The strong discriminators are applied
    " per row below rather than in SQL, because this class deliberately uses
    " only statement shapes this project has already activated - no NOT EXISTS
    " subquery appears anywhere in this repository.
    SELECT purchase_order_uuid, purchase_order_number, order_revision,
           status, supplier, company_code, currency, total_amount,
           integration_status, delivery_id, created_at
      FROM zjp_po_h
      WHERE status   = @status_draft
        AND supplier = @runtime_supplier
      ORDER BY created_at
      INTO TABLE @DATA(header_rows).

    IF lines( header_rows ) = 0.
      stop( |no ACTIVE { runtime_supplier } order in status DRAFT exists. | &&
            |Create one in Fiori and SAVE it, so it becomes an active instance rather than a technical draft.| ).
      RETURN.
    ENDIF.

    DATA candidates TYPE STANDARD TABLE OF sysuuid_x16.

    LOOP AT header_rows INTO DATA(header).

      " submit is the ONLY point in the lifecycle that draws a number, so a
      " DRAFT that already carries one is not a fresh order.
      IF header-purchase_order_number IS NOT INITIAL.
        console->write( |SKIP - a DRAFT already carrying PurchaseOrderNumber { header-purchase_order_number }| ).
        CONTINUE.
      ENDIF.

      " DeliveryId is written in exactly ONE place in the whole behaviour pool -
      " sendToSupplier - so a filled DeliveryId means delivery was already
      " requested for this order.
      IF header-delivery_id IS NOT INITIAL.
        console->write( 'SKIP - a DRAFT with a DeliveryId already assigned' ).
        CONTINUE.
      ENDIF.

      " A newly created root is determined to NOT_REQUESTED; only sendToSupplier
      " and recordDeliveryResult move it onwards.
      IF header-integration_status <> integration_fresh.
        console->write( |SKIP - IntegrationStatus { header-integration_status }| ).
        CONTINUE.
      ENDIF.

      " The intended fixture shape, as a cheap extra witness.
      IF header-company_code <> fixture_company OR header-currency <> fixture_currency
         OR header-total_amount <> fixture_total.
        console->write( |SKIP - not the intended fixture shape | &&
                        |({ header-company_code }/{ header-currency }/{ header-total_amount })| ).
        CONTINUE.
      ENDIF.

      " And no intent may exist for it in ANY revision. This is the same
      " read-only SELECT shape sendToSupplier itself uses.
      SELECT SINGLE delivery_uuid, dispatch_state
        FROM zjp_po_dlv
        WHERE purchase_order_uuid = @header-purchase_order_uuid
        INTO @DATA(existing_intent).

      IF sy-subrc = 0.
        console->write( |SKIP - an intent already exists ({ existing_intent-dispatch_state })| ).
        CONTINUE.
      ENDIF.

      console->write( |CANDIDATE rev { header-order_revision } total { header-total_amount } { header-currency }| ).
      console->write( name = 'CANDIDATE PurchaseOrderUUID' data = header-purchase_order_uuid ).
      APPEND header-purchase_order_uuid TO candidates.

    ENDLOOP.

    IF lines( candidates ) = 0.
      stop( |no fresh DRAFT candidate survived the safety conditions; see the SKIP lines above.| ).
      RETURN.
    ENDIF.

    IF lines( candidates ) > 1.
      " Deliberately refuses to choose. Picking "the newest" here would be the
      " same guess find_eligible makes, and the point of this runner is not to
      " guess which business order goes on the wire.
      stop( |selection is ambiguous: { lines( candidates ) } fresh DRAFT candidates listed above. | &&
            |Cancel or complete the extras first; this runner will not choose.| ).
      RETURN.
    ENDIF.

    order_uuid = candidates[ 1 ].

  ENDMETHOD.


  METHOD read_header.

    CLEAR row.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        FIELDS ( PurchaseOrderUUID PurchaseOrderNumber Status Supplier
                 CompanyCode Currency TotalAmount OrderRevision
                 IntegrationStatus DeliveryId LastCorrelationId )
        WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                        PurchaseOrderUUID = order_uuid ) )
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
    row-company_code          = orders[ 1 ]-CompanyCode.
    row-currency              = orders[ 1 ]-Currency.
    row-total_amount          = orders[ 1 ]-TotalAmount.
    row-order_revision        = orders[ 1 ]-OrderRevision.
    row-integration_status    = orders[ 1 ]-IntegrationStatus.
    row-delivery_id           = orders[ 1 ]-DeliveryId.
    row-last_correlation_id   = orders[ 1 ]-LastCorrelationId.

  ENDMETHOD.


  METHOD report_header.
    console->write( |{ label } number={ row-purchase_order_number } status={ row-status } | &&
                    |integration={ row-integration_status } rev={ row-order_revision } | &&
                    |supplier={ row-supplier } total={ row-total_amount } { row-currency }| ).
    console->write( name = |{ label } PurchaseOrderUUID| data = row-purchase_order_uuid ).
    console->write( name = |{ label } DeliveryId|        data = row-delivery_id ).
    console->write( name = |{ label } LastCorrelationId| data = row-last_correlation_id ).
  ENDMETHOD.


  METHOD intent_row.
    SELECT SINGLE delivery_uuid, purchase_order_uuid, order_revision,
                  dispatch_state, attempt_count, last_correlation_id,
                  portal_order_uuid, lease_owner, lease_expires_at,
                  payload_hash, payload_snapshot
      FROM zjp_po_dlv
      WHERE delivery_uuid = @delivery_uuid
      INTO CORRESPONDING FIELDS OF @row.
  ENDMETHOD.


  METHOD report_intent.
    " The snapshot is measured, never printed: it is the full business payload
    " and the console is not where it belongs.
    console->write( |{ label } DispatchState={ row-dispatch_state } AttemptCount={ row-attempt_count } | &&
                    |OrderRevision={ row-order_revision } SnapshotChars={ strlen( row-payload_snapshot ) }| ).
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
    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
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
