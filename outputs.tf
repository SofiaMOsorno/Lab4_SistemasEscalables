output "alb_dns_endpoint" {
  description = "HTTP endpoint for curl or wrk2 testing."
  value       = "http://${aws_lb.api.dns_name}"
}

output "rds_endpoint" {
  description = "Private PostgreSQL endpoint."
  value       = "${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}"
}

output "elasticache_endpoint" {
  description = "Private Redis endpoint."
  value       = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

output "lambda_function_details" {
  description = "Deployed Lambda function details."
  value = {
    name    = aws_lambda_function.api.function_name
    arn     = aws_lambda_function.api.arn
    runtime = aws_lambda_function.api.runtime
    handler = aws_lambda_function.api.handler
  }
}

output "cloudwatch_log_group" {
  description = "Lambda's standard CloudWatch log group."
  value       = "/aws/lambda/${aws_lambda_function.api.function_name}"
}
