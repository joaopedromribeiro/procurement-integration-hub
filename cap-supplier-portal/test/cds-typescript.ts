/**
 * CAP resolves TypeScript service implementations only when CDS_TYPESCRIPT is set;
 * see `@sap/cds/lib/srv/factory.js`, which otherwise looks for `.js` and `.mjs` only.
 * The `cds` CLI sets it for `cds-tsx serve` and `cds-tsx watch`. A test started by
 * `node --test` bypasses that CLI, so it has to declare the same runtime itself.
 */
process.env.CDS_TYPESCRIPT ??= 'tsx'
