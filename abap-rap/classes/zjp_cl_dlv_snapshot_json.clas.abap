" Phase 5.2f - the source order delivery snapshot serializer.
"
" One responsibility: turn the typed canonical snapshot into the deterministic
" JSON string that ZJP_PO_DLV-PayloadSnapshot stores. ADR-032 freezes the SOURCE
" order delivery in the intent, not the mapped CAP order, because Phase 6 deletes
" the mapping hop and keeps this one - so this shape must outlive the endpoint.
"
" It is stateless and pure: same DTO in, byte-identical string out. No EML, no
" database access, no HTTP, no COMMIT or ROLLBACK, and no hashing - PayloadHash
" is computed by the caller over whatever string this returns, which is why the
" output has to be deterministic rather than merely valid.
"
" It knows nothing about CAP. No endpoint path, no headers, no CAP member names,
" and no unit vocabulary: the source contract keeps `EA`, and `EA` -> `PCE` is
" the mapper's business alone. If this class ever needs to know a CAP name, the
" boundary has been broken.
"
" Every conversion below reuses a pattern this repository has already proven at
" runtime, never one written from memory:
"   sysuuid_x16 -> canonical C36 text   CL_SYSTEM_UUID=>CONVERT_UUID_X16_STATIC  (P5)
"   numeric     -> fixed-scale string   |{ value NUMBER = RAW DECIMALS = n }|    (P6)
"   JSON        -> explicit members     XCO_CP_JSON=>DATA->BUILDER( )            (P10)
CLASS zjp_cl_dlv_snapshot_json DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS serialize
      IMPORTING delivery    TYPE zjp_cl_order_delivery_builder=>ty_delivery
      RETURNING VALUE(json) TYPE string.

  PRIVATE SECTION.

    " Isolated for the same reason the mapper isolates it: this is the one call
    " whose exact parameter names came from probe evidence rather than from
    " source in this repository.
    METHODS uuid_text
      IMPORTING uuid        TYPE sysuuid_x16
      RETURNING VALUE(text) TYPE string.

    " NUMC(5) '00010' becomes the contract's "10" - a STRING, unpadded. The
    " source contract writes `"item": "10"`, which differs from the CAP order's
    " `lineNumber: 10`; the two shapes disagree on purpose and only the mapper
    " may produce the second. Leading zeros are stripped with a core statement
    " rather than a numeric format option, so no locale or formatting rule can
    " reach this value at all.
    METHODS item_text
      IMPORTING item_number TYPE zjp_po_i-item_number
      RETURNING VALUE(text) TYPE string.

ENDCLASS.


CLASS zjp_cl_dlv_snapshot_json IMPLEMENTATION.

  METHOD uuid_text.
    DATA uuid_c36 TYPE sysuuid_c36.

    cl_system_uuid=>convert_uuid_x16_static(
      EXPORTING uuid     = uuid
      IMPORTING uuid_c36 = uuid_c36 ).

    text = uuid_c36.
  ENDMETHOD.


  METHOD item_text.
    text = CONV string( item_number ).
    SHIFT text LEFT DELETING LEADING '0'.
  ENDMETHOD.


  METHOD serialize.

    " Member order is fixed and follows API_CONTRACTS' own listing. The order is
    " part of the contract here in a way it is not on the wire: PayloadHash is
    " taken over this exact string, so a reordering would change the hash of an
    " otherwise identical snapshot.
    DATA(builder) = xco_cp_json=>data->builder( ).

    builder->begin_object( ).

    builder->add_member( 'schemaVersion' )->add_string( delivery-schema_version ).
    builder->add_member( 'deliveryId' )->add_string( uuid_text( delivery-delivery_uuid ) ).
    builder->add_member( 'sourceSystem' )->add_string( delivery-source_system ).
    builder->add_member( 'purchaseOrderId' )->add_string( uuid_text( delivery-purchase_order_uuid ) ).

    " A JSON number, matching the contract's `"revision": 1`. Copied, never
    " recalculated - the builder already established that.
    builder->add_member( 'revision' )->add_number( delivery-order_revision ).

    builder->add_member( 'purchaseOrder' )->add_string( |{ delivery-purchase_order_number }| ).
    builder->add_member( 'supplier' )->add_string( |{ delivery-supplier }| ).
    builder->add_member( 'supplierName' )->add_string( |{ delivery-supplier_name }| ).
    builder->add_member( 'companyCode' )->add_string( |{ delivery-company_code }| ).
    builder->add_member( 'purchasingOrganization' )->add_string( |{ delivery-purchasing_organization }| ).
    builder->add_member( 'purchasingGroup' )->add_string( |{ delivery-purchasing_group }| ).
    builder->add_member( 'currency' )->add_string( |{ delivery-currency }| ).
    builder->add_member( 'totalAmount' )->add_string( |{ delivery-total_amount NUMBER = RAW DECIMALS = 2 }| ).

    builder->add_member( 'items' ).
    builder->begin_array( ).

    LOOP AT delivery-items INTO DATA(item).

      builder->begin_object( ).

      builder->add_member( 'itemId' )->add_string( uuid_text( item-item_uuid ) ).
      builder->add_member( 'item' )->add_string( item_text( item-item_number ) ).
      builder->add_member( 'material' )->add_string( |{ item-material }| ).
      builder->add_member( 'description' )->add_string( |{ item-description }| ).
      builder->add_member( 'quantity' )->add_string( |{ item-quantity NUMBER = RAW DECIMALS = 3 }| ).

      " The SAP value, untouched. No mapping table, no PCE, no CAP vocabulary.
      builder->add_member( 'unitOfMeasure' )->add_string( |{ item-unit_of_measure }| ).

      builder->add_member( 'netPrice' )->add_string( |{ item-net_price NUMBER = RAW DECIMALS = 4 }| ).
      builder->add_member( 'totalAmount' )->add_string( |{ item-total_amount NUMBER = RAW DECIMALS = 2 }| ).

      builder->end_object( ).

    ENDLOOP.

    builder->end_array( ).
    builder->end_object( ).

    json = builder->get_data( )->to_string( ).

  ENDMETHOD.

ENDCLASS.
