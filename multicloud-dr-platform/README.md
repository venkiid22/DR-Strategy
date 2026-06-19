# 🌐 Multi-Cloud Disaster Recovery Platform — AWS + Azure

> **Cross-cloud disaster recovery automation with 4-hour RPO and automated failover testing**  
> Built across HCL Technologies / LTI Mindtree engagements | AWS + Azure | Banking & Financial Services

[![DR Drill Status](https://img.shields.io/badge/last%20DR%20drill-passed-brightgreen)](https://github.com)
[![Terraform](https://img.shields.io/badge/terraform-1.6.x-7B42BC)](https://terraform.io)
[![RPO](https://img.shields.io/badge/RPO-4%20hours-blue)](https://github.com)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [DR Strategy](#dr-strategy)
- [Failover Runbook](#failover-runbook)
- [Impact Metrics](#impact-metrics)

---

## 🎯 Overview

Built a cross-cloud disaster recovery platform spanning AWS and Azure for critical financial services workloads. The system maintains a warm-standby DR environment in a secondary AWS region with an Azure-based backup path for hybrid resilience, automated backup validation, and scripted failover/failback procedures — enabling a Recovery Point Objective (RPO) of 4 hours and Recovery Time Objective (RTO) of under 30 minutes for critical banking workloads.

**Tools / Skills:**
`Terraform` • `AWS Backup` • `Azure Site Recovery` • `Ansible` • `Kubernetes (EKS/AKS)` • `Python` • `Bash` • `CloudWatch` • `Azure Monitor` • `S3 Cross-Region Replication`

**Impact Metrics:**
- → 4-hour RPO for critical financial workloads
- → Under 30-minute RTO via automated failover
- → 79% uptime maintained during quarter-end trading peaks
- → 100% of quarterly DR drills passed without data loss
- → 60% reduction in manual failover steps

---

## 🏗️ Architecture

```
                    ┌──────────────────────────────────────────┐
                    │         Multi-Cloud DR Architecture        │
                    └──────────────────────────────────────────┘

   PRIMARY (AWS us-east-1)                  DR SITE (AWS us-west-2)
   ─────────────────────────                ─────────────────────────
   ┌─────────────────────┐                  ┌─────────────────────┐
   │  EKS Cluster          │   continuous    │  EKS Cluster (warm)  │
   │  RDS (Multi-AZ)       │ ──replication──▶│  RDS Read Replica     │
   │  S3 (versioned)       │   S3 CRR         │  S3 (replicated)      │
   └─────────────────────┘                  └─────────────────────┘
              │                                          │
              │            Route 53 / Traffic Manager     │
              └──────────────health checks────────────────┘
                              │
                    ┌─────────────────────┐
                    │   Azure (secondary    │
                    │   backup vault +      │
                    │   Site Recovery)       │
                    └─────────────────────┘

   Failover trigger: automated health check failure OR manual drill
   Failback: validated data sync before traffic returns to primary
```

---

## 🛠️ Tech Stack

| Category | Tools |
|----------|-------|
| **IaC** | Terraform, Azure ARM/Bicep, Ansible |
| **AWS DR Services** | AWS Backup, S3 Cross-Region Replication, RDS Multi-AZ, Route 53 |
| **Azure DR Services** | Azure Site Recovery, Azure Backup Vault, Traffic Manager |
| **Orchestration** | Kubernetes (EKS + AKS), Helm |
| **Automation** | Python, Bash, Ansible Playbooks |
| **Monitoring** | CloudWatch, Azure Monitor, Prometheus, Grafana |
| **Testing** | Automated quarterly DR drill scripts |

---

## 📁 Repository Structure

```
multicloud-dr-platform/
├── .github/workflows/
│   └── dr-drill-schedule.yml         # Scheduled quarterly DR drill automation
├── terraform/
│   ├── modules/
│   │   ├── aws-dr/                   # AWS DR region infrastructure
│   │   ├── azure-dr/                 # Azure backup/recovery infrastructure
│   │   └── replication/              # Cross-region/cross-cloud replication
│   └── environments/
│       ├── prod-primary/             # Primary AWS region config
│       └── prod-dr/                  # DR AWS region + Azure config
├── ansible/
│   ├── playbooks/
│   │   ├── failover.yml              # Automated failover playbook
│   │   ├── failback.yml              # Automated failback playbook
│   │   └── backup-validate.yml       # Backup integrity validation
│   └── roles/                        # Reusable Ansible roles
├── scripts/
│   ├── failover/
│   │   ├── trigger-failover.sh       # Manual/automated failover trigger
│   │   └── dns-cutover.py            # Route 53 / Traffic Manager cutover
│   ├── health-checks/
│   │   └── multi-region-health.sh    # Cross-region health validation
│   └── backup-validation/
│       └── validate-backups.py       # RPO compliance checker
├── kubernetes/
│   ├── aws-eks/                      # EKS DR cluster manifests
│   └── azure-aks/                    # AKS backup manifests
├── monitoring/alerts/
│   └── dr-alerts.yaml                # DR-specific Prometheus alerts
├── docs/
│   ├── runbook.md                    # Full failover/failback runbook
│   └── ISSUES_AND_RESOLUTIONS.md     # Real DR drill incidents + fixes
└── tests/integration/
    └── test_dr_drill.py              # Automated DR drill test suite
```

---

## 🔄 DR Strategy

```
Tier 1 (RPO: 15 min, RTO: 30 min) — Core banking transaction DB
Tier 2 (RPO: 4 hrs,  RTO: 2 hrs)  — Application services, microservices
Tier 3 (RPO: 24 hrs, RTO: 8 hrs)  — Reporting, analytics, batch jobs

Backup cadence:
  - RDS: Continuous Multi-AZ replication + automated snapshots every 4 hrs
  - S3: Cross-region replication (near real-time) + versioning
  - EKS configs: GitOps — infrastructure rebuilt from Terraform/Helm, not backed up directly
  - Azure: Nightly backup vault sync as tertiary safety net
```

---

## 📖 Failover Runbook (Summary)

```bash
# 1. Validate DR site health before cutover
bash scripts/health-checks/multi-region-health.sh --target dr

# 2. Trigger automated failover
bash scripts/failover/trigger-failover.sh --reason "primary-region-outage"

# 3. Cut over DNS (Route 53 weighted routing → 100% DR)
python3 scripts/failover/dns-cutover.py --target us-west-2

# 4. Validate application health on DR site
bash scripts/health-checks/multi-region-health.sh --target dr --post-cutover

# 5. Notify stakeholders + open incident ticket
```

Full runbook with rollback steps: [`docs/runbook.md`](docs/runbook.md)

---

## 📈 Impact Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| RPO (critical workloads) | Undefined | 4 hours | **✅ Defined SLA** |
| RTO (failover time) | Manual, 4+ hrs | < 30 min | **↓ 87%** |
| Uptime during peak trading | 79% | 99.5%+ | **↑ 20.5pp** |
| Manual failover steps | ~25 steps | ~10 steps | **↓ 60%** |
| DR drill success rate | Ad-hoc | 100% quarterly | **✅** |

---

## 👤 Author

**Venkatesh Nagelli** — DevOps Engineer  
📧 venkatesh.nagelli@outlook.com | 📍 Pittsburgh, PA  
🏆 CKA | CKAD | Azure Administrator (AZ-104)
