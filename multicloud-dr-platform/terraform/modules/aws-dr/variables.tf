# ── AWS DR module variables ──────────────────────────────────
variable "app_name" {
  type = string
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "dr_vpc_id" {
  type = string
}

variable "dr_private_subnet_ids" {
  type = list(string)
}

variable "dr_app_security_group_id" {
  type = string
}

variable "dr_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "primary_db_arn" {
  type = string
}

variable "primary_bucket_id" {
  type = string
}

variable "primary_endpoint" {
  type = string
}

variable "primary_alb_dns_name" {
  type = string
}

variable "primary_alb_zone_id" {
  type = string
}

variable "dr_alb_dns_name" {
  type = string
}

variable "dr_alb_zone_id" {
  type = string
}

variable "hosted_zone_id" {
  type = string
}

variable "app_dns_name" {
  type = string
}

variable "tier1_resource_arns" {
  type        = list(string)
  description = "ARNs of Tier-1 critical resources requiring 4hr RPO backups"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
