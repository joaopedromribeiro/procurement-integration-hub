" Phase 9.5A. Production seam; the Phase 7 coordinator retains every side effect.
CLASS zjp_cl_event_dispatcher DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zjp_if_event_dispatcher.
    METHODS constructor
      IMPORTING transport     TYPE REF TO zjp_if_outbound_transport
                lease_seconds TYPE i.
  PRIVATE SECTION.
    DATA coordinator TYPE REF TO zjp_cl_dispatch_coordinator.
ENDCLASS.

CLASS zjp_cl_event_dispatcher IMPLEMENTATION.
  METHOD constructor.
    coordinator = NEW zjp_cl_dispatch_coordinator(
      transport     = transport
      lease_seconds = lease_seconds ).
  ENDMETHOD.

  METHOD zjp_if_event_dispatcher~run_once.
    outcome = coordinator->run_once( delivery_uuid ).
  ENDMETHOD.
ENDCLASS.
