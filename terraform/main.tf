# Terraform Configuration for Airbnb Clone on Azure

provider "azurerm" {
  features {}
  subscription_id = "983a0886-08fb-4fdd-bd82-06673c61d6cd"
}

# Variables
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "airbnb-clone"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "norwayeast"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "aks_node_count" {
  description = "Number of nodes in AKS cluster"
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-rg"
  location = var.location

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  vnet_name          = "${var.project_name}-vnet"
  address_space      = ["10.0.0.0/16"]
  
  subnets = {
    aks = {
      name           = "aks-subnet"
      address_prefix = "10.0.1.0/24"
    }
  }
}

# Network Security Group Module
module "nsg" {
  source = "./modules/nsg"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  nsg_name           = "${var.project_name}-nsg"
  subnet_id          = module.networking.subnet_ids["aks"]
}

# Azure Container Registry
module "acr" {
  source = "./modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  acr_name           = "${replace(var.project_name, "-", "")}acr"
  sku                = "Standard"
}

# Azure Kubernetes Service
module "aks" {
  source = "./modules/aks"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  cluster_name        = "${var.project_name}-aks"
  node_count          = var.aks_node_count
  vm_size             = var.aks_vm_size
  subnet_id           = module.networking.subnet_ids["aks"]
  kubernetes_version  = "1.34.1"
}

# Attach ACR to AKS
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = module.aks.kubelet_identity_object_id
  role_definition_name             = "AcrPull"
  scope                            = module.acr.acr_id
  skip_service_principal_aad_check = true
}

# Cosmos DB with MongoDB API
module "cosmosdb" {
  source = "./modules/cosmosdb"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  account_name        = "${var.project_name}-cosmos"
  throughput          = 400
}

# Outputs
output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Name of the resource group"
}

output "aks_cluster_name" {
  value       = module.aks.cluster_name
  description = "Name of the AKS cluster"
}

output "acr_login_server" {
  value       = module.acr.login_server
  description = "ACR login server URL"
}

output "cosmosdb_connection_string" {
  value       = module.cosmosdb.connection_string
  description = "Cosmos DB connection string"
  sensitive   = true
}

output "cosmosdb_endpoint" {
  value       = module.cosmosdb.endpoint
  description = "Cosmos DB endpoint"
}
