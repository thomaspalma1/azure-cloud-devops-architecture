output "server_id" {
  description = "ID do SQL Server."
  value       = azurerm_mssql_server.this.id
}

output "server_name" {
  description = "Nome do SQL Server."
  value       = azurerm_mssql_server.this.name
}

output "server_fqdn" {
  description = "FQDN do SQL Server."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_name" {
  description = "Nome do banco de dados."
  value       = azurerm_mssql_database.this.name
}

output "connection_string" {
  description = "Connection string sem senha, baseada em autenticacao via Managed Identity."
  value       = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.this.name};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}
