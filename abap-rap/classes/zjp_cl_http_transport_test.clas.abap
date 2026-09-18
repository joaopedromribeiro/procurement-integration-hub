" Phase 5.2e - console runtime harness for the REAL HTTP transport.
"
" A dedicated test object by explicit decision, recorded in the Phase 5.1 guide
" section 10.3. ZJP_CL_TRANSPORT_TEST stays exactly what Phase 5.2c verified it
" to be - an in-process, network-free harness over the fake - and putting real
" HTTP into it would destroy that meaning. ZJP_CL_PO_DISPATCH_TEST stays reserved
" for the Phase 5.2g coordinator.
"
" This harness MAKES REAL NETWORK CALLS to the deployed CAP application. It does
" not create a DeliveryIntent, does not touch PurchaseOrder, and writes nothing
" to the SAP database. The only persistence it causes is on the CAP side, which
" is the point of the test.
"
" It deliberately does NOT use the builder or the mapper. Deterministic literal
" bodies isolate transport behaviour: if an assertion fails, the transport is the
" only thing that can have caused it.
"
" IDENTITY AND RERUNS. The delivery identity below is fixed, because no released
" UUID-generation API is verified on this target yet - that is probe P14, and it
" stays OPEN. CAP's ingestion is idempotent on deliveryId, so the FIRST call
" returns 201 only on the first ever run of this harness; a later rerun returns
" 200 for the same call. The harness says so plainly rather than failing, and the
" replay and conflict assertions are unaffected because they never depended on
" the first call's code.
CLASS zjp_cl_http_transport_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " The base destination: host, port, TLS and OAuth, with NO application path.
    " The route travels in the request, which is what P15 established.
    CONSTANTS destination TYPE rfcdest VALUE 'ZJP_CAP_BASE'.
    CONSTANTS route       TYPE string  VALUE '/rest/integration/v1/Orders'.

    " Fresh identities, used by no earlier probe: not the manual ABAP probe's
    " 6b396c73-…, and not the P10 mapper fixture's 00000000-…-000000000001.
    CONSTANTS delivery_id TYPE string VALUE '7c4e1b90-3f52-4a6d-9e18-2d5b8a0c6f41'.
    CONSTANTS order_id    TYPE string VALUE '5a2f8d31-6c04-4b7e-8f93-1e6a7b2c9d05'.
    CONSTANTS item_id     TYPE string VALUE '2e91c47a-8b36-4d52-a0f7-9c14e3b5d682'.

    " RTTEST001 already exists in deployed HANA from the earlier manual probe.
    CONSTANTS supplier    TYPE string VALUE 'RTTEST001'.

    " Built by concatenation rather than held as a constant: a text literal is
    " capped at 255 characters and a CONSTANTS VALUE must be a single literal,
    " which Phase 5.2d established the hard way.
    "
    " quantity x 25.0000 = amount, and the header amount equals the single line
    " amount, so both parameter sets are internally consistent: 2.000 -> 50.00
    " and 3.000 -> 75.00. The second is a valid delivery that merely disagrees
    " with the first, which is exactly what makes it a CONFLICT and not a 400.
    METHODS delivery_body
      IMPORTING quantity    TYPE string
                amount      TYPE string
      RETURNING VALUE(body) TYPE string.

    METHODS build_request
      IMPORTING quantity       TYPE string
                amount         TYPE string
      RETURNING VALUE(request) TYPE zjp_if_outbound_transport=>ty_request.

    METHODS transport
      RETURNING VALUE(adapter) TYPE REF TO zjp_if_outbound_transport.

    METHODS test_created
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_replayed
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_conflict
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_bad_destination
      RETURNING VALUE(success) TYPE abap_bool.

ENDCLASS.


CLASS zjp_cl_http_transport_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write( '=== Phase 5.2e - real HTTP transport ===' ).
    out->write( |Destination { destination }, route { route }. This makes REAL network calls.| ).
    out->write( |Delivery identity { delivery_id } - fixed, because P14 is open.| ).

    IF test_created( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_replayed( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_conflict( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_bad_destination( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: Phase 5.2e real HTTP transport verified.' ).

  ENDMETHOD.


  METHOD transport.
    " Through the interface. The concrete class is named once, here.
    adapter = NEW zjp_cl_outbound_transport( destination_name = destination ).
  ENDMETHOD.


  METHOD delivery_body.
    body = '{"schemaVersion":"1.0","deliveryId":"' && delivery_id && '",'
        && '"source":{"system":"PIH_ABAP_HTTP_TEST","orderId":"' && order_id && '",'
        && '"orderNumber":"PO00052001","revision":1},'
        && '"supplierCode":"' && supplier && '",'
        && '"amount":{"currency":"EUR","value":"' && amount && '"},'
        && '"lines":[{"sourceItemId":"' && item_id && '","lineNumber":10,'
        && '"product":{"code":"MAT001","description":"HTTP transport test item"},'
        && '"orderedQuantity":{"value":"' && quantity && '","unit":"PCE"},'
        && '"unitPrice":{"currency":"EUR","value":"25.0000"},'
        && '"lineAmount":"' && amount && '"}]}'.
  ENDMETHOD.


  METHOD build_request.
    request-path = route.
    " Idempotency-Key equals the deliveryId, as the contract specifies. No
    " X-Correlation-ID: it is a fresh UUID per attempt and belongs to the 5.2g
    " coordinator, which must persist it to ZJP_PO_DLV-last_correlation_id.
    request-headers = VALUE #(
      ( name = 'Content-Type'    value = 'application/json' )
      ( name = 'Idempotency-Key' value = delivery_id ) ).
    request-body = delivery_body( quantity = quantity amount = amount ).
  ENDMETHOD.


  METHOD test_created.

    success = abap_false.

    DATA(response) = transport( )->post( build_request( quantity = '2.000'
                                                        amount   = '50.00' ) ).

    console->write( name = 'CREATED response' data = response ).

    IF response-answered <> abap_true.
      console->write( |STOP: no answer from the receiver. { response-failure_text }| ).
      RETURN.
    ENDIF.

    IF response-failure_text IS NOT INITIAL.
      console->write( 'STOP: an answered call must carry no failure_text.' ).
      RETURN.
    ENDIF.

    CASE response-status.
      WHEN 201.
        console->write( 'PASS: real HTTP transport CREATED returned answered=true, status=201.' ).
        success = abap_true.
      WHEN 200.
        " Not a failure, and not something to hide. CAP is idempotent on
        " deliveryId, so this is what a rerun looks like.
        console->write( 'NOTE: status 200, not 201. This delivery identity was already ingested by an earlier run of this harness.' ).
        console->write( 'PASS: real HTTP transport CREATED returned answered=true with an idempotent 200.' ).
        success = abap_true.
      WHEN OTHERS.
        console->write( |STOP: expected 201 on a first run or 200 on a rerun, got { response-status }.| ).
    ENDCASE.

  ENDMETHOD.


  METHOD test_replayed.

    success = abap_false.

    " Byte-identical to the CREATED request.
    DATA(response) = transport( )->post( build_request( quantity = '2.000'
                                                        amount   = '50.00' ) ).

    console->write( name = 'REPLAYED response' data = response ).

    IF response-answered <> abap_true.
      console->write( |STOP: no answer from the receiver. { response-failure_text }| ).
      RETURN.
    ENDIF.

    IF response-status <> 200.
      console->write( |STOP: an exact replay must return 200, got { response-status }.| ).
      RETURN.
    ENDIF.

    IF response-failure_text IS NOT INITIAL.
      console->write( 'STOP: an answered call must carry no failure_text.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: real HTTP transport REPLAYED returned answered=true, status=200.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_conflict.

    success = abap_false.

    " Same deliveryId, different but internally valid content.
    DATA(response) = transport( )->post( build_request( quantity = '3.000'
                                                        amount   = '75.00' ) ).

    console->write( name = 'CONFLICT response' data = response ).

    " The point of this assertion: a 409 is an ANSWER. The transport must not
    " have demoted it to a technical failure.
    IF response-answered <> abap_true.
      console->write( |STOP: a 409 is an answered result, not a transport failure. { response-failure_text }| ).
      RETURN.
    ENDIF.

    IF response-status <> 409.
      console->write( |STOP: a changed payload under the same deliveryId must return 409, got { response-status }.| ).
      RETURN.
    ENDIF.

    IF response-failure_text IS NOT INITIAL.
      console->write( 'STOP: an answered call must carry no failure_text.' ).
      RETURN.
    ENDIF.

    " The transport forwards the receiver body untouched; it does not classify
    " this code, and the test reads it only to prove the body survived.
    IF NOT response-body CS 'DELIVERY_PAYLOAD_CONFLICT'.
      console->write( 'STOP: the 409 body does not carry DELIVERY_PAYLOAD_CONFLICT.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: real HTTP transport CONFLICT returned answered=true, status=409 with the receiver body intact.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_bad_destination.

    success = abap_false.

    " Safe and isolated: a destination name that does not exist. Nothing in SM59
    " is created, changed or broken, and no request leaves the system. This is
    " the one place the production adapter's unanswered path can be exercised
    " without damaging working infrastructure.
    DATA adapter TYPE REF TO zjp_if_outbound_transport.
    adapter = NEW zjp_cl_outbound_transport( destination_name = 'ZJP_NO_SUCH_DEST' ).

    DATA(response) = adapter->post( build_request( quantity = '2.000'
                                                   amount   = '50.00' ) ).

    console->write( name = 'UNRESOLVABLE DESTINATION response' data = response ).

    IF response-answered <> abap_false.
      console->write( 'STOP: an unresolvable destination must be answered=false.' ).
      RETURN.
    ENDIF.

    IF response-status <> 0.
      console->write( 'STOP: an unanswered call must carry status 0.' ).
      RETURN.
    ENDIF.

    IF response-body IS NOT INITIAL.
      console->write( 'STOP: an unanswered call must carry an initial body.' ).
      RETURN.
    ENDIF.

    IF response-failure_text IS INITIAL.
      console->write( 'STOP: an unanswered call must carry diagnostic failure_text.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: real HTTP transport reported an unresolvable destination as a technical failure.' ).
    success = abap_true.

  ENDMETHOD.

ENDCLASS.
