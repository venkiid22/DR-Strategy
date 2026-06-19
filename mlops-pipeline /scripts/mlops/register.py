#!/usr/bin/env python3
"""
MLflow Model Registration Script — people.inc MLOps Platform
Author: Venkatesh Nagelli | people.inc
"""

import argparse
import logging
import sys

import mlflow
from mlflow.tracking import MlflowClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--mlflow-uri", required=True)
    parser.add_argument("--stage",      required=True, choices=["Staging", "Production", "Archived"])
    parser.add_argument("--version",    default=None,  help="Specific version to promote")
    return parser.parse_args()


def main():
    args = parse_args()
    mlflow.set_tracking_uri(args.mlflow_uri)
    client = MlflowClient()

    if args.version:
        # Promote specific version
        client.transition_model_version_stage(
            name=args.model_name,
            version=args.version,
            stage=args.stage,
            archive_existing_versions=(args.stage == "Production")
        )
        log.info(f"✅ {args.model_name} v{args.version} → {args.stage}")
        print(args.version)
    else:
        # Register latest run and get version
        run_id_file = "/tmp/mlflow_run_id.txt"
        try:
            with open(run_id_file) as f:
                run_id = f.read().strip()
        except FileNotFoundError:
            log.error("No run ID found — run train.py first")
            sys.exit(1)

        model_uri = f"runs:/{run_id}/model"
        result = mlflow.register_model(model_uri, args.model_name)
        version = result.version

        # Transition to target stage
        client.transition_model_version_stage(
            name=args.model_name,
            version=version,
            stage=args.stage
        )

        log.info(f"✅ Registered {args.model_name} v{version} → {args.stage}")

        # Add tags
        client.set_model_version_tag(args.model_name, version, "deployed_by", "jenkins-pipeline")
        client.set_model_version_tag(args.model_name, version, "company", "people.inc")

        # Print version for Jenkins to capture
        print(version)


if __name__ == "__main__":
    main()
