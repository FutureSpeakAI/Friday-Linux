#!/bin/sh
# Friday Linux — see friday-boot-test-probe.service's header for full context.
# This used to be inlined into that unit's ExecStart=/bin/sh -c '...' — moved
# to a real file after CI run 33474200410 showed systemd's own unit-file
# parser rejecting the whole unit ("Unbalanced quoting, ignoring" / "Unit
# configuration has fatal error, unit will not be started") the moment the
# inline script grew a python -c "..." block containing single quotes.
# systemd's ExecStart= parsing does its own naive quote-balance scan across
# the raw line — it does not understand bash's nested-quote semantics — so
# any new single quote inside an already single-quoted ExecStart argument
# can silently disable the entire unit, including checks that used to work.
# A real script file has no such fragility: ExecStart=<path> is one bare
# word, no quoting to balance, ever again.
set -e

echo "FRIDAY-BOOT-TEST-PROBE-BEGIN"

echo "--- /var/log/friday-firstboot.log (real, unexplained: journalctl -u friday-firstboot has come up empty here even right after a provably successful run — docs/DECISIONS.md) ---"
cat /var/log/friday-firstboot.log 2>&1 || true

echo "--- journalctl -u friday-firstboot.service (full, explicit suffix) ---"
journalctl -u friday-firstboot.service --no-pager 2>&1 || true

echo "--- journalctl -t wizard.py (by syslog identifier instead of unit) ---"
journalctl -t wizard.py --no-pager 2>&1 || true

echo "--- journalctl -u friday.service (last 100 lines) ---"
journalctl -u friday.service --no-pager -n 100 2>&1 || true

echo "--- B5 regression: on-disk state of the app-level setup marker ---"
ls -la /home/friday/.friday/ 2>&1 || true

echo "--- marker content ---"
cat /home/friday/.friday/.setup_complete 2>&1 || true

echo "--- findmnt /home/friday (is the @home lockbox subvolume actually mounted here?) ---"
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /home/friday 2>&1 || echo "not a separate mountpoint"

echo "--- what cli.py actually sees for FRIDAY_HOME / friday_home() / SETUP_MARKER.exists() ---"
(
  set -a
  . /etc/friday/os.env
  if [ -f /var/lib/friday/secrets.env ]; then . /var/lib/friday/secrets.env; fi
  set +a
  runuser -u friday -- /usr/lib/friday/venv/bin/python3 -c "
import os
from pathlib import Path
print('FRIDAY_HOME env =', repr(os.environ.get('FRIDAY_HOME')))
print('Path.home() =', Path.home())
from agent_friday.paths import friday_home
fh = friday_home()
print('friday_home() =', fh)
marker = fh / '.setup_complete'
print('marker path =', marker, 'exists =', marker.exists())
import agent_friday.cli as cli
print('cli.FRIDAY_DIR =', cli.FRIDAY_DIR)
print('cli.SETUP_MARKER =', cli.SETUP_MARKER, 'exists =', cli.SETUP_MARKER.exists())
print('_is_existing_user() =', cli._is_existing_user())
"
) 2>&1 || true

echo "--- systemctl status friday.service (read-only; not stopping it -- the"
echo "--- earlier direct-invocation bypass (systemctl stop + run the binary"
echo "--- manually) served its purpose finding the real EOFError crash and"
echo "--- FRIDAY_HOME root cause (docs/DECISIONS.md Deviation D-A21) and is"
echo "--- removed now: stopping friday.service here would make the real"
echo "--- /api/health check fail for a self-inflicted reason, defeating the"
echo "--- whole point of re-verifying the fix end to end. ---"
systemctl status friday.service --no-pager -n 30 2>&1 || true

echo "--- systemctl list-units --failed ---"
systemctl list-units --failed --no-pager 2>&1 || true

echo "--- bootc status ---"
bootc status --json 2>&1 || true

echo "--- /usr write test ---"
if touch /usr/.friday-boot-test-writeprobe 2>/tmp/usr-write.err; then
  echo "USR_WRITABLE=yes (unexpected — /usr should be read-only)"
  rm -f /usr/.friday-boot-test-writeprobe
else
  echo "USR_WRITABLE=no ($(cat /tmp/usr-write.err))"
fi

echo "--- findmnt /usr ---"
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /usr 2>&1 || true

echo "--- findmnt /boot/efi ---"
findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS /boot/efi 2>&1 || true

echo "--- lockbox subvolumes (btrfs subvolume list) ---"
btrfs subvolume list /friday/lockbox 2>&1 || true

echo "--- lsblk ---"
lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINT 2>&1 || true

echo "FRIDAY-BOOT-TEST-PROBE-END"
