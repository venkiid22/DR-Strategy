# ── EKS module variables ─────────────────────────────────────
variable "cluster_name"    { type = string }
variable "cluster_version" { type = string; default = "1.28" }
variable "environment"     { type = string }
variable "vpc_id"          { type = string }
variable "vpc_cidr"        { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "gpu_instance_types" {
  type    = list(string)
  default = ["g4dn.xlarge", "g4dn.2xlarge"]
  description = "GPU instance types for ML training"
}

variable "gpu_capacity_type" {
  type    = string
  default = "SPOT"
  description = "SPOT for training (cost saving), ON_DEMAND for serving"
}

variable "gpu_node_desired" { type = number; default = 0 }
variable "gpu_node_max"     { type = number; default = 10 }

variable "common_tags" {
  type    = map(string)
  default = {}
}
