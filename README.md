# Summary

Welcome to a collection of labs that I have created, in the course of my own work, to facilitate the teaching and learning of various cloud-based platforms, services and frameworks in the field of Big Data, Machine Learning, and Artificial Intelligence.

As much as possible, I have relied on [Terraform](https://www.terraform.io/) to quickly spin up and experiment with the environments needed by the labs.

I hope you find it useful, and of course you are more than welcome to submit your contributions.

Here is a summary of the labs currently provided:

- **Microsoft Azure**:

  - [Real-time data ingestion and processing with Microsoft Azure fully-managed services: hands-on lab](azure/stream-analytics), demonstrating the use of:
    - **Event Hubs** exposed as an [Apache Kafka](https://kafka.apache.org/) cluster, for ingestion of streaming data
    - **Stream Analytics**, for real-time processing of streaming data
    - **SQL Data Warehouse**, for the storage and analysis of big data volumes
    - **Power BI**, for business intelligence and data visualization

  - [Graph processing with Azure Databricks and Cosmos DB: hands-on lab](azure/cosmosdb/graph), demonstrating the use of:
    - **Cosmos DB** with Gremlin APIs, for storing and searching graphs
    - **Azure Databricks**, for graph analytics

  - [Azure Databricks integration with Cosmos DB: hands-on lab](azure/databricks), demonstrating the use of:
    - Integration of **Azure Databricks** and **Cosmos DB** via the [Azure Cosmos DB Connector for Apache Spark](https://github.com/Azure/azure-cosmosdb-spark)
    - Reusability of the environment through Terraform

  - [Use a cloud-based notebook server to get started with Azure Machine Learning](azure/machine-learning/basic), demonstrating how to:
    - Create a new cloud-based notebook server
    - Leverage the **Azure Machine Learning service**
    - Run automated machine learning experiments (**AutoML**). 

  - [Deploy and access Azure HDInsight in a private subnet](azure/hdinsight/hdinsight-private-subnet.ipynb), demonstrating how to:
    - Deploy an **HDInsight** cluster in a private subnet
    - Configure the netwok security groups (NSG) that are necessary to deny access from the public Internet through the public endpoint
    - Use an SSH tunnel with dynamic port forwarding to access the administrative web interfaces provided by the HDInsight cluster (eg. Ambari or the Spark UI)