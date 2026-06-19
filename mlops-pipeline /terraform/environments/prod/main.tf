# ============================================================
#  Production Environment — MLOps Platform
#  people.inc | Author: Venkatesh Nagelli
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "people-inc-terraform-state"
    key            = "prod/mlops/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "people-inc-terraform-lock"
  }

  required_providers {
    aws        = { source = "hashicorp/aws";       version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes"; version = "~> 2.23" }
    helm       = { source = "hashicorp/helm";       version = "~> 2.12" }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "people-inc-prod"

  default_tags {
    tags = {
      Project    = "mlops-platform"
      Company    = "people.inc"
      Environment = "prod"
      ManagedBy  = "terraform"
      Owner      = "devops"
    }
  }
}

# ── VPC ───────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name               = "mlops-prod-vpc"
  cidr               = "10.10.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets    = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnets     = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false
  environment        = "prod"
  common_tags        = local.common_tags
}

# ── EKS + GPU Nodes ───────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  cluster_name        = "mlops-prod-cluster"
  cluster_version     = "1.28"
  environment         = "prod"
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr_block
  private_subnet_ids  = module.vpc.private_subnet_ids
  gpu_instance_types  = ["g4dn.xlarge", "g4dn.2xlarge"]
  gpu_capacity_type   = "SPOT"
  gpu_node_desired    = 0
  gpu_node_max        = 8
  common_tags         = local.common_tags
}

# ── S3 — Model Artifacts ──────────────────────────────────────
resource "aws_s3_bucket" "model_artifacts" {
  bucket = "people-inc-model-artifacts"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

# Lifecycle: auto-expire old model artifacts after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    id     = "expire-old-experiments"
    status = "Enabled"
    filter { prefix = "experiments/" }
    expiration { days = 90 }
  }

  rule {
    id     = "archive-models"
    status = "Enabled"
    filter { prefix = "models/" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# ── RDS — MLflow Tracking DB ──────────────────────────────────
resource "aws_db_instance" "mlflow" {
  identifier              = "mlops-mlflow-prod"
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = "db.t3.medium"
  allocated_storage       = 50
  storage_encrypted       = true
  db_name                 = "mlflow"
  username                = "mlflow"
  password                = data.aws_secretsmanager_secret_version.db_password.secret_string
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.mlflow.name
  multi_az                = true
  backup_retention_period = 7
  skip_final_snapshot     = false
  final_snapshot_identifier = "mlflow-final-snapshot"
  tags                    = local.common_tags
}

resource "aws_db_subnet_group" "mlflow" {
  name       = "mlops-mlflow-subnet-group"
  subnet_ids = module.vpc.private_subnet_ids
  tags       = local.common_tags
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "people-inc/prod/mlflow-db-password"
}

# ── Locals ────────────────────────────────────────────────────
locals {
  common_tags = {
    Project   = "mlops-platform"
    Company   = "people.inc"
    Env       = "prod"
    ManagedBy = "terraform"
  }
}

# ── Outputs ───────────────────────────────────────────────────
output "cluster_name"          { value = module.eks.cluster_name }
output "cluster_endpoint"      { value = module.eks.cluster_endpoint }
output "model_artifacts_bucket" { value = aws_s3_bucket.model_artifacts.bucket }
output "mlflow_db_endpoint"    { value = aws_db_instance.mlflow.endpoint }
