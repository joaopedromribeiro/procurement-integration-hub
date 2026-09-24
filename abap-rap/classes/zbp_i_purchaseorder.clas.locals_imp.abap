CLASS lhc_PurchaseOrder DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    " B4: interim DEV source-system identity.
    " Replace with environment configuration before multi-environment rollout.
    CONSTANTS source_system TYPE string VALUE 'PIH_ABAP_DEV'.

    METHODS removeItem FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~removeItem.

    METHODS submit FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~submit.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~approve.

    METHODS sendToSupplier FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~sendToSupplier.

    METHODS retryDelivery FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~retryDelivery.

    METHODS recordDeliveryResult FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~recordDeliveryResult.

    " Phase 6.5b-1. The inbound supplier response.
    METHODS applySupplierResponse FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~applySupplierResponse.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~reject.

    METHODS cancel FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseOrder~cancel.

    METHODS precheck_update FOR PRECHECK
      IMPORTING entities FOR UPDATE purchaseorder.

    METHODS precheck_cba_items FOR PRECHECK
      IMPORTING entities FOR CREATE purchaseorder\_items.

    METHODS precheck_delete FOR PRECHECK
      IMPORTING keys FOR DELETE purchaseorder.

    METHODS validateSupplier FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseOrder~validateSupplier.

    METHODS initializeStatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseOrder~initializeStatus.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR PurchaseOrder
      RESULT result.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR purchaseorder RESULT result.
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

        " Allocate the human-readable identity. This is the only point in the
        " lifecycle that draws a number: a DRAFT order carries none, and every
        " state after SUBMITTED keeps exactly the number drawn here. The
        " number range object is the authority for uniqueness, never MAX + 1,
        " and a number is never reset or reused. A number that is drawn but
        " not persisted becomes a permitted gap.
        TRY.
            cl_numberrange_runtime=>number_get(
              EXPORTING
                nr_range_nr = '01'
                object      = 'ZJP_PO'
                quantity    = 1
              IMPORTING
                number      = DATA(allocated_number) ).
          CATCH cx_nr_object_not_found.
            error_text = 'Number range object ZJP_PO is missing.'.
          CATCH cx_number_ranges.
            error_text = 'No purchase order number could be drawn.'.
        ENDTRY.
        IF error_text IS NOT INITIAL.
          EXIT.
        ENDIF.
        IF allocated_number IS INITIAL.
          error_text = 'Number range returned no number; not submitted.'.
          EXIT.
        ENDIF.

        " NRLEVEL comes back as 20 digits on this target while the configured
        " ZJP_PO interval 01 is eight digits wide. Take the last eight
        " explicitly and refuse anything wider, so a value outside the
        " configured interval fails the action instead of being truncated
        " into a wrong number.
        IF allocated_number+0(12) <> '000000000000'.
          error_text = 'Allocated number is wider than eight digits.'.
          EXIT.
        ENDIF.
        DATA(order_number) = |PO{ allocated_number+12(8) }|.

        " OrderRevision becomes 1 here, in the same local-mode update as the
        " status and the number, so the three facts a successful submit
        " establishes are written or rolled back together.
        "
        " Revision 1 means "this order has been submitted once and is
        " deliverable". A DRAFT order keeps revision 0 and is deliberately not
        " deliverable: the CAP ingestion contract requires source.revision >= 1
        " and answers 400 INVALID_SOURCE_IDENTITY below that, so the revision
        " is what distinguishes an order that may be delivered from one that
        " may not. It is a business fact about the order and is therefore
        " written by the action that creates it, never defaulted from 0 to 1
        " inside a mapper or a transport class, which would hide a missing
        " fact and turn the revision into an artifact of the wire format.
        "
        " Nothing later in the lifecycle changes it. Approve, reject and
        " cancel leave the revision alone, and a refused second submit exits
        " above this statement, so the value written here is final until a
        " future phase introduces a re-delivery at a higher revision.
        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( Status PurchaseOrderNumber OrderRevision )
            WITH VALUE #( ( %tky = action_key-%tky
                            Status = 'SUBMITTED'
                            PurchaseOrderNumber = order_number
                            OrderRevision = 1 ) )
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

  METHOD sendToSupplier.
    " Phase 5.2f. Requests delivery; it does not report it. This action creates
    " or reuses the durable DeliveryIntent and marks the order as waiting for
    " dispatch, inside its own LUW. It performs NO HTTP, NO COMMIT and NO
    " ROLLBACK - the Phase 5.2g coordinator owns the network side effect, and the
    " external caller owns transaction completion.
    DATA reported_orders LIKE reported-purchaseorder.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      DO 1 TIMES.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        " LastChangedBy/LastChangedAt are read HERE, before this action changes
        " anything, because they are the approval evidence. On an APPROVED order
        " they can only have come from approve: submit requires DRAFT, approve
        " and reject require SUBMITTED, and cancel is the only action accepting
        " APPROVED - and it leaves APPROVED immediately. Reading them after the
        " local-mode update below would overwrite the evidence with the sender.
        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( PurchaseOrderUUID OrderRevision Status
                     LastChangedBy LastChangedAt )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; no action taken.'.
          EXIT.
        ENDIF.

        DATA(order) = orders[ 1 ].

        IF order-Status <> 'APPROVED'.
          error_text = 'Only approved orders can be sent to the supplier.'.
          EXIT.
        ENDIF.

        " Find an intent PERSISTED BY AN EARLIER TRANSACTION. A read-only SELECT
        " is the right instrument and is chosen deliberately: retry semantics
        " operate on committed delivery state, the unique index is over exactly
        " this pair, and EML remains the only mutation path. It must happen
        " BEFORE any create, because an intent created below lives in the
        " transactional buffer and would not be found here anyway.
        SELECT SINGLE delivery_uuid, dispatch_state
          FROM zjp_po_dlv
          WHERE purchase_order_uuid = @order-PurchaseOrderUUID
            AND order_revision      = @order-OrderRevision
          INTO @DATA(existing).

        DATA intent_uuid TYPE sysuuid_x16.
        CLEAR intent_uuid.

        IF sy-subrc = 0.
          " One intent per (PurchaseOrderUUID, OrderRevision), ever. A retry
          " reuses this delivery identity; only a changed commercial snapshot
          " justifies a higher OrderRevision, and that does not exist yet.
          intent_uuid = existing-delivery_uuid.

          CASE existing-dispatch_state.
            WHEN 'DELIVERED'.
              " Not an error. The request is already satisfied, and the business
              " transition to SENT belongs to Phase 5.2g.
              APPEND VALUE #( %tky = action_key-%tky
                %op-%action-sendToSupplier = if_abap_behv=>mk-on
                %msg = new_message_with_text(
                  severity = if_abap_behv_message=>severity-information
                  text = 'Already delivered; the existing delivery is reused.' ) )
                TO reported-purchaseorder.
              EXIT.

            WHEN 'FAILED' OR 'UNKNOWN'.
              " Explicit retry. The snapshot, its hash and the approval evidence
              " are immutable for this revision and are deliberately not
              " rewritten; only the dispatch state returns to PENDING. Lease
              " fields are left untouched - reclaiming a lease is 5.2g's.
              MODIFY ENTITIES OF ZJP_I_DeliveryIntent
                ENTITY DeliveryIntent
                  UPDATE FIELDS ( DispatchState )
                  WITH VALUE #( ( DeliveryUUID  = intent_uuid
                                  DispatchState = 'PENDING' ) )
                FAILED DATA(retry_failed)
                REPORTED DATA(retry_reported).

              IF retry_failed IS NOT INITIAL.
                error_text = 'Existing delivery intent could not be reset to PENDING.'.
                EXIT.
              ENDIF.

            WHEN OTHERS.
              " PENDING and IN_FLIGHT: idempotent no-op. The delivery is already
              " queued or a coordinator holds it; interfering would either mint
              " a second identity or disturb a lease.
              EXIT.
          ENDCASE.

        ELSE.

          " No intent for this revision yet: create exactly one.
          MODIFY ENTITIES OF ZJP_I_DeliveryIntent
            ENTITY DeliveryIntent
              CREATE FIELDS ( PurchaseOrderUUID OrderRevision DispatchState
                              ApprovedBy ApprovedAt )
              WITH VALUE #( ( %cid              = 'SEND_INTENT'
                              PurchaseOrderUUID = order-PurchaseOrderUUID
                              OrderRevision     = order-OrderRevision
                              DispatchState     = 'PENDING'
                              ApprovedBy        = order-LastChangedBy
                              ApprovedAt        = order-LastChangedAt ) )
            MAPPED DATA(mapped_intent)
            FAILED DATA(intent_failed)
            REPORTED DATA(intent_reported).

          IF intent_failed IS NOT INITIAL
             OR NOT line_exists( mapped_intent-deliveryintent[ %cid = 'SEND_INTENT' ] ).
            error_text = 'Delivery intent could not be created.'.
            EXIT.
          ENDIF.

          intent_uuid = mapped_intent-deliveryintent[ %cid = 'SEND_INTENT' ]-DeliveryUUID.
          IF intent_uuid IS INITIAL.
            error_text = 'Managed numbering returned no DeliveryUUID.'.
            EXIT.
          ENDIF.

          " The snapshot carries the delivery identity, so it cannot be built
          " until the key exists - which is why the intent is created first and
          " completed second, in this same LUW.
          DATA(built) = NEW zjp_cl_order_delivery_builder( )->build(
                          purchase_order_uuid = order-PurchaseOrderUUID
                          delivery_uuid       = intent_uuid
                          source_system       = source_system ).

          IF built-success = abap_false.
            error_text = |Delivery snapshot could not be built: { built-error_text }|.
            EXIT.
          ENDIF.

          DATA(snapshot) = NEW zjp_cl_dlv_snapshot_json( )->serialize( built-delivery ).
          IF snapshot IS INITIAL.
            error_text = 'Delivery snapshot serialization returned nothing.'.
            EXIT.
          ENDIF.

          " SHA-256 over the EXACT string that will be persisted. No
          " normalisation and no reserialization, or the hash would describe a
          " string the database never held.
          DATA snapshot_hash TYPE string.
          CLEAR snapshot_hash.
          TRY.
              cl_abap_message_digest=>calculate_hash_for_char(
                EXPORTING if_algorithm  = 'SHA256'
                          if_data       = snapshot
                IMPORTING ef_hashstring = snapshot_hash ).
            CATCH cx_root INTO DATA(hash_error).
              error_text = |Payload hash could not be calculated: { hash_error->get_text( ) }|.
          ENDTRY.

          IF snapshot_hash IS INITIAL.
            IF error_text IS INITIAL.
              error_text = 'Payload hash could not be calculated.'.
            ENDIF.
            EXIT.
          ENDIF.

          MODIFY ENTITIES OF ZJP_I_DeliveryIntent
            ENTITY DeliveryIntent
              UPDATE FIELDS ( PayloadSnapshot PayloadHash )
              WITH VALUE #( ( DeliveryUUID    = intent_uuid
                              PayloadSnapshot = snapshot
                              PayloadHash     = snapshot_hash ) )
            FAILED DATA(snapshot_failed)
            REPORTED DATA(snapshot_reported).

          IF snapshot_failed IS NOT INITIAL.
            error_text = 'Delivery intent snapshot could not be stored.'.
            EXIT.
          ENDIF.

        ENDIF.

        " Reached for a new intent and for a FAILED/UNKNOWN retry. Business
        " Status stays APPROVED: this action requests delivery and does not
        " report it, and SENT is only true once the portal has acknowledged.
        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( IntegrationStatus DeliveryId )
            WITH VALUE #( ( %tky              = action_key-%tky
                            IntegrationStatus = 'PENDING'
                            DeliveryId        = intent_uuid ) )
          FAILED DATA(update_failed)
          REPORTED DATA(update_reported).
        reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.

        IF update_failed IS NOT INITIAL.
          error_text = 'Header integration state could not be updated.'.
          EXIT.
        ENDIF.
      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-sendToSupplier = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-sendToSupplier = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD retryDelivery.
    " Phase 7.6. Preparation only: reuse the current UNKNOWN intent and make it
    " eligible for one explicit coordinator run after the caller commits. No
    " snapshot, hash, approval evidence, identity or attempt evidence is written.
    " There is deliberately NO HTTP, COMMIT, ROLLBACK or sendToSupplier call.
    DATA reported_orders LIKE reported-purchaseorder.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      DO 1 TIMES.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( PurchaseOrderUUID Status OrderRevision IntegrationStatus DeliveryId )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; no recovery prepared.'.
          EXIT.
        ENDIF.

        DATA(order) = orders[ 1 ].

        " UNKNOWN is recorded as ERROR/UNKNOWN by recordDeliveryResult. These
        " checks also refuse a late replay after a terminal receipt reached SAP.
        IF order-Status <> 'ERROR' OR order-IntegrationStatus <> 'UNKNOWN'.
          error_text = 'Only the current UNKNOWN delivery can be retried.'.
          EXIT.
        ENDIF.

        IF order-DeliveryId IS INITIAL.
          error_text = 'The order has no current delivery identity.'.
          EXIT.
        ENDIF.

        SELECT SINGLE delivery_uuid, purchase_order_uuid, order_revision,
                      dispatch_state, payload_snapshot, payload_hash,
                      approved_by, approved_at, attempt_count,
                      last_correlation_id, portal_order_uuid,
                      lease_owner, lease_expires_at
          FROM zjp_po_dlv
          WHERE delivery_uuid       = @order-DeliveryId
            AND purchase_order_uuid = @order-PurchaseOrderUUID
            AND order_revision      = @order-OrderRevision
          INTO @DATA(intent).

        IF sy-subrc <> 0.
          error_text = 'The current delivery intent could not be found.'.
          EXIT.
        ENDIF.

        IF intent-dispatch_state <> 'UNKNOWN'.
          error_text = 'The current delivery intent is no longer UNKNOWN.'.
          EXIT.
        ENDIF.

        IF intent-payload_snapshot IS INITIAL OR intent-payload_hash IS INITIAL
           OR intent-approved_by IS INITIAL OR intent-approved_at IS INITIAL.
          error_text = 'The UNKNOWN intent lacks immutable approval evidence.'.
          EXIT.
        ENDIF.

        " A completed/owned intent is never disturbed. UNKNOWN should already
        " have no lease, but refusing inconsistent evidence is safer than
        " silently clearing a lease that another actor might still rely on.
        IF intent-lease_owner IS NOT INITIAL OR intent-lease_expires_at IS NOT INITIAL
           OR intent-portal_order_uuid IS NOT INITIAL.
          error_text = 'The UNKNOWN intent carries terminal or lease evidence.'.
          EXIT.
        ENDIF.

        MODIFY ENTITIES OF ZJP_I_DeliveryIntent
          ENTITY DeliveryIntent
            UPDATE FIELDS ( DispatchState )
            WITH VALUE #( ( DeliveryUUID  = intent-delivery_uuid
                            DispatchState = 'PENDING' ) )
          FAILED DATA(intent_failed)
          REPORTED DATA(intent_reported).

        IF intent_failed IS NOT INITIAL.
          error_text = 'The UNKNOWN delivery intent could not be prepared.'.
          EXIT.
        ENDIF.

        " Status remains ERROR until the coordinator records a positive receipt.
        " DeliveryId and every other business/evidence field remain untouched.
        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( IntegrationStatus )
            WITH VALUE #( ( %tky              = action_key-%tky
                            IntegrationStatus = 'PENDING' ) )
          FAILED DATA(update_failed)
          REPORTED DATA(update_reported).
        reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.

        IF update_failed IS NOT INITIAL.
          error_text = 'The header recovery state could not be prepared.'.
          EXIT.
        ENDIF.
      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-retryDelivery = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-retryDelivery = if_abap_behv=>mk-on
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD recordDeliveryResult.
    " Phase 5.2g - the RAP outcome boundary for the post-commit coordinator.
    "
    " WHY THIS ACTION EXISTS AT ALL. Status, IntegrationStatus, LastErrorCode,
    " LastErrorMessage, LastErrorAt and LastCorrelationId are every one of them
    " declared `field ( readonly )` in the base BDEF. An external EML consumer
    " therefore cannot write them, and the coordinator runs outside every
    " handler by design. Only a handler in LOCAL MODE may write a readonly
    " field, so the coordinator needs a door - and this is the whole door, with
    " a lock on it rather than an opening in the wall.
    "
    " THE BUSINESS STATUS IS NEVER A PARAMETER. It is derived below from the
    " integration classification, so no caller can set an arbitrary business
    " status: "No unrestricted status PATCH exists" (domain model). The caller
    " supplies what the transport said; this handler decides what that means.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      DO 1 TIMES.
        " Active instance only, the shape every action in this pool uses.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        " The closed vocabulary, checked before anything is read. These are the
        " same four words the intent's DispatchState uses, which is why the two
        " never need translating.
        DATA(requested) = CONV string( action_key-%param-IntegrationStatus ).
        IF requested <> 'DELIVERED' AND requested <> 'FAILED'
           AND requested <> 'UNKNOWN' AND requested <> 'PENDING'.
          error_text = 'Unknown delivery result state.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( Status OrderRevision DeliveryId )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; no result recorded.'.
          EXIT.
        ENDIF.

        " Identity guards. A result carries the delivery and the revision it
        " belongs to, and both must match what this order currently holds.
        " Without them a stale or misrouted coordinator result could move an
        " order's business status on the strength of someone else's receipt.
        IF orders[ 1 ]-DeliveryId <> action_key-%param-DeliveryUUID.
          error_text = 'Result belongs to a different delivery.'.
          EXIT.
        ENDIF.

        IF orders[ 1 ]-OrderRevision <> action_key-%param-OrderRevision.
          error_text = 'Result belongs to a different revision.'.
          EXIT.
        ENDIF.

        DATA(current_status) = CONV string( orders[ 1 ]-Status ).
        DATA(new_status)     = current_status.

        " The domain model's transition table, and nothing invented.
        CASE requested.

          WHEN 'DELIVERED'.
            " APPROVED + positive portal receipt -> SENT. ERROR is allowed for
            " the same reason the model allows it - "SENT on positive receipt" -
            " and SENT itself is allowed so that recording an idempotent replay
            " twice is a no-op rather than a failure.
            IF current_status <> 'APPROVED' AND current_status <> 'ERROR'
               AND current_status <> 'SENT'.
              error_text = 'Order cannot be marked sent from its status.'.
              EXIT.
            ENDIF.
            new_status = 'SENT'.

          WHEN 'FAILED' OR 'UNKNOWN'.
            " Definite send failure or ambiguous timeout -> ERROR. Refused from
            " SENT on purpose: "A later delivery receipt must not downgrade
            " that state", so a late failure cannot un-send a delivered order.
            IF current_status <> 'APPROVED' AND current_status <> 'ERROR'.
              error_text = 'Order cannot be marked failed from its status.'.
              EXIT.
            ENDIF.
            new_status = 'ERROR'.

          WHEN OTHERS.
            " PENDING - a retryable congestion answer. The business status is
            " deliberately untouched: nothing was decided, so nothing moves.
            new_status = current_status.

        ENDCASE.

        IF requested = 'DELIVERED'.
          " Success clears the error evidence a previous attempt left behind.
          " A delivered order carrying the last failure's code would be a
          " standing lie about its own state.
          MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
            ENTITY PurchaseOrder
              UPDATE FIELDS ( Status IntegrationStatus LastCorrelationId
                              LastErrorCode LastErrorMessage LastErrorAt )
              WITH VALUE #( ( %tky              = action_key-%tky
                              Status            = new_status
                              IntegrationStatus = requested
                              LastCorrelationId = action_key-%param-CorrelationId
                              LastErrorCode     = VALUE zjp_po_h-last_error_code( )
                              LastErrorMessage  = VALUE zjp_po_h-last_error_message( )
                              LastErrorAt       = VALUE zjp_po_h-last_error_at( ) ) )
            FAILED DATA(delivered_failed)
            REPORTED DATA(delivered_reported).
          reported_orders = CORRESPONDING #( DEEP delivered_reported-purchaseorder ).
          APPEND LINES OF reported_orders TO reported-purchaseorder.

          IF delivered_failed IS NOT INITIAL.
            error_text = 'Delivery result could not be recorded.'.
            EXIT.
          ENDIF.

        ELSE.
          " Failure or retryable congestion. The error moment is taken HERE
          " rather than from a parameter, for the same reason Phase 5.2f takes
          " approval evidence from the header: the moment this system recorded
          " the outcome is a fact it owns, and a caller-supplied timestamp is a
          " claim it would have to trust.
          GET TIME STAMP FIELD DATA(error_at).

          MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
            ENTITY PurchaseOrder
              UPDATE FIELDS ( Status IntegrationStatus LastCorrelationId
                              LastErrorCode LastErrorMessage LastErrorAt )
              WITH VALUE #( ( %tky              = action_key-%tky
                              Status            = new_status
                              IntegrationStatus = requested
                              LastCorrelationId = action_key-%param-CorrelationId
                              LastErrorCode     = action_key-%param-ErrorCode
                              LastErrorMessage  = action_key-%param-ErrorMessage
                              LastErrorAt       = error_at ) )
            FAILED DATA(failure_failed)
            REPORTED DATA(failure_reported).
          reported_orders = CORRESPONDING #( DEEP failure_reported-purchaseorder ).
          APPEND LINES OF reported_orders TO reported-purchaseorder.

          IF failure_failed IS NOT INITIAL.
            error_text = 'Delivery failure could not be recorded.'.
            EXIT.
          ENDIF.

        ENDIF.

      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-recordDeliveryResult = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
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

  METHOD cancel.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      " One invocation cancels one active root; no state survives this method.
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

        " A positive allow-list, unlike the prechecks, which are deny-rules.
        " REJECTED and CANCELLED are terminal, and INITIAL is the transient
        " state between creation and initializeStatus rather than a business
        " state, so all three fall through to the rejection without needing
        " a carve-out of their own.
        IF orders[ 1 ]-Status <> 'DRAFT'
           AND orders[ 1 ]-Status <> 'SUBMITTED'
           AND orders[ 1 ]-Status <> 'APPROVED'.
          error_text = 'Only open orders can be cancelled.'.
          EXIT.
        ENDIF.

        " APPROVED is cancellable here with no delivery-request guard. Phase
        " 5.2a gives a new order IntegrationStatus = NOT_REQUESTED, but that
        " is precisely the value meaning no delivery has been requested, and
        " nothing yet moves it onwards or sets DeliveryId — so the guard
        " condition still cannot be true and still could not be tested. That
        " guard belongs with DeliveryIntent and sendToSupplier in Phase 5.
        MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            UPDATE FIELDS ( Status )
            WITH VALUE #( ( %tky = action_key-%tky
                            Status = 'CANCELLED' ) )
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
                        %op-%action-cancel = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
          %op-%action-cancel = if_abap_behv=>mk-on
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

  METHOD precheck_delete.
    DATA reported_orders LIKE reported-purchaseorder.

    " A delete request carries keys only, so there is no %control filter
    " here and nothing field-scoped to guard.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
        RESULT DATA(orders)
      FAILED DATA(read_failed)
      REPORTED DATA(read_reported).
    reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.

    LOOP AT keys INTO DATA(delete_key).
      READ TABLE orders INTO DATA(order) WITH KEY %tky = delete_key-%tky.
      " Unreadable instances are left to the framework's own handling.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      " Business rule: an order can be physically deleted only before it has
      " entered the business lifecycle, that is while Status is DRAFT.
      " INITIAL is a transient technical state, not a business state: a newly
      " created root can be readable before initializeStatus has run, and a
      " create-then-delete request inside one round must keep working. Every
      " state from SUBMITTED onwards is terminated through cancel or reject,
      " never removed. Technical draft Discard is a framework draft action
      " and is not affected by this rule.
      IF order-Status IS INITIAL OR order-Status = 'DRAFT'.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = delete_key-%tky )
        TO failed-purchaseorder.
      APPEND VALUE #( %tky = delete_key-%tky
        %msg = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text = 'Only draft orders can be deleted.' ) )
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
    " The guard stays on Status, which is what "this root has not been
    " initialized yet" has always meant here. It is deliberately not widened
    " to IntegrationStatus: every row persisted before Phase 5 carries a
    " filled Status and a blank IntegrationStatus, and guarding on the blank
    " integration value would make those rows look uninitialized.
    DELETE purchase_orders WHERE Status IS NOT INITIAL.
    CHECK purchase_orders IS NOT INITIAL.

    " Both initial values are written together, in the one determination that
    " already owns "what a newly created root starts as". IntegrationStatus
    " belongs here rather than in a second determination because it is the
    " same fact about the same moment: the order exists and nothing has been
    " requested of the portal for it yet. NOT_REQUESTED is an explicit
    " starting state, which is what lets a later delivery check read a
    " meaningful value instead of having to treat blank as a special case.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      UPDATE FIELDS ( Status IntegrationStatus )
      WITH VALUE #( FOR purchase_order IN purchase_orders
        ( %tky = purchase_order-%tky
          Status = 'DRAFT'
          IntegrationStatus = 'NOT_REQUESTED' ) )
      REPORTED DATA(update_reported).

    reported_orders = CORRESPONDING #( DEEP update_reported-purchaseorder ).
    APPEND LINES OF reported_orders TO reported-purchaseorder.
  ENDMETHOD.

METHOD get_instance_authorizations.

  DATA buyer_authorized       TYPE abap_bool.
  DATA approver_authorized    TYPE abap_bool.
  DATA integration_authorized TYPE abap_bool.
  DATA operator_authorized    TYPE abap_bool.
  DATA worker_authorized      TYPE abap_bool.


  " ------------------------------------------------------------
  " BUYER
  " ------------------------------------------------------------
  IF requested_authorizations-%update = if_abap_behv=>mk-on
     OR requested_authorizations-%delete = if_abap_behv=>mk-on
     OR requested_authorizations-%action-Edit = if_abap_behv=>mk-on
     OR requested_authorizations-%action-removeItem = if_abap_behv=>mk-on
     OR requested_authorizations-%action-submit = if_abap_behv=>mk-on
     OR requested_authorizations-%action-sendToSupplier = if_abap_behv=>mk-on
     OR requested_authorizations-%action-cancel = if_abap_behv=>mk-on.

    AUTHORITY-CHECK OBJECT 'ZJP_PIH'
      ID 'ZJP_ROLE'
      FIELD 'BUYER'.

    IF sy-subrc = 0.
      buyer_authorized = abap_true.
    ENDIF.

  ENDIF.


  " ------------------------------------------------------------
  " APPROVER
  " ------------------------------------------------------------
  IF requested_authorizations-%action-approve = if_abap_behv=>mk-on
     OR requested_authorizations-%action-reject = if_abap_behv=>mk-on.

    AUTHORITY-CHECK OBJECT 'ZJP_PIH'
      ID 'ZJP_ROLE'
      FIELD 'APPROVER'.

    IF sy-subrc = 0.
      approver_authorized = abap_true.
    ENDIF.

  ENDIF.


  " ------------------------------------------------------------
  " INTEGRATOR
  " ------------------------------------------------------------
  IF requested_authorizations-%action-applySupplierResponse =
       if_abap_behv=>mk-on.

    AUTHORITY-CHECK OBJECT 'ZJP_PIH'
      ID 'ZJP_ROLE'
      FIELD 'INTEGRATOR'.

    IF sy-subrc = 0.
      integration_authorized = abap_true.
    ENDIF.

  ENDIF.


  " ------------------------------------------------------------
  " OPERATOR
  " ------------------------------------------------------------
  IF requested_authorizations-%action-retryDelivery =
       if_abap_behv=>mk-on.

    AUTHORITY-CHECK OBJECT 'ZJP_PIH'
      ID 'ZJP_ROLE'
      FIELD 'OPERATOR'.

    IF sy-subrc = 0.
      operator_authorized = abap_true.
    ENDIF.

  ENDIF.


  " ------------------------------------------------------------
  " WORKER
  " ------------------------------------------------------------
  IF requested_authorizations-%action-recordDeliveryResult =
       if_abap_behv=>mk-on.

    AUTHORITY-CHECK OBJECT 'ZJP_PIH'
      ID 'ZJP_ROLE'
      FIELD 'WORKER'.

    IF sy-subrc = 0.
      worker_authorized = abap_true.
    ENDIF.

  ENDIF.


  " ------------------------------------------------------------
  " Resolve requested instances
  " ------------------------------------------------------------
  READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
    ENTITY PurchaseOrder
      FIELDS ( PurchaseOrderUUID )
      WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_orders)
      FAILED failed
      REPORTED reported.

  SORT purchase_orders BY %tky.

  DELETE ADJACENT DUPLICATES FROM purchase_orders
    COMPARING %tky.

  DATA authorization_result LIKE LINE OF result.


  LOOP AT purchase_orders INTO DATA(purchase_order).

    CLEAR authorization_result.

    authorization_result-%tky = purchase_order-%tky.


    " ----------------------------------------------------------
    " UPDATE -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%update = if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%update =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%update =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " DELETE -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%delete = if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%delete =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%delete =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " EDIT -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-Edit =
         if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%action-Edit =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-Edit =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " removeItem -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-removeItem =
         if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%action-removeItem =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-removeItem =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " submit -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-submit =
         if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%action-submit =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-submit =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " sendToSupplier -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-sendToSupplier =
         if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%action-sendToSupplier =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-sendToSupplier =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " cancel -> BUYER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-cancel =
         if_abap_behv=>mk-on.

      IF buyer_authorized = abap_true.
        authorization_result-%action-cancel =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-cancel =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " approve -> APPROVER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-approve =
         if_abap_behv=>mk-on.

      IF approver_authorized = abap_true.
        authorization_result-%action-approve =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-approve =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " reject -> APPROVER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-reject =
         if_abap_behv=>mk-on.

      IF approver_authorized = abap_true.
        authorization_result-%action-reject =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-reject =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " applySupplierResponse -> INTEGRATOR
    " ----------------------------------------------------------
    IF requested_authorizations-%action-applySupplierResponse =
         if_abap_behv=>mk-on.

      IF integration_authorized = abap_true.
        authorization_result-%action-applySupplierResponse =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-applySupplierResponse =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " retryDelivery -> OPERATOR
    " ----------------------------------------------------------
    IF requested_authorizations-%action-retryDelivery =
         if_abap_behv=>mk-on.

      IF operator_authorized = abap_true.
        authorization_result-%action-retryDelivery =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-retryDelivery =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    " ----------------------------------------------------------
    " recordDeliveryResult -> WORKER
    " ----------------------------------------------------------
    IF requested_authorizations-%action-recordDeliveryResult =
         if_abap_behv=>mk-on.

      IF worker_authorized = abap_true.
        authorization_result-%action-recordDeliveryResult =
          if_abap_behv=>auth-allowed.
      ELSE.
        authorization_result-%action-recordDeliveryResult =
          if_abap_behv=>auth-unauthorized.
      ENDIF.

    ENDIF.


    APPEND authorization_result TO result.

  ENDLOOP.

ENDMETHOD.

  METHOD applySupplierResponse.
    " Phase 6.5b-1 - the RAP inbound boundary for the supplier's answer.
    "
    " THE MIRROR IMAGE OF recordDeliveryResult, and for the same reason. Status,
    " SupplierResponse, EstimatedDeliveryDate, SupplierRespondedAt,
    " RejectionOrigin, RejectionReason, LastResponseId and LastResponseVersion
    " are every one of them declared `field ( readonly )`, so an external EML or
    " OData consumer cannot write them. Only a handler in LOCAL MODE may, which
    " is why this action exists at all.
    "
    " NO REMOTE CALL, NO COMMIT, NO ROLLBACK. It reads locally, mutates locally
    " and reports through RAP. Transaction ownership stays with the caller,
    " exactly as ADR-006 requires - the same rule that keeps the outbound HTTP
    " call outside every handler.
    "
    " THE DECISION IS A PARAMETER; THE BUSINESS STATUS IS NOT. An ACCEPTED
    " response does not appear in the Status field list below at all, so
    " acceptance provably cannot move the order: SENT stays SENT and only the
    " supplier's answer is recorded. A REJECTED response is terminal and the
    " handler derives REJECTED itself. No caller can set a status directly.
    DATA reported_orders LIKE reported-purchaseorder.
    DATA reported_items LIKE reported-purchaseorderitem.

    LOOP AT keys INTO DATA(action_key).
      DATA(error_text) = CONV string( '' ).

      DO 1 TIMES.
        " Active instance only, the shape every action in this pool uses.
        IF action_key-%is_draft = if_abap_behv=>mk-on.
          error_text = 'Not allowed on a draft instance.'.
          EXIT.
        ENDIF.

        " The closed commercial vocabulary, checked before anything is read.
        " ACCEPTED and REJECTED are the only decisions CAP can make, and the
        " field is char(8) precisely because those two words fit it exactly.
        DATA(decision) = CONV string( action_key-%param-SupplierResponse ).
        IF decision <> 'ACCEPTED' AND decision <> 'REJECTED'.
          error_text = 'Unsupported supplier response decision.'.
          EXIT.
        ENDIF.

        " A rejection without a reason is not a rejection anyone can act on.
        IF decision = 'REJECTED' AND action_key-%param-Reason IS INITIAL.
          error_text = 'A supplier rejection requires a reason.'.
          EXIT.
        ENDIF.

        READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
          ENTITY PurchaseOrder
            FIELDS ( PurchaseOrderUUID Status Supplier OrderRevision DeliveryId
                     SupplierResponse EstimatedDeliveryDate RejectionReason
                     LastResponseId LastResponseVersion )
            WITH VALUE #( ( %tky = action_key-%tky ) )
            RESULT DATA(orders)
          FAILED DATA(read_failed)
          REPORTED DATA(read_reported).
        reported_orders = CORRESPONDING #( DEEP read_reported-purchaseorder ).
        APPEND LINES OF reported_orders TO reported-purchaseorder.

        IF read_failed IS NOT INITIAL OR lines( orders ) <> 1.
          error_text = 'Order could not be read; no response applied.'.
          EXIT.
        ENDIF.

        " ---------- identity guards ----------
        " These are guards, not lookups. The instance was already located by its
        " key; each of these says "and it had better be the one this response
        " was written about". Without them a misrouted response could answer on
        " the strength of someone else's delivery.
        IF orders[ 1 ]-Supplier <> action_key-%param-Supplier.
          error_text = 'Response belongs to a different supplier.'.
          EXIT.
        ENDIF.

        IF orders[ 1 ]-DeliveryId <> action_key-%param-DeliveryUUID.
          error_text = 'Response belongs to a different delivery.'.
          EXIT.
        ENDIF.

        IF orders[ 1 ]-OrderRevision <> action_key-%param-OrderRevision.
          error_text = 'Response belongs to a different revision.'.
          EXIT.
        ENDIF.

        " The one guard that reads a second entity. PortalOrderUUID is NOT on
        " the header: it lives on ZJP_PO_DLV, written by recordDeliveryResult
        " when the receipt came back. A read-only SELECT is used for the same
        " reason the Phase 5.2f handler and the coordinator use one on this
        " table - RAP offers no query for "the intent behind this delivery" -
        " and nothing here writes to it. The inbound action does not own the
        " intent and does not touch it.
        DATA(order_uuid) = orders[ 1 ]-PurchaseOrderUUID.

        SELECT SINGLE portal_order_uuid
          FROM zjp_po_dlv
          WHERE purchase_order_uuid = @order_uuid
            AND delivery_uuid       = @action_key-%param-DeliveryUUID
          INTO @DATA(persisted_portal_order).

        IF sy-subrc <> 0.
          error_text = 'No delivery intent exists for this response.'.
          EXIT.
        ENDIF.

        IF persisted_portal_order <> action_key-%param-PortalOrderUUID.
          error_text = 'Response belongs to a different portal order.'.
          EXIT.
        ENDIF.

        " ---------- idempotency ----------
        " LastResponseId and LastResponseVersion are the receipt. Only the
        " LATEST response is retained, which is a deliberate Phase 6.5 limit:
        " an exact replay of the CURRENT response is recognised, while a replay
        " of a SUPERSEDED one falls through to the staleness rule below and is
        " refused rather than reported as already applied. That is conservative
        " in the safe direction - it never overwrites newer supplier state - and
        " response history is explicitly not persisted in this phase.
        DATA(last_response) = orders[ 1 ]-LastResponseId.
        DATA(last_version)  = orders[ 1 ]-LastResponseVersion.

        IF last_response IS NOT INITIAL
           AND last_response = action_key-%param-ResponseUUID.

          " Same identity. Is it the same EFFECTIVE response?
          "
          " RespondedAt is deliberately NOT compared. It is business-event
          " metadata, not commercial content, so a replay that differs only in
          " when the supplier says it decided is the same answer and must not
          " be turned into a conflict. Only the three commercial facts decide.
          DATA(same_effective) = abap_true.

          IF CONV string( orders[ 1 ]-SupplierResponse ) <> decision.
            same_effective = abap_false.
          ELSEIF decision = 'ACCEPTED'
                 AND orders[ 1 ]-EstimatedDeliveryDate <> action_key-%param-EstimatedDeliveryDate.
            same_effective = abap_false.
          ELSEIF decision = 'REJECTED'
                 AND orders[ 1 ]-RejectionReason <> action_key-%param-Reason.
            same_effective = abap_false.
          ENDIF.

          IF same_effective = abap_false.
            error_text = 'A different response was already applied under this response identity.'.
            EXIT.
          ENDIF.

          " ALREADY_APPLIED. Success with NO mutation, which is the whole point:
          " a duplicate delivery of the same answer must be harmless. Reported
          " as information so a caller can tell it apart from a fresh apply;
          " how OData surfaces that outcome is Phase 6.5c's question.
          APPEND VALUE #( %tky = action_key-%tky
                          %msg = new_message_with_text(
                            severity = if_abap_behv_message=>severity-information
                            text = 'Supplier response already applied; nothing changed.' ) )
            TO reported-purchaseorder.
          EXIT.
        ENDIF.

        " A different response. It must be strictly newer than the one already
        " applied; equal or older never overwrites newer supplier state.
        " ResponseVersion is the ordering key and RespondedAt is not, because a
        " timestamp minted by another system is not an ordering guarantee.
        IF last_response IS NOT INITIAL
           AND action_key-%param-ResponseVersion <= last_version.
          error_text = 'A newer or equal supplier response has already been applied.'.
          EXIT.
        ENDIF.

        " ---------- state guards and the two transitions ----------
        DATA(current_status)   = CONV string( orders[ 1 ]-Status ).
        DATA(current_response) = CONV string( orders[ 1 ]-SupplierResponse ).

        " SENT only, for both decisions, for Phase 6.5. An order in ERROR with
        " IntegrationStatus UNKNOWN is an AMBIGUOUS outbound case: the portal
        " may hold a delivery SAP could not positively confirm. Letting a
        " supplier response silently resolve that ambiguity would decide a
        " reconciliation question by accident, so it is refused here and the
        " reconciliation of ambiguous outbound states is left as open behaviour.
        IF current_status <> 'SENT'.
          IF decision = 'ACCEPTED'.
            error_text = 'A supplier acceptance is only valid on a sent order.'.
          ELSE.
            error_text = 'A supplier rejection is only valid on a sent order.'.
          ENDIF.
          EXIT.
        ENDIF.

        IF decision = 'ACCEPTED'.

          " A later ACCEPTED on an already ACCEPTED order is CAP's
          " updateEstimatedDeliveryDate path. It exists to carry a date, so a
          " date is mandatory - without one it would be a second commercial
          " acceptance that changes nothing, which is not a thing this contract
          " has. The first ACCEPTED may legitimately arrive without a date.
          IF current_response = 'ACCEPTED'
             AND action_key-%param-EstimatedDeliveryDate IS INITIAL.
            error_text = 'A supplier date update requires an estimated delivery date.'.
            EXIT.
          ENDIF.

          " Status is ABSENT from this field list on purpose. It is the
          " strongest available statement that acceptance does not move the
          " order: the handler cannot change Status here even by mistake, and
          " SENT remains SENT. No CONFIRMED status exists or is needed.
          MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
            ENTITY PurchaseOrder
              UPDATE FIELDS ( SupplierResponse EstimatedDeliveryDate
                              SupplierRespondedAt
                              LastResponseId LastResponseVersion )
              WITH VALUE #( ( %tky                  = action_key-%tky
                              SupplierResponse      = 'ACCEPTED'
                              EstimatedDeliveryDate = action_key-%param-EstimatedDeliveryDate
                              SupplierRespondedAt   = action_key-%param-RespondedAt
                              LastResponseId        = action_key-%param-ResponseUUID
                              LastResponseVersion   = action_key-%param-ResponseVersion ) )
            FAILED DATA(accepted_failed)
            REPORTED DATA(accepted_reported).
          reported_orders = CORRESPONDING #( DEEP accepted_reported-purchaseorder ).
          APPEND LINES OF reported_orders TO reported-purchaseorder.

          IF accepted_failed IS NOT INITIAL.
            error_text = 'Supplier acceptance could not be recorded.'.
            EXIT.
          ENDIF.

        ELSE.

          " CAP CANNOT SEND THIS, so SAP must not accept it. The portal's own
          " state machine requires status RECEIVED for both accept and reject
          " (supplier-service.ts: "Only a received order can be accepted or
          " rejected"), so once an order is ACCEPTED there the supplier has no
          " path to reject it and no such response can legitimately exist.
          "
          " SAP cannot lean on its own Status here, because an acceptance
          " deliberately leaves the order at SENT - the very design decision
          " that makes SupplierResponse the only field carrying the supplier's
          " answer. So the guard has to read the ANSWER, not the status. Without
          " it a forged or misordered REJECTED at a higher version would quietly
          " terminate an order the supplier had already accepted.
          IF current_response = 'ACCEPTED'.
            error_text = 'This order was already accepted; an accepted order cannot then be rejected.'.
            EXIT.
          ENDIF.

          " Rejection IS terminal, which is why it moves Status where an
          " acceptance does not. RejectionOrigin is what tells this apart from
          " the buyer's own reject action, which writes APPROVER and is not
          " touched, reused or reinterpreted by this phase.
          MODIFY ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
            ENTITY PurchaseOrder
              UPDATE FIELDS ( Status SupplierResponse
                              RejectionOrigin RejectionReason
                              SupplierRespondedAt
                              LastResponseId LastResponseVersion )
              WITH VALUE #( ( %tky                = action_key-%tky
                              Status              = 'REJECTED'
                              SupplierResponse    = 'REJECTED'
                              RejectionOrigin     = 'SUPPLIER'
                              RejectionReason     = action_key-%param-Reason
                              SupplierRespondedAt = action_key-%param-RespondedAt
                              LastResponseId      = action_key-%param-ResponseUUID
                              LastResponseVersion = action_key-%param-ResponseVersion ) )
            FAILED DATA(rejected_failed)
            REPORTED DATA(rejected_reported).
          reported_orders = CORRESPONDING #( DEEP rejected_reported-purchaseorder ).
          APPEND LINES OF reported_orders TO reported-purchaseorder.

          IF rejected_failed IS NOT INITIAL.
            error_text = 'Supplier rejection could not be recorded.'.
            EXIT.
          ENDIF.

        ENDIF.

      ENDDO.

      IF error_text IS NOT INITIAL.
        APPEND VALUE #( %tky = action_key-%tky
                        %op-%action-applySupplierResponse = if_abap_behv=>mk-on )
          TO failed-purchaseorder.
        APPEND VALUE #( %tky = action_key-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text = error_text ) )
          TO reported-purchaseorder.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

METHOD get_global_authorizations.

  IF requested_authorizations-%create = if_abap_behv=>mk-on.

    AUTHORITY-CHECK OBJECT 'ZJP_PIH'
      ID 'ZJP_ROLE'
      FIELD 'BUYER'.

    IF sy-subrc = 0.
      result-%create = if_abap_behv=>auth-allowed.
    ELSE.
      result-%create = if_abap_behv=>auth-unauthorized.
    ENDIF.

  ENDIF.

ENDMETHOD.

ENDCLASS.
