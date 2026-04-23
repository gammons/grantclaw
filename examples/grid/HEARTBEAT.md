# HEARTBEAT.md

## Periodic Checks

### 1. Cluster Health (3-4x per day)
- Check all nodes: `kubectl get nodes` — all should be Ready
- Check pod status in `acme` namespace — look for CrashLoopBackOff, OOMKilled, restarts
- Check pod resource usage — any pods near limits?
- If any node NotReady or critical pod down: ALERT Alex immediately

### 2. Sidekiq Health (3-4x per day)
- Check `app_sidekiq_dead_total` and `app_sidekiq_failed_total`
- Look for spikes in dead/failed jobs — indicates backend issues
- Check Sidekiq queue depth if available
- 20 workers + 1 maintenance should be running

### 3. Verification Throughput (2-3x per day)
- Check `app_batch_rate_per_second` — should be 200-400 emails/sec
- Check `app_processed_total` — look for sudden drops
- A throughput drop could mean: pods down, IP blocks, DB issues, or Redis problems

### 4. #alerts Channel (every heartbeat)
- Check C0EXAMPLE03 for new monitoring alerts
- For each new error: check logs, look at code
- Categorize: critical (data loss, downtime) vs warning (noisy errors, edge cases)
- Flag critical issues to Alex immediately

### 5. Database & Redis (daily)
- MySQL primary + replica both running?
- Redis cache + Sidekiq both healthy?
- Check for replication lag if possible
- Storage utilization on Longhorn volumes

### 6. Infrastructure Summary (weekly)
- Post cluster health summary to Alex's DM (D0ALEX00001)
- Include: uptime, notable events, resource trends, recommendations
- Flag anything that needs attention before it becomes urgent

## State Tracking
Track last check times in `memory/heartbeat-state.json`
