#!/usr/bin/env python3
"""Friday Linux first-boot wizard — SPEC.md §7.3.

M0 SCOPE ONLY (SPEC.md §15): this implements step 4 (create the lockbox)
driven by an unattended file (§7.6), and nothing else. Steps 1-3 and 5-9
are not implemented here; M1 replaces this with the full wizard.

This is the real implementation (2026-08-30 execution pass), not the
earlier NotImplementedError stub — see docs/DECISIONS.md for what was
resolved to get here (python3-pyyaml added to the Containerfile so this
script, which runs before friday.service and therefore before the app
venv exists, has a YAML parser of its own; sgdisk added for scriptable
partitioning; the friday Linux user, previously missing entirely, now
created in the Containerfile).

Still UNVERIFIED from this sandbox, recorded rather than guessed away:
- The exact ESP mount path (assumed /boot/efi — standard GRUB2-EFI
  convention on Fedora, checked by the CI boot test's console probe).
- Whether `findmnt -no SOURCE /sysroot` is the right way to find the real
  root PARTITION on this bootc/ostree layout, as opposed to `/` itself
  (which is a composefs/overlay mount over the ostree deployment, not the
  physical partition) — also checked by the CI boot test.
"""
from __future__ import annotations

import os
import pwd
import secrets
import subprocess
import sys
import time
from pathlib import Path

import yaml

FIRSTBOOT_DONE = Path("/var/lib/friday/.firstboot-done")
PROVISIONED_MARKER = Path("/var/lib/friday/.provisioned-unattended")
SECRETS_ENV = Path("/var/lib/friday/secrets.env")

# Real, unexplained anomaly (CI runs 33370623731 and its predecessor):
# `journalctl -u friday-firstboot` reports "-- No entries --" even
# immediately after this script has provably run (lockbox created,
# subvolumes made, /friday/lockbox mounted — all independently confirmed
# by other commands in the same probe capture). Not chased to a root
# cause — worked around instead: every _log() call also appends to a
# plain file, which cannot be affected by whatever is making the
# journal query come up empty for this unit.
FIRSTBOOT_LOG = Path("/var/log/friday-firstboot.log")

# UNVERIFIED (SPEC.md §7.6; the exact mount path Fedora/bootc uses for the
# ESP at runtime is not confirmed from this sandbox — standard GRUB2-EFI
# convention, checked by the CI boot test's console probe).
ESP_MOUNT = Path("/boot/efi")
UNATTENDED_FILE = ESP_MOUNT / "friday-unattended.yaml"

# SPEC.md §5.
LOCKBOX_DEVMAPPER_NAME = "friday-lockbox"
LOCKBOX_DEVMAPPER_PATH = Path(f"/dev/mapper/{LOCKBOX_DEVMAPPER_NAME}")
# SPEC.md's friday.service text names this unit "friday-lockbox.mount"
# verbatim; systemd's own naming rule (confirmed the hard way — see that
# unit file's header, CI run 33340378275) means the only Where= value
# that literal name can validly have is /friday/lockbox, not
# /run/friday-lockbox as originally drafted.
LOCKBOX_RUN_MOUNT = Path("/friday/lockbox")
SUBVOLUMES = ("@home", "@models", "@workshop", "@journal", "@snapshots")

# (subvolume, mountpoint, extra mount options beyond "subvol=<name>,noatime")
SUBVOLUME_MOUNTS = (
    ("@home", Path("/home/friday"), "compress=zstd:1"),
    ("@models", Path("/var/lib/friday/models"), None),
    ("@workshop", Path("/var/lib/friday/workshop"), "compress=zstd:1"),
    ("@journal", Path("/var/log/journal"), None),
)


def _log(msg: str) -> None:
    line = f"[firstboot] {msg}"
    print(line, flush=True)
    try:
        FIRSTBOOT_LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(FIRSTBOOT_LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass  # the journal is still the primary record; this is a backup


def _run(cmd: list[str], *, input_bytes: bytes | None = None, check: bool = True) -> subprocess.CompletedProcess:
    """Every prior version of this function used capture_output=True and
    never printed the captured stdout/stderr anywhere — meaning every
    command failure so far (e.g. CI run 33343357304's `sgdisk` exit status
    4) has been diagnosed blind: the journal only ever showed the raised
    CalledProcessError's own repr (command + return code), never the
    tool's own error message explaining WHY. friday-firstboot.service's
    stdout/stderr already go to the journal (systemd's default), and
    friday-boot-test-probe.service already dumps that journal to the
    console — so printing the captured output here, always, is enough to
    make it visible without changing anything else.
    """
    _log(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, input=input_bytes, check=False,
                             capture_output=True, text=False)
    for stream_name, data in (("stdout", result.stdout), ("stderr", result.stderr)):
        if data:
            text = data.decode("utf-8", errors="replace").rstrip()
            if text:
                _log(f"  {stream_name}: {text}")
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, cmd, result.stdout, result.stderr)
    return result


def load_unattended() -> dict:
    if not UNATTENDED_FILE.exists():
        _log(f"no unattended file at {UNATTENDED_FILE}; M0 stub has no "
             "interactive path — exiting for a human to run the real "
             "wizard once it exists (M1).")
        sys.exit(1)
    with open(UNATTENDED_FILE, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        _log(f"{UNATTENDED_FILE} did not parse to a mapping — got {type(data)!r}")
        sys.exit(1)
    return data


def mark_provisioned() -> None:
    PROVISIONED_MARKER.parent.mkdir(parents=True, exist_ok=True)
    PROVISIONED_MARKER.write_text("unattended\n", encoding="utf-8")


def find_root_disk() -> str:
    """SPEC.md §5/ADR-004: the lockbox claims free space on 'the boot
    device'. On an ostree/bootc system, `/` is a composefs/overlay mount
    over the deployment, not the physical partition — the real backing
    partition is whatever is mounted at /sysroot. Falls back to `/` for
    any non-ostree layout (e.g. testing this script outside a real image).
    """
    for target in ("/sysroot", "/"):
        out = _run(["findmnt", "-no", "SOURCE", target], check=False)
        src = out.stdout.decode().strip()
        if src and src.startswith("/dev/"):
            pk = _run(["lsblk", "-no", "PKNAME", src], check=False).stdout.decode().strip()
            if pk:
                _log(f"root device resolved via {target} ({src}) -> parent disk /dev/{pk}")
                return f"/dev/{pk}"
    raise RuntimeError("could not resolve the root disk from /sysroot or / — "
                        "see wizard.py:find_root_disk")


def partition_suffix(disk: str) -> str:
    """'p' for devices whose base name ends in a digit (nvme0n1, loop0,
    mmcblk0), '' otherwise (sda, vda)."""
    name = disk.rsplit("/", 1)[-1]
    return "p" if name and name[-1].isdigit() else ""


def create_lockbox_partition(disk: str) -> str:
    """Creates a new GPT partition spanning all remaining free space on
    `disk` (SPEC.md §5, ADR-004). Returns the new partition's device path.

    UNVERIFIED (docs/VERIFY.md): `sgdisk -n 0:0:0` (next available
    partition number, default-aligned first free sector, rest of the disk)
    is standard, long-documented sgdisk usage — used with more confidence
    than a guessed flag, but still not run against this exact disk layout
    before the CI boot test. `-t 0:8309` ("Linux LUKS" GPT type GUID
    shorthand) is cosmetic only: /etc/crypttab below references the
    partition by UUID, not by type-GUID auto-discovery, so a wrong type
    code does not break functionality, only `gdisk -l`'s own labelling.
    """
    # DIAGNOSTIC (CI run 33346716623): sgdisk -n 0:0:0 failed with
    # "Could not create partition 5 from 0 to 2047" — meaning sgdisk
    # believed the LARGEST free block was sectors 0-2047 (1 MiB), not the
    # multi-GiB block after the last real partition that the host-side
    # "Grow the disk" CI step's own sgdisk -p confirmed exists on this
    # same file before boot. Logging the guest's own view of the disk
    # before attempting -n, rather than guessing further, since the two
    # views disagree and only one of them is visible so far.
    _run(["blockdev", "--getsize64", disk], check=False)
    _run(["sgdisk", "-p", disk], check=False)
    # REAL BUG, CI run 33361356886: plain `lsblk -no NAME` uses tree-view
    # glyphs (├─, └─) by default whenever a device has children, e.g.
    # "├─vda1" / "└─vda4" — NOT separated from the device name by
    # whitespace, so `.split()` on the output kept the glyphs glued to the
    # name. Adding a fifth partition changes which existing entries are
    # "last" in the tree (└─ vs ├─), so `after - before` picked up the
    # glyph-mangled "├─vda4" as a "new" entry alongside the real "vda5" —
    # and `sorted(...)[-1]` chose the mangled one. `-l`/`--list` forces
    # plain list output with no tree formatting at all.
    before = set(_run(["lsblk", "-l", "-no", "NAME", disk]).stdout.decode().split())
    _run(["sgdisk", "-n", "0:0:0", "-t", "0:8309", "-c", "0:friday-lockbox", disk])
    _run(["udevadm", "settle"])
    after = set(_run(["lsblk", "-l", "-no", "NAME", disk]).stdout.decode().split())
    new_names = sorted(after - before)
    if not new_names:
        # udev can lag; give it one more chance before giving up.
        time.sleep(2)
        _run(["udevadm", "settle"])
        after = set(_run(["lsblk", "-l", "-no", "NAME", disk]).stdout.decode().split())
        new_names = sorted(after - before)
    if not new_names:
        raise RuntimeError(f"sgdisk reported success but no new block device appeared under {disk}")
    return f"/dev/{new_names[-1]}"


def create_lockbox(partition: str, passphrase: str) -> None:
    """SPEC.md §5, §7.3 step 4: LUKS2 + Argon2id, btrfs, five subvolumes.

    UNVERIFIED (docs/VERIFY.md): the exact `--pbkdf-memory`/
    `--pbkdf-force-iterations` argument syntax for "Argon2id, 2 GiB memory
    cost, 4 iterations minimum" against the cryptsetup build this base
    image ships — best-effort standard cryptsetup 2.x flag names, checked
    for real by the CI boot test.
    """
    pw = passphrase.encode("utf-8")

    _log(f"luksFormat {partition} (LUKS2, argon2id, 2 GiB memory, 4 iterations)")
    _run([
        "cryptsetup", "--batch-mode", "luksFormat", "--type", "luks2",
        "--pbkdf", "argon2id",
        "--pbkdf-memory", str(2 * 1024 * 1024),  # KiB -> 2 GiB
        "--pbkdf-force-iterations", "4",
        "--key-file", "-",
        partition,
    ], input_bytes=pw)

    _log(f"luksOpen {partition} -> {LOCKBOX_DEVMAPPER_PATH}")
    _run(["cryptsetup", "open", "--key-file", "-", partition, LOCKBOX_DEVMAPPER_NAME],
         input_bytes=pw)

    _log(f"mkfs.btrfs on {LOCKBOX_DEVMAPPER_PATH}")
    _run(["mkfs.btrfs", "-f", "-L", "friday-lockbox", str(LOCKBOX_DEVMAPPER_PATH)])

    uuid = _run(["cryptsetup", "luksUUID", partition]).stdout.decode().strip()
    if not uuid:
        raise RuntimeError(f"cryptsetup luksUUID returned nothing for {partition}")
    write_crypttab(uuid)

    _run(["systemctl", "daemon-reload"])
    _run(["systemctl", "start", "friday-lockbox.mount"])

    for sv in SUBVOLUMES:
        _log(f"btrfs subvolume create {LOCKBOX_RUN_MOUNT / sv}")
        _run(["btrfs", "subvolume", "create", str(LOCKBOX_RUN_MOUNT / sv)])

    write_subvolume_mount_units()
    _run(["systemctl", "daemon-reload"])
    # One at a time with check=False (real bug, CI run 33365778055):
    # `systemctl enable --now unit1 unit2 unit3 unit4` in one call means
    # one bad unit fails the whole call, which used to raise (check=True
    # default) and crash the wizard before it could write secrets.env /
    # the .firstboot-done marker / start friday.service at all. Per-unit
    # + check=False means one mount's own failure doesn't take out the
    # other three or abort the rest of first boot; a diagnostic dump of
    # the failing unit's own journal follows immediately so the real
    # error is visible without a second guess.
    for _, mountpoint, _ in SUBVOLUME_MOUNTS:
        unit = unit_name_for(mountpoint)
        result = _run(["systemctl", "enable", "--now", unit], check=False)
        if result.returncode != 0:
            _log(f"{unit} failed to start — dumping its journal:")
            _run(["journalctl", "-u", unit, "--no-pager", "-n", "50"], check=False)

    friday_uid = pwd.getpwnam("friday").pw_uid
    friday_gid = pwd.getpwnam("friday").pw_gid
    os.chown("/home/friday", friday_uid, friday_gid)
    for root, dirs, files in os.walk("/home/friday"):
        for d in dirs:
            os.chown(os.path.join(root, d), friday_uid, friday_gid)
        for f in files:
            os.chown(os.path.join(root, f), friday_uid, friday_gid)


def write_crypttab(uuid: str) -> None:
    entry = f"{LOCKBOX_DEVMAPPER_NAME}\tUUID={uuid}\tnone\tluks\n"
    crypttab = Path("/etc/crypttab")
    existing = crypttab.read_text(encoding="utf-8") if crypttab.exists() else ""
    if LOCKBOX_DEVMAPPER_NAME in existing:
        _log("/etc/crypttab already has a friday-lockbox entry, not duplicating")
        return
    _log(f"writing /etc/crypttab: {entry.strip()}")
    with open(crypttab, "a", encoding="utf-8") as f:
        f.write(entry)


def unit_name_for(mountpoint: Path) -> str:
    """systemd .mount unit filenames must equal the escaped mountpoint
    (e.g. /home/friday -> home-friday.mount)."""
    parts = [p for p in str(mountpoint).split("/") if p]
    return "-".join(parts) + ".mount"


def write_subvolume_mount_units() -> None:
    for sv, mountpoint, extra_opts in SUBVOLUME_MOUNTS:
        mountpoint.mkdir(parents=True, exist_ok=True)
        opts = f"subvol={sv},noatime"
        if extra_opts:
            opts += f",{extra_opts}"
        unit_path = Path("/etc/systemd/system") / unit_name_for(mountpoint)
        unit_text = (
            "# Written by image/firstboot/wizard.py at first boot — SPEC.md §5, §7.3 step 4.\n"
            "# friday-lockbox.mount's own header explains why this is generated here rather\n"
            "# than baked into the image: the lockbox does not exist until first boot.\n"
            "[Unit]\n"
            f"Description=Friday lockbox subvolume {sv} -> {mountpoint}\n"
            "BindsTo=friday-lockbox.mount\n"
            "After=friday-lockbox.mount\n"
            f"RequiresMountsFor={LOCKBOX_RUN_MOUNT}\n"
            "\n"
            "[Mount]\n"
            f"What={LOCKBOX_DEVMAPPER_PATH}\n"
            f"Where={mountpoint}\n"
            "Type=btrfs\n"
            f"Options={opts}\n"
            "\n"
            "[Install]\n"
            "WantedBy=multi-user.target\n"
        )
        _log(f"writing {unit_path}")
        unit_path.write_text(unit_text, encoding="utf-8")


def write_secrets_env() -> None:
    """SPEC.md §8.1: /var/lib/friday/secrets.env, mode 0600, owner friday,
    FRIDAY_PASSWORD and FRIDAY_SECRET_KEY generated with 256 bits of
    entropy each. Per Amendment A1, this file supplies FRIDAY_PASSWORD
    directly until PR-2 lands.

    CHALLENGE recorded in docs/DECISIONS.md, not silently resolved: §8.1
    calls this file "(lockbox...)" but its path, /var/lib/friday/
    secrets.env, is not on any of SPEC.md §5's five lockbox subvolumes —
    only /var/lib/friday/models and /var/lib/friday/workshop are. As
    written here it lives on the sealed OS's own persistent /var (ostree
    does not wipe /var between deployments, so it survives updates, but it
    is protected only by the root filesystem, not lockbox encryption) —
    a real gap against §8.1's stated security property, not something
    this executor can resolve unilaterally (extending the mount plan is a
    SPEC.md §5 change).
    """
    SECRETS_ENV.parent.mkdir(parents=True, exist_ok=True)
    if SECRETS_ENV.exists():
        _log(f"{SECRETS_ENV} already exists, not overwriting")
        return
    password = secrets.token_urlsafe(32)
    secret_key = secrets.token_urlsafe(32)
    _log(f"writing {SECRETS_ENV} (FRIDAY_PASSWORD, FRIDAY_SECRET_KEY, mode 0600)")
    SECRETS_ENV.write_text(
        f"FRIDAY_PASSWORD={password}\nFRIDAY_SECRET_KEY={secret_key}\n",
        encoding="utf-8",
    )
    os.chmod(SECRETS_ENV, 0o600)
    uid = pwd.getpwnam("friday").pw_uid
    gid = pwd.getpwnam("friday").pw_gid
    os.chown(SECRETS_ENV, uid, gid)


def seed_app_setup_marker() -> None:
    """Agent-Friday's own cmd_start() (src/agent_friday/cli.py at the
    pinned tag, checked directly against the real friday-desktop checkout,
    not guessed) calls Confirm.ask() interactively on first run unless
    ~/.friday/.setup_complete already exists. There is no tty attached to
    friday.service to answer that prompt. This is purely an Amendment-A1
    workaround (PR-2/PR-7, which would make the app itself OS-mode-aware,
    have not landed) — recorded in docs/DECISIONS.md, not a permanent
    fixture: it goes away once PR-7's `/api/setup/os-handoff` exists.
    """
    friday_dir = Path("/home/friday/.friday")
    friday_dir.mkdir(parents=True, exist_ok=True)
    marker = friday_dir / ".setup_complete"
    if not marker.exists():
        marker.write_text("friday-linux-os-wizard\n", encoding="utf-8")
    uid = pwd.getpwnam("friday").pw_uid
    gid = pwd.getpwnam("friday").pw_gid
    os.chown(friday_dir, uid, gid)
    os.chown(marker, uid, gid)


def _diagnose_partition_growth() -> None:
    """CI run 33350200049 found partition 4 (root) silently grown from the
    disk.toml-specified 16 GiB to fill the entire disk before this wizard
    ever ran. CI run 33353739418 root-caused it for real:
    `bootc-generic-growpart.service - Bootc Fallback Root Filesystem Grow`
    started successfully at boot (`bootc install to-filesystem
    --generic-image`, which `bootc-image-builder` invokes internally,
    installs this fallback unit so a generic image fills whatever disk it
    lands on — the opposite of what SPEC.md §5/ADR-004 want for Friday
    Linux specifically). `systemd-repart.service` was independently ruled
    out (its own log: "skipped, no trigger condition checks were met" —
    no /usr/lib/repart.d config exists). Fixed in the Containerfile:
    `systemctl mask bootc-generic-growpart.service`. This check confirms
    the mask actually holds at every boot, rather than trusting it
    silently — a masked unit should report "masked" here, never
    "started"/"success".
    """
    _run(["systemctl", "is-enabled", "bootc-generic-growpart.service"], check=False)


def main() -> int:
    if FIRSTBOOT_DONE.exists():
        _log("already done (FIRSTBOOT_DONE marker present) — nothing to do")
        return 0

    _diagnose_partition_growth()

    data = load_unattended()
    mark_provisioned()

    lockbox_cfg = data.get("lockbox") or {}
    passphrase = lockbox_cfg.get("passphrase")
    if not passphrase:
        _log("friday-unattended.yaml has no lockbox.passphrase — M0 stub "
             "only supports a literal passphrase, not the 'generate' flag "
             "(SPEC.md §7.3 step 4, Q1) yet")
        return 1

    if not LOCKBOX_DEVMAPPER_PATH.exists():
        disk = find_root_disk()
        _log(f"boot disk: {disk}")
        partition = create_lockbox_partition(disk)
        _log(f"new lockbox partition: {partition}")
        create_lockbox(partition, passphrase)
    else:
        _log(f"{LOCKBOX_DEVMAPPER_PATH} already open — assuming lockbox already created")

    write_secrets_env()
    seed_app_setup_marker()

    FIRSTBOOT_DONE.parent.mkdir(parents=True, exist_ok=True)
    FIRSTBOOT_DONE.write_text("done\n", encoding="utf-8")
    _log(f"wrote {FIRSTBOOT_DONE} — friday.service may now start")

    # Real bug, found via CI run 33357468619's console log: friday.service
    # is WantedBy=multi-user.target, so systemd attempts to start it early
    # in boot as part of reaching that target — long before this wizard
    # has created the lockbox. That attempt fails
    # ("Dependency failed for friday.service", since
    # Requires=friday-lockbox.mount can't be satisfied yet) and systemd
    # does NOT automatically retry a unit whose job already failed once
    # its dependency later becomes available — ConditionPathExists is
    # evaluated once per start attempt, not watched continuously. Without
    # an explicit re-trigger here, friday.service would simply never start
    # on this boot even after everything it needs now exists.
    _run(["systemctl", "start", "friday.service"], check=False)

    # SPEC.md §7.6: "The file is deleted from the ESP after use."
    try:
        UNATTENDED_FILE.unlink()
        _log(f"deleted {UNATTENDED_FILE} per SPEC.md §7.6")
    except OSError as exc:
        _log(f"could not delete {UNATTENDED_FILE}: {exc} (non-fatal)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
