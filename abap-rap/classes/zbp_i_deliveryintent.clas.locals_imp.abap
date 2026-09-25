CLASS ltc_delivery_event DEFINITION DEFERRED FOR TESTING.

CLASS lsc_DeliveryIntent DEFINITION
  INHERITING FROM cl_abap_behavior_saver
  FRIENDS ltc_delivery_event.

  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.

CLASS lhc_DeliveryIntent DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR DeliveryIntent
      RESULT result.
ENDCLASS.

CLASS lsc_DeliveryIntent IMPLEMENTATION.
  METHOD save_modified.
    IF create-deliveryintent IS NOT INITIAL.
      RAISE ENTITY EVENT
        ZJP_I_DeliveryIntent~PurchaseOrderDeliveryRequested
        FROM VALUE #(
          FOR delivery_intent IN create-deliveryintent
          (
            DeliveryUUID = delivery_intent-DeliveryUUID
            %param = VALUE #(
              PurchaseOrderUUID = delivery_intent-PurchaseOrderUUID
              OrderRevision     = delivery_intent-OrderRevision
              PayloadHash       = delivery_intent-PayloadHash
            )
          )
        ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS lhc_DeliveryIntent IMPLEMENTATION.
  METHOD get_instance_authorizations.
    " Phase 5.2b skeleton. The BDEF declares `authorization master ( instance )`,
    " so this method is the one thing the behavior pool is obliged to implement;
    " everything else the managed framework handles without handler code.
    "
    " Deliberately empty of business logic. The claim-under-lease and
    " state-transition handlers this pool will eventually carry belong to later
    " slices, and no action, validation or determination is declared yet — an
    " intent is created with its values already decided by its creator, and
    " nothing in 5.2b advances one.
    READ ENTITIES OF ZJP_I_DeliveryIntent IN LOCAL MODE
      ENTITY DeliveryIntent
      FIELDS ( DeliveryUUID ) WITH CORRESPONDING #( keys )
      RESULT DATA(delivery_intents)
      FAILED failed
      REPORTED reported.

    SORT delivery_intents BY %tky.
    DELETE ADJACENT DUPLICATES FROM delivery_intents COMPARING %tky.

    DATA authorization_result LIKE LINE OF result.

    LOOP AT delivery_intents INTO DATA(delivery_intent).
      CLEAR authorization_result.
      authorization_result-%tky = delivery_intent-%tky.

      " Study-only permissive policy, consistent with the existing
      " PurchaseOrder stub; replace with actual business authorization.
      IF requested_authorizations-%update = if_abap_behv=>mk-on.
        authorization_result-%update = if_abap_behv=>auth-allowed.
      ENDIF.

      IF requested_authorizations-%delete = if_abap_behv=>mk-on.
        authorization_result-%delete = if_abap_behv=>auth-allowed.
      ENDIF.

      APPEND authorization_result TO result.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
