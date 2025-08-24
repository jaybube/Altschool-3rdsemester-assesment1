variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

# The single variable to create a valid bucket name
variable "bucket_name_prefix" {
  description = "A unique prefix for S3 bucket names to ensure global uniqueness."
  type        = string
  default     = "yogi-s3-2025" 
}