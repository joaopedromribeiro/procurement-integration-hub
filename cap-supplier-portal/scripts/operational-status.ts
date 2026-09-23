/** Phase 7.7 read-only status command. */

import cds from '@sap/cds'
import { bootstrapCds } from '../srv/lib/cds-bootstrap'
import { readOperationalStatus } from '../srv/lib/operational-status'

async function main() {
  await bootstrapCds(cds as any)
  const status = await readOperationalStatus()
  console.log(JSON.stringify(status, null, 2))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(2)
  })
