CLASS zjp_cl_po_eml_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " UUIDs of the terminal lifecycle fixtures created by THIS execution.
    " Collected so the final summary can select by exact key instead of by
    " Status or Supplier, which would also pick up residue from earlier runs.
    DATA lifecycle_uuids TYPE STANDARD TABLE OF sysuuid_x16 WITH EMPTY KEY.

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
                " Initial means the row must still carry no number, which is
                " the correct expectation for every order that has not been
                " through a successful submit.
                expected_number       TYPE zjp_po_h-purchase_order_number OPTIONAL
      RETURNING VALUE(success) TYPE abap_bool.

    " Phase 5.2a. Verifies the two integration header values for one order
    " straight from ZJP_PO_H. Deliberately a separate helper rather than two
    " more optional parameters on check_submit_database: that helper has
    " eleven call sites whose expectations are already runtime-verified, and
    " widening it would silently impose a new assertion on all of them.
    "
    " Only orders created by this run are ever passed here. Rows persisted
    " before Phase 5 carry a blank integration_status, which is correct and
    " untouched, so no assertion in this class may read one of them.
    METHODS check_integration_fields
      IMPORTING order_uuid                  TYPE sysuuid_x16
                expected_revision           TYPE zjp_po_h-order_revision
                expected_integration_status TYPE zjp_po_h-integration_status
                label                       TYPE string
      RETURNING VALUE(success)              TYPE abap_bool.

    " Phase 5.2b. DeliveryIntent persistence and uniqueness only — no dispatch,
    " no transport, no sendToSupplier. Extending this class rather than creating
    " a new one follows the object inventory, which names ZJP_CL_PO_EML_TEST as
    " the class to extend whenever RAP behavior changes and reserves
    " ZJP_CL_PO_DISPATCH_TEST for the later coordinator.
    METHODS test_dlv_intent_persist
      IMPORTING order_uuid     TYPE sysuuid_x16
      RETURNING VALUE(success) TYPE abap_bool.

    " COMMIT ENTITIES selecting the DeliveryIntent response. `save_changes`
    " reports the PurchaseOrder response and cannot see this BO's failures.
    METHODS save_intent_changes
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS check_intent_database
      IMPORTING delivery_uuid     TYPE sysuuid_x16
                expected_rows     TYPE i
                expected_order    TYPE sysuuid_x16 OPTIONAL
                expected_revision TYPE zjp_po_dlv-order_revision OPTIONAL
                expected_state    TYPE zjp_po_dlv-dispatch_state OPTIONAL
                label             TYPE string
      RETURNING VALUE(success)    TYPE abap_bool.

    METHODS read_order_number
      IMPORTING order_uuid          TYPE sysuuid_x16
      RETURNING VALUE(order_number) TYPE zjp_po_h-purchase_order_number.

    METHODS check_number_format
      IMPORTING order_number   TYPE zjp_po_h-purchase_order_number
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_submitted_immutability
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_draft_still_editable
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_approve_lifecycle
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_reject_lifecycle
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_cancel_lifecycle
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS create_open_fixture
      IMPORTING supplier          TYPE zjp_po_h-supplier
      RETURNING VALUE(order_uuid) TYPE sysuuid_x16.

    METHODS create_decision_fixture
      IMPORTING supplier          TYPE zjp_po_h-supplier
      RETURNING VALUE(order_uuid) TYPE sysuuid_x16.

    METHODS expect_delete_rejected
      IMPORTING order_uuid      TYPE sysuuid_x16
                expected_status TYPE zjp_po_h-status
                expected_items  TYPE i
                expected_total  TYPE zjp_po_h-total_amount
                expected_number TYPE zjp_po_h-purchase_order_number OPTIONAL
      RETURNING VALUE(success)  TYPE abap_bool.

    METHODS print_lifecycle_summary.

    METHODS check_decision_database
      IMPORTING order_uuid      TYPE sysuuid_x16
                expected_status TYPE zjp_po_h-status
                expected_total  TYPE zjp_po_h-total_amount
                expected_origin TYPE zjp_po_h-rejection_origin OPTIONAL
                expected_reason TYPE zjp_po_h-rejection_reason OPTIONAL
                expected_number TYPE zjp_po_h-purchase_order_number OPTIONAL
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

    IF test_submitted_immutability( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_draft_still_editable( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: Phase 2.7B rejects root, item, CBA and removeItem changes after SUBMITTED.' ).

    IF test_approve_lifecycle( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_reject_lifecycle( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: Phase 2.7C approve and reject transitions with lifecycle immutability.' ).

    IF test_cancel_lifecycle( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: Phase 2.7D-1 cancel lifecycle verified.' ).
    out->write( 'PASS: Phase 2.7D-2 root DELETE is limited to DRAFT.' ).
    out->write( 'PASS: PurchaseOrderNumber is allocated on submit only.' ).

    " Phase 5.2b. Runs last and after the PurchaseOrder suite, because it is a
    " different business object and must not disturb any lifecycle assertion
    " above it. It correlates to `order_uuid`, a real key from this run.
    IF test_dlv_intent_persist( order_uuid ) = abap_false.
      print_lifecycle_summary( ).
      RETURN.
    ENDIF.
    out->write( 'PASS: Phase 5.2b DeliveryIntent persistence verified.' ).

    print_lifecycle_summary( ).
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
    " Phase 5.2a. A newly created root is DRAFT, has been through
    " initializeStatus, and is not yet deliverable: revision 0 is below the
    " minimum CAP accepts, and NOT_REQUESTED says no delivery was asked for.
    IF check_integration_fields( order_uuid = submit_uuid
                                 expected_revision = 0
                                 expected_integration_status = 'NOT_REQUESTED'
                                 label = 'new order before submit' ) = abap_false.
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

    " Phase 5.2a adds OrderRevision to this buffer assertion. Checking it here
    " rather than only after the commit proves the action wrote it, not a
    " determination or a save-time side effect.
    IF failed_submit IS NOT INITIAL OR failed_submitted_read IS NOT INITIAL
       OR lines( submitted_orders ) <> 1 OR lines( submitted_items ) <> 1
       OR submitted_orders[ 1 ]-Status <> 'SUBMITTED'
       OR submitted_orders[ 1 ]-OrderRevision <> 1
       OR submitted_orders[ 1 ]-IntegrationStatus <> 'NOT_REQUESTED'
       OR submitted_orders[ 1 ]-TotalAmount <> 1500
       OR submitted_items[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit must set Status SUBMITTED, OrderRevision 1 ' &&
                      'and leave totals unchanged.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: submit set the buffered Status to SUBMITTED with total 1500.' ).
    console->write( 'PASS: submit set the buffered OrderRevision to 1; ' &&
                    'IntegrationStatus stayed NOT_REQUESTED.' ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    DATA(submit_number) = read_order_number( submit_uuid ).
    console->write( name = 'Allocated PurchaseOrderNumber' data = submit_number ).
    IF check_number_format( submit_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.
    IF check_submit_database( order_uuid = submit_uuid
                              expected_headers = 1 expected_items = 1
                              expected_status = 'SUBMITTED'
                              expected_header_total = 1500
                              expected_number = submit_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: SUBMITTED status is persisted in ZJP_PO_H.' ).
    console->write( 'PASS: submit allocated PurchaseOrderNumber as PO + 8 digits.' ).
    " Phase 5.2a. Revision 1 must survive the commit, and submit must not have
    " disturbed IntegrationStatus, which only initializeStatus owns today.
    IF check_integration_fields( order_uuid = submit_uuid
                                 expected_revision = 1
                                 expected_integration_status = 'NOT_REQUESTED'
                                 label = 'after successful submit' ) = abap_false.
      RETURN.
    ENDIF.

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
    " A refused second submit must not draw or replace a number.
    IF check_submit_database( order_uuid = submit_uuid
                              expected_headers = 1 expected_items = 1
                              expected_status = 'SUBMITTED'
                              expected_header_total = 1500
                              expected_number = submit_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: re-submit rejected; persisted SUBMITTED order unchanged.' ).
    console->write( 'PASS: a refused re-submit kept the original PO number.' ).
    " Phase 5.2a. A refused second submit must neither re-write nor increment
    " the revision: it exits before the update, so 1 is still 1.
    IF check_integration_fields( order_uuid = submit_uuid
                                 expected_revision = 1
                                 expected_integration_status = 'NOT_REQUESTED'
                                 label = 'after refused re-submit' ) = abap_false.
      RETURN.
    ENDIF.

    " Phase 2.7D-2 replaced this teardown. Deleting the SUBMITTED fixture is
    " no longer valid behavior, so the assertion is inverted and the row is
    " left behind on purpose.
    success = expect_delete_rejected( order_uuid = submit_uuid
                                      expected_status = 'SUBMITTED'
                                      expected_items = 1
                                      expected_total = 1500
                                      expected_number = submit_number ).
    IF success = abap_true.
      console->write( 'PASS: SUBMITTED root DELETE rejected; fixture retained.' ).
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
    " Phase 5.2a. The decisive negative case for B1: a submit that fails must
    " leave the order undeliverable. The action exits before its update, so
    " the revision stays 0 and CAP would refuse a delivery built from it.
    IF check_integration_fields( order_uuid = empty_uuid
                                 expected_revision = 0
                                 expected_integration_status = 'NOT_REQUESTED'
                                 label = 'refused submit without items' ) = abap_false.
      RETURN.
    ENDIF.

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

  METHOD save_intent_changes.
    COMMIT ENTITIES RESPONSE OF ZJP_I_DeliveryIntent
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.

    console->write( name = 'Intent COMMIT sy-subrc' data = save_subrc ).
    console->write( name = 'Intent save FAILED' data = failed_save ).
    console->write( name = 'Intent save REPORTED' data = reported_save ).

    success = xsdbool( save_subrc = 0 AND failed_save IS INITIAL ).
    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'Intent save did not succeed; buffer rolled back.' ).
    ENDIF.
  ENDMETHOD.

  METHOD check_intent_database.
    " Read-only verification. Justified for the same reason as
    " check_submit_database: what the buffer reports and what the database holds
    " are different claims, and only the second one survives the commit. Every
    " WRITE in this class goes through EML; no INSERT, UPDATE or DELETE is
    " issued against ZJP_PO_DLV anywhere.
    SELECT delivery_uuid, purchase_order_uuid, order_revision, payload_hash,
           dispatch_state, last_correlation_id, portal_order_uuid,
           lease_owner, lease_expires_at
      FROM zjp_po_dlv
      WHERE delivery_uuid = @delivery_uuid
      INTO TABLE @DATA(intents_db).

    console->write( name = |ZJP_PO_DLV - { label }| data = intents_db ).

    success = xsdbool( lines( intents_db ) = expected_rows ).

    IF success = abap_true AND expected_rows = 1.
      DATA(row) = intents_db[ 1 ].
      " ADR-015: absent optional values are ABAP initial in non-null columns,
      " never SQL NULL. portal_order_uuid stays initial until a receipt
      " arrives, and the lease fields stay initial while unclaimed. Nothing in
      " Phase 5.2b writes any of the four.
      success = xsdbool(
        row-purchase_order_uuid = expected_order
        AND row-order_revision = expected_revision
        AND row-dispatch_state = expected_state
        AND row-portal_order_uuid IS INITIAL
        AND row-last_correlation_id IS INITIAL
        AND row-lease_owner IS INITIAL
        AND row-lease_expires_at IS INITIAL ).
    ENDIF.

    IF success = abap_false.
      console->write( |STOP: { label } - ZJP_PO_DLV verification failed.| ).
    ELSE.
      console->write( |PASS: { label } - persisted row and ADR-015 initial | &&
                      |values are correct.| ).
    ENDIF.
  ENDMETHOD.

  METHOD test_dlv_intent_persist.
    " Phase 5.2b proves three things and deliberately no more: an intent can be
    " created and read back through EML, its documented initial values are
    " initial, and the unique Table Index refuses a second intent for the same
    " purchase order revision.
    "
    " `order_uuid` is a real PurchaseOrder key from this run. purchase_order_uuid
    " is a correlation rather than a foreign key (ADR-032), so nothing enforces
    " that the order exists — using a real one keeps the fixture honest.
    "
    " payload_hash carries an obviously synthetic placeholder. This slice stores
    " the column and computes nothing: the released hashing API is probe P13.
    CONSTANTS synthetic_hash TYPE c LENGTH 64
      VALUE '0000000000000000000000000000000000000000000000000000000000000000'.

    console->write( '=== PHASE 5.2b DELIVERY INTENT PERSISTENCE ===' ).

    GET TIME STAMP FIELD DATA(approved_at).

    MODIFY ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        CREATE FIELDS ( PurchaseOrderUUID OrderRevision PayloadSnapshot
                        PayloadHash DispatchState ApprovedBy ApprovedAt )
        WITH VALUE #( (
          %cid = 'INTENT_1'
          PurchaseOrderUUID = order_uuid
          OrderRevision = 1
          PayloadSnapshot = '{"probe":"phase-5-2b persistence only"}'
          PayloadHash = synthetic_hash
          DispatchState = 'PENDING'
          ApprovedBy = sy-uname
          ApprovedAt = approved_at ) )
      MAPPED DATA(mapped_intent)
      FAILED DATA(failed_intent_create)
      REPORTED DATA(reported_intent_create).

    console->write( name = 'Intent create MAPPED' data = mapped_intent ).
    console->write( name = 'Intent create FAILED - expect empty'
                    data = failed_intent_create ).
    console->write( name = 'Intent create REPORTED'
                    data = reported_intent_create ).

    IF failed_intent_create IS NOT INITIAL
       OR NOT line_exists( mapped_intent-deliveryintent[ %cid = 'INTENT_1' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: DeliveryIntent create failed.' ).
      RETURN.
    ENDIF.

    " The key is framework-assigned, so it is read out of MAPPED rather than
    " supplied. This is also what sendToSupplier will do to learn the wire
    " deliveryId it must replay.
    DATA(intent_uuid) =
      mapped_intent-deliveryintent[ %cid = 'INTENT_1' ]-DeliveryUUID.
    console->write( name = 'Generated DeliveryUUID - retain for diagnosis'
                    data = intent_uuid ).
    IF intent_uuid IS INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: managed numbering returned no DeliveryUUID.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_DeliveryIntent
      ENTITY DeliveryIntent
        ALL FIELDS WITH VALUE #( ( DeliveryUUID = intent_uuid ) )
        RESULT DATA(buffered_intents)
      FAILED DATA(failed_intent_read).

    console->write( name = 'Intent in buffer before commit'
                    data = buffered_intents ).

    IF failed_intent_read IS NOT INITIAL OR lines( buffered_intents ) <> 1
       OR buffered_intents[ 1 ]-PurchaseOrderUUID <> order_uuid
       OR buffered_intents[ 1 ]-OrderRevision <> 1
       OR buffered_intents[ 1 ]-DispatchState <> 'PENDING'
       OR buffered_intents[ 1 ]-PayloadHash <> synthetic_hash
       OR buffered_intents[ 1 ]-PayloadSnapshot IS INITIAL
       OR buffered_intents[ 1 ]-PortalOrderUUID IS NOT INITIAL
       OR buffered_intents[ 1 ]-LeaseOwner IS NOT INITIAL
       OR buffered_intents[ 1 ]-LeaseExpiresAt IS NOT INITIAL
       OR buffered_intents[ 1 ]-LastCorrelationId IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: buffered intent does not match the created values.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: intent readable in the buffer with PENDING state ' &&
                    'and initial receipt/lease fields.' ).

    IF save_intent_changes( ) = abap_false.
      console->write( 'STOP: first intent could not be committed.' ).
      RETURN.
    ENDIF.
    IF check_intent_database( delivery_uuid = intent_uuid
                              expected_rows = 1
                              expected_order = order_uuid
                              expected_revision = 1
                              expected_state = 'PENDING'
                              label = 'after first commit' ) = abap_false.
      RETURN.
    ENDIF.

    " Evidence D — answered by the compiler, so there is no runtime test here.
    "
    " A duplicate-key create was originally written into this method, supplying
    " the first row's own DeliveryUUID to see how the target would answer. ADT
    " refused to compile it:
    "   "The field "DELIVERYUUID" of entity "ZJP_I_DELIVERYINTENT" cannot be
    "    modified."
    " because DeliveryUUID is declared `field ( readonly, numbering : managed )`,
    " which bars it from a CREATE FIELDS list outright.
    "
    " That is a stronger answer than the runtime check it replaces. "A second
    " row with the same delivery_uuid is rejected" is not a behaviour that has
    " to be observed and could regress; the key cannot be supplied at all, so a
    " duplicate cannot be expressed, let alone persisted. The statement was
    " removed rather than worked around: keeping a compile error to preserve a
    " test would be the wrong trade, and loosening the BDEF to make the test
    " writable would require a UUID-creation API this project has never used and
    " no probe has established.
    "
    " Evidence E below is therefore the only uniqueness assertion this method
    " makes, and it is the one that carries the business rule.

    " Evidence E — deliberately NOT exercised here. This is a decision forced
    " by runtime evidence, not a gap.
    "
    " The unique Table Index ZJP_PO_DLV~REV over CLIENT + PURCHASE_ORDER_UUID +
    " ORDER_REVISION is physically present and proven to enforce the invariant.
    " It was verified once, by hand: a second intent for the same order and
    " revision, carrying a DIFFERENT generated DeliveryUUID, terminated in
    "   CX_SY_OPEN_SQL_DB -> CX_CSP_ACT_INTERNAL -> RAISE_SHORTDUMP
    " inside CL_CSP_ACT_SAVE_TO_DB, with the database reason naming a duplicate
    " primary or unique secondary key. Different DeliveryUUID values are what
    " make that evidence meaningful: the collision can only have been on the
    " secondary business index, not on the primary key.
    "
    " So on this target a managed RAP COMMIT ENTITIES that reaches a physical
    " unique-index violation does NOT come back as FAILED/REPORTED — it dumps.
    " A regression suite must therefore not provoke it on every run: the test
    " would not assert a refusal, it would abort the suite and leave every
    " assertion after it unrun. The constraint is the final persistence safety
    " net and stays exactly as it is; what changes is that verifying it is
    " manual infrastructure evidence rather than an automated assertion.
    "
    " Not replaced by a direct SQL write, and the dump is not caught or
    " suppressed. Both would trade a real guarantee for a green line.
    "
    " What remains automated below is the positive form of the same invariant:
    " after a successful create there is exactly ONE intent for this order and
    " revision. That asserts the state the index protects without attacking it.
    SELECT COUNT( * ) FROM zjp_po_dlv
      WHERE purchase_order_uuid = @order_uuid AND order_revision = 1
      INTO @DATA(rows_for_revision).
    console->write( name = 'Rows for this order and revision 1 - expect 1'
                    data = rows_for_revision ).

    IF rows_for_revision <> 1.
      console->write( 'STOP: expected exactly one DeliveryIntent for this ' &&
                      'order revision.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: exactly one DeliveryIntent exists for this order ' &&
                    'revision; the unique index invariant holds.' ).
    console->write( 'NOTE: the unique index is not attacked by this suite. ' &&
                    'ZJP_PO_DLV~REV is verified manually - see the Phase 5 guide.' ).
    console->write( 'One DeliveryIntent row is left behind on purpose as ' &&
                    'Phase 5.2b evidence; retain the printed DeliveryUUID.' ).
    success = abap_true.
  ENDMETHOD.

  METHOD check_integration_fields.
    " Read-only verification of the Phase 5.2a header values.
    SELECT SINGLE purchase_order_uuid, status, order_revision,
                  integration_status
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO @DATA(integration_db).
    DATA(row_found) = xsdbool( sy-subrc = 0 ).

    console->write( name = |ZJP_PO_H integration fields - { label }|
                    data = integration_db ).

    success = xsdbool(
      row_found = abap_true
      AND integration_db-order_revision = expected_revision
      AND integration_db-integration_status = expected_integration_status ).

    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( |STOP: { label } - expected OrderRevision | &&
                      |{ expected_revision } and IntegrationStatus | &&
                      |{ expected_integration_status }.| ).
    ELSE.
      console->write( |PASS: { label } - OrderRevision { expected_revision }, | &&
                      |IntegrationStatus { expected_integration_status }.| ).
    ENDIF.
  ENDMETHOD.

  METHOD read_order_number.
    " Read-only. The allocated number is environmental, so the tests capture
    " whatever this run drew and compare later lifecycle states against that
    " captured value instead of asserting a literal like PO00000002.
    SELECT SINGLE purchase_order_number
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO @order_number.
  ENDMETHOD.

  METHOD check_number_format.
    " Approved business format: 'PO' plus exactly eight digits, left aligned
    " in the CHAR(20) field. Checked structurally, never against a literal.
    success = xsdbool( order_number(2) = 'PO'
                       AND order_number+2(8) CO '0123456789'
                       AND order_number+10 IS INITIAL ).
    IF success = abap_false.
      console->write( name = 'Unexpected PurchaseOrderNumber' data = order_number ).
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
                        AND headers_db[ 1 ]-purchase_order_number
                              = expected_number ).
    ENDIF.

    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit database verification failed; retain the test UUID.' ).
    ELSE.
      console->write( 'PASS: submit database checkpoint values are correct.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_submitted_immutability.
    " Phase 2.7B fixture: two items, 2 x 750 + 4 x 100 = 1900, submitted.
    DATA(root_text) = CONV string( 'Only draft orders can be changed.' ).
    DATA(item_text) = CONV string( 'Only draft order items can change.' ).
    DATA(cba_text) = CONV string( 'Items can be added to draft orders only.' ).
    DATA(remove_text) = CONV string( 'Only draft orders can lose items.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'LOCK_ROOT'
                        Supplier = 'SUP005'
                        CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'LOCK_ROOT'
          %target = VALUE #( ( %cid = 'LOCK_ITEM_1' ItemNumber = '00010'
                               Material = 'MAT001' Quantity = 2
                               UnitOfMeasure = 'EA' NetPrice = '750.00'
                               Currency = 'EUR' )
                             ( %cid = 'LOCK_ITEM_2' ItemNumber = '00020'
                               Material = 'MAT002' Quantity = 4
                               UnitOfMeasure = 'EA' NetPrice = '100.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_lock)
      FAILED DATA(failed_lock_create)
      REPORTED DATA(reported_lock_create).

    console->write( name = 'Immutability fixture FAILED' data = failed_lock_create ).
    console->write( name = 'Immutability fixture REPORTED' data = reported_lock_create ).
    IF failed_lock_create IS NOT INITIAL
       OR NOT line_exists( mapped_lock-purchaseorder[ %cid = 'LOCK_ROOT' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: immutability fixture creation failed.' ).
      RETURN.
    ENDIF.

    DATA(lock_uuid) =
      mapped_lock-purchaseorder[ %cid = 'LOCK_ROOT' ]-PurchaseOrderUUID.
    console->write( name = 'Immutability order UUID - retain for diagnosis'
                    data = lock_uuid ).

    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = lock_uuid ) )
        RESULT DATA(lock_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = lock_uuid ) )
        RESULT DATA(lock_items)
      FAILED DATA(failed_lock_read).
    IF failed_lock_read IS NOT INITIAL OR lines( lock_orders ) <> 1
       OR lines( lock_items ) <> 2
       OR NOT line_exists( lock_items[ ItemNumber = '00010' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: immutability fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(lock_key) = lock_orders[ 1 ]-%tky.
    DATA(lock_item_key) = lock_items[ ItemNumber = '00010' ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = lock_key ) )
      FAILED DATA(failed_lock_submit)
      REPORTED DATA(reported_lock_submit).
    IF failed_lock_submit IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit failed on the immutability fixture.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    DATA(lock_number) = read_order_number( lock_uuid ).
    console->write( name = 'Immutability fixture PO number' data = lock_number ).
    IF check_number_format( lock_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.
    IF check_submit_database( order_uuid = lock_uuid
                              expected_headers = 1 expected_items = 2
                              expected_status = 'SUBMITTED'
                              expected_header_total = 1900
                              expected_number = lock_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: immutability fixture is SUBMITTED with total 1900.' ).

    " 1 - root Supplier.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = lock_key Supplier = 'SUP999' ) )
      FAILED DATA(failed_supplier)
      REPORTED DATA(reported_supplier).
    console->write( name = 'Root Supplier update FAILED' data = failed_supplier ).
    console->write( name = 'Root Supplier update REPORTED' data = reported_supplier ).
    DATA(supplier_blocked) = xsdbool(
      line_exists( failed_supplier-purchaseorder[ %tky = lock_key ] ) ).
    DATA(supplier_message) = abap_false.
    LOOP AT reported_supplier-purchaseorder INTO DATA(supplier_line).
      IF supplier_line-%msg IS BOUND.
        IF supplier_line-%msg->if_message~get_text( ) = root_text.
          supplier_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    " 2 - root Currency.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Currency )
        WITH VALUE #( ( %tky = lock_key Currency = 'USD' ) )
      FAILED DATA(failed_currency)
      REPORTED DATA(reported_currency).
    console->write( name = 'Root Currency update FAILED' data = failed_currency ).
    DATA(currency_blocked) = xsdbool(
      line_exists( failed_currency-purchaseorder[ %tky = lock_key ] ) ).
    ROLLBACK ENTITIES.

    " 3 - item Quantity.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = lock_item_key Quantity = 99 ) )
      FAILED DATA(failed_quantity)
      REPORTED DATA(reported_quantity).
    console->write( name = 'Item Quantity update FAILED' data = failed_quantity ).
    console->write( name = 'Item Quantity update REPORTED' data = reported_quantity ).
    DATA(quantity_blocked) = xsdbool(
      line_exists( failed_quantity-purchaseorderitem[ %tky = lock_item_key ] ) ).
    DATA(quantity_message) = abap_false.
    LOOP AT reported_quantity-purchaseorderitem INTO DATA(quantity_line).
      IF quantity_line-%msg IS BOUND.
        IF quantity_line-%msg->if_message~get_text( ) = item_text.
          quantity_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    " 4 - item Material.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Material )
        WITH VALUE #( ( %tky = lock_item_key Material = 'MAT999' ) )
      FAILED DATA(failed_material)
      REPORTED DATA(reported_material).
    console->write( name = 'Item Material update FAILED' data = failed_material ).
    DATA(material_blocked) = xsdbool(
      line_exists( failed_material-purchaseorderitem[ %tky = lock_item_key ] ) ).
    ROLLBACK ENTITIES.

    " 5 - create-by-association of a third item.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %tky = lock_key
          %target = VALUE #( ( %cid = 'LOCK_ITEM_3' ItemNumber = '00030'
                               Material = 'MAT003' Quantity = 1
                               UnitOfMeasure = 'EA' NetPrice = '50.00'
                               Currency = 'EUR' ) ) ) )
      FAILED DATA(failed_cba)
      REPORTED DATA(reported_cba).
    console->write( name = 'Create-by-association FAILED' data = failed_cba ).
    console->write( name = 'Create-by-association REPORTED' data = reported_cba ).
    DATA(cba_blocked) = xsdbool(
      line_exists( failed_cba-purchaseorder[ %tky = lock_key ] ) ).
    DATA(cba_message) = abap_false.
    LOOP AT reported_cba-purchaseorder INTO DATA(cba_line).
      IF cba_line-%msg IS BOUND.
        IF cba_line-%msg->if_message~get_text( ) = cba_text.
          cba_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    " 6 - removeItem.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = lock_key
          %param-PurchaseOrderItemUUID = lock_item_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_remove)
      REPORTED DATA(reported_remove).
    console->write( name = 'removeItem after submit FAILED' data = failed_remove ).
    console->write( name = 'removeItem after submit REPORTED' data = reported_remove ).
    DATA(remove_blocked) = xsdbool( line_exists(
      failed_remove-purchaseorder[ %tky = lock_key
        %op-%action-removeItem = if_abap_behv=>mk-on ] ) ).
    DATA(remove_message) = abap_false.
    LOOP AT reported_remove-purchaseorder INTO DATA(remove_line).
      IF remove_line-%msg IS BOUND.
        IF remove_line-%msg->if_message~get_text( ) = remove_text.
          remove_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF supplier_blocked = abap_false OR supplier_message = abap_false
       OR currency_blocked = abap_false
       OR quantity_blocked = abap_false OR quantity_message = abap_false
       OR material_blocked = abap_false
       OR cba_blocked = abap_false OR cba_message = abap_false
       OR remove_blocked = abap_false OR remove_message = abap_false.
      console->write( 'STOP: a submitted-order mutation was not rejected.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: all six submitted-order mutations were rejected.' ).

    " Every rejected mutation must also leave the allocated number alone.
    IF check_submit_database( order_uuid = lock_uuid
                              expected_headers = 1 expected_items = 2
                              expected_status = 'SUBMITTED'
                              expected_header_total = 1900
                              expected_number = lock_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: the persisted submitted order is unchanged.' ).
    console->write( 'PASS: rejected mutations left the PO number untouched.' ).

    " Root DELETE was allowed here in Phase 2.7B and is rejected from Phase
    " 2.7D-2 onwards. This two-item fixture is deliberate residue.
    success = expect_delete_rejected( order_uuid = lock_uuid
                                      expected_status = 'SUBMITTED'
                                      expected_items = 2
                                      expected_total = 1900
                                      expected_number = lock_number ).
    IF success = abap_true.
      console->write( 'PASS: SUBMITTED two-item root DELETE rejected; kept.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_draft_still_editable.
    " Negative control: an order still in DRAFT keeps every commercial path.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'OPEN_ROOT'
                        Supplier = 'SUP006'
                        CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'OPEN_ROOT'
          %target = VALUE #( ( %cid = 'OPEN_ITEM' ItemNumber = '00010'
                               Material = 'MAT001' Quantity = 2
                               UnitOfMeasure = 'EA' NetPrice = '750.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_open)
      FAILED DATA(failed_open_create)
      REPORTED DATA(reported_open_create).
    console->write( name = 'DRAFT control fixture FAILED' data = failed_open_create ).
    IF failed_open_create IS NOT INITIAL
       OR NOT line_exists( mapped_open-purchaseorder[ %cid = 'OPEN_ROOT' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: DRAFT control fixture creation failed.' ).
      RETURN.
    ENDIF.
    DATA(open_uuid) =
      mapped_open-purchaseorder[ %cid = 'OPEN_ROOT' ]-PurchaseOrderUUID.
    console->write( name = 'DRAFT control UUID' data = open_uuid ).
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = open_uuid ) )
        RESULT DATA(open_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = open_uuid ) )
        RESULT DATA(open_items)
      FAILED DATA(failed_open_read).
    IF failed_open_read IS NOT INITIAL OR lines( open_orders ) <> 1
       OR lines( open_items ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: DRAFT control fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(open_key) = open_orders[ 1 ]-%tky.
    DATA(open_item_key) = open_items[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = open_key Supplier = 'SUP007' ) )
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = open_item_key Quantity = 3 ) )
      FAILED DATA(failed_open_update)
      REPORTED DATA(reported_open_update).
    console->write( name = 'DRAFT control update FAILED - expect empty'
                    data = failed_open_update ).
    IF failed_open_update IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: a DRAFT order must still accept commercial changes.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_submit_database( order_uuid = open_uuid
                              expected_headers = 1 expected_items = 1
                              expected_status = 'DRAFT'
                              expected_header_total = 2250 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: DRAFT order still accepts Supplier and Quantity changes.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( PurchaseOrderUUID = open_uuid ) )
      FAILED DATA(failed_open_cleanup)
      REPORTED DATA(reported_open_cleanup).
    IF failed_open_cleanup IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: DRAFT control cleanup failed.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    success = check_submit_database( order_uuid = open_uuid
                                     expected_headers = 0 expected_items = 0 ).
    IF success = abap_true.
      console->write( 'PASS: DRAFT control fixture cleanup complete.' ).
      console->write( 'PASS: DRAFT root DELETE succeeds and removes its items.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_approve_lifecycle.
    DATA(decided_text) = CONV string( 'Only submitted orders can be decided.' ).
    DATA(root_text) = CONV string( 'Only draft orders can be changed.' ).
    DATA(item_text) = CONV string( 'Only draft order items can change.' ).
    DATA(cba_text) = CONV string( 'Items can be added to draft orders only.' ).
    DATA(remove_text) = CONV string( 'Only draft orders can lose items.' ).

    DATA(approve_uuid) = create_decision_fixture( 'SUP010' ).
    IF approve_uuid IS INITIAL.
      RETURN.
    ENDIF.
    " The fixture is already SUBMITTED, so submit has drawn its number.
    " Every later state must show exactly this captured value.
    DATA(approve_number) = read_order_number( approve_uuid ).
    console->write( name = 'Fixture SUP010 PO number' data = approve_number ).
    IF check_number_format( approve_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = approve_uuid ) )
        RESULT DATA(approve_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = approve_uuid ) )
        RESULT DATA(approve_items)
      FAILED DATA(failed_approve_read).
    IF failed_approve_read IS NOT INITIAL OR lines( approve_orders ) <> 1
       OR lines( approve_items ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: approve fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(approve_key) = approve_orders[ 1 ]-%tky.
    DATA(approve_item_key) = approve_items[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = approve_key ) )
      FAILED DATA(failed_approve)
      REPORTED DATA(reported_approve).
    console->write( name = 'approve FAILED - expect empty' data = failed_approve ).
    console->write( name = 'approve REPORTED' data = reported_approve ).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = approve_key ) )
        RESULT DATA(approved_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = approve_key ) )
        RESULT DATA(approved_items)
      FAILED DATA(failed_approved_read).
    IF failed_approve IS NOT INITIAL OR failed_approved_read IS NOT INITIAL
       OR lines( approved_orders ) <> 1 OR lines( approved_items ) <> 1
       OR approved_orders[ 1 ]-Status <> 'APPROVED'
       OR approved_orders[ 1 ]-TotalAmount <> 1500
       OR approved_items[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      console->write( 'STOP: approve must set APPROVED and leave totals unchanged.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_decision_database( order_uuid = approve_uuid
                                expected_status = 'APPROVED'
                                expected_total = 1500
                                expected_number = approve_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: SUBMITTED to APPROVED persisted with total 1500.' ).

    " A decided order cannot be decided again, in either direction.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = approve_key ) )
      FAILED DATA(failed_reapprove)
      REPORTED DATA(reported_reapprove).
    DATA(reapprove_blocked) = xsdbool( line_exists(
      failed_reapprove-purchaseorder[ %tky = approve_key
        %op-%action-approve = if_abap_behv=>mk-on ] ) ).
    DATA(reapprove_message) = abap_false.
    LOOP AT reported_reapprove-purchaseorder INTO DATA(reapprove_line).
      IF reapprove_line-%msg IS BOUND.
        IF reapprove_line-%msg->if_message~get_text( ) = decided_text.
          reapprove_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE reject FROM VALUE #( (
          %tky = approve_key
          %param-RejectionReason = 'Late objection' ) )
      FAILED DATA(failed_reject_approved)
      REPORTED DATA(reported_reject_approved).
    DATA(reject_approved_blocked) = xsdbool( line_exists(
      failed_reject_approved-purchaseorder[ %tky = approve_key
        %op-%action-reject = if_abap_behv=>mk-on ] ) ).
    ROLLBACK ENTITIES.

    " The Phase 2.7B invariant must now cover APPROVED, not just SUBMITTED.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = approve_key Supplier = 'SUP999' ) )
      FAILED DATA(failed_root_on_approved)
      REPORTED DATA(reported_root_on_approved).
    DATA(root_on_approved_blocked) = xsdbool( line_exists(
      failed_root_on_approved-purchaseorder[ %tky = approve_key ] ) ).
    DATA(root_on_approved_message) = abap_false.
    LOOP AT reported_root_on_approved-purchaseorder INTO DATA(root_line).
      IF root_line-%msg IS BOUND.
        IF root_line-%msg->if_message~get_text( ) = root_text.
          root_on_approved_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = approve_item_key Quantity = 99 ) )
      FAILED DATA(failed_item_on_approved)
      REPORTED DATA(reported_item_on_approved).
    DATA(item_on_approved_blocked) = xsdbool( line_exists(
      failed_item_on_approved-purchaseorderitem[ %tky = approve_item_key ] ) ).
    DATA(item_on_approved_message) = abap_false.
    LOOP AT reported_item_on_approved-purchaseorderitem INTO DATA(item_line).
      IF item_line-%msg IS BOUND.
        IF item_line-%msg->if_message~get_text( ) = item_text.
          item_on_approved_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %tky = approve_key
          %target = VALUE #( ( %cid = 'APPROVED_EXTRA' ItemNumber = '00090'
                               Material = 'MAT009' Quantity = 1
                               UnitOfMeasure = 'EA' NetPrice = '10.00'
                               Currency = 'EUR' ) ) ) )
      FAILED DATA(failed_cba_on_approved)
      REPORTED DATA(reported_cba_on_approved).
    DATA(cba_on_approved_blocked) = xsdbool( line_exists(
      failed_cba_on_approved-purchaseorder[ %tky = approve_key ] ) ).
    DATA(cba_on_approved_message) = abap_false.
    LOOP AT reported_cba_on_approved-purchaseorder INTO DATA(cba_line).
      IF cba_line-%msg IS BOUND.
        IF cba_line-%msg->if_message~get_text( ) = cba_text.
          cba_on_approved_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = approve_key
          %param-PurchaseOrderItemUUID =
            approve_item_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_remove_on_approved)
      REPORTED DATA(reported_remove_on_approved).
    DATA(remove_on_approved_blocked) = xsdbool( line_exists(
      failed_remove_on_approved-purchaseorder[ %tky = approve_key
        %op-%action-removeItem = if_abap_behv=>mk-on ] ) ).
    DATA(remove_on_approved_message) = abap_false.
    LOOP AT reported_remove_on_approved-purchaseorder INTO DATA(remove_line).
      IF remove_line-%msg IS BOUND.
        IF remove_line-%msg->if_message~get_text( ) = remove_text.
          remove_on_approved_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF reapprove_blocked = abap_false OR reapprove_message = abap_false
       OR reject_approved_blocked = abap_false
       OR root_on_approved_blocked = abap_false
       OR root_on_approved_message = abap_false
       OR item_on_approved_blocked = abap_false
       OR item_on_approved_message = abap_false
       OR cba_on_approved_blocked = abap_false
       OR cba_on_approved_message = abap_false
       OR remove_on_approved_blocked = abap_false
       OR remove_on_approved_message = abap_false.
      console->write( 'STOP: an APPROVED order accepted a decision or a change.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: APPROVED rejects re-decision and every commercial change.' ).

    IF check_decision_database( order_uuid = approve_uuid
                                expected_status = 'APPROVED'
                                expected_total = 1500
                                expected_number = approve_number ) = abap_false.
      RETURN.
    ENDIF.

    " Phase 2.7D-2: an APPROVED order can no longer be deleted.
    success = expect_delete_rejected( order_uuid = approve_uuid
                                      expected_status = 'APPROVED'
                                      expected_items = 1
                                      expected_total = 1500
                                      expected_number = approve_number ).
    IF success = abap_true.
      console->write( 'PASS: APPROVED root DELETE rejected; fixture retained.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_reject_lifecycle.
    DATA(decided_text) = CONV string( 'Only submitted orders can be decided.' ).
    DATA(reason_text) = CONV string( 'Rejection reason is required.' ).
    DATA(root_text) = CONV string( 'Only draft orders can be changed.' ).
    DATA(reason_value) = CONV zjp_po_h-rejection_reason( 'Budget exceeded' ).

    DATA(reject_uuid) = create_decision_fixture( 'SUP011' ).
    IF reject_uuid IS INITIAL.
      RETURN.
    ENDIF.
    " The fixture is already SUBMITTED, so submit has drawn its number.
    " Every later state must show exactly this captured value.
    DATA(reject_number) = read_order_number( reject_uuid ).
    console->write( name = 'Fixture SUP011 PO number' data = reject_number ).
    IF check_number_format( reject_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = reject_uuid ) )
        RESULT DATA(reject_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = reject_uuid ) )
        RESULT DATA(reject_items)
      FAILED DATA(failed_reject_read).
    IF failed_reject_read IS NOT INITIAL OR lines( reject_orders ) <> 1
       OR lines( reject_items ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: reject fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(reject_key) = reject_orders[ 1 ]-%tky.
    DATA(reject_item_key) = reject_items[ 1 ]-%tky.

    " An empty reason must be refused before anything is written.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE reject FROM VALUE #( (
          %tky = reject_key
          %param-RejectionReason = '' ) )
      FAILED DATA(failed_empty_reason)
      REPORTED DATA(reported_empty_reason).
    console->write( name = 'Empty reason FAILED - expect rejection'
                    data = failed_empty_reason ).
    console->write( name = 'Empty reason REPORTED' data = reported_empty_reason ).
    DATA(empty_reason_blocked) = xsdbool( line_exists(
      failed_empty_reason-purchaseorder[ %tky = reject_key
        %op-%action-reject = if_abap_behv=>mk-on ] ) ).
    DATA(empty_reason_message) = abap_false.
    LOOP AT reported_empty_reason-purchaseorder INTO DATA(reason_line).
      IF reason_line-%msg IS BOUND.
        IF reason_line-%msg->if_message~get_text( ) = reason_text.
          empty_reason_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = reject_key ) )
        RESULT DATA(after_empty_reason)
      FAILED DATA(failed_after_empty).
    DATA(empty_reason_unchanged) = xsdbool(
      failed_after_empty IS INITIAL
      AND lines( after_empty_reason ) = 1
      AND after_empty_reason[ 1 ]-Status = 'SUBMITTED'
      AND after_empty_reason[ 1 ]-RejectionOrigin IS INITIAL
      AND after_empty_reason[ 1 ]-RejectionReason IS INITIAL ).
    ROLLBACK ENTITIES.

    IF empty_reason_blocked = abap_false OR empty_reason_message = abap_false
       OR empty_reason_unchanged = abap_false.
      console->write( 'STOP: an empty rejection reason was not refused cleanly.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: reject without a reason is refused and writes nothing.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE reject FROM VALUE #( (
          %tky = reject_key
          %param-RejectionReason = reason_value ) )
      FAILED DATA(failed_reject)
      REPORTED DATA(reported_reject).
    console->write( name = 'reject FAILED - expect empty' data = failed_reject ).
    console->write( name = 'reject REPORTED' data = reported_reject ).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = reject_key ) )
        RESULT DATA(rejected_orders)
      FAILED DATA(failed_rejected_read).
    console->write( name = 'Header after reject' data = rejected_orders ).
    IF failed_reject IS NOT INITIAL OR failed_rejected_read IS NOT INITIAL
       OR lines( rejected_orders ) <> 1
       OR rejected_orders[ 1 ]-Status <> 'REJECTED'
       OR rejected_orders[ 1 ]-RejectionOrigin <> 'APPROVER'
       OR rejected_orders[ 1 ]-RejectionReason <> reason_value
       OR rejected_orders[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      console->write( 'STOP: reject must set REJECTED, APPROVER and the reason.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_decision_database( order_uuid = reject_uuid
                                expected_status = 'REJECTED'
                                expected_total = 1500
                                expected_origin = 'APPROVER'
                                expected_reason = reason_value
                                expected_number = reject_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: SUBMITTED to REJECTED persisted with origin APPROVER.' ).

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = reject_key ) )
      FAILED DATA(failed_approve_rejected)
      REPORTED DATA(reported_approve_rejected).
    DATA(approve_rejected_blocked) = xsdbool( line_exists(
      failed_approve_rejected-purchaseorder[ %tky = reject_key
        %op-%action-approve = if_abap_behv=>mk-on ] ) ).
    DATA(approve_rejected_message) = abap_false.
    LOOP AT reported_approve_rejected-purchaseorder INTO DATA(decided_line).
      IF decided_line-%msg IS BOUND.
        IF decided_line-%msg->if_message~get_text( ) = decided_text.
          approve_rejected_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = reject_key Supplier = 'SUP999' ) )
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = reject_item_key Quantity = 99 ) )
      FAILED DATA(failed_change_rejected)
      REPORTED DATA(reported_change_rejected).
    DATA(rejected_root_blocked) = xsdbool( line_exists(
      failed_change_rejected-purchaseorder[ %tky = reject_key ] ) ).
    DATA(rejected_item_blocked) = xsdbool( line_exists(
      failed_change_rejected-purchaseorderitem[ %tky = reject_item_key ] ) ).
    DATA(rejected_root_message) = abap_false.
    LOOP AT reported_change_rejected-purchaseorder INTO DATA(rejected_line).
      IF rejected_line-%msg IS BOUND.
        IF rejected_line-%msg->if_message~get_text( ) = root_text.
          rejected_root_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF approve_rejected_blocked = abap_false
       OR approve_rejected_message = abap_false
       OR rejected_root_blocked = abap_false
       OR rejected_item_blocked = abap_false
       OR rejected_root_message = abap_false.
      console->write( 'STOP: a REJECTED order accepted a decision or a change.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: REJECTED rejects approve and every commercial change.' ).

    IF check_decision_database( order_uuid = reject_uuid
                                expected_status = 'REJECTED'
                                expected_total = 1500
                                expected_origin = 'APPROVER'
                                expected_reason = reason_value
                                expected_number = reject_number ) = abap_false.
      RETURN.
    ENDIF.

    " Phase 2.7D-2: a REJECTED order can no longer be deleted.
    success = expect_delete_rejected( order_uuid = reject_uuid
                                      expected_status = 'REJECTED'
                                      expected_items = 1
                                      expected_total = 1500
                                      expected_number = reject_number ).
    IF success = abap_true.
      console->write( 'PASS: REJECTED root DELETE rejected; fixture retained.' ).
    ENDIF.
  ENDMETHOD.

  METHOD test_cancel_lifecycle.
    DATA(open_text) = CONV string( 'Only open orders can be cancelled.' ).
    DATA(submit_text) =
      CONV string( 'Only orders in status DRAFT can be submitted.' ).
    DATA(decided_text) = CONV string( 'Only submitted orders can be decided.' ).
    DATA(root_text) = CONV string( 'Only draft orders can be changed.' ).
    DATA(item_text) = CONV string( 'Only draft order items can change.' ).
    DATA(cba_text) = CONV string( 'Items can be added to draft orders only.' ).
    DATA(remove_text) = CONV string( 'Only draft orders can lose items.' ).
    DATA(reason_value) = CONV zjp_po_h-rejection_reason( 'Cancel guard fixture' ).

    " Case 1: an active order in business Status DRAFT is cancellable. This
    " is a committed active instance, not a RAP technical draft.
    DATA(open_uuid) = create_open_fixture( 'SUP012' ).
    IF open_uuid IS INITIAL.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = open_uuid ) )
        RESULT DATA(open_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = open_uuid ) )
        RESULT DATA(open_items)
      FAILED DATA(failed_open_read).
    IF failed_open_read IS NOT INITIAL OR lines( open_orders ) <> 1
       OR lines( open_items ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: cancel fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(open_key) = open_orders[ 1 ]-%tky.
    DATA(open_item_key) = open_items[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE cancel FROM VALUE #( ( %tky = open_key ) )
      FAILED DATA(failed_cancel)
      REPORTED DATA(reported_cancel).
    console->write( name = 'cancel FAILED - expect empty' data = failed_cancel ).
    console->write( name = 'cancel REPORTED' data = reported_cancel ).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %tky = open_key ) )
        RESULT DATA(cancelled_orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = open_key ) )
        RESULT DATA(cancelled_items)
      FAILED DATA(failed_cancelled_read).
    IF failed_cancel IS NOT INITIAL OR failed_cancelled_read IS NOT INITIAL
       OR lines( cancelled_orders ) <> 1 OR lines( cancelled_items ) <> 1
       OR cancelled_orders[ 1 ]-Status <> 'CANCELLED'
       OR cancelled_orders[ 1 ]-TotalAmount <> 1500
       OR cancelled_items[ 1 ]-TotalAmount <> 1500
       OR cancelled_orders[ 1 ]-PurchaseOrderNumber IS NOT INITIAL
       OR cancelled_orders[ 1 ]-RejectionOrigin IS NOT INITIAL
       OR cancelled_orders[ 1 ]-RejectionReason IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: cancel must set CANCELLED and change nothing else.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_decision_database( order_uuid = open_uuid
                                expected_status = 'CANCELLED'
                                expected_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: DRAFT to CANCELLED persisted with total 1500.' ).
    " This fixture never went through submit, so it never drew a number. The
    " buffer assertion above already required PurchaseOrderNumber to stay
    " initial, and check_decision_database was called without an expected
    " number, which asserts the same thing on the persisted row.
    console->write( 'PASS: a cancelled DRAFT carries no PurchaseOrderNumber.' ).

    " Case 2: CANCELLED is terminal, so every further decision is refused.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE cancel FROM VALUE #( ( %tky = open_key ) )
      FAILED DATA(failed_recancel)
      REPORTED DATA(reported_recancel).
    DATA(recancel_blocked) = xsdbool( line_exists(
      failed_recancel-purchaseorder[ %tky = open_key
        %op-%action-cancel = if_abap_behv=>mk-on ] ) ).
    DATA(recancel_message) = abap_false.
    LOOP AT reported_recancel-purchaseorder INTO DATA(recancel_line).
      IF recancel_line-%msg IS BOUND.
        IF recancel_line-%msg->if_message~get_text( ) = open_text.
          recancel_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = open_key ) )
      FAILED DATA(failed_submit_cancelled)
      REPORTED DATA(reported_submit_cancelled).
    DATA(submit_on_cancelled) = xsdbool( line_exists(
      failed_submit_cancelled-purchaseorder[ %tky = open_key
        %op-%action-submit = if_abap_behv=>mk-on ] ) ).
    DATA(submit_cancelled_msg) = abap_false.
    LOOP AT reported_submit_cancelled-purchaseorder INTO DATA(submit_line).
      IF submit_line-%msg IS BOUND.
        IF submit_line-%msg->if_message~get_text( ) = submit_text.
          submit_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = open_key ) )
      FAILED DATA(failed_approve_cancelled)
      REPORTED DATA(reported_approve_cancelled).
    DATA(approve_on_cancelled) = xsdbool( line_exists(
      failed_approve_cancelled-purchaseorder[ %tky = open_key
        %op-%action-approve = if_abap_behv=>mk-on ] ) ).
    DATA(approve_cancelled_msg) = abap_false.
    LOOP AT reported_approve_cancelled-purchaseorder INTO DATA(approve_line).
      IF approve_line-%msg IS BOUND.
        IF approve_line-%msg->if_message~get_text( ) = decided_text.
          approve_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE reject FROM VALUE #( (
          %tky = open_key
          %param-RejectionReason = 'Late objection' ) )
      FAILED DATA(failed_reject_cancelled)
      REPORTED DATA(reported_reject_cancelled).
    DATA(reject_on_cancelled) = xsdbool( line_exists(
      failed_reject_cancelled-purchaseorder[ %tky = open_key
        %op-%action-reject = if_abap_behv=>mk-on ] ) ).
    DATA(reject_cancelled_msg) = abap_false.
    LOOP AT reported_reject_cancelled-purchaseorder INTO DATA(reject_line).
      IF reject_line-%msg IS BOUND.
        IF reject_line-%msg->if_message~get_text( ) = decided_text.
          reject_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF recancel_blocked = abap_false OR recancel_message = abap_false
       OR submit_on_cancelled = abap_false
       OR submit_cancelled_msg = abap_false
       OR approve_on_cancelled = abap_false
       OR approve_cancelled_msg = abap_false
       OR reject_on_cancelled = abap_false
       OR reject_cancelled_msg = abap_false.
      console->write( 'STOP: a CANCELLED order accepted a decision.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: CANCELLED refuses re-cancel, submit, approve and reject.' ).

    " Case 3: the Phase 2.7C invariant must already cover CANCELLED. No
    " CANCELLED-specific branch was added to any precheck or to removeItem.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        UPDATE FIELDS ( Supplier )
        WITH VALUE #( ( %tky = open_key Supplier = 'SUP999' ) )
      FAILED DATA(failed_root_cancelled)
      REPORTED DATA(reported_root_cancelled).
    DATA(root_on_cancelled) = xsdbool( line_exists(
      failed_root_cancelled-purchaseorder[ %tky = open_key ] ) ).
    DATA(root_cancelled_msg) = abap_false.
    LOOP AT reported_root_cancelled-purchaseorder INTO DATA(root_line).
      IF root_line-%msg IS BOUND.
        IF root_line-%msg->if_message~get_text( ) = root_text.
          root_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrderItem
        UPDATE FIELDS ( Quantity )
        WITH VALUE #( ( %tky = open_item_key Quantity = 99 ) )
      FAILED DATA(failed_item_cancelled)
      REPORTED DATA(reported_item_cancelled).
    DATA(item_on_cancelled) = xsdbool( line_exists(
      failed_item_cancelled-purchaseorderitem[ %tky = open_item_key ] ) ).
    DATA(item_cancelled_msg) = abap_false.
    LOOP AT reported_item_cancelled-purchaseorderitem INTO DATA(item_line).
      IF item_line-%msg IS BOUND.
        IF item_line-%msg->if_message~get_text( ) = item_text.
          item_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %tky = open_key
          %target = VALUE #( ( %cid = 'CANCELLED_EXTRA' ItemNumber = '00090'
                               Material = 'MAT009' Quantity = 1
                               UnitOfMeasure = 'EA' NetPrice = '10.00'
                               Currency = 'EUR' ) ) ) )
      FAILED DATA(failed_cba_cancelled)
      REPORTED DATA(reported_cba_cancelled).
    DATA(cba_on_cancelled) = xsdbool( line_exists(
      failed_cba_cancelled-purchaseorder[ %tky = open_key ] ) ).
    DATA(cba_cancelled_msg) = abap_false.
    LOOP AT reported_cba_cancelled-purchaseorder INTO DATA(cba_line).
      IF cba_line-%msg IS BOUND.
        IF cba_line-%msg->if_message~get_text( ) = cba_text.
          cba_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE removeItem FROM VALUE #( (
          %tky = open_key
          %param-PurchaseOrderItemUUID =
            open_item_key-PurchaseOrderItemUUID ) )
      FAILED DATA(failed_remove_cancelled)
      REPORTED DATA(reported_remove_cancelled).
    DATA(remove_on_cancelled) = xsdbool( line_exists(
      failed_remove_cancelled-purchaseorder[ %tky = open_key
        %op-%action-removeItem = if_abap_behv=>mk-on ] ) ).
    DATA(remove_cancelled_msg) = abap_false.
    LOOP AT reported_remove_cancelled-purchaseorder INTO DATA(remove_line).
      IF remove_line-%msg IS BOUND.
        IF remove_line-%msg->if_message~get_text( ) = remove_text.
          remove_cancelled_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF root_on_cancelled = abap_false OR root_cancelled_msg = abap_false
       OR item_on_cancelled = abap_false OR item_cancelled_msg = abap_false
       OR cba_on_cancelled = abap_false OR cba_cancelled_msg = abap_false
       OR remove_on_cancelled = abap_false
       OR remove_cancelled_msg = abap_false.
      console->write( 'STOP: a CANCELLED order accepted a commercial change.' ).
      RETURN.
    ENDIF.
    console->write( 'PASS: CANCELLED rejects every commercial change.' ).

    IF check_decision_database( order_uuid = open_uuid
                                expected_status = 'CANCELLED'
                                expected_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.
    " Phase 2.7D-2: a CANCELLED order can no longer be deleted.
    IF expect_delete_rejected( order_uuid = open_uuid
                               expected_status = 'CANCELLED'
                               expected_items = 1
                               expected_total = 1500 ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: CANCELLED root DELETE rejected; fixture retained.' ).

    " Case 4: SUBMITTED to CANCELLED.
    DATA(submitted_uuid) = create_decision_fixture( 'SUP013' ).
    IF submitted_uuid IS INITIAL.
      RETURN.
    ENDIF.
    " The fixture is already SUBMITTED, so submit has drawn its number.
    " Every later state must show exactly this captured value.
    DATA(submitted_number) = read_order_number( submitted_uuid ).
    console->write( name = 'Fixture SUP013 PO number' data = submitted_number ).
    IF check_number_format( submitted_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = submitted_uuid ) )
        RESULT DATA(submitted_orders)
      FAILED DATA(failed_submitted_read).
    IF failed_submitted_read IS NOT INITIAL OR lines( submitted_orders ) <> 1
       OR submitted_orders[ 1 ]-Status <> 'SUBMITTED'.
      ROLLBACK ENTITIES.
      console->write( 'STOP: the cancel fixture must start in SUBMITTED.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE cancel FROM VALUE #( ( %tky = submitted_orders[ 1 ]-%tky ) )
      FAILED DATA(failed_submitted_cancel)
      REPORTED DATA(reported_submitted_cancel).
    console->write( name = 'SUBMITTED cancel FAILED - expect empty'
                    data = failed_submitted_cancel ).
    IF failed_submitted_cancel IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: a SUBMITTED order must accept cancel.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_decision_database( order_uuid = submitted_uuid
                                expected_status = 'CANCELLED'
                                expected_total = 1500
                                expected_number = submitted_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: SUBMITTED to CANCELLED persisted with total 1500.' ).
    IF expect_delete_rejected( order_uuid = submitted_uuid
                               expected_status = 'CANCELLED'
                               expected_items = 1
                               expected_total = 1500
                               expected_number = submitted_number ) = abap_false.
      RETURN.
    ENDIF.

    " Case 5: APPROVED to CANCELLED. No delivery-request guard exists yet:
    " Phase 5.2a starts a new order at IntegrationStatus = NOT_REQUESTED,
    " which is the value meaning no delivery was requested, and nothing
    " advances it or sets DeliveryId.
    DATA(approved_uuid) = create_decision_fixture( 'SUP014' ).
    IF approved_uuid IS INITIAL.
      RETURN.
    ENDIF.
    " The fixture is already SUBMITTED, so submit has drawn its number.
    " Every later state must show exactly this captured value.
    DATA(approved_number) = read_order_number( approved_uuid ).
    console->write( name = 'Fixture SUP014 PO number' data = approved_number ).
    IF check_number_format( approved_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = approved_uuid ) )
        RESULT DATA(to_approve_orders)
      FAILED DATA(failed_to_approve_read).
    IF failed_to_approve_read IS NOT INITIAL OR lines( to_approve_orders ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: the approve-then-cancel fixture failed to read.' ).
      RETURN.
    ENDIF.
    DATA(approved_key) = to_approve_orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE approve FROM VALUE #( ( %tky = approved_key ) )
      FAILED DATA(failed_pre_approve)
      REPORTED DATA(reported_pre_approve).
    IF failed_pre_approve IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: approve failed on the cancel fixture.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE cancel FROM VALUE #( ( %tky = approved_key ) )
      FAILED DATA(failed_approved_cancel)
      REPORTED DATA(reported_approved_cancel).
    console->write( name = 'APPROVED cancel FAILED - expect empty'
                    data = failed_approved_cancel ).
    IF failed_approved_cancel IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: an APPROVED order must accept cancel.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    IF check_decision_database( order_uuid = approved_uuid
                                expected_status = 'CANCELLED'
                                expected_total = 1500
                                expected_number = approved_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: APPROVED to CANCELLED persisted with total 1500.' ).
    IF expect_delete_rejected( order_uuid = approved_uuid
                               expected_status = 'CANCELLED'
                               expected_items = 1
                               expected_total = 1500
                               expected_number = approved_number ) = abap_false.
      RETURN.
    ENDIF.

    " Case 6: REJECTED is terminal and is not a cancellable source.
    DATA(rejected_uuid) = create_decision_fixture( 'SUP015' ).
    IF rejected_uuid IS INITIAL.
      RETURN.
    ENDIF.
    " The fixture is already SUBMITTED, so submit has drawn its number.
    " Every later state must show exactly this captured value.
    DATA(rejected_number) = read_order_number( rejected_uuid ).
    console->write( name = 'Fixture SUP015 PO number' data = rejected_number ).
    IF check_number_format( rejected_number ) = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit did not allocate PO plus eight digits.' ).
      RETURN.
    ENDIF.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = rejected_uuid ) )
        RESULT DATA(to_reject_orders)
      FAILED DATA(failed_to_reject_read).
    IF failed_to_reject_read IS NOT INITIAL OR lines( to_reject_orders ) <> 1.
      ROLLBACK ENTITIES.
      console->write( 'STOP: the reject-then-cancel fixture failed to read.' ).
      RETURN.
    ENDIF.
    DATA(rejected_key) = to_reject_orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE reject FROM VALUE #( (
          %tky = rejected_key
          %param-RejectionReason = reason_value ) )
      FAILED DATA(failed_pre_reject)
      REPORTED DATA(reported_pre_reject).
    IF failed_pre_reject IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: reject failed on the cancel fixture.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE cancel FROM VALUE #( ( %tky = rejected_key ) )
      FAILED DATA(failed_rejected_cancel)
      REPORTED DATA(reported_rejected_cancel).
    console->write( name = 'REJECTED cancel FAILED - expect rejection'
                    data = failed_rejected_cancel ).
    console->write( name = 'REJECTED cancel REPORTED'
                    data = reported_rejected_cancel ).
    DATA(rejected_cancel_blocked) = xsdbool( line_exists(
      failed_rejected_cancel-purchaseorder[ %tky = rejected_key
        %op-%action-cancel = if_abap_behv=>mk-on ] ) ).
    DATA(rejected_cancel_msg) = abap_false.
    LOOP AT reported_rejected_cancel-purchaseorder INTO DATA(rejected_line).
      IF rejected_line-%msg IS BOUND.
        IF rejected_line-%msg->if_message~get_text( ) = open_text.
          rejected_cancel_msg = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF rejected_cancel_blocked = abap_false
       OR rejected_cancel_msg = abap_false.
      console->write( 'STOP: a REJECTED order accepted cancel.' ).
      RETURN.
    ENDIF.
    IF check_decision_database( order_uuid = rejected_uuid
                                expected_status = 'REJECTED'
                                expected_total = 1500
                                expected_origin = 'APPROVER'
                                expected_reason = reason_value
                                expected_number = rejected_number ) = abap_false.
      RETURN.
    ENDIF.
    console->write( 'PASS: REJECTED refuses cancel and stays REJECTED.' ).

    success = expect_delete_rejected( order_uuid = rejected_uuid
                                      expected_status = 'REJECTED'
                                      expected_items = 1
                                      expected_total = 1500
                                      expected_number = rejected_number ).
  ENDMETHOD.

  METHOD create_open_fixture.
    " One active root with one item, 2 x 750 = 1500, committed and left in
    " business Status DRAFT. Unlike create_decision_fixture it does not submit.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'OPEN_ROOT'
                        Supplier = supplier
                        CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'OPEN_ROOT'
          %target = VALUE #( ( %cid = 'OPEN_ITEM' ItemNumber = '00010'
                               Material = 'MAT001' Quantity = 2
                               UnitOfMeasure = 'EA' NetPrice = '750.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_open)
      FAILED DATA(failed_open_create)
      REPORTED DATA(reported_open_create).
    console->write( name = 'Open fixture FAILED' data = failed_open_create ).
    console->write( name = 'Open fixture REPORTED' data = reported_open_create ).
    IF failed_open_create IS NOT INITIAL
       OR NOT line_exists( mapped_open-purchaseorder[ %cid = 'OPEN_ROOT' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: open fixture creation failed.' ).
      RETURN.
    ENDIF.
    DATA(fixture_uuid) = mapped_open-purchaseorder[
      %cid = 'OPEN_ROOT' ]-PurchaseOrderUUID.
    console->write( name = 'Open fixture UUID - retain for diagnosis'
                    data = fixture_uuid ).
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = fixture_uuid ) )
        RESULT DATA(fixture_orders)
      FAILED DATA(failed_fixture_read).
    IF failed_fixture_read IS NOT INITIAL OR lines( fixture_orders ) <> 1
       OR fixture_orders[ 1 ]-Status <> 'DRAFT'
       OR fixture_orders[ 1 ]-TotalAmount <> 1500.
      ROLLBACK ENTITIES.
      console->write( 'STOP: open fixture must start in DRAFT with total 1500.' ).
      RETURN.
    ENDIF.
    APPEND fixture_uuid TO lifecycle_uuids.
    order_uuid = fixture_uuid.
  ENDMETHOD.

  METHOD create_decision_fixture.
    " One active root with one item, 2 x 750 = 1500, submitted and committed.
    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        CREATE FIELDS ( Supplier CompanyCode Currency )
        WITH VALUE #( ( %cid = 'DECISION_ROOT'
                        Supplier = supplier
                        CompanyCode = '1000'
                        Currency = 'EUR' ) )
        CREATE BY \_Items
        FIELDS ( ItemNumber Material Quantity UnitOfMeasure NetPrice Currency )
        WITH VALUE #( ( %cid_ref = 'DECISION_ROOT'
          %target = VALUE #( ( %cid = 'DECISION_ITEM' ItemNumber = '00010'
                               Material = 'MAT001' Quantity = 2
                               UnitOfMeasure = 'EA' NetPrice = '750.00'
                               Currency = 'EUR' ) ) ) )
      MAPPED DATA(mapped_decision)
      FAILED DATA(failed_decision_create)
      REPORTED DATA(reported_decision_create).
    console->write( name = 'Decision fixture FAILED' data = failed_decision_create ).
    console->write( name = 'Decision fixture REPORTED'
                    data = reported_decision_create ).
    IF failed_decision_create IS NOT INITIAL
       OR NOT line_exists( mapped_decision-purchaseorder[
            %cid = 'DECISION_ROOT' ] ).
      ROLLBACK ENTITIES.
      console->write( 'STOP: decision fixture creation failed.' ).
      RETURN.
    ENDIF.
    DATA(fixture_uuid) = mapped_decision-purchaseorder[
      %cid = 'DECISION_ROOT' ]-PurchaseOrderUUID.
    console->write( name = 'Decision fixture UUID - retain for diagnosis'
                    data = fixture_uuid ).
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = fixture_uuid ) )
        RESULT DATA(fixture_orders)
      FAILED DATA(failed_fixture_read).
    IF failed_fixture_read IS NOT INITIAL OR lines( fixture_orders ) <> 1
       OR fixture_orders[ 1 ]-Status <> 'DRAFT'.
      ROLLBACK ENTITIES.
      console->write( 'STOP: decision fixture must start in Status DRAFT.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE submit FROM VALUE #( ( %tky = fixture_orders[ 1 ]-%tky ) )
      FAILED DATA(failed_fixture_submit)
      REPORTED DATA(reported_fixture_submit).
    IF failed_fixture_submit IS NOT INITIAL.
      ROLLBACK ENTITIES.
      console->write( 'STOP: submit failed on the decision fixture.' ).
      RETURN.
    ENDIF.
    IF save_changes( ) = abap_false.
      RETURN.
    ENDIF.
    APPEND fixture_uuid TO lifecycle_uuids.
    order_uuid = fixture_uuid.
  ENDMETHOD.

  METHOD expect_delete_rejected.
    " Phase 2.7D-2: a fixture that has reached a terminal business state is
    " deliberate residue. It can no longer be removed through managed RAP,
    " direct SQL cleanup is forbidden, and a test-only deletion backdoor in
    " production behavior is not acceptable. The UUID is printed again so the
    " surviving row can be identified by hand later.
    DATA(delete_text) = CONV string( 'Only draft orders can be deleted.' ).
    console->write( name = 'Terminal residue UUID - retain for manual cleanup'
                    data = order_uuid ).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( PurchaseOrderUUID = order_uuid ) )
        RESULT DATA(residue_orders)
      FAILED DATA(failed_residue_read).
    IF failed_residue_read IS NOT INITIAL OR lines( residue_orders ) <> 1
       OR residue_orders[ 1 ]-Status <> expected_status.
      ROLLBACK ENTITIES.
      console->write( 'STOP: the terminal fixture could not be read.' ).
      RETURN.
    ENDIF.
    DATA(residue_key) = residue_orders[ 1 ]-%tky.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        DELETE FROM VALUE #( ( %tky = residue_key ) )
      FAILED DATA(failed_residue_delete)
      REPORTED DATA(reported_residue_delete).
    console->write( name = 'Terminal DELETE FAILED - expect rejection'
                    data = failed_residue_delete ).
    console->write( name = 'Terminal DELETE REPORTED'
                    data = reported_residue_delete ).
    DATA(delete_blocked) = xsdbool( line_exists(
      failed_residue_delete-purchaseorder[ %tky = residue_key ] ) ).
    DATA(delete_message) = abap_false.
    LOOP AT reported_residue_delete-purchaseorder INTO DATA(residue_line).
      IF residue_line-%msg IS BOUND.
        IF residue_line-%msg->if_message~get_text( ) = delete_text.
          delete_message = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    ROLLBACK ENTITIES.

    IF delete_blocked = abap_false OR delete_message = abap_false.
      console->write( 'STOP: a terminal order accepted root DELETE.' ).
      RETURN.
    ENDIF.

    success = check_submit_database( order_uuid = order_uuid
                                     expected_headers = 1
                                     expected_items = expected_items
                                     expected_status = expected_status
                                     expected_header_total = expected_total
                                     expected_number = expected_number ).
    IF success = abap_true.
      console->write( 'PASS: root DELETE rejected; the terminal order survives.' ).
    ENDIF.
  ENDMETHOD.

  METHOD print_lifecycle_summary.
    " Diagnostic output only. No assertion depends on this block and it
    " changes no lifecycle or cleanup behavior.
    "
    " Selection is by the exact UUIDs captured during THIS execution, never
    " by Status or Supplier: from Phase 2.7D-2 onwards terminal fixtures are
    " deliberate residue, so earlier runs have left APPROVED, REJECTED and
    " CANCELLED rows in ZJP_PO_H that a status query would wrongly report as
    " produced here. Read-only SELECT, one row per captured key.
    TYPES: BEGIN OF summary_line,
             purchase_order_uuid   TYPE zjp_po_h-purchase_order_uuid,
             supplier              TYPE zjp_po_h-supplier,
             status                TYPE zjp_po_h-status,
             total_amount          TYPE zjp_po_h-total_amount,
             purchase_order_number TYPE zjp_po_h-purchase_order_number,
             order_revision        TYPE zjp_po_h-order_revision,
             integration_status    TYPE zjp_po_h-integration_status,
             rejection_origin      TYPE zjp_po_h-rejection_origin,
             rejection_reason      TYPE zjp_po_h-rejection_reason,
           END OF summary_line.
    DATA summary_row  TYPE summary_line.
    DATA summary_rows TYPE STANDARD TABLE OF summary_line WITH EMPTY KEY.

    IF lifecycle_uuids IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lifecycle_uuids INTO DATA(summary_uuid).
      CLEAR summary_row.
      SELECT SINGLE purchase_order_uuid, supplier, status, total_amount,
                    purchase_order_number, order_revision, integration_status,
                    rejection_origin, rejection_reason
        FROM zjp_po_h
        WHERE purchase_order_uuid = @summary_uuid
        INTO @summary_row.
      IF sy-subrc <> 0.
        CLEAR summary_row.
        summary_row-purchase_order_uuid = summary_uuid.
        summary_row-status = 'NOT FOUND'.
      ENDIF.
      APPEND summary_row TO summary_rows.
    ENDLOOP.

    console->write( '=== FINAL LIFECYCLE SUMMARY ===' ).
    console->write( name = 'Terminal fixtures created by this run'
                    data = summary_rows ).

    LOOP AT summary_rows INTO DATA(printed_row).
      DATA(number_text) = COND string(
        WHEN printed_row-purchase_order_number IS INITIAL THEN '-'
        ELSE |{ printed_row-purchase_order_number }| ).
      DATA(origin_text) = COND string(
        WHEN printed_row-rejection_origin IS INITIAL THEN '-'
        ELSE |{ printed_row-rejection_origin }| ).
      DATA(reason_text) = COND string(
        WHEN printed_row-rejection_reason IS INITIAL THEN '-'
        ELSE |{ printed_row-rejection_reason }| ).
      " A blank integration_status prints as '-' and is expected on rows
      " persisted before Phase 5.2a. Those rows are deliberately not
      " back-filled, and nothing here asserts on them.
      DATA(integration_text) = COND string(
        WHEN printed_row-integration_status IS INITIAL THEN '-'
        ELSE |{ printed_row-integration_status }| ).
      console->write( |{ printed_row-supplier WIDTH = 10 }| &&
                      |{ printed_row-status WIDTH = 12 }| &&
                      |{ printed_row-total_amount WIDTH = 12 }| &&
                      |{ number_text WIDTH = 22 }| &&
                      |{ printed_row-order_revision WIDTH = 4 }| &&
                      |{ integration_text WIDTH = 16 }| &&
                      |{ origin_text WIDTH = 10 }| &&
                      |{ reason_text }| ).
    ENDLOOP.
    console->write( '=== END LIFECYCLE SUMMARY ===' ).
  ENDMETHOD.

  METHOD check_decision_database.
    SELECT purchase_order_uuid, status, total_amount, rejection_origin,
           rejection_reason, purchase_order_number
      FROM zjp_po_h
      WHERE purchase_order_uuid = @order_uuid
      INTO TABLE @DATA(headers_db).
    console->write( name = 'ZJP_PO_H - decision test UUID' data = headers_db ).

    success = xsdbool( lines( headers_db ) = 1 ).
    IF success = abap_true.
      success = xsdbool(
        headers_db[ 1 ]-status = expected_status
        AND headers_db[ 1 ]-total_amount = expected_total
        AND headers_db[ 1 ]-rejection_origin = expected_origin
        AND headers_db[ 1 ]-rejection_reason = expected_reason
        AND headers_db[ 1 ]-purchase_order_number = expected_number ).
    ENDIF.

    IF success = abap_false.
      ROLLBACK ENTITIES.
      console->write( 'STOP: decision database verification failed.' ).
    ELSE.
      console->write( 'PASS: decision database checkpoint values are correct.' ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
