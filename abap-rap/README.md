# ABAP RAP application

Phase 1 contains two table definitions and four CDS definitions for manual creation in ADT. SAP activation is pending. Follow the [step-by-step domain model guide](docs/phase-1-domain-model.md): every object has complete source, an explanation, its ADT name and a verification checkpoint.

| Folder | Planned content |
| --- | --- |
| persistence/ | Custom header/item tables and draft persistence |
| cds/ | Root/child view entities, projections, associations and UI annotations |
| behavior/ | Base and projection behavior definitions |
| classes/ | Behavior pools, small domain helpers, EML examples/tests and later coordinator |
| service/ | Service definitions and actual binding/export metadata |
| docs/ | ADT setup, object inventory, activation order and verification evidence |

Naming family selected by the learner: suggested package `ZJP_PIH`, tables `ZJP_PO_H` / `ZJP_PO_I`, base views `ZJP_I_PurchaseOrder` / `ZJP_I_PurchaseOrderItem`, and projections `ZJP_C_PurchaseOrder` / `ZJP_C_PurchaseOrderItem`. This supersedes the provisional Phase 0 names. Confirm object collisions before creation. Behavior pool and service objects are not created in this phase.

The `.ddl` and `.ddls` files contain complete source for the corresponding ADT editors. They are hand-maintained files, not serialized abapGit objects. Select a supported serialization tool/package mapping against the actual system before a future export. No `.abapgit.xml` or automated import claim is made.

Start from the [domain model](../docs/architecture/domain-model.md) and [environment prerequisites](../docs/environments.md). An SAP system is required for activation, RAP/EML execution, ATC and real OData validation.
