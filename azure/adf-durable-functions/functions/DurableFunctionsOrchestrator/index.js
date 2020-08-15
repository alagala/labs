/*
 * This function is not intended to be invoked directly. Instead it will be
 * triggered by an HTTP starter function.
 * 
 */

const df = require("durable-functions");

module.exports = df.orchestrator(function* (context) {
    const outputs = [];

    outputs.push(yield context.df.callActivity("DownloadDataToBlob"));
    
    return outputs;
});