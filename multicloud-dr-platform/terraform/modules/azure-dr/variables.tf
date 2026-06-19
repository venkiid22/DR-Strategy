variable "app_name" {
  type = string
}

variable "azure_dr_region" {
  type    = string
  default = "westus2"
}

variable "azure_tenant_id" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
