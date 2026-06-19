# ============================================================
#  Terraform Module: AWS Disaster Recovery Infrastructure
#  Warm-standby DR region with continuous replication
#  Author: Venkatesh Nagelli
# ============================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# ── DR Region RDS Read Replica ───────────────────────────────
resource "aws_db_instance" "dr_replica" {
  identifier             = "${var.app_name}-dr-replica"
  replicate_source_db    = var.primary_db_arn
  instance_class         = var.dr_instance_class
  publicly_accessible    = false
  storage_encrypted      = true
  vpc_security_group_ids = [aws_security_group.dr_db.id]
  db_subnet_group_name   = aws_db_subnet_group.dr.name

  # Auto-promote on failover is handled by Ansible playbook, not automatic,
  # to avoid split-brain during transient network issues
  backup_retention_period = 7
  skip_final_snapshot     = false

  tags = merge(var.common_tags, {
    Name = "${var.app_name}-dr-replica"
    Tier = "disaster-recovery"
  })
}

resource "aws_db_subnet_group" "dr" {
  name       = "${var.app_name}-dr-subnet-group"
  subnet_ids = var.dr_private_subnet_ids
  tags       = var.common_tags
}

resource "aws_security_group" "dr_db" {
  name   = "${var.app_name}-dr-db-sg"
  vpc_id = var.dr_vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.dr_app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.common_tags
}

# ── S3 Cross-Region Replication ──────────────────────────────
resource "aws_s3_bucket" "dr_replica" {
  bucket = "${var.app_name}-dr-replica-${var.dr_region}"
  tags   = merge(var.common_tags, { Tier = "disaster-recovery" })
}

resource "aws_s3_bucket_versioning" "dr_replica" {
  bucket = aws_s3_bucket.dr_replica.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = var.primary_bucket_id
  versioning_configuration { status = "Enabled" }
}

resource "aws_iam_role" "replication" {
  name = "${var.app_name}-s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "s3-replication-policy"
  role = aws_iam_role.replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.primary_bucket_id}"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl"]
        Resource = ["arn:aws:s3:::${var.primary_bucket_id}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete"]
        Resource = ["${aws_s3_bucket.dr_replica.arn}/*"]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "dr" {
  depends_on = [aws_s3_bucket_versioning.primary]
  bucket     = var.primary_bucket_id
  role       = aws_iam_role.replication.arn

  rule {
    id     = "dr-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.dr_replica.arn
      storage_class = "STANDARD_IA"

      replication_time {
        status = "Enabled"
        time { minutes = 15 }
      }
      metrics {
        status = "Enabled"
        event_threshold { minutes = 15 }
      }
    }
  }
}

# ── AWS Backup Plan (Tier-based RPO) ─────────────────────────
resource "aws_backup_vault" "dr" {
  name        = "${var.app_name}-dr-vault"
  kms_key_arn = aws_kms_key.backup.arn
  tags        = var.common_tags
}

resource "aws_kms_key" "backup" {
  description             = "AWS Backup vault encryption — ${var.app_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_backup_plan" "tier1_critical" {
  name = "${var.app_name}-tier1-critical"

  rule {
    rule_name         = "every-4-hours"
    target_vault_name = aws_backup_vault.dr.name
    schedule          = "cron(0 */4 * * ? *)"   # every 4 hours — meets 4hr RPO

    lifecycle {
      delete_after = 90
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
    }
  }

  tags = merge(var.common_tags, { Tier = "1-critical" })
}

resource "aws_backup_plan" "tier2_standard" {
  name = "${var.app_name}-tier2-standard"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.dr.name
    schedule          = "cron(0 2 * * ? *)"     # daily at 2am

    lifecycle {
      delete_after = 30
    }
  }

  tags = merge(var.common_tags, { Tier = "2-standard" })
}

resource "aws_backup_selection" "tier1" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.app_name}-tier1-resources"
  plan_id      = aws_backup_plan.tier1_critical.id

  resources = var.tier1_resource_arns
}

resource "aws_iam_role" "backup" {
  name = "${var.app_name}-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# ── Route 53 Health Check + Failover Routing ─────────────────
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.common_tags, { Name = "${var.app_name}-primary-health" })
}

resource "aws_route53_record" "primary" {
  zone_id        = var.hosted_zone_id
  name           = var.app_dns_name
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "dr" {
  zone_id        = var.hosted_zone_id
  name           = var.app_dns_name
  type           = "A"
  set_identifier = "dr"

  failover_routing_policy { type = "SECONDARY" }

  alias {
    name                   = var.dr_alb_dns_name
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
}

# ── Outputs ───────────────────────────────────────────────────
output "dr_replica_db_endpoint" { value = aws_db_instance.dr_replica.endpoint }
output "dr_replica_bucket"      { value = aws_s3_bucket.dr_replica.bucket }
output "backup_vault_arn"       { value = aws_backup_vault.dr.arn }
output "primary_health_check_id" { value = aws_route53_health_check.primary.id }
