variable "resource_group_name" {
  description = "Nome do resource group onde os recursos de rede serao criados."
  type        = string
}

variable "location" {
  description = "Região do Azure"
  type        = string
}

variable "workload" {
  description = "Abreviacao do workload usada na nomenclatura dos recursos."
  type        = string
}

variable "enviroment" {
  description = "Nome do ambiente"
  type        = string
}

variable "address_space" {
  description = "Espaco de enderecamento da virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "container_apps_subnet_prefix" {
  description = "Prefixo da subnet delegada ao Container Apps Environment. Exige no minimo /23."
  type        = string
  default     = "10.20.0.0/23"

  validation {
    condition     = tonumber(split("/", var.container_apps_subnet_prefix)[1]) <= 23
    error_message = "A subnet do Container Apps Environment exige prefixo /23 ou maior."
  }
}

variable "private_endpoints_subnet_prefix" {
  description = "Prefixo da subnet dedicada aos private endpoints."
  type        = string
  default     = "10.20.2.0/24"
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}