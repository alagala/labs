# Real-time data ingestion and processing with Microsoft Azure fully-managed services: hands-on lab

This guide will help you spin up an environment to test real-time data ingestion and processing using the following Microsoft Azure services: Kafka-enabled [Event Hubs](https://docs.microsoft.com/en-us/azure/event-hubs/), [Stream Analytics](https://docs.microsoft.com/en-us/azure/stream-analytics/), [SQL Data Warehouse](https://docs.microsoft.com/en-us/azure/sql-data-warehouse/) and [Power BI](https://docs.microsoft.com/en-us/power-bi/).

A sample client application is provided to showcase how the platform works end-to-end. The application consists of a basic client that consumes Twitter’s tweets using the Twitter Streaming APIs, and publishes each tweet (that matches a specified set of keywords) to Azure Event Hubs using the Kafka client APIs. Once the tweets are ingested in Event Hubs, they are processed by a Stream Analytics query that outputs a subset of their attributes to Power BI, for real-time visualization, and to Azure SQL Data Warehouse, for historical analysis.

The diagram below shows the logical architecture of the solution.
   
   ![Logical architecture](media/architecture-logical.png 'Logical architecture')

## Prerequisites

1. Microsoft [Azure subscription](https://azure.microsoft.com/en-us/)
1. Access to Microsoft [Power BI](https://powerbi.microsoft.com/en-us/)
1. A registered [Twitter app](https://developer.twitter.com/en/docs/basics/apps/guides/the-app-management-dashboard), with the following keys and tokens (that are used to configure the provided sample Twitter client application):
   - API Key (consumer key)
   - API Secret (consumer secret)
   - Access token
   - Access token secret
1. [Maven](https://maven.apache.org/download.cgi), and the [JDK](https://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html) or [OpenJDK](https://openjdk.java.net/install/) 1.8+, to compile the Twitter client application on your local machine
1. A CI server to run Terraform non-interactively, with a Service Principal (which is an application within Azure Active Directory); or
1. If you plan to run Terraform from your local machine, install:
   - The [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
   - [Terraform](https://www.terraform.io) 

# Run Terraform and setup the environment on Azure

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

This command will output a few values that must be mapped to the Terraform variables. Take note of them because you will need them in the following section:
- `appId` is the `client_id`
- `password` is the `client_secret`
- `tenant` is the `tenant_id`

Finally, since we're logged into the Azure CLI as a Service Principal we recommend logging out of the Azure CLI:
```shell
$ az logout
```

## Configure the Service Principal in Terraform

Store the credentials obtained in the previous step as environment variables:
```shell
$ export ARM_CLIENT_ID=<APP_ID>
$ export ARM_CLIENT_SECRET=<PASSWORD>
$ export ARM_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
$ export ARM_TENANT_ID=<TENANT>
```

## Run Terraform to create the environment

Clone this repository and modify the project file `poc.tfvars` to enter the values that are right for the deployment of the environment in your Azure subscription:
```
project_name              = <PROJECT_NAME>
project_location          = <AZURE_REGION_TO_DEPLOY_THE_PROJECT>
whitelist_ip_addresses    = <IP_ADDRESSES_TO_BE_WHITELISTED_BY_STORAGE_FIREWALL>

# Configure Azure Event Hubs properties
eventhub_min_throughput_units        = <MIN_TU>
eventhub_max_throughput_units        = <MAX_TU>
eventhub_num_of_partitions           = <NUM_OF_PARTITIONS>
eventhub_message_retention_in_days   = <MESSAGE_RETENTION>
eventhub_capture_interval_in_seconds = <CAPTURE_INTERVAL>
eventhub_capture_size_limit_in_bytes = <CAPTURE_SIZE_LIMIT>
eventhub_capture_skip_empty_archives = <CAPTURE_SKIP_EMPTY_FILES>

# Configure Azure Stream Analytics properties
streaming_units                                    = <STREAMING_UNITS>
streaming_events_late_arrival_max_delay_in_seconds = <EVENTS_LATE_ARRIVAL_MAX_DELAY>
streaming_events_out_of_order_max_delay_in_seconds = <EVENTS_OUT_OF_ORDER_MAX_DELAY>
```
   > **Note**: ensure that the value of the project name is maximum 16 characters in length, othwerwise some resources will not be created properly (as their names will exceed the maximum allowed length).

Run Terraform:
```shell
$ terraform init
$ terraform apply -var-file=poc.tfvars
```

When the execution of the Terraform plan has completed (expect about 10-15 minutes), verify that the required services have been successfully created:

1. Sign in to the [Azure Portal](https://portal.azure.com).

1. In the left pane, select **Resource groups**. If you don't see the service listed, select **All services**, and then select **Resource groups**.

1. You should see a resource group named `<PROJECT_NAME>-poc-rg` (eg. `streaming-poc-rg`).

1. Click on it and observe that the following services have been created:
   - `sqlserver<#>`: the **SQL Server endpoint**, used to connect to the SQL Data Warehouse.
   - `tweetsdb`: the **Azure SQL Data Warehouse database**, that is used to store the tweets for historical analysis.
   - `<PROJECT_NAME><#>`: the **Azure Storage account**, that the streaming data will be captured and archived to (by Azure Event Hubs).
   - `<PROJECT_NAME>-kafka-<#>`: the **Azure Event Hubs namespace**. Event Hubs is configured to provide a Kafka endpoint that can be used by new or existing Kafka-based applications as an alternative to running your own Kafka cluster. An Event Hubs namespace corresponds to a Kafka cluster.
   - `TwitterStoreProjectedFieldsJob`: the **Azure Stream Analytics job**, that processes the real-time Twitter feed and outputs each tweet to Azure SQL Data Warehouse and to Power BI.

## Copy the Terraform output variables

Terraform outputs a few variables that you need to configure the Kafka clients (including the sample Twitter client application provided) to send streaming data to Azure Event Hubs, and to connect to the Azure SQL Data Warehouse.

Copy the following property values and paste them to Notepad or some other text application that you can reference later:
- **eventhub_namespace_name** and **eventhub_primary_connection_string**
- **sql_server_name**, **sql_server_login** and **sql_server_password**

You can also reproduce the values with the following commands:
```shell
$ terraform output eventhub_namespace_name
$ terraform output eventhub_primary_connection_string
$ terraform output sql_server_name
$ terraform output sql_server_login
$ terraform output sql_server_password
```

# Compile and run the Twitter client application

Compile and run the provided sample Twitter client application, in order to test and verify that environment is correctly setup and integrated end-to-end. After cloning the repository:

1. Configure the Kafka producer properties:

   - Rename the `src/main/resources/producer.config.TEMPLATE` file into `src/main/resources/producer.config`:

     ```shell
     $ cp src/main/resources/producer.config.TEMPLATE src/main/resources/producer.config
     ```
   
   - You need to indicate the Kafka endpoint that the client application should connect to, and the Shared Access Signature (SAS) to be used for authentication. Therefore, in the new `producer.config` file, replace:
     - `{YOUR.EVENTHUBS.NAMESPACE}` with the **eventhub_namespace_name** value that you had obtained from Terraform.
     - `{YOUR.EVENTHUBS.CONNECTION.STRING}` with the **eventhub_primary_connection_string** value.

1. Configure the Twitter app credentials and other properties:

   - Rename the `src/main/resources/app.config.TEMPLATE` file into `src/main/resources/app.config`:

     ```shell
     $ cp src/main/resources/app.config.TEMPLATE src/main/resources/app.config
     ```

   - In the new `app.config` file, replace the following values with the keys and tokens of the Twitter app you have registered (see the [Prerequisites](#Prerequisites) section):
     - `{YOUR.TWITTER.CONSUMER.KEY}`
     - `{YOUR.TWITTER.CONSUMER.SECRET}`
     - `{YOUR.TWITTER.ACCESS.TOKEN}`
     - `{YOUR.TWITTER.ACCESS.TOKEN.SECRET}`

   - You can also modify the value of the `twitter.track.terms` property to filter tweets that match a different set of keywords. You can provide a list of comma-separated keywords of your choice.

     > **Note**: the `kafka.topic` value corresponds to the name of the Event Hub, which in this case is preconfigured by the Terraform script. Each Event Hub corresponds, conceptually, to a _topic_ in Kafka (whereas an Event Hubs _namespace_ corresponds to a _cluster_ in Kafka). A Kafka and Azure Event Hubs conceptual mapping can be found [here](https://github.com/MicrosoftDocs/azure-docs/blob/master/articles/event-hubs/event-hubs-for-kafka-ecosystem-overview.md).

After you have correctly configured the properties in the `producer.config` and `app.config` files, run the Twitter client application by executing the following commands:
```shell
$ cd twitter-client
$ mvn clean compile
$ mvn exec:java
```

From the output, you should be able to verify that the client application can successfully connect to Azure Event Hubs through the Kafka Protocol and starts sending it all tweets as they are received from Twitter.

Leave the application running until the end of this demo. You can interrupt it aftwerwards using the `Ctrl+C` command.

# Create a table in the Azure SQL Data Warehouse

1. Return to the [Azure portal](https://portal.azure.com).

1. Navigate to the newly provisioned SQL Server service (`sqlserver<#>`), then select **Firewalls and virtual networks** on the left-hand menu.

1. Click on the **Add client IP** button and then select the **Save** button.

1. Navigate to the newly provisioning SQL Data Warehouse database (`tweetsdb`), then select **Query editor** on the left-hand menu.

1. Enter the following credentials:
   - _Authorization type_: `SQL server authentication`
   - _Login_: the **sql_server_login** value returned by Terraform
   - _Password_: the **sql_server_password** value returned by Terraform

1. In the query editor, copy and paste the content of the `tweets.sql` to create the `tweets` table, then click **Run**.

1. Refresh and expand the **Tables** tree in the left-hand pane. You should see that the `dbo.tweets` table has been created as shown in the screenshot below:
    
    ![Create a table in the Azure SQL Data Warehouse](media/sql-dwh-create-table.png 'Create a table in the Azure SQL Data Warehouse')

# Configure and run the Azure Stream Analytics job

## Configure the job's outputs

1. Return to the [Azure portal](https://portal.azure.com).

1. Navigate to the newly provisioned Stream Analytics job (`TwitterStoreProjectedFieldsJob`), then select **Outputs** on the left-hand menu.

1. Click on the **Add** button and then select **SQL Database**. Enter the following values in the right-hand pane:
   - _Output alias_: `sqldwh-stream-output`
   - _Database_: `tweetsdb`
   - _Server name_: the **sql_server_name** value returned by Terraform
   - _Username_: the **sql_server_login** value returned by Terraform
   - _Password_: the **sql_server_password** value returned by Terraform
   - _Table_: `tweets`

   ![Create the SQL Data Warehouse output](media/asa-output-dwh-create.png 'Create the SQL Data Warehouse output in the Stream Analytics job')

1. Select the **Inherit partition scheme** option, then click **Save**.

1. Azure Stream Analytics tests the connection to the SQL Data Warehouse. Wait a few seconds and ensure that you receive a notification in the Azure portal stating that the connect test was successful.

   ![Test the SQL Data Warehouse output](media/asa-output-dwh-test.png 'Test the SQL Data Warehouse output in the Stream Analytics job')

1. From the left-hand menu of the Stream Analytics job, select **Outputs** again.

1. Click on the **Add** button and then select **Power BI**. Enter the following values in the right-hand pane:
   - _Output alias_: `powerbi-stream-output`
   - _Group workspace_: **Authorize connection to load workspaces**
   - _Dataset name_: `TwitterDataset`
   - _Table name_: `tweets`

   ![Create the Power BI output](media/asa-output-pbi-create.png 'Create the Power BI output in the Stream Analytics job')

1. Click on the **Authorize** button and follow the instructions on screen to login in Power BI with your credentials and complete the authorization process.

1. When you have completed the authorization process, click on **Save**.

## Start the job

1. Navigate to the Stream Analytics job (`TwitterStoreProjectedFieldsJob`), then select **Overview** on the left-hand menu.

1. Click on the **Start** button to run the job, then select **Now** as the `job output start time`, and click on **Start** in the right-hand pane.

1. Wait a few moments. If everything was configured properly, you will receive a notification in the Azure portal stating that the job was successfully started.

# Connect to the data and visualize it

## Verify the tweets are stored in the Azure SQL Data Warehouse

1. Navigate to the SQL Data Warehouse database (`tweetsdb`), then select **Query editor** on the left-hand menu.

1. Enter the following credentials:
   - _Authorization type_: `SQL server authentication`
   - _Login_: the **sql_server_login** value returned by Terraform
   - _Password_: the **sql_server_password** value returned by Terraform

1. In the query editor, enter:
   ```sql
   SELECT * FROM tweets
   ```

1. Click **Run**. The query should return the tweets that the Stream Analytics job is ingesting in the SQL Data Warehouse.
   
   ![Query the SQL Data Warehouse](media/sql-dwh-query-table.png 'Return the list of the tweets ingested in the SQL Data Warehouse')

## Create a simple real-time dashboard in Power BI

1. Navigate to the [Power BI](https://app.powerbi.com/?noSignUpCheck=1) online service and login using your credentials

1. Select **My Workspace** on the left-hand menu, then click on **Datasets**.

1. On the `TwitterDataset`, that was newly created by Azure Stream Analytics, click on the ![create report](media/pbi-report-icon.png) icon in the **Actions** menu to create a report using this dataset.

1. Use the `tweets` table to create a basic report. In the example shown below, we created a couple of visualizations:
   - A _card_ reporting the number of tweets ingested so far
   - A _line chart_ showing the number of tweets received across time

   ![Power BI sample report](media/pbi-sample-report.png 'Power BI sample report')

1. Select the visual that you want to be updated in near real-time, and click on its ![pin visual](media/pbi-pin-icon.png) icon to pin it to a dashboard.

1. If a dialog box is shown, enter a _name_ for your report and click on **Save**.

1. In the **Pin to dashboard** dialog, select **New dashboard** and enter a dashboard _name_. Then click on **Pin**.

   ![Power BI sample dashboard](media/pbi-sample-dashboard.png 'Power BI sample dashboard')

1. Navigate to the dashboard you just created, and you should observe that the visual you just pinned is refreshing automatically as new tweets are streamed into the platform.

_Congratulations! You have successfully setup an end-to-end, fully-managed real-time processing application on Microsoft Azure!_

# Cleanup the allocated resources

## Stop the Stream Analytics job

1. Navigate to the Stream Analytics job (`TwitterStoreProjectedFieldsJob`), then select **Overview** on the left-hand menu.

1. Click on the **Stop** button to stop the job.

1. Wait a few moments, until you receive a notification in the Azure portal stating that the job was successfully stopped.

## Run Terraform to destroy the environment

Run the following Terraform command to cleanup all allocated resources and destroy the environment:
```shell
$ terraform destroy
```