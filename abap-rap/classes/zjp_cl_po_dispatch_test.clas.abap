" The coordinator harness, object 11 of the Phase 5.1 section 10 inventory:
" "the coordinator, run explicitly; claim, dispatch, record, commit". Reserved
" for this purpose since Phase 5.2c, built in Phase 5.2g, and cut over to
" Integration Suite in Phase 6.4.
"
" *** THIS CLASS MAKES REAL NETWORK CALLS. Test E posts through Integration Suite
" *** over destination ZJP_CI_ORDER_DELIVERY and reaches the CAP Supplier Portal
" *** downstream.
" *** Every other test drives the deterministic fake and touches no network.
" *** Nothing here runs unless you press F9 deliberately.
"
" WHY THE COORDINATOR IS A SEPARATE CLASS FROM THIS ONE. ZJP_CL_DISPATCH_COORDINATOR
" holds the claim/dispatch/record contract and takes its transport through the
" verified seam; this class supplies fixtures, chooses which transport goes in,
" and asserts. Folding the two together would make the only runnable coordinator
" the one that always calls the network, so the lease contract, the reconstruction
" and three of the four classification branches could not be exercised at all -
" and it would repeat the mistake the builder/builder-test and transport/fake
" split was drawn to avoid.
"
" TEST RESIDUE IS DELIBERATE, as it is for ZJP_CL_PO_EML_TEST. A full run leaves
" several orders in terminal states with their intents, and consumes order
" numbers. Terminal orders are not physically deletable and a consumed number is
" never reused.
CLASS zjp_cl_po_dispatch_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " The Integration Suite destination. Host, port 443, TLS and OAuth 2.0 client
    " credentials live there, and its Path Prefix is EMPTY so that the coordinator
    " supplies the whole application route.
    "
    " ZJP_CL_HTTP_TRANSPORT_TEST remains the Phase 5 direct-to-CAP harness and
    " keeps that path runnable and verifiable alongside this one.
    CONSTANTS destination TYPE rfcdest VALUE 'ZJP_CI_ORDER_DELIVERY'.

    " An INJECTED test value, not a production timeout. Phase 5.2g introduces no
    " lease default and no configuration object.
    CONSTANTS lease_seconds TYPE i VALUE 300.

    TYPES:
      BEGIN OF ty_fixture,
        order_uuid    TYPE sysuuid_x16,
        delivery_uuid TYPE sysuuid_x16,
      END OF ty_fixture.

    TYPES:
      BEGIN OF ty_intent,
        delivery_uuid     TYPE zjp_po_dlv-delivery_uuid,
        order_revision    TYPE zjp_po_dlv-order_revision,
        dispatch_state    TYPE zjp_po_dlv-dispatch_state,
        payload_snapshot  TYPE zjp_po_dlv-payload_snapshot,
        payload_hash      TYPE zjp_po_dlv-payload_hash,
        approved_by       TYPE zjp_po_dlv-approved_by,
        approved_at       TYPE zjp_po_dlv-approved_at,
        last_correlation_id TYPE zjp_po_dlv-last_correlation_id,
        portal_order_uuid TYPE zjp_po_dlv-portal_order_uuid,
        lease_owner       TYPE zjp_po_dlv-lease_owner,
        lease_expires_at  TYPE zjp_po_dlv-lease_expires_at,
      END OF ty_intent.

    TYPES:
      BEGIN OF ty_header,
        status              TYPE zjp_po_h-status,
        integration_status  TYPE zjp_po_h-integration_status,
        delivery_id         TYPE zjp_po_h-delivery_id,
        last_correlation_id TYPE zjp_po_h-last_correlation_id,
        last_error_code     TYPE zjp_po_h-last_error_code,
        last_error_message  TYPE zjp_po_h-last_error_message,
      END OF ty_header.

    METHODS stop
      IMPORTING text TYPE string.

    METHODS save_all
      RETURNING VALUE(success) TYPE abap_bool.

    " One approved order with one durable PENDING intent, through the production
    " path only: create, submit, approve, sendToSupplier. No direct SQL anywhere.
    METHODS make_fixture
      IMPORTING supplier       TYPE zjp_po_h-supplier
      RETURNING VALUE(fixture) TYPE ty_fixture.

    " Read-only verification. What the buffer reports and what the database holds
    " are different claims, and only the second survives a commit.
    METHODS intent_row
      IMPORTING delivery_uuid TYPE sysuuid_x16
      RETURNING VALUE(row)    TYPE ty_intent.

    METHODS header_row
      IMPORTING order_uuid TYPE sysuuid_x16
      RETURNING VALUE(row) TYPE ty_header.

    " Test-only state setup, through EML exactly like the production path. No
    " INSERT, UPDATE or DELETE is issued against ZJP_PO_DLV anywhere in this class.
    METHODS force_lease_expiry
      IMPORTING delivery_uuid  TYPE sysuuid_x16
                expiry         TYPE zjp_po_dlv-lease_expires_at
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS force_dispatch_state
      IMPORTING delivery_uuid  TYPE sysuuid_x16
                state          TYPE string
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS golden_snapshot_body
      RETURNING VALUE(body) TYPE string.

    METHODS test_d_reconstruction
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_abc_lease
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_e_real_delivery
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_f_replay_and_immutable
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_g_conflict
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_h_unanswered_and_corr
      RETURNING VALUE(success) TYPE abap_bool.

ENDCLASS.


CLASS zjp_cl_po_dispatch_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write( '=== Phase 6.4 - dispatch coordinator through Integration Suite ===' ).
    out->write( '*** TEST E MAKES A REAL HTTP POST through Integration Suite ***' ).
    out->write( |*** over destination { destination }, reaching the CAP portal downstream. ***| ).
    out->write( '*** Tests A-D and F-J use the network-free fake. ***' ).
    out->write( |Injected lease_seconds = { lease_seconds } (test value, not a default).| ).
    out->write( '' ).

    IF test_d_reconstruction( ) = abap_false.
      RETURN.
    ENDIF.
    IF test_abc_lease( ) = abap_false.
      RETURN.
    ENDIF.
    IF test_e_real_delivery( ) = abap_false.
      RETURN.
    ENDIF.
    IF test_f_replay_and_immutable( ) = abap_false.
      RETURN.
    ENDIF.
    IF test_g_conflict( ) = abap_false.
      RETURN.
    ENDIF.
    IF test_h_unanswered_and_corr( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( '' ).
    out->write( 'PASS: Phase 6.4 dispatch coordinator through Integration Suite verified.' ).

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
      console->write( name = 'Save FAILED' data = failed_save ).
      console->write( 'Save did not succeed; buffer rolled back.' ).
    ENDIF.
  ENDMETHOD.


  METHOD golden_snapshot_body.
    " The Phase 5.2f golden source snapshot, byte-identical to the fixture in
    " ZJP_CL_BUILDER_TEST. Concatenated because a text literal caps at 255
    " characters and a CONSTANTS VALUE must be a single literal.
    body = '{"schemaVersion":"1.0","deliveryId":"00000000-0000-0000-0000-000000000001",'
        && '"sourceSystem":"PIH_ABAP_DEV","purchaseOrderId":"00000000-0000-0000-0000-000000000002",'
        && '"revision":1,"purchaseOrder":"PO00002001","supplier":"SUP001",'
        && '"supplierName":"Example Technology Supplier","companyCode":"1000",'
        && '"purchasingOrganization":"1000","purchasingGroup":"001","currency":"EUR",'
        && '"totalAmount":"1500.00","items":[{'
        && '"itemId":"00000000-0000-0000-0000-000000000003","item":"10",'
        && '"material":"MAT001","description":"Laptop","quantity":"2.000",'
        && '"unitOfMeasure":"EA","netPrice":"750.0000","totalAmount":"1500.00"}]}'.
  ENDMETHOD.


  METHOD intent_row.
    SELECT SINGLE delivery_uuid, order_revision, dispatch_state, payload_snapshot,
                  payload_hash, approved_by, approved_at, last_correlation_id,
                  portal_order_uuid, lease_owner, lease_expires_at
      FROM zjp_po_dlv
      WHERE delivery_uuid = @delivery_uuid
      INTO CORRESPONDING FIELDS OF @row.
  ENDMETHOD.


  METHOD header_row.
    SELECT SINGLE status, integration_status, delivery_id, last_correlation_id,
                  last_error_code, last_error_message
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO CORRESPONDING FIELDS OF @row.
  ENDMETHOD.


  METHOD force_lease_expiry.
    MODIFY ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        UPDATE FIELDS ( LeaseExpiresAt )
        WITH VALUE #( ( DeliveryUUID   = delivery_uuid
                        LeaseExpiresAt = expiry ) )
      FAILED DATA(failed_force).
    success = xsdbool( failed_force IS INITIAL AND save_all( ) = abap_true ).
  ENDMETHOD.


  METHOD force_dispatch_state.
    MODIFY ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        UPDATE FIELDS ( DispatchState )
        WITH VALUE #( ( DeliveryUUID  = delivery_uuid
                        DispatchState = state ) )
      FAILED DATA(failed_force).
    success = xsdbool( failed_force IS INITIAL AND save_all( ) = abap_true ).
  ENDMETHOD.


  METHOD make_fixture.

    " One active root with one item, 2 x 750 = 1500.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid        = 'DISPATCH_ROOT'
                        Supplier    = supplier
                        CompanyCode = '1000'
                        Currency    = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'DISPATCH_ROOT'
          %target = VALUE #( ( %cid = 'DISPATCH_ITEM' ItemNumber = '00010'
                               Material = 'MAT001' Quantity = 2
                               UnitOfMeasure = 'EA' NetPrice = '750.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_create)
      FAILED DATA(failed_create).

    IF failed_create IS NOT INITIAL
       OR NOT line_exists( mapped_create-purchaseorder[ %cid = 'DISPATCH_ROOT' ] ).
      ROLLBACK ENTITIES.
      stop( 'dispatch fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(order_uuid) = mapped_create-purchaseorder[ %cid = 'DISPATCH_ROOT' ]-PurchaseOrderUUID.
    IF save_all( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        FIELDS ( Status )
        WITH VALUE #( ( %is_draft = if_abap_behv=>mk-off PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(orders)
      FAILED DATA(failed_read).
    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1.
      stop( 'dispatch fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(order_key) = orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_submit).
    IF failed_submit IS NOT INITIAL OR save_all( ) = abap_false.
      ROLLBACK ENTITIES.
      stop( 'dispatch fixture could not be submitted.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_approve).
    IF failed_approve IS NOT INITIAL OR save_all( ) = abap_false.
      ROLLBACK ENTITIES.
      stop( 'dispatch fixture could not be approved.' ).
      RETURN.
    ENDIF.

    " The Phase 5.2f production path, unchanged and uninvolved with HTTP.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE sendToSupplier FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_send).
    IF failed_send IS NOT INITIAL OR save_all( ) = abap_false.
      ROLLBACK ENTITIES.
      stop( 'sendToSupplier failed on the dispatch fixture.' ).
      RETURN.
    ENDIF.

    SELECT SINGLE delivery_uuid, dispatch_state FROM zjp_po_dlv
      WHERE purchase_order_uuid = @order_uuid
      INTO @DATA(created_intent).

    IF sy-subrc <> 0 OR created_intent-dispatch_state <> 'PENDING'.
      stop( 'the fixture did not produce a PENDING intent.' ).
      RETURN.
    ENDIF.

    fixture-order_uuid    = order_uuid.
    fixture-delivery_uuid = created_intent-delivery_uuid.

    console->write( name = 'Fixture order / delivery' data = fixture ).

  ENDMETHOD.


  METHOD test_d_reconstruction.

    " ---------- D: snapshot reconstruction ----------
    " Pure: no database, no network. It runs first because everything after it
    " depends on the reader being right, and a failure here would otherwise show
    " up as a confusing transport problem.
    success = abap_false.
    console->write( '--- D: persisted snapshot -> DTO -> byte-identical round trip ---' ).

    DATA(original) = golden_snapshot_body( ).

    DATA(read_result) = NEW zjp_cl_dlv_snapshot_reader( )->read( original ).

    IF read_result-success = abap_false.
      console->write( name = 'Reader error code' data = read_result-error_code ).
      console->write( name = 'Reader error text' data = read_result-error_text ).
      stop( 'the reader could not reconstruct the golden snapshot.' ).
      RETURN.
    ENDIF.

    " The assertion that cannot pass by accident: a single wrong decimal scale,
    " a dropped leading zero or a mis-cased member breaks byte equality.
    DATA(re_serialized) = NEW zjp_cl_dlv_snapshot_json( )->serialize( read_result-delivery ).

    IF re_serialized <> original.
      console->write( name = 'Original'      data = original ).
      console->write( name = 'Re-serialized' data = re_serialized ).
      stop( 'the reconstructed DTO does not re-serialize to the original.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: D1 - round trip is byte-identical.' ).

    " And it must be acceptable to the verified mapper with no adaptation.
    DATA(map_result) = NEW zjp_cl_cap_order_mapper( )->map( read_result-delivery ).

    IF map_result-success = abap_false.
      console->write( name = 'Mapper error' data = map_result-error_code ).
      stop( 'the mapper refused the reconstructed DTO.' ).
      RETURN.
    ENDIF.

    console->write( name = 'Mapped CAP body' data = map_result-request-body ).
    console->write( 'PASS: D2 - the mapper accepted the reconstructed DTO.' ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_abc_lease.

    success = abap_false.
    console->write( '' ).
    console->write( '--- A/B/C: claim, live-lease contention, stale recovery ---' ).

    DATA(fixture) = make_fixture( 'SUP040' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(before) = intent_row( fixture-delivery_uuid ).

    " ---------- A: a PENDING intent is claimable ----------
    " The transport reference is declared and assigned SEPARATELY rather than
    " constructed inline. The SAP parser rejected the nested NEW form in this
    " context, and separating it also makes the seam visible: the coordinator is
    " handed a REF TO ZJP_IF_OUTBOUND_TRANSPORT and never learns which
    " implementation it got.
    DATA transport_one TYPE REF TO zjp_if_outbound_transport.

    transport_one = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-created ).

    DATA(worker_one) = NEW zjp_cl_dispatch_coordinator(
      transport     = transport_one
      lease_seconds = lease_seconds ).

    DATA(claim_a) = worker_one->claim_intent( fixture-delivery_uuid ).
    console->write( name = 'A claim outcome' data = claim_a ).

    IF claim_a-claimed = abap_false.
      stop( |a PENDING intent must be claimable; reason { claim_a-skip_reason }| ).
      RETURN.
    ENDIF.

    DATA(after_a) = intent_row( fixture-delivery_uuid ).
    GET TIME STAMP FIELD DATA(now_a).

    IF after_a-dispatch_state <> 'IN_FLIGHT'.
      stop( 'the claimed intent is not IN_FLIGHT.' ).
      RETURN.
    ENDIF.
    IF after_a-lease_owner <> worker_one->get_run_uuid( ).
      stop( 'the lease owner is not this run.' ).
      RETURN.
    ENDIF.
    IF after_a-lease_expires_at <= now_a.
      stop( 'the lease expiry is not in the future.' ).
      RETURN.
    ENDIF.

    " The immutable evidence must survive a claim untouched.
    IF after_a-payload_snapshot <> before-payload_snapshot
       OR after_a-payload_hash <> before-payload_hash
       OR after_a-approved_by <> before-approved_by
       OR after_a-approved_at <> before-approved_at
       OR after_a-order_revision <> before-order_revision.
      stop( 'the claim altered immutable delivery evidence.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: A - PENDING claimed, IN_FLIGHT, lease held, evidence intact.' ).

    " ---------- B: a LIVE lease must not be stolen ----------
    DATA transport_two TYPE REF TO zjp_if_outbound_transport.

    transport_two = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-created ).

    DATA(worker_two) = NEW zjp_cl_dispatch_coordinator(
      transport     = transport_two
      lease_seconds = lease_seconds ).

    DATA(claim_b) = worker_two->claim_intent( fixture-delivery_uuid ).
    console->write( name = 'B claim outcome' data = claim_b ).

    IF claim_b-claimed = abap_true.
      stop( 'a second worker stole a live lease.' ).
      RETURN.
    ENDIF.
    IF claim_b-skip_reason <> zjp_cl_dispatch_coordinator=>skipped-lease_live.
      stop( |B skipped for the wrong reason: { claim_b-skip_reason }| ).
      RETURN.
    ENDIF.

    DATA(after_b) = intent_row( fixture-delivery_uuid ).
    IF after_b-lease_owner <> after_a-lease_owner
       OR after_b-lease_expires_at <> after_a-lease_expires_at
       OR after_b-dispatch_state <> after_a-dispatch_state.
      stop( 'the refused claim still changed the lease.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: B - live lease refused and left completely untouched.' ).

    " ---------- C: an EXPIRED lease is reclaimable ----------
    " The expiry is forced to a past moment through EML, which is the same write
    " path production uses. No SQL UPDATE is issued anywhere in this class.
    IF force_lease_expiry( delivery_uuid = fixture-delivery_uuid
                           expiry        = CONV zjp_po_dlv-lease_expires_at( '20200101000000.0000000' ) ) = abap_false.
      stop( 'the lease expiry could not be forced into the past.' ).
      RETURN.
    ENDIF.

    DATA(claim_c) = worker_two->claim_intent( fixture-delivery_uuid ).
    console->write( name = 'C claim outcome' data = claim_c ).

    IF claim_c-claimed = abap_false.
      stop( |a stale lease must be reclaimable; reason { claim_c-skip_reason }| ).
      RETURN.
    ENDIF.

    DATA(after_c) = intent_row( fixture-delivery_uuid ).
    GET TIME STAMP FIELD DATA(now_c).

    IF after_c-lease_owner <> worker_two->get_run_uuid( ).
      stop( 'the reclaimed lease does not belong to the recovering run.' ).
      RETURN.
    ENDIF.
    IF after_c-lease_owner = after_a-lease_owner.
      stop( 'the lease owner did not change on recovery.' ).
      RETURN.
    ENDIF.
    IF after_c-lease_expires_at <= now_c.
      stop( 'the reclaimed lease has no future expiry.' ).
      RETURN.
    ENDIF.
    IF after_c-delivery_uuid <> before-delivery_uuid.
      stop( 'recovery minted a new delivery identity.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: C - stale lease reclaimed, same delivery identity.' ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_e_real_delivery.

    success = abap_false.
    console->write( '' ).
    console->write( '--- E: REAL HTTP delivery through Integration Suite ---' ).

    " PHASE 6.4b: the assertions below are UNCHANGED, and that is the point of
    " this test after the cutover. The same fixture must still produce a 201, a
    " DELIVERED intent, an APPROVED -> SENT order, a stored portalOrderId and a
    " persisted attempt correlation id - only the hop in the middle is different,
    " because CI returns CAP's receipt contract unchanged. A changed assertion
    " here would mean the cutover altered the outcome contract, which it must not.
    "
    " RTTEST001, NOT an invented supplier and not a production one. The first
    " real run used SUP041 and the deployed portal answered HTTP 400
    " UNKNOWN_SUPPLIER: "supplierCode SUP041 is not an active supplier in this
    " portal". That was CAP validating correctly, not a defect - production CAP
    " HANA does not carry the local development fixture data.
    "
    " RTTEST001, "Runtime Test Supplier (synthetic, HANA runtime verification)",
    " is provisioned in the deployed portal for exactly this purpose. It is a
    " DEPLOYED PREREQUISITE of this test: if the row is missing or inactive, E
    " fails with a 400 and the fix is to restore the supplier, never to
    " special-case it in the builder or the mapper.
    DATA(fixture) = make_fixture( 'RTTEST001' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA real_transport TYPE REF TO zjp_if_outbound_transport.

    real_transport = NEW zjp_cl_outbound_transport( destination_name = destination ).

    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = real_transport
      lease_seconds = lease_seconds ).

    DATA(outcome) = coordinator->run_once( fixture-delivery_uuid ).
    console->write( name = 'E outcome' data = outcome ).

    IF outcome-claimed = abap_false OR outcome-dispatched = abap_false.
      stop( |E did not dispatch; reason { outcome-skip_reason }| ).
      RETURN.
    ENDIF.

    " The delivery identity is fresh for every fixture, so this is a genuine
    " first ingestion and CAP answers 201 rather than a replay 200.
    IF outcome-answered = abap_false.
      console->write( name = 'E failure text' data = outcome-error_text ).
      stop( 'Integration Suite did not answer; check the destination and OAuth.' ).
      RETURN.
    ENDIF.
    IF outcome-http_status <> 201.
      stop( |expected HTTP 201 for a fresh deliveryId, got { outcome-http_status }| ).
      RETURN.
    ENDIF.

    DATA(intent) = intent_row( fixture-delivery_uuid ).
    DATA(header) = header_row( fixture-order_uuid ).
    console->write( name = 'E intent' data = intent ).
    console->write( name = 'E header' data = header ).

    IF intent-dispatch_state <> 'DELIVERED'.
      stop( 'a 201 did not produce DispatchState DELIVERED.' ).
      RETURN.
    ENDIF.
    IF header-status <> 'SENT'.
      stop( 'a delivered order did not transition APPROVED -> SENT.' ).
      RETURN.
    ENDIF.
    IF header-integration_status <> 'DELIVERED'.
      stop( 'the header integration status is not DELIVERED.' ).
      RETURN.
    ENDIF.
    IF header-delivery_id <> fixture-delivery_uuid.
      stop( 'the header delivery identity changed.' ).
      RETURN.
    ENDIF.
    IF intent-portal_order_uuid IS INITIAL.
      stop( 'the receipt portalOrderId was not persisted on the intent.' ).
      RETURN.
    ENDIF.
    IF intent-last_correlation_id <> outcome-correlation_uuid.
      stop( 'the attempt correlation id was not persisted.' ).
      RETURN.
    ENDIF.

    " A finished delivery must not advertise a live lease.
    IF intent-lease_owner IS NOT INITIAL OR intent-lease_expires_at IS NOT INITIAL.
      stop( 'a DELIVERED intent still holds a lease.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: E - real 201 via Integration Suite, intent DELIVERED, order SENT, receipt stored.' ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_f_replay_and_immutable.

    success = abap_false.
    console->write( '' ).
    console->write( '--- F/J: idempotent 200 replay, and immutable evidence ---' ).

    DATA(fixture) = make_fixture( 'SUP042' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA(before) = intent_row( fixture-delivery_uuid ).

    " The fake's REPLAYED scenario returns 200 with the SAME receipt body as
    " CREATED, byte for byte - which is what makes a replay safe and why 6.4
    " gives 200 and 201 identical handling.
    DATA replay_transport TYPE REF TO zjp_if_outbound_transport.

    replay_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-replayed ).

    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = replay_transport
      lease_seconds = lease_seconds ).

    DATA(outcome) = coordinator->run_once( fixture-delivery_uuid ).
    console->write( name = 'F outcome' data = outcome ).

    IF outcome-http_status <> 200 OR outcome-final_state <> 'DELIVERED'.
      stop( 'an idempotent 200 was not treated as a successful delivery.' ).
      RETURN.
    ENDIF.

    DATA(after) = intent_row( fixture-delivery_uuid ).
    DATA(header) = header_row( fixture-order_uuid ).

    IF after-dispatch_state <> 'DELIVERED' OR header-status <> 'SENT'.
      stop( 'a 200 replay did not deliver the intent and send the order.' ).
      RETURN.
    ENDIF.

    " No duplicate business identity.
    SELECT COUNT( * ) FROM zjp_po_dlv
      WHERE purchase_order_uuid = @fixture-order_uuid INTO @DATA(intent_count).
    IF intent_count <> 1.
      stop( |a replay produced { intent_count } intents.| ).
      RETURN.
    ENDIF.
    IF after-delivery_uuid <> before-delivery_uuid.
      stop( 'the delivery identity changed across a replay.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: F - 200 replay delivered, one intent, same identity.' ).

    " ---------- J: immutable evidence across a whole coordinator run ----------
    IF after-payload_snapshot <> before-payload_snapshot.
      stop( 'the coordinator changed PayloadSnapshot.' ).
      RETURN.
    ENDIF.
    IF after-payload_hash <> before-payload_hash.
      stop( 'the coordinator changed PayloadHash.' ).
      RETURN.
    ENDIF.
    IF after-approved_by <> before-approved_by OR after-approved_at <> before-approved_at.
      stop( 'the coordinator changed the approval evidence.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: J - snapshot, hash and approval evidence all unchanged.' ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_g_conflict.

    success = abap_false.
    console->write( '' ).
    console->write( '--- G: HTTP 409 payload collision is NOT success ---' ).

    DATA(fixture) = make_fixture( 'SUP043' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA conflict_transport TYPE REF TO zjp_if_outbound_transport.

    conflict_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-conflict ).

    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = conflict_transport
      lease_seconds = lease_seconds ).

    DATA(outcome) = coordinator->run_once( fixture-delivery_uuid ).
    console->write( name = 'G outcome' data = outcome ).

    " A 409 is answered. Classifying on `answered` alone would call this success,
    " which is exactly the mistake 6.4 exists to prevent.
    IF outcome-answered = abap_false OR outcome-http_status <> 409.
      stop( 'the conflict scenario did not produce an answered 409.' ).
      RETURN.
    ENDIF.
    IF outcome-final_state <> 'FAILED'.
      stop( |a 409 was classified as { outcome-final_state }, not FAILED.| ).
      RETURN.
    ENDIF.

    DATA(intent) = intent_row( fixture-delivery_uuid ).
    DATA(header) = header_row( fixture-order_uuid ).
    console->write( name = 'G header' data = header ).

    IF intent-dispatch_state <> 'FAILED'.
      stop( 'the intent is not FAILED after a collision.' ).
      RETURN.
    ENDIF.
    IF header-status <> 'ERROR'.
      stop( 'a definite send failure did not move the order to ERROR.' ).
      RETURN.
    ENDIF.
    IF header-integration_status <> 'FAILED'.
      stop( 'the header integration status is not FAILED.' ).
      RETURN.
    ENDIF.
    IF header-last_error_code IS INITIAL.
      stop( 'no error evidence was persisted for the collision.' ).
      RETURN.
    ENDIF.
    IF intent-lease_owner IS NOT INITIAL.
      stop( 'a FAILED intent still holds a lease.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: G - 409 kept meaningful, intent FAILED, order ERROR.' ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_h_unanswered_and_corr.

    success = abap_false.
    console->write( '' ).
    console->write( '--- H/I: unanswered call, and a fresh correlation per attempt ---' ).

    DATA(fixture) = make_fixture( 'SUP044' ).
    IF fixture-delivery_uuid IS INITIAL.
      RETURN.
    ENDIF.

    DATA silent_transport TYPE REF TO zjp_if_outbound_transport.

    silent_transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-unanswered ).

    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = silent_transport
      lease_seconds = lease_seconds ).

    DATA(first) = coordinator->run_once( fixture-delivery_uuid ).
    console->write( name = 'H first attempt' data = first ).

    " A timeout never proves non-delivery. It is UNKNOWN, and a later attempt
    " must replay the SAME deliveryId rather than mint a new one.
    IF first-answered = abap_true.
      stop( 'the unanswered scenario reported an answer.' ).
      RETURN.
    ENDIF.
    IF first-final_state <> 'UNKNOWN'.
      stop( |an unanswered call became { first-final_state }, not UNKNOWN.| ).
      RETURN.
    ENDIF.

    DATA(intent_one) = intent_row( fixture-delivery_uuid ).
    DATA(header_one) = header_row( fixture-order_uuid ).

    IF intent_one-dispatch_state <> 'UNKNOWN'.
      stop( 'the intent is not UNKNOWN after an unanswered call.' ).
      RETURN.
    ENDIF.
    IF header_one-status <> 'ERROR' OR header_one-integration_status <> 'UNKNOWN'.
      stop( 'the header did not record the ambiguous outcome.' ).
      RETURN.
    ENDIF.
    IF intent_one-last_correlation_id <> first-correlation_uuid.
      stop( 'the first attempt correlation id was not persisted.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: H - unanswered classified UNKNOWN, evidence persisted.' ).

    " ---------- I: a second attempt gets a NEW correlation id ----------
    " The intent is returned to PENDING through EML, standing in for the
    " operator-requested sendToSupplier retry. The coordinator itself never does
    " this: it does not claim FAILED or UNKNOWN intents at all.
    IF force_dispatch_state( delivery_uuid = fixture-delivery_uuid
                             state         = 'PENDING' ) = abap_false.
      stop( 'the intent could not be returned to PENDING for the retry.' ).
      RETURN.
    ENDIF.

    DATA(second) = coordinator->run_once( fixture-delivery_uuid ).
    console->write( name = 'I second attempt' data = second ).

    IF second-dispatched = abap_false.
      stop( |the retry did not dispatch; reason { second-skip_reason }| ).
      RETURN.
    ENDIF.
    IF second-correlation_uuid = first-correlation_uuid.
      stop( 'the retry reused the first attempt correlation id.' ).
      RETURN.
    ENDIF.
    IF second-delivery_uuid <> first-delivery_uuid.
      stop( 'the retry minted a new delivery identity.' ).
      RETURN.
    ENDIF.

    DATA(intent_two) = intent_row( fixture-delivery_uuid ).
    IF intent_two-last_correlation_id <> second-correlation_uuid.
      stop( 'the retry correlation id was not persisted.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: I - new correlation per attempt, delivery identity unchanged.' ).

    success = abap_true.

  ENDMETHOD.

ENDCLASS.
