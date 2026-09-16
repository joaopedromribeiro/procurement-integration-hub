CLASS zjp_cl_po_draft_probe DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zjp_cl_po_draft_probe IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    " Probe 1: create and delete a draft-only item before its first commit.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( (
          %cid = 'BUFFER_DRAFT_ROOT'
          %is_draft = if_abap_behv=>mk-on
          Supplier = 'SUP001'
          CompanyCode = '1000'
          Currency = 'EUR' ) )
      MAPPED DATA(mapped_buffer_create)
      FAILED DATA(failed_buffer_create)
      REPORTED DATA(reported_buffer_create).

    out->write( name = 'Buffer-only draft create MAPPED'
                data = mapped_buffer_create ).
    out->write( name = 'Buffer-only draft create FAILED'
                data = failed_buffer_create ).
    out->write( name = 'Buffer-only draft create REPORTED'
                data = reported_buffer_create ).

    IF failed_buffer_create IS NOT INITIAL
       OR NOT line_exists( mapped_buffer_create-purchaseorder[
         %cid = 'BUFFER_DRAFT_ROOT' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: buffer-only draft fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(buffer_root_key) = mapped_buffer_create-purchaseorder[
      %cid = 'BUFFER_DRAFT_ROOT' ]-%tky.
    IF buffer_root_key-%is_draft <> if_abap_behv=>mk-on.
      ROLLBACK ENTITIES.
      out->write( 'STOP: buffer-only root was not created as a draft.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( (
          %tky = buffer_root_key
          %target = VALUE #( (
            %cid = 'BUFFER_DRAFT_ITEM'
            %is_draft = if_abap_behv=>mk-on
            ItemNumber = '00010'
            Material = 'MAT001'
            Quantity = 2
            UnitOfMeasure = 'EA'
            NetPrice = 750
            Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_buffer_items)
      FAILED DATA(failed_buffer_items)
      REPORTED DATA(reported_buffer_items).
    out->write( name = 'Buffer-only draft CBA MAPPED' data = mapped_buffer_items ).
    out->write( name = 'Buffer-only draft CBA FAILED' data = failed_buffer_items ).
    out->write( name = 'Buffer-only draft CBA REPORTED' data = reported_buffer_items ).
    IF failed_buffer_items IS NOT INITIAL
       OR NOT line_exists( mapped_buffer_items-purchaseorderitem[
         %cid = 'BUFFER_DRAFT_ITEM' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: buffer-only draft item creation failed.' ).
      RETURN.
    ENDIF.

    DATA(buffer_item_key) = mapped_buffer_items-purchaseorderitem[
      %cid = 'BUFFER_DRAFT_ITEM' ]-%tky.
    IF buffer_item_key-%is_draft <> if_abap_behv=>mk-on.
      ROLLBACK ENTITIES.
      out->write( 'STOP: buffer-only item was not created as a draft.' ).
      RETURN.
    ENDIF.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = buffer_root_key ) )
        RESULT DATA(buffer_roots_before_delete)
      FAILED DATA(failed_buffer_before).
    IF failed_buffer_before IS NOT INITIAL
       OR lines( buffer_roots_before_delete ) <> 1
       OR buffer_roots_before_delete[ 1 ]-TotalAmount <> 1500
       OR buffer_roots_before_delete[ 1 ]-Status <> 'DRAFT'.
      ROLLBACK ENTITIES.
      out->write( 'STOP: buffer-only draft must start with total 1500 and business Status DRAFT.' ).
      RETURN.
    ENDIF.
    out->write( name = 'Buffer-only known root %tky' data = buffer_root_key ).
    out->write( name = 'Buffer-only item %tky' data = buffer_item_key ).

    " Phase 2.7A: submit is active-only and must reject this buffer-only draft.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = buffer_root_key ) )
      FAILED DATA(failed_buffer_submit)
      REPORTED DATA(reported_buffer_submit).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = buffer_root_key ) )
        RESULT DATA(buffer_roots_after_submit)
      FAILED DATA(failed_buffer_submit_read).

    out->write( name = 'Buffer-only submit FAILED - expect rejection'
                data = failed_buffer_submit ).
    out->write( name = 'Buffer-only submit REPORTED'
                data = reported_buffer_submit ).
    out->write( name = 'Buffer-only root after submit attempt'
                data = buffer_roots_after_submit ).

    DATA(buffer_submit_failed_key) = xsdbool( line_exists(
      failed_buffer_submit-purchaseorder[ %tky = buffer_root_key
        %op-%action-submit = if_abap_behv=>mk-on ] ) ).
    DATA(expected_draft_submit_text) =
      CONV string( 'Submit is not allowed on a draft instance.' ).
    DATA(buffer_submit_message) = abap_false.
    LOOP AT reported_buffer_submit-purchaseorder INTO DATA(buffer_submit_line).
      IF buffer_submit_line-%msg IS BOUND.
        DATA(actual_buffer_submit_text) =
          buffer_submit_line-%msg->if_message~get_text( ).
        IF buffer_submit_line-%tky = buffer_root_key
           AND buffer_submit_line-%op-%action-submit = if_abap_behv=>mk-on
           AND actual_buffer_submit_text = expected_draft_submit_text.
          buffer_submit_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF buffer_submit_failed_key = abap_false
       OR buffer_submit_message = abap_false
       OR failed_buffer_submit_read IS NOT INITIAL
       OR lines( buffer_roots_after_submit ) <> 1
       OR buffer_roots_after_submit[ 1 ]-%is_draft <> if_abap_behv=>mk-on
       OR buffer_roots_after_submit[ 1 ]-Status <> 'DRAFT'
       OR buffer_roots_after_submit[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      out->write( 'STOP: submit must be rejected on a buffer-only draft without changing it.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: submit rejected on buffer-only draft; Status DRAFT and total 1500 unchanged.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = buffer_root_key
          %param-PurchaseOrderItemUUID = buffer_item_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_buffer_delete)
      REPORTED DATA(reported_buffer_delete).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = buffer_root_key ) )
        RESULT DATA(buffer_roots_after_delete)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = buffer_root_key ) )
        RESULT DATA(buffer_items_after_delete)
      FAILED DATA(failed_buffer_navigation)
      REPORTED DATA(reported_buffer_navigation).

    out->write( name = 'Buffer-only delete FAILED' data = failed_buffer_delete ).
    out->write( name = 'Buffer-only delete REPORTED' data = reported_buffer_delete ).
    out->write( name = 'Buffer-only root after item delete'
                data = buffer_roots_after_delete ).
    out->write( name = 'Buffer-only items after item delete - expect empty'
                data = buffer_items_after_delete ).
    out->write( name = 'Buffer-only navigation FAILED'
                data = failed_buffer_navigation ).
    out->write( name = 'Buffer-only navigation REPORTED'
                data = reported_buffer_navigation ).

    DATA(buffer_probe_passed) = xsdbool(
      failed_buffer_delete IS INITIAL
      AND failed_buffer_navigation IS INITIAL
      AND lines( buffer_roots_after_delete ) = 1
      AND buffer_items_after_delete IS INITIAL
      AND buffer_roots_after_delete[ 1 ]-%is_draft = if_abap_behv=>mk-on
      AND buffer_roots_after_delete[ 1 ]-TotalAmount = 0
      AND buffer_roots_after_delete[ 1 ]-Status = 'DRAFT' ).
    ROLLBACK ENTITIES.
    IF buffer_probe_passed = abap_false.
      out->write( 'STOP: buffer-only known-parent draft navigation failed.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: removeItem buffer-only draft total 1500/0; rollback complete.' ).

    " Probe 2: save a two-item draft, then inspect one-item and last-item deletes.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( (
          %cid = 'SAVED_DRAFT_ROOT'
          %is_draft = if_abap_behv=>mk-on
          Supplier = 'SUP001'
          CompanyCode = '1000'
          Currency = 'EUR' ) )
      MAPPED DATA(mapped_saved_create)
      FAILED DATA(failed_saved_create)
      REPORTED DATA(reported_saved_create).

    out->write( name = 'Saved-draft create MAPPED' data = mapped_saved_create ).
    out->write( name = 'Saved-draft create FAILED' data = failed_saved_create ).
    out->write( name = 'Saved-draft create REPORTED' data = reported_saved_create ).
    IF failed_saved_create IS NOT INITIAL
       OR NOT line_exists( mapped_saved_create-purchaseorder[
         %cid = 'SAVED_DRAFT_ROOT' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(saved_create_root_key) = mapped_saved_create-purchaseorder[
      %cid = 'SAVED_DRAFT_ROOT' ]-%tky.
    IF saved_create_root_key-%is_draft <> if_abap_behv=>mk-on.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft root was not created as a draft.' ).
      RETURN.
    ENDIF.
    out->write( name = 'Saved draft CBA source %tky' data = saved_create_root_key ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( (
          %tky = saved_create_root_key
          %target = VALUE #( (
            %cid = 'SAVED_DRAFT_ITEM_1'
            %is_draft = if_abap_behv=>mk-on
            ItemNumber = '00010'
            Material = 'MAT001'
            Quantity = 2
            UnitOfMeasure = 'EA'
            NetPrice = 750
            Currency = 'EUR' )
          ( %cid = 'SAVED_DRAFT_ITEM_2'
            %is_draft = if_abap_behv=>mk-on
            ItemNumber = '00020'
            Material = 'MAT002'
            Quantity = 4
            UnitOfMeasure = 'EA'
            NetPrice = 100
            Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_saved_items)
      FAILED DATA(failed_saved_items)
      REPORTED DATA(reported_saved_items).
    out->write( name = 'Saved draft CBA MAPPED' data = mapped_saved_items ).
    out->write( name = 'Saved draft CBA FAILED' data = failed_saved_items ).
    out->write( name = 'Saved draft CBA REPORTED' data = reported_saved_items ).
    IF failed_saved_items IS NOT INITIAL
       OR NOT line_exists( mapped_saved_items-purchaseorderitem[
         %cid = 'SAVED_DRAFT_ITEM_1' ] )
       OR NOT line_exists( mapped_saved_items-purchaseorderitem[
         %cid = 'SAVED_DRAFT_ITEM_2' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft item creation failed.' ).
      RETURN.
    ENDIF.
    IF mapped_saved_items-purchaseorderitem[
         %cid = 'SAVED_DRAFT_ITEM_1' ]-%is_draft <> if_abap_behv=>mk-on
       OR mapped_saved_items-purchaseorderitem[
         %cid = 'SAVED_DRAFT_ITEM_2' ]-%is_draft <> if_abap_behv=>mk-on.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft items were not created as drafts.' ).
      RETURN.
    ENDIF.

    DATA(saved_root_uuid) = saved_create_root_key-PurchaseOrderUUID.
    out->write( name = 'Saved-draft root UUID - retain for cleanup'
                data = saved_root_uuid ).

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_draft_save)
      REPORTED DATA(reported_draft_save).
    DATA(draft_save_subrc) = sy-subrc.
    out->write( name = 'Saved-draft COMMIT sy-subrc' data = draft_save_subrc ).
    out->write( name = 'Saved-draft COMMIT FAILED' data = failed_draft_save ).
    out->write( name = 'Saved-draft COMMIT REPORTED' data = reported_draft_save ).
    IF draft_save_subrc <> 0 OR failed_draft_save IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saving the diagnostic draft failed.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( (
          PurchaseOrderUUID = saved_root_uuid
          %is_draft = if_abap_behv=>mk-on ) )
        RESULT DATA(saved_roots)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( (
          PurchaseOrderUUID = saved_root_uuid
          %is_draft = if_abap_behv=>mk-on ) )
        RESULT DATA(saved_items)
      FAILED DATA(failed_saved_read)
      REPORTED DATA(reported_saved_read).

    out->write( name = 'Saved draft root' data = saved_roots ).
    out->write( name = 'Saved draft items' data = saved_items ).
    out->write( name = 'Saved draft read FAILED' data = failed_saved_read ).
    out->write( name = 'Saved draft read REPORTED' data = reported_saved_read ).
    IF failed_saved_read IS NOT INITIAL
       OR lines( saved_roots ) <> 1 OR lines( saved_items ) <> 2
       OR saved_roots[ 1 ]-TotalAmount <> 1900
       OR saved_roots[ 1 ]-Status <> 'DRAFT'
       OR NOT line_exists( saved_items[ ItemNumber = '00010' ] )
       OR NOT line_exists( saved_items[ ItemNumber = '00020' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected one saved draft root with two items.' ).
      RETURN.
    ENDIF.

    DATA(saved_root_key) = saved_roots[ 1 ]-%tky.
    DATA(saved_item_1_key) = saved_items[ ItemNumber = '00010' ]-%tky.
    DATA(saved_item_2_key) = saved_items[ ItemNumber = '00020' ]-%tky.
    IF saved_root_key-%is_draft <> if_abap_behv=>mk-on
       OR saved_item_1_key-%is_draft <> if_abap_behv=>mk-on
       OR saved_item_2_key-%is_draft <> if_abap_behv=>mk-on.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved fixture read did not return draft identities.' ).
      RETURN.
    ENDIF.
    out->write( name = 'Saved draft known root %tky' data = saved_root_key ).

    " Phase 2.7A: a saved draft is still a draft and must also be rejected.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = saved_root_key ) )
      FAILED DATA(failed_saved_submit)
      REPORTED DATA(reported_saved_submit).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(saved_roots_after_submit)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(saved_items_after_submit)
      FAILED DATA(failed_saved_submit_read).

    out->write( name = 'Saved draft submit FAILED - expect rejection'
                data = failed_saved_submit ).
    out->write( name = 'Saved draft submit REPORTED'
                data = reported_saved_submit ).
    out->write( name = 'Saved draft root after submit attempt'
                data = saved_roots_after_submit ).
    out->write( name = 'Saved draft items after submit attempt'
                data = saved_items_after_submit ).

    DATA(saved_submit_failed_key) = xsdbool( line_exists(
      failed_saved_submit-purchaseorder[ %tky = saved_root_key
        %op-%action-submit = if_abap_behv=>mk-on ] ) ).
    DATA(expected_saved_submit_text) =
      CONV string( 'Submit is not allowed on a draft instance.' ).
    DATA(saved_submit_message) = abap_false.
    LOOP AT reported_saved_submit-purchaseorder INTO DATA(saved_submit_line).
      IF saved_submit_line-%msg IS BOUND.
        DATA(actual_saved_submit_text) =
          saved_submit_line-%msg->if_message~get_text( ).
        IF saved_submit_line-%tky = saved_root_key
           AND saved_submit_line-%op-%action-submit = if_abap_behv=>mk-on
           AND actual_saved_submit_text = expected_saved_submit_text.
          saved_submit_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF saved_submit_failed_key = abap_false
       OR saved_submit_message = abap_false
       OR failed_saved_submit_read IS NOT INITIAL
       OR lines( saved_roots_after_submit ) <> 1
       OR lines( saved_items_after_submit ) <> 2
       OR saved_roots_after_submit[ 1 ]-%is_draft <> if_abap_behv=>mk-on
       OR saved_roots_after_submit[ 1 ]-Status <> 'DRAFT'
       OR saved_roots_after_submit[ 1 ]-TotalAmount <> 1900.
      ROLLBACK ENTITIES.
      out->write( 'STOP: submit must be rejected on a saved draft without changing it.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: submit rejected on saved draft; Status DRAFT and total 1900 unchanged.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = saved_root_key
          %param-PurchaseOrderItemUUID = saved_item_2_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_saved_item_2_delete)
      REPORTED DATA(reported_saved_item_2_delete).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(saved_roots_after_one_delete)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(saved_items_after_one_delete)
      FAILED DATA(failed_saved_one_navigation)
      REPORTED DATA(reported_saved_one_navigation).

    out->write( name = 'Saved draft first delete FAILED'
                data = failed_saved_item_2_delete ).
    out->write( name = 'Saved draft first delete REPORTED'
                data = reported_saved_item_2_delete ).
    out->write( name = 'Saved draft root after deleting 00020'
                data = saved_roots_after_one_delete ).
    out->write( name = 'Saved draft items after deleting 00020 - expect 00010'
                data = saved_items_after_one_delete ).
    out->write( name = 'Saved draft first navigation FAILED'
                data = failed_saved_one_navigation ).
    out->write( name = 'Saved draft first navigation REPORTED'
                data = reported_saved_one_navigation ).

    IF failed_saved_item_2_delete IS NOT INITIAL
       OR failed_saved_one_navigation IS NOT INITIAL
       OR lines( saved_roots_after_one_delete ) <> 1
       OR lines( saved_items_after_one_delete ) <> 1
       OR saved_items_after_one_delete[ 1 ]-ItemNumber <> '00010'
       OR saved_roots_after_one_delete[ 1 ]-TotalAmount <> 1500
       OR saved_items_after_one_delete[ 1 ]-TotalAmount <> 1500
       OR saved_roots_after_one_delete[ 1 ]-%is_draft <> if_abap_behv=>mk-on
       OR saved_items_after_one_delete[ 1 ]-%is_draft <> if_abap_behv=>mk-on.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft navigation after first delete failed.' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_one_delete_save)
      REPORTED DATA(reported_one_delete_save).
    DATA(one_delete_subrc) = sy-subrc.
    out->write( name = 'one_delete COMMIT sy-subrc' data = one_delete_subrc ).
    out->write( name = 'one_delete COMMIT FAILED' data = failed_one_delete_save ).
    out->write( name = 'one_delete COMMIT REPORTED' data = reported_one_delete_save ).
    IF one_delete_subrc <> 0 OR failed_one_delete_save IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft removal commit failed; retain the printed root UUID.' ).
      RETURN.
    ENDIF.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(roots_one_delete_saved)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(items_one_delete_saved)
      FAILED DATA(failed_one_delete_reread)
      REPORTED DATA(reported_one_delete_reread).
    out->write( name = 'one_delete root after commit' data = roots_one_delete_saved ).
    out->write( name = 'one_delete items after commit' data = items_one_delete_saved ).
    out->write( name = 'one_delete reread FAILED' data = failed_one_delete_reread ).
    out->write( name = 'one_delete reread REPORTED' data = reported_one_delete_reread ).
    IF failed_one_delete_reread IS NOT INITIAL
       OR lines( roots_one_delete_saved ) <> 1
       OR roots_one_delete_saved[ 1 ]-%tky <> saved_root_key
       OR roots_one_delete_saved[ 1 ]-TotalAmount <> 1500
       OR roots_one_delete_saved[ 1 ]-Status <> 'DRAFT'
       OR lines( items_one_delete_saved ) <> 1
       OR items_one_delete_saved[ 1 ]-%tky <> saved_item_1_key
       OR items_one_delete_saved[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft total or surviving collection differs after commit.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = saved_root_key
          %param-PurchaseOrderItemUUID = saved_item_1_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_saved_last_delete)
      REPORTED DATA(reported_saved_last_delete).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(saved_roots_after_last_delete)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(saved_items_after_last_delete)
      FAILED DATA(failed_saved_last_navigation)
      REPORTED DATA(reported_saved_last_navigation).

    out->write( name = 'Saved draft last delete FAILED'
                data = failed_saved_last_delete ).
    out->write( name = 'Saved draft last delete REPORTED'
                data = reported_saved_last_delete ).
    out->write( name = 'Saved draft root after last item delete'
                data = saved_roots_after_last_delete ).
    out->write( name = 'Saved draft items after last delete - expect empty'
                data = saved_items_after_last_delete ).
    out->write( name = 'Saved draft last navigation FAILED'
                data = failed_saved_last_navigation ).
    out->write( name = 'Saved draft last navigation REPORTED'
                data = reported_saved_last_navigation ).

    DATA(saved_probe_passed) = xsdbool(
      failed_saved_last_delete IS INITIAL
      AND failed_saved_last_navigation IS INITIAL
      AND lines( saved_roots_after_last_delete ) = 1
      AND saved_items_after_last_delete IS INITIAL
      AND saved_roots_after_last_delete[ 1 ]-%is_draft = if_abap_behv=>mk-on
      AND saved_roots_after_last_delete[ 1 ]-TotalAmount = 0 ).

    IF saved_probe_passed = abap_false.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft navigation after last delete failed.' ).
      RETURN.
    ENDIF.
    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_last_delete_save)
      REPORTED DATA(reported_last_delete_save).
    DATA(last_delete_subrc) = sy-subrc.
    out->write( name = 'last_delete COMMIT sy-subrc' data = last_delete_subrc ).
    out->write( name = 'last_delete COMMIT FAILED' data = failed_last_delete_save ).
    out->write( name = 'last_delete COMMIT REPORTED' data = reported_last_delete_save ).
    IF last_delete_subrc <> 0 OR failed_last_delete_save IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft removal commit failed; retain the printed root UUID.' ).
      RETURN.
    ENDIF.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(roots_last_delete_saved)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(items_last_delete_saved)
      FAILED DATA(failed_last_delete_reread)
      REPORTED DATA(reported_last_delete_reread).
    out->write( name = 'last_delete root after commit' data = roots_last_delete_saved ).
    out->write( name = 'last_delete items after commit' data = items_last_delete_saved ).
    out->write( name = 'last_delete reread FAILED' data = failed_last_delete_reread ).
    out->write( name = 'last_delete reread REPORTED' data = reported_last_delete_reread ).
    IF failed_last_delete_reread IS NOT INITIAL
       OR lines( roots_last_delete_saved ) <> 1
       OR roots_last_delete_saved[ 1 ]-%tky <> saved_root_key
       OR roots_last_delete_saved[ 1 ]-TotalAmount <> 0
       OR roots_last_delete_saved[ 1 ]-Status <> 'DRAFT'
       OR lines( items_last_delete_saved ) <> 0.
      ROLLBACK ENTITIES.
      out->write( 'STOP: saved-draft total or surviving collection differs after commit.' ).
      RETURN.
    ENDIF.

    out->write( 'PASS: removeItem saved draft totals 1900/1500/0; both deletion commits pass.' ).

    " Remove the saved diagnostic draft through its framework draft action.
    DATA failed_discard TYPE RESPONSE FOR FAILED ZJP_I_PurchaseOrder.
    DATA reported_discard TYPE RESPONSE FOR REPORTED ZJP_I_PurchaseOrder.

    " Discard selects the draft implicitly; its input uses %key, not %tky.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE Discard FROM VALUE #( (
          %key-PurchaseOrderUUID = saved_root_uuid ) )
      FAILED failed_discard
      REPORTED reported_discard.
    out->write( name = 'Diagnostic draft Discard FAILED' data = failed_discard ).
    out->write( name = 'Diagnostic draft Discard REPORTED' data = reported_discard ).
    IF failed_discard IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: draft probe passed but cleanup failed; use the printed root UUID.' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_discard_save)
      REPORTED DATA(reported_discard_save).
    DATA(discard_subrc) = sy-subrc.
    out->write( name = 'Diagnostic draft cleanup COMMIT sy-subrc'
                data = discard_subrc ).
    out->write( name = 'Diagnostic draft cleanup FAILED'
                data = failed_discard_save ).
    out->write( name = 'Diagnostic draft cleanup REPORTED'
                data = reported_discard_save ).
    IF discard_subrc <> 0 OR failed_discard_save IS NOT INITIAL.
      out->write( 'STOP: draft probe passed but cleanup commit failed; use the printed root UUID.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = saved_root_key ) )
        RESULT DATA(drafts_after_discard)
      FAILED DATA(failed_cleanup_read)
      REPORTED DATA(reported_cleanup_read).
    out->write( name = 'Discard cleanup read FAILED - expect NOT_FOUND'
                data = failed_cleanup_read ).
    out->write( name = 'Discard cleanup read REPORTED'
                data = reported_cleanup_read ).
    IF drafts_after_discard IS NOT INITIAL
       OR NOT line_exists( failed_cleanup_read-purchaseorder[
         PurchaseOrderUUID = saved_root_uuid
         %is_draft = if_abap_behv=>mk-on
         %fail-cause = if_abap_behv=>cause-not_found ] ).
      out->write( 'STOP: expected saved draft to be absent after Discard commit.' ).
      RETURN.
    ENDIF.

    out->write( 'PASS: removeItem saved and buffer-only draft deletion; totals and cleanup pass.' ).

    " Probe 3, Phase 2.7B: a technical draft taken from a SUBMITTED order
    " carries Status SUBMITTED on this target, so the precheck must reject
    " commercial changes on the draft instance too.
    DATA failed_lock_edit TYPE RESPONSE FOR FAILED ZJP_I_PurchaseOrder.
    DATA reported_lock_edit TYPE RESPONSE FOR REPORTED ZJP_I_PurchaseOrder.
    DATA failed_lock_discard TYPE RESPONSE FOR FAILED ZJP_I_PurchaseOrder.
    DATA reported_lock_discard TYPE RESPONSE FOR REPORTED ZJP_I_PurchaseOrder.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'LOCK_DRAFT_ROOT'
                        Supplier = 'SUP008'
                        CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'LOCK_DRAFT_ROOT'
          %target = VALUE #( ( %cid = 'LOCK_DRAFT_ITEM' ItemNumber = '00010'
                               Material = 'MAT001' Quantity = 2
                               UnitOfMeasure = 'EA' NetPrice = '750.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_lock_draft)
      FAILED DATA(failed_lock_draft_create)
      REPORTED DATA(reported_lock_draft_create).
    out->write( name = 'Submitted-draft fixture FAILED'
                data = failed_lock_draft_create ).
    IF failed_lock_draft_create IS NOT INITIAL
       OR NOT line_exists( mapped_lock_draft-purchaseorder[
            %cid = 'LOCK_DRAFT_ROOT' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: submitted-draft fixture creation failed.' ).
      RETURN.
    ENDIF.
    DATA(lock_draft_uuid) = mapped_lock_draft-purchaseorder[
      %cid = 'LOCK_DRAFT_ROOT' ]-PurchaseOrderUUID.
    out->write( name = 'Submitted-draft root UUID - retain for cleanup'
                data = lock_draft_uuid ).

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_lock_draft_save)
      REPORTED DATA(reported_lock_draft_save).
    DATA(lock_draft_subrc) = sy-subrc.
    out->write( name = 'Submitted-draft fixture COMMIT sy-subrc'
                data = lock_draft_subrc ).
    IF lock_draft_subrc <> 0 OR failed_lock_draft_save IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: submitted-draft fixture commit failed.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = lock_draft_uuid ) )
        RESULT DATA(lock_active_rows)
      FAILED DATA(failed_lock_active_read).
    IF failed_lock_active_read IS NOT INITIAL
       OR lines( lock_active_rows ) <> 1.
      ROLLBACK ENTITIES.
      out->write( 'STOP: submitted-draft fixture could not be read.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = lock_active_rows[ 1 ]-%tky ) )
      FAILED DATA(failed_lock_draft_submit)
      REPORTED DATA(reported_lock_draft_submit).
    IF failed_lock_draft_submit IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: submit failed on the submitted-draft fixture.' ).
      RETURN.
    ENDIF.
    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_lock_submit_save)
      REPORTED DATA(reported_lock_submit_save).
    DATA(lock_submit_subrc) = sy-subrc.
    out->write( name = 'Submitted-draft submit COMMIT sy-subrc'
                data = lock_submit_subrc ).
    IF lock_submit_subrc <> 0.
      ROLLBACK ENTITIES.
      out->write( 'STOP: submit commit failed on the submitted-draft fixture.' ).
      RETURN.
    ENDIF.

    " Edit is instance-generating and needs %cid; its input uses %key.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE Edit FROM VALUE #( (
          %cid = 'LOCK_DRAFT_EDIT'
          %key-PurchaseOrderUUID = lock_draft_uuid ) )
      FAILED failed_lock_edit
      REPORTED reported_lock_edit.
    out->write( name = 'Submitted-order Edit FAILED' data = failed_lock_edit ).
    out->write( name = 'Submitted-order Edit REPORTED' data = reported_lock_edit ).
    IF failed_lock_edit IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: Edit on a SUBMITTED order failed; probe 3 cannot run.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = lock_draft_uuid
                                   %is_draft = if_abap_behv=>mk-on ) )
        RESULT DATA(lock_draft_rows)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = lock_draft_uuid
                                   %is_draft = if_abap_behv=>mk-on ) )
        RESULT DATA(lock_draft_items)
      FAILED DATA(failed_lock_draft_read).
    out->write( name = 'Draft of a SUBMITTED order' data = lock_draft_rows ).
    out->write( name = 'Draft items of a SUBMITTED order' data = lock_draft_items ).
    IF failed_lock_draft_read IS NOT INITIAL
       OR lines( lock_draft_rows ) <> 1 OR lines( lock_draft_items ) <> 1
       OR lock_draft_rows[ 1 ]-Status <> 'SUBMITTED'.
      ROLLBACK ENTITIES.
      out->write( 'STOP: the draft of a submitted order must carry Status SUBMITTED.' ).
      RETURN.
    ENDIF.
    DATA(lock_draft_key) = lock_draft_rows[ 1 ]-%tky.
    DATA(lock_draft_item_key) = lock_draft_items[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = lock_draft_key Supplier = 'SUP999' ) )
      FAILED DATA(failed_draft_root_update)
      REPORTED DATA(reported_draft_root_update).
    out->write( name = 'Draft root update FAILED - expect rejection'
                data = failed_draft_root_update ).
    out->write( name = 'Draft root update REPORTED'
                data = reported_draft_root_update ).
    DATA(draft_root_blocked) = xsdbool( line_exists(
      failed_draft_root_update-purchaseorder[ %tky = lock_draft_key ] ) ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = lock_draft_item_key Quantity = 99 ) )
      FAILED DATA(failed_draft_item_update)
      REPORTED DATA(reported_draft_item_update).
    out->write( name = 'Draft item update FAILED - expect rejection'
                data = failed_draft_item_update ).
    out->write( name = 'Draft item update REPORTED'
                data = reported_draft_item_update ).
    DATA(draft_item_blocked) = xsdbool( line_exists(
      failed_draft_item_update-purchaseorderitem[
        %tky = lock_draft_item_key ] ) ).

    " Phase 2.7C: approve and reject are active-only, exactly like submit.
    " Run while the draft still exists, before the rollback below.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = lock_draft_key ) )
      FAILED DATA(failed_draft_approve)
      REPORTED DATA(reported_draft_approve).
    out->write( name = 'Draft approve FAILED - expect rejection'
                data = failed_draft_approve ).
    out->write( name = 'Draft approve REPORTED' data = reported_draft_approve ).
    DATA(draft_approve_blocked) = xsdbool( line_exists(
      failed_draft_approve-purchaseorder[ %tky = lock_draft_key
        %op-%action-approve = if_abap_behv=>mk-on ] ) ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE reject FROM VALUE #( (
          %tky = lock_draft_key
          %param-RejectionReason = 'Draft decision attempt' ) )
      FAILED DATA(failed_draft_reject)
      REPORTED DATA(reported_draft_reject).
    out->write( name = 'Draft reject FAILED - expect rejection'
                data = failed_draft_reject ).
    out->write( name = 'Draft reject REPORTED' data = reported_draft_reject ).
    DATA(draft_reject_blocked) = xsdbool( line_exists(
      failed_draft_reject-purchaseorder[ %tky = lock_draft_key
        %op-%action-reject = if_abap_behv=>mk-on ] ) ).

    " Phase 2.7D-1: cancel is active-only too. Run while the draft still
    " exists, before the rollback below.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE cancel FROM VALUE #( ( %tky = lock_draft_key ) )
      FAILED DATA(failed_draft_cancel)
      REPORTED DATA(reported_draft_cancel).
    out->write( name = 'Draft cancel FAILED - expect rejection'
                data = failed_draft_cancel ).
    out->write( name = 'Draft cancel REPORTED' data = reported_draft_cancel ).
    DATA(draft_cancel_blocked) = xsdbool( line_exists(
      failed_draft_cancel-purchaseorder[ %tky = lock_draft_key
        %op-%action-cancel = if_abap_behv=>mk-on ] ) ).
    DATA(draft_cancel_message) = abap_false.
    LOOP AT reported_draft_cancel-purchaseorder INTO DATA(draft_cancel_line).
      IF draft_cancel_line-%msg IS BOUND.
        IF draft_cancel_line-%msg->if_message~get_text( )
           = 'Not allowed on a draft instance.'.
          draft_cancel_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    ROLLBACK ENTITIES.
    IF draft_root_blocked = abap_false OR draft_item_blocked = abap_false
       OR draft_approve_blocked = abap_false
       OR draft_reject_blocked = abap_false.
      out->write( 'STOP: a SUBMITTED draft must reject changes and decisions.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: SUBMITTED draft rejected root and item updates plus approve and reject.' ).

    IF draft_cancel_blocked = abap_false
       OR draft_cancel_message = abap_false.
      out->write( 'STOP: a SUBMITTED draft must reject cancel.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: Phase 2.7D-1 technical draft refuses cancel.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE Discard FROM VALUE #( (
          %key-PurchaseOrderUUID = lock_draft_uuid ) )
      FAILED failed_lock_discard
      REPORTED reported_lock_discard.
    out->write( name = 'Submitted-draft Discard FAILED' data = failed_lock_discard ).
    IF failed_lock_discard IS INITIAL.
      COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
        FAILED DATA(failed_lock_discard_save)
        REPORTED DATA(reported_lock_discard_save).
      out->write( name = 'Submitted-draft Discard COMMIT sy-subrc' data = sy-subrc ).
    ELSE.
      ROLLBACK ENTITIES.
    ENDIF.

    " The technical draft is gone. What remains is the ACTIVE order, which is
    " SUBMITTED, so from Phase 2.7D-2 onwards root DELETE no longer removes
    " it. Draft Discard above and business root DELETE here are different
    " operations and only the second one changed.
    out->write( name = 'Terminal residue UUID - retain for manual cleanup'
                data = lock_draft_uuid ).
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( PurchaseOrderUUID = lock_draft_uuid ) )
      FAILED DATA(failed_lock_draft_delete)
      REPORTED DATA(reported_lock_draft_delete).
    out->write( name = 'Submitted-active DELETE FAILED - expect rejection'
                data = failed_lock_draft_delete ).
    out->write( name = 'Submitted-active DELETE REPORTED'
                data = reported_lock_draft_delete ).
    DATA(lock_delete_blocked) = xsdbool(
      failed_lock_draft_delete IS NOT INITIAL ).
    DATA(lock_delete_message) = abap_false.
    LOOP AT reported_lock_draft_delete-purchaseorder INTO DATA(lock_delete_line).
      IF lock_delete_line-%msg IS BOUND.
        IF lock_delete_line-%msg->if_message~get_text( )
           = 'Only draft orders can be deleted.'.
          lock_delete_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    SELECT COUNT(*) FROM zjp_po_h
      WHERE purchase_order_uuid = @lock_draft_uuid INTO @DATA(lock_headers_left).
    SELECT COUNT(*) FROM zjp_po_i
      WHERE purchase_order_uuid = @lock_draft_uuid INTO @DATA(lock_items_left).
    SELECT SINGLE status FROM zjp_po_h
      WHERE purchase_order_uuid = @lock_draft_uuid INTO @DATA(lock_status_left).
    out->write( name = 'Submitted-active surviving headers - expect 1'
                data = lock_headers_left ).
    out->write( name = 'Submitted-active surviving items - expect 1'
                data = lock_items_left ).
    out->write( name = 'Submitted-active surviving status' data = lock_status_left ).
    IF lock_delete_blocked = abap_false OR lock_delete_message = abap_false
       OR lock_headers_left <> 1 OR lock_items_left <> 1
       OR lock_status_left <> 'SUBMITTED'.
      out->write( 'STOP: a SUBMITTED active order accepted root DELETE.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: Phase 2.7B draft immutability verified.' ).
    out->write( 'PASS: Phase 2.7D-2 SUBMITTED root DELETE rejected; row kept.' ).
  ENDMETHOD.
ENDCLASS.
