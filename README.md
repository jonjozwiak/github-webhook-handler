# GitHub Webhook Handlers

This repository contains examples of GitHub webhook handlers.

* Forwarding webhooks to a private network

The example here uses an AWS API Gateway to forward webhooks to a private network.  Within the private network is an EC2 instance running Jenkins.  The Jenkins host is not exposed to the public internet.  Instead webhooks are forwarded to an SQS queue.  A lambda function in the private VPC reads from the SQS queue and triggers a Jenkins build.

To walk through this example, first look at the `aws-jenkins-in-vpc` example to get the private network and Jenkins host setup.  Then look at the `aws-api-gateway-forwarder` example to see how the setup the webhook forwarder to the private network.  While this example uses a Jenkins host in AWS this could be used to forward to any service within a private network.  It could also be used to forward to an on premises service when Direct Connect or VPN is setup.
