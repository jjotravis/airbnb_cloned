output "cosmosdb_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.cosmosdb.id
}

output "endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.cosmosdb.endpoint
}

output "connection_string" {
  description = "Primary MongoDB connection string"
  value       = azurerm_cosmosdb_account.cosmosdb.primary_mongodb_connection_string
  sensitive   = true
}

output "cosmosdb_connection_strings" {
  description = "Connection strings for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.cosmosdb.primary_mongodb_connection_string
  sensitive   = true
}

output "cosmosdb_primary_key" {
  description = "Primary key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.cosmosdb.primary_key
  sensitive   = true
}
