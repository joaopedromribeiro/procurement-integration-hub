" Phase 5.2d - the CAP wire mapper, object 9 of the Phase 5.1 section 10
" inventory: "Source delivery -> mapped CAP order JSON; pure and deterministic;
" owns EA -> PCE".
"
" It converts the canonical snapshot into the transport request of the VERIFIED
" Phase 5.2c seam. It is pure: same snapshot in, byte-identical request out. It
" opens no connection, names no destination, reads no database and writes none.
"
" Everything endpoint-shaped lives here and nowhere else:
"   sysuuid_x16   -> canonical 36-character text   (P5, CL_SYSTEM_UUID)
"   numeric       -> fixed-scale decimal STRING    (P6, NUMBER = RAW DECIMALS)
"   NUMC '00010'  -> JSON number 10
"   'EA'          -> 'PCE', by lookup and rejection
"   member names  -> exact case-sensitive camelCase
"
" Phase 6 deletes this hop and keeps the builder's, which is why the two are
" separate classes rather than one.
CLASS zjp_cl_cap_order_mapper DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_result,
        success    TYPE abap_bool,
        request    TYPE zjp_if_outbound_transport=>ty_request,
        error_code TYPE string,
        error_text TYPE string,
      END OF ty_result.

    CONSTANTS:
      BEGIN OF error,
        unsupported_unit TYPE string VALUE 'UNSUPPORTED_UNIT',
      END OF error.

    " Path only, never a base URL: the host and its credentials belong to the
    " destination configuration, per the seam's own contract in section 6.2.
    CONSTANTS ingestion_path TYPE string VALUE '/rest/integration/v1/Orders'.
    CONSTANTS content_type   TYPE string VALUE 'application/json'.

    METHODS constructor.

    METHODS map
      IMPORTING delivery      TYPE zjp_cl_order_delivery_builder=>ty_delivery
      RETURNING VALUE(result) TYPE ty_result.

  PRIVATE SECTION.

    " The controlled value mapping, as a lookup rather than a branch. The
    " contract's rule is "unknown units fail validation; they are not guessed",
    " and a lookup that can miss is what makes rejection the default. No DDIC
    " customizing object is documented for this, and Phase 6 is where value
    " mapping formally moves to Cloud Integration, so the table lives here.
    TYPES:
      BEGIN OF ty_unit_map,
        sap_unit  TYPE zjp_po_i-unit_of_measure,
        wire_unit TYPE string,
      END OF ty_unit_map.

    DATA unit_map TYPE STANDARD TABLE OF ty_unit_map WITH EMPTY KEY.

    " Isolated on purpose: this is the only call in Phase 5.2d whose exact
    " parameter names were not captured by the P5 probe evidence, so if ADT
    " rejects the signature, this one method is what changes.
    METHODS uuid_text
      IMPORTING uuid        TYPE sysuuid_x16
      RETURNING VALUE(text) TYPE string.

ENDCLASS.


CLASS zjp_cl_cap_order_mapper IMPLEMENTATION.

  METHOD constructor.
    unit_map = VALUE #( ( sap_unit = 'EA' wire_unit = 'PCE' ) ).
  ENDMETHOD.


  METHOD uuid_text.
    DATA uuid_c36 TYPE sysuuid_c36.

    cl_system_uuid=>convert_uuid_x16_static(
      EXPORTING uuid     = uuid
      IMPORTING uuid_c36 = uuid_c36 ).

    text = uuid_c36.
  ENDMETHOD.


  METHOD map.

    result-success = abap_false.

    " Reject before building anything, so a rejected delivery never produces a
    " half-formed body that could be mistaken for a sendable one.
    LOOP AT delivery-items INTO DATA(check_item).
      IF NOT line_exists( unit_map[ sap_unit = check_item-unit_of_measure ] ).
        result-error_code = error-unsupported_unit.
        result-error_text = |Unit { check_item-unit_of_measure } has no mapping to a CAP unit.|.
        RETURN.
      ENDIF.
    ENDLOOP.

    DATA(builder) = xco_cp_json=>data->builder( ).

    builder->begin_object( ).

    builder->add_member( 'schemaVersion' )->add_string( delivery-schema_version ).
    builder->add_member( 'deliveryId' )->add_string( uuid_text( delivery-delivery_uuid ) ).

    builder->add_member( 'source' ).
    builder->begin_object( ).
    builder->add_member( 'system' )->add_string( delivery-source_system ).
    builder->add_member( 'orderId' )->add_string( uuid_text( delivery-purchase_order_uuid ) ).
    builder->add_member( 'orderNumber' )->add_string( |{ delivery-purchase_order_number }| ).
    " A JSON number, not a string. Copied from the snapshot, never recalculated.
    builder->add_member( 'revision' )->add_number( delivery-order_revision ).
    builder->end_object( ).

    builder->add_member( 'supplierCode' )->add_string( |{ delivery-supplier }| ).

    builder->add_member( 'amount' ).
    builder->begin_object( ).
    builder->add_member( 'currency' )->add_string( |{ delivery-currency }| ).
    builder->add_member( 'value' )->add_string( |{ delivery-total_amount NUMBER = RAW DECIMALS = 2 }| ).
    builder->end_object( ).

    builder->add_member( 'lines' ).
    builder->begin_array( ).

    LOOP AT delivery-items INTO DATA(item).

      builder->begin_object( ).

      builder->add_member( 'sourceItemId' )->add_string( uuid_text( item-item_uuid ) ).
      " NUMC '00010' becomes the JSON number 10. The scale change is the point:
      " CAP declares lineNumber as Integer and rejects a padded string.
      builder->add_member( 'lineNumber' )->add_number( CONV i( item-item_number ) ).

      builder->add_member( 'product' ).
      builder->begin_object( ).
      builder->add_member( 'code' )->add_string( |{ item-material }| ).
      builder->add_member( 'description' )->add_string( |{ item-description }| ).
      builder->end_object( ).

      builder->add_member( 'orderedQuantity' ).
      builder->begin_object( ).
      builder->add_member( 'value' )->add_string( |{ item-quantity NUMBER = RAW DECIMALS = 3 }| ).
      builder->add_member( 'unit' )->add_string( unit_map[ sap_unit = item-unit_of_measure ]-wire_unit ).
      builder->end_object( ).

      builder->add_member( 'unitPrice' ).
      builder->begin_object( ).
      " The HEADER currency, propagated onto every line, as the mapping table
      " specifies. CAP answers LINE_CURRENCY_MISMATCH if a line disagrees, and
      " propagating rather than copying the line's own value is what prevents it.
      builder->add_member( 'currency' )->add_string( |{ delivery-currency }| ).
      builder->add_member( 'value' )->add_string( |{ item-net_price NUMBER = RAW DECIMALS = 4 }| ).
      builder->end_object( ).

      builder->add_member( 'lineAmount' )->add_string( |{ item-total_amount NUMBER = RAW DECIMALS = 2 }| ).

      builder->end_object( ).

    ENDLOOP.

    builder->end_array( ).
    builder->end_object( ).

    result-request-path = ingestion_path.

    " Content-Type is a property of this body and belongs with the mapping.
    " Idempotency-Key equals the deliveryId, per section 5.4, and is therefore
    " derived from the payload rather than from the attempt.
    " X-Correlation-ID is deliberately ABSENT: it is a fresh UUID per transport
    " ATTEMPT, which makes it the transport's to mint, not the mapper's - and
    " Phase 5.2d creates no UUIDs at all.
    result-request-headers = VALUE #(
      ( name = 'Content-Type'    value = content_type )
      ( name = 'Idempotency-Key' value = uuid_text( delivery-delivery_uuid ) ) ).

    result-request-body = builder->get_data( )->to_string( ).

    result-success = abap_true.

  ENDMETHOD.

ENDCLASS.
