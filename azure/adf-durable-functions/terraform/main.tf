# Configure the Microsoft Azure Provider
provider "azurerm" {
    # The "feature" block is required for AzureRM provider 2.x. 
    # If you are using version 1.x, the "features" block is not allowed.
    version = "=2.20.0"
    features {}
}

# Configure the Random Provider.
# It is useful to generate random numbers, strings, and passwords.
provider "random" {
  version = "~>2.2"
}

# Create a resource group for the project
resource "azurerm_resource_group" "project_rg" {
  name     = var.res_group_name
  location = var.project_location
}

locals {
  # Service endpoints to enable in the subnets that are created.
  functions_subnet_service_endpoints = [
    "Microsoft.Storage", "Microsoft.Web", "Microsoft.KeyVault"
  ]
  adf_ir_subnet_service_endpoints = [
    "Microsoft.Storage", "Microsoft.Web", "Microsoft.KeyVault"
  ]
}

# Create the VNet
resource "azurerm_virtual_network" "project_vnet" {
  name                = "vnet-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  address_space       = [var.vnet_address_space]
}

# Create the functions-subnet
resource "azurerm_subnet" "functions_subnet" {
  name                      = "functions-subnet"
  resource_group_name       = azurerm_resource_group.project_rg.name
  virtual_network_name      = azurerm_virtual_network.project_vnet.name
  address_prefixes          = [var.functions_subnet_prefix]
  service_endpoints         = local.functions_subnet_service_endpoints

  delegation {
    name = "subnet-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Create the adf-ir-subnet
resource "azurerm_subnet" "adf_ir_subnet" {
  name                      = "adf-ir-subnet"
  resource_group_name       = azurerm_resource_group.project_rg.name
  virtual_network_name      = azurerm_virtual_network.project_vnet.name
  address_prefixes          = [var.adf_ir_subnet_prefix]
  service_endpoints         = local.adf_ir_subnet_service_endpoints
}

# Create the AzureBastionSubnet
resource "azurerm_subnet" "bastion_subnet" {
  name                      = "AzureBastionSubnet"
  resource_group_name       = azurerm_resource_group.project_rg.name
  virtual_network_name      = azurerm_virtual_network.project_vnet.name
  address_prefixes          = [var.bastion_subnet_prefix]
}

# Create a public IP address for the Azure Bastion
resource "azurerm_public_ip" "bastion_public_ip" {
  name                = "vnet-bastion-ip-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create the Bastion Host
resource "azurerm_bastion_host" "bastion_host" {
  name                = "vnet-bastion-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_public_ip.id
  }
}

resource "random_integer" "unique_id" {
  min     = 1
  max     = 9999
}

# Create the ADLS Gen2 Storage account
resource "azurerm_storage_account" "storage" {
  name                      = "prjstorage${random_integer.unique_id.result}"
  resource_group_name       = azurerm_resource_group.project_rg.name
  location                  = azurerm_resource_group.project_rg.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  access_tier               = "Hot"
  enable_https_traffic_only = true
  is_hns_enabled            = true

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.adf_ir_subnet.id, azurerm_subnet.functions_subnet.id]
    bypass                     = ["AzureServices"]
  }

  depends_on = [
    azurerm_subnet.adf_ir_subnet,
    azurerm_subnet.functions_subnet
  ]
}

# Create a network interface for the ADF Integration Runtime VM
resource "azurerm_network_interface" "adf_ir_vm_nic" {
  name                = "adf-ir-vm-nic-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name

  ip_configuration {
    name                          = "configuration"
    subnet_id                     = azurerm_subnet.adf_ir_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Create the Network Security Group (NSG) for the ADF IR VM.
# It allows direct RDP access to the VM - but since the VM is given
# only a private IP address, the connection to the VM can only
# happen through the Bastion Host we have setup in the VNet where
# the VM is also deployed.
resource "azurerm_network_security_group" "adf_ir_vm_nsg" {
  name                = "adf-ir-vm-nsg-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name

  security_rule {
    name                       = "RDP"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 3389
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate the NSG to the network interface of the ADF IR VM
resource "azurerm_network_interface_security_group_association" "adf_ir_vm_nsg_association" {
  network_interface_id      = azurerm_network_interface.adf_ir_vm_nic.id
  network_security_group_id = azurerm_network_security_group.adf_ir_vm_nsg.id
}

# Create the ADF Integration Runtime VM.
resource "azurerm_virtual_machine" "adf_ir_vm" {
  name                  = "adf-ir-vm-${random_integer.unique_id.result}"
  location              = azurerm_resource_group.project_rg.location
  resource_group_name   = azurerm_resource_group.project_rg.name
  network_interface_ids = [azurerm_network_interface.adf_ir_vm_nic.id]
  vm_size               = "Standard_DS3_v2"

  # Comment this line to keep the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Comment this line to keep the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
  os_profile {
    computer_name  = "adf-ir-vm"
    admin_username = var.dev_vm_username
    admin_password = var.dev_vm_password
  }
  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
  }
  identity {
      type = "SystemAssigned"
  }
  storage_os_disk {
    name              = "adf-ir-vm-osdisk-${random_integer.unique_id.result}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "StandardSSD_LRS"
  }
}

# Create a Data Factory instance
resource "azurerm_data_factory" "data_factory" {
  name                = "datafactory-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name

  identity {
      type = "SystemAssigned"
  }
}

#
# Configure the Azure Application Insights service.
#
resource "azurerm_application_insights" "app_insights" {
  name                = "app-insights-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  application_type    = "other"
}


#
# Configure the Blob Storage account needed by the Function App
# to manage triggers and log function executions.
#
resource "azurerm_storage_account" "storage_functions" {
  name                      = "funstorage${random_integer.unique_id.result}"
  resource_group_name       = azurerm_resource_group.project_rg.name
  location                  = azurerm_resource_group.project_rg.location
  account_kind              = "Storage"
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
}

#
# Configure the Function App, using an Elastic Premium Plan.
# The function app is connected to the VNet.
# 
#
resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "app-service-plan-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  kind                = "elastic"

  maximum_elastic_worker_count = 20

  sku {
    tier     = "ElasticPremium"
    size     = "EP2"
    capacity = 1
  }
}

resource "azurerm_function_app" "function_app" {
  name                       = "funcapp-${random_integer.unique_id.result}"
  location                   = azurerm_resource_group.project_rg.location
  resource_group_name        = azurerm_resource_group.project_rg.name
  app_service_plan_id        = azurerm_app_service_plan.app_service_plan.id
  storage_account_name       = azurerm_storage_account.storage_functions.name
  storage_account_access_key = azurerm_storage_account.storage_functions.primary_access_key
  version                    = "~2"

  # It is important that the Function App is given a managed identity.
  # The managed identity will be used to grant the Function App access to storage locations.
  identity {
      type = "SystemAssigned"
  }

  site_config {
    ip_restriction = [
      {
        ip_address = null
        subnet_id  = azurerm_subnet.adf_ir_subnet.id
      },
      {
        ip_address = null
        subnet_id  = azurerm_subnet.functions_subnet.id
      }
    ]
  }

  app_settings = {
    "AzureWebJobsStorage"             = "${azurerm_storage_account.storage.primary_connection_string}"
    "APPINSIGHTS_INSTRUMENTATIONKEY"  = "${azurerm_application_insights.app_insights.instrumentation_key}"
    "FUNCTIONS_EXTENSION_VERSION"     = "~2"
    "FUNCTIONS_V2_COMPATIBILITY_MODE" = "true"
    "FUNCTIONS_WORKER_RUNTIME"        = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"    = "~10"
    "AZURE_STORAGE_ACCOUNT"           = "${azurerm_storage_account.storage.name}"
    "AZURE_STORAGE_CONTAINER"         = "${var.storage_container}"
  }
}

# Enable the VNet Integration feature to enable the Function App
# to access resources in or through the VNet. 
resource "azurerm_app_service_virtual_network_swift_connection" "app_service_vnet" {
  app_service_id = azurerm_function_app.function_app.id
  subnet_id      = azurerm_subnet.functions_subnet.id
}

#
# Create an Azure Key Vault instance
#
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "key_vault" {
  name                = "keyvault-${random_integer.unique_id.result}"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  soft_delete_enabled = true

  access_policy = [
    # Default access policy to allow the admin user to manage the secrets.
    {
      tenant_id               = data.azurerm_client_config.current.tenant_id
      object_id               = data.azurerm_client_config.current.object_id
      application_id          = null
      key_permissions         = []
      certificate_permissions = []
      storage_permissions     = []
      secret_permissions      = [
        "backup", "delete", "get", "list", "purge", "recover", "restore", "set"
      ]
    },
    # Ensure Azure Data Factory can read secrets stored in Key Vault.
    {
      tenant_id               = data.azurerm_client_config.current.tenant_id
      object_id               = azurerm_data_factory.data_factory.identity.0.principal_id
      application_id          = null
      key_permissions         = []
      certificate_permissions = []
      storage_permissions     = []
      secret_permissions      = ["get"]
    },
    # Ensure Azure Functions can read secrets stored in Key Vault.
    {
      tenant_id               = data.azurerm_client_config.current.tenant_id
      object_id               = azurerm_function_app.function_app.identity.0.principal_id
      application_id          = null
      key_permissions         = []
      certificate_permissions = []
      storage_permissions     = []
      secret_permissions      = ["get"]
    }
  ]

  network_acls {
    virtual_network_subnet_ids = [azurerm_subnet.functions_subnet.id, azurerm_subnet.adf_ir_subnet.id]
    bypass                     = "AzureServices"
    default_action             = "Deny"
  }
}
