output "id" {
  description = "ID da instancia do Azure Managed Redis."
  value       = azurerm_managed_redis.this.id
}

output "name" {
  description = "Nome da instancia."
  value       = azurerm_managed_redis.this.name
}

output "hostname" {
  description = "Hostname da instancia."
  value       = azurerm_managed_redis.this.hostname
}

output "port" {
  description = "Porta de conexao. O Azure Managed Redis utiliza 10000, diferente da porta 6380 do Azure Cache for Redis."
  value       = 10000
}
