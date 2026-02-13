# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform IaC project deploying an AWS EC2 instance with an S3 content bucket and a Temporal Cloud worker. The EC2 instance runs two services: a Node.js web server (port 80) and a Python Temporal order management worker that connects to Temporal Cloud via mTLS credentials from AWS Secrets Manager.

## Common Commands

```bash
terraform init          # Initialize providers (run once or after provider changes)
terraform plan          # Preview infrastructure changes
terraform apply         # Deploy infrastructure (prompts for confirmation)
terraform destroy       # Tear down all resources
terraform fmt           # Format .tf files
terraform validate      # Validate configuration syntax

# Targeted updates (avoid full EC2 replacement):
terraform apply -target=aws_s3_object.message   # Update S3 content only
```

## Architecture

```
Internet → Security Group (80/443/22) → EC2 (Amazon Linux 2023, t3.micro)
                                          ├─ Node.js web server (port 80, systemd: webapp)
                                          ├─ Python Temporal worker (systemd: temporal-worker)
                                          │   └─ Reads credentials from AWS Secrets Manager
                                          └─ IAM Instance Profile
                                               ├─ S3: GetObject, ListBucket → S3 content bucket
                                               └─ SecretsManager: GetSecretValue → temporal-cloud-credentials
```

**Key design decisions:**
- Uses default VPC and subnets (no custom networking)
- AMI is auto-resolved to latest Amazon Linux 2023 x86_64 via `data.aws_ami`
- `user_data_replace_on_change = true` — modifying `user-data.sh` triggers EC2 replacement
- EC2 key pair is hardcoded to `temporal-demo-key`
- S3 bucket has all public access blocked; EC2 accesses via IAM role

## File Layout

- **main.tf** — All resources: provider config, VPC/AMI data sources, S3 bucket + objects, IAM roles/policies, security group, EC2 instance
- **variables.tf** — Input variable definitions (region, app name, environment, bucket name, instance type, SSH CIDRs)
- **outputs.tf** — Outputs: instance ID/IP/DNS, website URL, bucket name, SSH command
- **terraform.tfvars** — Variable values for deployment (edit `content_bucket_name` before first deploy)
- **user-data.sh** — EC2 bootstrap script (~150 lines): installs Python 3.12, Poetry, Node.js 18; creates both systemd services; fetches Temporal creds from Secrets Manager

## Conventions

- All resources are in a single `main.tf` (no module decomposition)
- Resource names use `${var.app_name}` prefix for tags and IAM resource naming
- `templatefile()` passes `bucket_name` and `aws_region` into `user-data.sh`
- Bootstrap logs on EC2 go to `/var/log/user-data.log`; services log to journald (`journalctl -u webapp` / `journalctl -u temporal-worker`)

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.0
- AWS IAM permissions for EC2, S3, IAM, VPC, Secrets Manager
- `temporal-cloud-credentials` secret must exist in Secrets Manager with keys: `namespace`, `address`, `cert`, `key` (cert/key are base64-encoded)
- EC2 key pair named `temporal-demo-key` must exist in the target region
