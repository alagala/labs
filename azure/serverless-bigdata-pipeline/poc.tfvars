# Choose a project name with max 16 characters
project_name           = "serverless"
project_location       = "southeastasia"

# IP address(es) of the machine executing the Terraform script.
# The indicated IP addresses are used to set the Storage firewall rules
# for the purpose of automatically creating the Blob container or
# ADLS filesystem.
whitelist_ip_addresses = ["222.164.176.163"]

# Configure Azure Event Hubs properties
eventhub_min_throughput_units        = 2
eventhub_max_throughput_units        = 4
eventhub_num_of_partitions           = 4
eventhub_message_retention_in_days   = 3
eventhub_capture_interval_in_seconds = 300
eventhub_capture_size_limit_in_bytes = 33554432
eventhub_capture_skip_empty_archives = true