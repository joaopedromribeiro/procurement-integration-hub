# ABAP RAP application

Phase 1 is complete: the learner manually created and activated the two tables and four CDS entities in SAP S/4HANA using ADT/Eclipse. The [domain model guide](docs/phase-1-domain-model.md) includes the two confirmed compatibility corrections and synchronized source listings. Activation is learner-reported; managed CRUD/composition now also has Phase 2 SAP runtime evidence.

The learner reports Phase 2.4C runtime-verified complete: header totals 1900 → 2650 → 2800 → 2400 → 0, successful relevant COMMIT ENTITIES calls (sy-subrc 0), and `PASS: header totals 1900/2650/2800/2400/0; cleanup complete.` The persisted-parent lookup still does not support uncommitted-item deletion. No independent SAP execution by the assistant is claimed. Current checkpoint: [Phase 2.5A Supplier validation](docs/phase-2-5a-supplier-validation.md), source-prepared; SAP verification pending.

| Folder | Planned content |
| --- | --- |
| persistence/ | Custom header/item tables and draft persistence |
| cds/ | Root/child view entities, projections, associations and UI annotations |
| behavior/ | Base and projection behavior definitions |
| classes/ | Behavior pools, small domain helpers, EML examples/tests and later coordinator |
| service/ | Service definitions and actual binding/export metadata |
| docs/ | ADT setup, object inventory, activation order and verification evidence |

Naming family selected by the learner: suggested package `ZJP_PIH`, tables `ZJP_PO_H` / `ZJP_PO_I`, base views `ZJP_I_PurchaseOrder` / `ZJP_I_PurchaseOrderItem`, and projections `ZJP_C_PurchaseOrder` / `ZJP_C_PurchaseOrderItem`. This supersedes the provisional Phase 0 names. Confirm object collisions before creation. Behavior pool and service objects are not created in this phase.

The `.ddl`, `.ddls` and `.bdef` files contain source for the corresponding ADT editors. The behavior pool's `.clas.abap` and `.clas.locals_imp.abap` files go into the main class and Local Types areas of the same ADT class. These are hand-maintained files, not a complete serialized abapGit package. Select a supported serialization tool/package mapping against the actual system before a future export. No `.abapgit.xml` or automated import claim is made.

Start from the [domain model](../docs/architecture/domain-model.md) and [environment prerequisites](../docs/environments.md). An SAP system is required for activation, RAP/EML execution, ATC and real OData validation.
