output "id" {
  description = "ID do Container App."
  value       = azurerm_container_app.this.id
}

output "name" {
  description = "Nome do Container App."
  value       = azurerm_container_app.this.name
}

output "fqdn" {
  description = "FQDN da aplicacao. Nulo quando nao ha ingress configurado."
  value       = var.ingress == null ? null : azurerm_container_app.this.ingress[0].fqdn
}

output "identity_principal_id" {
  description = "Principal ID da identidade gerenciada da aplicacao."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "identity_client_id" {
  description = "Client ID da identidade gerenciada, usado na autenticacao via Entra ID."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "identity_id" {
  description = "ID do recurso de identidade gerenciada."
  value       = azurerm_user_assigned_identity.this.id
}
