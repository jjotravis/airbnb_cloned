resource "azurerm_cosmosdb_account" "cosmosdb" {
  name                = var.account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "MongoDB"

  consistency_policy {
    consistency_level = "Session"
  }

  capabilities {
    name = "EnableMongo"
  }

  capabilities {
    name = "mongoEnableDocLevelTTL"
  }

  automatic_failover_enabled = true

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = {
    ManagedBy = "Terraform"
  }
}

resource "azurerm_cosmosdb_mongo_database" "mongodb" {
  name                = "${var.account_name}-db"
  resource_group_name = azurerm_cosmosdb_account.cosmosdb.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmosdb.name
  throughput          = var.throughput
}
