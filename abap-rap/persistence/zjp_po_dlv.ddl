@EndUserText.label : 'Procurement Hub: Purchase Order Delivery Intent'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table zjp_po_dlv {

  key client              : abap.clnt not null;
  key delivery_uuid       : sysuuid_x16 not null;
  purchase_order_uuid     : sysuuid_x16 not null;
  order_revision          : abap.int4 not null;
  payload_snapshot        : abap.string(0);
  payload_hash            : abap.char(64) not null;
  dispatch_state          : abap.char(16) not null;
  last_correlation_id     : sysuuid_x16 not null;
  portal_order_uuid       : sysuuid_x16 not null;
  approved_by             : abp_lastchange_user not null;
  approved_at             : abp_lastchange_tstmpl not null;
  lease_owner             : sysuuid_x16 not null;
  lease_expires_at        : abp_lastchange_tstmpl not null;
  created_at              : abp_creation_tstmpl not null;
  last_changed_at         : abp_lastchange_tstmpl not null;
  local_last_changed_at   : abp_locinst_lastchange_tstmpl not null;
  attempt_count           : abap.int4 not null;
  next_attempt_at         : abp_lastchange_tstmpl not null;
  retry_window_started_at : abp_lastchange_tstmpl not null;

}