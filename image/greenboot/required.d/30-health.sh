#!/bin/bash
# Friday Linux — SPEC.md §11.2 check 3: GET /api/health returns 200 with
# boot_critical_ok: true. Contract is defined by Agent-Friday PR-6
# (SPEC.md §13); this script only consumes it and does not implement it.
# UNVERIFIED: whether `jq` is present in the base image (docs/VERIFY.md
# does not yet list it — add it there if not already installed by §6).
set -euo pipefail

HEALTH_URL="http://127.0.0.1:3000/api/health"

response=$(curl -fsS --max-time 5 "$HEALTH_URL") || {
    echo "friday-greenboot: $HEALTH_URL unreachable" >&2
    exit 1
}

ok=$(echo "$response" | jq -r '.boot_critical_ok // false')

if [[ "$ok" != "true" ]]; then
    echo "friday-greenboot: boot_critical_ok is not true: $response" >&2
    exit 1
fi

echo "friday-greenboot: /api/health boot_critical_ok=true"
exit 0
