/**
 * Phase 6.5e — programmatic CAP boot for a standalone command.
 *
 * This exists because of a real deployed defect. The first Cloud Foundry
 * dry-run failed with:
 *
 *     Query was not inferred and includes '*' in the columns.
 *     For which there is no column name available.
 *
 * ...raised inside `@cap-js/hana`'s `cqn2sql`, before any HTTP request.
 *
 * THE ORDER IS THE WHOLE POINT. `cds.connect.to('db')` captures the model that
 * `cds.model` holds AT THAT MOMENT and stores it on the service. A later
 * `cds.model = ...` does not reach it — measured on @sap/cds 10.1.0:
 *
 *     cds.model defs before connect : none
 *     db.model  defs at connect     : none
 *     cds.model defs after assign   : 47
 *     db.model  defs after assign   : none      <-- never updated
 *
 * A database service holding a model with no definitions cannot resolve the
 * columns of `SELECT.from(SupplierResponseDeliveries)`, so the `*` never gets
 * expanded and HANA refuses to render the statement.
 *
 * Local SQLite hid it. `cds.deploy(...).to(db)` repairs `db.model` as a side
 * effect (measured: `none` before, 27 definitions after), and the deploy runs
 * only on the in-memory profile — so the one environment that never deploys was
 * the one environment that never got a usable model. Boot order that is only
 * exercised on the masked path is exactly the kind of defect that reaches
 * production, which is why the order now lives in a function with its own test
 * rather than inline in a script.
 *
 * `cds.compile.for.nodejs` rather than `cds.linked`, and that is not cosmetic:
 * it applies the runtime transformations the database layer reads, and it is
 * what this project's previously successful HANA verification tasks used.
 */

/** The parts of `cds` this bootstrap touches. Narrow so a test can stand in. */
export interface CdsBootstrapHost {
  model: any
  env: any
  load(pattern: string): Promise<any>
  compile: { for: { nodejs(csn: any): any } }
  connect: { to(name: string): Promise<any> }
  deploy(model: any): { to(db: any): Promise<any> }
}

export interface BootstrapResult {
  db: any
  /** True only on the in-memory development profile. */
  deployed: boolean
}

/**
 * The marker that distinguishes local development from every deployed target.
 *
 * Verified with `cds env requires.db` per profile: development resolves to
 * `{"url":":memory:"}` and production to HANA with no `credentials` at all
 * until a binding supplies them. A bound HANA container's `url` is a JDBC URL
 * (`jdbc:sap://...`), so exact equality against this constant can never match
 * it — the deploy branch is structurally unreachable on Cloud Foundry.
 */
export const IN_MEMORY_URL = ':memory:'

/** True only when the resolved database is the in-memory development one. */
export function isInMemory(env: any): boolean {
  return env?.requires?.db?.credentials?.url === IN_MEMORY_URL
}

/**
 * Boots CAP for a standalone command and returns the connected database.
 *
 * Deployed targets connect to the already-bound service and **nothing else**:
 * no deploy, no schema creation, no fixture seeding, no in-memory fallback.
 */
export async function bootstrapCds(
  cds: CdsBootstrapHost,
  log: (line: string) => void = () => {}
): Promise<BootstrapResult> {
  // 1. MODEL FIRST. Everything about this defect was the fact that this line
  //    used to come after the connect below.
  cds.model = cds.compile.for.nodejs(await cds.load('*'))

  // 2. Connect. The service captures the model published above, so its CQN
  //    inference works on every profile rather than only where a deploy ran.
  const db = await cds.connect.to('db')

  // 3. Development only: the in-memory database starts with no tables, so the
  //    very first SELECT would fail for a completely different reason.
  if (isInMemory(cds.env)) {
    log('Development profile: deploying the model into the in-memory database.')

    // A SEPARATELY LOADED, UNCOMPILED CSN — not `cds.model`. `cds.deploy` runs
    // the relational-database transformation itself, and handing it a model
    // that `compile.for.nodejs` already flattened makes it flatten twice:
    //
    //   Generated foreign key element "order_ID" for association "order"
    //   conflicts with existing element
    //
    // The two compilations have different targets and neither is a substitute
    // for the other, so each gets its own input.
    await cds.deploy(await cds.load('*')).to(db)
    return { db, deployed: true }
  }

  return { db, deployed: false }
}
