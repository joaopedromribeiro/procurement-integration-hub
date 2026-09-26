" Phase 9.5A. Ordinary application service, not a RAP action or HTTP endpoint.
" It validates a committed intent before delegating the same DeliveryUUID.
CLASS zjp_cl_event_trigger DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF decision,
        delegated         TYPE string VALUE 'DELEGATED',
        unknown_delivery  TYPE string VALUE 'UNKNOWN_DELIVERY',
        identity_conflict TYPE string VALUE 'IDENTITY_CONFLICT',
        stale_revision   TYPE string VALUE 'STALE_REVISION',
        order_not_found  TYPE string VALUE 'ORDER_NOT_FOUND',
      END OF decision.

    TYPES:
      BEGIN OF ty_request,
        delivery_uuid       TYPE sysuuid_x16,
        purchase_order_uuid TYPE sysuuid_x16,
        order_revision      TYPE zjp_po_dlv-order_revision,
        payload_hash        TYPE zjp_po_dlv-payload_hash,
      END OF ty_request,
      BEGIN OF ty_result,
        decision TYPE string,
        " Populated only after delegation; this is the coordinator's actual
        " claim/skip/transport result, not an adapter-invented delivery status.
        coordinator_outcome TYPE zjp_cl_dispatch_coordinator=>ty_outcome,
      END OF ty_result.

    METHODS constructor
      IMPORTING reader     TYPE REF TO zjp_if_event_intent_reader
                dispatcher TYPE REF TO zjp_if_event_dispatcher.
    METHODS trigger
      IMPORTING request TYPE ty_request
      RETURNING VALUE(result) TYPE ty_result.

  PRIVATE SECTION.
    DATA reader TYPE REF TO zjp_if_event_intent_reader.
    DATA dispatcher TYPE REF TO zjp_if_event_dispatcher.
ENDCLASS.

CLASS zjp_cl_event_trigger IMPLEMENTATION.
  METHOD constructor.
    me->reader = reader.
    me->dispatcher = dispatcher.
  ENDMETHOD.

  METHOD trigger.
    " No publication ID is accepted or stored. DeliveryUUID is the operation key.
    DATA(snapshot) = reader->read( request-delivery_uuid ).
    IF snapshot-intent_found = abap_false.
      result-decision = decision-unknown_delivery.
      RETURN.
    ENDIF.

    IF snapshot-delivery_uuid <> request-delivery_uuid
       OR snapshot-purchase_order_uuid <> request-purchase_order_uuid
       OR snapshot-order_revision <> request-order_revision
       OR snapshot-payload_hash <> request-payload_hash.
      result-decision = decision-identity_conflict.
      RETURN.
    ENDIF.

    IF snapshot-order_found = abap_false.
      result-decision = decision-order_not_found.
      RETURN.
    ENDIF.

    " The persisted header revision is authoritative for the current order.
    " An older event must not dispatch merely because its intent is PENDING.
    IF snapshot-current_revision > snapshot-order_revision.
      result-decision = decision-stale_revision.
      RETURN.
    ENDIF.
    IF snapshot-current_revision <> snapshot-order_revision.
      result-decision = decision-identity_conflict.
      RETURN.
    ENDIF.

    " Only the coordinator evaluates PENDING, leases, budget, retry and UNKNOWN.
    result-decision = decision-delegated.
    result-coordinator_outcome = dispatcher->run_once( request-delivery_uuid ).
  ENDMETHOD.
ENDCLASS.
