terraform {
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

# --- TASK 1: S3 BUCKETS AND IAM USER ---

# Public S3 bucket for the static website
resource "aws_s3_bucket" "site_bucket" {
  bucket = "${var.bucket_name_prefix}-site"
}

# Block public access to the bucket by default
resource "aws_s3_bucket_public_access_block" "site_bucket_public_access" {
  bucket                  = aws_s3_bucket.site_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable static website hosting on the bucket
resource "aws_s3_bucket_website_configuration" "site_bucket_website_config" {
  bucket = aws_s3_bucket.site_bucket.id
  index_document {
    suffix = "index.html"
  }
}

# Set a bucket policy to allow public read access
resource "aws_s3_bucket_policy" "site_bucket_policy" {
  bucket = aws_s3_bucket.site_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site_bucket.arn}/*"
      }
    ]
  })
}

# Upload the website content
resource "aws_s3_object" "index_html" { # <-- Corrected resource name
  bucket       = aws_s3_bucket.site_bucket.id
  key          = "index.html"
  source       = "website_content/index.html"
  content_type = "text/html"
}

# S3 Bucket for private documents
resource "aws_s3_bucket" "private_bucket" {
  bucket = "${var.bucket_name_prefix}-private"
}


# S3 Bucket for visible-only access
resource "aws_s3_bucket" "visible_only_bucket" {
  bucket = "${var.bucket_name_prefix}-visible"
}


# Create the IAM user
resource "aws_iam_user" "cloudlaunch_user" {
  name = "${var.bucket_name_prefix}-user"
}

# Create a login profile and enforce password change on first login
resource "aws_iam_user_login_profile" "cloudlaunch_user_login" {
  user                    = aws_iam_user.cloudlaunch_user.name
  password_reset_required = true
  # The password will be generated automatically by Terraform
}

# Define the IAM policy document
data "aws_iam_policy_document" "cloudlaunch_user_policy_doc" {
  statement {
    sid = "ListAllCloudLaunchBuckets"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.site_bucket.arn,
      aws_s3_bucket.private_bucket.arn,
      aws_s3_bucket.visible_only_bucket.arn
    ]
  }
  statement {
    sid = "ReadWritePrivateBucket"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.private_bucket.arn}/*"]
  }
  statement {
    sid = "ReadOnlySiteBucket"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site_bucket.arn}/*"]
  }
  statement {
    sid = "VPCReadOnlyAccess"
    actions = [
      "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups", "ec2:DescribeInternetGateways"
    ]
    resources = ["*"]
  }
}

# Attach the policy to the IAM user
resource "aws_iam_user_policy" "cloudlaunch_user_policy" {
  name   = "cloudlaunch-user-s3-policy"
  user   = aws_iam_user.cloudlaunch_user.name
  policy = data.aws_iam_policy_document.cloudlaunch_user_policy_doc.json
}

# --- TASK 2: VPC DESIGN ---

# Create the VPC
resource "aws_vpc" "cloudlaunch_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "cloudlaunch-vpc" }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.cloudlaunch_vpc.id
  cidr_block = "10.0.1.0/24"
  tags = { Name = "cloudlaunch-public-subnet" }
}
resource "aws_subnet" "app_subnet" {
  vpc_id     = aws_vpc.cloudlaunch_vpc.id
  cidr_block = "10.0.2.0/24"
  tags = { Name = "cloudlaunch-app-subnet" }
}
resource "aws_subnet" "db_subnet" {
  vpc_id     = aws_vpc.cloudlaunch_vpc.id
  cidr_block = "10.0.3.0/28"
  tags = { Name = "cloudlaunch-db-subnet" }
}

# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "cloudlaunch_igw" {
  vpc_id = aws_vpc.cloudlaunch_vpc.id
  tags = { Name = "cloudlaunch-igw" }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cloudlaunch_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudlaunch_igw.id
  }
  tags = { Name = "cloudlaunch-public-rt" }
}

# Associate public route table with the public subnet
resource "aws_route_table_association" "public_subnet_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Route Tables
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.cloudlaunch_vpc.id
  tags = { Name = "cloudlaunch-app-rt" }
}
resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.cloudlaunch_vpc.id
  tags = { Name = "cloudlaunch-db-rt" }
}
resource "aws_route_table_association" "app_subnet_rt_assoc" {
  subnet_id      = aws_subnet.app_subnet.id
  route_table_id = aws_route_table.app_rt.id
}
resource "aws_route_table_association" "db_subnet_rt_assoc" {
  subnet_id      = aws_subnet.db_subnet.id
  route_table_id = aws_route_table.db_rt.id
}

# Security Groups
resource "aws_security_group" "app_sg" {
  name        = "cloudlaunch-app-sg"
  vpc_id      = aws_vpc.cloudlaunch_vpc.id
  description = "Allows HTTP access within the VPC"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.cloudlaunch_vpc.cidr_block]
  }
}
resource "aws_security_group" "db_sg" {
  name        = "cloudlaunch-db-sg"
  vpc_id      = aws_vpc.cloudlaunch_vpc.id
  description = "Allows MySQL access from app subnet only"
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.app_sg.id]
}
}