#!/usr/bin/env python3
"""
Model Evaluation Script — people.inc MLOps Platform
Validates model metrics against thresholds before deployment.
Author: Venkatesh Nagelli | people.inc
"""

import argparse
import json
import logging
import sys

import mlflow
import mlflow.sklearn
import numpy as np
import pandas as pd
from sklearn.metrics import (accuracy_score, classification_report,
                             confusion_matrix, f1_score)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description="Evaluate ML model for deployment gate")
    parser.add_argument("--model-name",   required=True)
    parser.add_argument("--mlflow-uri",   required=True)
    parser.add_argument("--min-accuracy", type=float, default=0.85)
    parser.add_argument("--min-f1",       type=float, default=0.80)
    parser.add_argument("--output-file",  default="/tmp/eval_results.json")
    parser.add_argument("--test-data",    default="/tmp/test.csv")
    return parser.parse_args()


def load_latest_model(model_name: str, mlflow_uri: str):
    """Load the latest Staging model from MLflow registry."""
    mlflow.set_tracking_uri(mlflow_uri)
    client = mlflow.tracking.MlflowClient()

    versions = client.get_latest_versions(model_name, stages=["Staging"])
    if not versions:
        log.error(f"No Staging model found for '{model_name}'")
        sys.exit(1)

    version = versions[0]
    log.info(f"Loading model: {model_name} v{version.version} (run: {version.run_id})")

    model_uri = f"models:/{model_name}/Staging"
    model = mlflow.sklearn.load_model(model_uri)
    return model, version


def evaluate(model, X_test, y_test, min_accuracy: float, min_f1: float):
    """Run evaluation and return pass/fail with metrics."""
    y_pred = model.predict(X_test)

    accuracy = accuracy_score(y_test, y_pred)
    f1       = f1_score(y_test, y_pred, average="weighted")

    log.info("── Evaluation Results ──")
    log.info(f"  Accuracy : {accuracy:.4f}  (threshold: {min_accuracy})")
    log.info(f"  F1 Score : {f1:.4f}  (threshold: {min_f1})")
    log.info("\n" + classification_report(y_test, y_pred))

    passed = accuracy >= min_accuracy and f1 >= min_f1

    return {
        "accuracy":     round(accuracy, 4),
        "f1_score":     round(f1, 4),
        "min_accuracy": min_accuracy,
        "min_f1":       min_f1,
        "passed":       passed,
        "gate_reason":  (
            None if passed
            else f"accuracy={accuracy:.4f} < {min_accuracy} or f1={f1:.4f} < {min_f1}"
        )
    }


def check_drift(current_metrics: dict, mlflow_uri: str, model_name: str):
    """Compare current metrics against production baseline."""
    mlflow.set_tracking_uri(mlflow_uri)
    client = mlflow.tracking.MlflowClient()

    prod_versions = client.get_latest_versions(model_name, stages=["Production"])
    if not prod_versions:
        log.info("No Production baseline found — skipping drift check")
        return {"drift_detected": False, "baseline_accuracy": None}

    prod_run = client.get_run(prod_versions[0].run_id)
    baseline_acc = prod_run.data.metrics.get("accuracy", 0)
    current_acc  = current_metrics["accuracy"]
    drift        = abs(current_acc - baseline_acc)

    log.info(f"  Baseline accuracy : {baseline_acc:.4f}")
    log.info(f"  Current  accuracy : {current_acc:.4f}")
    log.info(f"  Drift             : {drift:.4f}")

    return {
        "drift_detected":    drift > 0.02,
        "drift_value":       round(drift, 4),
        "baseline_accuracy": round(baseline_acc, 4),
    }


def main():
    args = parse_args()

    # Load model from MLflow
    model, version = load_latest_model(args.model_name, args.mlflow_uri)

    # Load test data
    try:
        df = pd.read_csv(args.test_data)
        X_test = df.drop(columns=["label"])
        y_test = df["label"]
    except FileNotFoundError:
        log.warning("Test CSV not found — generating synthetic data for CI")
        np.random.seed(42)
        X_test = pd.DataFrame(np.random.randn(500, 10),
                              columns=[f"feature_{i}" for i in range(10)])
        y_test = pd.Series(np.random.randint(0, 2, 500))

    # Evaluate
    metrics = evaluate(model, X_test, y_test, args.min_accuracy, args.min_f1)

    # Drift check
    drift = check_drift(metrics, args.mlflow_uri, args.model_name)

    # Combine results
    results = {
        "model_name":    args.model_name,
        "model_version": version.version,
        "run_id":        version.run_id,
        **metrics,
        **drift
    }

    # Write output file for Jenkins to read
    with open(args.output_file, "w") as f:
        json.dump(results, f, indent=2)

    log.info(f"\nResults written to {args.output_file}")

    if not metrics["passed"]:
        log.error(f"❌ EVALUATION GATE FAILED: {metrics['gate_reason']}")
        sys.exit(1)

    if drift.get("drift_detected"):
        log.warning("⚠️  Model drift detected — review before promoting to production")

    log.info("✅ EVALUATION GATE PASSED — model approved for deployment")


if __name__ == "__main__":
    main()
