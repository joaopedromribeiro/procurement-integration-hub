" Phase 5.2e / Phase 7.4c - real HTTP transport.
"
" The class performs exactly one synchronous HTTP POST and reports the
" transport outcome through ZJP_IF_OUTBOUND_TRANSPORT.
"
" Phase 7.4c adds:
" - explicit transport certainty for unanswered calls
" - raw bounded Retry-After exposure
"
" Important:
" - EXECUTE is used exactly once.
" - RETRY_EXECUTE must never be used here because it performs hidden retries.
" - No explicit timeout is configured yet: the target API supports I_TIMEOUT,
"   but its unit has not been authoritatively established on this system.
" - Retry policy remains outside this adapter.

CLASS zjp_cl_outbound_transport DEFINITION

  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zjp_if_outbound_transport.

    METHODS constructor
      IMPORTING destination_name TYPE rfcdest.

  PRIVATE SECTION.

    DATA destination_name TYPE rfcdest.

    " Builds one consistent unanswered result.
    "
    " certainty:
    "   NOT_SENT  -> the transport can prove no request was dispatched
    "   MAY_APPLY -> the receiver may have applied the request
    METHODS unanswered
      IMPORTING
        text                 TYPE string
        certainty            TYPE string
      RETURNING
        VALUE(response)      TYPE zjp_if_outbound_transport=>ty_response.

ENDCLASS.


CLASS zjp_cl_outbound_transport IMPLEMENTATION.

  METHOD constructor.

    me->destination_name = destination_name.

  ENDMETHOD.


  METHOD unanswered.

    response-answered     = abap_false.
    response-status       = 0.
    response-certainty    = certainty.
    response-failure_text = text.

    " body and retry_after deliberately remain initial because no authoritative
    " HTTP response exists in the unanswered case.

  ENDMETHOD.


  METHOD zjp_if_outbound_transport~post.

    DATA client TYPE REF TO if_web_http_client.

    TRY.

        " Failure here is a proven pre-send failure: no HTTP request could have
        " been dispatched.
        DATA(destination) =
          cl_outbound_provider_http=>create_by_destination(
            i_name = destination_name
          ).

        client =
          cl_web_http_client_manager=>create_by_http_destination(
            i_destination = destination
          ).

        DATA(http_request) = client->get_http_request( ).

        " The route belongs to the prepared request, not to the destination.
        http_request->set_uri_path(
          i_uri_path = request-path
        ).

        " Forward request headers generically.
        LOOP AT request-headers INTO DATA(header).

          http_request->set_header_field(
            i_name  = header-name
            i_value = header-value
          ).

        ENDLOOP.

        " Forward the prepared body unchanged.
        http_request->set_text(
          i_text = request-body
        ).

        " IMPORTANT:
        " - exactly one transport attempt
        " - do NOT replace EXECUTE with RETRY_EXECUTE
        " - no explicit I_TIMEOUT until its target-system unit is proven
        DATA(http_response) =
          client->execute(
            i_method = if_web_http_client=>post
          ).

        DATA(status) = http_response->get_status( ).

        " Once a status was successfully obtained, an HTTP answer exists.
        response-answered = abap_true.
        response-status   = status-code.

        " Retry-After is optional transport metadata.
        "
        " Read only this header; do not expose all response headers.
        " Failure to read this optional header must not erase an already known
        " HTTP answer.
        DATA retry_after TYPE string.

        TRY.

            retry_after =
              http_response->get_header_field(
                i_name = 'Retry-After'
              ).

          CATCH cx_web_message_error.

            " The HTTP answer/status is already known. Retry-After is optional,
            " so an accessor failure means simply that no usable Retry-After is
            " exposed through the seam.
            CLEAR retry_after.

        ENDTRY.

        " Phase 7.4 contract:
        " - preserve the raw value
        " - maximum 128 characters
        " - overlong values are rejected entirely, never truncated
        IF retry_after IS NOT INITIAL
           AND strlen( retry_after ) <= 128.

          response-retry_after = retry_after.

        ENDIF.

        " The adapter does not interpret the body.
        response-body = http_response->get_text( ).

        " certainty is meaningful only when answered = false.
        CLEAR response-certainty.
        CLEAR response-failure_text.

      CATCH cx_outbound_provider_http INTO DATA(destination_error).

        " Proven pre-send failure. The destination could not be constructed, so
        " no HTTP request was dispatched.
        response = unanswered(
          text =
            |Destination { destination_name } could not be resolved: {
              destination_error->get_text( ) }|
          certainty =
            zjp_if_outbound_transport=>co_certainty_not_sent
        ).

      CATCH cx_web_http_client_error INTO DATA(client_error).

        " This target exposes no reliable compiler-visible discriminator for
        " connect / TLS / timeout / post-send failures.
        "
        " Therefore the entire exception family is conservatively MAY_APPLY.
        response = unanswered(
          text =
            |HTTP client error on destination { destination_name }: {
              client_error->get_text( ) }|
          certainty =
            zjp_if_outbound_transport=>co_certainty_may_apply
        ).

      CATCH cx_web_message_error INTO DATA(message_error).

        " Request composition or response processing failed.
        "
        " There is no safe target-supported discriminator proving that the
        " request was never dispatched, so this remains MAY_APPLY.
        response = unanswered(
          text =
            |HTTP message error on destination { destination_name }: {
              message_error->get_text( ) }|
          certainty =
            zjp_if_outbound_transport=>co_certainty_may_apply
        ).

    ENDTRY.

    " Cleanup never changes the transport outcome.
    IF client IS BOUND.

      TRY.

          client->close( ).

        CATCH cx_web_http_client_error.

          " Intentionally ignored.
          "
          " A close failure cannot invalidate an answer already observed and
          " must not manufacture another delivery attempt.

      ENDTRY.

    ENDIF.

  ENDMETHOD.

ENDCLASS.