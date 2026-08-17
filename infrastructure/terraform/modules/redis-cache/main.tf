locals {
  suffix = "${var.workload}-${var.environment}"
  name   = "redis-${local.suffix}"
}

resource "azurerm_managed_redis" "this" {
  name                      = local.name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  sku_name                  = var.sku_name
  high_availability_enabled = var.high_availability_enabled
  public_network_access     = "Disabled"
  tags                      = var.tags

  identity {
    type = "SystemAssigned"
  }

  default_database {
    clustering_policy = "EnterpriseCluster"
    eviction_policy   = var.eviction_policy
    client_protocol   = "Encrypted"
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "pep-${local.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.name}"
    private_connection_resource_id = azurerm_managed_redis.this.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-redis"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "diag-redis-cache"
  target_resource_id         = azurerm_managed_redis.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ConnectionEvents"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
