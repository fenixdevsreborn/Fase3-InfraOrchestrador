output "notification_queue_url" {
  value = aws_sqs_queue.notification.url
}

output "notification_queue_arn" {
  value = aws_sqs_queue.notification.arn
}

output "notification_dlq_url" {
  value = aws_sqs_queue.notification_dlq.url
}
