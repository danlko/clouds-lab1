#!/usr/bin/env bash
# Запуск навантажувального тесту однією командою:
#   DEMO_EMAIL=... DEMO_PASSWORD='...' ./loadtest/run.sh
# Змінні: BASE_URL (за замовчуванням — terraform output app_url), TOKEN (інакше отримується з Cognito),
#         VUS, THINK, LABEL, WRITE_MODE (sync|async), RAMP_UP, STEADY, RAMP_DOWN. Використовує k6, якщо встановлено, інакше Docker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_URL="${BASE_URL:-$(terraform -chdir=infra output -raw app_url)}"
if [[ -z "${TOKEN:-}" ]]; then
  if [[ "$BASE_URL" == *localhost* || "$BASE_URL" == *127.0.0.1* ]]; then
    TOKEN="local"   # локально AUTH_ENABLED=false
  else
    TOKEN="$(./scripts/get_token.sh)"   # access token Cognito живе 60 хв — вистачає на прогін
  fi
fi

mkdir -p loadtest/results
ARGS=(-e BASE_URL="$BASE_URL" -e TOKEN="$TOKEN"
      -e VUS="${VUS:-60}" -e WRITE_MODE="${WRITE_MODE:-sync}" -e THINK="${THINK:-0.3}" -e LABEL="${LABEL:-run}"
      -e RAMP_UP="${RAMP_UP:-3m}" -e STEADY="${STEADY:-5m}" -e RAMP_DOWN="${RAMP_DOWN:-2m}")

echo "Target: $BASE_URL  VUS=${VUS:-60}  LABEL=${LABEL:-run}  start: $(date -u +%H:%M:%S) UTC"
if command -v k6 >/dev/null; then
  cd loadtest && exec k6 run "${ARGS[@]}" script.js
else
  exec docker run --rm -i --network host --user "$(id -u):$(id -g)" \
    -v "$ROOT/loadtest:/loadtest" -w /loadtest "${K6_IMAGE:-grafana/k6:1.0.0}" run "${ARGS[@]}" script.js
fi
