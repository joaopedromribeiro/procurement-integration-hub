CLASS lhc_PurchaseOrder DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS validateSupplier FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseOrder~validateSupplier.

    METHODS initializeStatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseOrder~initializeStatus.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR PurchaseOrder
      RESULT result.
ENDCLASS.

CLASS lhc_PurchaseOrderItem DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS calculateTotalAmount FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseOrderItem~calculateTotalAmount.

    METHODS recalculateHeaderAfterDelete FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseOrderItem~recalculateHeaderAfterDelete.
ENDCLASS.

CLASS lhc_PurchaseOrderItem IMPLEMENTATION.
  METHOD calculateTotalAmount.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrderItem
      FIELDS ( PurchaseOrderUUID Quantity NetPrice )
      WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_order_items).

    CHECK purchase_order_items IS NOT INITIAL.

    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrderItem BY \_PurchaseOrder
      FIELDS ( PurchaseOrderUUID ) WITH CORRESPONDING #( keys )
      RESULT DATA(affected_orders).

    SORT affected_orders BY PurchaseOrderUUID.
    DELETE ADJACENT DUPLICATES FROM affected_orders
      COMPARING PurchaseOrderUUID.

    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder BY \_Items
      FIELDS ( PurchaseOrderUUID Quantity NetPrice )
      WITH CORRESPONDING #( affected_orders )
      RESULT DATA(all_items).

    DATA items_to_update TYPE TABLE FOR UPDATE ZJP_I_PurchaseOrderItem.
    items_to_update = VALUE #( FOR item IN purchase_order_items
      ( %tky        = item-%tky
        TotalAmount = item-Quantity * item-NetPrice ) ).

    DATA orders_to_update TYPE TABLE FOR UPDATE ZJP_I_PurchaseOrder.
    LOOP AT affected_orders INTO DATA(affected_order).
      DATA(header_total) = CONV zjp_po_h-total_amount( 0 ).

      LOOP AT all_items INTO DATA(all_item)
        WHERE PurchaseOrderUUID = affected_order-PurchaseOrderUUID.
        DATA(item_total) = CONV zjp_po_i-total_amount(
          all_item-Quantity * all_item-NetPrice ).
        header_total += item_total.
      ENDLOOP.

      APPEND VALUE #( %tky        = affected_order-%tky
                      TotalAmount = header_total )
        TO orders_to_update.
    ENDLOOP.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrderItem
      UPDATE FIELDS ( TotalAmount )
      WITH items_to_update
      ENTITY PurchaseOrder
      UPDATE FIELDS ( TotalAmount )
      WITH orders_to_update
      REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).
  ENDMETHOD.

  METHOD recalculateHeaderAfterDelete.
    CHECK keys IS NOT INITIAL.

    " Committed items remain in persistence until RAP's save sequence.
    " Read immutable parent identities only; amounts come from EML below.
    SELECT purchase_order_item_uuid, purchase_order_uuid
      FROM zjp_po_i
      FOR ALL ENTRIES IN @keys
      WHERE purchase_order_item_uuid = @keys-PurchaseOrderItemUUID
      INTO TABLE @DATA(persisted_parents).

    DATA parent_keys TYPE TABLE FOR READ IMPORT ZJP_I_PurchaseOrder.
    LOOP AT keys INTO DATA(delete_key).
      READ TABLE persisted_parents INTO DATA(persisted_parent)
        WITH KEY purchase_order_item_uuid = delete_key-PurchaseOrderItemUUID.
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = delete_key-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Parent lookup requires a previously committed item; rollback this request.' ) )
          TO reported-purchaseorderitem.
        RETURN.
      ENDIF.
      APPEND VALUE #( PurchaseOrderUUID = persisted_parent-purchase_order_uuid )
        TO parent_keys.
    ENDLOOP.
    SORT parent_keys BY PurchaseOrderUUID.
    DELETE ADJACENT DUPLICATES FROM parent_keys COMPARING PurchaseOrderUUID.

    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      FIELDS ( PurchaseOrderUUID ) WITH parent_keys
      RESULT DATA(affected_orders).

    SORT affected_orders BY PurchaseOrderUUID.
    DELETE ADJACENT DUPLICATES FROM affected_orders
      COMPARING PurchaseOrderUUID.
    CHECK affected_orders IS NOT INITIAL.

    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder BY \_Items
      FIELDS ( PurchaseOrderItemUUID PurchaseOrderUUID Quantity NetPrice )
      WITH CORRESPONDING #( affected_orders )
      RESULT DATA(remaining_items).

    LOOP AT keys INTO DATA(deleted_item_key).
      DELETE remaining_items
        WHERE PurchaseOrderItemUUID = deleted_item_key-PurchaseOrderItemUUID.
    ENDLOOP.

    DATA orders_to_update TYPE TABLE FOR UPDATE ZJP_I_PurchaseOrder.
    LOOP AT affected_orders INTO DATA(affected_order).
      DATA(header_total) = CONV zjp_po_h-total_amount( 0 ).

      LOOP AT remaining_items INTO DATA(remaining_item)
        WHERE PurchaseOrderUUID = affected_order-PurchaseOrderUUID.
        DATA(item_total) = CONV zjp_po_i-total_amount(
          remaining_item-Quantity * remaining_item-NetPrice ).
        header_total += item_total.
      ENDLOOP.

      APPEND VALUE #( %tky        = affected_order-%tky
                      TotalAmount = header_total )
        TO orders_to_update.
    ENDLOOP.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      UPDATE FIELDS ( TotalAmount )
      WITH orders_to_update
      REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).
  ENDMETHOD.
ENDCLASS.

CLASS lhc_PurchaseOrder IMPLEMENTATION.
  METHOD validateSupplier.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      FIELDS ( Supplier ) WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_orders).

    LOOP AT purchase_orders INTO DATA(purchase_order).
      IF purchase_order-Supplier IS INITIAL.
        APPEND VALUE #( %tky = purchase_order-%tky )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = purchase_order-%tky
          %element-Supplier = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Supplier is required.' ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD initializeStatus.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_orders)
      REPORTED DATA(read_reported).

    DATA reported_orders LIKE reported-purchaseorder.
    reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.
    DELETE purchase_orders WHERE Status IS NOT INITIAL.
    CHECK purchase_orders IS NOT INITIAL.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      UPDATE FIELDS ( Status )
      WITH VALUE #( FOR purchase_order IN purchase_orders
        ( %tky = purchase_order-%tky Status = 'DRAFT' ) )
      REPORTED DATA(update_reported).

    reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.
  ENDMETHOD.

  METHOD get_instance_authorizations.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      FIELDS ( PurchaseOrderUUID ) WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_orders)
      FAILED failed
      REPORTED reported.

    SORT purchase_orders BY %tky.
    DELETE ADJACENT DUPLICATES FROM purchase_orders COMPARING %tky.

    DATA authorization_result LIKE LINE OF result.

    LOOP AT purchase_orders INTO DATA(purchase_order).
      CLEAR authorization_result.
      authorization_result-%tky = purchase_order-%tky.

      " Study-only permissive policy; replace with actual business authorization.
      IF requested_authorizations-%update = if_abap_behv=>mk-on.
        authorization_result-%update = if_abap_behv=>auth-allowed.
      ENDIF.

      IF requested_authorizations-%delete = if_abap_behv=>mk-on.
        authorization_result-%delete = if_abap_behv=>auth-allowed.
      ENDIF.

      APPEND authorization_result TO result.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
