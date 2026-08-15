variable "resource_group_name" {
  description = "Nome do resource group onde o environment sera criado."
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

variable "infrastructure_subnet_id" {
  description = "ID da subnet delegada ao Microsoft.App/environments."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID do Log Analytics Workspace de destino dos logs das aplicacoes."
  type        = string
}

variable "internal_load_balancer_enabled" {
  description = "Quando verdadeiro, o environment nao expoe endereco publico."
  type        = bool
  default     = false
}

variable "zone_redundancy_enabled" {
  description = "Redundancia de zona. Desabilitada em homologacao por questao de custo."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
