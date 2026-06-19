# 🐛 Issues & Resolutions — Multi-Cloud DR Platform

Real engineering issues encountered while building and operating the disaster recovery platform, with root cause analysis and fixes.

---

## Issue #1 — Failover Promoted a Lagging Replica, Causing Data Loss in Drill

**Severity:** P1 — Critical
**Component:** `ansible/playbooks/failover.yml`
**Status:** ✅ Resolved

### Symptoms
- During a quarterly DR drill, the promoted DR database was missing ~12 minutes of transactions
- `aws rds describe-db-instances` showed the replica as "available" even though replication lag was high at promotion time
- Drill was marked as a partial failure in `docs/dr-drill-history.log`

### Root Cause
The failover playbook checked the replica's **availability status**, not its **replication lag**. RDS reported the instance as healthy/available even while several minutes behind the primary, because "available" only reflects the instance being reachable — not how current the data is.

### Resolution
- Added an explicit replication lag check (`ReplicaLag` CloudWatch metric) as a pre-flight gate before promotion, with a hard threshold of 60 seconds
- If lag exceeds the threshold, the playbook now pauses and pages on-call instead of promoting automatically
- Added the `DRReplicaLagHigh` Prometheus alert so lag issues are caught hours before a real failover would ever be needed

```yaml
- name: Check DR site database replica lag
  shell: aws cloudwatch get-metric-statistics --metric-name ReplicaLag ...
  register: replica_lag

- name: Abort if lag exceeds safe threshold
  fail:
    msg: "Replica lag {{ replica_lag.stdout }}s exceeds 60s safety threshold"
  when: replica_lag.stdout | int > 60
```

**Impact:** Zero data-loss incidents in subsequent drills; lag is now caught and alerted on well before any failover event.

---

## Issue #2 — DNS Cutover Script Hung Waiting on a Already-Propagated Change

**Severity:** P3 — Medium
**Component:** `scripts/failover/dns-cutover.py`
**Status:** ✅ Resolved

### Symptoms
- `dns-cutover.py` hung for the full 5-minute waiter timeout during a drill, even though DNS had already cut over correctly
- Failover playbook took 5 extra minutes longer than expected, inflating the measured RTO

### Root Cause
The script always called `route53.get_waiter("resource_record_sets_changed").wait()` even in cases where Route 53 had already marked the change as `INSYNC` by the time the script checked. The waiter doesn't short-circuit if the resource is already in the target state when first polled in some boto3 versions combined with eventual consistency timing — the first poll request itself raced with propagation.

### Resolution
- Added an immediate status check via `get_change()` before invoking the waiter, skipping the wait entirely if the change is already `INSYNC`
- Reduced waiter poll interval from 30s to 10s for faster detection when waiting genuinely is needed

```python
status = route53.get_change(Id=change_id)["ChangeInfo"]["Status"]
if status != "INSYNC":
    waiter.wait(Id=change_id, WaiterConfig={"Delay": 10, "MaxAttempts": 30})
```

**Impact:** Cut average DNS cutover step time from ~5 min to under 45 seconds in normal cases.

---

## Issue #3 — Azure Backup Vault Silently Stopped Syncing After Key Vault Rotation

**Severity:** P2 — High
**Component:** `terraform/modules/azure-dr` (Key Vault + Recovery Services Vault)
**Status:** ✅ Resolved

### Symptoms
- Azure backup jobs showed as "succeeded" in the Azure portal for weeks
- A manual audit revealed the actual backup content hadn't changed since a Key Vault secret rotation six weeks earlier
- No alert had fired because the job status itself wasn't failing — it was succeeding while backing up stale/cached credentials

### Root Cause
The Recovery Services Vault's backup extension was using a Key Vault reference that had been rotated, but the extension's cached credential wasn't refreshed automatically. Backups continued to "succeed" against a now-orphaned snapshot source rather than failing loudly.

### Resolution
- Added a content-hash comparison step to the backup validation script — not just "did the job succeed" but "did the backed-up data actually change when source data changed"
- Set up a 90-day mandatory Key Vault secret rotation reminder tied to a forced backup-vault credential refresh step in the rotation runbook
- Added the `AzureBackupVaultSyncStale` alert as a second line of defense

**Impact:** Caught two additional stale-credential scenarios in subsequent quarterly audits before they became real incidents.

---

## Issue #4 — Trigger Script's Confirmation Prompt Blocked CI Automation

**Severity:** P3 — Medium
**Component:** `scripts/failover/trigger-failover.sh`
**Status:** ✅ Resolved

### Symptoms
- The scheduled GitHub Actions DR drill workflow hung indefinitely at the `read -r -p` confirmation prompt
- Workflow eventually timed out after 6 hours, wasting CI minutes and delaying the drill report

### Root Cause
The interactive `read` confirmation step designed to prevent a human from accidentally triggering a real production failover was also blocking the **automated, sandboxed** drill runs in CI, which have no human present to type "FAILOVER".

### Resolution
- Added an `AUTOMATED_TRIGGER` environment variable check that bypasses the interactive prompt only when explicitly set by the CI pipeline (not by a human's shell)
- CI workflow now sets `AUTOMATED_TRIGGER=true` explicitly and only ever targets the isolated staging DR environment, never production

```bash
if [[ "${AUTOMATED_TRIGGER:-false}" != "true" ]]; then
  read -r -p "Type 'FAILOVER' to confirm: " confirm
  ...
fi
```

**Impact:** Quarterly drills now run unattended and complete in ~25 minutes instead of timing out.

---

## Issue #5 — S3 Cross-Region Replication Fell Behind During Large Batch Upload

**Severity:** P2 — High
**Component:** `terraform/modules/aws-dr` (S3 replication)
**Status:** ✅ Resolved

### Symptoms
- A nightly batch job uploaded ~40GB of files to the primary bucket
- `S3ReplicationDelayed` alert fired — replication lag exceeded 30 minutes
- DR bucket was measurably behind during the exact window when an actual failover drill was scheduled

### Root Cause
Standard S3 Cross-Region Replication doesn't guarantee a fixed replication time under heavy, bursty upload volume — the default configuration replicates on a best-effort basis with no SLA.

### Resolution
- Enabled S3 Replication Time Control (RTC) on the replication rule, which adds a 15-minute SLA-backed replication guarantee for an additional cost
- Shifted the large nightly batch job's schedule to avoid overlapping with the DR drill window
- Added the replication lag check as a pre-drill gate (similar to the RDS lag check in Issue #1)

```hcl
replication_time {
  status = "Enabled"
  time { minutes = 15 }
}
```

**Impact:** Replication lag now stays under the 15-minute RTC SLA even during large batch uploads; pre-drill gate catches any remaining edge cases.

---

## 📋 Summary Table

| # | Issue | Severity | Component | Resolution Type |
|---|-------|----------|-----------|-----------------|
| 1 | Failover promoted lagging replica | P1 | Ansible / RDS | Added lag check before promotion |
| 2 | DNS cutover script hung unnecessarily | P3 | Python / Route 53 | Skip wait if already INSYNC |
| 3 | Azure backup silently stale | P2 | Terraform / Key Vault | Content-hash validation + rotation runbook |
| 4 | Confirmation prompt blocked CI | P3 | Bash / GitHub Actions | Automated-trigger env var bypass |
| 5 | S3 replication fell behind under load | P2 | Terraform / S3 RTC | Enabled Replication Time Control |

---

*All issues above were identified, triaged, and resolved as part of operating this multi-cloud DR platform across quarterly drills and production-equivalent testing.*
