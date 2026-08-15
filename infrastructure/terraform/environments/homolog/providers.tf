terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.54"
    }
  }

  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstateacda"
  #   container_name       = "tfstate"
  #   key                  = "homolog.tfstate"
  #   use_azuread_auth     = true
  # }

  # O bloco backend está comentado porque exige uma storage account pré-existente. 
  # Em produção ele é obrigatório: 
  # sem backend remoto, o state fica local, 
  # contém segredos em text plain e diverge entre máquinas.
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}
