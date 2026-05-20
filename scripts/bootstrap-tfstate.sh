#!/usr/bin/env bash
# bootstrap-tfstate.sh — Create the S3 bucket + DynamoDB lock table for OpenTofu state.
#
# Per ADR-0007 §3 — one-time per AWS account. Creates the chicken-and-egg dependencies
# Terraform itself can't manage. Idempotent — re-running on an existing setup is safe.
#
# Usage:
#   ./bootstrap-tfstate.sh [--account-prefix=<prefix>] [--region=<region>]
#
# Requires: AWS CLI authenticated to the target account.

set -euo pipefail

ACCOUNT_PREFIX=""
AWS_REGION="${AWS_REGION:-us-east-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-prefix=*)  ACCOUNT_PREFIX="${1#*=}" ;;
    --region=*)          AWS_REGION="${1#*=}" ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# //'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2 ;;
  esac
  shift
done

# Detect account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[[ -n "$ACCOUNT_ID" ]] || { echo "ERROR: cannot determine AWS account ID; check AWS auth" >&2; exit 3; }

# Default account prefix derived from account ID
ACCOUNT_PREFIX="${ACCOUNT_PREFIX:-tfstate-${ACCOUNT_ID}}"
BUCKET_NAME="${ACCOUNT_PREFIX}-${ACCOUNT_ID}"
TABLE_NAME="terraform-state-lock"

echo "🪣 Bootstrapping Terraform state backend in account $ACCOUNT_ID, region $AWS_REGION"
echo "   Bucket: $BUCKET_NAME"
echo "   Table:  $TABLE_NAME"
echo

# ============================================================
# S3 bucket
# ============================================================
echo "Creating S3 bucket..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "  Bucket already exists; skipping creation."
else
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi
fi

echo "Enabling bucket versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "Enabling SSE-S3 encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo "Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ============================================================
# DynamoDB lock table
# ============================================================
echo "Creating DynamoDB lock table..."
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" 2>/dev/null; then
  echo "  Table already exists; skipping creation."
else
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --region "$AWS_REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
fi

# ============================================================
# OIDC provider for GitHub Actions
# ============================================================
# Note: AWS now derives the thumbprint automatically when omitted (recent IAM behavior).
# We pass a thumbprint as a defense-in-depth fallback. Keep this updated if GitHub
# rotates its CA cert. As of 2026, the canonical value is 6938fd4d98bab03faadb97b34396831e3780aea1.
# Reference: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
echo "Creating GitHub OIDC identity provider (if not exists)..."
GITHUB_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
if aws iam list-open-id-connect-providers | grep -q "token.actions.githubusercontent.com"; then
  echo "  Provider already exists; skipping creation."
else
  aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "$GITHUB_THUMBPRINT"
fi

# ============================================================
# Done
# ============================================================
echo
echo "✅ Bootstrap complete."
echo
echo "Use these values in your projects' terraform/envs/<env>/backend.tf:"
echo "  bucket         = \"$BUCKET_NAME\""
echo "  region         = \"$AWS_REGION\""
echo "  dynamodb_table = \"$TABLE_NAME\""
echo "  encrypt        = true"
echo
echo "GitHub OIDC provider ARN (for IAM trust policies):"
echo "  arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
