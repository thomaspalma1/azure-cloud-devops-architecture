variable "resource_group_name" {
  description = "Nome do resource group onde a instancia sera criada."
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

variable "sku_name" {
  description = "SKU do Azure Managed Redis. Balanced_B0 corresponde a 1 GB."
  type        = string
  default     = "Balanced_B0"
}

variable "high_availability_enabled" {
  description = "Replicacao entre dois nos. Desabilitado reduz custo e e indicado apenas para dev e homologacao."
  type        = bool
  default     = false
}

variable "eviction_policy" {
  description = "Politica de remocao de chaves quando a memoria se esgota."
  type        = string
  default     = "AllKeysLRU"
}

variable "private_endpoint_subnet_id" {
  description = "ID da subnet onde o private endpoint sera criado."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID da private DNS zone do Azure Managed Redis."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID do workspace de destino dos logs e metricas de diagnostico."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
