#!/usr/bin/env bash
# ============================================================
#  Model Health Check — people.inc MLOps Platform
#  Author: Venkatesh Nagelli | people.inc
#  Usage : bash model-health.sh <env>
# ============================================================

set -euo pipefail

ENV="${1:-dev}"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

declare -A URLS=(
  [dev]="https://ai-dev.people.inc"
  [prod]="https://ai.people.inc"
)

BASE_URL="${URLS[$ENV]}"
FAILED=0

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

echo "🔍 Model health checks — ${ENV}: ${BASE_URL}"
echo "──────────────────────────────────────────"

check "Liveness probe"          "${BASE_URL}/health"
check "Readiness probe"         "${BASE_URL}/ready"
check "Model info endpoint"     "${BASE_URL}/v1/model/info"
check "Predict endpoint (GET)"  "${BASE_URL}/v1/predict" "405"
check "Metrics endpoint"        "${BASE_URL}/metrics"

echo ""
[[ "${FAILED}" -eq 1 ]] && { echo -e "${RED}❌ HEALTH CHECKS FAILED${NC}"; exit 1; }
echo -e "${GREEN}✅ ALL HEALTH CHECKS PASSED${NC}"
