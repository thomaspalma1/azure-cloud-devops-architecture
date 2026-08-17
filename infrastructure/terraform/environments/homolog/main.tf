locals {
  suffix = "${var.workload}-${var.environment}"

  tags = merge(var.tags, {
    workload    = var.workload
    environment = var.environment
    managed_by  = "terraform"
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.suffix}"
  location = var.location
  tags     = local.tags
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workload            = var.workload
  environment         = var.environment
  tags                = local.tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workload            = var.workload
  environment         = var.environment
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

module "container_registry" {
  source = "../../modules/container-registry"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  workload                   = var.workload
  environment                = var.environment
  sku                        = var.container_registry_sku
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

module "key_vault" {
  source = "../../modules/key-vault"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  workload                   = var.workload
  environment                = var.environment
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_id        = module.networking.private_dns_zone_ids["key_vault"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

resource "azurerm_role_assignment" "deployer_key_vault_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "sql_database" {
  source = "../../modules/sql-database"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  workload                   = var.workload
  environment                = var.environment
  sku_name                   = var.sql_sku_name
  entra_admin_login          = var.entra_admin_login
  entra_admin_object_id      = var.entra_admin_object_id
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_id        = module.networking.private_dns_zone_ids["sql"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

module "redis_cache" {
  source = "../../modules/redis-cache"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  workload                   = var.workload
  environment                = var.environment
  sku_name                   = var.redis_sku_name
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_id        = module.networking.private_dns_zone_ids["redis"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

module "storage_account" {
  source = "../../modules/storage-account"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  workload                   = var.workload
  environment                = var.environment
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  blob_private_dns_zone_id   = module.networking.private_dns_zone_ids["blob"]
  queue_private_dns_zone_id  = module.networking.private_dns_zone_ids["queue"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

resource "azurerm_key_vault_secret" "app_insights_connection_string" {
  name         = "ApplicationInsights--ConnectionString"
  value        = module.monitoring.application_insights_connection_string
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployer_key_vault_officer]
}

resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "ConnectionStrings--SqlDatabase"
  value        = module.sql_database.connection_string
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployer_key_vault_officer]
}

resource "azurerm_key_vault_secret" "redis_host" {
  name         = "Redis--Host"
  value        = "${module.redis_cache.hostname}:${module.redis_cache.port}"
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployer_key_vault_officer]
}

module "container_app_environment" {
  source = "../../modules/container-app-environment"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  workload                   = var.workload
  environment                = var.environment
  infrastructure_subnet_id   = module.networking.container_apps_subnet_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

module "container_app_api" {
  source = "../../modules/container-app"

  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  workload                        = var.workload
  environment                     = var.environment
  app_name                        = "api"
  container_app_environment_id    = module.container_app_environment.id
  container_registry_id           = module.container_registry.id
  container_registry_login_server = module.container_registry.login_server
  key_vault_id                    = module.key_vault.id
  image                           = "api:${var.image_tag}"
  cpu                             = 0.5
  memory                          = "1Gi"
  min_replicas                    = 0
  max_replicas                    = 5
  http_scale_concurrent_requests  = 50

  ingress = {
    external_enabled = false
    target_port      = 8080
  }

  # A porta de escuta e definida no proprio Dockerfile (ASPNETCORE_HTTP_PORTS=8080)
  # e refletida aqui apenas no target_port do ingress, para nao existir em dois lugares.
  env_vars = {
    ASPNETCORE_ENVIRONMENT = "Homolog"
  }

  secrets = {
    "sql-connection-string" = {
      key_vault_secret_id = azurerm_key_vault_secret.sql_connection_string.versionless_id
      env_var_name        = "ConnectionStrings__SqlDatabase"
    }
    "appinsights-connection-string" = {
      key_vault_secret_id = azurerm_key_vault_secret.app_insights_connection_string.versionless_id
      env_var_name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
    }
    "redis-host" = {
      key_vault_secret_id = azurerm_key_vault_secret.redis_host.versionless_id
      env_var_name        = "Redis__Host"
    }
  }

  tags = local.tags
}

module "container_app_web" {
  source = "../../modules/container-app"

  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  workload                        = var.workload
  environment                     = var.environment
  app_name                        = "web"
  container_app_environment_id    = module.container_app_environment.id
  container_registry_id           = module.container_registry.id
  container_registry_login_server = module.container_registry.login_server
  key_vault_id                    = module.key_vault.id
  image                           = "web:${var.image_tag}"
  cpu                             = 0.25
  memory                          = "0.5Gi"
  min_replicas                    = 0
  max_replicas                    = 3
  http_scale_concurrent_requests  = 50

  ingress = {
    external_enabled = true
    target_port      = 8080
  }

  # O container do front-end roda nginx servindo arquivos estaticos, nao um processo .NET.
  # A configuracao da aplicacao Angular e resolvida em build time (--build-arg
  # BUILD_CONFIGURATION), entao nao ha variavel de ambiente de runtime a injetar aqui.
  secrets = {
    "appinsights-connection-string" = {
      key_vault_secret_id = azurerm_key_vault_secret.app_insights_connection_string.versionless_id
      env_var_name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
    }
  }

  tags = local.tags
}

module "container_app_worker" {
  source = "../../modules/container-app"

  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  workload                        = var.workload
  environment                     = var.environment
  app_name                        = "worker"
  container_app_environment_id    = module.container_app_environment.id
  container_registry_id           = module.container_registry.id
  container_registry_login_server = module.container_registry.login_server
  key_vault_id                    = module.key_vault.id
  image                           = "worker:${var.image_tag}"
  cpu                             = 0.5
  memory                          = "1Gi"
  min_replicas                    = 0
  max_replicas                    = 5

  queue_scale = {
    queue_name   = module.storage_account.worker_queue_name
    queue_length = 20
    account_name = module.storage_account.name
  }

  env_vars = {
    DOTNET_ENVIRONMENT = "Homolog"
  }

  secrets = {
    "sql-connection-string" = {
      key_vault_secret_id = azurerm_key_vault_secret.sql_connection_string.versionless_id
      env_var_name        = "ConnectionStrings__SqlDatabase"
    }
    "appinsights-connection-string" = {
      key_vault_secret_id = azurerm_key_vault_secret.app_insights_connection_string.versionless_id
      env_var_name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
    }
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "api_storage_blob" {
  scope                = module.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.container_app_api.identity_principal_id
}

resource "azurerm_role_assignment" "api_storage_queue" {
  scope                = module.storage_account.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = module.container_app_api.identity_principal_id
}

resource "azurerm_role_assignment" "worker_storage_blob" {
  scope                = module.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.container_app_worker.identity_principal_id
}

resource "azurerm_role_assignment" "worker_storage_queue" {
  scope                = module.storage_account.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = module.container_app_worker.identity_principal_id
}