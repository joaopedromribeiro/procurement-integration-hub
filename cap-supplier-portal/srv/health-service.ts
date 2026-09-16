import cds from '@sap/cds'

/**
 * Phase 4.1 foundation handler.
 *
 * Reports that the CAP runtime is up. It reads no persistence and owns no
 * business rule, so it can stay unchanged while Phases 4.2 to 4.4 add the real
 * domain model and services.
 */
export default class HealthService extends cds.ApplicationService {

  private readonly startedAt = Date.now()

  init(): Promise<void> {
    this.on('ping', () => ({
      status   : 'UP',
      component: 'cap-supplier-portal',
      phase    : '4.1',
      uptimeMs : Date.now() - this.startedAt
    }))

    return super.init()
  }
}
