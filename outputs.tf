data "aws_caller_identity" "current" {}

output "cloudlaunch_site_bucket_website_endpoint" {
  description = "The URL of the static website hosted on S3."
  value = aws_s3_bucket_website_configuration.site_bucket_website_config.website_endpoint
}
output "cloudlaunch_user_login_url" {
  description = "The AWS Console login URL for the cloudlaunch-user."
  value = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}
output "cloudlaunch_user_name" {
  description = "The name of the IAM user created."
  value = aws_iam_user.cloudlaunch_user.name
}


