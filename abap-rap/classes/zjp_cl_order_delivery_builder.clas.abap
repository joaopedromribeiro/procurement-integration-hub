" Phase 5.2d - the outbound commercial snapshot builder, object 8 of the Phase 5.1
" section 10 inventory: "RAP buffer -> source delivery DTO; no HTTP, no JSON".
"
" It reads ONE ACTIVE PurchaseOrder and its items through EML and returns the
" canonical snapshot of API_CONTRACTS' "Source order delivery". It is READ-ONLY:
" no EML MODIFY, no SQL write, no COMMIT, no ROLLBACK.
"
" The snapshot keeps SAP-NATIVE values on purpose - sysuuid_x16 stays raw, amounts
" and quantities stay numeric, ItemNumber stays NUMC, the unit stays 'EA'. Wire
" format is the mapper's job, so that Phase 6 can delete the mapping hop and keep
" this one. Converting here would put the endpoint's concerns inside the snapshot
" that is meant to outlive the endpoint.
"
" What it deliberately does NOT do: it does not create a DeliveryIntent, does not
" generate a UUID, does not increment OrderRevision, does not decide whether the
" order may be sent, and does not know the CAP contract. Approval and dispatch
" belong to sendToSupplier in Phase 5.2f.
CLASS zjp_cl_order_delivery_builder DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    " One item of the canonical snapshot. These are exactly the members of the
    " "Source order delivery" item in API_CONTRACTS - no more, no less. Item
    " currency is absent because the contract's item has none; the header
    " currency is what the mapper propagates onto every line.
    TYPES:
      BEGIN OF ty_item,
        item_uuid       TYPE sysuuid_x16,
        item_number     TYPE zjp_po_i-item_number,
        material        TYPE zjp_po_i-material,
        description     TYPE zjp_po_i-material_description,
        quantity        TYPE zjp_po_i-quantity,
        unit_of_measure TYPE zjp_po_i-unit_of_measure,
        net_price       TYPE zjp_po_i-net_price,
        total_amount    TYPE zjp_po_i-total_amount,
      END OF ty_item,
      ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    " The canonical snapshot. This is the artifact Phase 5.2f freezes into
    " ZJP_PO_DLV-payload_snapshot, which is why it must not carry anything that
    " depends on the current endpoint.
    TYPES:
      BEGIN OF ty_delivery,
        schema_version          TYPE string,
        delivery_uuid           TYPE sysuuid_x16,
        source_system           TYPE string,
        purchase_order_uuid     TYPE sysuuid_x16,
        order_revision          TYPE zjp_po_h-order_revision,
        purchase_order_number   TYPE zjp_po_h-purchase_order_number,
        supplier                TYPE zjp_po_h-supplier,
        supplier_name           TYPE zjp_po_h-supplier_name,
        company_code            TYPE zjp_po_h-company_code,
        purchasing_organization TYPE zjp_po_h-purchasing_organization,
        purchasing_group        TYPE zjp_po_h-purchasing_group,
        currency                TYPE zjp_po_h-currency,
        total_amount            TYPE zjp_po_h-total_amount,
        items                   TYPE ty_items,
      END OF ty_delivery.

    " An outcome record rather than an exception, matching the decision already
    " taken for the transport seam in ADR-032 and section 6.3. It is the smallest
    " shape that can say which of the documented failures occurred, and it needs
    " no exception class - so this slice adds no dependency on an unverified API.
    TYPES:
      BEGIN OF ty_result,
        success    TYPE abap_bool,
        delivery   TYPE ty_delivery,
        error_code TYPE string,
        error_text TYPE string,
      END OF ty_result.

    CONSTANTS:
      BEGIN OF error,
        order_not_found TYPE string VALUE 'ORDER_NOT_FOUND',
        no_items        TYPE string VALUE 'NO_ITEMS',
        missing_number  TYPE string VALUE 'MISSING_ORDER_NUMBER',
      END OF error.

    " The contract's constant. CAP accepts major version 1 only.
    CONSTANTS schema_version TYPE string VALUE '1.0'.

    " delivery_uuid and source_system are INPUTS and are never derived here.
    " The delivery identity belongs to the DeliveryIntent created in Phase 5.2f,
    " and sourceSystem is still blocker B4 - its configuration mechanism is
    " undecided, so baking a value in would decide it by accident.
    METHODS build
      IMPORTING purchase_order_uuid TYPE sysuuid_x16
                delivery_uuid       TYPE sysuuid_x16
                source_system       TYPE string
      RETURNING VALUE(result)       TYPE ty_result.

ENDCLASS.


CLASS zjp_cl_order_delivery_builder IMPLEMENTATION.

  METHOD build.

    result-success = abap_false.

    " Active instance only. %is_draft = mk-off is explicit rather than implied,
    " because "the builder reads the active instance, never a draft" is a rule
    " worth being able to see in the source.
    READ ENTITIES OF ZJP_I_PurchaseOrder
      ENTITY PurchaseOrder
        ALL FIELDS WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                                   PurchaseOrderUUID = purchase_order_uuid ) )
        RESULT DATA(orders)
      ENTITY PurchaseOrder BY \_Items
        ALL FIELDS WITH VALUE #( ( %is_draft         = if_abap_behv=>mk-off
                                   PurchaseOrderUUID = purchase_order_uuid ) )
        RESULT DATA(items)
      FAILED DATA(failed_read)
      REPORTED DATA(reported_read).

    IF failed_read IS NOT INITIAL OR lines( orders ) <> 1.
      result-error_code = error-order_not_found.
      result-error_text = 'No active PurchaseOrder for the supplied UUID.'.
      RETURN.
    ENDIF.

    DATA(header) = orders[ 1 ].

    IF lines( items ) = 0.
      result-error_code = error-no_items.
      result-error_text = 'The PurchaseOrder has no items; a delivery needs at least one line.'.
      RETURN.
    ENDIF.

    " The one header invariant the contract states outright: "Never send an empty
    " string as a number". 2.7E allocates it at submit and dispatch is downstream
    " of submit, so in practice it is always populated - but "in practice" is not
    " a guarantee, and an empty order number reaching CAP is a silent bad record.
    IF header-PurchaseOrderNumber IS INITIAL.
      result-error_code = error-missing_number.
      result-error_text = 'PurchaseOrderNumber is empty; it is allocated on a successful submit.'.
      RETURN.
    ENDIF.

    result-delivery = VALUE ty_delivery(
      schema_version          = schema_version
      delivery_uuid           = delivery_uuid
      source_system           = source_system
      purchase_order_uuid     = header-PurchaseOrderUUID
      " Copied, never recalculated and never incremented. Revision-increment
      " behaviour does not exist anywhere in this project yet.
      order_revision          = header-OrderRevision
      purchase_order_number   = header-PurchaseOrderNumber
      supplier                = header-Supplier
      supplier_name           = header-SupplierName
      company_code            = header-CompanyCode
      purchasing_organization = header-PurchasingOrganization
      purchasing_group        = header-PurchasingGroup
      currency                = header-Currency
      total_amount            = header-TotalAmount ).

    LOOP AT items INTO DATA(item).
      APPEND VALUE ty_item(
        item_uuid       = item-PurchaseOrderItemUUID
        item_number     = item-ItemNumber
        material        = item-Material
        description     = item-MaterialDescription
        quantity        = item-Quantity
        unit_of_measure = item-UnitOfMeasure
        net_price       = item-NetPrice
        total_amount    = item-TotalAmount ) TO result-delivery-items.
    ENDLOOP.

    result-success = abap_true.

  ENDMETHOD.

ENDCLASS.
