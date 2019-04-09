variable "project_name" {
  default = "datainsights"
}

variable "project_location" {
  default = "southeastasia"
}

variable "vnet_address_space" {
  default = "10.0.0.0/16"
}

variable "adb_public_subnet_prefix" {
  default = "10.0.1.0/24"
}

variable "adb_private_subnet_prefix" {
  default = "10.0.2.0/24"
}

locals {
  # Service endpoints to enable in the subnets that are created.
  subnets_service_endpoints = [
    "Microsoft.AzureCosmosDB", "Microsoft.KeyVault", "Microsoft.Storage"
  ]

  # IP Range Filter here is to allow Azure Portal access
  cosmosdb_ip_range_azure = [
    "104.42.195.92/32",
    "40.76.54.131/32",
    "52.176.6.30/32",
    "52.169.50.45/32",
    "52.187.184.26/32"
  ]
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

  version = "=1.24.0"
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "poc_rg" {
  name     = "${var.project_name}-poc-rg"
  location = "${var.project_location}"
}

#
# Configure the virtual network where Azure Databricks has to be deployed.
#
resource "azurerm_virtual_network" "poc_vnet" {
  name                = "${var.project_name}-poc-vnet"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  address_space       = ["${var.vnet_address_space}"]
}

resource "azurerm_subnet" "adb_public_subnet" {
  name                 = "databricks-public-subnet"
  resource_group_name  = "${azurerm_resource_group.poc_rg.name}"
  virtual_network_name = "${azurerm_virtual_network.poc_vnet.name}"
  address_prefix       = "${var.adb_public_subnet_prefix}"
  service_endpoints    = "${local.subnets_service_endpoints}"
}

resource "azurerm_subnet" "adb_private_subnet" {
  name                 = "databricks-private-subnet"
  resource_group_name  = "${azurerm_resource_group.poc_rg.name}"
  virtual_network_name = "${azurerm_virtual_network.poc_vnet.name}"
  address_prefix       = "${var.adb_private_subnet_prefix}"
  service_endpoints    = "${local.subnets_service_endpoints}"
}

#
# Configure the Cosmos DB account that will be used by the Azure Databricks application.
#
resource "azurerm_cosmosdb_account" "poc_cosmos" {
  name                = "${var.project_name}poc${random_integer.ri.result}"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  enable_automatic_failover       = false
  enable_multiple_write_locations = false

  geo_location {
    location          = "${azurerm_resource_group.poc_rg.location}"
    failover_priority = 0
  }

  consistency_policy {
    consistency_level = "Session"
  }

  # capabilities {
  #   name = "EnableCassandra"
  # }

  is_virtual_network_filter_enabled = true

  virtual_network_rule {
    id = "${azurerm_subnet.adb_public_subnet.id}"
  }

  virtual_network_rule {
    id = "${azurerm_subnet.adb_private_subnet.id}"
  }

  # IPs https://docs.microsoft.com/en-us/azure/cosmos-db/firewall-support#connections-from-the-azure-portal
  ip_range_filter = "${join(",",local.cosmosdb_ip_range_azure)}"
}

#
# Configure the Azure Data Lake Storage account that will be used by the Azure Databricks application.
#
resource "azurerm_storage_account" "poc_storage_account" {
  name                     = "${var.project_name}poc${random_integer.ri.result}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  location                 = "${azurerm_resource_group.poc_rg.location}"
  account_kind             = "StorageV2"
  account_tier             = "Premium"
  account_replication_type = "LRS"
  access_tier              = "Hot"
  is_hns_enabled           = false  # Enable compatibility with Blob APIs

  network_rules {
    virtual_network_subnet_ids = ["${azurerm_subnet.adb_public_subnet.id}", "${azurerm_subnet.adb_private_subnet.id}"]
    bypass                     = ["AzureServices"]
  }
}

#
# Store the Cosmos DB and Storage Account secrets in Azure Key Vault.
#
resource "azurerm_key_vault" "poc_key_vault" {
  name                = "${var.project_name}poc${random_integer.ri.result}"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  tenant_id           = "${data.azurerm_client_config.current.tenant_id}"

  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
    object_id = "${data.azurerm_client_config.current.service_principal_object_id}"

    secret_permissions = [
      "get", "set", "delete", "list", "purge"
    ]
  }

  # network_acls {
  #   virtual_network_subnet_ids = ["${azurerm_subnet.adb_public_subnet.id}", "${azurerm_subnet.adb_private_subnet.id}"]
  #   bypass                     = "AzureServices"
  #   default_action             = "Deny"
  # }
}

resource "azurerm_key_vault_secret" "secret_cosmos_uri" {
  name         = "Cosmos-DB-URI"
  value        = "${azurerm_cosmosdb_account.poc_cosmos.endpoint}"
  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
}

resource "azurerm_key_vault_secret" "secret_cosmos_key" {
  name         = "Cosmos-DB-Key"
  value        = "${azurerm_cosmosdb_account.poc_cosmos.primary_master_key}"
  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
}

resource "azurerm_key_vault_secret" "secret_storage_name" {
  name         = "ADLS-Gen2-Account-Name"
  value        = "${azurerm_storage_account.poc_storage_account.name}"
  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
}

resource "azurerm_key_vault_secret" "secret_storage_key" {
  name         = "ADLS-Gen2-Account-Key"
  value        = "${azurerm_storage_account.poc_storage_account.primary_access_key}"
  key_vault_id = "${azurerm_key_vault.poc_key_vault.id}"
}
 
#
# Configure the Azure Databricks Workspace using an ARM template.
# At the moment this is so because the native Terraform azurerm_databricks_workspace
# does not support:
#   - Deployment of the workspace resources in a LRS storage account
#   - Injection of Azure Databricks driver and workers in a VNET
#
# This may change in future.
#
resource "azurerm_template_deployment" "poc_adb_workspace" {
  name                = "adb-arm-poc-template"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"

  template_body = <<DEPLOY
${file("arm/vnetinj-template-LRSdbfs.json")}
DEPLOY

  # these key-value pairs are passed into the ARM Template's `parameters` block
  parameters = {
    "workspaceName"     = "${var.project_name}-poc-workspace"
    "pricingTier"       = "premium"
    "vnetName"          = "${azurerm_virtual_network.poc_vnet.name}"
    "vnetCidr"          = "${var.vnet_address_space}"
    "privateSubnetName" = "${azurerm_subnet.adb_private_subnet.name}"
    "privateSubnetCidr" = "${var.adb_private_subnet_prefix}"
    "publicSubnetName"  = "${azurerm_subnet.adb_public_subnet.name}"
    "publicSubnetCidr"  = "${var.adb_public_subnet_prefix}"
    "nsgName"           = "${var.project_name}-poc-nsg"
  }

  deployment_mode = "Incremental"
}

#
# Define the output variables that are needed in the application.
#
output "key_vault_id" {
  value = "${azurerm_key_vault.poc_key_vault.id}"
}

output "key_vault_uri" {
  value = "${azurerm_key_vault.poc_key_vault.vault_uri}"
}