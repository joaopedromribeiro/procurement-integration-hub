" Phase 5.2g - the delivery snapshot JSON reader. The exact inverse of
" ZJP_CL_DLV_SNAPSHOT_JSON, and the object that lets the coordinator dispatch the
" PERSISTED snapshot instead of rebuilding one.
"
" WHY IT HAS TO EXIST. ZJP_PO_DLV-PayloadSnapshot is a JSON string; the verified
" ZJP_CL_CAP_ORDER_MAPPER=>MAP takes the typed TY_DELIVERY. Phase 5.2f only ever
" needed the one-way trip, so nothing converted the string back. ADR-032 forbids
" the two shortcuts that would avoid this class: the snapshot may not be replaced
" by the mapped CAP body, because Phase 6 deletes the mapping hop and keeps the
" source hop; and the coordinator may not rebuild the delivery from the current
" PurchaseOrder, because the whole point of the outbox is that what is dispatched
" is what was approved, not what the order says later.
"
" WHAT IT MUST NOT DO, and does not: it reads no PurchaseOrder, reads no
" DeliveryIntent row, opens no connection, computes no hash, and mutates nothing.
" It is pure - the same string in gives the same DTO out - and it has no
" constructor and no state.
"
" THE TWO-STEP SHAPE IS DELIBERATE. The JSON is first bound to an intermediate
" structure that mirrors the SOURCE CONTRACT member for member, and only then
" mapped explicitly onto TY_DELIVERY. One automatic step plus one explicit step,
" rather than one clever step: the intermediate names are the contract's names
" after the underscore transformation, so the binding is mechanical, while every
" type conversion that could silently go wrong - text to UUID, text to packed
" decimal, text to NUMC - is written out where it can be read and reviewed.
"
" ALL JSON SCALARS ARE BOUND AS STRING except `revision`, which the serializer
" writes with ADD_NUMBER and which is therefore a JSON number. The contract sends
" totalAmount, quantity and netPrice as JSON STRINGS with fixed scales, so they
" arrive as text and are converted here.
"
" SAP RUNTIME-VERIFIED in Phase 5.2g. The golden persisted snapshot round-trips
" through this reader and back out of ZJP_CL_DLV_SNAPSHOT_JSON byte-identically,
" and the reconstructed DTO was accepted by ZJP_CL_CAP_ORDER_MAPPER unchanged.
" Two target-specific facts were settled the hard way and are recorded at their
" call sites below: XCO WRITE_TO is TERMINAL, and the C36 to X16 conversion is
" case-sensitive in a way that fails silently.
CLASS zjp_cl_dlv_snapshot_reader DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    " An outcome record rather than an exception, matching the builder, the
    " mapper and the transport seam. A malformed snapshot is a condition the
    " coordinator must classify, not an exception it must catch.
    TYPES:
      BEGIN OF ty_result,
        success    TYPE abap_bool,
        delivery   TYPE zjp_cl_order_delivery_builder=>ty_delivery,
        error_code TYPE string,
        error_text TYPE string,
      END OF ty_result.

    CONSTANTS:
      BEGIN OF error,
        empty_snapshot TYPE string VALUE 'EMPTY_SNAPSHOT',
        unreadable     TYPE string VALUE 'SNAPSHOT_UNREADABLE',
        no_items       TYPE string VALUE 'SNAPSHOT_NO_ITEMS',
        bad_identity   TYPE string VALUE 'SNAPSHOT_BAD_IDENTITY',
      END OF error.

    METHODS read
      IMPORTING snapshot      TYPE string
                RETURNING VALUE(result) TYPE ty_result.

  PRIVATE SECTION.

    " The SOURCE contract, one component per JSON member. The names are the
    " contract's camelCase members after camel-case-to-underscore, which is what
    " makes the binding below mechanical rather than a second mapping table.
    TYPES:
      BEGIN OF ty_src_item,
        item_id         TYPE string,
        item            TYPE string,
        material        TYPE string,
        description     TYPE string,
        quantity        TYPE string,
        unit_of_measure TYPE string,
        net_price       TYPE string,
        total_amount    TYPE string,
      END OF ty_src_item,
      ty_src_items TYPE STANDARD TABLE OF ty_src_item WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_source,
        schema_version          TYPE string,
        delivery_id             TYPE string,
        source_system           TYPE string,
        purchase_order_id       TYPE string,
        revision                TYPE i,
        purchase_order          TYPE string,
        supplier                TYPE string,
        supplier_name           TYPE string,
        company_code            TYPE string,
        purchasing_organization TYPE string,
        purchasing_group        TYPE string,
        currency                TYPE string,
        total_amount            TYPE string,
        items                   TYPE ty_src_items,
      END OF ty_source.

    " THE ONE XCO CALL, isolated so the contract types and the explicit mapping
    " above it never depend on the binding API. IF_XCO_CP_JSON_DATA exposes APPLY,
    " TO_STRING, TRAVERSE and WRITE_TO on this target and NO GET_MEMBER-style
    " accessors at all, which is why this is a WRITE_TO binding rather than a
    " member walk. TRAVERSE was not needed.
    METHODS bind_source
      IMPORTING snapshot      TYPE string
      EXPORTING source        TYPE ty_source
      RETURNING VALUE(success) TYPE abap_bool.

    " SIGNATURE SETTLED BY THE SAP METHOD LIST. P5 had verified the OPPOSITE
    " direction only, and the symmetric guess was wrong: the parameters are NOT
    " named after the source representation. The real signature on this target is
    "
    "   EXPORTING uuid     = <the C36 text>
    "   IMPORTING uuid_x16 = <the raw 16 bytes>
    "
    " so 'uuid' is the INPUT in both directions and the output is named after the
    " target representation. Worth remembering, because the symmetry the earlier
    " guess assumed does not exist.
    METHODS uuid_from_text
      IMPORTING text        TYPE string
      RETURNING VALUE(uuid) TYPE sysuuid_x16.

ENDCLASS.


CLASS zjp_cl_dlv_snapshot_reader IMPLEMENTATION.

  METHOD read.

    result-success = abap_false.

    IF snapshot IS INITIAL.
      result-error_code = error-empty_snapshot.
      result-error_text = 'The persisted PayloadSnapshot is empty.'.
      RETURN.
    ENDIF.

    DATA source TYPE ty_source.

    IF bind_source( EXPORTING snapshot = snapshot
                    IMPORTING source   = source ) = abap_false.
      result-error_code = error-unreadable.
      result-error_text = 'The persisted PayloadSnapshot could not be parsed.'.
      RETURN.
    ENDIF.

    " Identity is the one thing worth refusing on. A snapshot without its two
    " UUIDs cannot be dispatched under the identity the intent holds, and a
    " silent initial UUID would produce a wire message addressed to nothing.
    IF source-delivery_id IS INITIAL OR source-purchase_order_id IS INITIAL.
      result-error_code = error-bad_identity.
      result-error_text = 'The snapshot carries no delivery or order identity.'.
      RETURN.
    ENDIF.

    IF source-items IS INITIAL.
      result-error_code = error-no_items.
      result-error_text = 'The snapshot carries no items.'.
      RETURN.
    ENDIF.

    " The explicit half. Every conversion that can go wrong is written out.
    result-delivery-schema_version          = source-schema_version.
    result-delivery-delivery_uuid           = uuid_from_text( source-delivery_id ).
    result-delivery-source_system           = source-source_system.
    result-delivery-purchase_order_uuid     = uuid_from_text( source-purchase_order_id ).
    result-delivery-order_revision          = source-revision.
    result-delivery-purchase_order_number   = source-purchase_order.
    result-delivery-supplier                = source-supplier.
    result-delivery-supplier_name           = source-supplier_name.
    result-delivery-company_code            = source-company_code.
    result-delivery-purchasing_organization = source-purchasing_organization.
    result-delivery-purchasing_group        = source-purchasing_group.
    result-delivery-currency                = source-currency.

    " Text to packed. The contract sends the amount as the STRING "1500.00" with
    " a dot separator, and ABAP reads a dot as the decimal point in this
    " direction. The reader's own test proves it by re-serializing and comparing
    " byte for byte, which is the only check that cannot pass by accident.
    result-delivery-total_amount            = source-total_amount.

    LOOP AT source-items INTO DATA(src_item).

      DATA target_item TYPE zjp_cl_order_delivery_builder=>ty_item.
      CLEAR target_item.

      target_item-item_uuid = uuid_from_text( src_item-item_id ).

      " "10" back to NUMC(5) '00010'. Character-to-NUMC assignment right-aligns
      " and pads with leading zeros, which is the exact inverse of the
      " serializer's SHIFT ... LEFT DELETING LEADING '0'.
      target_item-item_number = src_item-item.

      target_item-material    = src_item-material.
      target_item-description = src_item-description.
      target_item-quantity    = src_item-quantity.

      " Stays EA. The source contract has no PCE anywhere and EA -> PCE is the
      " mapper's business alone; a PCE appearing here would mean the ADR-032
      " boundary had been broken by the reader.
      target_item-unit_of_measure = src_item-unit_of_measure.

      target_item-net_price    = src_item-net_price.
      target_item-total_amount = src_item-total_amount.

      APPEND target_item TO result-delivery-items.

    ENDLOOP.

    result-success = abap_true.

  ENDMETHOD.


  METHOD bind_source.

    success = abap_false.
    CLEAR source.

    TRY.

        " ORDER MATTERS, AND THE COMPILER SETTLED IT. The first version chained
        " FROM_STRING -> WRITE_TO -> APPLY and SAP rejected it: WRITE_TO has NO
        " RETURNING parameter on this target and therefore cannot appear inside an
        " expression chain at all. It is TERMINAL. The correct order is
        "
        "   FROM_STRING  ->  APPLY  ->  WRITE_TO
        "
        " which also reads correctly: transform the document first, then bind the
        " transformed document to the structure. The transformation turns the
        " contract's camelCase members into TY_SOURCE's underscored components.
        DATA(json_data) = xco_cp_json=>data->from_string( snapshot ).

        DATA(transformed_data) = json_data->apply(
          VALUE #( ( xco_cp_json=>transformation->camel_case_to_underscore ) ) ).

        transformed_data->write_to( REF #( source ) ).

        success = abap_true.

      CATCH cx_root.
        CLEAR source.
    ENDTRY.

  ENDMETHOD.


  METHOD uuid_from_text.

    DATA uuid_c36 TYPE sysuuid_c36.

    uuid_c36 = text.

    " Uppercase before converting. See ZJP_CL_DISPATCH_COORDINATOR for the full
    " runtime finding: lowercase C36 input can produce a SILENTLY TRUNCATED X16
    " on this target. Snapshot UUIDs are written by our own serializer and are
    " already lowercase canonical, so this boundary needs the same normalisation
    " as the CAP receipt does.
    TRANSLATE uuid_c36 TO UPPER CASE.

    TRY.
        cl_system_uuid=>convert_uuid_c36_static(
          EXPORTING uuid     = uuid_c36
          IMPORTING uuid_x16 = uuid ).
      CATCH cx_root.
        CLEAR uuid.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
