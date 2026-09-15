CLASS zjp_cl_po_eml_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    METHODS test_supplier_required
      IMPORTING existing_uuid TYPE sysuuid_x16 OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_quantity_validation
      IMPORTING existing_order_uuid TYPE sysuuid_x16 OPTIONAL
                existing_item_uuid  TYPE sysuuid_x16 OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS save_changes
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_net_price_validation
      IMPORTING existing_order_uuid TYPE sysuuid_x16 OPTIONAL
                existing_item_uuid  TYPE sysuuid_x16 OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_zero_net_price
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS check_price_buffer
      IMPORTING order_uuid     TYPE sysuuid_x16
                item_uuid      TYPE sysuuid_x16
                expected_price TYPE zjp_po_i-net_price
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS check_database
      IMPORTING order_uuid            TYPE sysuuid_x16
                expected_headers      TYPE i
                expected_items        TYPE i
                expected_supplier     TYPE zjp_po_h-supplier OPTIONAL
                expected_header_total TYPE zjp_po_h-total_amount OPTIONAL
                expected_quantity     TYPE zjp_po_i-quantity OPTIONAL
                expected_net_price    TYPE zjp_po_i-net_price OPTIONAL
                expected_item_total   TYPE zjp_po_i-total_amount OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_submit_active
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_submit_requires_item
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS check_submit_database
      IMPORTING order_uuid            TYPE sysuuid_x16
                expected_headers      TYPE i
                expected_items        TYPE i
                expected_status       TYPE zjp_po_h-status OPTIONAL
                expected_header_total TYPE zjp_po_h-total_amount OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.
ENDCLASS.

CLASS zjp_cl_po_eml_test IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    console = out.

    IF test_supplier_required( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_quantity_validation( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_net_price_validation( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_zero_net_price( ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode PurchasingOrganization
                        PurchasingGroup Currency )
        WITH VALUE #( (
          %cid = 'PO_1'
          Supplier = 'SUP001'
          CompanyCode = '1000'
          PurchasingOrganization = '1000'
          PurchasingGroup = '001'
          Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material MaterialDescription Quantity
                 UnitOfMeasure NetPrice Currency )
        WITH VALUE #( (
          %cid_ref = 'PO_1'
          %target = VALUE #( (
            %cid = 'ITEM_1'
            ItemNumber = '00010'
            Material = 'MAT001'
            MaterialDescription = 'EML study laptop'
            Quantity = 2
            UnitOfMeasure = 'EA'
            NetPrice = '750.00'
            Currency = 'EUR' )
          ( %cid = 'ITEM_2'
            ItemNumber = '00020'
            Material = 'MAT002'
            MaterialDescription = 'EML study accessory'
            Quantity = 4
            UnitOfMeasure = 'EA'
            NetPrice = '100.00'
            Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_create)
      FAILED DATA(failed_create)
      REPORTED DATA(reported_create).

    out->write( name = 'Create MAPPED' data = mapped_create ).
    out->write( name = 'Create FAILED' data = failed_create ).
    out->write( name = 'Create REPORTED' data = reported_create ).

    IF failed_create IS NOT INITIAL
       OR NOT line_exists( mapped_create-purchaseorder[ %cid = 'PO_1' ] )
       OR NOT line_exists( mapped_create-purchaseorderitem[ %cid = 'ITEM_1' ] )
       OR NOT line_exists( mapped_create-purchaseorderitem[ %cid = 'ITEM_2' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: create failed; unsaved work rolled back.' ).
      RETURN.
    ENDIF.

    DATA(order_uuid) =
      mapped_create-purchaseorder[ %cid = 'PO_1' ]-PurchaseOrderUUID.
    out->write( name = 'Test order UUID - retain for diagnosis' data = order_uuid ).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(items)
      FAILED DATA(failed_read)
      REPORTED DATA(reported_read).

    out->write( name = 'Header before commit - RAP buffer' data = orders ).
    out->write( name = 'Items before commit - RAP buffer' data = items ).
    out->write( name = 'Read FAILED' data = failed_read ).
    out->write( name = 'Read REPORTED' data = reported_read ).

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1 OR lines( items ) <> 2
       OR NOT line_exists( items[ ItemNumber = '00010' ] )
       OR NOT line_exists( items[ ItemNumber = '00020' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected one header and two items in the RAP buffer.' ).
      RETURN.
    ENDIF.

    DATA(order_key) = orders[ 1 ]-%tky.
    DATA(item_1_key) = items[ ItemNumber = '00010' ]-%tky.
    DATA(item_2_key) = items[ ItemNumber = '00020' ]-%tky.

    IF order_key-%is_draft <> if_abap_behv=>mk-off
       OR item_1_key-%is_draft <> if_abap_behv=>mk-off
       OR item_2_key-%is_draft <> if_abap_behv=>mk-off.
      ROLLBACK ENTITIES.
      out->write( 'STOP: the active regression requires active root and item identities.' ).
      RETURN.
    ENDIF.

    IF orders[ 1 ]-Status <> 'DRAFT'
       OR orders[ 1 ]-TotalAmount <> 1900
       OR items[ ItemNumber = '00010' ]-Quantity <> 2
       OR items[ ItemNumber = '00010' ]-NetPrice <> 750
       OR items[ ItemNumber = '00010' ]-TotalAmount <> 1500
       OR items[ ItemNumber = '00020' ]-Quantity <> 4
       OR items[ ItemNumber = '00020' ]-NetPrice <> 100
       OR items[ ItemNumber = '00020' ]-TotalAmount <> 400.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected item totals 1500/400 and header total 1900.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: buffered create totals are 1500 + 400 = 1900.' ).

    out->write( 'Database before first commit: expect 0 headers and 0 items.' ).
    IF check_database( order_uuid = order_uuid
                       expected_headers = 0 expected_items = 0 ) = abap_false.
      ROLLBACK ENTITIES.
      RETURN.
    ENDIF.

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 2
                       expected_supplier = 'SUP001'
                       expected_header_total = 1900
                       expected_quantity = 2
                       expected_net_price = 750
                       expected_item_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.

    IF test_supplier_required( existing_uuid = order_uuid ) = abap_false.
      RETURN.
    ENDIF.

    IF test_quantity_validation(
         existing_order_uuid = order_uuid
         existing_item_uuid = item_1_key-PurchaseOrderItemUUID ) = abap_false.
      RETURN.
    ENDIF.

    IF test_net_price_validation(
         existing_order_uuid = order_uuid
         existing_item_uuid = item_1_key-PurchaseOrderItemUUID ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = order_key Supplier = 'SUP002' ) )
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = item_1_key Quantity = 3 ) )
      FAILED DATA(failed_quantity_update)
      REPORTED DATA(reported_quantity_update).

    out->write( name = 'Quantity update FAILED' data = failed_quantity_update ).
    out->write( name = 'Quantity update REPORTED' data = reported_quantity_update ).
    IF failed_quantity_update IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: Quantity update failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(quantity_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(quantity_items)
      FAILED DATA(failed_quantity_read)
      REPORTED DATA(reported_quantity_read).

    out->write( name = 'After Quantity change - RAP buffer' data = quantity_orders ).
    out->write( name = 'Items after Quantity change' data = quantity_items ).
    IF failed_quantity_read IS NOT INITIAL
       OR lines( quantity_orders ) <> 1 OR lines( quantity_items ) <> 2
       OR quantity_orders[ 1 ]-TotalAmount <> 2650
       OR quantity_items[ ItemNumber = '00010' ]-TotalAmount <> 2250
       OR quantity_items[ ItemNumber = '00020' ]-TotalAmount <> 400.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected item totals 2250/400 and header total 2650.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: Quantity change updated item/header totals to 2250/2650.' ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 2
                       expected_supplier = 'SUP002'
                       expected_header_total = 2650
                       expected_quantity = 3
                       expected_net_price = 750
                       expected_item_total = 2250 ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( NetPrice )
        WITH VALUE #( ( %tky = item_1_key NetPrice = 800 ) )
      FAILED DATA(failed_price_update)
      REPORTED DATA(reported_price_update).

    out->write( name = 'Price update FAILED' data = failed_price_update ).
    out->write( name = 'Price update REPORTED' data = reported_price_update ).
    IF failed_price_update IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: NetPrice update failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(price_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(price_items)
      FAILED DATA(failed_price_read)
      REPORTED DATA(reported_price_read).

    out->write( name = 'After NetPrice change - RAP buffer' data = price_orders ).
    out->write( name = 'Items after NetPrice change' data = price_items ).
    IF failed_price_read IS NOT INITIAL
       OR lines( price_orders ) <> 1 OR lines( price_items ) <> 2
       OR price_orders[ 1 ]-TotalAmount <> 2800
       OR price_items[ ItemNumber = '00010' ]-TotalAmount <> 2400
       OR price_items[ ItemNumber = '00020' ]-TotalAmount <> 400.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected item totals 2400/400 and header total 2800.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: NetPrice change updated item/header totals to 2400/2800.' ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 2
                       expected_supplier = 'SUP002'
                       expected_header_total = 2800
                       expected_quantity = 3
                       expected_net_price = 800
                       expected_item_total = 2400 ) = abap_false.
      RETURN.
    ENDIF.

    " A foreign item's UUID must not bypass the root composition boundary.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'OTHER_ROOT'
                        Supplier = 'SUP001' CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'OTHER_ROOT'
          %target = VALUE #( ( %cid = 'OTHER_ITEM' ItemNumber = '00010'
            Quantity = 1 UnitOfMeasure = 'EA' NetPrice = 100
            Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_other)
      FAILED DATA(failed_other)
      REPORTED DATA(reported_other).
    out->write( name = 'Ownership fixture FAILED' data = failed_other ).
    out->write( name = 'Ownership fixture REPORTED' data = reported_other ).
    IF failed_other IS NOT INITIAL
       OR NOT line_exists( mapped_other-purchaseorder[ %cid = 'OTHER_ROOT' ] )
       OR NOT line_exists( mapped_other-purchaseorderitem[ %cid = 'OTHER_ITEM' ] ).
      ROLLBACK ENTITIES.
      out->write( 'STOP: ownership fixture creation failed.' ).
      RETURN.
    ENDIF.
    DATA(other_root_key) = mapped_other-purchaseorder[
      %cid = 'OTHER_ROOT' ]-%tky.
    DATA(other_item_key) = mapped_other-purchaseorderitem[
      %cid = 'OTHER_ITEM' ]-%tky.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) ( %tky = other_root_key ) )
        RESULT DATA(ownership_roots_before)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) ( %tky = other_root_key ) )
        RESULT DATA(ownership_items_before)
      FAILED DATA(failed_ownership_before).
    IF failed_ownership_before IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: ownership baseline could not be read.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = order_key
          %param-PurchaseOrderItemUUID = other_item_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_foreign_remove)
      REPORTED DATA(reported_foreign_remove).

    " Inspect the buffer before rollback can hide any unintended changes.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) ( %tky = other_root_key ) )
        RESULT DATA(ownership_roots)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) ( %tky = other_root_key ) )
        RESULT DATA(ownership_items)
      FAILED DATA(failed_ownership_read).
    out->write( name = 'Foreign removeItem FAILED - expect root rejection'
                data = failed_foreign_remove ).
    out->write( name = 'Foreign removeItem REPORTED'
                data = reported_foreign_remove ).

    DATA(ownership_failed_key) = xsdbool(
      line_exists( failed_foreign_remove-purchaseorder[
        %tky = order_key %op-%action-removeItem = if_abap_behv=>mk-on ] ) ).
    DATA(expected_ownership_text) =
      CONV string( 'Item does not belong to this Purchase Order.' ).
    DATA(ownership_message) = abap_false.
    LOOP AT reported_foreign_remove-purchaseorder INTO DATA(foreign_message).
      IF foreign_message-%msg IS BOUND.
        DATA(actual_ownership_text) = foreign_message-%msg->if_message~get_text( ).
        IF foreign_message-%tky = order_key
           AND foreign_message-%op-%action-removeItem = if_abap_behv=>mk-on
           AND actual_ownership_text = expected_ownership_text.
          ownership_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    SORT ownership_roots_before BY %tky.
    SORT ownership_roots BY %tky.
    SORT ownership_items_before BY %tky.
    SORT ownership_items BY %tky.
    DATA(ownership_read_ok) = xsdbool( failed_ownership_read IS INITIAL ).
    DATA(ownership_counts_ok) = xsdbool(
      lines( ownership_roots_before ) = 2 AND lines( ownership_items_before ) = 3
      AND lines( ownership_roots ) = 2 AND lines( ownership_items ) = 3 ).
    DATA(ownership_main_total_ok) = xsdbool( line_exists(
      ownership_roots[ %tky = order_key TotalAmount = 2800 ] ) ).
    DATA(ownership_other_total_ok) = xsdbool( line_exists(
      ownership_roots[ %tky = other_root_key TotalAmount = 100 ] ) ).
    DATA(ownership_main_items_ok) = xsdbool(
      line_exists( ownership_items[ %tky = item_1_key
        PurchaseOrderUUID = order_uuid ItemNumber = '00010' TotalAmount = 2400 ] )
      AND line_exists( ownership_items[ %tky = item_2_key
        PurchaseOrderUUID = order_uuid ItemNumber = '00020' TotalAmount = 400 ] ) ).
    DATA(ownership_other_item_ok) = xsdbool( line_exists(
      ownership_items[ %tky = other_item_key
        PurchaseOrderUUID = other_root_key-PurchaseOrderUUID TotalAmount = 100 ] ) ).
    DATA(ownership_roots_same) = xsdbool( ownership_roots = ownership_roots_before ).
    DATA(ownership_items_same) = xsdbool( ownership_items = ownership_items_before ).

    IF ownership_failed_key = abap_false OR ownership_message = abap_false
       OR ownership_read_ok = abap_false OR ownership_counts_ok = abap_false
       OR ownership_main_total_ok = abap_false OR ownership_other_total_ok = abap_false
       OR ownership_main_items_ok = abap_false OR ownership_other_item_ok = abap_false
       OR ownership_roots_same = abap_false OR ownership_items_same = abap_false.
      ROLLBACK ENTITIES.
      out->write( 'STOP: ownership rejection or unchanged-buffer assertion failed.' ).
      RETURN.
    ENDIF.
    ROLLBACK ENTITIES.
    IF check_database( order_uuid = other_root_key-PurchaseOrderUUID
                       expected_headers = 0 expected_items = 0 ) = abap_false
       OR check_database( order_uuid = order_uuid
                          expected_headers = 1 expected_items = 2
                          expected_supplier = 'SUP002'
                          expected_header_total = 2800
                          expected_quantity = 3 expected_net_price = 800
                          expected_item_total = 2400 ) = abap_false.
      RETURN.
    ENDIF.
    out->write( 'PASS: removeItem rejected a foreign item; both roots and items unchanged.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = order_key
          %param-PurchaseOrderItemUUID = item_2_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_item_2_delete)
      REPORTED DATA(reported_item_2_delete).

    out->write( name = 'First item delete FAILED' data = failed_item_2_delete ).
    out->write( name = 'First item delete REPORTED' data = reported_item_2_delete ).
    IF failed_item_2_delete IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: deleting item 00020 failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(one_item_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(one_item)
      FAILED DATA(failed_one_item_read)
      REPORTED DATA(reported_one_item_read).

    out->write( name = 'Header after item 00020 delete - before commit'
                data = one_item_orders ).
    out->write( name = 'Surviving buffered items - expect only 00010'
                data = one_item ).
    out->write( name = 'After delete read FAILED' data = failed_one_item_read ).
    out->write( name = 'After delete read REPORTED' data = reported_one_item_read ).

    IF failed_one_item_read IS NOT INITIAL
       OR lines( one_item_orders ) <> 1 OR lines( one_item ) <> 1
       OR one_item_orders[ 1 ]-TotalAmount <> 2400
       OR one_item[ 1 ]-ItemNumber <> '00010'
       OR one_item[ 1 ]-TotalAmount <> 2400.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected header total 2400 after deleting item 00020.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: deleting item 00020 reduced the buffered header to 2400.' ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 1
                       expected_supplier = 'SUP002'
                       expected_header_total = 2400
                       expected_quantity = 3
                       expected_net_price = 800
                       expected_item_total = 2400 ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = order_key
          %param-PurchaseOrderItemUUID = item_1_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_last_item_delete)
      REPORTED DATA(reported_last_item_delete).

    out->write( name = 'Last item delete FAILED' data = failed_last_item_delete ).
    out->write( name = 'Last item delete REPORTED' data = reported_last_item_delete ).
    IF failed_last_item_delete IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: deleting the last item failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(empty_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(no_items)
      FAILED DATA(failed_empty_read)
      REPORTED DATA(reported_empty_read).

    out->write( name = 'Header after last item delete - expect total 0'
                data = empty_orders ).
    out->write( name = 'Remaining buffered items - expect empty' data = no_items ).
    out->write( name = 'Last delete read FAILED' data = failed_empty_read ).
    out->write( name = 'Last delete read REPORTED' data = reported_empty_read ).

    IF failed_empty_read IS NOT INITIAL
       OR lines( empty_orders ) <> 1 OR no_items IS NOT INITIAL
       OR empty_orders[ 1 ]-TotalAmount <> 0.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected header total 0 after deleting the last item.' ).
      RETURN.
    ENDIF.
    out->write( 'PASS: deleting the last item set the buffered header total to 0.' ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 0
                       expected_supplier = 'SUP002'
                       expected_header_total = 0 ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_root_delete)
      REPORTED DATA(reported_root_delete).

    out->write( name = 'Root cleanup FAILED' data = failed_root_delete ).
    out->write( name = 'Root cleanup REPORTED' data = reported_root_delete ).
    IF failed_root_delete IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: root cleanup failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    IF check_database( order_uuid = order_uuid
                       expected_headers = 0 expected_items = 0 ) = abap_false.
      RETURN.
    ENDIF.
    out->write( 'PASS: header totals 1900/2650/2800/2400/0; cleanup complete.' ).
    out->write( 'PASS: Supplier validation rejects blank create/update; valid flow and cleanup pass.' ).
    out->write( 'PASS: Quantity validation rejects zero create/negative update; valid flow and cleanup pass.' ).
    out->write( 'PASS: NetPrice rejects negative create/update; zero create/update, regression and cleanup pass.' ).
    out->write( 'PASS: removeItem active totals 2400/0; ownership, Phase 2.5 regression and cleanup pass.' ).

    IF test_submit_active( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_submit_requires_item( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: submit active DRAFT to SUBMITTED persisted; re-submit and empty-order rejections pass.' ).
  ENDMETHOD.

  METHOD test_supplier_required.
    DATA(test_uuid) = existing_uuid.
    DATA modify_failed TYPE RESPONSE FOR FAILED ZJP_I_PurchaseOrder.
    DATA modify_reported TYPE RESPONSE FOR REPORTED ZJP_I_PurchaseOrder.

    IF existing_uuid IS INITIAL.
      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'NO_SUPPLIER'
                        Supplier = '' CompanyCode = '1000' Currency = 'EUR' ) )
        MAPPED DATA(mapped_invalid)
        FAILED modify_failed
        REPORTED modify_reported.
      IF line_exists( mapped_invalid-purchaseorder[ %cid = 'NO_SUPPLIER' ] ).
        test_uuid = mapped_invalid-purchaseorder[ %cid = 'NO_SUPPLIER' ]-PurchaseOrderUUID.
      ENDIF.
    ELSE.
      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( PurchaseOrderUUID = existing_uuid Supplier = '' ) )
        FAILED modify_failed
        REPORTED modify_reported.
    ENDIF.

    console->write( name = 'Supplier negative test UUID' data = test_uuid ).
    console->write( name = 'Negative MODIFY FAILED - expect empty' data = modify_failed ).
    console->write( name = 'Negative MODIFY REPORTED' data = modify_reported ).
    IF modify_failed IS NOT INITIAL OR test_uuid IS INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: negative test did not reach the save validation.' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.
    console->write( name = 'Negative COMMIT sy-subrc - expect nonzero' data = save_subrc ).
    console->write( name = 'Negative Save FAILED' data = failed_save ).
    console->write( name = 'Negative Save REPORTED' data = reported_save ).

    DATA(found_message) = abap_false.
    LOOP AT reported_save-purchaseorder INTO DATA(message).
      IF message-%msg IS BOUND.
        console->write( message-%msg->if_message~get_text( ) ).
        IF message-PurchaseOrderUUID = test_uuid
           AND message-%element-Supplier = if_abap_behv=>mk-on
           AND message-%msg->if_message~get_text( ) = 'Supplier is required.'.
          found_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    success = xsdbool( save_subrc <> 0 AND found_message = abap_true
      AND line_exists( failed_save-purchaseorder[ PurchaseOrderUUID = test_uuid ] ) ).
    ROLLBACK ENTITIES.

    SELECT purchase_order_uuid, supplier FROM zjp_po_h
      WHERE purchase_order_uuid = @test_uuid
      INTO TABLE @DATA(persisted_orders).
    IF existing_uuid IS INITIAL.
      success = xsdbool( success = abap_true AND persisted_orders IS INITIAL ).
    ELSE.
      IF lines( persisted_orders ) <> 1.
        success = abap_false.
      ELSEIF persisted_orders[ 1 ]-supplier <> 'SUP001'.
        success = abap_false.
      ENDIF.
    ENDIF.

    IF success = abap_true.
      console->write( 'PASS: blank Supplier save rejected; database unchanged.' ).
    ELSE.
      console->write( 'STOP: Supplier validation assertion failed; retain the test UUID.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_quantity_validation.
    DATA(test_order_uuid) = existing_order_uuid.
    DATA(test_item_uuid) = existing_item_uuid.
    DATA modify_failed TYPE RESPONSE FOR FAILED ZJP_I_PurchaseOrder.
    DATA modify_reported TYPE RESPONSE FOR REPORTED ZJP_I_PurchaseOrder.

    " Read-only snapshots prove the rejected update changes no persisted field.
    SELECT * FROM zjp_po_h
      WHERE purchase_order_uuid = @existing_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(headers_before).
    SELECT * FROM zjp_po_i
      WHERE purchase_order_uuid = @existing_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(items_before).

    IF existing_order_uuid IS INITIAL.
      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrder
          CREATE FIELDS ( Supplier CompanyCode Currency )
          WITH VALUE #( ( %cid = 'BAD_QUANTITY_PO'
                          Supplier = 'SUP001'
                          CompanyCode = '1000'
                          Currency = 'EUR' ) )
          CREATE BY \_Items
          FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
          WITH VALUE #( (
            %cid_ref = 'BAD_QUANTITY_PO'
            %target = VALUE #( (
              %cid = 'ZERO_QUANTITY_ITEM'
              ItemNumber = '00010'
              Material = 'MAT001'
              Quantity = 0
              UnitOfMeasure = 'EA'
              NetPrice = 750
              Currency = 'EUR' ) ) ) )
        MAPPED DATA(mapped_invalid)
        FAILED modify_failed
        REPORTED modify_reported.

      IF line_exists( mapped_invalid-purchaseorder[ %cid = 'BAD_QUANTITY_PO' ] ).
        test_order_uuid =
          mapped_invalid-purchaseorder[ %cid = 'BAD_QUANTITY_PO' ]-PurchaseOrderUUID.
      ENDIF.
      IF line_exists(
           mapped_invalid-purchaseorderitem[ %cid = 'ZERO_QUANTITY_ITEM' ] ).
        test_item_uuid = mapped_invalid-purchaseorderitem[
          %cid = 'ZERO_QUANTITY_ITEM' ]-PurchaseOrderItemUUID.
      ENDIF.
    ELSE.
      IF existing_item_uuid IS INITIAL.
        console->write( 'STOP: Quantity update test requires an item UUID.' ).
        RETURN.
      ENDIF.

      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( (
          PurchaseOrderItemUUID = existing_item_uuid Quantity = -1 ) )
        FAILED modify_failed
        REPORTED modify_reported.
    ENDIF.

    console->write( name = 'Quantity negative test order UUID'
                    data = test_order_uuid ).
    console->write( name = 'Quantity negative test item UUID'
                    data = test_item_uuid ).
    console->write( name = 'Quantity negative MODIFY FAILED - expect empty'
                    data = modify_failed ).
    console->write( name = 'Quantity negative MODIFY REPORTED'
                    data = modify_reported ).
    IF modify_failed IS NOT INITIAL
       OR test_order_uuid IS INITIAL OR test_item_uuid IS INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: Quantity negative test did not reach save validation.' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.
    console->write( name = 'Quantity negative COMMIT sy-subrc - expect nonzero'
                    data = save_subrc ).
    console->write( name = 'Quantity negative Save FAILED' data = failed_save ).
    console->write( name = 'Quantity negative Save REPORTED' data = reported_save ).

    DATA(found_message) = abap_false.
    LOOP AT reported_save-purchaseorderitem INTO DATA(message).
      IF message-%msg IS BOUND.
        console->write( message-%msg->if_message~get_text( ) ).
        IF message-PurchaseOrderItemUUID = test_item_uuid
           AND message-%element-Quantity = if_abap_behv=>mk-on
           AND message-%msg->if_message~get_text( ) =
             'Quantity must be greater than 0.'.
          found_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    success = xsdbool(
      save_subrc <> 0
      AND found_message = abap_true
      AND line_exists( failed_save-purchaseorderitem[
        PurchaseOrderItemUUID = test_item_uuid ] ) ).
    ROLLBACK ENTITIES.

    SELECT purchase_order_uuid, total_amount FROM zjp_po_h
      WHERE purchase_order_uuid = @test_order_uuid
      INTO TABLE @DATA(persisted_orders).
    SELECT purchase_order_item_uuid, purchase_order_uuid, quantity, total_amount
      FROM zjp_po_i
      WHERE purchase_order_item_uuid = @test_item_uuid
      INTO TABLE @DATA(persisted_items).

    SELECT * FROM zjp_po_h
      WHERE purchase_order_uuid = @test_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(headers_after).
    SELECT * FROM zjp_po_i
      WHERE purchase_order_uuid = @test_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(items_after).
    console->write( name = 'Quantity test persisted headers after rollback'
                    data = headers_after ).
    console->write( name = 'Quantity test persisted items after rollback'
                    data = items_after ).

    IF existing_order_uuid IS INITIAL.
      success = xsdbool( success = abap_true
        AND persisted_orders IS INITIAL AND persisted_items IS INITIAL
        AND headers_after IS INITIAL AND items_after IS INITIAL ).
    ELSE.
      success = xsdbool( success = abap_true
        AND headers_after = headers_before AND items_after = items_before
        AND lines( persisted_orders ) = 1
        AND persisted_orders[ 1 ]-total_amount = 1900
        AND lines( persisted_items ) = 1
        AND persisted_items[ 1 ]-purchase_order_uuid = existing_order_uuid
        AND persisted_items[ 1 ]-quantity = 2
        AND persisted_items[ 1 ]-total_amount = 1500 ).
    ENDIF.

    IF success = abap_true.
      console->write( 'PASS: invalid Quantity save rejected; database unchanged.' ).
    ELSE.
      console->write( 'STOP: Quantity validation assertion failed; retain the test UUIDs.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_net_price_validation.
    DATA(test_order_uuid) = existing_order_uuid.
    DATA(test_item_uuid) = existing_item_uuid.
    DATA modify_failed TYPE RESPONSE FOR FAILED ZJP_I_PurchaseOrder.
    DATA modify_reported TYPE RESPONSE FOR REPORTED ZJP_I_PurchaseOrder.

    " Read-only snapshots prove the rejected update changes no persisted field.
    SELECT * FROM zjp_po_h
      WHERE purchase_order_uuid = @existing_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(headers_before).
    SELECT * FROM zjp_po_i
      WHERE purchase_order_uuid = @existing_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(items_before).

    IF existing_order_uuid IS INITIAL.
      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrder
          CREATE FIELDS ( Supplier CompanyCode Currency )
          WITH VALUE #( ( %cid = 'BAD_PRICE_PO'
                          Supplier = 'SUP001'
                          CompanyCode = '1000'
                          Currency = 'EUR' ) )
          CREATE BY \_Items
          FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
          WITH VALUE #( (
            %cid_ref = 'BAD_PRICE_PO'
            %target = VALUE #( (
              %cid = 'NEGATIVE_PRICE_ITEM'
              ItemNumber = '00010'
              Material = 'MAT001'
              Quantity = 2
              UnitOfMeasure = 'EA'
              NetPrice = -1
              Currency = 'EUR' ) ) ) )
        MAPPED DATA(mapped_invalid)
        FAILED modify_failed
        REPORTED modify_reported.

      IF line_exists( mapped_invalid-purchaseorder[ %cid = 'BAD_PRICE_PO' ] ).
        test_order_uuid =
          mapped_invalid-purchaseorder[ %cid = 'BAD_PRICE_PO' ]-PurchaseOrderUUID.
      ENDIF.
      IF line_exists(
           mapped_invalid-purchaseorderitem[ %cid = 'NEGATIVE_PRICE_ITEM' ] ).
        test_item_uuid = mapped_invalid-purchaseorderitem[
          %cid = 'NEGATIVE_PRICE_ITEM' ]-PurchaseOrderItemUUID.
      ENDIF.
    ELSE.
      IF existing_item_uuid IS INITIAL.
        console->write( 'STOP: NetPrice update test requires an item UUID.' ).
        RETURN.
      ENDIF.

      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrderItem
        UPDATE FIELDS ( NetPrice )
        WITH VALUE #( (
          PurchaseOrderItemUUID = existing_item_uuid NetPrice = -1 ) )
        FAILED modify_failed
        REPORTED modify_reported.
    ENDIF.

    console->write( name = 'NetPrice negative test order UUID'
                    data = test_order_uuid ).
    console->write( name = 'NetPrice negative test item UUID'
                    data = test_item_uuid ).
    console->write( name = 'NetPrice negative MODIFY FAILED - expect empty'
                    data = modify_failed ).
    console->write( name = 'NetPrice negative MODIFY REPORTED'
                    data = modify_reported ).
    IF modify_failed IS NOT INITIAL
       OR test_order_uuid IS INITIAL OR test_item_uuid IS INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: NetPrice negative test did not reach save validation.' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.
    console->write( name = 'NetPrice negative COMMIT sy-subrc - expect nonzero'
                    data = save_subrc ).
    console->write( name = 'NetPrice negative Save FAILED' data = failed_save ).
    console->write( name = 'NetPrice negative Save REPORTED' data = reported_save ).

    DATA(found_message) = abap_false.
    LOOP AT reported_save-purchaseorderitem INTO DATA(message).
      IF message-%msg IS BOUND.
        console->write( message-%msg->if_message~get_text( ) ).
        IF message-PurchaseOrderItemUUID = test_item_uuid
           AND message-%element-NetPrice = if_abap_behv=>mk-on
           AND message-%msg->if_message~get_text( ) =
             'Net Price cannot be negative.'.
          found_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    success = xsdbool(
      save_subrc <> 0
      AND found_message = abap_true
      AND line_exists( failed_save-purchaseorderitem[
        PurchaseOrderItemUUID = test_item_uuid ] ) ).
    ROLLBACK ENTITIES.

    SELECT purchase_order_uuid, total_amount FROM zjp_po_h
      WHERE purchase_order_uuid = @test_order_uuid
      INTO TABLE @DATA(persisted_orders).
    SELECT purchase_order_item_uuid, purchase_order_uuid, quantity, net_price, total_amount
      FROM zjp_po_i
      WHERE purchase_order_item_uuid = @test_item_uuid
      INTO TABLE @DATA(persisted_items).

    SELECT * FROM zjp_po_h
      WHERE purchase_order_uuid = @test_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(headers_after).
    SELECT * FROM zjp_po_i
      WHERE purchase_order_uuid = @test_order_uuid
      ORDER BY PRIMARY KEY
      INTO TABLE @DATA(items_after).
    console->write( name = 'NetPrice test persisted headers after rollback'
                    data = headers_after ).
    console->write( name = 'NetPrice test persisted items after rollback'
                    data = items_after ).

    IF existing_order_uuid IS INITIAL.
      success = xsdbool( success = abap_true
        AND persisted_orders IS INITIAL AND persisted_items IS INITIAL
        AND headers_after IS INITIAL AND items_after IS INITIAL ).
    ELSE.
      success = xsdbool( success = abap_true
        AND headers_after = headers_before AND items_after = items_before
        AND lines( persisted_orders ) = 1
        AND persisted_orders[ 1 ]-total_amount = 1900
        AND lines( persisted_items ) = 1
        AND persisted_items[ 1 ]-purchase_order_uuid = existing_order_uuid
        AND persisted_items[ 1 ]-quantity = 2
        AND persisted_items[ 1 ]-net_price = 750
        AND persisted_items[ 1 ]-total_amount = 1500 ).
    ENDIF.

    IF success = abap_true.
      console->write( 'PASS: negative NetPrice save rejected; database unchanged.' ).
    ELSE.
      console->write( 'STOP: NetPrice validation assertion failed; retain the test UUIDs.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_zero_net_price.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'ZERO_PRICE_PO'
                        Supplier = 'SUP001' CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( (
          %cid_ref = 'ZERO_PRICE_PO'
          %target = VALUE #( (
            %cid = 'ZERO_PRICE_ITEM' ItemNumber = '00010'
            Material = 'MAT001' Quantity = 2 UnitOfMeasure = 'EA'
            NetPrice = 0 Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_create)
      FAILED DATA(failed_create)
      REPORTED DATA(reported_create).

    console->write( name = 'Zero-price create MAPPED' data = mapped_create ).
    console->write( name = 'Zero-price create FAILED' data = failed_create ).
    console->write( name = 'Zero-price create REPORTED' data = reported_create ).
    IF failed_create IS NOT INITIAL
       OR NOT line_exists( mapped_create-purchaseorder[ %cid = 'ZERO_PRICE_PO' ] )
       OR NOT line_exists( mapped_create-purchaseorderitem[ %cid = 'ZERO_PRICE_ITEM' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: zero-price create failed; retain the mapped UUIDs.' ).
      RETURN.
    ENDIF.

    DATA(order_uuid) = mapped_create-purchaseorder[
      %cid = 'ZERO_PRICE_PO' ]-PurchaseOrderUUID.
    DATA(item_uuid) = mapped_create-purchaseorderitem[
      %cid = 'ZERO_PRICE_ITEM' ]-PurchaseOrderItemUUID.
    IF check_price_buffer( order_uuid = order_uuid item_uuid = item_uuid
                           expected_price = 0 ) = abap_false.
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 1
                       expected_supplier = 'SUP001'
                       expected_quantity = 2 expected_net_price = 0
                       expected_header_total = 0
                       expected_item_total = 0 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: zero NetPrice create saved with item/header totals 0.' ).

    " Establish a positive price before proving a real change back to zero.
    DATA prices TYPE STANDARD TABLE OF zjp_po_i-net_price WITH EMPTY KEY.
    prices = VALUE #( ( CONV zjp_po_i-net_price( 750 ) )
                      ( CONV zjp_po_i-net_price( 0 ) ) ).
    LOOP AT prices INTO DATA(price).
      MODIFY ENTITIES OF ZJP_I_PurchaseOrder
        ENTITY PurchaseOrderItem
        UPDATE FIELDS ( NetPrice )
        WITH VALUE #( ( PurchaseOrderItemUUID = item_uuid NetPrice = price ) )
        FAILED DATA(failed_update)
        REPORTED DATA(reported_update).
      console->write( name = 'Boundary test requested NetPrice' data = price ).
      console->write( name = 'Boundary test update FAILED' data = failed_update ).
      console->write( name = 'Boundary test update REPORTED' data = reported_update ).
      IF failed_update IS NOT INITIAL.
        ROLLBACK ENTITIES.
        console->write( 'STOP: boundary price update failed; retain the mapped UUIDs.' ).
        RETURN.
      ENDIF.
      IF check_price_buffer( order_uuid = order_uuid item_uuid = item_uuid
                             expected_price = price ) = abap_false.
        RETURN.
      ENDIF.
      IF save_changes( ) = abap_false.
        RETURN.
      ENDIF.
      IF check_database( order_uuid = order_uuid
                         expected_headers = 1 expected_items = 1
                         expected_supplier = 'SUP001'
                         expected_quantity = 2 expected_net_price = price
                         expected_header_total = 2 * price
                         expected_item_total = 2 * price ) = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
    console->write( 'PASS: NetPrice 750 to 0 update saved with item/header totals 0.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
      DELETE FROM VALUE #( ( PurchaseOrderUUID = order_uuid ) )
      FAILED DATA(failed_delete)
      REPORTED DATA(reported_delete).
    console->write( name = 'Zero-price cleanup FAILED' data = failed_delete ).
    console->write( name = 'Zero-price cleanup REPORTED' data = reported_delete ).
    IF failed_delete IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: zero-price cleanup failed; retain the mapped UUIDs.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    success = check_database( order_uuid = order_uuid
                              expected_headers = 0 expected_items = 0 ).
    IF success = abap_true.
      console->write( 'PASS: zero-price fixture cleanup complete.' ).
    ENDIF.
  ENDMETHOD.

  METHOD check_price_buffer.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(items)
      FAILED DATA(failed_read)
      REPORTED DATA(reported_read).
    console->write( name = 'Boundary price header before commit' data = orders ).
    console->write( name = 'Boundary price item before commit' data = items ).
    console->write( name = 'Boundary price read FAILED' data = failed_read ).
    console->write( name = 'Boundary price read REPORTED' data = reported_read ).
    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1 OR lines( items ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: expected one header/item for the boundary price test.' ).
      RETURN.
    ENDIF.
    success = xsdbool(
      orders[ 1 ]-Status = 'DRAFT'
      AND orders[ 1 ]-TotalAmount = 2 * expected_price
      AND items[ 1 ]-PurchaseOrderItemUUID = item_uuid
      AND items[ 1 ]-Quantity = 2
      AND items[ 1 ]-NetPrice = expected_price
      AND items[ 1 ]-TotalAmount = 2 * expected_price ).
    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: incorrect NetPrice or totals in the boundary test buffer.' ).
    ENDIF.
  ENDMETHOD.

  METHOD save_changes.
    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.

    console->write( name = 'COMMIT sy-subrc' data = save_subrc ).
    console->write( name = 'Save FAILED' data = failed_save ).
    console->write( name = 'Save REPORTED' data = reported_save ).

    success = xsdbool( save_subrc = 0 AND failed_save IS INITIAL ).
    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: save failed; earlier successful commits remain.' ).
    ENDIF.
  ENDMETHOD.

  METHOD check_database.
    SELECT purchase_order_uuid, supplier, total_amount, status
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(headers_db).

    SELECT purchase_order_item_uuid, purchase_order_uuid, item_number,
           quantity, net_price, total_amount
      FROM zjp_po_i
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(items_db).

    console->write( name = 'ZJP_PO_H - only this test UUID' data = headers_db ).
    console->write( name = 'ZJP_PO_I - only this test UUID' data = items_db ).

    success = xsdbool( lines( headers_db ) = expected_headers
                      AND lines( items_db ) = expected_items ).

    IF success = abap_true AND expected_headers = 1.
      DATA(persisted_item_sum) = CONV zjp_po_h-total_amount( 0 ).
      LOOP AT items_db INTO DATA(item_db).
        persisted_item_sum += item_db-total_amount.
      ENDLOOP.

      success = xsdbool( headers_db[ 1 ]-supplier = expected_supplier
                        AND headers_db[ 1 ]-status = 'DRAFT'
                        AND headers_db[ 1 ]-total_amount = expected_header_total
                        AND persisted_item_sum = expected_header_total ).
    ENDIF.

    IF success = abap_true AND expected_items > 0.
      IF NOT line_exists( items_db[ item_number = '00010' ] ).
        success = abap_false.
      ELSE.
        success = xsdbool(
          items_db[ item_number = '00010' ]-quantity = expected_quantity
          AND items_db[ item_number = '00010' ]-net_price = expected_net_price
          AND items_db[ item_number = '00010' ]-total_amount = expected_item_total ).
      ENDIF.
    ENDIF.

    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: database verification failed; retain the test UUID.' ).
    ELSE.
      console->write( 'PASS: database checkpoint values are correct.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_submit_active.
    " Self-contained fixture; the Phase 2.5/2.6 flow above stays untouched.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode PurchasingOrganization
                        PurchasingGroup Currency )
        WITH VALUE #( (
          %cid = 'SUBMIT_ROOT'
          Supplier = 'SUP003'
          CompanyCode = '1000'
          PurchasingOrganization = '1000'
          PurchasingGroup = '001'
          Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material MaterialDescription Quantity
                 UnitOfMeasure NetPrice Currency )
        WITH VALUE #( (
          %cid_ref = 'SUBMIT_ROOT'
          %target = VALUE #( (
            %cid = 'SUBMIT_ITEM'
            ItemNumber = '00010'
            Material = 'MAT001'
            MaterialDescription = 'Submit study item'
            Quantity = 2
            UnitOfMeasure = 'EA'
            NetPrice = '750.00'
            Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_submit)
      FAILED DATA(failed_submit_create)
      REPORTED DATA(reported_submit_create).

    console->write( name = 'Submit fixture MAPPED' data = mapped_submit ).
    console->write( name = 'Submit fixture FAILED' data = failed_submit_create ).
    console->write( name = 'Submit fixture REPORTED' data = reported_submit_create ).
    IF failed_submit_create IS NOT INITIAL
       OR NOT line_exists( mapped_submit-purchaseorder[ %cid = 'SUBMIT_ROOT' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(submit_uuid) =
      mapped_submit-purchaseorder[ %cid = 'SUBMIT_ROOT' ]-PurchaseOrderUUID.
    console->write( name = 'Submit test order UUID - retain for diagnosis'
                    data = submit_uuid ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_submit_database( order_uuid = submit_uuid
                              expected_headers = 1 expected_items = 1
                              expected_status = 'DRAFT'
                              expected_header_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = submit_uuid ) )
        RESULT DATA(draft_status_orders)
      FAILED DATA(failed_draft_status_read).
    IF failed_draft_status_read IS NOT INITIAL
       OR lines( draft_status_orders ) <> 1
       OR draft_status_orders[ 1 ]-Status <> 'DRAFT'
       OR draft_status_orders[ 1 ]-%is_draft <> if_abap_behv=>mk-off.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit fixture must be an active order in Status DRAFT.' ).
      RETURN.
    ENDIF.
    DATA(submit_key) = draft_status_orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = submit_key ) )
      FAILED DATA(failed_submit)
      REPORTED DATA(reported_submit).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = submit_key ) )
        RESULT DATA(submitted_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = submit_key ) )
        RESULT DATA(submitted_items)
      FAILED DATA(failed_submitted_read).

    console->write( name = 'Submit FAILED - expect empty' data = failed_submit ).
    console->write( name = 'Submit REPORTED' data = reported_submit ).
    console->write( name = 'Header after submit - before commit'
                    data = submitted_orders ).
    console->write( name = 'Items after submit - expect unchanged'
                    data = submitted_items ).

    IF failed_submit IS NOT INITIAL OR failed_submitted_read IS NOT INITIAL
       OR lines( submitted_orders ) <> 1 OR lines( submitted_items ) <> 1
       OR submitted_orders[ 1 ]-Status <> 'SUBMITTED'
       OR submitted_orders[ 1 ]-TotalAmount <> 1500
       OR submitted_items[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit must set Status SUBMITTED and leave totals unchanged.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: submit set the buffered Status to SUBMITTED with total 1500.' ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_submit_database( order_uuid = submit_uuid
                              expected_headers = 1 expected_items = 1
                              expected_status = 'SUBMITTED'
                              expected_header_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: SUBMITTED status is persisted in ZJP_PO_H.' ).

    " A second submit must be rejected because the order is no longer DRAFT.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = submit_key ) )
      FAILED DATA(failed_resubmit)
      REPORTED DATA(reported_resubmit).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = submit_key ) )
        RESULT DATA(resubmit_orders)
      FAILED DATA(failed_resubmit_read).

    console->write( name = 'Re-submit FAILED - expect rejection'
                    data = failed_resubmit ).
    console->write( name = 'Re-submit REPORTED' data = reported_resubmit ).
    console->write( name = 'Header after re-submit attempt' data = resubmit_orders ).

    DATA(resubmit_failed_key) = xsdbool( line_exists(
      failed_resubmit-purchaseorder[ %tky = submit_key
        %op-%action-submit = if_abap_behv=>mk-on ] ) ).
    DATA(expected_resubmit_text) =
      CONV string( 'Only orders in status DRAFT can be submitted.' ).
    DATA(resubmit_message) = abap_false.
    LOOP AT reported_resubmit-purchaseorder INTO DATA(resubmit_line).
      IF resubmit_line-%msg IS BOUND.
        DATA(actual_resubmit_text) = resubmit_line-%msg->if_message~get_text( ).
        IF resubmit_line-%tky = submit_key
           AND resubmit_line-%op-%action-submit = if_abap_behv=>mk-on
           AND actual_resubmit_text = expected_resubmit_text.
          resubmit_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF resubmit_failed_key = abap_false OR resubmit_message = abap_false
       OR failed_resubmit_read IS NOT INITIAL
       OR lines( resubmit_orders ) <> 1
       OR resubmit_orders[ 1 ]-Status <> 'SUBMITTED'
       OR resubmit_orders[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      console->write( 'STOP: re-submit rejection or unchanged-buffer assertion failed.' ).
      RETURN.
    ENDIF.
    ROLLBACK ENTITIES.
    IF check_submit_database( order_uuid = submit_uuid
                              expected_headers = 1 expected_items = 1
                              expected_status = 'SUBMITTED'
                              expected_header_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: re-submit rejected; persisted SUBMITTED order unchanged.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( PurchaseOrderUUID = submit_uuid ) )
      FAILED DATA(failed_submit_cleanup)
      REPORTED DATA(reported_submit_cleanup).
    console->write( name = 'Submit cleanup FAILED' data = failed_submit_cleanup ).
    console->write( name = 'Submit cleanup REPORTED' data = reported_submit_cleanup ).
    IF failed_submit_cleanup IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit fixture cleanup failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    success = check_submit_database( order_uuid = submit_uuid
                                     expected_headers = 0 expected_items = 0 ).
    IF success = abap_true.
      console->write( 'PASS: submit fixture cleanup complete.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_submit_requires_item.
    " An order without items must not reach SUBMITTED.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( (
          %cid = 'EMPTY_ROOT'
          Supplier = 'SUP004'
          CompanyCode = '1000'
          Currency = 'EUR' ) )
      MAPPED DATA(mapped_empty)
      FAILED DATA(failed_empty_create)
      REPORTED DATA(reported_empty_create).

    console->write( name = 'Empty-order fixture MAPPED' data = mapped_empty ).
    console->write( name = 'Empty-order fixture FAILED' data = failed_empty_create ).
    console->write( name = 'Empty-order fixture REPORTED'
                    data = reported_empty_create ).
    IF failed_empty_create IS NOT INITIAL
       OR NOT line_exists( mapped_empty-purchaseorder[ %cid = 'EMPTY_ROOT' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: empty-order fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(empty_uuid) =
      mapped_empty-purchaseorder[ %cid = 'EMPTY_ROOT' ]-PurchaseOrderUUID.
    console->write( name = 'Empty-order UUID - retain for diagnosis'
                    data = empty_uuid ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_submit_database( order_uuid = empty_uuid
                              expected_headers = 1 expected_items = 0
                              expected_status = 'DRAFT'
                              expected_header_total = 0 ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = empty_uuid ) )
        RESULT DATA(empty_orders)
      FAILED DATA(failed_empty_read).
    IF failed_empty_read IS NOT INITIAL OR lines( empty_orders ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: the empty-order fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(empty_key) = empty_orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = empty_key ) )
      FAILED DATA(failed_empty_submit)
      REPORTED DATA(reported_empty_submit).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = empty_key ) )
        RESULT DATA(empty_orders_after)
      FAILED DATA(failed_empty_after_read).

    console->write( name = 'Empty-order submit FAILED - expect rejection'
                    data = failed_empty_submit ).
    console->write( name = 'Empty-order submit REPORTED'
                    data = reported_empty_submit ).
    console->write( name = 'Header after empty-order submit attempt'
                    data = empty_orders_after ).

    DATA(empty_failed_key) = xsdbool( line_exists(
      failed_empty_submit-purchaseorder[ %tky = empty_key
        %op-%action-submit = if_abap_behv=>mk-on ] ) ).
    DATA(expected_empty_text) = CONV string(
      'Submit requires at least one item.' ).
    DATA(empty_message) = abap_false.
    LOOP AT reported_empty_submit-purchaseorder INTO DATA(empty_line).
      IF empty_line-%msg IS BOUND.
        DATA(actual_empty_text) = empty_line-%msg->if_message~get_text( ).
        IF empty_line-%tky = empty_key
           AND empty_line-%op-%action-submit = if_abap_behv=>mk-on
           AND actual_empty_text = expected_empty_text.
          empty_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF empty_failed_key = abap_false OR empty_message = abap_false
       OR failed_empty_after_read IS NOT INITIAL
       OR lines( empty_orders_after ) <> 1
       OR empty_orders_after[ 1 ]-Status <> 'DRAFT'.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit must be rejected for an order without items.' ).
      RETURN.
    ENDIF.
    ROLLBACK ENTITIES.
    IF check_submit_database( order_uuid = empty_uuid
                              expected_headers = 1 expected_items = 0
                              expected_status = 'DRAFT'
                              expected_header_total = 0 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: submit rejected without items; persisted Status stayed DRAFT.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( PurchaseOrderUUID = empty_uuid ) )
      FAILED DATA(failed_empty_cleanup)
      REPORTED DATA(reported_empty_cleanup).
    console->write( name = 'Empty-order cleanup FAILED' data = failed_empty_cleanup ).
    console->write( name = 'Empty-order cleanup REPORTED'
                    data = reported_empty_cleanup ).
    IF failed_empty_cleanup IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: empty-order cleanup failed; retain the printed UUID.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    success = check_submit_database( order_uuid = empty_uuid
                                     expected_headers = 0 expected_items = 0 ).
    IF success = abap_true.
      console->write( 'PASS: empty-order fixture cleanup complete.' ).
    ENDIF.
  ENDMETHOD.

  METHOD check_submit_database.
    " Read-only verification; Phase 2.7A must not allocate PurchaseOrderNumber.
    SELECT purchase_order_uuid, supplier, total_amount, status,
           purchase_order_number
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(headers_db).

    SELECT purchase_order_item_uuid, purchase_order_uuid, item_number,
           total_amount
      FROM zjp_po_i
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(items_db).

    console->write( name = 'ZJP_PO_H - submit test UUID' data = headers_db ).
    console->write( name = 'ZJP_PO_I - submit test UUID' data = items_db ).

    success = xsdbool( lines( headers_db ) = expected_headers
                      AND lines( items_db ) = expected_items ).

    IF success = abap_true AND expected_headers = 1.
      DATA(persisted_item_sum) = CONV zjp_po_h-total_amount( 0 ).
      LOOP AT items_db INTO DATA(item_db).
        persisted_item_sum += item_db-total_amount.
      ENDLOOP.

      success = xsdbool( headers_db[ 1 ]-status = expected_status
                        AND headers_db[ 1 ]-total_amount = expected_header_total
                        AND persisted_item_sum = expected_header_total
                        AND headers_db[ 1 ]-purchase_order_number IS INITIAL ).
    ENDIF.

    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit database verification failed; retain the test UUID.' ).
    ELSE.
      console->write( 'PASS: submit database checkpoint values are correct.' ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
