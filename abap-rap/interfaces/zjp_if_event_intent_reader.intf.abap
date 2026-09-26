" Phase 9.5A. Read-only committed business identity for one delivery.
INTERFACE zjp_if_event_intent_reader PUBLIC.
  TYPES:
    BEGIN OF ty_snapshot,
      intent_found        TYPE abap_bool,
      delivery_uuid       TYPE zjp_po_dlv-delivery_uuid,
      purchase_order_uuid TYPE zjp_po_dlv-purchase_order_uuid,
      order_revision      TYPE zjp_po_dlv-order_revision,
      payload_hash        TYPE zjp_po_dlv-payload_hash,
      order_found         TYPE abap_bool,
      current_revision    TYPE zjp_po_h-order_revision,
    END OF ty_snapshot.

  METHODS read
    IMPORTING delivery_uuid  TYPE sysuuid_x16
    RETURNING VALUE(snapshot) TYPE ty_snapshot.
ENDINTERFACE.
