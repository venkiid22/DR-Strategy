# 🤖 MLOps & AI Platform — people.inc

> **Production-grade MLOps platform for training, deploying, and monitoring AI/ML models**  
> Built at people.inc | Kubernetes + Jenkins + Terraform + Linux | End-to-end automation

[![Pipeline Status](https://img.shields.io/badge/pipeline-passing-brightgreen)](https://github.com)
[![Terraform](https://img.shields.io/badge/terraform-1.6.x-7B42BC)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28-326CE5)](https://kubernetes.io)
[![Python](https://img.shields.io/badge/python-3.11-3776AB)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [MLOps Pipeline Stages](#mlops-pipeline-stages)
- [Infrastructure Setup](#infrastructure-setup)
- [Model Deployment Guide](#model-deployment-guide)
- [Linux Hardening](#linux-hardening)
- [Monitoring & Observability](#monitoring--observability)
- [Impact Metrics](#impact-metrics)

---

## 🎯 Overview

Built a production-grade MLOps platform at people.inc that automates the full AI/ML lifecycle — from data ingestion and model training to containerized deployment on Kubernetes. By integrating Jenkins CI/CD pipelines with automated model validation, GPU-optimized infrastructure provisioned via Terraform, and Linux-hardened compute nodes, the platform reduced model deployment time from weeks to hours and enabled data science teams to ship AI features 3x faster.

**Tools / Skills:**
`Jenkins` • `Kubernetes` • `Terraform` • `Linux/RHEL` • `Python` • `Docker` • `MLflow` • `Kubeflow` • `Prometheus` • `Grafana` • `AWS EKS` • `Helm` • `Ansible`

**Impact Metrics:**
- → 70% faster model deployment
- → 3x faster AI feature delivery
- → 40% reduction in GPU compute cost
- → 99.9% model serving uptime
- → 60% less manual ML infrastructure effort

---

## 🏗️ Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │              people.inc MLOps Platform        │
                        └─────────────────────────────────────────────┘

  Data Scientists                    Jenkins CI/CD                    Production
  ─────────────                    ─────────────────                 ───────────
  Push code/model    ──────────►   Stage 1: Lint & Test              Kubernetes
  to GitHub                        Stage 2: Model Train              (EKS)
                                   Stage 3: Model Evaluate    ──►    │
                                   Stage 4: Docker Build              ├── Model Server
                                   Stage 5: Push to ECR               │   (FastAPI)
                                   Stage 6: Helm Deploy Dev           │
                                   Stage 7: Integration Test          ├── MLflow
                                   Stage 8: Deploy Prod               │   (Tracking)
                                                                      │
  Infrastructure                  Terraform                           ├── Kubeflow
  ─────────────                   ─────────────                       │   (Pipelines)
  VPC + Subnets      ◄──────────  modules/vpc                        │
  EKS Cluster                     modules/eks                         └── Prometheus
  GPU Node Groups                 modules/gpu-nodes                       + Grafana
  Linux RHEL Nodes                Ansible hardening

```

---

## 🛠️ Tech Stack

| Category | Tools |
|----------|-------|
| **CI/CD** | Jenkins, GitHub Actions |
| **MLOps** | MLflow, Kubeflow Pipelines, Seldon Core |
| **Containerization** | Docker, Amazon ECR |
| **Orchestration** | Kubernetes (Amazon EKS), Helm, Kustomize |
| **IaC** | Terraform, Ansible |
| **OS / Linux** | RHEL 9, Ubuntu 22.04, CIS Benchmark hardening |
| **AI/ML** | Python, PyTorch, Scikit-learn, Transformers |
| **Monitoring** | Prometheus, Grafana, CloudWatch |
| **Secrets** | AWS Secrets Manager, Vault |
| **Storage** | S3, EFS (model artifacts), PostgreSQL (MLflow) |

---

## 📁 Repository Structure

```
mlops-ai-platform/
├── .github/
│   └── workflows/
│       ├── pr-validation.yml         # PR checks: lint, test, scan
│       └── model-release.yml         # Model release tagging
├── jenkins/
│   ├── pipelines/
│   │   ├── Jenkinsfile               # Main MLOps CI/CD pipeline
│   │   └── Jenkinsfile.retrain       # Model retraining pipeline
│   └── shared-libs/vars/
│       ├── trainModel.groovy         # Model training shared lib
│       ├── evaluateModel.groovy      # Model evaluation shared lib
│       └── deployModel.groovy        # Model deployment shared lib
├── terraform/
│   ├── modules/
│   │   ├── eks/                      # EKS cluster module
│   │   ├── vpc/                      # VPC & networking module
│   │   └── gpu-nodes/                # GPU node group module
│   └── environments/
│       ├── dev/                      # Dev environment config
│       └── prod/                     # Production environment config
├── kubernetes/
│   ├── base/                         # Base Kustomize manifests
│   │   ├── model-serving.yaml        # Model serving deployment
│   │   ├── mlflow.yaml               # MLflow tracking server
│   │   └── kubeflow.yaml             # Kubeflow pipelines
│   ├── mlops/
│   │   ├── seldon-model.yaml         # Seldon Core model server
│   │   └── kfp-pipeline.yaml         # Kubeflow pipeline definition
│   └── overlays/
│       ├── dev/                      # Dev overrides
│       └── prod/                     # Prod overrides
├── helm/
│   ├── model-serving/                # Model serving Helm chart
│   └── monitoring/                   # Prometheus + Grafana stack
├── scripts/
│   ├── linux-hardening/
│   │   ├── harden.sh                 # CIS benchmark hardening
│   │   └── audit.sh                  # Security audit script
│   ├── health-checks/
│   │   ├── model-health.sh           # Model endpoint health check
│   │   └── slo-check.sh              # SLO validation script
│   └── mlops/
│       ├── train.py                  # Model training script
│       ├── evaluate.py               # Model evaluation script
│       └── register.py               # MLflow model registration
├── monitoring/
│   └── alerts/
│       └── mlops-alerts.yaml         # Prometheus alert rules
├── docs/
│   ├── architecture.md               # Detailed architecture docs
│   └── runbook.md                    # Incident runbook
└── tests/
    ├── unit/                         # Unit tests
    └── integration/                  # Integration tests
```

---

## 🔄 MLOps Pipeline Stages

```
Stage 1:  Checkout & Version     →  Git clone, semantic versioning
Stage 2:  Lint & Unit Tests      →  Flake8, pytest, coverage check
Stage 3:  Data Validation        →  Great Expectations data quality
Stage 4:  Model Training         →  GPU-accelerated training job
Stage 5:  Model Evaluation       →  Accuracy, F1, AUC thresholds
Stage 6:  MLflow Registration    →  Log metrics, register model
Stage 7:  Docker Build + Scan    →  Build image, Trivy scan
Stage 8:  Push to ECR            →  Tag and push to registry
Stage 9:  Deploy Dev             →  Helm upgrade, smoke test
Stage 10: Integration Tests      →  API contract tests
Stage 11: Deploy Prod            →  Helm upgrade, canary rollout
Stage 12: Model Monitoring       →  Drift detection, SLO check
```

---

## 🚀 Infrastructure Setup

### Prerequisites
```bash
# Install tools
brew install terraform kubectl helm awscli ansible
pip install mlflow kubeflow-pipelines boto3 great-expectations

# Configure AWS
aws configure --profile people-inc-prod
```

### 1. Provision Infrastructure
```bash
cd terraform/environments/prod
terraform init
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```

### 2. Configure EKS
```bash
aws eks update-kubeconfig \
  --name mlops-prod-cluster \
  --region us-east-1 \
  --profile people-inc-prod
```

### 3. Install MLOps Stack
```bash
# Install MLflow
helm upgrade --install mlflow ./helm/model-serving \
  --namespace mlops \
  --create-namespace \
  -f helm/model-serving/values-prod.yaml

# Install monitoring
helm upgrade --install monitoring ./helm/monitoring \
  --namespace monitoring \
  --create-namespace
```

---

## 🔒 Linux Hardening

```bash
# Run CIS Benchmark hardening
sudo bash scripts/linux-hardening/harden.sh

# Run security audit
sudo bash scripts/linux-hardening/audit.sh
```

Controls implemented:
- SSH key-only authentication (password auth disabled)
- CIS Benchmark Level 2 compliance
- Auditd logging for all privileged commands
- Automatic security patching via Ansible
- iptables firewall rules
- AIDE file integrity monitoring

---

## 📊 Monitoring & Observability

**Model SLOs tracked in Grafana:**
- Prediction latency p95 < 100ms
- Model accuracy drift < 2% from baseline
- Error rate < 0.1%
- GPU utilization > 60% (cost efficiency)

---

## 📈 Impact Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Model deployment time | Weeks | Hours | **↓ 70%** |
| AI feature delivery | Baseline | 3x faster | **↑ 3x** |
| GPU compute cost | Baseline | Optimized | **↓ 40%** |
| Model serving uptime | — | 99.9% | **✅** |
| Manual ML infra effort | Baseline | Automated | **↓ 60%** |

---

## 👤 Author

**Venkatesh Nagelli** — DevOps / MLOps Engineer, people.inc  
📧 venkatesh.nagelli@outlook.com | 📍 Pittsburgh, PA  
🏆 CKA | CKAD | Azure Administrator (AZ-104)
