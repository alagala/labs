const { DefaultAzureCredential } = require("@azure/identity");
const { BlobServiceClient, StorageSharedKeyCredential } = require("@azure/storage-blob");
const { Readable } = require("readable-stream");
const fetch = require("node-fetch");

const apiURL = "https://api.carbonintensity.org.uk/regional";
const emulatorKey = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==";

const connection = process.env["AzureWebJobsStorage"];
const account = process.env["AZURE_STORAGE_ACCOUNT"];
const containerName = process.env["AZURE_STORAGE_CONTAINER"];

let emulator = connection.includes("UseDevelopmentStorage=true") &&
    account == "devstoreaccount1";

let path = emulator ?
    `http://127.0.0.1:10000/${account}` :
    `https://${account}.blob.core.windows.net`;

module.exports = async function (context) {
    context.log("Requesting data to API");
    let response = await fetch(apiURL);
    let data = await response.text();

    context.log("Retrieved response: ", data);
    const readable = Readable.from(data);

    context.log(`Connecting to the Azure Storage Blob service at ${path}`);
    const blobServiceClient = emulator ?
        new BlobServiceClient(path, new StorageSharedKeyCredential(account, emulatorKey)) :
        new BlobServiceClient(path, new DefaultAzureCredential());

    const blobName = "carbon-footprint.json";
    const containerClient = blobServiceClient.getContainerClient(containerName);
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);
    const uploadBlobResponse = await blockBlobClient.uploadStream(readable, readable.length);
    context.log(`Upload block blob ${blobName} successfully`, uploadBlobResponse.requestId);
};