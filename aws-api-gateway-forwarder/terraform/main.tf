
resource "aws_sqs_queue" "github_webhook_queue" {
  name                    = "github-webhook-queue"
  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.github_webhook_dlq.arn
    maxReceiveCount     = 5  # Adjust this value as needed
  })
}

resource "aws_sqs_queue" "github_webhook_dlq" {
  name                    = "github-webhook-dlq"
  sqs_managed_sse_enabled = true
}


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

# Allow the lambda function to log, access SSM, send/receive messages to SQS, and create network interfaces to run in a VPC
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
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Effect   = "Allow",
        Resource = aws_sqs_queue.github_webhook_queue.arn
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ],
        Resource = "*"
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
data "archive_file" "github_webhook_receiver_lambda_zip" {
  type = "zip"

  source_dir  = "${abspath("${path.module}/../src/github_webhook_receiver")}"
  output_path = "${abspath("${path.module}/../src/github_webhook_receiver.zip")}"
}

data "archive_file" "github_webhook_processor_lambda_zip" {
  type = "zip"

  source_dir  = "${abspath("${path.module}/../src/github_webhook_processor")}"
  output_path = "${abspath("${path.module}/../src/github_webhook_processor.zip")}"
}

// Log Groups for logging
resource "aws_cloudwatch_log_group" "github_webhook_receiver_log_group" {
  name              = "/aws/lambda/github_webhook_receiver"
  retention_in_days = var.log_group_retention_in_days

  tags = {
    Application = "Github Webhook Handler"
    Name        = "Lambda Receiver Logs"
  }
}

resource "aws_cloudwatch_log_group" "github_webhook_processor_log_group" {
  name              = "/aws/lambda/github_webhook_processor"
  retention_in_days = var.log_group_retention_in_days

  tags = {
    Application = "Github Webhook Handler"
    Name        = "Lambda Processor Logs"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api_gateway/${aws_api_gateway_rest_api.github_webhook_api.name}"
  retention_in_days = var.log_group_retention_in_days

  tags = {
    Application = "Github Webhook Handler"
    Name        = "API Gateway Logs"
  }
}

// Upload the Lambda Functions to S3
resource "aws_s3_object" "lambda_receiver_object" {
  key                    = "github_webhook_receiver.zip"
  bucket                 = aws_s3_bucket.lambda_bucket.id
  source                 = data.archive_file.github_webhook_receiver_lambda_zip.output_path
  etag                   = filemd5(data.archive_file.github_webhook_receiver_lambda_zip.output_path)
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "lambda_processor_object" {
  key                    = "github_webhook_processor.zip"
  bucket                 = aws_s3_bucket.lambda_bucket.id
  source                 = data.archive_file.github_webhook_processor_lambda_zip.output_path
  etag                   = filemd5(data.archive_file.github_webhook_processor_lambda_zip.output_path)
  server_side_encryption = "AES256"
}

// Lambda function to receive the webhook from API Gateway and send to SQS
resource "aws_lambda_function" "github_webhook_receiver" {
  //filename         = "lambda_receiver.zip"
  function_name    = "github_webhook_receiver"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.github_webhook_receiver_lambda_zip.output_base64sha256
  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_receiver_object.key

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.github_webhook_queue.url
      GITHUB_WEBHOOK_SECRET_NAME = aws_ssm_parameter.github_webhook_secret.name
    }
  }

  tracing_config {
    mode = "Active"
  }
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
  uri         = aws_lambda_function.github_webhook_receiver.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_webhook_receiver.function_name
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

// Subnets to use for the Lambda SQS Processor Function
// Note your subnet must have a route to the internet or a SQS VPC endpoint... 
data "aws_subnets" "selected" {
  count = var.process_in_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

resource "aws_security_group" "sqs_processor_sg" {
  count       = var.process_in_vpc ? 1 : 0
  name        = "github_webhook_processor_sg"
  description = "Security group for GitHub Webhook Processor Lambda function"
  vpc_id      = var.vpc_id

  # Note this could be tightened up if you only want to forward to specific IPs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow egress to all IP addresses"
  }

  tags = {
    Name = "github_webhook_processor_sg"
  }
}

resource "aws_lambda_function" "sqs_processor" {
  //filename         = "lambda_processor.zip"
  function_name    = "github_webhook_processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.github_webhook_processor_lambda_zip.output_base64sha256
  s3_bucket        = aws_s3_bucket.lambda_bucket.id
  s3_key           = aws_s3_object.lambda_processor_object.key

  environment {
    variables = {
      TARGET_API_ENDPOINT = var.target_api_endpoint
    }
  }

  dynamic "vpc_config" {
    for_each = var.process_in_vpc ? [1] : []
    content {
      subnet_ids         = data.aws_subnets.selected[0].ids
      security_group_ids = [aws_security_group.sqs_processor_sg[0].id]
    }
  }

  tracing_config {
    mode = "Active"
  }

}

resource "aws_lambda_event_source_mapping" "sqs_event_source" {
  event_source_arn  = aws_sqs_queue.github_webhook_queue.arn
  function_name     = aws_lambda_function.sqs_processor.arn
  batch_size        = 10
  enabled           = true
  function_response_types = ["ReportBatchItemFailures"]
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