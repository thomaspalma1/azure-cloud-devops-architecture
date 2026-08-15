output "virtual_network_id" {
  description = "ID da virtual network."
  value       = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  description = "Nome da virtual network."
  value       = azurerm_virtual_network.this.name
}

output "container_apps_subnet_id" {
  description = "ID da subnet delegada ao Container Apps Environment."
  value       = azurerm_subnet.container_apps.id
}

output "private_endpoints_subnet_id" {
  description = "ID da subnet dedicada aos private endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_ids" {
  description = "Mapa de IDs das private DNS zones, indexado por servico."
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}

output "container_apps_network_security_group_id" {
  description = "ID do NSG associado a subnet do Container Apps Environment."
  value       = azurerm_network_security_group.container_apps.id
}

output "private_endpoints_network_security_group_id" {
  description = "ID do NSG associado a subnet dos private endpoints."
  value       = azurerm_network_security_group.private_endpoints.id
}
