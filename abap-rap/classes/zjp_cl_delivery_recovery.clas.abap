" Phase 7.6 production recovery runner for exactly one UNKNOWN delivery.
"
" The runner refuses unless the system contains exactly one UNKNOWN intent.
" It invokes the EML-only retryDelivery action and commits that preparation,
" then calls the existing coordinator exactly once for the selected DeliveryUUID.
" No loop, no bulk recovery, no sendToSupplier and no new delivery identity.
CLASS zjp_cl_delivery_recovery DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS destination   TYPE rfcdest VALUE 'ZJP_CI_ORDER_DELIVERY'.
    CONSTANTS lease_seconds TYPE i VALUE 300.
ENDCLASS.


CLASS zjp_cl_delivery_recovery IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    out->write( '=== Phase 7.6 single UNKNOWN delivery recovery ===' ).
    out->write( 'This run makes at most one HTTP POST and never creates an intent.' ).

    SELECT delivery_uuid, purchase_order_uuid, order_revision
      FROM zjp_po_dlv
      WHERE dispatch_state = 'UNKNOWN'
      INTO TABLE @DATA(candidates).

    IF lines( candidates ) <> 1.
      out->write( |STOP: expected exactly one UNKNOWN intent; found { lines( candidates ) }.| ).
      out->write( 'Use read-only status evidence to resolve the selection; nothing changed.' ).
      RETURN.
    ENDIF.

    DATA(candidate) = candidates[ 1 ].
    out->write( name = 'Selected DeliveryUUID' data = candidate-delivery_uuid ).
    out->write( name = 'Selected PurchaseOrderUUID' data = candidate-purchase_order_uuid ).

    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        FIELDS ( PurchaseOrderUUID Status IntegrationStatus DeliveryId OrderRevision )
        WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                        PurchaseOrderUUID = candidate-purchase_order_uuid ) )
        RESULT DATA(orders)
      FAILED DATA(failed_read)
      REPORTED DATA(reported_read).

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1.
      out->write( name = 'Read REPORTED' data = reported_read ).
      out->write( 'STOP: the active owning order could not be read; nothing changed.' ).
      RETURN.
    ENDIF.

    DATA(order) = orders[ 1 ].
    IF order-DeliveryId <> candidate-delivery_uuid
       OR order-OrderRevision <> candidate-order_revision
       OR order-Status <> 'ERROR'
       OR order-IntegrationStatus <> 'UNKNOWN'.
      out->write( 'STOP: the UNKNOWN intent is not the current ERROR/UNKNOWN delivery.' ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        EXECUTE retryDelivery FROM VALUE #( ( %tky = order-%tky ) )
      FAILED DATA(failed_retry)
      REPORTED DATA(reported_retry).

    IF failed_retry IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( name = 'retryDelivery REPORTED' data = reported_retry ).
      out->write( 'STOP: recovery preparation was refused; nothing committed or sent.' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ZJP_I_PurchaseOrder
      FAILED DATA(failed_save)
      REPORTED DATA(reported_save).
    DATA(save_subrc) = sy-subrc.

    IF save_subrc <> 0 OR failed_save IS NOT INITIAL.
      ROLLBACK ENTITIES.
      out->write( name = 'Save REPORTED' data = reported_save ).
      out->write( 'STOP: recovery preparation did not commit; nothing sent.' ).
      RETURN.
    ENDIF.

    " Re-read the exact intent after commit. A terminal result that won the race
    " makes this gate refuse before the network; the coordinator also claims by key.
    SELECT SINGLE dispatch_state FROM zjp_po_dlv
      WHERE delivery_uuid = @candidate-delivery_uuid INTO @DATA(prepared_state).
    IF sy-subrc <> 0 OR prepared_state <> 'PENDING'.
      out->write( |STOP: selected intent is now { prepared_state }, not PENDING; nothing sent.| ).
      RETURN.
    ENDIF.

    DATA transport TYPE REF TO zjp_if_outbound_transport.
    transport = NEW zjp_cl_outbound_transport( destination_name = destination ).
    DATA(coordinator) = NEW zjp_cl_dispatch_coordinator(
      transport     = transport
      lease_seconds = lease_seconds ).

    " Exactly one call, for exactly the identity selected before preparation.
    DATA(outcome) = coordinator->run_once( candidate-delivery_uuid ).

    out->write( |claimed={ outcome-claimed } dispatched={ outcome-dispatched } | &&
                |answered={ outcome-answered } http={ outcome-http_status }| ).
    out->write( |state={ outcome-final_state } attempts={ outcome-attempt_count } | &&
                |recorded={ outcome-recorded } skip={ outcome-skip_reason }| ).
    out->write( name = 'CorrelationId' data = outcome-correlation_uuid ).
    out->write( name = 'PortalOrderUUID' data = outcome-portal_order_uuid ).
  ENDMETHOD.

ENDCLASS.
