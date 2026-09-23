" Phase 7.7 read-only outbound operational status.
" No EML mutation and no HTTP.

CLASS zjp_cl_delivery_status DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zjp_cl_delivery_status IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    GET TIME STAMP FIELD DATA(now).

    SELECT delivery_uuid,
           purchase_order_uuid,
           dispatch_state,
           attempt_count,
           next_attempt_at,
           retry_window_started_at,
           lease_owner,
           lease_expires_at,
           last_correlation_id
      FROM zjp_po_dlv
      ORDER BY dispatch_state,
               next_attempt_at,
               delivery_uuid
      INTO TABLE @DATA(rows).

    DATA pending   TYPE i.
    DATA in_flight TYPE i.
    DATA delivered TYPE i.
    DATA failed    TYPE i.
    DATA unknown   TYPE i.
    DATA live      TYPE i.
    DATA stale     TYPE i.

    out->write(
      |=== Phase 7.7 delivery status ({ lines( rows ) } rows) ===|
    ).

    LOOP AT rows INTO DATA(row).

      DATA(lease_state) = CONV string( '-' ).

      CASE row-dispatch_state.

        WHEN 'PENDING'.
          pending += 1.

        WHEN 'IN_FLIGHT'.

          in_flight += 1.

          IF row-lease_expires_at IS NOT INITIAL
             AND row-lease_expires_at > now.

            lease_state = 'LIVE'.
            live += 1.

          ELSE.

            lease_state = 'STALE'.
            stale += 1.

          ENDIF.

        WHEN 'DELIVERED'.
          delivered += 1.

        WHEN 'FAILED'.
          failed += 1.

        WHEN 'UNKNOWN'.
          unknown += 1.

      ENDCASE.

      out->write(
        |state={ row-dispatch_state } attempts={ row-attempt_count } | &&
        |next={ row-next_attempt_at } window={ row-retry_window_started_at } | &&
        |lease={ lease_state } expires={ row-lease_expires_at }|
      ).

      out->write(
        name = 'DeliveryUUID'
        data = row-delivery_uuid
      ).

      out->write(
        name = 'PurchaseOrderUUID'
        data = row-purchase_order_uuid
      ).

      out->write(
        name = 'LeaseOwner'
        data = row-lease_owner
      ).

      out->write(
        name = 'LastCorrelationId'
        data = row-last_correlation_id
      ).

    ENDLOOP.

    out->write(
      |CENSUS PENDING={ pending } IN_FLIGHT={ in_flight } | &&
      |DELIVERED={ delivered } FAILED={ failed } UNKNOWN={ unknown }|
    ).

    out->write(
      |LEASES LIVE={ live } STALE={ stale }|
    ).


  ENDMETHOD.

ENDCLASS.