" Phase 5.2c - deterministic fake transport, object 6 of the Phase 5.1 section 10
" inventory: "Scripted 201 / 200 / 409 / timeout for tests; no network".
"
" Pure in-process ABAP. It opens no connection, names no destination, and
" references no HTTP, OAuth or CAP artefact. The request is accepted and
" deliberately ignored - correlating a receipt with the delivery that was sent
" needs JSON parsing, which belongs to the builder and mapper in Phase 5.2d and
" to sendToSupplier in Phase 5.2f, not to the transport seam.
"
" Every scenario returns fixed values so a test can assert exact outcomes.
CLASS zjp_cl_transport_fake DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zjp_if_outbound_transport.

    " The four scenarios the inventory requires. Callers use these constants
    " rather than literals: zjp_cl_transport_fake=>scenario-created.
    CONSTANTS:
      BEGIN OF scenario,
        " 201 - CAP accepted a new delivery and returned a receipt.
        created    TYPE string VALUE 'CREATED',
        " 200 - an exact replay, answered with the stored ORIGINAL receipt.
        replayed   TYPE string VALUE 'REPLAYED',
        " 409 - the delivery id was reused with different content.
        conflict   TYPE string VALUE 'CONFLICT',
        " The receiver never answered. Not a failed delivery - an unknown one.
        unanswered TYPE string VALUE 'UNANSWERED',
      END OF scenario.

    " Configuration is constructor injection and nothing else: one instance is
    " one scripted outcome, immutable for its lifetime, so a test that drives
    " four scenarios creates four instances and no call can be influenced by a
    " previous one. No factory, no registry, no setter.
    METHODS constructor
      IMPORTING for_scenario TYPE string.

  PRIVATE SECTION.
    DATA active_scenario TYPE string.

    " The receipt body of a successful ingestion. Shape taken from API_CONTRACTS
    " and runtime-verified twice - locally in Phase 4.3 and against deployed HANA
    " in Phase 5.1, which returned 201 RECEIVED. The identifiers are fixed
    " fixtures, NOT echoes of the request; see the class comment.
    METHODS receipt_body
      RETURNING VALUE(body) TYPE string.

    " The 409 body, in the API_CONTRACTS error envelope. DELIVERY_PAYLOAD_CONFLICT
    " is the code CAP actually returned to SAP in the Phase 5.1 outbound probe.
    METHODS conflict_body
      RETURNING VALUE(body) TYPE string.

ENDCLASS.


CLASS zjp_cl_transport_fake IMPLEMENTATION.

  METHOD constructor.
    active_scenario = for_scenario.
  ENDMETHOD.


  METHOD zjp_if_outbound_transport~post.

    " request is intentionally unused. The seam transports what it is given; in
    " 5.2c there is nowhere for it to go.

    CASE active_scenario.

      WHEN scenario-created.
        response-answered = abap_true.
        response-status   = 201.
        response-body     = receipt_body( ).

      WHEN scenario-replayed.
        " Same body as CREATED, different status. That is the whole point of a
        " replay: Phase 4.3 verified that an exact resend returns the stored
        " original receipt, with the same portalOrderId and receivedAt, so the
        " caller may handle 200 and 201 identically. A test can assert that the
        " two bodies are equal.
        response-answered = abap_true.
        response-status   = 200.
        response-body     = receipt_body( ).

      WHEN scenario-conflict.
        response-answered = abap_true.
        response-status   = 409.
        response-body     = conflict_body( ).

      WHEN scenario-unanswered.
        " answered = abap_false is the one distinction this interface exists to
        " preserve. status stays 0 and body stays empty because there was no
        " reply to carry a status or a body. failure_text is safe diagnostic
        " text: no stack, no URL, no destination name.
        response-answered    = abap_false.
        response-status      = 0.
        response-failure_text = 'Fake transport: the receiver did not answer.'.

      WHEN OTHERS.
        " A misconfigured test must fail loudly and deterministically rather
        " than silently resembling a success. Reported through the same outcome
        " record instead of an exception, so the fake needs no exception class
        " and stays free of any released API.
        response-answered    = abap_false.
        response-status      = 0.
        response-failure_text = 'Fake transport: unknown scenario configured: '
                                && active_scenario.

    ENDCASE.

  ENDMETHOD.


  METHOD receipt_body.
    body = '{"deliveryId":"00000000-0000-0000-0000-000000000001",'
        && '"sourceOrderId":"00000000-0000-0000-0000-000000000002",'
        && '"portalOrderId":"00000000-0000-0000-0000-000000000003",'
        && '"status":"RECEIVED",'
        && '"receivedAt":"2026-01-01T00:00:00Z"}'.
  ENDMETHOD.


  METHOD conflict_body.
    body = '{"error":{"code":"DELIVERY_PAYLOAD_CONFLICT",'
        && '"message":"deliveryId 00000000-0000-0000-0000-000000000001 was '
        && 'already accepted with different content. The stored order is '
        && 'unchanged; use a new deliveryId for a corrected snapshot.",'
        && '"correlationId":"00000000-0000-0000-0000-000000000004",'
        && '"retryable":false}}'.
  ENDMETHOD.

ENDCLASS.
