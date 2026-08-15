variable "resource_group_name" {
  description = "Nome do resource group onde o SQL Server sera criado."
  type        = string
}

variable "location" {
  description = "Regiao do Azure."
  type        = string
}

variable "workload" {
  description = "Abreviacao do workload usada na nomenclatura dos recursos."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente."
  type        = string
}

variable "database_name" {
  description = "Nome do banco de dados."
  type        = string
  default     = "appdb"
}

variable "sku_name" {
  description = "SKU do banco. S1 equivale a 20 DTU com 250 GB inclusos."
  type        = string
  default     = "S1"
}

variable "max_size_gb" {
  description = "Tamanho maximo do banco em GB."
  type        = number
  default     = 50
}

variable "entra_admin_login" {
  description = "Nome do grupo ou usuario do Entra ID definido como administrador do SQL Server."
  type        = string
}

variable "entra_admin_object_id" {
  description = "Object ID do grupo ou usuario administrador no Entra ID."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "ID da subnet onde o private endpoint sera criado."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID da private DNS zone privatelink.database.windows.net."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID do workspace de destino dos logs de diagnostico."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
