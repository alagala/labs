#!/bin/bash

# Set the default rule to deny network access by default.
az storage account update --resource-group $resourceGroup --name $storageAccount --default-action Deny

# Add network rules for the whitelist IP addresses
echo "Whitelisting the following IP addresses:"
for ipAddress in $(echo $whitelistedIPAddresses | sed "s/,/ /g")
do
    echo "$ipAddress"
    az storage account network-rule add --resource-group $resourceGroup --account-name $storageAccount --ip-address "$ipAddress"
done

# Configure the exceptions to the storage account network rules.
az storage account update --resource-group $resourceGroup --name $storageAccount --bypass Logging Metrics AzureServices