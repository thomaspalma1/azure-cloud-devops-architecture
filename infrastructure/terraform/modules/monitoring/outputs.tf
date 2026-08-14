output "log_analytics_workspace_id" {
  description = "ID do Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) usado pelo Container Apps Environment."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Chave primaria do workspace."
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string do Application Insights."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "application_insights_id" {
  description = "ID do recurso Application Insights."
  value       = azurerm_application_insights.this.id
}
