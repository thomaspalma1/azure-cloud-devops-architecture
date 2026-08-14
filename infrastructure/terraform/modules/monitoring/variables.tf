variable "resource_group_name" {
  description = "Nome do resource group onde os recursos de monitoramento serao criados."
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

variable "retention_in_days" {
  description = "Retencao dos logs no workspace. Ate 31 dias nao ha custo adicional de retencao."
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Limite diario de ingestao em GB. Protege contra custo descontrolado por loop de log."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
