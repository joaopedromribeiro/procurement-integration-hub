" Phase 9.5A. Exactly one explicit-identity coordinator invocation.
INTERFACE zjp_if_event_dispatcher PUBLIC.
  METHODS run_once
    IMPORTING delivery_uuid TYPE sysuuid_x16
    RETURNING VALUE(outcome) TYPE zjp_cl_dispatch_coordinator=>ty_outcome.
ENDINTERFACE.
