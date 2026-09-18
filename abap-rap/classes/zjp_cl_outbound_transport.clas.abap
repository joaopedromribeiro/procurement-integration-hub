" Phase 5.2e - the real HTTP transport, object 7 of the Phase 5.1 section 10
" inventory. It implements the verified ZJP_IF_OUTBOUND_TRANSPORT seam and does
" exactly one thing: execute a synchronous HTTP POST and report what came back.
"
" This is the ONLY object in the design permitted to touch an HTTP API, which is
" what lets every other object stay on the ABAP Cloud side of the boundary and
" depend on the interface instead of on a client class.
"
" It knows nothing about PurchaseOrder, OrderRevision, DeliveryIntent, approval,
" sendToSupplier, suppliers, CAP receipt semantics, retry policy, business status
" or the payload schema. It does not read or write the database, does not use EML,
" and performs no COMMIT or ROLLBACK. Its only side effect is the network call.
"
" Path ownership, settled by the P15 probe: the destination owns host, port, TLS
" and OAuth and carries NO application path; ZJP_IF_OUTBOUND_TRANSPORT=>TY_REQUEST
" owns the application route, applied through SET_URI_PATH. That is why no route
" is hard-coded here - the mapper supplies it.
"
" Header and body are forwarded generically. Content-Type, Idempotency-Key and a
" future X-Correlation-ID are ordinary entries in the header table, so a caller
" can add one without this class changing.
CLASS zjp_cl_outbound_transport DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zjp_if_outbound_transport.

    " Constructor injection, matching the fake's instance-configuration
    " precedent: one instance is one destination, fixed for its lifetime. No
    " factory, no registry, no configuration framework - and no destination name
    " hard-coded in post( ), so the class stays reusable and testable.
    METHODS constructor
      IMPORTING destination_name TYPE rfcdest.

  PRIVATE SECTION.
    DATA destination_name TYPE rfcdest.

    " Builds the unanswered outcome in one place, so all four fields are always
    " set consistently: answered false, status 0, body initial, failure_text set.
    METHODS unanswered
      IMPORTING text            TYPE string
      RETURNING VALUE(response) TYPE zjp_if_outbound_transport=>ty_response.

ENDCLASS.


CLASS zjp_cl_outbound_transport IMPLEMENTATION.

  METHOD constructor.
    me->destination_name = destination_name.
  ENDMETHOD.


  METHOD unanswered.
    response-answered     = abap_false.
    response-status       = 0.
    response-failure_text = text.
  ENDMETHOD.


  METHOD zjp_if_outbound_transport~post.

    DATA client TYPE REF TO if_web_http_client.

    TRY.

        DATA(destination) = cl_outbound_provider_http=>create_by_destination(
                              i_name = destination_name ).

        client = cl_web_http_client_manager=>create_by_http_destination(
                   i_destination = destination ).

        DATA(http_request) = client->get_http_request( ).

        " The route comes from the request, never from the destination and never
        " from a constant in this class.
        http_request->set_uri_path( i_uri_path = request-path ).

        " Forwarded generically. This class does not know what Content-Type or
        " Idempotency-Key mean, and must not start to.
        LOOP AT request-headers INTO DATA(header).
          http_request->set_header_field( i_name  = header-name
                                          i_value = header-value ).
        ENDLOOP.

        " Sent unchanged. No parsing, no rebuilding, no formatting.
        http_request->set_text( i_text = request-body ).

        " i_timeout is deliberately left at its API default. The repository has
        " chosen no timeout policy, and inventing one here would put a business
        " decision inside a transport adapter.
        DATA(http_response) = client->execute( i_method = if_web_http_client=>post ).

        DATA(status) = http_response->get_status( ).

        " An HTTP answer is an answer. 400, 401, 403, 404, 409, 429 and 500 all
        " arrive here with answered = abap_true, because the receiver replied.
        " This class never interprets DELIVERY_PAYLOAD_CONFLICT or any other CAP
        " code - classifying a business outcome is the caller's job.
        response-answered     = abap_true.
        response-status       = status-code.
        response-body         = http_response->get_text( ).
        response-failure_text = ``.

      CATCH cx_outbound_provider_http INTO DATA(destination_error).
        " The destination could not be resolved. Nothing was sent.
        response = unanswered( |Destination { destination_name } could not be resolved: { destination_error->get_text( ) }| ).

      CATCH cx_web_http_client_error INTO DATA(client_error).
        " Client creation or execution failed: connect, TLS or timeout. No
        " receiver answer exists.
        response = unanswered( |HTTP client error on destination { destination_name }: { client_error->get_text( ) }| ).

      CATCH cx_web_message_error INTO DATA(message_error).
        " Raised while composing the request or reading the response. Treated as
        " unanswered on purpose: section 6.3 makes the classification
        " deliberately conservative, because over-classifying as UNKNOWN costs
        " one replay - which Phase 4.3 verified is safe - while under-classifying
        " risks a duplicate order. The narrow case this concedes is a reply whose
        " status or body could not be read, which is reported as unknown rather
        " than as a status this class did not actually observe.
        response = unanswered( |HTTP message error on destination { destination_name }: { message_error->get_text( ) }| ).

    ENDTRY.

    " Cleanup is deliberately outside the classification above, and its failure
    " deliberately does NOT change the outcome. Once the receiver has answered,
    " that answer is a fact; turning it into "unanswered" because a socket could
    " not be closed would invent a non-delivery the system has evidence against,
    " and a replay of a delivery CAP already committed is exactly the failure
    " mode the outbox exists to prevent.
    IF client IS BOUND.
      TRY.
          client->close( ).
        CATCH cx_web_http_client_error.
          " Intentionally swallowed; see above.
      ENDTRY.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
