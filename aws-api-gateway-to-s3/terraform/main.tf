
# Allow the lambda function to log, access SSM, and interact with S3 and X-Ray
resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-execution-policy"
  description = "IAM policy for Lambda execution"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "ssm:GetParameter"
        ],
        Effect   = "Allow",
        Resource = aws_ssm_parameter.github_webhook_secret.arn
      },
      {
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.webhook_data.arn,
          "${aws_s3_bucket.webhook_data.arn}/*"
        ]
      },
      {
        Action = [
          "sqs:SendMessage"
        ],
        Effect   = "Allow",
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Resource = "*"
      } 
    ]
  })
}

resource "aws_ssm_parameter" "github_webhook_secret" {
  name        = var.github_webhook_secret_parameter_name
  description = "GitHub Webhook Secret"
  type        = "SecureString"
  value       = var.github_webhook_secret
  tags = {
    Name = "github-webhook-secret"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

// S3 Bucket to hold Lambda function zip files
resource "aws_s3_bucket" "lambda_bucket" {
  bucket_prefix = "github-webhook-lambda-"
  force_destroy = true

}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket_ownership" {
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_bucket_public_access" {
  bucket = aws_s3_bucket.lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// Zip the Lambda Functions
data "archive_file" "github_webhook_to_s3_lambda_zip" {
  type = "zip"

  source_dir  = "${abspath("${path.module}/../src/github_webhook_to_s3")}"
  output_path = "${abspath("${path.module}/../src/github_webhook_to_s3.zip")}"
}

# S3 Bucket for storing webhook data
resource "aws_s3_bucket" "webhook_data" {
  bucket_prefix = "github-webhook-data-"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "webhook_data_ownership" {
  bucket = aws_s3_bucket.webhook_data.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "webhook_data_public_access" {
  bucket = aws_s3_bucket.webhook_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// Log Groups for logging
resource "aws_cloudwatch_log_group" "github_webhook_to_s3_log_group" {
  name              = "/aws/lambda/github_webhook_to_s3"
  retention_in_days = var.log_group_retention_in_days

  tags = {
    Application = "Github Webhook to S3 Handler"
    Name        = "Lambda Receiver Logs"
  }
}


resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api_gateway/${aws_api_gateway_rest_api.github_webhook_api.name}"
  retention_in_days = var.log_group_retention_in_days

  tags = {
    Application = "Github Webhook to S3 Handler"
    Name        = "API Gateway Logs"
  }
}

// Upload the Lambda Functions to S3
resource "aws_s3_object" "lambda_to_s3_object" {
  key                    = "github_webhook_to_s3.zip"
  bucket                 = aws_s3_bucket.lambda_bucket.id
  source                 = data.archive_file.github_webhook_to_s3_lambda_zip.output_path
  etag                   = filemd5(data.archive_file.github_webhook_to_s3_lambda_zip.output_path)
  server_side_encryption = "AES256"
}

// Lambda function to receive the webhook from API Gateway and send to SQS
resource "aws_lambda_function" "github_webhook_to_s3" {
  //filename         = "lambda_receiver.zip"
  function_name    = "github_webhook_to_s3"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.github_webhook_to_s3_lambda_zip.output_base64sha256
  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_to_s3_object.key

  environment {
    variables = {
      GITHUB_WEBHOOK_SECRET_NAME = aws_ssm_parameter.github_webhook_secret.name
      WEBHOOK_DATA_BUCKET = aws_s3_bucket.webhook_data.id
    }
  }

  tracing_config {
    mode = "Active"
  }
  
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
}

// Lambda function Dead letter queue
resource "aws_sqs_queue" "dlq" {
  name = "github-webhook-dlq"
  sqs_managed_sse_enabled = true
}

resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

// API Gateway to forward the webhook to the Lambda function
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
}

# Note this is region-wide.  May not want to do this here... 
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}

resource "aws_api_gateway_rest_api" "github_webhook_api" {
  name        = "github-webhook-api"
  description = "API Gateway for GitHub Webhook"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "webhook_resource" {
  rest_api_id = aws_api_gateway_rest_api.github_webhook_api.id
  parent_id   = aws_api_gateway_rest_api.github_webhook_api.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook_method" {
  rest_api_id   = aws_api_gateway_rest_api.github_webhook_api.id
  resource_id   = aws_api_gateway_resource.webhook_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook_integration" {
  rest_api_id = aws_api_gateway_rest_api.github_webhook_api.id
  resource_id = aws_api_gateway_resource.webhook_resource.id
  http_method = aws_api_gateway_method.webhook_method.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.github_webhook_to_s3.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_webhook_to_s3.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.github_webhook_api.execution_arn}/*/*"
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.webhook_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.github_webhook_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  xray_tracing_enabled = true

  depends_on = [aws_api_gateway_account.main]
}

resource "aws_api_gateway_deployment" "webhook_deployment" {
  depends_on = [
    aws_api_gateway_integration.webhook_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.github_webhook_api.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method_settings" "method_settings" {
  rest_api_id = aws_api_gateway_rest_api.github_webhook_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = true
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

// Listen only to GitHub hooks range of IPs as defined here: https://api.github.com/meta
resource "aws_api_gateway_rest_api_policy" "github_ip_restriction" {
  rest_api_id = aws_api_gateway_rest_api.github_webhook_api.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect: "Allow",
        Principal: "*",
        Action: "execute-api:Invoke",
        Resource: "${aws_api_gateway_rest_api.github_webhook_api.execution_arn}/*/*",
        Condition: {
          IpAddress: {
            "aws:SourceIp": [
              "192.30.252.0/22",
              "185.199.108.0/22",
              "140.82.112.0/20",
              "143.55.64.0/20"
            ]
          }
        }
      }
    ]
  })
}

// Athena Configuration
# Athena resources
/*
resource "aws_athena_database" "webhook_data" {
  name   = "github_webhook_data"
  bucket = aws_s3_bucket.webhook_data.id
}

resource "aws_athena_workgroup" "webhook_queries" {
  name = "webhook_queries"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.webhook_data.bucket}/athena_results/"
    }
  }
}
*/