# Fila SQS para eventos de notificação (integração com Lambda)

resource "aws_sqs_queue" "notification" {
  name                       = "${var.name_prefix}-${var.notification_queue_name}"
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds  = 60
  receive_wait_timeout_seconds = 20
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${var.notification_queue_name}"
  })
}

# Dead-letter queue opcional (para mensagens que falharem após retries)
resource "aws_sqs_queue" "notification_dlq" {
  name = "${var.name_prefix}-${var.notification_queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 dias
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${var.notification_queue_name}-dlq"
  })
}

resource "aws_sqs_queue_redrive_policy" "notification" {
  queue_url = aws_sqs_queue.notification.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
    maxReceiveCount     = 3
  })
}
