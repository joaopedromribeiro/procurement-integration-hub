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
  ENDMETHOD.
ENDCLASS.
