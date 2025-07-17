const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const crypto = require('crypto');

const sqs = new SQSClient();
const ssm = new SSMClient();

const SQS_QUEUE_URL = process.env.SQS_QUEUE_URL;
const GITHUB_WEBHOOK_SECRET_NAME = process.env.GITHUB_WEBHOOK_SECRET_NAME;

let cachedSecret;

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


exports.handler = async (event) => {
    const headers = event.headers;
    const body = event.body;
    const signature = headers['X-Hub-Signature-256'];
    const deliveryId = headers['X-GitHub-Delivery'];

    // Validate the request is from GitHub
    if (!signature || !deliveryId) {
        return {
            statusCode: 400,
            body: JSON.stringify({ message: 'Invalid request' })
        };
    }

    // Retrieve the webhook secret
    const GITHUB_WEBHOOK_SECRET = await getSecret();

    // Validate the webhook secret
    const hmac = crypto.createHmac('sha256', GITHUB_WEBHOOK_SECRET);
    const digest = `sha256=${hmac.update(body).digest('hex')}`;

    if (signature !== digest) {
        return {
            statusCode: 401,
            body: JSON.stringify({ message: 'Invalid signature' })
        };
    }

    // Forward the payload to SQS
    const params = {
        MessageBody: body,
        QueueUrl: SQS_QUEUE_URL,
        MessageAttributes: {
            'X-GitHub-Delivery': {
                DataType: 'String',
                StringValue: deliveryId
            }
        }
    };

    try {
        await sqs.send(new SendMessageCommand(params));
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Message received' })
        };
    } catch (error) {
        console.error('Error sending message to SQS:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: 'Internal server error' })
        };
    }
};