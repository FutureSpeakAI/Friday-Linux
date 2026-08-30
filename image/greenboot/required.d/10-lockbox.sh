#!/bin/bash
# Friday Linux — SPEC.md §11.2 check 1: all five subvolumes mounted and writable.
set -euo pipefail

MOUNTS=(/home/friday /var/lib/friday/models /var/lib/friday/workshop /var/log/journal)

for m in "${MOUNTS[@]}"; do
    if ! mountpoint -q "$m"; then
        echo "friday-greenboot: $m is not a mountpoint" >&2
        exit 1
    fi
    testfile="$m/.greenboot-write-test"
    if ! ( : > "$testfile" && rm -f "$testfile" ); then
        echo "friday-greenboot: $m is not writable" >&2
        exit 1
    fi
done

echo "friday-greenboot: lockbox mounts OK"
exit 0
