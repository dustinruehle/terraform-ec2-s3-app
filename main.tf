terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create S3 bucket for content storage
resource "aws_s3_bucket" "content" {
  bucket = var.content_bucket_name

  tags = {
    Name        = "EC2 Web App Content"
    Environment = var.environment
  }
}

# Block public access to S3 bucket (EC2 will access via IAM role)
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload content files to S3
resource "aws_s3_object" "message" {
  bucket       = aws_s3_bucket.content.id
  key          = "message.txt"
  content      = "Hello from S3! This message was retrieved from an S3 bucket by the EC2 instance."
  content_type = "text/plain"
}

resource "aws_s3_object" "config" {
  bucket = aws_s3_bucket.content.id
  key    = "config.json"
  content = jsonencode({
    app_name    = "Hello World EC2 + S3 App"
    version     = "1.0.0"
    description = "A web application running on EC2 that retrieves content from S3"
    features    = ["EC2 Hosting", "S3 Integration", "IAM Role Authentication"]
  })
  content_type = "application/json"
}

# IAM role for EC2 to access S3
resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.app_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-ec2-role"
  }
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${var.app_name}-s3-policy"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.content.arn,
          "${aws_s3_bucket.content.arn}/*"
        ]
      }
    ]
  })
}

# --- Temporal Secrets Access Policy ---
resource "aws_iam_policy" "temporal_secrets_policy" {
  name        = "TemporalSecretsAccessPolicy"
  description = "Allow EC2 to read Temporal Cloud credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:temporal-cloud-credentials*"
      }
    ]
  })
}

# Attach the Temporal Secrets policy to the EC2 role
resource "aws_iam_role_policy_attachment" "temporal_secrets_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.temporal_secrets_policy.arn
}

# Data source for account ID (add only once per file)
data "aws_caller_identity" "current" {}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-ec2-profile"
  role = aws_iam_role.ec2_s3_role.name
}

# Security group for EC2 instance
resource "aws_security_group" "web_server" {
  name        = "${var.app_name}-web-sg"
  description = "Security group for web server"
  vpc_id      = data.aws_vpc.default.id

  # HTTP access from anywhere
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anywhere
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access (restrict to your IP in production)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-web-sg"
  }
}

# EC2 instance
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.web_server.id]

  user_data = templatefile("${path.module}/user-data.sh", {
    bucket_name = aws_s3_bucket.content.id
    aws_region  = var.aws_region
  })

  user_data_replace_on_change = true

  tags = {
    Name        = "${var.app_name}-web-server"
    Environment = var.environment
  }

  # Ensure IAM role is created first
  depends_on = [
    aws_iam_role_policy.ec2_s3_policy,
    aws_s3_object.message,
    aws_s3_object.config
  ]
}