variable "resource_group_name" {
  description = "Nome do resource group onde o Key Vault sera criado."
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

variable "tenant_id" {
  description = "ID do tenant do Microsoft Entra ID."
  type        = string
}

variable "sku_name" {
  description = "SKU do Key Vault. Premium so se justifica para chaves protegidas por HSM."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU deve ser standard ou premium."
  }
}

variable "soft_delete_retention_days" {
  description = "Dias de retencao apos exclusao logica."
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "Impede exclusao definitiva antes do fim da retencao. Nao pode ser desativado apos habilitado."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "ID da subnet onde o private endpoint sera criado."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID da private DNS zone privatelink.vaultcore.azure.net."
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
