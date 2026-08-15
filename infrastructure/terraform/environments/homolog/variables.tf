variable "subscription_id" {
  description = "ID da subscription do Azure onde o ambiente sera provisionado."
  type        = string
}

variable "location" {
  description = "Regiao do Azure."
  type        = string
}

variable "workload" {
  description = "Abreviacao do workload usada na nomenclatura dos recursos."
  type        = string
  default     = "acda"
}

variable "environment" {
  description = "Nome do ambiente."
  type        = string
  default     = "homolog"
}

variable "entra_admin_login" {
  description = "Nome do grupo do Entra ID definido como administrador do SQL Server."
  type        = string
}

variable "entra_admin_object_id" {
  description = "Object ID do grupo administrador no Entra ID."
  type        = string
}

variable "sql_sku_name" {
  description = "SKU do Azure SQL Database."
  type        = string
  default     = "S1"
}

variable "redis_sku_name" {
  description = "SKU do Azure Managed Redis."
  type        = string
  default     = "Balanced_B0"
}

variable "container_registry_sku" {
  description = "SKU do Azure Container Registry."
  type        = string
  default     = "Basic"
}

variable "log_daily_quota_gb" {
  description = "Limite diario de ingestao de logs em GB."
  type        = number
  default     = 1
}

variable "image_tag" {
  description = "Tag das imagens de container publicadas pelo pipeline."
  type        = string
  default     = "latest"
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
