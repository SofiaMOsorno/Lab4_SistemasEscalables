variable "aws_region" {
  description = "AWS region in which to deploy the lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to prefix AWS resources."
  type        = string
  default     = "cache-lab"
}

variable "vpc_cidr" {
  description = "CIDR range for the application VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "database_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "cachelab"
}

variable "database_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "cachelab_admin"
}

variable "database_password" {
  description = "PostgreSQL master password."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type."
  type        = string
  default     = "cache.t3.micro"
}

variable "cache_ttl_seconds" {
  description = "Redis TTL for database results."
  type        = number
  default     = 300
}
