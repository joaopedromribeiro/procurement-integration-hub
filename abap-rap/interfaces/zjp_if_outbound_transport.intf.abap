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
      " abap_false means the receiver never answered: a timeout, a dropped
      " connection, an unresolvable host. It does NOT mean the delivery failed.
      answered     TYPE abap_bool,
      status       TYPE i,
      body         TYPE string,
      " Safe diagnostic text for the unanswered case. Never a stack or a URL.
      failure_text TYPE string,
    END OF ty_response.

  " Returns an outcome instead of raising. Section 6.3: an exception collapses
  " "definitely not delivered" into "possibly delivered", and those two lead to
  " opposite actions. A timeout never proves non-delivery.
  METHODS post
    IMPORTING request         TYPE ty_request
    RETURNING VALUE(response) TYPE ty_response.

ENDINTERFACE.
