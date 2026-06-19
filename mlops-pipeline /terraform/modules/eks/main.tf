# ============================================================
#  Terraform Module: EKS + GPU Node Groups
#  people.inc MLOps Platform
#  Author: Venkatesh Nagelli | people.inc
# ============================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

data "aws_caller_identity" "current" {}

# ── EKS Cluster ───────────────────────────────────────────────
resource "aws_eks_cluster" "mlops" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  encryption_config {
    resources = ["secrets"]
    provider  { key_arn = aws_kms_key.eks.arn }
  }

  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  tags = merge(var.common_tags, {
    Name        = var.cluster_name
    Environment = var.environment
    Platform    = "mlops"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]
}

# ── CloudWatch Log Group ──────────────────────────────────────
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 90
  tags              = var.common_tags
}

# ── KMS Key ───────────────────────────────────────────────────
resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption — ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.common_tags
}

# ── General Node Group (CPU) ──────────────────────────────────
resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.mlops.name
  node_group_name = "${var.cluster_name}-general"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["m5.xlarge", "m5.2xlarge"]
  capacity_type   = "ON_DEMAND"
  disk_size       = 100

  scaling_config {
    desired_size = 3
    min_size     = 2
    max_size     = 15
  }

  update_config { max_unavailable_percentage = 25 }

  labels = {
    role        = "general"
    environment = var.environment
  }

  tags = merge(var.common_tags, {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}

# ── GPU Node Group (ML Training) ─────────────────────────────
resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.mlops.name
  node_group_name = "${var.cluster_name}-gpu"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.gpu_instance_types
  capacity_type   = var.gpu_capacity_type   # SPOT for non-critical training
  disk_size       = 200

  scaling_config {
    desired_size = var.gpu_node_desired
    min_size     = 0
    max_size     = var.gpu_node_max
  }

  # Taint GPU nodes — only ML training pods scheduled here
  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    role              = "gpu-training"
    "nvidia.com/gpu"  = "true"
    workload          = "ml-training"
  }

  tags = merge(var.common_tags, {
    "k8s.io/cluster-autoscaler/enabled"                   = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"       = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/role"  = "gpu-training"
  })

  depends_on = [aws_eks_node_group.general]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}

# ── Model Serving Node Group ──────────────────────────────────
resource "aws_eks_node_group" "model_serving" {
  cluster_name    = aws_eks_cluster.mlops.name
  node_group_name = "${var.cluster_name}-model-serving"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["c5.2xlarge", "c5.4xlarge"]  # CPU-optimized for inference
  capacity_type   = "ON_DEMAND"                    # Always-on for serving
  disk_size       = 100

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 10
  }

  taint {
    key    = "workload"
    value  = "model-serving"
    effect = "NO_SCHEDULE"
  }

  labels = {
    role    = "model-serving"
    workload = "inference"
  }

  tags = var.common_tags

  depends_on = [aws_eks_node_group.general]
}

# ── Security Group ────────────────────────────────────────────
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS cluster control plane SG"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.cluster_name}-cluster-sg" })
}

# ── IAM — Cluster Role ────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# ── IAM — Node Role ───────────────────────────────────────────
resource "aws_iam_role" "eks_node" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

# S3 access for model artifacts
resource "aws_iam_role_policy" "s3_model_artifacts" {
  name = "s3-model-artifacts"
  role = aws_iam_role.eks_node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::people-inc-model-artifacts",
        "arn:aws:s3:::people-inc-model-artifacts/*"
      ]
    }]
  })
}

# ── Outputs ───────────────────────────────────────────────────
output "cluster_name"       { value = aws_eks_cluster.mlops.name }
output "cluster_endpoint"   { value = aws_eks_cluster.mlops.endpoint }
output "node_role_arn"      { value = aws_iam_role.eks_node.arn }
output "gpu_node_group"     { value = aws_eks_node_group.gpu.node_group_name }
output "oidc_issuer"        { value = aws_eks_cluster.mlops.identity[0].oidc[0].issuer }
