terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.69 e exigido pelo argumento identity_id em custom_scale_rule, usado para
      # autenticar o scaler KEDA de fila via identidade gerenciada (sem secret/connection string).
      version = ">= 4.69"
    }
  }
}
