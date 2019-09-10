variable "project_name" {
  default = "serverless"
}

variable "project_location" {
  default = "southeastasia"
}

variable "whitelist_ip_addresses" {
  type    = "list"
  default = ["127.0.0.1"]
}

variable "eventhub_min_throughput_units"        { default = 2 }
variable "eventhub_max_throughput_units"        { default = 4 }
variable "eventhub_num_of_partitions"           { default = 4 }
variable "eventhub_message_retention_in_days"   { default = 7 }
variable "eventhub_capture_interval_in_seconds" { default = 300 }
variable "eventhub_capture_size_limit_in_bytes" { default = 33554432 }
variable "eventhub_capture_skip_empty_archives" { default = true }

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

  version = "=1.28.0"
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
# Configure the Blob Storage account that will be used to archive (capture) the data streams
# and to allow the Function App to manage triggers and log function executions.
#
resource "azurerm_storage_account" "poc_storage_account" {
  name                     = "${var.project_name}${random_integer.ri.result}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  location                 = "${azurerm_resource_group.poc_rg.location}"
  account_kind             = "Storage"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  #access_tier              = "Hot"

  # Disabling the network rules, otherwise the deployment of the Function App fails:
  # https://github.com/terraform-providers/terraform-provider-azurerm/issues/3816
  #network_rules {
  #  bypass                 = ["AzureServices"]
  #}
}

resource "azurerm_storage_container" "poc_storage_container_tweets" {
  name                  = "tweets"
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
  capacity                 = "${var.eventhub_min_throughput_units}"
  auto_inflate_enabled     = true
  maximum_throughput_units = "${var.eventhub_max_throughput_units}"
  kafka_enabled            = true
}

resource "azurerm_eventhub" "poc_eventhub_src" {
  name                     = "tweets-raw"
  namespace_name           = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  partition_count          = "${var.eventhub_num_of_partitions}"
  message_retention        = "${var.eventhub_message_retention_in_days}"
}

resource "azurerm_eventhub_consumer_group" "functions_consumer_group" {
  name                = "FunctionConsumerGroup"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub_src.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
}

resource "azurerm_eventhub_consumer_group" "asa_consumer_group" {
  name                = "ASAConsumerGroup"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub_src.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
}

resource "azurerm_eventhub_authorization_rule" "src_producer_key" {
  name                = "ProducerSharedAccessKey"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub_src.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  listen              = false
  send                = true
  manage              = false
}

resource "azurerm_eventhub_authorization_rule" "src_consumer_key" {
  name                = "ConsumerSharedAccessKey"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub_src.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  listen              = true
  send                = false
  manage              = false
}

output "eventhub_namespace_name" {
  value = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
}

output "eventhub_primary_connection_string" {
  value = "${azurerm_eventhub_authorization_rule.src_producer_key.primary_connection_string}"
}

resource "azurerm_eventhub" "poc_eventhub_dst" {
  name                     = "tweets-processed"
  namespace_name           = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  partition_count          = "${var.eventhub_num_of_partitions}"
  message_retention        = "${var.eventhub_message_retention_in_days}"
  
  capture_description {
    enabled                = true
    encoding               = "Avro"
    interval_in_seconds    = "${var.eventhub_capture_interval_in_seconds}"
    size_limit_in_bytes    = "${var.eventhub_capture_size_limit_in_bytes}"
    skip_empty_archives    = "${var.eventhub_capture_skip_empty_archives}"

    destination {
      name                 = "EventHubArchive.AzureBlockBlob"
      archive_name_format  = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}{Minute}{Second}"
      blob_container_name  = "${azurerm_storage_container.poc_storage_container_tweets.name}"
      storage_account_id   = "${azurerm_storage_account.poc_storage_account.id}"
    }
  }
}

resource "azurerm_eventhub_authorization_rule" "dst_producer_key" {
  name                = "ProducerSharedAccessKey"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub_dst.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  listen              = false
  send                = true
  manage              = false
}

#
# Configure the Azure Application Insights service.
#
resource "azurerm_application_insights" "poc_app_insights" {
  name                = "${var.project_name}-poc-app-insights"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  application_type    = "other"
}

#
# Configure the Function App, using a Consumption Plan.
#
resource "azurerm_app_service_plan" "poc_app_service_plan" {
  name                = "${var.project_name}-poc-service-plan"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  kind                = "FunctionApp"

  # Force the creation of a Linux instance by setting 'reserved' to true.
  reserved            = true

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "poc_function_app" {
  name                      = "${var.project_name}-funcapp-${random_integer.ri.result}"
  location                  = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name       = "${azurerm_resource_group.poc_rg.name}"
  app_service_plan_id       = "${azurerm_app_service_plan.poc_app_service_plan.id}"
  storage_connection_string = "${azurerm_storage_account.poc_storage_account.primary_connection_string}"
  version                   = "~2"

  app_settings {
    "APPINSIGHTS_INSTRUMENTATIONKEY"              = "${azurerm_application_insights.poc_app_insights.instrumentation_key}"
    "FUNCTIONS_WORKER_RUNTIME"                    = "python"
    "TWEETS_RAW_EVENTHUB_CONNECTION_STRING"       = "${azurerm_eventhub_authorization_rule.src_consumer_key.primary_connection_string}"
    "TWEETS_PROCESSED_EVENTHUB_CONNECTION_STRING" = "${azurerm_eventhub_authorization_rule.dst_producer_key.primary_connection_string}"
  }
}

output "funcapp_name" {
  value = "${azurerm_function_app.poc_function_app.name}"
}

# Generate the function
resource "local_file" "functions_local_settings" {
  sensitive_content = <<EOF
{
    "IsEncrypted": false,
    "Values": {
      "FUNCTIONS_WORKER_RUNTIME": "python",
      "FUNCTIONS_EXTENSION_VERSION": "~2",
      "AzureWebJobsStorage": "${azurerm_storage_account.poc_storage_account.primary_connection_string}",
      "TWEETS_RAW_EVENTHUB_CONNECTION_STRING": "${azurerm_eventhub_authorization_rule.src_consumer_key.primary_connection_string}",
      "TWEETS_PROCESSED_EVENTHUB_CONNECTION_STRING": "${azurerm_eventhub_authorization_rule.dst_producer_key.primary_connection_string}"
    }
}
EOF

  filename = "./functions/local.settings.json"

  provisioner "local-exec" {
    command = "chmod 664 ./functions/local.settings.json"
  }
}

#
# Secure the Storage Account by enabling firewall rules.
#
resource "null_resource" "azure_cli" {
  provisioner "local-exec" {
    command = "./set-storage-network-rules.sh"

    environment {
      resourceGroup          = "${azurerm_resource_group.poc_rg.name}"
      storageAccount         = "${azurerm_storage_account.poc_storage_account.name}"
      whitelistedIPAddresses = "${join(",", concat(var.whitelist_ip_addresses, split(",", azurerm_function_app.poc_function_app.possible_outbound_ip_addresses)))}"
    }
  }

  triggers = {
    ip_addresses = "${azurerm_function_app.poc_function_app.possible_outbound_ip_addresses}"
  }

  depends_on = ["azurerm_storage_account.poc_storage_account", "azurerm_function_app.poc_function_app"]
}