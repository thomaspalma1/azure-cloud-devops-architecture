locals {
  name = "st${replace("${var.workload}${var.environment}", "-", "")}"

  private_endpoints = {
    blob = {
      subresource = "blob"
      dns_zone_id = var.blob_private_dns_zone_id
    }
    queue = {
      subresource = "queue"
      dns_zone_id = var.queue_private_dns_zone_id
    }
  }
}

resource "azurerm_storage_account" "this" {
  name                            = local.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.account_replication_type
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  tags                            = var.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "uploads" {
  name                  = var.uploads_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_queue" "worker" {
  name               = var.worker_queue_name
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                = "pep-${local.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.name}-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-${each.key}"
    private_dns_zone_ids = [each.value.dns_zone_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "queue" {
  name                       = "diag-storage-queue"
  target_resource_id         = "${azurerm_storage_account.this.id}/queueServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_metric {
    category = "Transaction"
  }
}
