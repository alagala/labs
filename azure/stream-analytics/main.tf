variable "project_name" {
  default = "streaming"
}

variable "project_location" {
  default = "southeastasia"
}

#
# Configure the Microsoft Azure Provider.
#
provider "azurerm" {
  # This AzureRM Provider is configured to authenticate to Azure
  # using a Service Principal with a Client Secret - therefore
  # ensure that you have exported the following environment variables:
  
  # ARM_CLIENT_ID       = "..."
  # ARM_CLIENT_SECRET   = "..."
  # ARM_SUBSCRIPTION_ID = "..."
  # ARM_TENANT_ID       = "..."

  version = "=1.27.1"
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

#
# Configure the resource group.
#
resource "azurerm_resource_group" "poc_rg" {
  name     = "${var.project_name}-poc-rg"
  location = "${var.project_location}"
}

#
# Configure the Blob Storage account that will be used to archive (capture) the data streams.
#
resource "azurerm_storage_account" "poc_storage_account" {
  name                     = "${var.project_name}${random_integer.ri.result}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  location                 = "${azurerm_resource_group.poc_rg.location}"
  account_kind             = "BlobStorage"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  network_rules {
    bypass                 = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "poc_storage_container" {
  name                  = "archive"
  resource_group_name   = "${azurerm_resource_group.poc_rg.name}"
  storage_account_name  = "${azurerm_storage_account.poc_storage_account.name}"
  container_access_type = "private"
}

#
# Configure the Kafka-enabled Events Hub resource.
#
resource "azurerm_eventhub_namespace" "poc_eh_ns" {
  name                     = "${var.project_name}-kafka-${random_integer.ri.result}"
  location                 = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  sku                      = "Standard"
  capacity                 = 2
  auto_inflate_enabled     = true
  maximum_throughput_units = 4
  kafka_enabled            = true
}

resource "azurerm_eventhub" "poc_eventhub" {
  name                     = "${var.project_name}-poc-tweets"
  namespace_name           = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  partition_count          = 4
  message_retention        = 7
  
  capture_description {
    enabled                = true
    encoding               = "AvroDeflate"
    interval_in_seconds    = 300
    size_limit_in_bytes    = 33554432
    skip_empty_archives    = false

    destination {
      name                 = "EventHubArchive.AzureBlockBlob"
      archive_name_format  = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}{Minute}{Second}"
      blob_container_name  = "${azurerm_storage_container.poc_storage_container.name}"
      storage_account_id   = "${azurerm_storage_account.poc_storage_account.id}"
    }
  }
}

resource "azurerm_eventhub_authorization_rule" "producer_key" {
  name                = "ProducerSharedAccessKey"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  listen              = false
  send                = true
  manage              = false
}

resource "azurerm_eventhub_authorization_rule" "consumer_key" {
  name                = "ConsumerSharedAccessKey"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  listen              = true
  send                = false
  manage              = false
}

output "eventhub_primary_connection_string" {
  value = "${azurerm_eventhub_authorization_rule.producer_key.primary_connection_string}"
}

##
## Store the Cosmos DB and Storage Account secrets in Azure Key Vault.
##
#resource "azurerm_key_vault" "poc_key_vault" {
#  name                = "${var.project_name}poc${random_integer.ri.result}"
#  location            = "${azurerm_resource_group.poc_rg.location}"
#  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
#  tenant_id           = "${data.azurerm_client_config.current.tenant_id}"
#
#  sku {
#    name = "standard"
#  }
#
#  access_policy {
#    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
#    object_id = "${data.azurerm_client_config.current.service_principal_object_id}"
#
#    secret_permissions = [
#      "get", "set", "delete"
#    ]
#  }
#
#  # network_acls {
#  #   virtual_network_subnet_ids = ["${azurerm_subnet.adb_public_subnet.id}", "${azurerm_subnet.adb_private_subnet.id}"]
#  #   bypass                     = "AzureServices"
#  #   default_action             = "Deny"
#  # }
#}
#
#resource "azurerm_key_vault_secret" "secret_cosmos_uri" {
#  name         = "Cosmos-DB-URI"
#  value        = "${azurerm_cosmosdb_account.poc_cosmos.endpoint}"
#  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
#}
#
#resource "azurerm_key_vault_secret" "secret_cosmos_key" {
#  name         = "Cosmos-DB-Key"
#  value        = "${azurerm_cosmosdb_account.poc_cosmos.primary_master_key}"
#  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
#}
#
#resource "azurerm_key_vault_secret" "secret_storage_name" {
#  name         = "ADLS-Gen2-Account-Name"
#  value        = "${azurerm_storage_account.poc_storage_account.name}"
#  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
#}
#
#resource "azurerm_key_vault_secret" "secret_storage_key" {
#  name         = "ADLS-Gen2-Account-Key"
#  value        = "${azurerm_storage_account.poc_storage_account.primary_access_key}"
#  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
#}
#
##
## Define the output variables that are needed in the application.
##
#output "key_vault_id" {
#  value = "${azurerm_key_vault.poc_key_vault.id}"
#}
#
#output "key_vault_uri" {
#  value = "${azurerm_key_vault.poc_key_vault.vault_uri}"
#}