output "resource_group_name" {
  description = "Nome do resource group do ambiente."
  value       = azurerm_resource_group.this.name
}

output "container_registry_login_server" {
  description = "FQDN do registry, usado pelo pipeline no push das imagens."
  value       = module.container_registry.login_server
}

output "container_registry_name" {
  description = "Nome do registry, usado no comando az acr login."
  value       = module.container_registry.name
}

output "container_app_environment_static_ip" {
  description = "IP estatico do environment, usado na configuracao do registro DNS."
  value       = module.container_app_environment.static_ip_address
}

output "container_app_environment_default_domain" {
  description = "Dominio padrao do Container Apps Environment."
  value       = module.container_app_environment.default_domain
}

output "web_fqdn" {
  description = "FQDN publico do front-end."
  value       = module.container_app_web.fqdn
}

output "api_fqdn" {
  description = "FQDN interno da API."
  value       = module.container_app_api.fqdn
}

output "container_app_names" {
  description = "Nomes dos Container Apps, usados pelo pipeline nos comandos de deploy e rollback."
  value = {
    api    = module.container_app_api.name
    web    = module.container_app_web.name
    worker = module.container_app_worker.name
  }
}

output "key_vault_name" {
  description = "Nome do Key Vault."
  value       = module.key_vault.name
}

output "sql_server_fqdn" {
  description = "FQDN do SQL Server."
  value       = module.sql_database.server_fqdn
}
