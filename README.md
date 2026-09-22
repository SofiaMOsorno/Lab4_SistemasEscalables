# AWS cache lab infrastructure

This Terraform configuration deploys a VPC with public ALB subnets and private
Lambda, PostgreSQL, and Redis subnets. The ALB invokes the Python Lambda. On a
cache miss, the Lambda queries PostgreSQL, seeds a small `items` table on the
first request, stores the result in Redis for `cache_ttl_seconds`, and returns
the data, cache status, elapsed time, and UTC timestamp.

The Lambda writes structured JSON log records containing `CACHE_HIT`,
`CACHE_MISS`, `DATABASE_QUERY`, `TOTAL_RESPONSE`, and `REQUEST_ERROR` to its
CloudWatch log group.

## File structure

The repository is organized as follows:

```text
Lab4_SistemasEscalables/
├── explanation.md
├── .gitignore
├── README.md
├── versions.tf
├── variables.tf
├── network.tf
├── security.tf
├── data-services.tf
├── lambda.tf
├── alb.tf
├── outputs.tf
└── lambda/
    ├── handler.py
    └── requirements.txt
```

### Terraform file responsibilities

| File | Responsibility |
|---|---|
| `versions.tf` | Configures Terraform and the AWS and Archive providers. |
| `variables.tf` | Defines deployment, database, Redis, and cache TTL variables. |
| `network.tf` | Creates the VPC, subnets, routes, database subnet group, and Redis subnet group. |
| `security.tf` | Creates security groups for the ALB, Lambda, RDS, and Redis. |
| `data-services.tf` | Creates the PostgreSQL RDS instance and ElastiCache Redis cluster. |
| `lambda.tf` | Packages dependencies and creates the Lambda IAM role and function. |
| `alb.tf` | Creates the ALB, Lambda target group, listener, and invocation permission. |
| `outputs.tf` | Exposes the ALB, RDS, Redis, Lambda, and CloudWatch outputs. |
| `lambda/handler.py` | Implements the Redis-first, PostgreSQL-fallback cache logic. |
| `lambda/requirements.txt` | Lists the Python dependencies packaged with Lambda. |
| `explanation.md` | Documents the architecture, services, request flow, deployment, and testing. |

Generated deployment artifacts such as `.terraform/`, `lambda_build/`,
`lambda.zip`, and Python bytecode are excluded by the repository `.gitignore`.

## Deploy

```powershell
terraform init
terraform apply -var='database_password=replace-with-a-strong-password'
terraform output alb_dns_endpoint
```

The local packaging step requires Python and pip. It installs Linux-compatible
`psycopg2-binary` and `redis` wheels into the deployment zip for the AWS
`python3.12` runtime.

Test the ALB endpoint with curl, or use wrk2 after retrieving the output:

```powershell
curl.exe "$(terraform output -raw alb_dns_endpoint)"
wrk -t2 -c10 -d30s -R100 "$(terraform output -raw alb_dns_endpoint)"
```

RDS and Redis are intentionally private and are reachable by the Lambda only.
For a lab teardown, run `terraform destroy` with the same database password
variable.
