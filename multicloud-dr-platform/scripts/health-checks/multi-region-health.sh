#!/usr/bin/env bash
# ============================================================
#  Multi-Region Health Check — Multi-Cloud DR Platform
#  Validates both AWS primary/DR and Azure backup path health
#  Author: Venkatesh Nagelli
#  Usage : bash multi-region-health.sh --target [primary|dr] [--post-cutover]
# ============================================================

set -euo pipefail

TARGET="primary"
POST_CUTOVER=false
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
FAILED=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --target)       TARGET="$2"; shift 2 ;;
    --post-cutover) POST_CUTOVER=true; shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

declare -A ENDPOINTS=(
  [primary]="https://banking-platform.example.com"
  [dr]="https://banking-platform-dr.example.com"
)

URL="${ENDPOINTS[$TARGET]}"

echo "🔍 Multi-region health check — target: ${TARGET}"
echo "──────────────────────────────────────────────────"

check() {
  local desc="$1" url="$2" expected="${3:-200}"
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 10 "${url}" 2>/dev/null || echo "000")
  if [[ "${STATUS}" == "${expected}" ]]; then
    echo -e "${GREEN}✅ PASS${NC} [${STATUS}] ${desc}"
  else
    echo -e "${RED}❌ FAIL${NC} [${STATUS}] ${desc}"
    FAILED=1
  fi
}

# ── 1. Application health ─────────────────────────────────────
check "Application health endpoint" "${URL}/health"

# ── 2. Database connectivity (via app health detail) ──────────
check "Database connectivity check" "${URL}/health/db"

# ── 3. AWS-specific checks ─────────────────────────────────────
echo ""
echo "── AWS infrastructure checks (${TARGET}) ──"

if [[ "${TARGET}" == "dr" ]]; then
  REGION="us-west-2"
  DB_ID="banking-platform-dr-replica"
else
  REGION="us-east-1"
  DB_ID="banking-platform-primary"
fi

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "${DB_ID}" \
  --region "${REGION}" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "error")

if [[ "${RDS_STATUS}" == "available" ]]; then
  echo -e "${GREEN}✅ PASS${NC} RDS instance status: available"
else
  echo -e "${RED}❌ FAIL${NC} RDS instance status: ${RDS_STATUS}"
  FAILED=1
fi

# ── 4. EKS cluster node readiness ──────────────────────────────
CONTEXT="${TARGET}-cluster"
READY_NODES=$(kubectl --context "${CONTEXT}" get nodes \
  --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
TOTAL_NODES=$(kubectl --context "${CONTEXT}" get nodes \
  --no-headers 2>/dev/null | wc -l || echo "0")

if [[ "${READY_NODES}" -gt 0 && "${READY_NODES}" -eq "${TOTAL_NODES}" ]]; then
  echo -e "${GREEN}✅ PASS${NC} EKS nodes: ${READY_NODES}/${TOTAL_NODES} Ready"
else
  echo -e "${YELLOW}⚠️  WARN${NC} EKS nodes: ${READY_NODES}/${TOTAL_NODES} Ready"
  [[ "${TARGET}" == "dr" ]] && FAILED=1
fi

# ── 5. Post-cutover extra validation ───────────────────────────
if [[ "${POST_CUTOVER}" == "true" ]]; then
  echo ""
  echo "── Post-cutover validation ──"
  check "Write operation test (POST /health/write-test)" "${URL}/health/write-test"
  check "Read replica lag check"                          "${URL}/health/replication-lag"
fi

# ── 6. Azure backup path (informational, non-blocking) ────────
echo ""
echo "── Azure backup path (informational) ──"
echo -e "${YELLOW}ℹ️  INFO${NC} Azure Site Recovery vault checked separately via Azure Monitor"

echo ""
echo "──────────────────────────────────────────────────"
if [[ "${FAILED}" -eq 1 ]]; then
  echo -e "${RED}❌ HEALTH CHECK FAILED for ${TARGET}${NC}"
  exit 1
else
  echo -e "${GREEN}✅ ALL HEALTH CHECKS PASSED for ${TARGET}${NC}"
  exit 0
fi
