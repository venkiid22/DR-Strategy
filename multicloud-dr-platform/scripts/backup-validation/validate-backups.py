#!/usr/bin/env python3
"""
Backup Validation Script — Multi-Cloud DR Platform
Verifies RPO compliance by checking actual backup recency against SLA.
Author: Venkatesh Nagelli
"""

import argparse
import logging
import sys
from datetime import datetime, timedelta, timezone

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

# RPO SLA per tier, in hours
TIER_RPO_HOURS = {
    "tier1": 4,
    "tier2": 24,
    "tier3": 24,
}


def parse_args():
    parser = argparse.ArgumentParser(description="Validate backup recency against RPO SLA")
    parser.add_argument("--vault-name", required=True)
    parser.add_argument("--region",     default="us-east-1")
    parser.add_argument("--tier",       default="tier1", choices=TIER_RPO_HOURS.keys())
    return parser.parse_args()


def get_latest_recovery_point(backup_client, vault_name: str):
    """Find the most recent successful recovery point in the vault."""
    response = backup_client.list_recovery_points_by_backup_vault(
        BackupVaultName=vault_name,
        MaxResults=50
    )

    points = response.get("RecoveryPoints", [])
    completed = [p for p in points if p.get("Status") == "COMPLETED"]

    if not completed:
        return None

    latest = max(completed, key=lambda p: p["CreationDate"])
    return latest


def validate_rpo(latest_point, rpo_hours: int):
    """Check if the latest backup is within the RPO window."""
    now = datetime.now(timezone.utc)
    backup_age = now - latest_point["CreationDate"]
    rpo_limit = timedelta(hours=rpo_hours)

    compliant = backup_age <= rpo_limit

    return {
        "compliant":        compliant,
        "backup_age_hours": round(backup_age.total_seconds() / 3600, 2),
        "rpo_limit_hours":  rpo_hours,
        "last_backup_time": latest_point["CreationDate"].isoformat(),
        "resource_arn":     latest_point.get("ResourceArn", "unknown"),
    }


def main():
    args = parse_args()
    backup_client = boto3.client("backup", region_name=args.region)

    log.info(f"Checking backup vault: {args.vault_name} (region: {args.region})")
    log.info(f"Tier: {args.tier} | RPO SLA: {TIER_RPO_HOURS[args.tier]} hours")

    latest = get_latest_recovery_point(backup_client, args.vault_name)

    if latest is None:
        log.error("❌ No completed recovery points found in vault!")
        sys.exit(1)

    result = validate_rpo(latest, TIER_RPO_HOURS[args.tier])

    log.info(f"  Last backup     : {result['last_backup_time']}")
    log.info(f"  Backup age      : {result['backup_age_hours']} hours")
    log.info(f"  RPO SLA         : {result['rpo_limit_hours']} hours")
    log.info(f"  Resource        : {result['resource_arn']}")

    if result["compliant"]:
        log.info("✅ RPO COMPLIANT — backup is within SLA window")
        sys.exit(0)
    else:
        log.error(
            f"❌ RPO VIOLATION — backup is {result['backup_age_hours']}h old, "
            f"exceeds {result['rpo_limit_hours']}h SLA"
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
