/**
 * Phase 4.1 foundation service.
 *
 * This service exists only to prove that the CAP runtime boots, that the REST
 * adapter serves a TypeScript handler, and that the local test harness can
 * reach it. It carries no business meaning and no persistence.
 *
 * The Phase 4 business surfaces are deliberately absent here. Integration-facing
 * ingestion arrives in Phase 4.3 and the supplier-facing read/decision API in
 * Phase 4.4, each as its own service with its own permissions.
 */
@protocol: 'rest'
@path    : '/health'
service HealthService {

  type Health : {
    status    : String(16);
    component : String(64);
    phase     : String(16);
    uptimeMs  : Integer;
  };

  function ping() returns Health;
}
