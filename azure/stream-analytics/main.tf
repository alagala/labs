variable "project_name" {
  default = "streaming"
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
variable "eventhub_capture_skip_empty_archives" { default = false }
variable "streaming_units"                      { default = 6 }
variable "streaming_events_late_arrival_max_delay_in_seconds" { default = 60 }
variable "streaming_events_out_of_order_max_delay_in_seconds" { default = 50 } 

#
# Configure the Microsoft Azurewhitelist_ip_addresses Provider.
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

resource "random_string" "password" {
  length           = 16
  special          = true
  override_special = "/@\" "
}

resource "random_pet" "username" {
  length = 2
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
    ip_rules               = "${var.whitelist_ip_addresses}"
  }
}

resource "azurerm_storage_container" "poc_storage_container_archive" {
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
  capacity                 = "${var.eventhub_min_throughput_units}"
  auto_inflate_enabled     = true
  maximum_throughput_units = "${var.eventhub_max_throughput_units}"
  kafka_enabled            = true
}

resource "azurerm_eventhub" "poc_eventhub" {
  name                     = "${var.project_name}-poc-tweets"
  namespace_name           = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  partition_count          = "${var.eventhub_num_of_partitions}"
  message_retention        = "${var.eventhub_message_retention_in_days}"
  
  capture_description {
    enabled                = true
    encoding               = "AvroDeflate"
    interval_in_seconds    = "${var.eventhub_capture_interval_in_seconds}"
    size_limit_in_bytes    = "${var.eventhub_capture_size_limit_in_bytes}"
    skip_empty_archives    = "${var.eventhub_capture_skip_empty_archives}"

    destination {
      name                 = "EventHubArchive.AzureBlockBlob"
      archive_name_format  = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}{Minute}{Second}"
      blob_container_name  = "${azurerm_storage_container.poc_storage_container_archive.name}"
      storage_account_id   = "${azurerm_storage_account.poc_storage_account.id}"
    }
  }
}

resource "azurerm_eventhub_consumer_group" "poc_eh_consumer_group" {
  name                = "StreamAnalyticsConsumerGroup"
  namespace_name      = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  eventhub_name       = "${azurerm_eventhub.poc_eventhub.name}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
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

output "eventhub_namespace_name" {
  value = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
}

output "eventhub_primary_connection_string" {
  value = "${azurerm_eventhub_authorization_rule.producer_key.primary_connection_string}"
}

#
# Configure the Azure Stream Analytics jobs that will get and process
# messages from the Azure Event Hubs. 
#
resource "azurerm_stream_analytics_job" "poc_asa_job" {
  name                                     = "TwitterStoreProjectedFieldsJob"
  resource_group_name                      = "${azurerm_resource_group.poc_rg.name}"
  location                                 = "${azurerm_resource_group.poc_rg.location}"
  compatibility_level                      = "1.1"
  data_locale                              = "en-US"
  events_late_arrival_max_delay_in_seconds = "${var.streaming_events_late_arrival_max_delay_in_seconds}"
  events_out_of_order_max_delay_in_seconds = "${var.streaming_events_out_of_order_max_delay_in_seconds}"
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = "${var.streaming_units}"

  transformation_query = <<QUERY
    WITH AllTweets AS (
      SELECT
          id,
          created_at,
          text AS tweet,
          source,
          author.id AS user_id,
          author.name AS user_name,
          author.screen_name AS user_screen_name
      FROM [eventhub-stream-input]
      PARTITION BY PartitionId
      TIMESTAMP BY created_at
  )
  SELECT * INTO [sqldwh-stream-output] FROM AllTweets
  SELECT * INTO [powerbi-stream-output] FROM AllTweets
QUERY
}

resource "azurerm_stream_analytics_stream_input_eventhub" "poc_asa_eventhub_input" {
  name                         = "eventhub-stream-input"
  resource_group_name          = "${azurerm_resource_group.poc_rg.name}"
  stream_analytics_job_name    = "${azurerm_stream_analytics_job.poc_asa_job.name}"
  eventhub_consumer_group_name = "${azurerm_eventhub_consumer_group.poc_eh_consumer_group.name}"
  eventhub_name                = "${azurerm_eventhub.poc_eventhub.name}"
  servicebus_namespace         = "${azurerm_eventhub_namespace.poc_eh_ns.name}"
  shared_access_policy_key     = "${azurerm_eventhub_authorization_rule.consumer_key.primary_key}"
  shared_access_policy_name    = "${azurerm_eventhub_authorization_rule.consumer_key.name}"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

#
# Configure the Azure SQL Database used to store data.
#
resource "azurerm_sql_server" "poc_sql_server" {
  name                         = "sqlserver${random_integer.ri.result}"
  resource_group_name          = "${azurerm_resource_group.poc_rg.name}"
  location                     = "${azurerm_resource_group.poc_rg.location}"
  version                      = "12.0"
  administrator_login          = "${random_pet.username.id}"
  administrator_login_password = "${random_string.password.result}"
}

# The Azure feature 'Allow access to Azure services' can be enabled
# by setting start_ip_address and end_ip_address to 0.0.0.0.
#
resource "azurerm_sql_firewall_rule" "poc_sql_firewall_rule" {
  name                = "AllowAccessToAzureServicesRule"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  server_name         = "${azurerm_sql_server.poc_sql_server.name}"
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

resource "azurerm_sql_database" "poc_sql_dwh" {
  name                = "tweetsdb"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  location            = "${azurerm_resource_group.poc_rg.location}"
  server_name         = "${azurerm_sql_server.poc_sql_server.name}"
  create_mode         = "Default"
  edition             = "DataWarehouse"
  requested_service_objective_name = "DW1000c"
  collation           = "SQL_LATIN1_GENERAL_CP1_CI_AS"
}

output "sql_server_name" {
  value = "${azurerm_sql_server.poc_sql_server.name}"
}

output "sql_server_login" {
  value = "${azurerm_sql_server.poc_sql_server.administrator_login}"
}

output "sql_server_password" {
  value = "${azurerm_sql_server.poc_sql_server.administrator_login_password}"
}