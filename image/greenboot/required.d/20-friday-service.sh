#!/bin/bash
# Friday Linux — SPEC.md §11.2 check 2: friday.service active within 300s of boot.
set -euo pipefail

DEADLINE=$(( $(date +%s) + 300 ))

while (( $(date +%s) < DEADLINE )); do
    if systemctl is-active --quiet friday.service; then
        echo "friday-greenboot: friday.service active"
        exit 0
    fi
    sleep 2
done

echo "friday-greenboot: friday.service did not become active within 300s" >&2
systemctl status friday.service --no-pager || true
exit 1
