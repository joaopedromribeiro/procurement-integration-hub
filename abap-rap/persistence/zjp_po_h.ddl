@EndUserText.label : 'Procurement Hub: Purchase Order Header'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table zjp_po_h {
  key client                  : abap.clnt not null;
  key purchase_order_uuid     : sysuuid_x16 not null;
  purchase_order_number       : abap.char(20) not null;
  supplier                    : abap.char(10) not null;
  supplier_name               : abap.char(100) not null;
  company_code                : abap.char(4) not null;
  purchasing_organization     : abap.char(4) not null;
  purchasing_group            : abap.char(3) not null;
  currency                    : abap.cuky not null;
  total_amount                : abap.dec(19,2) not null;
  status                      : abap.char(12) not null;
  supplier_response           : abap.char(8) not null;
  estimated_delivery_date     : abap.dats not null;
  created_by                  : abp_creation_user not null;
  created_at                  : abp_creation_tstmpl not null;
  last_changed_by             : abp_lastchange_user not null;
  last_changed_at             : abp_lastchange_tstmpl not null;
  local_last_changed_at       : abp_locinst_lastchange_tstmpl not null;
  order_revision              : abap.int4 not null;
  integration_status          : abap.char(16) not null;
  delivery_id                 : sysuuid_x16 not null;
  last_error_code             : abap.char(60) not null;
  last_error_message          : abap.char(255) not null;
  last_error_at               : abp_lastchange_tstmpl not null;
  last_correlation_id         : sysuuid_x16 not null;
  last_response_id            : sysuuid_x16 not null;
  last_response_version       : abap.int4 not null;
  supplier_responded_at       : abp_lastchange_tstmpl not null;
  rejection_origin           : abap.char(10) not null;
  rejection_reason           : abap.char(255) not null;
}
