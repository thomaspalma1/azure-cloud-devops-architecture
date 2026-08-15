output "id" {
  description = "ID do Container Apps Environment."
  value       = azurerm_container_app_environment.this.id
}

output "name" {
  description = "Nome do Container Apps Environment."
  value       = azurerm_container_app_environment.this.name
}

output "default_domain" {
  description = "Dominio padrao do environment, sufixo dos FQDNs das aplicacoes."
  value       = azurerm_container_app_environment.this.default_domain
}

output "static_ip_address" {
  description = "Endereco IP estatico do environment, usado na configuracao de DNS."
  value       = azurerm_container_app_environment.this.static_ip_address
}
