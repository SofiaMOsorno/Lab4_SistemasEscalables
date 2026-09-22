resource "terraform_data" "lambda_dependencies" {
  triggers_replace = [
    filesha256("${path.module}/lambda/handler.py"),
    filesha256("${path.module}/lambda/requirements.txt"),
  ]

  provisioner "local-exec" {
    working_dir = path.module
    command     = "if (Test-Path lambda_build) { Remove-Item lambda_build -Recurse -Force }; New-Item -ItemType Directory -Path lambda_build | Out-Null; Copy-Item lambda\\handler.py lambda_build\\handler.py; python -m pip install --disable-pip-version-check --no-cache-dir --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 --only-binary=:all: -r lambda\\requirements.txt -t lambda_build"
    interpreter = ["PowerShell", "-Command"]
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda.zip"

  depends_on = [terraform_data.lambda_dependencies]
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.project_name}-api"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST           = aws_db_instance.postgres.address
      DB_PORT           = tostring(aws_db_instance.postgres.port)
      DB_NAME           = var.database_name
      DB_USER           = var.database_username
      DB_PASSWORD       = var.database_password
      REDIS_HOST        = aws_elasticache_cluster.redis.cache_nodes[0].address
      CACHE_TTL_SECONDS = tostring(var.cache_ttl_seconds)
    }
  }

}
