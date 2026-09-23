" Phase 5.2c / Phase 7.4c - console runtime harness for the outbound
" transport seam.
"
" Pure in-process ABAP:
" - no HTTP client
" - no destination
" - no OAuth artefact
" - no CAP URL
" - no SQL
" - no EML
" - no COMMIT
" - no ROLLBACK
"
" Phase 7.4c extends the seam evidence with:
" - explicit MAY_APPLY
" - explicit NOT_SENT
" - raw Retry-After
" - initial/unknown certainty fallback fixture

CLASS zjp_cl_transport_test DEFINITION

  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.

    DATA console TYPE REF TO if_oo_adt_classrun_out.

    METHODS synthetic_request
      RETURNING VALUE(request)
        TYPE zjp_if_outbound_transport=>ty_request.

    METHODS test_created
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_replayed
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_conflict
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_unanswered
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_not_sent
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_retry_after
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_unknown_certainty
      RETURNING VALUE(success) TYPE abap_bool.

ENDCLASS.


CLASS zjp_cl_transport_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write(
      '=== Phase 7.4c - outbound transport abstraction ==='
    ).

    out->write(
      'The fake is pure in-process ABAP. No request leaves this system.'
    ).

    IF test_created( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_replayed( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_conflict( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_unanswered( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_not_sent( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_retry_after( ) = abap_false.
      RETURN.
    ENDIF.

    IF test_unknown_certainty( ) = abap_false.
      RETURN.
    ENDIF.

    out->write(
      'PASS: Phase 7.4c transport seam verified.'
    ).

  ENDMETHOD.


  METHOD synthetic_request.

    request-path = '/rest/integration/v1/Orders'.

    " Synthetic request only. The fake accepts and ignores it.
    request-headers = VALUE #(
      ( name = 'Content-Type'
        value = 'application/json' )
    ).

    request-body = '{"probe":"phase-7-4c"}'.

  ENDMETHOD.


  METHOD test_created.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-created
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'CREATED response'
      data = response
    ).

    IF response-answered <> abap_true.

      console->write(
        'STOP: CREATED expected answered=true.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 201.

      console->write(
        'STOP: CREATED expected status=201.'
      ).

      RETURN.

    ENDIF.

    IF response-body IS INITIAL.

      console->write(
        'STOP: CREATED expected a non-initial receipt body.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS NOT INITIAL.

      console->write(
        'STOP: CREATED expected an initial failure_text.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty IS NOT INITIAL.

      console->write(
        'STOP: CREATED answered response should not require certainty.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after IS NOT INITIAL.

      console->write(
        'STOP: CREATED must not carry Retry-After.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: CREATED returned answered=true, status=201.'
    ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_replayed.

    success = abap_false.

    DATA reference TYPE REF TO zjp_if_outbound_transport.

    reference = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-created
    ).

    DATA(created_response) = reference->post(
      synthetic_request( )
    ).

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-replayed
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'REPLAYED response'
      data = response
    ).

    IF response-answered <> abap_true.

      console->write(
        'STOP: REPLAYED expected answered=true.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 200.

      console->write(
        'STOP: REPLAYED expected status=200.'
      ).

      RETURN.

    ENDIF.

    IF response-body IS INITIAL.

      console->write(
        'STOP: REPLAYED expected a non-initial receipt body.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS NOT INITIAL.

      console->write(
        'STOP: REPLAYED expected an initial failure_text.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty IS NOT INITIAL.

      console->write(
        'STOP: REPLAYED answered response should not require certainty.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after IS NOT INITIAL.

      console->write(
        'STOP: REPLAYED must not carry Retry-After.'
      ).

      RETURN.

    ENDIF.

    IF response-body <> created_response-body.

      console->write(
        'STOP: REPLAYED body differs from the CREATED body.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: REPLAYED returned status=200 with the original receipt body.'
    ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_conflict.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-conflict
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'CONFLICT response'
      data = response
    ).

    IF response-answered <> abap_true.

      console->write(
        'STOP: CONFLICT expected answered=true.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 409.

      console->write(
        'STOP: CONFLICT expected status=409.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS NOT INITIAL.

      console->write(
        'STOP: CONFLICT expected an initial failure_text.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty IS NOT INITIAL.

      console->write(
        'STOP: CONFLICT answered response should not require certainty.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after IS NOT INITIAL.

      console->write(
        'STOP: CONFLICT must not carry Retry-After.'
      ).

      RETURN.

    ENDIF.

    IF NOT response-body CS 'DELIVERY_PAYLOAD_CONFLICT'.

      console->write(
        'STOP: CONFLICT body does not carry DELIVERY_PAYLOAD_CONFLICT.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: CONFLICT returned answered=true, status=409.'
    ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_unanswered.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-unanswered
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'UNANSWERED response'
      data = response
    ).

    IF response-answered <> abap_false.

      console->write(
        'STOP: UNANSWERED expected answered=false.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 0.

      console->write(
        'STOP: UNANSWERED expected status=0.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty
       <> zjp_if_outbound_transport=>co_certainty_may_apply.

      console->write(
        'STOP: UNANSWERED expected certainty=MAY_APPLY.'
      ).

      RETURN.

    ENDIF.

    IF response-body IS NOT INITIAL.

      console->write(
        'STOP: UNANSWERED expected an initial body.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after IS NOT INITIAL.

      console->write(
        'STOP: UNANSWERED must not carry Retry-After.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS INITIAL.

      console->write(
        'STOP: UNANSWERED expected diagnostic failure_text.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: UNANSWERED returned answered=false, certainty=MAY_APPLY.'
    ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_not_sent.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-not_sent
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'NOT_SENT response'
      data = response
    ).

    IF response-answered <> abap_false.

      console->write(
        'STOP: NOT_SENT expected answered=false.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 0.

      console->write(
        'STOP: NOT_SENT expected status=0.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty
       <> zjp_if_outbound_transport=>co_certainty_not_sent.

      console->write(
        'STOP: NOT_SENT expected certainty=NOT_SENT.'
      ).

      RETURN.

    ENDIF.

    IF response-body IS NOT INITIAL.

      console->write(
        'STOP: NOT_SENT expected an initial body.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after IS NOT INITIAL.

      console->write(
        'STOP: NOT_SENT must not carry Retry-After.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS INITIAL.

      console->write(
        'STOP: NOT_SENT expected safe diagnostic text.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: NOT_SENT returned answered=false, certainty=NOT_SENT.'
    ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_retry_after.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = zjp_cl_transport_fake=>scenario-retry_after
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'RETRY_AFTER response'
      data = response
    ).

    IF response-answered <> abap_true.

      console->write(
        'STOP: RETRY_AFTER expected answered=true.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 503.

      console->write(
        'STOP: RETRY_AFTER expected status=503.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after <> '120'.

      console->write(
        'STOP: RETRY_AFTER expected raw value 120.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty IS NOT INITIAL.

      console->write(
        'STOP: RETRY_AFTER answered response should not require certainty.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS NOT INITIAL.

      console->write(
        'STOP: RETRY_AFTER expected initial failure_text.'
      ).

      RETURN.

    ENDIF.

    IF response-body IS INITIAL.

      console->write(
        'STOP: RETRY_AFTER expected a technical error body.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: RETRY_AFTER returned answered=true, status=503, raw Retry-After=120.'
    ).

    success = abap_true.

  ENDMETHOD.


  METHOD test_unknown_certainty.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.

    transport = NEW zjp_cl_transport_fake(
      for_scenario = 'UNKNOWN_SCENARIO'
    ).

    DATA(response) = transport->post(
      synthetic_request( )
    ).

    console->write(
      name = 'UNKNOWN certainty response'
      data = response
    ).

    IF response-answered <> abap_false.

      console->write(
        'STOP: UNKNOWN scenario expected answered=false.'
      ).

      RETURN.

    ENDIF.

    IF response-status <> 0.

      console->write(
        'STOP: UNKNOWN scenario expected status=0.'
      ).

      RETURN.

    ENDIF.

    IF response-certainty IS NOT INITIAL.

      console->write(
        'STOP: UNKNOWN scenario expected initial certainty.'
      ).

      RETURN.

    ENDIF.

    IF response-body IS NOT INITIAL.

      console->write(
        'STOP: UNKNOWN scenario expected an initial body.'
      ).

      RETURN.

    ENDIF.

    IF response-retry_after IS NOT INITIAL.

      console->write(
        'STOP: UNKNOWN scenario must not carry Retry-After.'
      ).

      RETURN.

    ENDIF.

    IF response-failure_text IS INITIAL.

      console->write(
        'STOP: UNKNOWN scenario expected diagnostic failure_text.'
      ).

      RETURN.

    ENDIF.

    console->write(
      'PASS: UNKNOWN scenario preserves initial certainty.'
    ).

    success = abap_true.

  ENDMETHOD.

ENDCLASS.