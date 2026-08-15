locals {
  suffix = "${var.workload}-${var.environment}"
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${local.suffix}"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  infrastructure_subnet_id       = var.infrastructure_subnet_id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  internal_load_balancer_enabled = var.internal_load_balancer_enabled
  zone_redundancy_enabled        = var.zone_redundancy_enabled
  tags                           = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}
