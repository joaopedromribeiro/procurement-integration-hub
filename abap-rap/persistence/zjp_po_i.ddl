@EndUserText.label : 'Procurement Hub: Purchase Order Item'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table zjp_po_i {
  key client                  : abap.clnt not null;
  key purchase_order_item_uuid : sysuuid_x16 not null;
  purchase_order_uuid         : sysuuid_x16 not null;
  item_number                 : abap.numc(5) not null;
  material                    : abap.char(40) not null;
  material_description        : abap.char(100) not null;
  @Semantics.quantity.unitOfMeasure : 'zjp_po_i.unit_of_measure'
  quantity                    : abap.quan(13,3) not null;
  unit_of_measure             : abap.unit(3) not null;
  net_price                   : abap.dec(19,4) not null;
  currency                    : abap.cuky not null;
  total_amount                : abap.dec(19,2) not null;
  local_last_changed_at       : abp_locinst_lastchange_tstmpl not null;
}
