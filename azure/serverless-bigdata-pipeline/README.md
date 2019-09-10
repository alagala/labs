# Serverless real-time data ingestion and processing with Microsoft Azure Event Hubs and Azure Functions: hands-on lab

This guide will help you spin up an environment to test serverless real-time data ingestion and processing using the following Microsoft Azure services: Kafka-enabled [Event Hubs](https://docs.microsoft.com/en-us/azure/event-hubs/), [Functions](https://docs.microsoft.com/en-us/azure/azure-functions/), and [Blob Storage](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction).

A sample client application is provided to showcase how the platform works end-to-end. The application consists of a basic client that consumes Twitter’s tweets using the Twitter Streaming APIs, and publishes each tweet (that matches a specified set of keywords) to Azure Event Hubs using the Kafka client APIs. Once the tweets are ingested in an Event Hub, they are processed individually - as they are received - by an Azure Function that parses each tweet and outputs it to a second Event Hub. This Event Hub is setup with [Capture](https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-capture-overview enabled, so that the processed tweets can be batched specifying a time or size interval and stored on Blob Storage, code-less.

The diagram below shows the logical architecture of the solution.
   
   ![Logical architecture](media/architecture-logical.png 'Logical architecture')

The solution is useful when you need a fully-managed platform to process streaming data (eg. telemetry data), atomically, in a way that is responsive to extreme bursts in throughput. Should you need capabilities around complex event processing, sorting, aggregating, and joining streaming data over a period of time, we recommend that you look instead at our other lab: [Real-time data ingestion and processing with Microsoft Azure fully-managed services: hands-on lab](../stream-analytics)

## Prerequisites

1. Microsoft [Azure subscription](https://azure.microsoft.com/en-us/)
1. [Conda](https://conda.io/projects/conda/en/latest/user-guide/install/index.html) to create a virtual environment with Python 3.6
1. [Azure Functions Core Tools](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local) (version 2.x) to run the provided Python-based Function locally and publish it to Azure
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

1. You should see a resource group named `<PROJECT_NAME>-poc-rg` (eg. `serverless-poc-rg`).

1. Click on it and observe that the following services have been created:
   - `<PROJECT_NAME><#>`: the **Azure Storage account**, that the streaming data will be captured and archived to (by Azure Event Hubs).
   - `<PROJECT_NAME>-kafka-<#>`: the **Azure Event Hubs namespace**. Event Hubs is configured to provide a Kafka endpoint that can be used by new or existing Kafka-based applications as an alternative to running your own Kafka cluster. An Event Hubs namespace corresponds to a Kafka cluster.
   - `<PROJECT_NAME>-funcapp-<#>`: the **Azure Function App**, ie. the serverless compute service that enables you to run code on-demand without having to explicitly provision or manage infrastructure.
   - `<PROJECT_NAME>-poc-app-insights`: the **Azure Application Insights** service that is used to help you monitor your Azure Functions. Consult the [Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview) for more details.
   - `<PROJECT_NAME>-poc-service-plan`: the **Azure App Service Plan**, that defines the consumption plan to be used by Azure Functions (a consumption plan is billed based on per-second resource consumption and executions).

## Copy the Terraform output variables

Terraform outputs a few variables that you need to configure the Kafka clients (including the sample Twitter client application provided) to send streaming data to Azure Event Hubs, and to publish the provided Function to Azure:

Copy the following property values and paste them to Notepad or some other text application that you can reference later:
- **eventhub_namespace_name** and **eventhub_primary_connection_string**
- **funcapp_name**

You can also reproduce the values with the following commands:
```shell
$ terraform output eventhub_namespace_name
$ terraform output eventhub_primary_connection_string
$ terraform output funcapp_name
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

# Test the Azure Function locally and publish it to Azure

Create a Python 3.6 environment with Conda, then test the provided Azure Function locally before publishing it to Azure (you will need Conda and the Azure Functions Core Tools installed on your machine - see the [Prerequisites](#Prerequisites) section). After cloning the repository execute the following commands:

```shell
$ cd functions
$ conda create -p .venv/functions python=3.6
$ conda activate .venv/functions
$ func host start
```

If the Twitter client application is running and receiving Tweets, you should see each tweet being processed and logged to the console by the Azure Function.

You are now ready to publish the function to Azure, executing the following command (replacing {FUNCAPP_NAME} with the **funcapp_name** value output by Terraform):

```shell
$ func azure functionapp publish {FUNCAPP_NAME} --build remote
```

_Congratulations! You have successfully setup an end-to-end, serverless real-time processing application on Microsoft Azure!_

# Cleanup the allocated resources

## Run Terraform to destroy the environment

Run the following Terraform command to cleanup all allocated resources and destroy the environment:
```shell
$ terraform destroy
```