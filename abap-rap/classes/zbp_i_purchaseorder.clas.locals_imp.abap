CLASS lhc_PurchaseOrder DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS removeItem FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~removeItem.

    METHODS submit FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~submit.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~approve.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~reject.

    METHODS precheck_update FOR PRECHECK
      IMPORTING entities FOR UPDATE purchaseorder.

    METHODS precheck_cba_items FOR PRECHECK
      IMPORTING entities FOR CREATE purchaseorder\_items.

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

    METHODS precheck_update FOR PRECHECK
      IMPORTING entities FOR UPDATE PurchaseOrderItem.
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


  METHOD precheck_update.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.
    DATA commercial_entities LIKE entities.

    " Only user-writable commercial item fields are guarded. The readonly
    " TotalAmount written by calculateTotalAmount is not one of them.
    LOOP AT entities INTO DATA(entity).
      IF entity-%control-ItemNumber          <> if_abap_behv=>mk-on
         AND entity-%control-Material            <> if_abap_behv=>mk-on
         AND entity-%control-MaterialDescription <> if_abap_behv=>mk-on
         AND entity-%control-Quantity            <> if_abap_behv=>mk-on
         AND entity-%control-UnitOfMeasure       <> if_abap_behv=>mk-on
         AND entity-%control-NetPrice            <> if_abap_behv=>mk-on
         AND entity-%control-Currency            <> if_abap_behv=>mk-on.
        CONTINUE.
      ENDIF.
      APPEND entity TO commercial_entities.
    ENDLOOP.
    CHECK commercial_entities IS NOT INITIAL.

    " The item carries no status. Its owning root is the authority, and the
    " parent is matched on UUID and %is_draft so an active instance and its
    " draft are never combined.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrderItem
        FIELDS ( PurchaseOrderUUID )
        WITH CORRESPONDING #( commercial_entities )
        RESULT DATA(items)
      ENTITY PurchaseOrderItem BY \_PurchaseOrder
        FIELDS ( PurchaseOrderUUID Status )
        WITH CORRESPONDING #( commercial_entities )
        RESULT DATA(parent_orders)
      FAILED DATA(read_failed)
      REPORTED DATA(read_reported).
    reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.
    reported_items = CORRESPONDING #( DEEP read_reported-purchaseorderitem ).
    APPEND LINES OF reported_items TO reported-purchaseorderitem.

    LOOP AT commercial_entities INTO DATA(checked_entity).
      READ TABLE items INTO DATA(item)
        WITH KEY %tky = checked_entity-%tky.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      READ TABLE parent_orders INTO DATA(parent_order)
        WITH KEY PurchaseOrderUUID = item-PurchaseOrderUUID
                 %is_draft = item-%is_draft.
      " Unreadable parents are left to the framework's own handling.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      " Business rule: item content is editable only while the owning root is
      " in Status DRAFT. INITIAL is a transient technical state, not a
      " business state, and must keep creation working. Every persisted state
      " after DRAFT is immutable.
      IF parent_order-Status IS INITIAL
         OR parent_order-Status = 'DRAFT'.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = checked_entity-%tky )
        TO failed-purchaseorderitem.
      APPEND VALUE #( %tky = checked_entity-%tky
        %msg = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text = 'Only draft order items can change.' ) )
        TO reported-purchaseorderitem.
    ENDLOOP.
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
            FIELDS ( PurchaseOrderUUID Status )
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
        " Commercial content is editable only while Status is DRAFT. INITIAL
        " is a transient technical state, not a business state. Checked before
        " ownership so the state of the order decides uniformly.
        IF orders[ 1 ]-Status IS NOT INITIAL
           AND orders[ 1 ]-Status <> 'DRAFT'.
          error_text = 'Only draft orders can lose items.'.
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

  METHOD submit.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      " One invocation submits one active root; no state survives this method.
      DO 1 TIMES.
        " Reject technical draft instances before reading or changing anything.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Submit is not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( Status )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          ENTITY PurchaseOrder BY \_Items
            FIELDS ( PurchaseOrderUUID )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(current_items)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP read_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; submit not performed.'.
          EXIT.
        ENDIF.

        " Business Status, not the RAP draft flag, controls this transition.
        IF orders[ 1 ]-Status <> 'DRAFT'.
          error_text = 'Only orders in status DRAFT can be submitted.'.
          EXIT.
        ENDIF.

        " Supplier, Quantity and NetPrice stay with their save validations.
        IF current_items IS INITIAL.
          error_text = 'Submit requires at least one item.'.
          EXIT.
        ENDIF.

        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( Status )
            WITH VALUE #( ( %tky = action_key-%tky
                            Status = 'SUBMITTED' ) )
          FAILED DATA(update_failed)
          REPORTED DATA(update_reported).
        reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP update_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.
        IF update_failed IS NOT INITIAL.
          error_text = 'Status update failed; rollback this request.'.
          EXIT.
        ENDIF.
      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-submit = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-submit = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.



  METHOD approve.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      " One invocation decides one active root; no state survives this method.
      DO 1 TIMES.
        " Reject technical draft instances before reading or changing anything.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( Status )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP read_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; no action taken.'.
          EXIT.
        ENDIF.

        " Business Status is the transition authority. Content was validated
        " before submission and is immutable afterwards, so nothing is
        " revalidated here.
        IF orders[ 1 ]-Status <> 'SUBMITTED'.
          error_text = 'Only submitted orders can be decided.'.
          EXIT.
        ENDIF.

        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( Status )
            WITH VALUE #( ( %tky = action_key-%tky
                            Status = 'APPROVED' ) )
          FAILED DATA(update_failed)
          REPORTED DATA(update_reported).
        reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP update_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.
        IF update_failed IS NOT INITIAL.
          error_text = 'Status update failed; rollback this request.'.
          EXIT.
        ENDIF.
      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-approve = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-approve = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD reject.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    " Approver rejection only. Supplier-side rejection is a separate
    " mechanism and sets RejectionOrigin to SUPPLIER in a later phase.
    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      DO 1 TIMES.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( Status )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP read_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; no action taken.'.
          EXIT.
        ENDIF.

        IF orders[ 1 ]-Status <> 'SUBMITTED'.
          error_text = 'Only submitted orders can be decided.'.
          EXIT.
        ENDIF.

        " Eligibility and lifecycle state decide before the parameter.
        IF action_key-%param-RejectionReason IS INITIAL.
          error_text = 'Rejection reason is required.'.
          EXIT.
        ENDIF.

        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( Status RejectionOrigin RejectionReason )
            WITH VALUE #( ( %tky = action_key-%tky
                            Status = 'REJECTED'
                            RejectionOrigin = 'APPROVER'
                            RejectionReason =
                              action_key-%param-RejectionReason ) )
          FAILED DATA(update_failed)
          REPORTED DATA(update_reported).
        reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.
        reported_items = CORRESPONDING #( DEEP update_reported-purchaseorderitem ).
        APPEND LINES OF reported_items TO reported-purchaseorderitem.
        IF update_failed IS NOT INITIAL.
          error_text = 'Status update failed; rollback this request.'.
          EXIT.
        ENDIF.
      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-reject = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-reject = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD precheck_update.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA commercial_entities LIKE entities.

    " Only user-writable commercial fields are guarded. Requests that touch
    " readonly fields alone - Status from submit, TotalAmount from the
    " determinations - are left untouched by this rule.
    LOOP AT entities INTO DATA(entity).
      IF entity-%control-Supplier               <> if_abap_behv=>mk-on
         AND entity-%control-CompanyCode            <> if_abap_behv=>mk-on
         AND entity-%control-PurchasingOrganization <> if_abap_behv=>mk-on
         AND entity-%control-PurchasingGroup        <> if_abap_behv=>mk-on
         AND entity-%control-Currency               <> if_abap_behv=>mk-on.
        CONTINUE.
      ENDIF.
      APPEND entity TO commercial_entities.
    ENDLOOP.
    CHECK commercial_entities IS NOT INITIAL.

    " A precheck runs before the buffer changes, so this is the current
    " business Status. %tky carries %is_draft, so a draft instance resolves
    " against the draft row.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
        FIELDS ( Status )
        WITH CORRESPONDING #( commercial_entities )
        RESULT DATA(orders)
      FAILED DATA(read_failed)
      REPORTED DATA(read_reported).
    reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.

    LOOP AT commercial_entities INTO DATA(checked_entity).
      READ TABLE orders INTO DATA(order)
        WITH KEY %tky = checked_entity-%tky.
      " Unreadable instances are left to the framework's own handling.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      " Business rule: commercial content is editable only while Status is
      " DRAFT. INITIAL is a transient technical state, not a business state:
      " a newly created root can be readable before initializeStatus has run,
      " and creation must keep working. Every persisted state after DRAFT is
      " immutable.
      IF order-Status IS INITIAL OR order-Status = 'DRAFT'.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = checked_entity-%tky )
        TO failed-purchaseorder.
      APPEND VALUE #( %tky = checked_entity-%tky
        %msg = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text = 'Only draft orders can be changed.' ) )
        TO reported-purchaseorder.
    ENDLOOP.
  ENDMETHOD.

  METHOD precheck_cba_items.
    DATA reported_orders LIKE reported-purchaseorder.

    " Adding an item is a commercial change, so no %control filter applies.
    " The request is addressed by the target root's key.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
        FIELDS ( Status )
        WITH CORRESPONDING #( entities )
        RESULT DATA(orders)
      FAILED DATA(read_failed)
      REPORTED DATA(read_reported).
    reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.

    LOOP AT entities INTO DATA(entity).
      READ TABLE orders INTO DATA(order) WITH KEY %tky = entity-%tky.
      " Unreadable instances are left to the framework's own handling.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      " Business rule: commercial content is editable only while Status is
      " DRAFT. INITIAL is a transient technical state, not a business state:
      " a newly created root can be readable before initializeStatus has run,
      " and creation must keep working. Every persisted state after DRAFT is
      " immutable.
      IF order-Status IS INITIAL OR order-Status = 'DRAFT'.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = entity-%tky )
        TO failed-purchaseorder.
      APPEND VALUE #( %tky = entity-%tky
        %msg = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text = 'Items can be added to draft orders only.' ) )
        TO reported-purchaseorder.
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
