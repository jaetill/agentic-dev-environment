# State backend per ADR-0007 — S3 + DynamoDB lock table
# State key pattern: <project>/<env>/terraform.tfstate

terraform {
  required_version = ">= 1.6"
  backend "s3" {
    bucket         = "{{account_prefix}}-tfstate-{{aws_account_id}}"
    key            = "{{project_name}}/dev/terraform.tfstate"
    region         = "{{aws_region}}"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
