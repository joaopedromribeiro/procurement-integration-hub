CLASS zjp_cl_po_eml_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    METHODS test_supplier_required
      IMPORTING existing_uuid TYPE sysuuid_x16 OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS save_changes
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
ENDCLASS.

CLASS zjp_cl_po_eml_test IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    console = out.

    IF test_supplier_required( ) = abap_false.
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

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem BY \_PurchaseOrder
        FIELDS ( PurchaseOrderUUID ) WITH VALUE #( ( %tky = item_2_key ) )
        RESULT DATA(parent_before_delete)
      FAILED DATA(failed_parent_before_delete)
      REPORTED DATA(reported_parent_before_delete).
    out->write( name = 'Parent before item deletion' data = parent_before_delete ).
    out->write( name = 'Parent probe FAILED' data = failed_parent_before_delete ).
    out->write( name = 'Parent probe REPORTED' data = reported_parent_before_delete ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        DELETE FROM VALUE #( ( %tky = item_2_key ) )
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

    SELECT purchase_order_item_uuid, purchase_order_uuid
      FROM zjp_po_i
      WHERE purchase_order_item_uuid = @item_2_key-PurchaseOrderItemUUID
      INTO TABLE @DATA(deleted_item_identity_db).
    out->write( name = 'Deleted item identity still persisted before commit'
                data = deleted_item_identity_db ).
    IF lines( deleted_item_identity_db ) <> 1
       OR deleted_item_identity_db[ 1 ]-purchase_order_uuid <> order_uuid.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected committed parent identity until delete commit.' ).
      RETURN.
    ENDIF.

    " Diagnostic only: deleted source may no longer support parent navigation.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem BY \_PurchaseOrder
        FIELDS ( PurchaseOrderUUID ) WITH VALUE #( ( %tky = item_2_key ) )
        RESULT DATA(parent_after_delete)
      FAILED DATA(failed_parent_after_delete)
      REPORTED DATA(reported_parent_after_delete).
    out->write( name = 'Diagnostic parent navigation from deleted item'
                data = parent_after_delete ).
    out->write( name = 'Diagnostic deleted-source FAILED - not a test failure'
                data = failed_parent_after_delete ).
    out->write( name = 'Diagnostic deleted-source REPORTED'
                data = reported_parent_after_delete ).

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
      ENTITY PurchaseOrderItem
        DELETE FROM VALUE #( ( %tky = item_1_key ) )
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

    SELECT purchase_order_item_uuid, purchase_order_uuid
      FROM zjp_po_i
      WHERE purchase_order_item_uuid = @item_1_key-PurchaseOrderItemUUID
      INTO TABLE @DATA(last_item_identity_db).
    out->write( name = 'Last item identity still persisted before commit'
                data = last_item_identity_db ).
    IF lines( last_item_identity_db ) <> 1
       OR last_item_identity_db[ 1 ]-purchase_order_uuid <> order_uuid.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected last item parent identity until delete commit.' ).
      RETURN.
    ENDIF.

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
ENDCLASS.
