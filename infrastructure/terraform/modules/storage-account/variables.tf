variable "resource_group_name" {
  description = "Nome do resource group onde a storage account sera criada."
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

variable "account_replication_type" {
  description = "Tipo de replicacao. LRS mantem tres copias na mesma regiao."
  type        = string
  default     = "LRS"
}

variable "uploads_container_name" {
  description = "Nome do container de blobs destinado ao upload de arquivos."
  type        = string
  default     = "uploads"
}

variable "worker_queue_name" {
  description = "Nome da fila consumida pelo Background Worker."
  type        = string
  default     = "worker-jobs"
}

variable "private_endpoint_subnet_id" {
  description = "ID da subnet onde os private endpoints serao criados."
  type        = string
}

variable "blob_private_dns_zone_id" {
  description = "ID da private DNS zone privatelink.blob.core.windows.net."
  type        = string
}

variable "queue_private_dns_zone_id" {
  description = "ID da private DNS zone privatelink.queue.core.windows.net."
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
