const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const crypto = require('crypto');

const s3 = new S3Client();
const ssm = new SSMClient();

const WEBHOOK_DATA_BUCKET = process.env.WEBHOOK_DATA_BUCKET;
const GITHUB_WEBHOOK_SECRET_NAME = process.env.GITHUB_WEBHOOK_SECRET_NAME;

let cachedSecret;

const eventHandlers = require('./webhookHandlers');

async function getSecret() {
    if (cachedSecret) {
        return cachedSecret;
    }

    const parameterName = GITHUB_WEBHOOK_SECRET_NAME;
    const command = new GetParameterCommand({ Name: parameterName, WithDecryption: true });
    const response = await ssm.send(command);
    cachedSecret = response.Parameter.Value;

    return cachedSecret;
}

function flattenObject(obj, prefix = '') {
    return Object.keys(obj).reduce((acc, k) => {
        const pre = prefix.length ? prefix + '_' : '';
        if (typeof obj[k] === 'object' && obj[k] !== null && !Array.isArray(obj[k])) {
            Object.assign(acc, flattenObject(obj[k], pre + k));
        } else {
            acc[pre + k] = Array.isArray(obj[k]) ? JSON.stringify(obj[k]) : obj[k];
        }
        return acc;
    }, {});
}

exports.handler = async (event) => {
    const headers = event.headers;
    const body = event.body;
    const signature = headers['X-Hub-Signature-256'];
    const deliveryId = headers['X-GitHub-Delivery'];
    const eventType = headers['X-GitHub-Event'];

    if (!signature || !deliveryId) {
        return {
            statusCode: 400,
            body: JSON.stringify({ message: 'Invalid request' })
        };
    }

    const GITHUB_WEBHOOK_SECRET = await getSecret();

    const hmac = crypto.createHmac('sha256', GITHUB_WEBHOOK_SECRET);
    const digest = `sha256=${hmac.update(body).digest('hex')}`;

    if (signature !== digest) {
        return {
            statusCode: 401,
            body: JSON.stringify({ message: 'Invalid signature' })
        };
    }

    const rawTimestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const timestamp = new Date(); // Use the current timestamp for processing
    const rawKey = `raw/${eventType}_${deliveryId}_${rawTimestamp}.json`;

    try {
        // Store raw data immediately
        await s3.send(new PutObjectCommand({
            Bucket: WEBHOOK_DATA_BUCKET,
            Key: rawKey,
            Body: body,
            ContentType: 'application/json'
        }));

        // Process the data with retries
        await processWebhookData(body, eventType, deliveryId, timestamp);

        console.log(`Successfully processed webhook data: ${rawKey}`);
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Webhook data processed successfully' })
        };
    } catch (error) {
        console.error('Error processing webhook data:', error);
        throw error; // This will trigger the DLQ if configured
    }
};

async function processWebhookData(body, eventType, deliveryId, timestamp) {
    const maxRetries = 3;
    for (let i = 0; i < maxRetries; i++) {
        try {
            const payload = JSON.parse(body);
            
            // Use the appropriate event handler or default to the original payload
            const processedPayload = eventHandlers[eventType] 
                ? eventHandlers[eventType](payload, eventType, deliveryId)
                : payload;
            
            const flattenedPayload = flattenObject(processedPayload);

            const year = timestamp.getUTCFullYear();
            const month = String(timestamp.getUTCMonth() + 1).padStart(2, '0');
            const day = String(timestamp.getUTCDate()).padStart(2, '0');
            const hour = String(timestamp.getUTCHours()).padStart(2, '0');
            const minute = String(timestamp.getUTCMinutes()).padStart(2, '0');
            const second = String(timestamp.getUTCSeconds()).padStart(2, '0');

            const processedKey = `processed/event_type=${eventType}/year=${year}/month=${month}/day=${day}/${hour}${minute}${second}_${deliveryId}.json`;

            await s3.send(new PutObjectCommand({
                Bucket: WEBHOOK_DATA_BUCKET,
                Key: processedKey,
                Body: JSON.stringify(flattenedPayload),
                ContentType: 'application/json'
            }));

            return; // Success, exit the function
        } catch (error) {
            if (i === maxRetries - 1) throw error; // Throw on last retry
            await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, i))); // Exponential backoff
        }
    }
}