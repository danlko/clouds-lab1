#!/usr/bin/env bash
# Отримати access token Cognito для тестового користувача:
#   DEMO_EMAIL=you@example.com DEMO_PASSWORD='...' ./scripts/get_token.sh
set -euo pipefail
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
