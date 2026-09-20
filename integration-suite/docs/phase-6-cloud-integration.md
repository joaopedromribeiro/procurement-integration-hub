# Phase 6 — Cloud Integration as the mediation layer

Status: **Phases 6.1, 6.2, 6.3 and 6.4 are all runtime-verified. Phase 6 is NOT complete** — 6.5, the inbound supplier response, has not started. A real HTTPS request reached a deployed iFlow in a real tenant, was converted, validated against the source contract, and answered with a controlled response carrying the caller's own correlation ID — and an invalid contract was rejected by the schema instead of being answered. **Phase 6.2 added the mapping**: a Graphical Message Mapping turns the validated source into the CAP order contract, with semantic parity against the Phase 5 ABAP mapper and **no Groovy anywhere**. **Phase 6.3 closed the loop**: Cloud Integration now calls the protected CAP `IntegrationService` over OAuth 2.0 client credentials and returns CAP's real receipt, with a `201` create, a `200` idempotent replay, a truthful `409` conflict and a controlled `502` for technical failures. No SAP ABAP object changed and no CAP object changed in any of the three subphases. **Phase 6.4 cut SAP over.** The post-commit coordinator now posts the persisted `PayloadSnapshot` **verbatim** to Cloud Integration over destination `ZJP_CI_ORDER_DELIVERY`, so Integration Suite owns mapping on the **active production path** and the ABAP mapper has left it. Phase 5's direct SAP-to-CAP objects are all preserved as the fallback and the parity reference. **Phase 6 is still not complete**: `PIH_SupplierResponse_v1`, the inbound supplier response, is Phase 6.5 and has not started.

Phase 5 is no longer the active path, but every one of its objects survives as the rollback and the reference: `ZJP_CL_OUTBOUND_TRANSPORT` and the seam are unchanged and still carry the traffic, destination `ZJP_CAP_BASE` still points at CAP directly and is still exercised by `ZJP_CL_HTTP_TRANSPORT_TEST`, and `ZJP_CL_DLV_SNAPSHOT_READER` and `ZJP_CL_CAP_ORDER_MAPPER` are untouched and still tested.

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

## 3. The deployed flow

Integration Package **Procurement Integration Hub**, Integration Flow **`PIH_OrderDelivery_v1`**, version **1.0.0**, runtime profile **Cloud Integration**.

Phase 6.1 deployed the first four steps, **Phase 6.2 added the mapping**, and **Phase 6.3 added the CAP call and the Exception Subprocess**. The deployed flow, with step names exactly as the export carries them:

```text
HTTPS Sender
  → Capture Correlation ID            (Content Modifier, exchange property)
  → Convert Source JSON to XML        (root element OrderDelivery)
  → Validate Source Contract          (XML Validator, source XSD)
  → Map Source to CAP Contract        (Graphical Message Mapping, OpenAPI target)  [6.2]
  → Prepare CAP Request               (Content Modifier, headers only)             [6.3]
  → Send to CAP request Reply         (Request Reply)                              [6.3]
       → CAP_Supplier_Portal          (HTTP receiver participant)                  [6.3]
  → Prepare Delivery Receipt Response (Content Modifier, headers only)             [6.3]
  → End

Exception Subprocess "Handle Technical Exception"                                      [6.3]
  Error Start
  → Prepare Technical Error Response  (Content Modifier)
  → End Message
```

**The exported artifact is the implementation truth**, and its step names drift slightly from the prose anyone would write: *Send to CAP request Reply*, and a trailing space in *Prepare CAP Request*. They are reproduced here as-is rather than tidied, because a reader comparing this guide against the iFlow should find the same strings.

**The isolation discipline was kept to the end.** 6.1 proved the entry boundary with no receiver at all, 6.2 proved the mapping with still no receiver, and only 6.3 connected the portal. When 6.3's first attempt failed, that ordering is what made the cause obvious within one request rather than ambiguous across five candidate steps.

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

One adapter setting alongside this one turned out to matter as much as the role: **CSRF protection on the HTTPS Sender**, which Phase 6.2 had to disable before an authenticated machine-to-machine POST could reach the flow at all. See [CSRF protection on the HTTPS Sender](#csrf-protection-on-the-https-sender-and-a-403-that-never-reached-the-flow).

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

At the 6.1 checkpoint no mapping existed, and the `VALIDATED` body was a stand-in; Phase 6.2 has since added the mapping and replaced that response. Still true today: **no CAP call exists and no SAP system has pointed at this endpoint.** And only the `schemaVersion` enumeration has ever been exercised out of the whole source schema — every other facet is contract, not evidence.

## 5. Phase 6.2 — mapping parity, runtime-verified

**Phase 6.2 is runtime-verified.** The Graphical Message Mapping turns the validated source into the CAP order contract and reaches **semantic parity** with the Phase 5 ABAP mapper. It was proven with a **one-item and a two-item** payload, and it needed **no Groovy**.

At this checkpoint there was still no SAP cutover, no CAP receiver, no coordinator change and no destination change, and the ABAP mapper was not deleted — `ZJP_CL_CAP_ORDER_MAPPER` was the runtime-verified **parity oracle** until CI took over the outbound path in 6.4. **Phase 6.4 has since done that**, and the mapper is now kept as the Phase 5 parity reference rather than as the live oracle. It was never deleted.

### CSRF protection on the HTTPS Sender, and a 403 that never reached the flow

**Before any mapping could be tested, the test could not get in.** The HTTPS Sender was deployed with address `/pih/v1/order-deliveries`, authorization **User Role**, user role `ESBMessaging.send` and **CSRF Protected enabled**. A POST to `/http/pih/v1/order-deliveries`, carrying the same SAP Process Integration Runtime service-key authentication that was already working, came back:

```text
HTTP 403 Forbidden
HTTP Status 403 — Forbidden      (plain HTML body)
```

**The diagnostically decisive detail is what was *absent*.** The rejected POSTs produced **no new Message Processing Log** under *Monitor → Integrations and APIs → Monitor Message Processing*. A 403 with an MPL would have meant the message entered `PIH_OrderDelivery_v1` and something inside it refused the request; a 403 with no MPL can only mean the request was rejected at the **HTTPS sender / endpoint boundary, before the flow ran**. That single observation separates an adapter-configuration problem from a flow problem, and it is worth reaching for before changing anything.

Setting **CSRF Protected to disabled**, then Save → Deploy → Runtime Status *Started*, was the whole fix. **No mapping change was required for this problem.** The same authenticated POST to the same endpoint then returned:

```text
HTTP 200 OK
Content-Type: application/json
X-Correlation-Id: 11111111-2222-3333-4444-555555555555
```

with `PIH_OrderDelivery_v1` returning the mapped CAP contract. That `X-Correlation-Id` is the **caller-provided PIH attempt correlation ID**, distinct from the platform's own technical correlation and request IDs — the ownership rule from Phase 6.1 still holding across the mapping hop.

**Authentication was never broken, and this should not be recorded as if it were.** The identical service-key client-credentials authentication succeeded once CSRF protection was off. The 403 was a CSRF-token requirement that the caller did not satisfy, not an authorization failure.

**`CSRF Protected = disabled` is the current Phase 6.2 runtime configuration, and it is not declared to be the final production security posture.** The exported artifact records it: `xsrfProtection` is `0` in the `.iflw` inside [`iflows/PIH_OrderDelivery_v1.zip`](../iflows/PIH_OrderDelivery_v1.zip), so the posture is checkable from this repository without tenant access. If CSRF protection is enabled later, **the caller must implement the matching CSRF token fetch-and-use flow**, or the final security architecture must explicitly choose another supported machine-to-machine approach. Which of those happens is a later security and cutover decision, tracked as an open item.

### The target turned out to be OpenAPI, not XSD

This guide originally proposed a target **XSD**. The built flow uses an **OpenAPI 3.0.3** document instead, [`mappings/pih-cap-order-target-v1.openapi.json`](../mappings/pih-cap-order-target-v1.openapi.json). That changed how the two conversion risks flagged below were answered — but, as the next section records, **the target document alone did not answer them.**

### How JSON numbers and the array were actually achieved — two mechanisms, not one

**Declaring the contract was necessary and not sufficient.** Each risk needed a declaration *and* a mapping-side mechanism.

**Numeric typing.** The OpenAPI target declares `revision` and `lineNumber` as `"type": "integer"`. On its own that did **not** produce numbers. The deployed run emitted them quoted:

```json
"revision": "1"
"lineNumber": "10"
```

Only after the Message Mapping was configured to use the **basic data types defined by the target JSON/OpenAPI schema** — its *Basic Data Type Handling* setting — did the same payload emit them unquoted:

```json
"revision": 1
"lineNumber": 10
```

So the OpenAPI document **declares** the primitive types, and the Message Mapping runtime setting is what **makes the generated JSON honour them**. Attributing the fix to the target schema alone would misdescribe what was done, and would leave the next person wondering why their integers are still strings.

**Array handling.** The target declares `lines` as `"type": "array"` with `"minItems": 1`. The mapping also carries an explicit **structure mapping**, `/OrderDelivery/items` → `/lines`, which is what establishes the repeated target node and its cardinality. The declaration describes the shape; the structure mapping produces the repetition. Both are present in the deployed `.mmap`.

The generalisable lesson is the same in both halves: **a declared target contract is necessary but not sufficient — the transformation engine has to be told to honour it.**

**A consequence worth recording: there is no XML-to-JSON converter step in the flow at all.** ARCHITECTURE's original sketch had one. With an OpenAPI target the Message Mapping emits JSON directly, so the step is unnecessary. That is a deliberate deviation from the sketch, noted here rather than silently absorbed.

The OpenAPI schemas mirror the CAP ingestion contract field for field, lengths included — `supplierCode` 10, `source.system` 30, `source.orderNumber` 20, `product.code` 40, `product.description` 100, `currency` and `unit` 3, `deliveryId` 36, `DecimalString` 30 — so the target document and `cap-supplier-portal/srv/integration-service.cds` agree.

### `EA` to `PCE`, and the header currency, with standard functions

The unit mapping is a **`FixValues`** function over `items/unitOfMeasure` with the single entry `EA` → `PCE`. ADR-009 asked for standard components before Groovy, and this is the rule that could most easily have been answered with a script; it was not.

The header `currency` reaches two places. `amount.currency` is a direct mapping. Every line's `unitPrice.currency` is a **`useOneAsMany`** function, with the per-line cardinality supplied by **`removeContexts`** over `items/itemId` — the standard idiom for replicating one header value once per repeating target node. This too is standard-function work, not a script.

### What the runtime proved

Graphical Message Mapping executes against the source XSD and the OpenAPI target; **JSON number handling** — `revision` and `lineNumber` emerge unquoted, once Basic Data Type Handling honours the target schema; **array handling** — `lines` is an array, from the target declaration plus the `items` → `lines` structure mapping; a **one-item** payload maps correctly; a **two-item** payload maps correctly; `EA` becomes `PCE`; the header currency is replicated per line; the SAP-internal fields `supplierName`, `companyCode`, `purchasingOrganization` and `purchasingGroup` are excluded; `X-Correlation-ID` is still preserved end to end; and the result reaches **semantic parity** with the ABAP mapper golden payload. No Groovy, no SAP ABAP change, no CAP change.

**The two-item run is the one that retires the array risk.** A single-item test cannot distinguish a real array from an object that a converter collapsed, so on its own it would have proven the weaker half of the claim.

**Parity is semantic, not byte-level, and that is stated deliberately.** The rule set before the test was *do not claim byte parity unless it is literally true*. Field-by-field equivalence against the golden payload is what was verified.

The two-item runtime response makes the distinction concrete rather than cautious: Cloud Integration emits its members in a different order from the ABAP mapper — `deliveryId`, `amount`, `schemaVersion`, `source`, `supplierCode`, `lines`, against the ABAP `schemaVersion`, `deliveryId`, `source`, `supplierCode`, `amount`, `lines`, with `source` differing internally too. The payloads are equivalent and are **not** byte-identical, so byte parity is not merely unproven here, it is known to be false.

### Fixtures

| File | Role |
| --- | --- |
| [`order-delivery-source-valid-v1.json`](../payloads/order-delivery-source-valid-v1.json) | one-item source, the Phase 5.2d golden input |
| [`cap-order-target-golden-v1.json`](../payloads/cap-order-target-golden-v1.json) | **the oracle** — byte-exact ABAP mapper output for that input |
| [`order-delivery-source-valid-2items-v1.json`](../payloads/order-delivery-source-valid-2items-v1.json) | **the two-item source actually executed** against the deployed iFlow — the one-item order extended with a second line, header `totalAmount` `2000.00` |
| [`cap-order-target-runtime-2items-v1.json`](../payloads/cap-order-target-runtime-2items-v1.json) | **the deployed runtime response, verbatim** — Cloud Integration output, not a derivation. The ABAP golden covers one item only, so there is no ABAP oracle for this case |

The two-item pair is the executed scenario, not a constructed one: `1500.00 + 500.00 = 2000.00` matches the header, both lines carry `PCE` and the header `EUR`, and both `lineNumber` values are numeric. It reuses the one-item order's `deliveryId`, `orderId` and `PO00002001` and adds line `20` (`MAT002`, Docking Station, `1.000` at `500.0000`), so line `10` is identical to the ABAP golden line and can be compared against it directly.

---

## 5a. The Phase 6.2 design as written beforehand

Kept as a record, because the two conversion risks it named were real and are exactly what the OpenAPI target resolved.

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

The plan proposed a target **XSD**, `pih-cap-order-target-v1.xsd`, derived from `cap-supplier-portal/srv/integration-service.cds` with element order taken from the verified ABAP golden body. **It was superseded by the OpenAPI target that was actually built and is no longer in the repository** (it remains in git history at commit `baaf278`). The derivation held up: the OpenAPI document carries the same fields and the same lengths.

### The two conversion risks to prove first — both since answered

Both produce output that reads as correct and is not, which is why they come before the cosmetic fields.

**Numeric typing.** `source.revision` and `lines[].lineAmount`'s sibling `lineNumber` must emerge as JSON **numbers** — the CAP contract types them `Integer` and the golden body carries `"revision":1` and `"lineNumber":10` unquoted. An XML-to-JSON converter that stringifies everything yields `"revision":"1"`, which parses, looks fine and breaks the contract.

**Single-element arrays.** `lines` must be a JSON **array** even with exactly one line — and the golden fixture has exactly one. A converter that renders a single repeated element as an object produces a payload that matches field by field and is still wrong. **The parity test must assert `Array.isArray(lines)`, not merely compare its contents.**

If either needs more than standard components, ADR-009 applies: prefer standard components, and justify any Groovy explicitly rather than reaching for it out of convenience.

### Parity method, stated honestly in advance

Compare CI's output with the golden oracle. **Byte-level comparison if it is literally achievable** after canonical serialisation; if CI's serialiser necessarily differs in whitespace or property order, **say so and compare the parsed structure field by field instead**. Do not claim byte parity unless it is true.

Assertions required either way: `schemaVersion`, `deliveryId`, `source.system` / `.orderId` / `.orderNumber` / `.revision`, `supplierCode`, `amount.value` / `.currency`, `lines` cardinality **and array-ness**, `sourceItemId`, `lineNumber` numeric, `product.code` / `.description`, `orderedQuantity.value`, `EA → PCE`, `unitPrice.value` / `.currency`, `lineAmount`, and the **absence** of `supplierName`, `companyCode`, `purchasingOrganization` and `purchasingGroup`.

## 6. Phase 6.3 — the CAP call, runtime-verified

**Cloud Integration now delivers to the portal.** The Request Reply step calls the protected CAP `IntegrationService` and the caller receives CAP's own receipt. Every configuration value below is verifiable in [`iflows/PIH_OrderDelivery_v1.zip`](../iflows/PIH_OrderDelivery_v1.zip); none of it rests on a screenshot.

### Receiver configuration

| Property | Value |
| --- | --- |
| CAP endpoint | `https://0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com/rest/integration/v1/Orders` |
| Proxy type | Internet (`proxyType = default` in the export) |
| Method | `POST` |
| Authentication | OAuth 2.0 Client Credentials |
| Credential name | `PIH_CAP_OAUTH` |
| Request headers | `Content-Type|X-Correlation-ID` |
| Response headers | `*` |
| Throw Exception on Failure | **OFF** |
| Retry | platform default; no custom retry behaviour introduced |

`PIH_CAP_OAUTH` is a Security Material entry of type OAuth2 Client Credentials holding the CAP XSUAA technical client. **No secret value, client id or token URL is recorded in this repository** — only the alias, the grant type and the fact that Integration Suite obtains a token and reaches the protected service.

**Neither Content Modifier touches the body.** *Prepare CAP Request* sets `Content-Type: application/json` and `X-Correlation-ID` from `${property.PihCorrelationId}`, and lets the Message Mapping output pass through untouched. *Prepare Delivery Receipt Response* does the same two headers on the way back and leaves **CAP's receipt as the body**. That is the Phase 6.1 recommendation — *CI returns CAP's receipt unchanged* — actually implemented rather than quietly reshaped.

### `Throw Exception on Failure = OFF` is the load-bearing setting

**This one checkbox decides whether the caller is told the truth.** With it enabled, CPI converts a downstream non-2xx into a generic integration exception: the 6.3c conflict test came back as a failed MPL and a caller-facing **500**, and CAP's precise `409 DELIVERY_PAYLOAD_CONFLICT` — including the sentence telling the caller to use a new `deliveryId` — was destroyed in transit.

With it **OFF**, CPI preserves the real status code and the real CAP error body. The distinction the flow now draws is exactly the right one:

- **Downstream HTTP answers** (`201`, `200`, `409`, and any other CAP 4xx/5xx) are **real responses from the portal** and are passed through as themselves.
- **Technical integration failures** (DNS, connectivity, TLS, timeout, OAuth, iFlow processing) never produce a downstream answer at all, so the **Exception Subprocess** handles them and returns a controlled `502`.

**A downstream `409` is not an integration error, and a DNS failure is not a business outcome.** Collapsing both into one generic 500 would have made the coordinator's Section 6.4 receipt classification unimplementable, because `409` and `502` sit on opposite sides of its retry decision.

### The technical error response

The Exception Subprocess sets `CamelHttpResponseCode = 502`, `Content-Type: application/json` and the same `X-Correlation-ID`, with a fixed body:

```json
{
  "error": {
    "code": "INTEGRATION_TECHNICAL_ERROR",
    "message": "A technical error occurred while delivering the order.",
    "correlationId": "${property.PihCorrelationId}",
    "retryable": true
  }
}
```

**`exception.message` and the stack trace are deliberately not exposed.** The caller gets a stable code, a retryability flag and its own correlation ID; the diagnostic detail stays in the MPL where it belongs. A caller that must parse an error to decide whether to retry needs a contract, not a Java exception string.

### Runtime evidence

All four runs used delivery `244b218a-5b0c-4244-befe-d3a163f4b3f1`.

**6.3a — create, `HTTP 201 Created`.** The receipt came back through Integration Suite:

```json
{
  "deliveryId": "244b218a-5b0c-4244-befe-d3a163f4b3f1",
  "sourceOrderId": "bcb31a02-43ad-41d4-83c8-a4c12917213b",
  "portalOrderId": "958b9eb4-a427-4acb-af9a-e9b023734349",
  "status": "RECEIVED",
  "receivedAt": "2026-09-19T20:51:36.114Z"
}
```

One request proves the whole chain at once: HTTPS sender authentication, source validation, mapping, OAuth 2.0 client credentials, Integration Suite reaching CAP, CAP reaching HANA, and the receipt travelling back out.

**6.3b — idempotent replay, `HTTP 200 OK`.** Same `deliveryId`, same content, and the receipt came back with the **same `portalOrderId` and the same `receivedAt`**. Those two fields are the proof: a second portal order would have carried a new id, and a re-created one a later timestamp. Neither moved, so nothing was created.

**6.3c — conflicting replay, `HTTP 409 Conflict`.** Same `deliveryId`, changed commercial content, and CAP's own error body arrived intact through CI:

```json
{
  "error": {
    "message": "deliveryId 244b218a-5b0c-4244-befe-d3a163f4b3f1 was already accepted with different content. The stored order is unchanged; use a new deliveryId for a corrected snapshot.",
    "correlationId": "44444444-5555-6666-7777-888888888888",
    "retryable": false,
    "code": "DELIVERY_PAYLOAD_CONFLICT"
  }
}
```

**6.3d — controlled technical failure, `HTTP 502`.** For verification only, the receiver host was temporarily pointed at `https://pih-cap-test.invalid/...` to force a DNS/connectivity failure. The Exception Subprocess answered with the controlled body above, carrying correlation `55555555-6666-7777-8888-999999999999`.

**The real receiver was then restored and redeployed, and the restore was verified rather than assumed**: the original payload was sent again and returned `HTTP 200 OK` with the same `portalOrderId` and `receivedAt` as 6.3a. The export in this repository carries the real CAP host, not the `.invalid` one, so the restore is checkable here too.

### Idempotency works without an `Idempotency-Key` header, and that resolves an open item unexpectedly

**Phase 6.1 recorded a worry that turned out to be misdirected.** The open item said the ABAP mapper sets `Idempotency-Key` (= `deliveryId`) and that *CI must set it too, otherwise nothing does*. CI does **not** set it: *Prepare CAP Request* sends `Content-Type` and `X-Correlation-ID` only. Yet 6.3b deduplicated correctly and 6.3c detected the conflict.

The reason is in CAP's own contract. `deliveryId` is the **key of the `Orders` entity in the request body**, and `integration-service.cds` says so in as many words, describing it as the *"`Idempotency-Key` equivalent"*. Delivery identity travels **in the payload**, not in a header, so the header was never what CAP deduplicated on. **The open item is closed, but not the way it was written** — and the difference matters for 6.4, because it means the cutover does not need to reproduce that header at all.

### Correlation, still owned by the caller

The caller's `X-Correlation-ID` is captured into `PihCorrelationId`, forwarded to CAP, and echoed on every response — including the `409` body, which proves the same value reached CAP and came back, and the `502`, which proves the Exception Subprocess has it too. **This is the business attempt correlation ID and is not the platform's own CPI or Cloud Foundry correlation identifiers**; conflating them would attach retry semantics to an id that changes per hop.

### What Phase 6.3 does **not** prove

**At the 6.3 checkpoint SAP had not been cut over**: `ZJP_CL_DISPATCH_COORDINATOR` still posted directly to CAP over `ZJP_CAP_BASE`, every 6.3 run was driven by a test client rather than by ABAP, and Phase 5 was still the working path. **Phase 6.4 has since cut SAP over**, and Phase 5 is now the rollback rather than the live path. The receipt has not been consumed by the coordinator through CI, `PIH_SupplierResponse_v1` does not exist, and no retry or resilience behaviour beyond the platform default was configured or tested.

## 7. Phase 6.4 — the SAP cutover, runtime-verified

**SAP now delivers through Cloud Integration.** The post-commit coordinator posts the persisted `PayloadSnapshot` verbatim to `PIH_OrderDelivery_v1`, which maps it and calls the portal. This is the step the whole phase was built toward, and it was done in four checkpoints so that a failure could never be ambiguous about which hop caused it.

### The production flow, end to end

```text
RAP sendToSupplier                     (inside the order's own LUW, no network)
  → durable DeliveryIntent + immutable PayloadSnapshot + SHA-256
  → post-commit coordinator     (transaction A: claim under a lease, COMMIT)
      → destination ZJP_CI_ORDER_DELIVERY   (host, port 443, TLS, OAuth 2.0; Path Prefix EMPTY)
      → POST /http/pih/v1/order-deliveries
          → Integration Suite PIH_OrderDelivery_v1  (validate, map, call CAP)
              → CAP Supplier Portal                 (ingest, persist, receipt)
      → receipt returned unchanged through CI
  → recordDeliveryResult        (transaction B: outcome onto intent and order, COMMIT)
```

**No RAP behaviour handler performs HTTP, `COMMIT WORK` or `ROLLBACK WORK`**, which is the rule the whole outbox exists to keep. The BDEF, the handlers, the seam `ZJP_IF_OUTBOUND_TRANSPORT` and the adapter `ZJP_CL_OUTBOUND_TRANSPORT` were **not changed by the cutover at all** — the seam needed no new field and no new method, which is ADR-032's fourth decision paying off for the second time.

### What actually changed in ABAP

Only the coordinator's network section and the harness. The coordinator used to reconstruct a DTO and re-shape it into the CAP contract; it now assigns `request-body = row-payload_snapshot` and sends it. Two coordinator-owned constants supply the route `/http/pih/v1/order-deliveries` and `Content-Type: application/json`, because the mapper that used to own every wire concern is no longer on the path.

**`ZJP_CL_DLV_SNAPSHOT_READER` and `ZJP_CL_CAP_ORDER_MAPPER` are unchanged and were not deleted.** They are the Phase 5 fallback and the mapping-parity reference, and test D still exercises them directly — reader, serializer and mapper — on every harness run. They are simply no longer in the active coordinator network path.

**The snapshot is sent verbatim and is never deserialized and re-serialized.** A round trip through the reader and the serializer is byte-identical today, so it would buy nothing, and it would put a transformation back in front of the bytes whose SHA-256 was recorded with the approval. What was approved is what is sent.

**No `Idempotency-Key` is sent.** Delivery identity is the `deliveryId` **in the body**, which is the key of CAP's `Orders` entity and what CAP actually deduplicates on. The header was never the mechanism, and the cutover does not reproduce it.

### Outcome classification, unchanged by the cutover

| Transport result | Intent | Order |
| --- | --- | --- |
| `201` created | `DELIVERED` | `APPROVED` → `SENT` |
| `200` idempotent replay | `DELIVERED` | `APPROVED` → `SENT` |
| `409` conflict (also 400, 401, 403, 413) | `FAILED` | `ERROR` |
| unanswered — timeout, DNS, TLS | `UNKNOWN` | `ERROR` |
| `429`, `502`, `503` retryable | `PENDING` | unchanged |
| `500` ambiguous | `UNKNOWN` | `ERROR` |

**`classify()` was not modified for the cutover.** The table was written in Phase 5.1 against CAP's status codes and turned out to fit Cloud Integration unchanged, including the `502` that CI's Exception Subprocess emits deliberately. That is worth stating precisely rather than as a success: the fit was **confirmed**, not designed for CI, and it holds because CI passes downstream answers through as themselves (ADR-039) so the codes arriving at ABAP still mean what the table assumed.

### Runtime evidence

**6.4a — connectivity and authorization, in isolation.** A standalone transport probe reached CAP through CI over `ZJP_CI_ORDER_DELIVERY` and returned `201`, proving the SM59 destination, its OAuth 2.0 client-credentials configuration and the ABAP-supplied path before any coordinator code changed.

**6.4b — the production coordinator.** The real coordinator sent the persisted snapshot verbatim through CI.

**6.4c — real `201`, then a real `200` replay.** The full-harness test E returned `HTTP 201` with `FINAL_STATE DELIVERED`, `BUSINESS_STATUS SENT`, `PortalOrderUUID` persisted, the attempt correlation persisted and the lease cleared; the order ended `STATUS SENT` / `INTEGRATION_STATUS DELIVERED`. Test K then replayed **the exact persisted snapshot under the same `deliveryId`** and CAP answered `HTTP 200` with a receipt naming the **same delivery and the same `portalOrderId`**, with the delivered intent untouched. **No new `deliveryId`, no new source order, no second `DeliveryIntent` and no mutation of the immutable snapshot** — which is the whole claim idempotency makes.

**6.4d — real conflict, and the classification branches.** Test L sent the same `deliveryId` with one changed mapped business field, altered **only in a local test copy**, and CI returned CAP's real `HTTP 409 DELIVERY_PAYLOAD_CONFLICT` with the stored order unchanged. The coordinator's own state handling is proven deterministically rather than by damaging real evidence: `409` → `FAILED`/`ERROR` (G), unanswered → `UNKNOWN`/`ERROR` with a fresh correlation per attempt and the delivery identity preserved (H/I), and an **answered `502`** → `PENDING` with the intent returned to `PENDING`, the lease cleared and the order still `APPROVED` (M).

**Why K and L drive the transport directly.** A `DELIVERED` intent is deliberately terminal: `find_eligible` will not return it and `claim` refuses it. Forcing a reclaim would weaken the outbox's own rule to suit a test, so K and L are **transport and portal evidence** while F and G remain the coordinator state-machine evidence. Splitting them that way is what let the real `409` be proven without writing a failure onto a delivery that genuinely succeeded.

### What Phase 6.4 does **not** prove

**Retry and resilience remain unexercised.** The receiver runs on platform-default retry, and nothing has tested a timeout, a transient `5xx`, a redelivery or any bounded retry budget. The `502` evidence is about **classification**, not recovery: it proves the coordinator returns an intent to `PENDING` so a later run *may* pick it up, and separately that CI reports a technical failure cleanly. **Neither is evidence that the platform retries anything**, and the two must not be read as one.

**Nothing returns from the supplier yet.** `PIH_SupplierResponse_v1` does not exist and `applySupplierResponse` has not been written. That is Phase 6.5.

## 8. Remaining subphases

**6.5, and it is the only one left in Phase 6** — inbound `PIH_SupplierResponse_v1`, which needs `applySupplierResponse` and does not exist yet. **NOT STARTED.**

## 9. Open items

- ~~**Header ownership transfer.**~~ **Closed by Phase 6.3, and the premise was wrong.** CI sets `Content-Type` and `X-Correlation-ID` and does **not** send `Idempotency-Key` — yet 6.3b deduplicated and 6.3c conflicted correctly, because `deliveryId` is the key of the `Orders` entity in the body and is what CAP actually deduplicates on. No header ownership needs transferring at cutover.
- ~~**Receipt shape.**~~ **Closed by Phase 6.3 as recommended.** *Prepare Delivery Receipt Response* sets headers only and leaves CAP's receipt as the body, so CI reshapes nothing and the coordinator's runtime-verified `read_receipt` keeps working unchanged at cutover. Any later reshaping remains a separate decision that would now be a deliberate break.
- ~~**Exported iFlow artifact.**~~ **Closed.** [`iflows/PIH_OrderDelivery_v1.zip`](../iflows/PIH_OrderDelivery_v1.zip) is a real export and contains the deployed `.iflw`, the source XSD, the OpenAPI target and the `.mmap` mapping. The repository copies under `mappings/` are now extracted from that export rather than derived by hand.
- **Final inbound security posture, including CSRF.** Phase 6.2 runs with **CSRF protection disabled** on the HTTPS Sender, because an authenticated machine-to-machine POST was rejected with HTTP 403 before reaching the flow while it was enabled. That is the current verified configuration and **not** a declared production posture. The decision to make later: either the caller implements the CSRF token fetch-and-use flow, or the security architecture picks another supported machine-to-machine approach. Belongs with the Phase 8 security work and the 6.4 cutover, not with mapping.
- ~~**`EA → PCE` will exist in two places**~~ **Resolved by the 6.4 cutover.** Only Cloud Integration performs the mapping on the active path now. `ZJP_CL_CAP_ORDER_MAPPER` still contains the rule, but as a **reference exercised by tests**, not as a second live implementation, so the divergence risk that needed an end date is gone.
- **Retry and resilience are still untested, and 6.4 did not change that.** The receiver remains on platform-default retry with no custom behaviour, and nothing has exercised a timeout, a transient `5xx` or a redelivery. What 6.4 added is **classification** evidence: an answered `502` returns the intent to `PENDING` with the lease cleared. **Returning an intent to `PENDING` is not a retry** — no component has yet been shown to pick it up again, and `retryDelivery` does not exist. Keep the two apart when reading this row.
- ~~**The `502` contract is CI's alone.**~~ **Closed by Phase 6.4d.** The coordinator classifies an **answered** `502` as `PENDING` and an **unanswered** call as `UNKNOWN`, and the distinction holds because the seam reports `answered` and `status` separately rather than a single success flag. `classify()` needed no change. The remaining question was never classification but recovery, which is the retry row above.
- ~~**Cutover consequence worth planning for now**~~ **Done, and it was as small as predicted.** The coordinator posts the persisted snapshot verbatim and both `ZJP_CL_DLV_SNAPSHOT_READER` and `ZJP_CL_CAP_ORDER_MAPPER` left the outbound path, with the seam and the transport adapter unchanged. ADR-032's two-hop split is what made a cutover of this size possible.
