output "id" {
  description = "ID do Key Vault."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Nome do Key Vault."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "URI do Key Vault, usado pelas aplicacoes para resolver secrets."
  value       = azurerm_key_vault.this.vault_uri
}
