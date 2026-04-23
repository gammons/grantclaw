# MEMORY.md - Long-Term Memory

*Last updated: 2026-04-05*

## Cluster Topology (admin@acme-prod-1)
- **Nodes:** node-1, node-2, node-3, node-4 (4 nodes)
- **Backend:** 5 pods (acme-backend-deploy)
- **Sidekiq:** 20 workers + 1 maintenance
- **Browser validators:** 8 workers + 1 controller
- **MySQL:** primary + replica (statefulsets)
- **Redis:** cache + sidekiq (statefulsets)
- **Websockets:** 1 pod

## Key Metrics (Prometheus)
- `app_batch_rate_per_second` — per-batch throughput (normal: 200-400 emails/sec)
- `app_processed_total` — total verifications
- `app_sidekiq_dead_total` — dead jobs
- `app_sidekiq_failed_total` — failed jobs

## Lessons Learned
- **Grafana dashboards may render empty in headless browser** — use the Grafana API directly (`/api/datasources/proxy/...`) to verify data
- **Prometheus runs on a separate monitoring cluster, NOT the production cluster** — don't kubectl the wrong context
