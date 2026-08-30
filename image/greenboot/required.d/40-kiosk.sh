#!/bin/bash
# Friday Linux — SPEC.md §11.2 check 4: friday-kiosk.service active and
# cage has an output. The "cage has an output" half is UNVERIFIED — no
# confirmed command from this sandbox for checking a Wayland compositor's
# output state from outside it; loginctl session state is the best
# candidate pending a real check on hardware (see docs/VERIFY.md).
set -euo pipefail

if ! systemctl is-active --quiet friday-kiosk.service; then
    echo "friday-greenboot: friday-kiosk.service not active" >&2
    systemctl status friday-kiosk.service --no-pager || true
    exit 1
fi

# UNVERIFIED: placeholder for an actual cage-output check.
if ! loginctl show-session self -p State 2>/dev/null | grep -q "State=active"; then
    echo "friday-greenboot: no active login session for the kiosk" >&2
    exit 1
fi

echo "friday-greenboot: kiosk OK"
exit 0
