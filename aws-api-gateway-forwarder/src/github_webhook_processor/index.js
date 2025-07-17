const https = require('https');
const http = require('http');
const url = require('url');

const TARGET_API_ENDPOINT = process.env.TARGET_API_ENDPOINT;

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));

    const batchItemFailures = [];

    await Promise.all(event.Records.map(async (record) => {
        console.log('Processing record:', JSON.stringify(record, null, 2));

        try {
            // The GitHub payload is directly in the body
            const githubPayload = JSON.parse(record.body);
            console.log('GitHub payload:', JSON.stringify(githubPayload, null, 2));

            // Extract all GitHub-related headers from message attributes
            const headers = {
                'Content-Type': 'application/json',
            };
            for (const [key, value] of Object.entries(record.messageAttributes)) {
                if (key.startsWith('X-GitHub-') || key === 'X-Hub-Signature') {
                    headers[key] = value.stringValue;
                }
            }

            // Add X-GitHub-Event header if not present
            if (!headers['X-GitHub-Event']) {
                headers['X-GitHub-Event'] = githubPayload.hasOwnProperty('pull_request') ? 'pull_request' : 'push';
            }

            console.log('Headers:', JSON.stringify(headers, null, 2));

            // Parse the TARGET_API_ENDPOINT
            const parsedUrl = new url.URL(TARGET_API_ENDPOINT);

            // Choose http or https module based on the protocol
            const requestModule = parsedUrl.protocol === 'https:' ? https : http;

            // Create the request promise
            const requestPromise = new Promise((resolve, reject) => {
                const req = requestModule.request({
                    hostname: parsedUrl.hostname,
                    port: parsedUrl.port || (parsedUrl.protocol === 'https:' ? 443 : 80),
                    path: parsedUrl.pathname + parsedUrl.search,
                    method: 'POST',
                    headers: headers
                }, (res) => {
                    let data = '';
                    res.on('data', (chunk) => {
                        data += chunk;
                    });
                    res.on('end', () => {
                        console.log(`Response from Jenkins: ${res.statusCode} ${res.statusMessage}`);
                        console.log(`Response body: ${data}`);
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                            resolve();
                        } else {
                            reject(new Error(`HTTP request failed with status ${res.statusCode}`));
                        }
                    });
                });

                req.on('error', (error) => {
                    console.error('Error making request to Jenkins:', error);
                    reject(error);
                });

                // Write the GitHub payload to the request body
                req.write(JSON.stringify(githubPayload));
                req.end();
            });

            await requestPromise;
            console.log('Successfully processed record');
        } catch (error) {
            console.error('Error processing record:', error);
            // Mark this message to be returned to SQS for reprocessing
            batchItemFailures.push({ itemIdentifier: record.messageId });
        }
    }));

    return { batchItemFailures };
};