# Azure Databricks integration with Cosmos DB: hands-on lab
This guide will help you spin up an environment to test the integration between Azure Databricks, Azure Data Lake Storage and Azure Cosmos DB.

The environment is created by using Terraform, and a notebook is provided to showcase a sample Spark application that count words from a text file stored in Azure Data Lake Storage and writes the output to Azure Cosmos DB (exposed through Cassandra APIs).

The diagram below shows the architecture of the solution.

> **TODO**: insert architecture diagram. 

# Run Terraform and setup the environment

## Requirements

1. Microsoft Azure subscription
2. A CI server to run Terraform non-interactively, with a Service Principal (which is an application within Azure Active Directory); or
3. If you plan to run Terraform from your local machine:
   - The Azure CLI
   - [Terraform](https://www.terraform.io)

## Create a Service Principal on your local machine using the Azure CLI

Firstly, login to the Azure CLI using:
```shell
$ az login
```
Once logged in - it's possible to list the Subscriptions associated with the account via:
```shell
$ az account list
```

The output will display one or more Subscriptions - with the `id` field being the `SUBSCRIPTION_ID` field referred to in the scripts below.

Should you have more than one Subscription, you can specify the Subscription to use via the following command:
```shell
$ az account set --subscription="SUBSCRIPTION_ID"
```

We can now create the Service Principal which will have permissions to manage resources in the specified Subscription using the following command:
```shell
$ az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/SUBSCRIPTION_ID"
```

This command will output a few values that must be mapped to the Terraform variables:
- `appId` is the `client_id`
- `password` is the `client_secret`
- `tenant` is the `tenant_id`

## Configure the Service Principal in Terraform

Store the credentials obtained in the previous step as environment variables:
```shell
$ export ARM_CLIENT_ID=<APP_ID>
$ export ARM_CLIENT_SECRET=<PASSWORD>
$ export ARM_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
$ export ARM_TENANT_ID=<TENANT>
```

## Run Terraform to create the environment

Modify the project file `poc.tfvars` to enter the values that are right for the deploymnent of the environment in your Azure subscription:
```
project_name              = <PROJECT_NAME>
project_location          = <AZURE_REGION_TO_DEPLOY_THE_PROJECT>
vnet_address_space        = <ADDRESS_SPACE_OF_THE_VNET_TO_BE_CREATED>
adb_public_subnet_prefix  = <DATABRICKS_PUBLIC_SUBNET_ADDRESS_RANGE>
adb_private_subnet_prefix = <DATABRICKS_PRIVATE_SUBNET_ADDRESS_RANGE>
```

Run Terraform:
```shell
$ terraform apply -var-file=poc.tfvars
```

When the execution of the Terraform plan has completed (expect about 10-15 minutes), verify that the required services have been successfully created:

1. Sign in to the [Azure Portal](https://portal.azure.com).

2. In the left pane, select **Resource groups**. If you don't see the service listed, select **All services**, and then select **Resource groups**.

3. You should see a resource group named `<PROJECT_NAME>-poc-rg` (eg. `datainsights-poc-rg`).

4. Click on it and observe that the following services have been created:
- `<PROJECT_NAME>-poc-vnet`: the virtual network (with subnets) where Azure Databricks service components and Spark workers are deployed.
- `<PROJECT_NAME>-poc-nsg`:	the network security group (created by Azure Databricks) associated to the subnets.
- `<PROJECT_NAME>-poc-workspace`: the Azure Databricks workspace, which we will utilize to start our Spark clusters and run our sample application.
- `<PROJECT_NAME>poc<#>`: the Azure Cosmos DB account, where we will host the database of our sample application.
- `<PROJECT_NAME>poc<#>`: the Azure Data Lake Storage account (Gen2), that the sample application will read the data from and write the data to.
- `<PROJECT_NAME>pocvault`: the Azure Key vault	service that will store the secrets our application uses to access the Cosmos DB and the Storage accounts.

## Copy the Terraform output variables

Terraform outputs a few variables that you need to configure Azure Databricks.

Copy the **key_vault_uri** and **key_vault_id** property values and paste them to Notepad or some other text application that you can reference later. These values will be used in the next section.

You can also reproduce the values with the following commands:
```shell
$ terraform output key_vault_uri
$ terraform output key_vault_id
```

## Configure Azure Databricks to access Key Vault

Connect to your Azure Databricks workspace and configure Azure Databricks secrets to use your Azure Key Vault account as a backing store.

1. Return to the [Azure portal](https://portal.azure.com), navigate to the Azure Databricks workspace you provisioned above (`<PROJECT_NAME>-poc-workspace`), and select **Launch Workspace** from the overview blade, signing into the workspace with your Azure credentials, if required.

   ![The Launch Workspace button is displayed on the Databricks Workspace Overview blade.](media/databricks-launch-workspace.png 'Launch Workspace')

2. In your browser's URL bar, append **#secrets/createScope** to your Azure Databricks base URL (for example, <https://southeastasia.azuredatabricks.net#secrets/createScope>).

3. Enter `key-vault-secrets` for the name of the secret scope.

4. Select **Creator** within the Manage Principal drop-down to specify only the creator (which is you) of the secret scope has the MANAGE permission.

5. Enter:
   - **DNS Name**: the `key_vault_uri` value output by Terraform (for example, <https://datainsightspocvault.vault.azure.net/>).
   - **Resource ID**: the `key_vault_id` value output by Terraform (for example: `/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourcegroups/datainsights-poc-rg/providers/Microsoft.KeyVault/vaults/datainsightspocvault`).

   ![Create Secret Scope form](media/create-secret-scope.png 'Create Secret Scope')

6. Select **Create**.

After a moment, you will see a dialog verifying that the secret scope has been created.

## Create the Cosmos DB database

1. Return to the [Azure portal](https://portal.azure.com).

2. Navigate to the newly provisioned Azure Cosmos DB account, then select **Data Explorer** on the left-hand menu.

   ![Data Explorer is selected within the left-hand menu](media/cosmos-db-data-explorer-link.png 'Select Data Explorer')

3. Select **New Collection** in the top toolbar.

   ![The New Collection button is highlighted on the top toolbar](media/new-collection-button.png 'New Collection')

4. In the **Add Collection** blade, configure the following:

   - **Database id**: Select **Create new**, then enter "Woodgrove" for the id.
   - **Provision database throughput**: Unchecked.
   - **Collection id**: Enter "transactions".
   - **Partition key**: Enter "/ipCountryCode".
   - **Throughput**: Enter 15000.
   
   >**Note**: The /ipCountryCode partition was selected because the data will most likely include this value, and it allows us to partition by location from which the transaction originated. This field also contains a wide range of values, which is preferable for partitions.

   ![The Add Collection blade is displayed, with the previously mentioned settings entered into the appropriate fields.](media/cosmos-db-add-collection-blade.png 'Add Collection blade')


# Run the sample Spark application

## Create an Azure Databricks cluster

1. Return to the [Azure portal](https://portal.azure.com), navigate to the Azure Databricks workspace you provisioned above, and select **Launch Workspace** from the overview blade, signing into the workspace with your Azure credentials, if required.

2. Select **Clusters** from the left-hand navigation menu, and then select **+ Create Cluster**.

   ![The Clusters option in the left-hand menu is selected and highlighted, and the Create Cluster button is highlighted on the clusters page.](media/databricks-clusters.png 'Databricks Clusters')

3. On the Create Cluster screen, enter the following:

   - **Cluster Name**: Enter a name for your cluster, such as `lab-cluster`.
   - **Cluster Mode**: Select Standard.
   - **Databricks Runtime Version**: Select Runtime: 5.2 (Scala 2.11, Spark 2.4.0).
   - **Python Version**: Select 3.
   - **Enable autoscaling**: Ensure this is checked.
   - **Terminate after XX minutes of inactivity**: Leave this checked, and the number of minutes set to 120.
   - **Worker Type**: Select Standard_DS4_v2.
     - **Min Workers**: Leave set to 2.
     - **Max Workers**: Leave set to 8.
   - **Driver Type**: Set to Same as worker.
   - Expand Advanced Options and enter the following into the Spark Config box:

   ```bash
   spark.databricks.delta.preview.enabled true
   ```

   ![The Create Cluster screen is displayed, with the values specified above entered into the appropriate fields.](media/databricks-create-new-cluster.png 'Create a new Databricks cluster')

4. Select **Create Cluster**. It will take 3-5 minutes for the cluster to be created and started.

## Install the Azure Cosmos DB Spark Connector

You have to install the [Azure Cosmos DB Spark Connector](https://github.com/Azure/azure-cosmosdb-spark) on your Databricks cluster: it allows you to easily read from and write to Azure Cosmos DB via Apache Spark DataFrames.

1. Navigate to your Azure Databricks workspace in the [Azure portal](https://portal.azure.com/), and select **Launch Workspace** from the overview blade, signing into the workspace with your Azure credentials, if required.

2. Select **Workspace** from the left-hand menu, then select the drop down arrow next to **Shared** and select **Create** and **Library** from the context menus.

   ![The Workspace items is selected in the left-hand menu, and the shared workspace is highlighted. In the Shared workspace context menu, Create and Library are selected.](media/databricks-create-shared-library.png 'Create Shared Library')

3. On the Create Library page, select **Maven** under Library Source, and then select **Search Packages** next to the Coordinates text box.

   ![The Databricks Create Library dialog is displayed, with Maven selected under Library Source and the Search Packages link highlighted.](media/databricks-create-maven-library.png 'Create Library')

4. On the Search Packages dialog, select **Maven Central** from the source drop down, enter **azure-cosmosdb-spark** into the search box, and click **Select** next to Artifact Id `azure-cosmosdb-spark_2.4.0_2.11` release `1.3.5`.

   ![The Search Packages dialog is displayed, with Maven Central specified as the source and azure-cosmosdb-spark entered into the search box. The most recent version of the Cosmos DB Spark Connector is highlighted.](media/databricks-maven-search-packages.png)

5. Select **Create** to finish installing the library.

   ![The Create button is highlighted on the Create Library dialog.](media/databricks-create-library-cosmosdb-spark.png 'Create Library')

6. On the following screen, check the box for **Install automatically on all clusters**, and select **Confirm** when prompted.

   ![The Install automatically on all clusters box is checked and highlighted on the library dialog.](media/databricks-install-library-on-all-clusters.png 'Install library on all clusters')

## Open Azure Databricks and load lab notebooks

Follow the instructions below to download the notebook contained in this repository and upload it to your Azure Databricks workspace.

1. Download the notebook from the following link: [CosmosDB-WordCount-Sample-Application.ipynb](https://github.com/alagala/labs/blob/master/azure/databricks/notebooks/CosmosDB-WordCount-Sample-Application.ipynb)

2. Navigate to your Azure Databricks workspace in the Azure portal, and select **Launch Workspace** from the overview blade, signing into the workspace with your Azure credentials, if required.

3. Select **Workspace** from the left-hand menu, then select **Users** and select your user account (email address), and then select the down arrow on top of your user workspace and select **Import** from the context menu.

   ![The Workspace menu is highlighted in the Azure Databricks workspace, and Users is selected with the current user's account selected and highlighted. Import is selected in the user's context menu.](media/databricks-workspace-import.png 'Import files into user workspace')

4. Within the Import Notebooks dialog, select **File** for Import from, and then drag-and-drop the downloaded `dbc` file into the box, or browse to upload it.

   ![The Import Notebooks dialog is displayed](media/databricks-import-notebooks.png 'Import Notebooks dialog')

5. Select **Import**.

6. You should now see a notebook named **CosmosDB-WordCount-Sample-Application** in your user workspace.

7. In the **CosmosDB-WordCount-Sample-Application** notebook, follow the instructions to execute the Spark application.

## Explore the data in Cosmos DB

> TODO

# Cleanup the allocated resources

## Run Terraform to destroy the environment
Run the following Terraform command to cleanup all allocated resources and destroy the environment:
```shell
$ terraform destroy
```