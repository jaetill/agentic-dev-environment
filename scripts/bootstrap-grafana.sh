#!/usr/bin/env bash
# bootstrap-grafana.sh — Set up Grafana Cloud cross-account access to AWS.
#
# Per ADR-0009 §5 — one-time per AWS account. Creates the IAM role Grafana Cloud
# assumes to query CloudWatch + X-Ray + AWS billing.
#
# Usage:
#   ./bootstrap-grafana.sh --grafana-org=<org-id> [--region=<region>]
#
# Requires:
#   - AWS CLI authenticated to the target account
#   - Grafana Cloud account already created
#   - Grafana org ID (find it in Grafana Cloud account portal)

set -euo pipefail

GRAFANA_ORG=""
AWS_REGION="${AWS_REGION:-us-east-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --grafana-org=*)  GRAFANA_ORG="${1#*=}" ;;
    --region=*)       AWS_REGION="${1#*=}" ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# //'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2 ;;
  esac
  shift
done

[[ -n "$GRAFANA_ORG" ]] || { echo "ERROR: --grafana-org required" >&2; exit 2; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME="grafana-cloud-cross-account"
GRAFANA_AWS_ACCOUNT_ID="008923505280"   # Grafana Labs' AWS account; verify at grafana.com/docs

echo "📊 Bootstrapping Grafana Cloud cross-account access in $ACCOUNT_ID"
echo "   Role: $ROLE_NAME"
echo "   Grafana org: $GRAFANA_ORG"
echo

# ============================================================
# IAM role with trust policy
# ============================================================
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::${GRAFANA_AWS_ACCOUNT_ID}:root"},
    "Action": "sts:AssumeRole",
    "Condition": {"StringEquals": {"sts:ExternalId": "${GRAFANA_ORG}"}}
  }]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
  echo "  Role already exists; updating trust policy..."
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY"
else
  echo "  Creating role..."
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY"
fi

# ============================================================
# Read-only policy for CloudWatch + X-Ray + Cost Explorer
# ============================================================
echo "Attaching read-only policies..."
for policy_arn in \
  arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess \
  arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess \
  arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess; do
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" 2>/dev/null || true
done

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# ============================================================
# Done
# ============================================================
echo
echo "✅ Bootstrap complete."
echo
echo "Configure data sources in Grafana Cloud with:"
echo "  Role ARN:    $ROLE_ARN"
echo "  External ID: $GRAFANA_ORG"
echo "  Region:      $AWS_REGION"
echo
echo "In Grafana Cloud UI: Connections → Data sources → Add CloudWatch / AWS X-Ray data source."
echo "Use the role ARN above; Grafana assumes it via STS."
