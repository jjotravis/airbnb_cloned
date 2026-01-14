variable "account_name" {
  description = "Name of the Cosmos DB account"
  type        = string
}

variable "location" {
  description = "Azure region where Cosmos DB will be created"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "mongo_server_version" {
  description = "MongoDB server version"
  type        = string
  default     = "4.2"
}

variable "throughput" {
  description = "Throughput for the MongoDB database"
  type        = number
  default     = 400
}
