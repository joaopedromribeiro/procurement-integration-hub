" Phase 9.5B - network-free HTTP boundary tests.
" No real outbound transport, no Integration Suite, no CAP.

CLASS ltc_po_event_dispatch DEFINITION DEFERRED.

CLASS zcl_jp_po_event_dispatch DEFINITION
  LOCAL FRIENDS ltc_po_event_dispatch.


CLASS ltd_http_intent_reader DEFINITION FINAL.

  PUBLIC SECTION.

    INTERFACES zjp_if_event_intent_reader.

    DATA snapshot
      TYPE zjp_if_event_intent_reader=>ty_snapshot.

ENDCLASS.


CLASS ltd_http_intent_reader IMPLEMENTATION.

  METHOD zjp_if_event_intent_reader~read.

    snapshot = me->snapshot.

  ENDMETHOD.

ENDCLASS.


CLASS ltd_http_dispatcher DEFINITION FINAL.

  PUBLIC SECTION.

    INTERFACES zjp_if_event_dispatcher.

    DATA call_count TYPE i.
    DATA last_uuid  TYPE sysuuid_x16.

    DATA outcome
      TYPE zjp_cl_dispatch_coordinator=>ty_outcome.

ENDCLASS.


CLASS ltd_http_dispatcher IMPLEMENTATION.

  METHOD zjp_if_event_dispatcher~run_once.

    call_count = call_count + 1.
    last_uuid  = delivery_uuid.
    outcome    = me->outcome.

  ENDMETHOD.

ENDCLASS.


CLASS ltc_po_event_dispatch DEFINITION FINAL
  FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.

    CONSTANTS delivery_uuid_text TYPE sysuuid_c36
      VALUE '11111111-1111-4111-8111-111111111111'.

    CONSTANTS order_uuid_text TYPE sysuuid_c36
      VALUE '22222222-2222-4222-8222-222222222222'.

    CONSTANTS payload_hash TYPE string
      VALUE 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'.

    DATA sut
      TYPE REF TO zcl_jp_po_event_dispatch.

    DATA reader
      TYPE REF TO ltd_http_intent_reader.

    DATA dispatcher
      TYPE REF TO ltd_http_dispatcher.

    DATA trigger
      TYPE REF TO zjp_cl_event_trigger.

    DATA request
      TYPE zjp_cl_event_trigger=>ty_request.


    METHODS setup.

    METHODS wrong_method
      FOR TESTING.

    METHODS unauthorized
      FOR TESTING.

    METHODS invalid_json
      FOR TESTING.

    METHODS valid_delegated
      FOR TESTING.

    METHODS stale_revision
      FOR TESTING.

    METHODS invalid_content_type
      FOR TESTING.

    METHODS empty_body
      FOR TESTING.

    METHODS invalid_uuid
      FOR TESTING.

    METHODS invalid_hash
      FOR TESTING.

    METHODS trigger_unavailable
      FOR TESTING.

    METHODS unknown_delivery
      FOR TESTING.

    METHODS identity_conflict
      FOR TESTING.

    METHODS order_not_found
      FOR TESTING.


    METHODS valid_body
      RETURNING
        VALUE(json) TYPE string.

    METHODS uuid_x16
      IMPORTING
        text        TYPE sysuuid_c36
      RETURNING
        VALUE(uuid) TYPE sysuuid_x16.

    METHODS assert_contains
      IMPORTING
        actual   TYPE string
        expected TYPE string.

ENDCLASS.


CLASS ltc_po_event_dispatch IMPLEMENTATION.

  METHOD setup.

    sut = NEW zcl_jp_po_event_dispatch( ).

    reader     = NEW ltd_http_intent_reader( ).
    dispatcher = NEW ltd_http_dispatcher( ).

    trigger = NEW zjp_cl_event_trigger(
      reader     = reader
      dispatcher = dispatcher
    ).

    request = VALUE #(
      delivery_uuid       = uuid_x16( delivery_uuid_text )
      purchase_order_uuid = uuid_x16( order_uuid_text )
      order_revision      = 1
      payload_hash        = payload_hash
    ).

    reader->snapshot = VALUE #(
      intent_found        = abap_true
      delivery_uuid       = request-delivery_uuid
      purchase_order_uuid = request-purchase_order_uuid
      order_revision      = request-order_revision
      payload_hash        = request-payload_hash
      order_found         = abap_true
      current_revision    = request-order_revision
    ).

    dispatcher->outcome = VALUE #(
      claimed             = abap_true
      delivery_uuid       = request-delivery_uuid
      purchase_order_uuid = request-purchase_order_uuid
      order_revision      = request-order_revision
      dispatched          = abap_true
      recorded            = abap_true
      final_state         = 'DELIVERED'
    ).

  ENDMETHOD.


  METHOD wrong_method.

    DATA(result) = sut->process_request(
      http_method  = 'GET'
      content_type = 'application/json'
      body         = valid_body( )
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 405
      act = result-status
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 'POST'
      act = result-allow_header
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'METHOD_NOT_ALLOWED'
    ).

  ENDMETHOD.


  METHOD unauthorized.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = valid_body( )
      authorized   = abap_false
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 403
      act = result-status
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'FORBIDDEN'
    ).

  ENDMETHOD.


  METHOD invalid_json.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = '{broken-json'
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 400
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'INVALID_REQUEST'
    ).

  ENDMETHOD.


  METHOD valid_delegated.

    DATA(test_body) = valid_body( ).

    DATA parsed_request TYPE zjp_cl_event_trigger=>ty_request.
    DATA parse_valid    TYPE abap_bool.
    DATA parse_error    TYPE string.

    sut->parse_request(
      EXPORTING
        body            = test_body
      IMPORTING
        valid           = parse_valid
        error_text      = parse_error
        trigger_request = parsed_request
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = abap_true
      act = parse_valid
      msg = |BODY=[{ test_body }] ERROR=[{ parse_error }]|
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = request-delivery_uuid
      act = parsed_request-delivery_uuid
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = request-purchase_order_uuid
      act = parsed_request-purchase_order_uuid
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = request-order_revision
      act = parsed_request-order_revision
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = request-payload_hash
      act = parsed_request-payload_hash
    ).

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = test_body
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 200
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 1
      act = dispatcher->call_count
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = request-delivery_uuid
      act = dispatcher->last_uuid
    ).

    assert_contains(
      actual   = result-body
      expected = 'DELEGATED'
    ).

    assert_contains(
      actual   = result-body
      expected = 'DELIVERED'
    ).

  ENDMETHOD.


  METHOD stale_revision.

    DATA trigger_result
      TYPE zjp_cl_event_trigger=>ty_result.

    trigger_result-decision =
      zjp_cl_event_trigger=>decision-stale_revision.

    DATA(json) = sut->result_json(
      delivery_uuid = request-delivery_uuid
      result        = trigger_result
    ).

    assert_contains(
      actual   = json
      expected = 'STALE_REVISION'
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

  ENDMETHOD.


  METHOD invalid_content_type.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'text/plain'
      body         = valid_body( )
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 415
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'UNSUPPORTED_MEDIA_TYPE'
    ).

  ENDMETHOD.


  METHOD empty_body.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = ''
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 400
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'INVALID_REQUEST'
    ).

    assert_contains(
      actual   = result-body
      expected = 'Request body is required'
    ).

  ENDMETHOD.


  METHOD invalid_uuid.

    DATA(invalid_body) =
        '{"deliveryUUID":"NOT-A-UUID"'
      && ',"purchaseOrderUUID":"'
      && order_uuid_text
      && '","orderRevision":1,"payloadHash":"'
      && payload_hash
      && '"}'.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = invalid_body
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 400
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'deliveryUUID is not a valid canonical UUID'
    ).

  ENDMETHOD.


  METHOD invalid_hash.

    DATA(invalid_body) =
        '{"deliveryUUID":"'
      && delivery_uuid_text
      && '","purchaseOrderUUID":"'
      && order_uuid_text
      && '","orderRevision":1,"payloadHash":"XYZ"}'.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = invalid_body
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 400
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'payloadHash must contain exactly 64 hexadecimal characters'
    ).

  ENDMETHOD.


  METHOD trigger_unavailable.

    DATA no_trigger
      TYPE REF TO zjp_cl_event_trigger.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = valid_body( )
      authorized   = abap_true
      trigger      = no_trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 500
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'TRIGGER_NOT_AVAILABLE'
    ).

  ENDMETHOD.


  METHOD unknown_delivery.

    reader->snapshot-intent_found = abap_false.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = valid_body( )
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 200
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'UNKNOWN_DELIVERY'
    ).

  ENDMETHOD.


  METHOD identity_conflict.

    reader->snapshot-payload_hash =
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = valid_body( )
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 200
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'IDENTITY_CONFLICT'
    ).

  ENDMETHOD.


  METHOD order_not_found.

    reader->snapshot-order_found = abap_false.

    DATA(result) = sut->process_request(
      http_method  = 'POST'
      content_type = 'application/json'
      body         = valid_body( )
      authorized   = abap_true
      trigger      = trigger
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 200
      act = result-status
      msg = result-body
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = dispatcher->call_count
    ).

    assert_contains(
      actual   = result-body
      expected = 'ORDER_NOT_FOUND'
    ).

  ENDMETHOD.


  METHOD valid_body.

    json =
        '{"deliveryUUID":"'
      && delivery_uuid_text
      && '","purchaseOrderUUID":"'
      && order_uuid_text
      && '","orderRevision":1,"payloadHash":"'
      && payload_hash
      && '"}'.

  ENDMETHOD.


  METHOD uuid_x16.

    cl_system_uuid=>convert_uuid_c36_static(
      EXPORTING
        uuid     = text
      IMPORTING
        uuid_x16 = uuid
    ).

  ENDMETHOD.


  METHOD assert_contains.

    FIND FIRST OCCURRENCE OF expected
      IN actual.

    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = sy-subrc
      msg = |Expected [{ expected }] in [{ actual }]|
    ).

  ENDMETHOD.

ENDCLASS.
