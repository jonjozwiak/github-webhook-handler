output "api_gateway_url" {
  description = "The URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_deployment.webhook_deployment.invoke_url}${aws_api_gateway_stage.prod.stage_name}${aws_api_gateway_resource.webhook_resource.path}"
}

output "lambda_webhook_to_s3_function_name" {
  description = "The name of the Lambda function that receives webhooks"
  value       = aws_lambda_function.github_webhook_to_s3.function_name
}

output "sqs_dlq_url" {
  description = "The URL of the SQS queue for webhook processing"
  value       = aws_sqs_queue.dlq.url
}

output "sqs_dlq_arn" {
  description = "The ARN of the SQS queue for webhook processing"
  value       = aws_sqs_queue.dlq.arn
}

output "github_webhook_secret_parameter_name" {
  description = "The name of the SSM Parameter storing the GitHub webhook secret"
  value       = aws_ssm_parameter.github_webhook_secret.name
}

output "alert_topic_arn" {
  description = "The ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for webhook data"
  value       = aws_s3_bucket.webhook_data.bucket
}
output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket for webhook data"
  value       = aws_s3_bucket.webhook_data.arn
}
