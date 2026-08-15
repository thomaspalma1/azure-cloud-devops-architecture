locals {
  suffix = "${var.workload}-${var.environment}"

  private_dns_zones = {
    sql       = "privatelink.database.windows.net"
    redis     = "privatelink.redisenterprise.cache.azure.net"
    key_vault = "privatelink.vaultcore.azure.net"
    blob      = "privatelink.blob.core.windows.net"
    queue     = "privatelink.queue.core.windows.net"
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.container_apps_subnet_prefix]

  delegation {
    name = "container-apps-delegation"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoints_subnet_prefix]
}

# Toda subnet de producao deve ter um NSG associado, mesmo sem regras customizadas:
# alem de ser uma exigencia comum de policy/compliance (ex.: Azure Policy "Subnets
# should be associated with a Network Security Group"), o objeto fica pronto para
# receber regras especificas no futuro sem exigir uma mudanca estrutural.
# As regras padrao implicitas da Azure (nega entrada da Internet, permite VNet e
# Load Balancer) sao preservadas, que e o que o Container Apps Environment exige
# para o trafego de gerenciamento do plano de controle.
resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-${local.suffix}-container-apps"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = azurerm_subnet.container_apps.id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${local.suffix}-private-endpoints"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.private_dns_zones

  name                  = "link-${each.key}-${local.suffix}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
