CLASS zjp_cl_po_eml_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    METHODS save_changes
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS check_database
      IMPORTING order_uuid       TYPE sysuuid_x16
                expected_headers TYPE i
                expected_items   TYPE i
                expected_supplier TYPE zjp_po_h-supplier OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.
ENDCLASS.

CLASS zjp_cl_po_eml_test IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    console = out.

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
            Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_create)
      FAILED DATA(failed_create)
      REPORTED DATA(reported_create).

    out->write( name = 'Create MAPPED' data = mapped_create ).
    out->write( name = 'Create FAILED' data = failed_create ).
    out->write( name = 'Create REPORTED' data = reported_create ).

    IF failed_create IS NOT INITIAL
       OR NOT line_exists( mapped_create-purchaseorder[ %cid = 'PO_1' ] )
       OR NOT line_exists( mapped_create-purchaseorderitem[ %cid = 'ITEM_1' ] ).
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

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1 OR lines( items ) <> 1.
      ROLLBACK ENTITIES.
      out->write( 'STOP: expected one header and one item in the RAP buffer.' ).
      RETURN.
    ENDIF.

    DATA(order_key) = orders[ 1 ]-%tky.
    IF items[ 1 ]-PurchaseOrderUUID <> order_uuid
       OR items[ 1 ]-PurchaseOrderItemUUID IS INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: item identity or parent relationship is incorrect.' ).
      RETURN.
    ENDIF.

    out->write( 'Database before first commit: expect 0 headers and 0 items.' ).
    IF check_database( order_uuid = order_uuid
                       expected_headers = 0 expected_items = 0 ) = abap_false.
      ROLLBACK ENTITIES.
      RETURN.
    ENDIF.

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    out->write( 'CHECKPOINT 1: create committed; expect SUP001 and one item.' ).
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 1
                       expected_supplier = 'SUP001' ) = abap_false.
      RETURN.
    ENDIF.

    " Set an ADT breakpoint here to inspect the committed test rows.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = order_key Supplier = 'SUP002' ) )
      FAILED DATA(failed_update)
      REPORTED DATA(reported_update).

    out->write( name = 'Update FAILED' data = failed_update ).
    out->write( name = 'Update REPORTED' data = reported_update ).
    IF failed_update IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: update failed; the previously committed order remains.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = order_key ) )
        RESULT DATA(updated_orders)
      FAILED DATA(failed_update_read)
      REPORTED DATA(reported_update_read).

    out->write( name = 'Header read after update commit' data = updated_orders ).
    out->write( name = 'Update read FAILED' data = failed_update_read ).
    out->write( name = 'Update read REPORTED' data = reported_update_read ).
    IF failed_update_read IS NOT INITIAL OR lines( updated_orders ) <> 1.
      ROLLBACK ENTITIES.
      out->write( 'STOP: could not read the committed update.' ).
      RETURN.
    ENDIF.
    IF updated_orders[ 1 ]-Supplier <> 'SUP002'.
      ROLLBACK ENTITIES.
      out->write( 'STOP: EML read did not return the expected supplier.' ).
      RETURN.
    ENDIF.

    out->write( 'CHECKPOINT 2: update committed; expect SUP002 and one item.' ).
    IF check_database( order_uuid = order_uuid
                       expected_headers = 1 expected_items = 1
                       expected_supplier = 'SUP002' ) = abap_false.
      RETURN.
    ENDIF.

    " Set an ADT breakpoint here to inspect rows before cleanup.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( %tky = order_key ) )
      FAILED DATA(failed_delete)
      REPORTED DATA(reported_delete).

    out->write( name = 'Delete FAILED' data = failed_delete ).
    out->write( name = 'Delete REPORTED' data = reported_delete ).
    IF failed_delete IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( 'STOP: delete failed; retain the printed UUID for cleanup.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'CHECKPOINT 3: delete committed; expect 0 headers and 0 items.' ).
    IF check_database( order_uuid = order_uuid
                       expected_headers = 0 expected_items = 0 ) = abap_false.
      RETURN.
    ENDIF.
    out->write( 'PASS: managed create/read/update/delete and composition cleanup.' ).
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
    SELECT purchase_order_uuid, supplier, currency, total_amount,
           status, purchase_order_number, created_by, created_at,
           local_last_changed_at
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(headers_db).

    SELECT purchase_order_item_uuid, purchase_order_uuid, item_number,
           quantity, net_price, currency, total_amount
      FROM zjp_po_i
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(items_db).

    console->write( name = 'ZJP_PO_H - only this test UUID' data = headers_db ).
    console->write( name = 'ZJP_PO_I - only this test UUID' data = items_db ).

    success = xsdbool( lines( headers_db ) = expected_headers
                      AND lines( items_db ) = expected_items ).
    IF success = abap_true AND expected_headers = 1.
      success = xsdbool( headers_db[ 1 ]-supplier = expected_supplier ).
    ENDIF.
    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: database verification failed; retain the test UUID.' ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
