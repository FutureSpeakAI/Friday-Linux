#!/bin/bash
# Friday Linux — SPEC.md §11.2 check 3: GET /api/health.
#
# RESTORED (B5, 2026-08-31): the real contract — 200 plus boot_critical_ok:
# true in the JSON body — is Agent-Friday PR-6 (SPEC.md §13), merged
# upstream in v5.9.0 (this repo's current build/agent-friday.pin). Amendment
# A1 deferred this to M2 and checked HTTP status alone in the meantime,
# because PR-6 did not exist at the pin then (v5.7.0) and boot_critical_ok
# was never present in the response body — parsing it with jq back then
# always yielded "false" and would have failed greenboot on every boot.
# That workaround is removed now that the field is real.
set -euo pipefail

HEALTH_URL="http://127.0.0.1:3000/api/health"

BODY="$(curl -fsS --max-time 5 "$HEALTH_URL")" || {
    echo "friday-greenboot: $HEALTH_URL did not return a 2xx status" >&2
    exit 1
}

OK="$(echo "$BODY" | jq -r '.boot_critical_ok // "missing"')"
if [ "$OK" != "true" ]; then
    echo "friday-greenboot: /api/health returned 2xx but boot_critical_ok is not true (got: ${OK})" >&2
    echo "friday-greenboot: subsystems: $(echo "$BODY" | jq -c '.subsystems // {}')" >&2
    exit 1
fi

echo "friday-greenboot: /api/health returned 2xx with boot_critical_ok: true"
exit 0
