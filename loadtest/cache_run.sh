#!/usr/bin/env bash
set -euo pipefail
MODE="${1:?usage: cache_run.sh on|off}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export BASE_URL="${BASE_URL:-$(terraform -chdir=infra output -raw app_url)}"
if [[ -z "${TOKEN:-}" ]]; then
  if [[ "$BASE_URL" == *localhost* ]]; then TOKEN=local; else TOKEN="$(./scripts/get_token.sh)"; fi
fi
export TOKEN
[[ "$MODE" == on ]] && ENABLED=true || ENABLED=false

curl -sf -X PUT "$BASE_URL/admin/cache?enabled=$ENABLED&reset_stats=true" -H "Authorization: Bearer $TOKEN" >/dev/null
sleep 6

mkdir -p loadtest/results
curl -sf "$BASE_URL/cache/stats" > "loadtest/results/cache-$MODE-before.json"
LABEL="cache-$MODE" ./loadtest/run.sh || true
curl -sf "$BASE_URL/cache/stats" > "loadtest/results/cache-$MODE-after.json"

python3 - "$MODE" <<'PY'
import json, sys
mode = sys.argv[1]
b = json.load(open(f"loadtest/results/cache-{mode}-before.json"))
a = json.load(open(f"loadtest/results/cache-{mode}-after.json"))
print(f"\n=== cache {mode}: навантаження на БД за прогін ===")
for k in ("xact_commit", "tup_returned", "tup_fetched"):
    print(f"{k:>13}: +{a['db'][k] - b['db'][k]}")
c = a["cache"]
print(f"cache hits/misses: {c.get('hits')}/{c.get('misses')}  hit_ratio={c.get('hit_ratio')}")
PY
