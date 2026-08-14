output "id" {
  description = "ID do Azure Container Registry."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Nome do registry."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "FQDN do registry, usado nas tags de imagem e no deploy dos Container Apps."
  value       = azurerm_container_registry.this.login_server
}
