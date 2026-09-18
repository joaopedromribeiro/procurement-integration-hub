" Phase 5.2d - console runtime harness for the outbound builder and CAP mapper.
"
" A dedicated test object by explicit decision, recorded in the Phase 5.1 guide
" section 10.2. ZJP_CL_PO_EML_TEST stays the RAP lifecycle regression suite -
" Phase 5.2d changes no RAP behavior - and ZJP_CL_PO_DISPATCH_TEST stays reserved
" for the Phase 5.2g coordinator.
"
" Two kinds of evidence, deliberately kept apart:
"
"   The BUILDER is tested against a REAL active PurchaseOrder, because the thing
"   worth proving is that it copies what SAP actually holds. The expected values
"   are read independently with a read-only SELECT, so two different paths -
"   EML inside the builder, SQL inside the test - have to agree. It creates no
"   fixture and commits nothing.
"
"   The MAPPER is tested against a DETERMINISTIC in-memory snapshot, because the
"   thing worth proving is byte-exact wire output, which a live order with
"   generated identities can never give. Its expected body is the golden payload
"   the P10 runtime probe produced, which is in turn the shape the deployed CAP
"   IntegrationService has accepted.
"
" No network. No COMMIT, no ROLLBACK, no EML MODIFY, no SQL write.
CLASS zjp_cl_builder_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " The golden payload. Byte-for-byte what the P10 probe produced on this
    " system, and semantically the fixture in the CAP test suite that the
    " deployed IntegrationService accepted with 201.
    "
    " A method rather than a CONSTANTS VALUE: ADT rejects a text literal longer
    " than 255 characters, and a constant's VALUE must be a single literal, so it
    " cannot be split with &&. Concatenating in a method is the way to hold a
    " payload-sized fixture. The split points are chosen at JSON boundaries so
    " each piece stays readable.
    METHODS golden_body
      RETURNING VALUE(body) TYPE string.

    METHODS golden_snapshot
      RETURNING VALUE(delivery) TYPE zjp_cl_order_delivery_builder=>ty_delivery.

    METHODS count_rows
      RETURNING VALUE(total) TYPE i.

    METHODS test_builder_reads_active
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_mapper_golden_payload
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_mapper_determinism
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_mapper_rejects_unit
      RETURNING VALUE(success) TYPE abap_bool.

    " Phase 5.2f. The snapshot serializer shares this harness rather than taking
    " its own, because it consumes the same ty_delivery the builder produces and
    " the same deterministic fixture the mapper is tested against - two shapes
    " from one DTO, compared side by side.
    METHODS source_snapshot_body
      RETURNING VALUE(body) TYPE string.

    METHODS test_snapshot_serializer
      RETURNING VALUE(success) TYPE abap_bool.

ENDCLASS.


CLASS zjp_cl_builder_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write( '=== Phase 5.2d - outbound builder and CAP mapper ===' ).
    out->write( 'Pure transformation. No network, no write, no commit.' ).

    IF test_builder_reads_active( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_mapper_golden_payload( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_mapper_determinism( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_mapper_rejects_unit( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: Phase 5.2d outbound builder and CAP mapper verified.' ).

    IF test_snapshot_serializer( ) = abap_false.
      RETURN.
    ENDIF.

    out->write( 'PASS: Phase 5.2f source delivery snapshot serializer verified.' ).

  ENDMETHOD.


  METHOD golden_body.
    body = '{"schemaVersion":"1.0","deliveryId":"00000000-0000-0000-0000-000000000001",'
        && '"source":{"system":"PIH_ABAP_DEV","orderId":"00000000-0000-0000-0000-000000000002",'
        && '"orderNumber":"PO00002001","revision":1},'
        && '"supplierCode":"SUP001","amount":{"currency":"EUR","value":"1500.00"},"lines":[{'
        && '"sourceItemId":"00000000-0000-0000-0000-000000000003","lineNumber":10,'
        && '"product":{"code":"MAT001","description":"Laptop"},'
        && '"orderedQuantity":{"value":"2.000","unit":"PCE"},'
        && '"unitPrice":{"currency":"EUR","value":"750.0000"},'
        && '"lineAmount":"1500.00"}]}'.
  ENDMETHOD.


  METHOD golden_snapshot.

    " Fixed identities so the output is byte-comparable. These are the same
    " placeholder UUIDs the P10 probe used.
    DATA delivery_uuid TYPE sysuuid_x16 VALUE '00000000000000000000000000000001'.
    DATA order_uuid    TYPE sysuuid_x16 VALUE '00000000000000000000000000000002'.
    DATA item_uuid     TYPE sysuuid_x16 VALUE '00000000000000000000000000000003'.

    delivery = VALUE #(
      schema_version        = zjp_cl_order_delivery_builder=>schema_version
      delivery_uuid         = delivery_uuid
      source_system         = 'PIH_ABAP_DEV'
      purchase_order_uuid   = order_uuid
      order_revision        = 1
      purchase_order_number = 'PO00002001'
      supplier              = 'SUP001'
      supplier_name         = 'Example Technology Supplier'
      company_code          = '1000'
      purchasing_organization = '1000'
      purchasing_group      = '001'
      currency              = 'EUR'
      total_amount          = '1500.00'
      items                 = VALUE #( (
        item_uuid       = item_uuid
        item_number     = '00010'
        material        = 'MAT001'
        description     = 'Laptop'
        quantity        = '2.000'
        unit_of_measure = 'EA'
        net_price       = '750.0000'
        total_amount    = '1500.00' ) ) ).

  ENDMETHOD.


  METHOD count_rows.
    SELECT COUNT( * ) FROM zjp_po_h INTO @DATA(headers).
    SELECT COUNT( * ) FROM zjp_po_i INTO @DATA(items).
    SELECT COUNT( * ) FROM zjp_po_dlv INTO @DATA(intents).
    total = headers + items + intents.
  ENDMETHOD.


  METHOD test_builder_reads_active.

    success = abap_false.

    " Any active order that has items and an allocated number. The builder is
    " not being asked to produce specific values here - it is being asked to
    " copy whatever is really there.
    DATA blank_number TYPE zjp_po_h-purchase_order_number.

    SELECT SINGLE i~purchase_order_uuid
      FROM zjp_po_i AS i
      INNER JOIN zjp_po_h AS h ON h~purchase_order_uuid = i~purchase_order_uuid
      WHERE h~purchase_order_number <> @blank_number
      INTO @DATA(order_uuid).

    IF sy-subrc <> 0.
      console->write( 'STOP: no active PurchaseOrder with items and an allocated number exists. Run ZJP_CL_PO_EML_TEST first.' ).
      RETURN.
    ENDIF.

    " Independently read what the builder is supposed to copy.
    SELECT SINGLE purchase_order_number, supplier, currency, total_amount, order_revision
      FROM zjp_po_h WHERE purchase_order_uuid = @order_uuid INTO @DATA(expected_header).

    SELECT purchase_order_item_uuid, item_number, material, material_description,
           quantity, unit_of_measure, net_price, total_amount
      FROM zjp_po_i WHERE purchase_order_uuid = @order_uuid
      ORDER BY item_number
      INTO TABLE @DATA(expected_items).

    DATA delivery_uuid TYPE sysuuid_x16 VALUE '000000000000000000000000000000AA'.

    DATA(rows_before) = count_rows( ).

    DATA(builder) = NEW zjp_cl_order_delivery_builder( ).
    DATA(result) = builder->build( purchase_order_uuid = order_uuid
                                   delivery_uuid       = delivery_uuid
                                   source_system       = 'PIH_ABAP_DEV' ).

    DATA(rows_after) = count_rows( ).

    console->write( name = 'Builder result' data = result ).

    IF result-success <> abap_true.
      console->write( 'STOP: builder did not succeed for a real active order.' ).
      RETURN.
    ENDIF.

    DATA(snapshot) = result-delivery.

    IF snapshot-purchase_order_uuid <> order_uuid.
      console->write( 'STOP: PurchaseOrderUUID was not copied.' ).
      RETURN.
    ENDIF.

    IF snapshot-delivery_uuid <> delivery_uuid.
      console->write( 'STOP: the DeliveryUUID input was not copied.' ).
      RETURN.
    ENDIF.

    IF snapshot-source_system <> 'PIH_ABAP_DEV'.
      console->write( 'STOP: the SourceSystem input was not copied.' ).
      RETURN.
    ENDIF.

    IF snapshot-schema_version <> '1.0'.
      console->write( 'STOP: schemaVersion is not 1.0.' ).
      RETURN.
    ENDIF.

    IF snapshot-purchase_order_number <> expected_header-purchase_order_number
       OR snapshot-supplier     <> expected_header-supplier
       OR snapshot-currency     <> expected_header-currency
       OR snapshot-total_amount <> expected_header-total_amount.
      console->write( 'STOP: a header commercial value does not match the persisted row.' ).
      RETURN.
    ENDIF.

    " Copied, not recalculated and not incremented.
    IF snapshot-order_revision <> expected_header-order_revision.
      console->write( 'STOP: OrderRevision was not copied unchanged.' ).
      RETURN.
    ENDIF.

    IF lines( snapshot-items ) <> lines( expected_items ).
      console->write( 'STOP: item count does not match the persisted items.' ).
      RETURN.
    ENDIF.

    LOOP AT expected_items INTO DATA(expected_item).
      IF NOT line_exists( snapshot-items[ item_uuid = expected_item-purchase_order_item_uuid ] ).
        console->write( 'STOP: a persisted item is missing from the snapshot.' ).
        RETURN.
      ENDIF.
      DATA(built_item) = snapshot-items[ item_uuid = expected_item-purchase_order_item_uuid ].
      IF built_item-item_number     <> expected_item-item_number
         OR built_item-material     <> expected_item-material
         OR built_item-description  <> expected_item-material_description
         OR built_item-quantity     <> expected_item-quantity
         OR built_item-unit_of_measure <> expected_item-unit_of_measure
         OR built_item-net_price    <> expected_item-net_price
         OR built_item-total_amount <> expected_item-total_amount.
        console->write( 'STOP: an item commercial value does not match the persisted row.' ).
        RETURN.
      ENDIF.
    ENDLOOP.

    " The builder is read-only, asserted rather than asserted-about.
    IF rows_after <> rows_before.
      console->write( 'STOP: the builder changed the database; it must be read-only.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: builder copied header, revision and all items from a real active order, and wrote nothing.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_mapper_golden_payload.

    success = abap_false.

    DATA(mapper) = NEW zjp_cl_cap_order_mapper( ).
    DATA(result) = mapper->map( golden_snapshot( ) ).

    console->write( name = 'Mapper request' data = result-request ).

    IF result-success <> abap_true.
      console->write( 'STOP: mapper did not succeed for the golden snapshot.' ).
      RETURN.
    ENDIF.

    IF result-request-path <> '/rest/integration/v1/Orders'.
      console->write( 'STOP: unexpected ingestion path.' ).
      RETURN.
    ENDIF.

    IF NOT line_exists( result-request-headers[ name = 'Content-Type' ] )
       OR result-request-headers[ name = 'Content-Type' ]-value <> 'application/json'.
      console->write( 'STOP: Content-Type is missing or wrong.' ).
      RETURN.
    ENDIF.

    " Valid JSON, proven by reparsing it rather than by inspecting it.
    DATA(reparsed) = xco_cp_json=>data->from_string( result-request-body ).
    IF reparsed IS NOT BOUND.
      console->write( 'STOP: the produced body did not reparse as JSON.' ).
      RETURN.
    ENDIF.

    " The decisive assertion. Byte equality against the golden payload covers
    " every member name, the nesting, the scalar types, all four decimal scales,
    " the C36 UUID form, revision and lineNumber as JSON numbers, 00010 -> 10,
    " and EA -> PCE, in one comparison that cannot be satisfied by accident.
    IF result-request-body <> golden_body( ).
      console->write( name = 'Produced body' data = result-request-body ).
      console->write( name = 'Golden body'   data = golden_body( ) ).
      console->write( 'STOP: produced body differs from the golden CAP payload.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: mapper produced the golden CAP payload byte for byte.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_mapper_determinism.

    success = abap_false.

    DATA(snapshot) = golden_snapshot( ).

    " Two separately constructed mappers, so determinism is shown to be a
    " property of the class rather than of one instance's history.
    DATA(first)  = NEW zjp_cl_cap_order_mapper( )->map( snapshot ).
    DATA(second) = NEW zjp_cl_cap_order_mapper( )->map( snapshot ).

    IF first-success <> abap_true OR second-success <> abap_true.
      console->write( 'STOP: determinism check could not map the snapshot.' ).
      RETURN.
    ENDIF.

    IF first-request-body <> second-request-body.
      console->write( 'STOP: the same snapshot produced two different bodies.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: the same snapshot mapped to a byte-identical body twice.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_mapper_rejects_unit.

    success = abap_false.

    DATA(snapshot) = golden_snapshot( ).
    snapshot-items[ 1 ]-unit_of_measure = 'BOX'.

    DATA(result) = NEW zjp_cl_cap_order_mapper( )->map( snapshot ).

    console->write( name = 'Unsupported unit result' data = result ).

    " "Unknown units fail validation; they are not guessed." A unit with no
    " mapping must be refused here rather than passed through for CAP to reject
    " with UNSUPPORTED_UNIT after a network round trip.
    IF result-success <> abap_false.
      console->write( 'STOP: an unmapped unit was accepted; it must be rejected, not guessed.' ).
      RETURN.
    ENDIF.

    IF result-error_code <> zjp_cl_cap_order_mapper=>error-unsupported_unit.
      console->write( 'STOP: expected error code UNSUPPORTED_UNIT.' ).
      RETURN.
    ENDIF.

    IF result-request IS NOT INITIAL.
      console->write( 'STOP: a rejected mapping must not produce a half-formed request.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: mapper rejected an unmapped unit instead of guessing it.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD source_snapshot_body.
    " The expected SOURCE order delivery snapshot for golden_snapshot( ). Note
    " how it differs from golden_body( ): `item` is the string "10" rather than
    " the number 10, the unit stays "EA" rather than becoming "PCE", and the
    " member names are the contract's source names. Those differences are the
    " point - one DTO, two shapes, and only the mapper may produce the CAP one.
    "
    " Concatenated rather than held as a CONSTANTS VALUE: a text literal is
    " capped at 255 characters and a constant's value must be a single literal.
    body = '{"schemaVersion":"1.0","deliveryId":"00000000-0000-0000-0000-000000000001",'
        && '"sourceSystem":"PIH_ABAP_DEV","purchaseOrderId":"00000000-0000-0000-0000-000000000002",'
        && '"revision":1,"purchaseOrder":"PO00002001","supplier":"SUP001",'
        && '"supplierName":"Example Technology Supplier","companyCode":"1000",'
        && '"purchasingOrganization":"1000","purchasingGroup":"001","currency":"EUR",'
        && '"totalAmount":"1500.00","items":[{'
        && '"itemId":"00000000-0000-0000-0000-000000000003","item":"10",'
        && '"material":"MAT001","description":"Laptop","quantity":"2.000",'
        && '"unitOfMeasure":"EA","netPrice":"750.0000","totalAmount":"1500.00"}]}'.
  ENDMETHOD.


  METHOD test_snapshot_serializer.
    " Phase 5.2f. The serializer is pure, so it is tested exactly like the
    " mapper: a deterministic in-memory DTO, and one byte comparison that
    " cannot be satisfied by accident.
    success = abap_false.

    DATA(snapshot) = golden_snapshot( ).

    DATA(json) = NEW zjp_cl_dlv_snapshot_json( )->serialize( snapshot ).

    console->write( name = 'Source delivery snapshot' data = json ).

    " (1)
    IF json IS INITIAL.
      console->write( 'STOP: serializer returned an initial string.' ).
      RETURN.
    ENDIF.

    " Valid JSON, proven by reparsing rather than by inspection.
    DATA(reparsed) = xco_cp_json=>data->from_string( json ).
    IF reparsed IS NOT BOUND.
      console->write( 'STOP: the snapshot did not reparse as JSON.' ).
      RETURN.
    ENDIF.

    " (2) Determinism, across two separately constructed instances, so it is a
    " property of the class rather than of one instance's history.
    DATA(second) = NEW zjp_cl_dlv_snapshot_json( )->serialize( snapshot ).
    IF json <> second.
      console->write( 'STOP: the same DTO produced two different snapshots.' ).
      RETURN.
    ENDIF.

    " (3)-(10) Named properties, each checked on its own so a failure says which
    " rule broke, before the byte comparison says only that something did.
    IF NOT json CS '"deliveryId":"00000000-0000-0000-0000-000000000001"'.
      console->write( 'STOP: deliveryId missing or not canonical C36.' ).
      RETURN.
    ENDIF.

    IF NOT json CS '"sourceSystem":"PIH_ABAP_DEV"'.
      console->write( 'STOP: sourceSystem was not carried through unchanged.' ).
      RETURN.
    ENDIF.

    " A JSON number, not a quoted string.
    IF NOT json CS '"revision":1,'.
      console->write( 'STOP: revision is not emitted as a JSON number.' ).
      RETURN.
    ENDIF.

    " NUMC 00010 becomes the source contract's unpadded STRING "10".
    IF NOT json CS '"item":"10"'.
      console->write( 'STOP: item number is not the unpadded string "10".' ).
      RETURN.
    ENDIF.

    " The source contract keeps EA. EA -> PCE belongs to the mapper alone, and
    " finding PCE here would mean the CAP boundary had leaked inwards.
    IF NOT json CS '"unitOfMeasure":"EA"'.
      console->write( 'STOP: unitOfMeasure is not the source value EA.' ).
      RETURN.
    ENDIF.

    IF json CS 'PCE'.
      console->write( 'STOP: CAP unit vocabulary leaked into the source snapshot.' ).
      RETURN.
    ENDIF.

    IF NOT json CS '"totalAmount":"1500.00"'
       OR NOT json CS '"quantity":"2.000"'
       OR NOT json CS '"netPrice":"750.0000"'.
      console->write( 'STOP: decimal scales do not match the source contract.' ).
      RETURN.
    ENDIF.

    " (11) The decisive assertion. PayloadHash will later be taken over exactly
    " this string, so byte equality is the property that actually matters.
    IF json <> source_snapshot_body( ).
      console->write( name = 'Produced snapshot' data = json ).
      console->write( name = 'Expected snapshot' data = source_snapshot_body( ) ).
      console->write( 'STOP: snapshot differs from the expected source contract string.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: serializer produced the source delivery snapshot byte for byte.' ).
    success = abap_true.
  ENDMETHOD.

ENDCLASS.
