variable "resource_group_name" {
  description = "Nome do resource group onde o registry sera criado."
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

variable "sku" {
  description = "SKU do Azure Container Registry."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU deve ser Basic, Standard ou Premium."
  }
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
