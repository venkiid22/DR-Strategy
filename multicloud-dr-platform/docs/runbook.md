# 📖 Multi-Cloud DR Platform — Runbook

**Author:** Venkatesh Nagelli
**On-Call Slack:** `#dr-oncall`

---

## 🎯 When to invoke this runbook

- Primary AWS region (`us-east-1`) is experiencing a regional outage
- A critical service is down and cannot be restored within RTO targets via normal incident response
- A scheduled quarterly DR drill is being executed

---

## 🚨 Emergency Failover (Real Incident)

### Step 1 — Confirm this is a real regional issue, not an app bug
```bash
# Check AWS Service Health Dashboard first
curl -s https://status.aws.amazon.com/

# Confirm multiple independent services are affected, not just one app
bash scripts/health-checks/multi-region-health.sh --target primary
```

### Step 2 — Trigger failover
```bash
bash scripts/failover/trigger-failover.sh --reason "primary-region-outage-INC-XXXX"
```
This will:
1. Run pre-flight DR health check (aborts if DR is also unhealthy)
2. Prompt for typed confirmation (`FAILOVER`)
3. Run the Ansible failover playbook (promote replica, scale DR, cut DNS)
4. Run post-cutover health validation
5. Notify `#dr-oncall` on Slack at each stage

### Step 3 — Validate manually
- Log into the application as a test user
- Confirm read AND write operations succeed
- Check `docs/dr-drill-history.log` / incident channel for the automated summary

### Step 4 — Communicate
- Update status page
- Open/update the incident ticket with failover start/end timestamps
- Do NOT failback until primary region is confirmed stable for 30+ minutes

---

## 🔄 Failback (After Primary Recovers)

```bash
ansible-playbook ansible/playbooks/failback.yml -e "reason='primary-restored-INC-XXXX'"
```

This will:
1. Verify primary region health
2. Sync any data written during the DR period back to primary
3. Rebuild the DR read replica
4. Gradually shift DNS back to primary
5. Scale DR back down to warm-standby (cost savings)

**⚠️ Never failback during business-critical hours unless primary stability is fully confirmed.**

---

## 🧪 Quarterly DR Drill (Scheduled, Non-Production)

Drills run automatically via `.github/workflows/dr-drill-schedule.yml` against an isolated staging environment — never production. To run manually:

```bash
gh workflow run dr-drill-schedule.yml -f dry_run=false
```

Drill checklist:
- [ ] Pre-drill: backup recency validated (RPO compliance)
- [ ] Pre-drill: both primary and DR sites healthy
- [ ] Failover executes successfully
- [ ] Post-cutover health checks pass
- [ ] Integration test suite passes against DR
- [ ] Failback executes successfully
- [ ] Drill result logged to `docs/dr-drill-history.log`

---

## 📊 RPO / RTO Targets by Tier

| Tier | Workload Examples | RPO | RTO |
|------|-------------------|-----|-----|
| 1 — Critical | Core transaction DB, payment processing | 4 hours | 30 min |
| 2 — Standard | Application services, microservices | 24 hours | 2 hours |
| 3 — Low priority | Reporting, analytics, batch jobs | 24 hours | 8 hours |

---

## 📞 Escalation

| Role | When to escalate |
|------|------------------|
| DevOps Lead (`@venkatesh-nagelli`) | Failover not progressing after 15 min |
| Database Team | RDS promotion failures |
| Network Team | DNS propagation issues beyond 10 min |
| Azure Team | Azure Site Recovery / backup vault issues |
