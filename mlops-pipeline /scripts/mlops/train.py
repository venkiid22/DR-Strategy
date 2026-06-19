#!/usr/bin/env python3
"""
Model Training Script — people.inc MLOps Platform
Author: Venkatesh Nagelli | people.inc
"""

import argparse
import logging
import os
import time

import boto3
import mlflow
import mlflow.sklearn
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.metrics import (accuracy_score, f1_score, precision_score,
                             recall_score, roc_auc_score)
from sklearn.model_selection import StratifiedKFold, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description="Train AI model for people.inc platform")
    parser.add_argument("--model-name",    required=True,  help="MLflow model name")
    parser.add_argument("--mlflow-uri",    required=True,  help="MLflow tracking server URI")
    parser.add_argument("--s3-bucket",     required=True,  help="S3 bucket for artifacts")
    parser.add_argument("--experiment-name", required=True, help="MLflow experiment name")
    parser.add_argument("--data-path",     default="/tmp/train.csv", help="Training data path")
    parser.add_argument("--test-size",     type=float, default=0.2)
    parser.add_argument("--random-state",  type=int,   default=42)
    return parser.parse_args()


def load_data(s3_bucket: str, local_path: str) -> pd.DataFrame:
    """Download training data from S3."""
    log.info("Downloading training data from S3...")
    s3 = boto3.client("s3")
    s3.download_file(s3_bucket, "datasets/latest/train.csv", local_path)
    df = pd.read_csv(local_path)
    log.info(f"Dataset loaded: {len(df)} rows, {len(df.columns)} columns")
    return df


def preprocess(df: pd.DataFrame):
    """Feature engineering and preprocessing."""
    log.info("Preprocessing data...")

    # Drop nulls
    df = df.dropna()

    # Encode categoricals
    cat_cols = df.select_dtypes(include=["object"]).columns.tolist()
    cat_cols = [c for c in cat_cols if c != "label"]
    for col in cat_cols:
        df[col] = df[col].astype("category").cat.codes

    X = df.drop(columns=["label"])
    y = df["label"]

    log.info(f"Features: {X.shape[1]} | Positive class ratio: {y.mean():.3f}")
    return X, y


def build_pipeline(model_type: str = "xgboost") -> Pipeline:
    """Build sklearn pipeline with preprocessing + model."""
    models = {
        "xgboost": XGBClassifier(
            n_estimators=300,
            max_depth=6,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            use_label_encoder=False,
            eval_metric="logloss",
            random_state=42,
            n_jobs=-1
        ),
        "random_forest": RandomForestClassifier(
            n_estimators=200,
            max_depth=10,
            random_state=42,
            n_jobs=-1
        ),
        "gradient_boosting": GradientBoostingClassifier(
            n_estimators=200,
            max_depth=5,
            learning_rate=0.05,
            random_state=42
        )
    }
    return Pipeline([
        ("scaler", StandardScaler()),
        ("model", models.get(model_type, models["xgboost"]))
    ])


def cross_validate(pipeline, X, y, n_folds: int = 5):
    """Run stratified k-fold cross validation."""
    log.info(f"Running {n_folds}-fold cross validation...")
    skf = StratifiedKFold(n_splits=n_folds, shuffle=True, random_state=42)
    cv_scores = []

    for fold, (train_idx, val_idx) in enumerate(skf.split(X, y), 1):
        X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_val = y.iloc[train_idx], y.iloc[val_idx]

        pipeline.fit(X_tr, y_tr)
        preds = pipeline.predict(X_val)
        score = accuracy_score(y_val, preds)
        cv_scores.append(score)
        log.info(f"  Fold {fold}: accuracy = {score:.4f}")

    mean_cv = np.mean(cv_scores)
    std_cv  = np.std(cv_scores)
    log.info(f"CV Accuracy: {mean_cv:.4f} ± {std_cv:.4f}")
    return mean_cv, std_cv


def compute_metrics(y_true, y_pred, y_prob=None):
    """Compute full suite of classification metrics."""
    metrics = {
        "accuracy":  accuracy_score(y_true, y_pred),
        "f1":        f1_score(y_true, y_pred, average="weighted"),
        "precision": precision_score(y_true, y_pred, average="weighted", zero_division=0),
        "recall":    recall_score(y_true, y_pred, average="weighted", zero_division=0),
    }
    if y_prob is not None:
        try:
            metrics["roc_auc"] = roc_auc_score(y_true, y_prob, multi_class="ovr")
        except Exception:
            pass
    return metrics


def main():
    args = parse_args()

    # Set MLflow tracking
    mlflow.set_tracking_uri(args.mlflow_uri)
    mlflow.set_experiment(args.experiment_name)

    # Load + preprocess data
    df = load_data(args.s3_bucket, args.data_path)
    X, y = preprocess(df)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=args.test_size,
        random_state=args.random_state,
        stratify=y
    )

    with mlflow.start_run(run_name=f"{args.model_name}-{int(time.time())}") as run:
        log.info(f"MLflow run ID: {run.info.run_id}")

        # Log params
        mlflow.log_params({
            "model_name":   args.model_name,
            "test_size":    args.test_size,
            "train_rows":   len(X_train),
            "test_rows":    len(X_test),
            "n_features":   X_train.shape[1],
        })

        # Build + cross-validate
        pipeline = build_pipeline("xgboost")
        cv_mean, cv_std = cross_validate(pipeline, X_train, y_train)
        mlflow.log_metrics({"cv_accuracy_mean": cv_mean, "cv_accuracy_std": cv_std})

        # Final training on full train set
        log.info("Training final model on full training set...")
        start = time.time()
        pipeline.fit(X_train, y_train)
        train_time = time.time() - start
        log.info(f"Training time: {train_time:.1f}s")

        # Evaluate on test set
        y_pred = pipeline.predict(X_test)
        y_prob = pipeline.predict_proba(X_test) if hasattr(pipeline, "predict_proba") else None
        metrics = compute_metrics(y_test, y_pred, y_prob)

        log.info("── Test Set Metrics ──")
        for k, v in metrics.items():
            log.info(f"  {k}: {v:.4f}")

        mlflow.log_metrics(metrics)
        mlflow.log_metric("train_time_seconds", train_time)

        # Log model
        mlflow.sklearn.log_model(
            pipeline,
            artifact_path="model",
            registered_model_name=args.model_name,
            input_example=X_test.head(5),
        )

        log.info(f"✅ Model logged to MLflow: {args.model_name}")
        log.info(f"   Test accuracy: {metrics['accuracy']:.4f}")
        log.info(f"   Run ID: {run.info.run_id}")

        # Write run ID for downstream stages
        with open("/tmp/mlflow_run_id.txt", "w") as f:
            f.write(run.info.run_id)


if __name__ == "__main__":
    main()
