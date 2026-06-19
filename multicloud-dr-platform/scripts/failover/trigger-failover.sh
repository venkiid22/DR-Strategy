#!/usr/bin/env bash
# ============================================================
#  Trigger Failover — Multi-Cloud DR Platform
#  Entry point for manual or automated failover initiation
#  Author: Venkatesh Nagelli
#  Usage : bash trigger-failover.sh --reason "primary-region-outage"
# ============================================================

set -euo pipefail

REASON="manual-trigger"
DRY_RUN=false
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

while [[ $# -gt 0 ]]; do
  case $1 in
    --reason)  REASON="$2";  shift 2 ;;
    --dry-run) DRY_RUN=true; shift   ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

echo "══════════════════════════════════════════════════════"
echo "  🚨 MULTI-CLOUD DR FAILOVER"
echo "  Reason: ${REASON}"
echo "  Dry run: ${DRY_RUN}"
echo "  Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "══════════════════════════════════════════════════════"

# ── Safety confirmation for production (skip if automated) ───
if [[ "${AUTOMATED_TRIGGER:-false}" != "true" ]]; then
  echo -e "${YELLOW}⚠️  This will fail over PRODUCTION traffic to the DR region.${NC}"
  read -r -p "Type 'FAILOVER' to confirm: " confirm
  if [[ "${confirm}" != "FAILOVER" ]]; then
    echo "Aborted — confirmation not received."
    exit 1
  fi
fi

# ── Pre-flight: validate DR site is actually healthy ─────────
echo ""
echo "── Pre-flight: DR site health check ──"
if ! bash "$(dirname "$0")/../health-checks/multi-region-health.sh" --target dr; then
  echo -e "${RED}❌ DR site failed health check — ABORTING failover${NC}"
  echo "   Failing over to an unhealthy site would cause a full outage."
  exit 1
fi
echo -e "${GREEN}✅ DR site healthy — proceeding${NC}"

# ── Execute Ansible failover playbook ─────────────────────────
echo ""
echo "── Executing failover playbook ──"
if [[ "${DRY_RUN}" == "true" ]]; then
  ansible-playbook "$(dirname "$0")/../../ansible/playbooks/failover.yml" \
    -e "reason='${REASON}'" \
    --check
else
  ansible-playbook "$(dirname "$0")/../../ansible/playbooks/failover.yml" \
    -e "reason='${REASON}'"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ FAILOVER SEQUENCE COMPLETE${NC}"
echo "  Next steps:"
echo "    1. Verify application functionality manually"
echo "    2. Open incident ticket: docs/runbook.md"
echo "    3. Schedule failback once primary region recovers"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
