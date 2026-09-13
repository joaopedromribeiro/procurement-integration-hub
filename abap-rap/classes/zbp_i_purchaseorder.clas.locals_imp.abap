CLASS lhc_PurchaseOrder DEFINITION
  INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR PurchaseOrder
      RESULT result.
ENDCLASS.

CLASS lhc_PurchaseOrder IMPLEMENTATION.
  METHOD get_instance_authorizations.
    READ ENTITIES OF ZJP_I_PurchaseOrder IN LOCAL MODE
      ENTITY PurchaseOrder
      FIELDS ( PurchaseOrderUUID ) WITH CORRESPONDING #( keys )
      RESULT DATA(purchase_orders)
      FAILED failed
      REPORTED reported.

    SORT purchase_orders BY %tky.
    DELETE ADJACENT DUPLICATES FROM purchase_orders COMPARING %tky.

    DATA authorization_result LIKE LINE OF result.

    LOOP AT purchase_orders INTO DATA(purchase_order).
      CLEAR authorization_result.
      authorization_result-%tky = purchase_order-%tky.

      " Study-only permissive policy; replace with actual business authorization.
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
