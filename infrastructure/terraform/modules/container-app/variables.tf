variable "resource_group_name" {
  description = "Nome do resource group onde a aplicacao sera criada."
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

variable "app_name" {
  description = "Nome curto da aplicacao, como api, web ou worker."
  type        = string
}

variable "container_app_environment_id" {
  description = "ID do Container Apps Environment que hospeda a aplicacao."
  type        = string
}

variable "container_registry_id" {
  description = "ID do Azure Container Registry, usado na atribuicao da role AcrPull."
  type        = string
}

variable "container_registry_login_server" {
  description = "FQDN do registry."
  type        = string
}

variable "key_vault_id" {
  description = "ID do Key Vault, usado na atribuicao da role Key Vault Secrets User."
  type        = string
}

variable "image" {
  description = "Nome da imagem sem o registry, incluindo a tag."
  type        = string
}

variable "cpu" {
  description = "Cores de CPU alocados por replica."
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memoria alocada por replica."
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Numero minimo de replicas. Zero habilita scale to zero."
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Numero maximo de replicas."
  type        = number
  default     = 5
}

variable "ingress" {
  description = "Configuracao de ingress. Nulo cria a aplicacao sem entrada HTTP."
  type = object({
    external_enabled = bool
    target_port      = number
  })
  default = null
}

variable "http_scale_concurrent_requests" {
  description = "Requisicoes concorrentes por replica antes de escalar. Nulo desabilita a regra HTTP."
  type        = number
  default     = null
}

variable "queue_scale" {
  description = "Regra de escala por profundidade de fila. Nulo desabilita a regra."
  type = object({
    queue_name   = string
    queue_length = number
    account_name = string
  })
  default = null
}

variable "health_probe_path" {
  description = "Caminho do endpoint de health check. Aplicavel apenas quando ha ingress."
  type        = string
  default     = "/healthz"
}

variable "env_vars" {
  description = "Variaveis de ambiente nao sensiveis."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets resolvidos no Key Vault e expostos como variaveis de ambiente."
  type = map(object({
    key_vault_secret_id = string
    env_var_name        = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
