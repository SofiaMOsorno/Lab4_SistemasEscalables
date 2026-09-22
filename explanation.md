# AWS Cache Lab Explanation

## 1. Lab objective

This project deploys a two-tier cached API on AWS using Terraform. A client
sends an HTTP request to an Application Load Balancer (ALB). The ALB invokes a
Python AWS Lambda function. Lambda first checks Redis for previously retrieved
data. If the data is not cached, Lambda queries PostgreSQL on Amazon RDS,
stores the result in Redis, and returns the response to the client.

The architecture is designed to demonstrate:

- Infrastructure as code with Terraform.
- A serverless application using AWS Lambda.
- Persistent storage with PostgreSQL.
- In-memory caching with Redis.
- Private networking with a VPC.
- CloudWatch observability and performance measurements.
- The performance difference between cache hits and cache misses.

## 2. Architecture overview

The deployment has a public entry point and private data services:

```text
Client / curl / wrk2
          |
          v
Internet Gateway
          |
          v
Public subnets (Availability Zone A and B)
          |
          v
Application Load Balancer :80
          |
          v
Lambda target group
          |
          v
AWS Lambda: Python 3.12
          |
          +--------------------> CloudWatch Logs
          |
          +--> ElastiCache Redis :6379
          |       |
          |       +--> CACHE_HIT: return cached items
          |
          +--> Amazon RDS PostgreSQL :5432
                  |
                  +--> CACHE_MISS: query items, save result in Redis

Private subnets (Availability Zone A and B)
```

The ALB is deployed in public subnets so clients can reach it. Lambda,
PostgreSQL, and Redis use private subnets. RDS and Redis are not publicly
accessible; their security groups allow connections only from Lambda.

The request path is:

1. A client sends an HTTP request to the ALB DNS endpoint.
2. The ALB forwards the request to the Lambda target group.
3. Lambda checks Redis using the `items:v1` cache key.
4. On a hit, Lambda returns the cached JSON data.
5. On a miss, Lambda queries PostgreSQL, stores the result in Redis for 300
   seconds, and returns the data.
6. Lambda logs cache status, query timing, total response timing, request ID,
   timestamp, and errors to CloudWatch.

The VPC, subnets, route table, subnet groups, security groups, ALB, Lambda,
RDS, Redis, IAM role reference, and outputs are created or configured by
Terraform.

## 3. AWS services used

### Amazon VPC

The VPC provides the private network for the application. It uses the CIDR
range `10.0.0.0/16` and enables DNS support and DNS hostnames.

The VPC contains:

- Two public subnets for the internet-facing ALB.
- Two private subnets for Lambda networking, RDS, and Redis.
- Two Availability Zones for basic high availability.

The public subnets use CIDR ranges `10.0.1.0/24` and `10.0.2.0/24`.
The private subnets use CIDR ranges `10.0.11.0/24` and `10.0.12.0/24`.

### Internet Gateway

The Internet Gateway allows internet traffic to reach the public subnets where
the ALB is deployed. It is not used to expose the RDS database or Redis
cluster directly.

### Route tables

The public route table sends traffic destined for `0.0.0.0/0` through the
Internet Gateway. The public subnets are associated with this route table.

RDS and Redis are deployed in private subnets. They do not have public IP
addresses and are not directly reachable from the internet.

### Application Load Balancer

The ALB is the public entry point for the application. It listens on HTTP port
80 and receives requests from clients, `curl`, or `wrk2`.

The ALB uses a Lambda target group. When a request arrives, the ALB invokes the
Lambda function and returns the Lambda response to the client.

The Terraform output `alb_dns_endpoint` provides the URL used for testing:

```text
http://<alb-dns-name>
```

### AWS Lambda

Lambda runs the application without requiring a continuously running server.
The deployed runtime is Python 3.12, and the handler is
`handler.lambda_handler`.

The Lambda function is attached to the private subnets and uses a security
group that permits outbound communication to the private data services.

Lambda is responsible for:

1. Receiving the request from the ALB.
2. Reading the AWS request ID and creating a UTC timestamp.
3. Checking Redis for cached data.
4. Returning the cached value immediately when there is a cache hit.
5. Querying PostgreSQL when Redis has no value.
6. Storing database results in Redis with a configurable TTL.
7. Measuring database query time and total response time.
8. Returning a JSON response.
9. Writing structured logs to CloudWatch.

The function has a default timeout of 30 seconds and 256 MB of memory.

### Amazon ElastiCache for Redis

ElastiCache provides the in-memory cache used by the Lambda function. The lab
creates a Redis cluster with one cache node using the `cache.t3.micro` default
node type.

The cache key used by the Lambda code is:

```text
items:v1
```

On a cache miss, the database result is serialized as JSON and stored with a
default expiration of 300 seconds. The TTL is configurable through the
Terraform variable `cache_ttl_seconds`.

Redis is located in private subnets and accepts connections only from the
Lambda security group.

### Amazon RDS for PostgreSQL

RDS provides the persistent relational database. The configuration creates a
PostgreSQL 16 instance using the `db.t3.micro` default instance class, 20 GB
of storage, and private networking.

The database is named `cachelab` by default. The Lambda connects using the
database host, port, name, username, and password supplied through Terraform.

The Lambda creates the following table during the first database request if it
does not already exist:

```sql
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

If the table is empty, the Lambda inserts three sample records:

- `scalable-api`
- `redis-cache`
- `postgres-database`

The database is not publicly accessible. Its security group allows PostgreSQL
traffic on port 5432 only from the Lambda security group.

### Security groups

The Terraform configuration creates four security groups:

#### ALB security group

- Allows HTTP traffic on port 80 from `0.0.0.0/0`.
- Allows outbound traffic.

#### Lambda security group

- Allows outbound traffic to resources in the VPC.
- It does not expose an inbound application port because Lambda is invoked by
  the ALB service.

#### RDS security group

- Allows TCP port 5432 only from the Lambda security group.

#### Redis security group

- Allows TCP port 6379 only from the Lambda security group.

This prevents direct public access to the database and cache.

### IAM

AWS Academy Learner Lab does not allow this project to create a new IAM role.
Instead, Terraform reads the preexisting role:

```text
arn:aws:iam::706113607058:role/LabRole
```

The Terraform data source looks up the role by name:

```hcl
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}
```

The Lambda function uses `data.aws_iam_role.lab_role.arn`. The role must
already contain the permissions required by the lab, including permission to
write CloudWatch logs and create the elastic network interfaces needed for VPC
access. This project does not create or attach IAM policies to `LabRole`.

The ALB also receives an explicit Lambda permission allowing it to invoke the
function through the Lambda target group.

### Amazon CloudWatch Logs

Lambda automatically writes its output to the log group:

```text
/aws/lambda/<project-name>-api
```

The function writes JSON log entries for the following events:

- `CACHE_HIT`: Redis contained the requested data.
- `CACHE_MISS`: Redis did not contain the requested data.
- `DATABASE_QUERY`: includes the database query duration.
- `TOTAL_RESPONSE`: includes the total response duration, request ID, and
  timestamp.
- `REQUEST_ERROR`: includes the request ID and error information when an
  exception occurs.

These logs make it possible to compare the performance of cache hits and cache
misses in CloudWatch.

## 3. Lambda two-tier cache flow

The Lambda handler is implemented in `lambda/handler.py`.

### Cache hit

The function connects to Redis and executes a `GET` for `items:v1`. If Redis
returns a value:

1. The JSON value is decoded.
2. The function prints a `CACHE_HIT` log.
3. No database query is performed.
4. The response is returned with `"cache_status": "HIT"`.

### Cache miss

If Redis returns no value:

1. The function prints a `CACHE_MISS` log.
2. It opens a PostgreSQL connection.
3. It creates and seeds the `items` table if necessary.
4. It queries up to 100 items.
5. It measures and logs the database query duration.
6. It stores the JSON result in Redis using `SETEX`.
7. The response is returned with `"cache_status": "MISS"`.

### Response format

A successful request returns a response similar to:

```json
{
  "data": [
    {
      "id": 1,
      "name": "scalable-api",
      "created_at": "2026-09-22T17:00:00+00:00"
    }
  ],
  "response_time_ms": 12.45,
  "cache_status": "HIT",
  "timestamp": "2026-09-22T17:00:01.000000+00:00"
}
```

The exact response time and timestamp depend on the request.

If an unexpected error occurs, Lambda logs the error and returns HTTP status
500 with a request ID:

```json
{
  "error": "Internal server error",
  "request_id": "..."
}
```

## 5. Terraform files

All Terraform infrastructure files are located in the repository root.

### `versions.tf`

Defines the required Terraform version and providers:

- AWS provider.
- Archive provider for creating the Lambda ZIP package.

It also configures the AWS region and default resource tags.

### `variables.tf`

Defines configurable values such as:

- AWS region.
- Project name.
- VPC CIDR.
- Database name and username.
- Database password.
- RDS instance type.
- Redis node type.
- Cache TTL.

The database password is marked as sensitive.

### `network.tf`

Creates:

- VPC.
- Internet Gateway.
- Public and private subnets.
- Public route table.
- Public route associations.
- RDS subnet group.
- ElastiCache subnet group.

The configuration obtains available Availability Zones dynamically and uses the
first two available zones.

### `security.tf`

Creates the ALB, Lambda, RDS, and Redis security groups described above.

### `data-services.tf`

Creates:

- The PostgreSQL RDS instance.
- The Redis ElastiCache cluster.

Both services are private and use the private subnet groups.

### `lambda.tf`

Creates:

- Lambda dependency packaging.
- Lambda ZIP archive.
- A data source that reads the existing AWS Academy `LabRole`.
- Lambda function.

The Lambda function uses the existing role ARN
`arn:aws:iam::706113607058:role/LabRole`; no new IAM role or IAM policy
attachment is created by this file.

The packaging step copies `handler.py` and installs the Python dependencies
from `lambda/requirements.txt` into a build directory.

The dependencies are:

```text
psycopg2-binary==2.9.9
redis==5.0.4
```

The package is built for the AWS Lambda Python 3.12 Linux runtime.

### `alb.tf`

Creates:

- The internet-facing ALB.
- A Lambda target group.
- Permission for the ALB to invoke Lambda.
- Target group attachment.
- HTTP listener on port 80.

### `outputs.tf`

Exports:

- ALB DNS endpoint.
- RDS endpoint.
- ElastiCache endpoint.
- Lambda name, ARN, runtime, and handler.
- CloudWatch log group name.

### `README.md`

Contains deployment and testing instructions, including examples using
`terraform`, `curl`, and `wrk`.

### `.gitignore`

Excludes generated files such as:

- Terraform provider cache.
- Lambda build directory.
- Lambda ZIP archive.
- Python bytecode.

The Terraform provider lock file is retained so provider versions can be
reproduced.

## 6. Deployment

Initialize the providers:

```powershell
terraform init
```

Deploy the infrastructure with a database password:

```powershell
terraform apply -var='database_password=replace-with-a-strong-password'
```

Terraform displays a plan and asks for confirmation before creating resources.
The deployment creates billable AWS resources, so the lab should be destroyed
when it is no longer needed.

To display the public endpoint:

```powershell
terraform output -raw alb_dns_endpoint
```

To display the private database and Redis endpoints:

```powershell
terraform output rds_endpoint
terraform output elasticache_endpoint
```

## 7. Testing

Test the API with `curl`:

```powershell
curl.exe "$(terraform output -raw alb_dns_endpoint)"
```

The first request should normally produce a cache miss and query RDS. A second
request within five minutes should normally produce a cache hit:

```powershell
curl.exe "$(terraform output -raw alb_dns_endpoint)"
curl.exe "$(terraform output -raw alb_dns_endpoint)"
```

For load testing with wrk2:

```powershell
wrk -t2 -c10 -d30s -R100 "$(terraform output -raw alb_dns_endpoint)"
```

The `-R100` option requests approximately 100 requests per second. The
appropriate load depends on AWS account limits and lab requirements.

CloudWatch logs can be inspected in the Lambda log group. The logs should show
the initial database query and subsequent cache hits while the Redis value is
valid.

## 8. Validation performed

Before completing the Terraform files, the following checks were run:

```text
terraform init -backend=false
terraform validate
terraform fmt -check -recursive
python -m py_compile lambda\handler.py
git diff --check
```

The Terraform configuration initialized successfully, passed validation and
format checks, and the Python Lambda handler passed syntax compilation.

## 9. Important lab considerations

- RDS and Redis are private and cannot be accessed directly from the public
  internet.
- The Lambda function requires network interfaces in the VPC to reach RDS and
  Redis.
- The Lambda environment contains the database password because this is a
  student lab implementation. A production system should use AWS Secrets
  Manager or a similar secret-management service.
- The RDS instance uses `skip_final_snapshot = true` and
  `deletion_protection = false` to make lab cleanup easier. Production
  deployments should use backups and deletion protection.
- The current Redis deployment has one node and is intended for a lab, not
  production high availability.
- The first request may take longer because Lambda may initialize and must
  connect to both Redis and PostgreSQL.
- When the cache expires after the TTL, the next request becomes a cache miss
  and refreshes Redis from RDS.

## 10. Cleanup

Destroy the resources when finished:

```powershell
terraform destroy -var='database_password=replace-with-a-strong-password'
```

The same database password variable should be supplied because Terraform needs
it to match the configuration during destroy.
