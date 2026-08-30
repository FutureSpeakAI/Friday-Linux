#!/bin/bash
# Friday Linux — SPEC.md §11.2 check 3: GET /api/health.
#
# Full contract (200 + boot_critical_ok: true in the JSON body) is defined
# by Agent-Friday PR-6 (SPEC.md §13), which has not landed — per Amendment
# A1 (SPEC.md, appended 2026-08-30): "M0's boot_critical_ok gate is deferred
# to M2; greenboot 30-health.sh checks HTTP status code only until then."
# A previous pass of this script parsed `boot_critical_ok` with `jq`
# anyway, which would have failed greenboot on every boot: PR-6 doesn't
# exist at the pinned tag (v5.7.0, docs/DECISIONS.md), so that field is
# never present and `jq -r '.boot_critical_ok // false'` always yields
# "false". Fixed to match Amendment A1's own simplification. Restore the
# JSON-body check (and add `jq` to the §6 package list, which does not
# currently include it) once PR-6 actually lands and M2 planning revisits
# this file.
set -euo pipefail

HEALTH_URL="http://127.0.0.1:3000/api/health"

# curl -f treats any non-2xx response as a failure (non-zero exit), which is
# all Amendment A1 asks this check to confirm for M0 — no jq/JSON parsing
# needed.
if ! curl -fsS --max-time 5 -o /dev/null "$HEALTH_URL"; then
    echo "friday-greenboot: $HEALTH_URL did not return a 2xx status" >&2
    exit 1
fi

echo "friday-greenboot: /api/health returned 2xx (boot_critical_ok check deferred to M2 per Amendment A1)"
exit 0
