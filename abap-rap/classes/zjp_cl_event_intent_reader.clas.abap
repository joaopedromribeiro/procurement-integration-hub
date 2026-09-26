" Phase 9.5A. Committed-state lookup only; no business-object mutation.
CLASS zjp_cl_event_intent_reader DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zjp_if_event_intent_reader.
ENDCLASS.

CLASS zjp_cl_event_intent_reader IMPLEMENTATION.
  METHOD zjp_if_event_intent_reader~read.
    SELECT SINGLE delivery_uuid, purchase_order_uuid, order_revision, payload_hash
      FROM zjp_po_dlv
      WHERE delivery_uuid = @delivery_uuid
      INTO ( @snapshot-delivery_uuid,
             @snapshot-purchase_order_uuid,
             @snapshot-order_revision,
             @snapshot-payload_hash ).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    snapshot-intent_found = abap_true.

    SELECT SINGLE order_revision
      FROM zjp_po_h
      WHERE purchase_order_uuid = @snapshot-purchase_order_uuid
      INTO @snapshot-current_revision.
    IF sy-subrc = 0.
      snapshot-order_found = abap_true.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
