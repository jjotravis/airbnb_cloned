output "nsg_id" {
  description = "Network Security Group ID"
  value       = azurerm_network_security_group.nsg.id
}

output "nsg_name" {
  description = "Network Security Group name"
  value       = azurerm_network_security_group.nsg.name
}
