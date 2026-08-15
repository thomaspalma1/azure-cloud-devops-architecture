locals {
  suffix = "${var.workload}-${var.environment}"
  name   = "ca-${var.app_name}-${local.suffix}"
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.app_name}-${local.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_container_app" "this" {
  name                         = local.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  registry {
    server   = var.container_registry_login_server
    identity = azurerm_user_assigned_identity.this.id
  }

  dynamic "secret" {
    for_each = var.secrets

    content {
      name                = secret.key
      key_vault_secret_id = secret.value.key_vault_secret_id
      identity            = azurerm_user_assigned_identity.this.id
    }
  }

  dynamic "ingress" {
    for_each = var.ingress == null ? [] : [var.ingress]

    content {
      external_enabled = ingress.value.external_enabled
      target_port      = ingress.value.target_port
      transport        = "auto"

      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.app_name
      image  = "${var.container_registry_login_server}/${var.image}"
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.env_vars

        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets

        content {
          name        = env.value.env_var_name
          secret_name = env.key
        }
      }

      dynamic "liveness_probe" {
        for_each = var.ingress == null ? [] : [1]

        content {
          transport = "HTTP"
          port      = var.ingress.target_port
          path      = var.health_probe_path
        }
      }

      dynamic "startup_probe" {
        for_each = var.ingress == null ? [] : [1]

        content {
          transport = "HTTP"
          port      = var.ingress.target_port
          path      = var.health_probe_path
        }
      }
    }

    dynamic "http_scale_rule" {
      for_each = var.http_scale_concurrent_requests == null ? [] : [1]

      content {
        name                = "http-concurrency"
        concurrent_requests = var.http_scale_concurrent_requests
      }
    }

    dynamic "custom_scale_rule" {
      for_each = var.queue_scale == null ? [] : [var.queue_scale]

      content {
        name             = "queue-depth"
        custom_rule_type = "azure-queue"

        metadata = {
          accountName = custom_scale_rule.value.account_name
          queueName   = custom_scale_rule.value.queue_name
          queueLength = tostring(custom_scale_rule.value.queue_length)
        }

        authentication {
          secret_name       = "queue-identity"
          trigger_parameter = "workloadIdentity"
        }
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets_user
  ]
}
