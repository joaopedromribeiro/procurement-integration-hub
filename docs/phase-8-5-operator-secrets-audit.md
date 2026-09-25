# Phase 8.5 — operator access, secrets hygiene, and audit evidence

Status: **CLOSED on owner-supplied SAP authorization trace, obsolete-key retirement, and previously accepted cross-system audit evidence (2026-09-24).** Phase 8.6 subsequently closed, completing Phase 8. No production-code defect was found; this phase did not alter the Phase 7 business, delivery, or recovery state machines.

## Authorization boundary and safe proof

`ZJP_I_PURCHASEORDER` declares `retryDelivery` and `recordDeliveryResult` with instance authorization. `ZBP_I_PURCHASEORDER.get_instance_authorizations` requests `ZJP_PIH`/`ZJP_ROLE=OPERATOR` only for `retryDelivery` and `ZJP_ROLE=WORKER` only for `recordDeliveryResult`, returning allowed or unauthorized independently. The real callers, `ZJP_CL_DELIVERY_RECOVERY` and `ZJP_CL_DISPATCH_COORDINATOR`, use external EML rather than `IN LOCAL MODE`. RAP checks instance authorization before running the action handler. The handler's subsequent local-mode operations are not a substitute for caller authorization. Neither action is projected onto the buyer or integration OData surface.

The owner compared and assigned the existing `ZJP_PIH_OPERATOR` and `ZJP_PIH_WORKER` PFCG roles to shared study user `ZHUB.USER`; their project authorization values are `OPERATOR` and `WORKER`, respectively. A read-only `GET PERMISSIONS` probe was attempted against a confirmed existing `ZJP_PO_H` PurchaseOrderUUID, but the target returned **no instance permission result**. It is **not** positive acceptance evidence. The useful evidence came from `STAUTHTRACE` while the ACTIVE behavior-pool authorization handler executed. No `retryDelivery` or `recordDeliveryResult` action, coordinator, recovery runner, HTTP send, or business-state mutation was performed for this acceptance. SAP documents that [instance authorization precedes operation execution](https://help.sap.com/docs/abap-cloud/abap-rap/2a26db5640364b46b843dca786c495d1.html?version=s4_hana).

### Accepted SAP authorization evidence

| Time (2026-09-24) | User / entry point / program | `ZJP_PIH` field `ZJP_ROLE` | Result |
| --- | --- | --- | --- |
| 18:57:44.378 | `ZHUB.USER` / `SADT_REST_RFC_ENDPOINT` / `ZBP_I_PURCHASEORDER===========CP` | `OPERATOR` | Successful authorization check, RC 0 |
| 18:57:44.380 | `ZHUB.USER` / `SADT_REST_RFC_ENDPOINT` / `ZBP_I_PURCHASEORDER===========CP` | `WORKER` | Successful authorization check, RC 0 |

These traces prove that ACTIVE `ZBP_I_PURCHASEORDER` executed both checks and the assigned roles satisfied them. They do **not** prove separate OPERATOR/WORKER identities, negative cross-role isolation, or individual attribution. `ZHUB.USER` is a shared Dialog user with unrelated roles; that limitation is accepted for the study environment and remains open for a stronger deployment posture.

## Secrets hygiene and legacy key

| Boundary | Current handling / remaining limit |
| --- | --- |
| SAP → Cloud Integration | Destination `ZJP_CI_ORDER_DELIVERY` uses OAuth configuration `ZJP_CI_ORDERDLV`; credential values live in SAP configuration, not source. Dedicated OrderDelivery Process Integration Runtime client/key was runtime-verified in 8.4. |
| Cloud Integration → CAP | Security Material alias `PIH_CAP_OAUTH` supplies the XSUAA technical OAuth client; the exported iFlow refers to the alias, not a secret value. |
| CAP → Cloud Integration | `PIH_CI_CLIENT_ID`, `PIH_CI_CLIENT_SECRET`, and `PIH_CI_SUPPLIER_RESPONSE_URL` are runtime environment variables read by `ci-transport.ts`; the MTA records no values. The dedicated SupplierResponse client was runtime-verified in 8.4. |
| Cloud Integration → SAP | `PIH_SAP_BASIC` is a Security Material alias. It currently authenticates shared Dialog user `ZHUB.USER`, which has unrelated roles; full SAP-user least privilege is **not** claimed. |
| Repository | Targeted tracked-source, documentation, export-member, and available Git-history checks found references/aliases and synthetic test credentials, but no actual secret value. Gitleaks was unavailable; this is not a forensic assurance about every historical blob. Never attach service-key JSON, token, Authorization header, cookie, or credential value to evidence. |

The former shared Process Integration Runtime client was refused by both hardened HTTPS senders (403, no MPL) in Phase 8.4. On 2026-09-24 the owner removed the exposed obsolete shared **service key** under `pih-integration-runtime`. The `pih-integration-runtime` **instance was not deleted**. The active dedicated instances `pih-orderdelivery-runtime` and `pih-supplierresponse-runtime` remain. This records retirement of the old shared credential, not removal of the service instance or rotation of any active credential. No secret value is recorded here.

## Accepted audit evidence

Durable business evidence: `ZJP_PO_DLV` stores DeliveryUUID, PurchaseOrderUUID, OrderRevision, approved-by/at, snapshot/hash, dispatch state, AttemptCount, PortalOrderUUID, and LastCorrelationId. `ZJP_PO_H` stores purchase-order identity, LastChangedBy/At, LastCorrelationId, and supplier response ID/version/timestamp. CAP stores order/source identities, response ID/version/timestamp, delivery state/attempts/last correlation, and per-attempt history with outcome and sanitized error. These are operationally useful records, not an immutable compliance audit log.

Operational evidence: both transport legs propagate `X-Correlation-ID`; Cloud Integration MPL can correlate a run, and Phase 7 already matched a persisted SAP correlation ID to the CAP request. SAP status and CAP operational-status reporters read the durable records. `STAUTHTRACE`, MPL, CF task logs, and HTTP traces are transient or retention-limited; do not treat them as permanent business audit records. There is no demonstrated durable per-authorization-denial audit record, and shared SAP identity does not prove which individual performed an action.

Phase 8.5 accepted the existing Phase 7/8 evidence, including the persisted SAP/CAP identities and attempt facts, Cloud Integration MPL correlation, and Phase 7's matching `X-Correlation-ID` across SAP and CAP. No new business transaction, read-only audit query, or audit framework was needed. `STAUTHTRACE` and MPL remain retention-limited operational evidence, not permanent audit storage.

## Sender CSRF decision

Both final exported HTTPS senders retain CSRF protection disabled, with dedicated authenticated machine clients and custom sender roles. Phase 8.5 accepted this verified machine-to-machine posture without changing either iFlow. CSRF protects against a browser reusing a human session; it does not authenticate or authorize the caller. SAP's [Cloud Integration CSRF guidance](https://help.sap.com/docs/cloud-integration/sap-cloud-integration/use-csrf-protection?locale=enUS) says pure backend-to-backend technical communication may omit sender CSRF protection, while browser-callable modifying APIs should keep it enabled. This is not a blanket recommendation for browser-originated modifying requests or a substitute for credential hygiene and authorization.

**PHASE 8.5 CLOSED.** The accepted scope is positive OPERATOR/WORKER authorization-check execution, retirement of the obsolete shared key, reuse of existing audit/correlation evidence, and a documented M2M CSRF decision. Separate SAP-user least-privilege isolation and permanent security-event audit storage are not claimed.
