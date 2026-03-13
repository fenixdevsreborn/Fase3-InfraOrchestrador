# Lambda de notificação — container image (ECR), trigger SQS
# IAM mínimo: SQS (consumir fila), CloudWatch Logs, SES (envio de e-mail)

resource "aws_iam_role" "lambda" {
  name_prefix        = "${var.name_prefix}-notif-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Política: CloudWatch Logs + SQS receive/delete
resource "aws_iam_role_policy" "lambda" {
  name_prefix = "${var.name_prefix}-notif-"
  role        = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [var.sqs_queue_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-notification"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "main" {
  function_name = "${var.name_prefix}-notification"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:${var.image_tag}"
  timeout       = var.timeout_sec
  memory_size   = var.memory_mb

  environment {
    variables = {
      # Apps podem sobrescrever via variáveis adicionais
      ASPNETCORE_ENVIRONMENT = "Production"
    }
  }

  tags = var.tags
}

# Event source: SQS -> Lambda
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.main.function_name
  batch_size       = 10
}

# Permissão para SQS invocar Lambda
resource "aws_lambda_permission" "sqs" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = var.sqs_queue_arn
}
