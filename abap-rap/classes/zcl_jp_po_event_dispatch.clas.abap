CLASS zcl_jp_po_event_dispatch DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.

  PRIVATE SECTION.

    CONSTANTS destination TYPE rfcdest
      VALUE 'ZJP_CI_ORDER_DELIVERY'.

    " Phase 9.5B DEV runtime value.
    " This is explicit runtime wiring, not a cross-environment default.
    CONSTANTS lease_seconds TYPE i VALUE 300.

    CONSTANTS auth_role TYPE c LENGTH 10 VALUE 'DISPATCH'.

TYPES:
  BEGIN OF ty_wire_request,
    delivery_u_u_i_d        TYPE string,
    purchase_order_u_u_i_d  TYPE string,
    order_revision          TYPE i,
    payload_hash            TYPE string,
  END OF ty_wire_request.

    TYPES:
      BEGIN OF ty_http_result,
        status       TYPE i,
        body         TYPE string,
        allow_header TYPE string,
      END OF ty_http_result.

    METHODS process_request
      IMPORTING
        http_method  TYPE string
        content_type TYPE string
        body         TYPE string
        authorized   TYPE abap_bool
        trigger      TYPE REF TO zjp_cl_event_trigger
      RETURNING
        VALUE(result) TYPE ty_http_result.

    METHODS build_trigger
      RETURNING
        VALUE(trigger) TYPE REF TO zjp_cl_event_trigger.

    METHODS parse_request
      IMPORTING
        body            TYPE string
      EXPORTING
        valid           TYPE abap_bool
        error_text      TYPE string
        trigger_request TYPE zjp_cl_event_trigger=>ty_request.

    METHODS uuid_from_text
      IMPORTING
        text        TYPE string
      EXPORTING
        valid       TYPE abap_bool
      RETURNING
        VALUE(uuid) TYPE sysuuid_x16.

    METHODS uuid_to_text
      IMPORTING
        uuid        TYPE sysuuid_x16
      RETURNING
        VALUE(text) TYPE string.

    METHODS result_json
      IMPORTING
        delivery_uuid TYPE sysuuid_x16
        result        TYPE zjp_cl_event_trigger=>ty_result
      RETURNING
        VALUE(json) TYPE string.

    METHODS error_json
      IMPORTING
        code        TYPE string
        message     TYPE string
      RETURNING
        VALUE(json) TYPE string.

    METHODS respond
      IMPORTING
        response TYPE REF TO if_web_http_response
        status   TYPE i
        body     TYPE string.

ENDCLASS.


CLASS zcl_jp_po_event_dispatch IMPLEMENTATION.

  METHOD if_http_service_extension~handle_request.

    TRY.

        DATA(http_method) = request->get_method( ).

        DATA authorized   TYPE abap_bool.
        DATA content_type TYPE string.
        DATA body         TYPE string.
        DATA trigger      TYPE REF TO zjp_cl_event_trigger.

        " Method validation happens before authorization.
        IF http_method = 'POST'.

          AUTHORITY-CHECK OBJECT 'ZJP_PIH'
            ID 'ZJP_ROLE'
            FIELD auth_role.

          authorized = xsdbool( sy-subrc = 0 ).

          " An unauthorized caller never causes the production
          " trigger/dispatcher/transport graph to be built.
          IF authorized = abap_true.

            content_type = request->get_content_type( ).
            body         = request->get_text( ).

            trigger = build_trigger( ).

          ENDIF.

        ENDIF.

        DATA(process_result) = process_request(
          http_method  = http_method
          content_type = content_type
          body         = body
          authorized   = authorized
          trigger      = trigger
        ).

        IF process_result-allow_header IS NOT INITIAL.

          response->set_header_field(
            i_name  = 'Allow'
            i_value = process_result-allow_header
          ).

        ENDIF.

        respond(
          response = response
          status   = process_result-status
          body     = process_result-body
        ).

      CATCH cx_web_message_error.

        respond(
          response = response
          status   = 500
          body     = error_json(
                       code    = 'HTTP_SERVICE_ERROR'
                       message = 'The HTTP request could not be processed.'
                     )
        ).

      CATCH cx_root.

        respond(
          response = response
          status   = 500
          body     = error_json(
                       code    = 'INTERNAL_ERROR'
                       message = 'An unexpected technical error occurred.'
                     )
        ).

    ENDTRY.

  ENDMETHOD.


  METHOD process_request.

    CLEAR result.

    " -------------------------------------------------------
    " POST only
    " -------------------------------------------------------
    IF http_method <> 'POST'.

      result-status       = 405.
      result-allow_header = 'POST'.

      result-body = error_json(
        code    = 'METHOD_NOT_ALLOWED'
        message = 'Only POST is allowed.'
      ).

      RETURN.

    ENDIF.

    " -------------------------------------------------------
    " Explicit PIH authorization
    " -------------------------------------------------------
    IF authorized = abap_false.

      result-status = 403.

      result-body = error_json(
        code    = 'FORBIDDEN'
        message = 'The caller is not authorized to dispatch deliveries.'
      ).

      RETURN.

    ENDIF.

    " -------------------------------------------------------
    " JSON only
    " -------------------------------------------------------
    DATA(normalized_content_type) = content_type.
    TRANSLATE normalized_content_type TO LOWER CASE.

    IF normalized_content_type NP 'application/json*'.

      result-status = 415.

      result-body = error_json(
        code    = 'UNSUPPORTED_MEDIA_TYPE'
        message = 'Content-Type must be application/json.'
      ).

      RETURN.

    ENDIF.

    IF body IS INITIAL.

      result-status = 400.

      result-body = error_json(
        code    = 'INVALID_REQUEST'
        message = 'Request body is required.'
      ).

      RETURN.

    ENDIF.

    " -------------------------------------------------------
    " Parse + validate logical event identity
    " -------------------------------------------------------
    DATA trigger_request TYPE zjp_cl_event_trigger=>ty_request.
    DATA valid            TYPE abap_bool.
    DATA error_text       TYPE string.

    parse_request(
      EXPORTING
        body            = body
      IMPORTING
        valid           = valid
        error_text      = error_text
        trigger_request = trigger_request
    ).

    IF valid = abap_false.

      result-status = 400.

      result-body = error_json(
        code    = 'INVALID_REQUEST'
        message = error_text
      ).

      RETURN.

    ENDIF.

    " Fail closed if production/test wiring did not supply the trigger.
    IF trigger IS NOT BOUND.

      result-status = 500.

      result-body = error_json(
        code    = 'TRIGGER_NOT_AVAILABLE'
        message = 'The event trigger is not available.'
      ).

      RETURN.

    ENDIF.

    " -------------------------------------------------------
    " Exactly one delegation.
    " -------------------------------------------------------
    DATA(trigger_result) =
      trigger->trigger( trigger_request ).

    result-status = 200.

    result-body = result_json(
      delivery_uuid = trigger_request-delivery_uuid
      result        = trigger_result
    ).

  ENDMETHOD.


  METHOD build_trigger.

    DATA reader TYPE REF TO zjp_if_event_intent_reader.

    reader = NEW zjp_cl_event_intent_reader( ).

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_outbound_transport(
      destination_name = destination
    ).

    DATA dispatcher TYPE REF TO zjp_if_event_dispatcher.

    dispatcher = NEW zjp_cl_event_dispatcher(
      transport      = transport
      lease_seconds  = lease_seconds
    ).

    trigger = NEW zjp_cl_event_trigger(
      reader     = reader
      dispatcher = dispatcher
    ).

  ENDMETHOD.


  METHOD parse_request.

    CLEAR:
      valid,
      error_text,
      trigger_request.

    DATA wire TYPE ty_wire_request.

    TRY.

        DATA(json_data) =
          xco_cp_json=>data->from_string( body ).

        DATA(transformed_data) =
          json_data->apply(
            VALUE #(
              ( xco_cp_json=>transformation->camel_case_to_underscore )
            )
          ).

        transformed_data->write_to(
          REF #( wire )
        ).

      CATCH cx_root.

        error_text = 'The request body is not valid JSON.'.
        RETURN.

    ENDTRY.

    " -------------------------------------------------------
    " Required fields
    " -------------------------------------------------------
IF wire-delivery_u_u_i_d IS INITIAL
   OR wire-purchase_order_u_u_i_d IS INITIAL
   OR wire-order_revision <= 0
   OR wire-payload_hash IS INITIAL.

  error_text =
    'deliveryUUID, purchaseOrderUUID, orderRevision and payloadHash are required.'.

  RETURN.

ENDIF.

    " -------------------------------------------------------
    " SHA-256 representation
    " -------------------------------------------------------
    IF strlen( wire-payload_hash ) <> 64.

      error_text =
        'payloadHash must contain exactly 64 hexadecimal characters.'.

      RETURN.

    ENDIF.

    FIND REGEX '^[0-9A-Fa-f]{64}$'
      IN wire-payload_hash.

    IF sy-subrc <> 0.

      error_text =
        'payloadHash must contain exactly 64 hexadecimal characters.'.

      RETURN.

    ENDIF.

    " -------------------------------------------------------
    " Delivery UUID
    " -------------------------------------------------------
    DATA delivery_uuid TYPE sysuuid_x16.

delivery_uuid = uuid_from_text(
  EXPORTING
    text  = wire-delivery_u_u_i_d
  IMPORTING
    valid = valid
).
    IF valid = abap_false.

      error_text =
        'deliveryUUID is not a valid canonical UUID.'.

      RETURN.

    ENDIF.

    " -------------------------------------------------------
    " Purchase Order UUID
    " -------------------------------------------------------
    DATA purchase_order_uuid TYPE sysuuid_x16.

purchase_order_uuid = uuid_from_text(
  EXPORTING
    text  = wire-purchase_order_u_u_i_d
  IMPORTING
    valid = valid
).
    IF valid = abap_false.

      error_text =
        'purchaseOrderUUID is not a valid canonical UUID.'.

      RETURN.

    ENDIF.

    trigger_request = VALUE #(
      delivery_uuid        = delivery_uuid
      purchase_order_uuid  = purchase_order_uuid
      order_revision       = wire-order_revision
      payload_hash         = wire-payload_hash
    ).

    valid = abap_true.

  ENDMETHOD.


  METHOD uuid_from_text.

    CLEAR:
      uuid,
      valid.

    DATA canonical TYPE string.
    canonical = text.

    TRANSLATE canonical TO UPPER CASE.

    FIND REGEX
      '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'
      IN canonical.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    TRY.

        DATA uuid_c36 TYPE sysuuid_c36.
        uuid_c36 = canonical.

        cl_system_uuid=>convert_uuid_c36_static(
          EXPORTING
            uuid     = uuid_c36
          IMPORTING
            uuid_x16 = uuid
        ).

        DATA(round_trip) = uuid_to_text( uuid ).

        TRANSLATE round_trip TO UPPER CASE.

        IF round_trip <> canonical.

          CLEAR uuid.
          RETURN.

        ENDIF.

        valid = abap_true.

      CATCH cx_root.

        CLEAR uuid.
        valid = abap_false.

    ENDTRY.

  ENDMETHOD.


  METHOD uuid_to_text.

    DATA uuid_c36 TYPE sysuuid_c36.

    cl_system_uuid=>convert_uuid_x16_static(
      EXPORTING
        uuid     = uuid
      IMPORTING
        uuid_c36 = uuid_c36
    ).

    text = uuid_c36.

  ENDMETHOD.


  METHOD result_json.

    DATA(builder) =
      xco_cp_json=>data->builder( ).

    builder->begin_object( ).

    builder->add_member( 'decision' ).
    builder->add_string( result-decision ).

    builder->add_member( 'deliveryUUID' ).
    builder->add_string(
      uuid_to_text( delivery_uuid )
    ).

    IF result-decision =
         zjp_cl_event_trigger=>decision-delegated.

      builder->add_member( 'coordinator' ).
      builder->begin_object( ).

      builder->add_member( 'claimed' ).
      builder->add_boolean(
        result-coordinator_outcome-claimed
      ).

      builder->add_member( 'dispatched' ).
      builder->add_boolean(
        result-coordinator_outcome-dispatched
      ).

      builder->add_member( 'recorded' ).
      builder->add_boolean(
        result-coordinator_outcome-recorded
      ).

      builder->add_member( 'skipReason' ).
      builder->add_string(
        result-coordinator_outcome-skip_reason
      ).

      builder->add_member( 'finalState' ).
      builder->add_string(
        result-coordinator_outcome-final_state
      ).

      builder->end_object( ).

    ENDIF.

    builder->end_object( ).

    json =
      builder->get_data( )->to_string( ).

  ENDMETHOD.


  METHOD error_json.

    DATA(builder) =
      xco_cp_json=>data->builder( ).

    builder->begin_object( ).

    builder->add_member( 'error' ).
    builder->add_string( code ).

    builder->add_member( 'message' ).
    builder->add_string( message ).

    builder->end_object( ).

    json =
      builder->get_data( )->to_string( ).

  ENDMETHOD.


  METHOD respond.

    response->set_status(
      i_code = status
    ).

    response->set_content_type(
      content_type = 'application/json'
    ).

    response->set_text(
      i_text = body
    ).

  ENDMETHOD.

ENDCLASS.
