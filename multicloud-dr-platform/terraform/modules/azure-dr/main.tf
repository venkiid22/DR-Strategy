# ============================================================
#  Terraform Module: Azure Disaster Recovery (Secondary Path)
#  Azure Backup Vault + Site Recovery for hybrid resilience
#  Author: Venkatesh Nagelli
# ============================================================

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.80" }
  }
}

resource "azurerm_resource_group" "dr" {
  name     = "${var.app_name}-dr-rg"
  location = var.azure_dr_region
  tags     = var.common_tags
}

# ── Recovery Services Vault ──────────────────────────────────
resource "azurerm_recovery_services_vault" "dr" {
  name                = "${var.app_name}-dr-vault"
  location            = azurerm_resource_group.dr.location
  resource_group_name = azurerm_resource_group.dr.name
  sku                 = "Standard"
  soft_delete_enabled = true

  tags = var.common_tags
}

# ── Backup Policy — Tier 1 (every 4 hours) ───────────────────
resource "azurerm_backup_policy_vm" "tier1" {
  name                = "${var.app_name}-tier1-policy"
  resource_group_name = azurerm_resource_group.dr.name
  recovery_vault_name = azurerm_recovery_services_vault.dr.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }
}

# ── Storage Account for cross-cloud backup landing zone ───────
resource "azurerm_storage_account" "dr_backup" {
  name                     = "${replace(var.app_name, "-", "")}drbackup"
  resource_group_name      = azurerm_resource_group.dr.name
  location                 = azurerm_resource_group.dr.location
  account_tier             = "Standard"
  account_replication_type = "GRS"   # Geo-redundant storage
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }

  tags = var.common_tags
}

resource "azurerm_storage_container" "dr_backup" {
  name                  = "tier1-backups"
  storage_account_name  = azurerm_storage_account.dr_backup.name
  container_access_type = "private"
}

# ── Site Recovery Fabric (for VM-based workloads) ─────────────
resource "azurerm_site_recovery_fabric" "dr" {
  name                = "${var.app_name}-asr-fabric"
  resource_group_name = azurerm_resource_group.dr.name
  recovery_vault_name = azurerm_recovery_services_vault.dr.name
  location             = var.azure_dr_region
}

resource "azurerm_site_recovery_protection_container" "dr" {
  name                 = "${var.app_name}-protection-container"
  resource_group_name  = azurerm_resource_group.dr.name
  recovery_vault_name  = azurerm_recovery_services_vault.dr.name
  recovery_fabric_name = azurerm_site_recovery_fabric.dr.name
}

# ── Key Vault for DR secrets (separate from primary cloud) ────
resource "azurerm_key_vault" "dr_secrets" {
  name                       = "${var.app_name}-dr-kv"
  resource_group_name        = azurerm_resource_group.dr.name
  location                   = azurerm_resource_group.dr.location
  tenant_id                  = var.azure_tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 30
  purge_protection_enabled   = true

  tags = var.common_tags
}

# ── Azure Monitor Alert — backup failure ──────────────────────
resource "azurerm_monitor_action_group" "dr_alerts" {
  name                = "${var.app_name}-dr-alerts"
  resource_group_name = azurerm_resource_group.dr.name
  short_name          = "drAlerts"

  email_receiver {
    name          = "devops-oncall"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_metric_alert" "backup_failure" {
  name                = "${var.app_name}-backup-failure-alert"
  resource_group_name = azurerm_resource_group.dr.name
  scopes              = [azurerm_recovery_services_vault.dr.id]
  description         = "Alert when Azure backup job fails"

  criteria {
    metric_namespace = "Microsoft.RecoveryServices/vaults"
    metric_name      = "BackupHealthEvent"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.dr_alerts.id
  }
}

# ── Outputs ───────────────────────────────────────────────────
output "recovery_vault_name"    { value = azurerm_recovery_services_vault.dr.name }
output "dr_backup_storage_account" { value = azurerm_storage_account.dr_backup.name }
output "dr_resource_group"      { value = azurerm_resource_group.dr.name }
