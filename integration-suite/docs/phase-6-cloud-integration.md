# Phase 6 — Cloud Integration as the mediation layer

Status: **Phase 6.1 is SAP Integration Suite runtime-verified.** A real HTTPS request reached a deployed iFlow in a real tenant, was converted, validated against the source contract, and answered with a controlled response carrying the caller's own correlation ID — and an invalid contract was rejected by the schema instead of being answered. **Phase 6.2 is designed here and not built.** No SAP ABAP object changed, no CAP object changed, and Cloud Integration is not yet in the real outbound path.

Phase 5 remains the working baseline and the rollback: SAP still posts directly to CAP through `ZJP_CL_OUTBOUND_TRANSPORT` and `ZJP_CAP_BASE`, and nothing in this phase has touched that.

---

## 1. What Phase 6 was already designed to be

Phase 6 was largely pre-decided, which is why this guide records rather than invents. [ARCHITECTURE.md](../../ARCHITECTURE.md) already specified the outbound iFlow `PIH_OrderDelivery_v1` as a nine-step pipeline, the return iFlow `PIH_SupplierResponse_v1`, and an Exception Subprocess; [API_CONTRACTS.md](../../API_CONTRACTS.md) already fixed the sender path `POST /http/pih/v1/order-deliveries`; ADR-009 already ruled that standard mapping components come before Groovy; and `integration-suite/` already carried the folder contract. The one thing the architecture explicitly deferred was *"Define XML wrapper/root names and source/target XSDs in Phase 6 so conversion, validation and mapping agree."* **Phase 6.1 settles the source half of that sentence.**

The governing principle is unchanged: *"Phase 6 switches endpoints to Cloud Integration without changing business identities or ownership."*

## 2. A dedicated subaccount, and the failure that forced it

**Subaccount: `PIH Integration`** — a dedicated SAP BTP subaccount hosting Integration Suite scenarios between SAP RAP and the CAP Supplier Portal.

It exists because the original trial subaccount had an inconsistent Cloud Integration runtime. Deployment failed with:

```text
Requested runtime location (: cloudintegration) is not supported for tenant: 0badc38dtrial
```

and the monitor failed the same way:

```text
Request for artifact list failed: Requested runtime location (cloudintegration)
is not supported for tenant: 0badc38dtrial
```

**This was a tenant runtime-provisioning problem, not an iFlow design error**, and that distinction is the lesson worth keeping. Nothing about the flow was wrong; it had nowhere valid to run. The iFlow was exported before the tenant change, a clean Integration Suite subscription was provisioned in `PIH Integration`, and **the same imported artifact deployed successfully** — which is what proves the diagnosis rather than merely asserting it.

Capabilities and roles used: `Integration_Provisioner`, **Build Integration Scenarios**, `PI_Integration_Developer`.

## 3. The Phase 6.1 flow

Integration Package **Procurement Integration Hub**, Integration Flow **`PIH_OrderDelivery_v1`**, version **1.0.0**, runtime profile **Cloud Integration**.

```text
HTTPS Sender
  → Capture Correlation ID      (Content Modifier, exchange property)
  → Convert Source JSON to XML  (root element OrderDelivery)
  → Validate Source Contract    (XML Validator, source XSD)
  → Build Validation Response   (Content Modifier, controlled JSON)
  → End
```

**There is no CAP receiver call in Phase 6.1.** The receiver participant may remain visible but disconnected until Phase 6.3. That absence is the point: this subphase proves the *entry* boundary in isolation, so a later failure cannot be ambiguous between the sender, the conversion, the schema and the portal.

### Endpoint

| Property | Value |
| --- | --- |
| Deployed endpoint | `https://pih-integration-bncd0sdp.it-cpitrial05-rt.cfapps.us10-001.hana.ondemand.com/http/pih/v1/order-deliveries` |
| Configured relative address | `/pih/v1/order-deliveries` |
| Allowed header | `X-Correlation-ID` |
| Sender authorization | `ESBMessaging.send` |

The public path matches API_CONTRACTS' documented boundary exactly. The `/http` prefix is the adapter's, so the configured relative address is the remainder — worth stating, because the two differ and the difference looks like a mistake until you know why.

### Authentication boundary

A **SAP Process Integration Runtime** service instance in the new subaccount: technical service `it-rt`, plan `integration-flow`, role `ESBMessaging.send`, grant type **client credentials**. A service key was created and carries the usual client-credentials fields.

**No secret material is recorded here or anywhere in this repository** — not the client secret, not the service key, not a token. Only the model, the service name, the plan, the role and the already-public host and path.

The `CPI → CAP` hop does not exist yet and its authentication is Phase 6.3's. The full OAuth model for both hops remains Phase 8 per the security progression.

### Correlation

A Content Modifier, *Capture Correlation ID*, creates an exchange property:

| Field | Value |
| --- | --- |
| Action | Create |
| Name | `PihCorrelationId` |
| Source Type | Expression |
| Source Value | `${header.X-Correlation-ID}` |
| Data Type | `java.lang.String` |

and the response modifier sets the header back from `${property.PihCorrelationId}`.

**Cloud Integration does not mint a replacement business correlation ID.** The attempt identity belongs to the ABAP coordinator, which mints a fresh UUID per attempt while the `deliveryId` stays constant; CI's job is to carry it, not to have an opinion about it. This is the same ownership rule Phase 5 verified, preserved across a new hop.

### JSON to XML, and a design-time warning that is not a defect

*Convert Source JSON to XML*: JSON Prefix Separator **colon**, namespace mapping **off**, **Add XML Root Element on**, root **`OrderDelivery`**.

Integration Suite raises a design-time warning here:

```text
Http Sender Component may not pass JSON message to JSON To XML Converter.
JSON To XML Converter supports JSON input only.
```

**This is an expected design-time warning for this architecture, not a runtime defect.** The converter cannot know at design time what an arbitrary HTTP caller will send; the *contract* requires `Content-Type: application/json`, and the runtime run below proves valid JSON traverses the converter. It is recorded here so nobody later mistakes it for an unresolved problem — and so nobody "fixes" it by weakening the contract.

### Source contract and its schema

Resource `pih-order-delivery-source-v1.xsd`, resolved by the validator as `/xsd/pih-order-delivery-source-v1.xsd`, root `OrderDelivery`, with `schemaVersion` restricted to `1.0`.

**The source contract is the persisted SAP `PayloadSnapshot`, not the CAP request body.** `unitOfMeasure` stays `EA` here. `EA → PCE` is a boundary mapping concern and belongs to Phase 6.2 — putting it in the source schema would mean the source contract had quietly become the target contract, which is the exact confusion ADR-032 drew the two-hop design to prevent.

**Prevent Exception on Failure is deliberately unchecked.** An invalid source contract must fail and must not fall through into the happy-path response. A validator that swallows its own failure is worse than no validator, because it converts a rejected message into a successful-looking one.

The repository copy is [`mappings/pih-order-delivery-source-v1.xsd`](../mappings/pih-order-delivery-source-v1.xsd). It is a repository copy derived from the same contract, **not a byte-level export of the deployed resource**, and it says so in its own header; it must be reconciled when the iFlow is exported.

### Controlled response

*Build Validation Response* sets `Content-Type: application/json` (constant) and `X-Correlation-ID` from the captured property, with the body:

```json
{
  "status": "VALIDATED",
  "flow": "PIH_OrderDelivery_v1",
  "message": "Source order delivery contract accepted"
}
```

This is a **Phase 6.1 stand-in** and not a contract anybody may build on. From Phase 6.3 the response becomes the CAP receipt.

## 4. Runtime evidence

### Happy path

A real POST to the deployed endpoint with `Content-Type: application/json`, `X-Correlation-ID: 11111111-2222-3333-4444-555555555555`, client-credentials authentication and the exact valid source payload returned:

```json
{
    "status": "VALIDATED",
    "flow": "PIH_OrderDelivery_v1",
    "message": "Source order delivery contract accepted"
}
```

**The same `X-Correlation-ID` came back.** Monitor → Message Processing: artifact `PIH_OrderDelivery_v1`, status **Completed**, **477 ms**.

So the runtime proved the whole entry boundary: HTTPS inbound → correlation capture → JSON-to-XML → source XSD validation → controlled JSON response → completion.

### Negative path

The same request with `"schemaVersion": "2.0"` returned a server error rather than `VALIDATED`. MPL `AGqup_aXlRrjF40ZFbiUOtGFZMwy`, status **Failed**, **490 ms**:

```text
Validation failed for: /xsd/pih-order-delivery-source-v1.xsd
The content "2.0" of element <schemaVersion> does not match the required simple type.
Value "2.0" contravenes the enumeration facet "1.0" of the type SchemaVersionType.
```

**The negative path is the more valuable of the two.** A happy path alone would prove only that a request can reach an endpoint; this proves the schema is actually enforced, that a rejected message is visibly `Failed` in monitoring rather than quietly successful, and that the happy-path response was never reached. It also confirms the contract's own rule that *"unknown schema major versions fail"* is real rather than aspirational.

### What Phase 6.1 does **not** prove

No mapping exists. No CAP call exists. No SAP system has pointed at this endpoint. The `VALIDATED` body is a stand-in. Only the `schemaVersion` enumeration has been exercised out of the whole schema — every other facet is contract, not evidence.

## 5. Phase 6.2 — mapping parity

**Objective:** validated source XML → Graphical Message Mapping → target CAP XML → target XSD validation → XML to JSON → compared against the Phase 5 ABAP mapper's golden output.

Still no SAP cutover, no CAP receiver, no coordinator change, no destination change, and **no deletion of the ABAP mapper** — `ZJP_CL_CAP_ORDER_MAPPER` is the runtime-verified **parity oracle** for the whole of 6.2, and it stops being the oracle only after CI has matched it.

### The oracle

[`payloads/cap-order-target-golden-v1.json`](../payloads/cap-order-target-golden-v1.json) — 524 bytes, the exact output of `ZJP_CL_BUILDER_TEST=>GOLDEN_BODY`, which Phase 5.2d verified byte for byte and which the deployed portal has accepted over real HTTP. [`payloads/order-delivery-source-valid-v1.json`](../payloads/order-delivery-source-valid-v1.json) is the matching input.

### Mapping contract

Authority is API_CONTRACTS.md; the ABAP mapper and the CAP ingestion contract agree with it.

| Source | CAP target | Rule |
| --- | --- | --- |
| `schemaVersion` | `schemaVersion` | pass through |
| `deliveryId` | `deliveryId` | pass through, unchanged |
| `purchaseOrderId` | `source.orderId` | source identity kept separate from any CAP UUID |
| `purchaseOrder` | `source.orderNumber` | |
| `revision` | `source.revision` | **JSON number** |
| `sourceSystem` | `source.system` | validate against the authenticated integration client |
| `supplier` | `supplierCode` | unknown code is a 400 at CAP |
| `supplierName` | **not transmitted** | CAP resolves its own supplier reference |
| `companyCode`, `purchasingOrganization`, `purchasingGroup` | **not transmitted** | internal SAP context |
| `currency` | `amount.currency` | |
| `totalAmount` | `amount.value` | unchanged decimal string; no repricing |
| `items[]` | `lines[]` | preserve cardinality |
| `itemId` | `lines[].sourceItemId` | preserve source item identity |
| `item` | `lines[].lineNumber` | **string `"10"` → number `10`**; reject invalid, non-numeric or duplicate |
| `material` | `product.code` | |
| `description` | `product.description` | |
| `quantity` | `orderedQuantity.value` | |
| `unitOfMeasure` | `orderedQuantity.unit` | **controlled `EA` → `PCE`**; an unknown unit fails, it is not guessed |
| `netPrice` | `unitPrice.value` | |
| header `currency` | `unitPrice.currency` | propagated to every line |
| `items[].totalAmount` | `lines[].lineAmount` | verify arithmetic; never invent totals |

Decimals keep their canonical scale as strings throughout: `1500.00`, `2.000`, `750.0000`.

### Target schema

[`mappings/pih-cap-order-target-v1.xsd`](../mappings/pih-cap-order-target-v1.xsd) — **proposed, not deployed**. Every element, type and length is derived from `cap-supplier-portal/srv/integration-service.cds` and the element order from the verified ABAP golden body; nothing is invented.

### The two conversion risks to prove first

Both produce output that reads as correct and is not, which is why they come before the cosmetic fields.

**Numeric typing.** `source.revision` and `lines[].lineAmount`'s sibling `lineNumber` must emerge as JSON **numbers** — the CAP contract types them `Integer` and the golden body carries `"revision":1` and `"lineNumber":10` unquoted. An XML-to-JSON converter that stringifies everything yields `"revision":"1"`, which parses, looks fine and breaks the contract.

**Single-element arrays.** `lines` must be a JSON **array** even with exactly one line — and the golden fixture has exactly one. A converter that renders a single repeated element as an object produces a payload that matches field by field and is still wrong. **The parity test must assert `Array.isArray(lines)`, not merely compare its contents.**

If either needs more than standard components, ADR-009 applies: prefer standard components, and justify any Groovy explicitly rather than reaching for it out of convenience.

### Parity method, stated honestly in advance

Compare CI's output with the golden oracle. **Byte-level comparison if it is literally achievable** after canonical serialisation; if CI's serialiser necessarily differs in whitespace or property order, **say so and compare the parsed structure field by field instead**. Do not claim byte parity unless it is true.

Assertions required either way: `schemaVersion`, `deliveryId`, `source.system` / `.orderId` / `.orderNumber` / `.revision`, `supplierCode`, `amount.value` / `.currency`, `lines` cardinality **and array-ness**, `sourceItemId`, `lineNumber` numeric, `product.code` / `.description`, `orderedQuantity.value`, `EA → PCE`, `unitPrice.value` / `.currency`, `lineAmount`, and the **absence** of `supplierName`, `companyCode`, `purchasingOrganization` and `purchasingGroup`.

## 6. Remaining subphases

**6.3** — CI → CAP: HTTP receiver, real 201/200/409, receipt handling, Exception Subprocess, and the `Idempotency-Key` ownership transfer noted below. **6.4** — SAP cutover: a new destination, and the coordinator posts the persisted snapshot to CI. **6.5** — inbound `PIH_SupplierResponse_v1`, which needs `applySupplierResponse` and does not exist yet.

## 7. Open items

- **Header ownership transfer.** Today the *ABAP mapper* sets `Content-Type` and `Idempotency-Key` (= `deliveryId`) and owns the CAP path. When CI takes over mapping, CI must set them — otherwise nothing does. Phase 6.3.
- **Receipt shape.** ARCHITECTURE describes CI mapping the receipt *to the source contract*, but the coordinator's `read_receipt` is runtime-verified against CAP's actual receipt. **Recommendation: CI returns CAP's receipt unchanged**, and any reshaping is a separate later decision. Phase 6.3.
- **Exported iFlow artifact.** The deployed artifact is in the tenant and **not in this repository**. `integration-suite/iflows/PIH_OrderDelivery_v1/` is still empty.
- **`EA → PCE` will exist in two places** during 6.2 — ABAP and CI. Acceptable while both run; it needs an explicit end date at cutover.
- **Cutover consequence worth planning for now:** once CI owns mapping, the coordinator posts the persisted snapshot **verbatim**, so both `ZJP_CL_DLV_SNAPSHOT_READER` and `ZJP_CL_CAP_ORDER_MAPPER` leave the outbound path entirely. That is ADR-032's two-hop split paying off exactly as designed, and it makes 6.4 a smaller change than it looks.
