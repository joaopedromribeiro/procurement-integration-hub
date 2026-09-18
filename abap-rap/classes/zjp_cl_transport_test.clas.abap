" Phase 5.2c - console runtime harness for the outbound transport seam.
"
" A dedicated test object by explicit decision, recorded in the Phase 5.1 guide
" section 10.1. ZJP_CL_PO_EML_TEST was not used because Phase 5.2c changes no RAP
" behavior, and ZJP_CL_PO_DISPATCH_TEST stays reserved for the Phase 5.2g
" coordinator. This class verifies the seam and its fake, and nothing else.
"
" It is pure in-process ABAP: no HTTP client, no destination, no OAuth artefact,
" no CAP URL, no SQL, no EML, no COMMIT and no ROLLBACK. There is nothing here to
" commit - the fake touches no database.
"
" Every scenario is driven through REF TO ZJP_IF_OUTBOUND_TRANSPORT. The concrete
" class is named exactly once per scenario, at construction, and never called
" through afterwards. That is the point: the runtime evidence has to prove the
" interface seam works, not that a class with the right methods exists.
CLASS zjp_cl_transport_test DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    DATA console TYPE REF TO if_oo_adt_classrun_out.

    " One harmless synthetic request, reused by every scenario. The fake accepts
    " it and ignores it; nothing parses the body, and nothing may start to,
    " because payload shape is a Phase 5.2d concern.
    METHODS synthetic_request
      RETURNING VALUE(request) TYPE zjp_if_outbound_transport=>ty_request.

    METHODS test_created
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_replayed
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_conflict
      RETURNING VALUE(success) TYPE abap_bool.

    METHODS test_unanswered
      RETURNING VALUE(success) TYPE abap_bool.

ENDCLASS.


CLASS zjp_cl_transport_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    console = out.

    out->write( '=== Phase 5.2c - outbound transport abstraction ===' ).
    out->write( 'The fake is pure in-process ABAP. No request leaves this system.' ).

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

    out->write( 'PASS: Phase 5.2c outbound transport abstraction verified.' ).

  ENDMETHOD.


  METHOD synthetic_request.

    request-path = '/rest/integration/v1/Orders'.

    " A header is carried only to prove ty_headers compiles and survives the
    " call. The values are synthetic and no scenario depends on them.
    request-headers = VALUE #(
      ( name = 'Content-Type' value = 'application/json' ) ).

    request-body = '{"probe":"phase-5-2c"}'.

  ENDMETHOD.


  METHOD test_created.

    success = abap_false.

    " Interface-typed reference. The concrete class appears here and nowhere
    " else in this method.
    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = NEW zjp_cl_transport_fake(
                      for_scenario = zjp_cl_transport_fake=>scenario-created ).

    DATA(response) = transport->post( synthetic_request( ) ).

    console->write( name = 'CREATED response' data = response ).

    IF response-answered <> abap_true.
      console->write( 'STOP: CREATED expected answered=true.' ).
      RETURN.
    ENDIF.

    IF response-status <> 201.
      console->write( 'STOP: CREATED expected status=201.' ).
      RETURN.
    ENDIF.

    IF response-body IS INITIAL.
      console->write( 'STOP: CREATED expected a non-initial receipt body.' ).
      RETURN.
    ENDIF.

    IF response-failure_text IS NOT INITIAL.
      console->write( 'STOP: CREATED expected an initial failure_text; an answered call has no technical failure.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: fake transport CREATED returned answered=true, status=201.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_replayed.

    success = abap_false.

    " This scenario needs the CREATED body to compare against, so it builds its
    " own CREATED instance rather than reading state left behind by the previous
    " test. Each scenario therefore stands alone, and the comparison proves
    " something extra for free: two independently constructed fakes produce the
    " same receipt, so the determinism is a property of the class, not of one
    " instance's history.
    DATA reference TYPE REF TO zjp_if_outbound_transport.
    reference = NEW zjp_cl_transport_fake(
                      for_scenario = zjp_cl_transport_fake=>scenario-created ).

    DATA(created_response) = reference->post( synthetic_request( ) ).

    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = NEW zjp_cl_transport_fake(
                      for_scenario = zjp_cl_transport_fake=>scenario-replayed ).

    DATA(response) = transport->post( synthetic_request( ) ).

    console->write( name = 'REPLAYED response' data = response ).

    IF response-answered <> abap_true.
      console->write( 'STOP: REPLAYED expected answered=true.' ).
      RETURN.
    ENDIF.

    IF response-status <> 200.
      console->write( 'STOP: REPLAYED expected status=200.' ).
      RETURN.
    ENDIF.

    IF response-body IS INITIAL.
      console->write( 'STOP: REPLAYED expected a non-initial receipt body.' ).
      RETURN.
    ENDIF.

    IF response-failure_text IS NOT INITIAL.
      console->write( 'STOP: REPLAYED expected an initial failure_text.' ).
      RETURN.
    ENDIF.

    " CAP returns the STORED ORIGINAL receipt on an exact replay - same
    " portalOrderId, same receivedAt - which is what makes a replay safe and why
    " the receipt interpretation table handles 200 and 201 identically. The fake
    " models that, so the two bodies must be equal.
    IF response-body <> created_response-body.
      console->write( 'STOP: REPLAYED body differs from the CREATED body; the fake is not modelling an idempotent replay.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: fake transport REPLAYED returned status=200 with the original receipt body.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_conflict.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = NEW zjp_cl_transport_fake(
                      for_scenario = zjp_cl_transport_fake=>scenario-conflict ).

    DATA(response) = transport->post( synthetic_request( ) ).

    console->write( name = 'CONFLICT response' data = response ).

    IF response-answered <> abap_true.
      console->write( 'STOP: CONFLICT expected answered=true; a 409 is an answer, not a technical failure.' ).
      RETURN.
    ENDIF.

    IF response-status <> 409.
      console->write( 'STOP: CONFLICT expected status=409.' ).
      RETURN.
    ENDIF.

    IF response-failure_text IS NOT INITIAL.
      console->write( 'STOP: CONFLICT expected an initial failure_text.' ).
      RETURN.
    ENDIF.

    " One safe deterministic property of the body, checked with the CS
    " comparison operator rather than by parsing. No JSON reader is introduced
    " here: reading a body belongs to Phase 5.2d and 5.2f.
    IF NOT response-body CS 'DELIVERY_PAYLOAD_CONFLICT'.
      console->write( 'STOP: CONFLICT body does not carry DELIVERY_PAYLOAD_CONFLICT.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: fake transport CONFLICT returned answered=true, status=409.' ).
    success = abap_true.

  ENDMETHOD.


  METHOD test_unanswered.

    success = abap_false.

    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = NEW zjp_cl_transport_fake(
                      for_scenario = zjp_cl_transport_fake=>scenario-unanswered ).

    DATA(response) = transport->post( synthetic_request( ) ).

    console->write( name = 'UNANSWERED response' data = response ).

    " This is the distinction the whole interface exists to preserve: the
    " receiver never replied, which is NOT the same as the delivery failing.
    " A timeout never proves non-delivery.
    IF response-answered <> abap_false.
      console->write( 'STOP: UNANSWERED expected answered=false.' ).
      RETURN.
    ENDIF.

    IF response-status <> 0.
      console->write( 'STOP: UNANSWERED expected status=0; there was no reply to carry a status.' ).
      RETURN.
    ENDIF.

    IF response-body IS NOT INITIAL.
      console->write( 'STOP: UNANSWERED expected an initial body.' ).
      RETURN.
    ENDIF.

    IF response-failure_text IS INITIAL.
      console->write( 'STOP: UNANSWERED expected diagnostic failure_text.' ).
      RETURN.
    ENDIF.

    console->write( 'PASS: fake transport UNANSWERED returned a deterministic technical failure outcome.' ).
    success = abap_true.

  ENDMETHOD.

ENDCLASS.
