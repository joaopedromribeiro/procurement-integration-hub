CLASS lhc_PurchaseOrder DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS removeItem FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~removeItem.

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
    METHODS validateQuantity FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseOrderItem~validateQuantity.

    METHODS validateNetPrice FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseOrderItem~validateNetPrice.

    METHODS calculateTotalAmount FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseOrderItem~calculateTotalAmount.
ENDCLASS.

CLASS lhc_PurchaseOrderItem IMPLEMENTATION.
  METHOD validateNetPrice.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrderItem
      FIELDS ( NetPrice ) WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_order_items).

    LOOP AT purchase_order_items INTO DATA(purchase_order_item).
      IF purchase_order_item-NetPrice < 0.
        APPEND VALUE #( %tky = purchase_order_item-%tky )
          TO failed-purchaseorderitem.
        APPEND VALUE #( %tky = purchase_order_item-%tky
          %element-NetPrice = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Net Price cannot be negative.' ) )
          TO reported-purchaseorderitem.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateQuantity.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrderItem
      FIELDS ( Quantity ) WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_order_items).

    LOOP AT purchase_order_items INTO DATA(purchase_order_item).
      IF purchase_order_item-Quantity <= 0.
        APPEND VALUE #( %tky = purchase_order_item-%tky )
          TO failed-purchaseorderitem.
        APPEND VALUE #( %tky = purchase_order_item-%tky
          %element-Quantity = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Quantity must be greater than 0.' ) )
          TO reported-purchaseorderitem.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

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

    SORT affected_orders BY %tky.
    DELETE ADJACENT DUPLICATES FROM affected_orders
      COMPARING %tky.

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
        WHERE PurchaseOrderUUID = affected_order-PurchaseOrderUUID
          AND %is_draft = affected_order-%is_draft.
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

ENDCLASS.

CLASS lhc_PurchaseOrder IMPLEMENTATION.
  METHOD removeItem.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      " Keep the caller's complete root identity throughout this invocation.
      DO 1 TIMES.
        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( PurchaseOrderUUID )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          ENTITY PurchaseOrder BY \_Items
            FIELDS ( PurchaseOrderUUID TotalAmount )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(owned_items)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP read_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Purchase Order could not be read; item was not removed.'.
          EXIT.
        ENDIF.

        READ TABLE owned_items INTO DATA(item_to_delete)
          WITH KEY PurchaseOrderItemUUID =
            action_key-%param-PurchaseOrderItemUUID
            PurchaseOrderUUID = action_key-PurchaseOrderUUID
            %is_draft = action_key-%is_draft.
        IF sy-subrc <> 0 OR action_key-%param-PurchaseOrderItemUUID IS INITIAL.
          error_text = 'Item does not belong to this Purchase Order.'.
          EXIT.
        ENDIF.

        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrderItem
            DELETE FROM VALUE #( ( %tky = item_to_delete-%tky ) )
          FAILED DATA(delete_failed)
          REPORTED DATA(delete_reported).
        reported_orders = CORRESPONDING #( DEEP delete_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP delete_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.
        IF delete_failed IS NOT INITIAL.
          error_text = 'Item removal failed; rollback this request.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder BY \_Items
            FIELDS ( TotalAmount )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(surviving_items)
          FAILED DATA(survivors_failed)
          REPORTED DATA(survivors_reported).
        reported_orders = CORRESPONDING #( DEEP survivors_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP survivors_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.
        IF survivors_failed IS NOT INITIAL.
          error_text = 'Remaining items could not be read; rollback this request.'.
          EXIT.
        ENDIF.

        DATA(header_total) = CONV zjp_po_h-total_amount( 0 ).
        LOOP AT surviving_items INTO DATA(surviving_item).
          header_total += surviving_item-TotalAmount.
        ENDLOOP.

        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( TotalAmount )
            WITH VALUE #( ( %tky = action_key-%tky
                            TotalAmount = header_total ) )
          FAILED DATA(update_failed)
          REPORTED DATA(update_reported).
        reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP update_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.
        IF update_failed IS NOT INITIAL.
          error_text = 'Header total could not be updated; rollback this request.'.
          EXIT.
        ENDIF.
      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-removeItem = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-removeItem = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

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
