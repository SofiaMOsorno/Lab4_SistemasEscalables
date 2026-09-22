resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "Allow public HTTP traffic to the Application Load Balancer."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow ALB to invoke Lambda"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda"
  description = "Lambda access to PostgreSQL and Redis."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Lambda to private data services"
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds"
  description = "PostgreSQL accepts connections only from Lambda."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Lambda"
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.lambda.id]
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis"
  description = "Redis accepts connections only from Lambda."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from Lambda"
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    security_groups = [aws_security_group.lambda.id]
  }
}
