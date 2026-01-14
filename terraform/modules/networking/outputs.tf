output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "VNet name"
  value       = azurerm_virtual_network.vnet.name
}

output "subnet_ids" {
  description = "Map of subnet IDs"
  value       = { for k, v in azurerm_subnet.subnets : k => v.id }
}
