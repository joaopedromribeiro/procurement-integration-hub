" Phase 5.2c - the outbound transport seam.
"
" This interface is the boundary between business code and the network. It
" represents transporting an ALREADY PREPARED request and returning what came
" back. It knows nothing about PurchaseOrder rules, DeliveryIntent, OrderRevision,
" the commercial snapshot, payload hashing or RAP entities, and it neither
" commits nor rolls back.
"
" It uses nothing but abap_bool and built-in types on purpose, so it carries no
" dependency on any released API and compiles on both sides of the ABAP Cloud /
" Standard ABAP boundary. ZJP_CL_OUTBOUND_TRANSPORT (Phase 5.2e) is intended to
" be the only object in the design that touches an HTTP client class.
"
" Source of the contract: Phase 5.1 guide, sections 6.1 to 6.4, object 5 of the
" section 10 inventory. Implemented here as specified, unchanged.
INTERFACE zjp_if_outbound_transport
  PUBLIC.

  CONSTANTS:
    co_certainty_not_sent TYPE string VALUE 'NOT_SENT',
    co_certainty_may_apply TYPE string VALUE 'MAY_APPLY'.

  TYPES:

    BEGIN OF ty_header,

      name  TYPE string,
      value TYPE string,

    END OF ty_header,

    ty_headers TYPE STANDARD TABLE OF ty_header WITH EMPTY KEY.

  TYPES:

    BEGIN OF ty_request,

      " Path only. The base URL and its credentials belong to the destination
      " configuration, never to business code.
      path    TYPE string,

      headers TYPE ty_headers,

      body    TYPE string,

    END OF ty_request.

  TYPES:

    BEGIN OF ty_response,

      " abap_true means an HTTP response was received and status is authoritative.
      " abap_false means no HTTP response was received.
      answered     TYPE abap_bool,

      status       TYPE i,

      body         TYPE string,

      " Meaningful only when answered = abap_false.
      "
      " NOT_SENT  = transport can prove the request was not dispatched.
      " MAY_APPLY = transport cannot rule out that the receiver may have applied it.
      "
      " Initial, unknown or future values must be treated conservatively by the
      " caller as MAY_APPLY.
      certainty    TYPE string,

      " Raw Retry-After response-header value.
      "
      " Meaningful only for answered HTTP responses. The transport extracts it
      " but does not interpret it. Retry policy decides whether/how to consume it.
      "
      " No arbitrary response headers are exposed through this seam.
      retry_after  TYPE string,

      " Safe diagnostic text for unanswered transport failures.
      " Never a stack, URL, credentials or raw exception dump.
      failure_text TYPE string,

    END OF ty_response.

  " Returns an outcome instead of raising transport exceptions.
  "
  " The transport reports delivery certainty only where it can prove it.
  " Business classification and retry policy remain outside this interface.
  METHODS post

    IMPORTING request         TYPE ty_request

    RETURNING VALUE(response) TYPE ty_response.

ENDINTERFACE.