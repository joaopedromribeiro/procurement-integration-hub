# Phase 2 — managed RAP runtime test with EML

This test was executed successfully in the learner’s SAP S/4HANA study system. The [supplied console evidence](phase-2-3-eml-runtime-evidence.md) verifies the scoped CRUD/composition flow below. The assistant reviewed that output but did not independently run SAP. Phase 1 and Phase 2.1–2.3 are complete; the [status-initialization plan](phase-2-4a-status-initialization-plan.md) is next.

## Why this comes next

Compilation checks the model and signatures. EML now lets us exercise the BO's actual transactional behavior before adding business rules or a service. A small ABAP consumer makes requests to RAP; it does not implement persistence. If a basic create or composition fails, the cause can be investigated without draft, actions or HTTP in the picture.

We use the base BO ZJP_I_PurchaseOrder directly. No projection BDEF, service binding or UI is required. The consumer deliberately omits IN LOCAL MODE: it must respect the BO's public field controls and authorization behavior. The internal read in the authorization handler is a different context.

## Compatibility correction already applied

The target compiler reported that AUTHORIZATION_RESULT and REQUESTED_AUTHORIZATIONS do not have component `%ASSOC-_ITEMS`. The local handler source now handles only `%update` and `%delete`, matching the learner's working implementation. Keep `lhc_PurchaseOrder` local inside the behavior pool. We did not change the existing global pool name or BDEF reference.

Generated RAP structures depend on the release and behavior declaration. ADT autocomplete and the real compiler determine which components exist. Do not reconstruct an unsupported component with casts or reintroduce it from a generic example. The BDEF still declares `association _Items { create; }`; removal of an authorization-result component does not remove composition creation.

Successful deep creation in this test does not establish a complete authorization policy. SAP documents that a combined create and create-by-association through %cid_ref does not execute instance authorization in the same way as a request for an existing instance. This test therefore is not evidence that all item-creation authorization paths are secured. See [SAP EML behavior](https://help.sap.com/docs/abap-cloud/abap-rap/entity-manipulation-language-eml?version=s4_hana_cloud_pce).

## Scope and exact ADT object

Create a normal **ABAP Class** named **ZJP_CL_PO_EML_TEST**, with interface **IF_OO_ADT_CLASSRUN**, in the existing project package/transport using ABAP for Cloud Development.

This is a separate global console class, not a local handler and not another behavior pool. Its complete source belongs in the class's main editor. The [source file](../classes/zjp_cl_po_eml_test.clas.abap) is hand-maintained ADT source, not a complete serialized import.

The program creates synthetic data in ZJP_PO_H and ZJP_PO_I and deletes only the order it just created. No execution against SAP has been performed by the assistant. It contains no direct database writes.

## Understand the sequence before execution

```text
1. MODIFY ENTITIES: create header + one composed item
2. READ ENTITIES: see both in RAP's transactional buffer
3. SELECT: verify neither row is saved yet
4. COMMIT ENTITIES: save header and item
5. SELECT: verify one header + one item, supplier SUP001
6. MODIFY ENTITIES: change supplier to SUP002
7. COMMIT ENTITIES: save the change
8. READ ENTITIES + SELECT: verify SUP002
9. MODIFY ENTITIES: delete the newly created root
10. COMMIT ENTITIES: save deletion
11. SELECT: verify root and its composed item are both gone
```

The linear main method exposes the teaching sequence. Two small helpers keep repetition separate: save_changes contains the actual COMMIT ENTITIES and save-response checks; check_database performs read-only, UUID-filtered verification. This is an integration smoke test against a real BO, not an isolated ABAP Unit test.

### Create and connect the item

The root CREATE supplies only writable fields: supplier and organizational/currency values. `CREATE BY \_Items` contains the item within `%target`. Its `%cid_ref` points to the new root's `%cid` in the same MODIFY request. We do not supply either technical UUID or the item's parent UUID: managed numbering and create-by-association establish them.

The sample has one item (00010, quantity 2, net price 750 EUR). To try more items in a later rerun, add another row inside %target with a different %cid and item number, and adjust the expected item counts. Do not change the one-item baseline on the first run.

### Response and identity vocabulary

| Component | Meaning here |
| --- | --- |
| %cid | Temporary caller-supplied content ID within the modify request, such as PO_1 or ITEM_1; not a database key or PO number |
| %cid_ref | Reference from the composition-create request to the root's PO_1 content ID |
| %target | Nested table of items to create for that parent |
| MAPPED | Correlates content IDs with generated identities; this is how we capture the new PurchaseOrderUUID |
| %tky | RAP transactional key used for later update/delete; this non-draft BO's root identity is its UUID |
| FAILED | Identifies failed operations/instances and failure causes; inspect both root and child entries |
| REPORTED | Carries messages and context, including warnings or information; nonempty does not automatically mean failure |
| FIELDS (...) | Selects which fields the request writes; for example updating Supplier does not overwrite Currency |

See [SAP EML response operands](https://learning.sap.com/courses/building-transactional-apps-with-the-abap-restful-application-programming-model/using-the-entity-manipulation-language-eml-to-access-business-objects).

The class prints every request's FAILED and REPORTED structures, plus create MAPPED. Open their nested entries in the console/debugger. In a reported row, a bound %msg reference can supply readable text through get_text(); the raw structures also preserve entity/key and field context.

### Buffer and commit boundaries

A successful MODIFY request changes RAP's transaction buffer. It is not proof of a durable database save. READ ENTITIES can see the newly created header and item before they are committed; a read-only SELECT from our persistence tables at that point should find zero matching rows.

This standalone consumer explicitly calls COMMIT ENTITIES after create, after update and after delete. Each call triggers RAP's save sequence for the current transaction. The helper captures sy-subrc immediately and examines the save-phase FAILED/REPORTED responses, which are separate from modify-phase responses. A successful create MAPPED result alone does not mean the save succeeded. See [SAP transaction model](https://help.sap.com/docs/ABAP_PLATFORM_NEW/fc4c71aa50014fd1b43721701471913d/ccda1094b0f845e28b88f9f50a68dfc4.html).

Read-only operations need no commit. COMMIT ENTITIES belongs in this consumer; do not move it into the behavior handler. On a detected failure, ROLLBACK ENTITIES discards uncommitted work and the program stops. It cannot reverse an earlier successful commit. Retain the printed UUID if the test stops after the first commit: that test order may still exist, and rerunning the class creates a new UUID. Resolve cleanup for the retained UUID through EML, never by a broad table deletion.

### Framework-managed versus requested explicitly

| We explicitly request or inspect | RAP supplies |
| --- | --- |
| Header creation and composition item creation | UUID assignment, parent link, transactional buffering and managed persistence |
| Reads through the BO | Root/item access through the modeled entities and association |
| Change Supplier only | Field controls, declared authorization/locking and update persistence |
| Delete the root created by this run | Managed deletion of the root and composition children |
| Commit or roll back the current transaction | Save sequence and buffer lifecycle |
| SELECT only our UUID to check actual rows | Database state resulting from RAP saving |

Totals remain zero even though 2 × 750 = 1500; calculation is not implemented. Status and PurchaseOrderNumber remain initial because defaulting/numbering is not implemented. Framework-generated UUIDs and supported annotated audit timestamps should be populated. Initial business fields are expected at this checkpoint.

The study handler allows the supported requested %update/%delete flags. This test exercises normal consumer access, but is not a negative authorization test or a stale-ETag HTTP test.

## Complete source

Read the following code before running it. For ADT, use the source file linked above; both listings are synchronized.

```abap
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
```

## Activate and execute in ADT

1. Ensure ZJP_I_PURCHASEORDER BDEF and the referenced behavior pool are active under the accepted compatibility baseline.
2. Create ABAP Class ZJP_CL_PO_EML_TEST and place the complete source in its main editor. Save, syntax-check and activate it.
3. Before execution, review the UUID-scoped deletion and the three save boundaries. If you want manual database previews, set ADT breakpoints at the two marked lines before UPDATE and DELETE and use the debugger.
4. Run As → ABAP Application (Console), normally F9. The console shows the generated UUID, EML responses, database snapshots and checkpoint labels.
5. Read the result and stop. Do not add another feature until the learner reports the outcome.

If a console interface or EML form is rejected, record the exact diagnostic and inspect the system-generated type/signature. Do not remove FAILED/REPORTED handling or switch to direct SQL writes as a workaround.

## Expected results and database verification

| Checkpoint | ZJP_PO_H for printed UUID | ZJP_PO_I for printed parent UUID | Key observation |
| --- | --- | --- | --- |
| Before first commit | 0 rows | 0 rows | EML already returned one header and one item from the buffer |
| After create commit | 1 row, Supplier SUP001 | 1 row, ItemNumber 00010 | Distinct generated technical UUIDs, item references its parent |
| After update commit | 1 row, Supplier SUP002 | Same 1 item | UPDATE FIELDS changes only Supplier among business inputs |
| After delete commit | 0 rows | 0 rows | Root deletion also removes its composition child |

The code checks row counts, supplier values, item identity and parent reference. It prints PASS only after all these checks succeed. It prints audit, amount and status fields for inspection; it does not automatically assert every administrative field or business value.

For manual verification, pause at the marked breakpoint after create or update, open ZJP_PO_H and ZJP_PO_I in ADT Data Preview, and filter both by purchase_order_uuid using the printed UUID or the debugger's value in the format accepted by the filter. Refresh after each commit. The console's filtered SELECT snapshots are an alternative if UUID filtering is inconvenient. A normal uninterrupted run removes its data before you open Data Preview, so zero final rows is expected.

Actual EML test result: **PASS, verified by learner-supplied SAP console output.** All three commits returned sy-subrc = 0; the final database checks contained no rows for the test UUID. FAILED/REPORTED were empty. Expected blank Status and zero totals belong to this pre-determination baseline. No draft, validations, determinations, actions, OData/Fiori, CAP or Integration Suite was implemented by this test.

The learner confirmed this EML checkpoint passed. Continue only to the status-initialization plan; keep the successful test source as the baseline until the next implementation step.
