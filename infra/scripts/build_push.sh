#!/usr/bin/env bash
set -euo pipefail
: "${REPO_URL:?}" "${REGION:?}" "${TAG:?}" "${CONTEXT:?}"

REGISTRY="${REPO_URL%%/*}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build --platform linux/amd64 -t "$REPO_URL:$TAG" "$CONTEXT"
docker push "$REPO_URL:$TAG"
