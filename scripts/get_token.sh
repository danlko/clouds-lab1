#!/usr/bin/env bash
set -euo pipefail

# Якщо змінні не задано — беремо тестового користувача з локального infra/terraform.tfvars (він у .gitignore)
TFVARS="$(dirname "$0")/../infra/terraform.tfvars"
if [[ -z "${DEMO_EMAIL:-}" && -f "$TFVARS" ]]; then
  DEMO_EMAIL=$(sed -nE 's/^demo_user_email *= *"(.*)"/\1/p' "$TFVARS")
fi
if [[ -z "${DEMO_PASSWORD:-}" && -f "$TFVARS" ]]; then
  DEMO_PASSWORD=$(sed -nE 's/^demo_user_password *= *"(.*)"/\1/p' "$TFVARS")
fi
: "${DEMO_EMAIL:?set DEMO_EMAIL}" "${DEMO_PASSWORD:?set DEMO_PASSWORD}"

CLIENT_ID=$(terraform -chdir=infra output -raw cognito_client_id)
REGION=$(terraform -chdir=infra output -raw region)

aws cognito-idp initiate-auth \
  --region "$REGION" \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "$CLIENT_ID" \
  --auth-parameters "USERNAME=$DEMO_EMAIL,PASSWORD=$DEMO_PASSWORD" \
  --query 'AuthenticationResult.AccessToken' \
  --output text
