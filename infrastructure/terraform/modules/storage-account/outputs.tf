output "id" {
  description = "ID da storage account."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Nome da storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Endpoint de blob da storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_queue_endpoint" {
  description = "Endpoint de fila da storage account."
  value       = azurerm_storage_account.this.primary_queue_endpoint
}

output "uploads_container_name" {
  description = "Nome do container de uploads."
  value       = azurerm_storage_container.uploads.name
}

output "worker_queue_name" {
  description = "Nome da fila consumida pelo Worker."
  value       = azurerm_storage_queue.worker.name
}
