" Local ABAP Unit test include for ZJP_CL_EVENT_TRIGGER. No SQL or HTTP.
CLASS ltd_intent_reader DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zjp_if_event_intent_reader.
    DATA snapshot TYPE zjp_if_event_intent_reader=>ty_snapshot.
ENDCLASS.

CLASS ltd_intent_reader IMPLEMENTATION.
  METHOD zjp_if_event_intent_reader~read.
    snapshot = me->snapshot.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_dispatcher DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zjp_if_event_dispatcher.
    DATA call_count TYPE i.
    DATA last_uuid TYPE sysuuid_x16.
ENDCLASS.

CLASS ltd_dispatcher IMPLEMENTATION.
  METHOD zjp_if_event_dispatcher~run_once.
    call_count = call_count + 1.
    last_uuid = delivery_uuid.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_event_trigger DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA reader TYPE REF TO ltd_intent_reader.
    DATA dispatcher TYPE REF TO ltd_dispatcher.
    DATA trigger TYPE REF TO zjp_cl_event_trigger.
    DATA request TYPE zjp_cl_event_trigger=>ty_request.

    METHODS setup.
    METHODS valid_identity FOR TESTING.
    METHODS unknown_delivery FOR TESTING.
    METHODS wrong_order FOR TESTING.
    METHODS wrong_revision FOR TESTING.
    METHODS wrong_hash FOR TESTING.
    METHODS stale_revision FOR TESTING.
    METHODS duplicate_identity FOR TESTING.
    METHODS missing_order FOR TESTING.
ENDCLASS.

CLASS ltc_event_trigger IMPLEMENTATION.
  METHOD setup.
    reader = NEW ltd_intent_reader( ).
    dispatcher = NEW ltd_dispatcher( ).
    trigger = NEW zjp_cl_event_trigger(
      reader = reader
      dispatcher = dispatcher ).

    request = VALUE #(
      delivery_uuid = cl_system_uuid=>create_uuid_x16_static( )
      purchase_order_uuid = cl_system_uuid=>create_uuid_x16_static( )
      order_revision = 1
      payload_hash = 'HASH_A' ).
    reader->snapshot = VALUE #(
      intent_found = abap_true
      delivery_uuid = request-delivery_uuid
      purchase_order_uuid = request-purchase_order_uuid
      order_revision = request-order_revision
      payload_hash = request-payload_hash
      order_found = abap_true
      current_revision = request-order_revision ).
  ENDMETHOD.

  METHOD valid_identity.
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-delegated
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = dispatcher->call_count ).
    cl_abap_unit_assert=>assert_equals(
      exp = request-delivery_uuid act = dispatcher->last_uuid ).
  ENDMETHOD.

  METHOD unknown_delivery.
    reader->snapshot-intent_found = abap_false.
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-unknown_delivery
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = dispatcher->call_count ).
  ENDMETHOD.

  METHOD wrong_order.
    request-purchase_order_uuid = cl_system_uuid=>create_uuid_x16_static( ).
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-identity_conflict
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = dispatcher->call_count ).
  ENDMETHOD.

  METHOD wrong_revision.
    request-order_revision = 2.
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-identity_conflict
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = dispatcher->call_count ).
  ENDMETHOD.

  METHOD wrong_hash.
    request-payload_hash = 'HASH_B'.
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-identity_conflict
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = dispatcher->call_count ).
  ENDMETHOD.

  METHOD stale_revision.
    reader->snapshot-current_revision = 2.
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-stale_revision
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = dispatcher->call_count ).
  ENDMETHOD.

  METHOD duplicate_identity.
    DATA(first) = trigger->trigger( request ).
    DATA(second) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-delegated
      act = first-decision ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-delegated
      act = second-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = dispatcher->call_count ).
    cl_abap_unit_assert=>assert_equals(
      exp = request-delivery_uuid act = dispatcher->last_uuid ).
  ENDMETHOD.

  METHOD missing_order.
    reader->snapshot-order_found = abap_false.
    DATA(result) = trigger->trigger( request ).
    cl_abap_unit_assert=>assert_equals(
      exp = zjp_cl_event_trigger=>decision-order_not_found
      act = result-decision ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = dispatcher->call_count ).
  ENDMETHOD.
ENDCLASS.
