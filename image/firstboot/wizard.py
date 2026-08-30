#!/usr/bin/env python3
"""Friday Linux first-boot wizard — SPEC.md §7.3.

M0 SCOPE ONLY (SPEC.md §15): this stub implements step 4 (create the
lockbox) driven by an unattended file (§7.6), and nothing else. Steps 1-3
and 5-9 are not implemented here; M1 replaces this with the full wizard.

Even at M0 scope, this cannot be exercised end-to-end yet: friday.service
has no venv to start (see docs/DECISIONS.md, "Blocking dependency: PR-1/2/3
not yet merged upstream"), so the acceptance check in SPEC.md M0
("/api/health returns 200") cannot pass regardless of what this script
does correctly. Written and left ready for when that pin is fillable.

Unverified from this sandbox, per SPEC.md §18 rule 5: the exact ESP mount
path for friday-unattended.yaml, and the precise `cryptsetup luksFormat`
argument set for "Argon2id, 2 GiB memory cost, 4 iterations minimum"
(SPEC.md §5) as accepted by the cryptsetup version the base image ships.
Both are marked below; confirm against a real base image before trusting
this script on real hardware.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

FIRSTBOOT_DONE = Path("/var/lib/friday/.firstboot-done")

# UNVERIFIED (SPEC.md §17 mentions the ESP holds friday-unattended.yaml,
# §7.6; the exact mount path Universal Blue/bootc uses for the ESP at
# runtime is not confirmed from this sandbox).
ESP_MOUNT = Path("/boot/efi")
UNATTENDED_FILE = ESP_MOUNT / "friday-unattended.yaml"

LOCKBOX_SUBVOLUMES = ("@home", "@models", "@workshop", "@journal", "@snapshots")


def _run(cmd: list[str]) -> None:
    print(f"[firstboot] $ {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, check=True)


def load_unattended() -> dict:
    if not UNATTENDED_FILE.exists():
        print(f"[firstboot] no unattended file at {UNATTENDED_FILE}; "
              "M0 stub has no interactive path — exiting for a human to "
              "run the real wizard once it exists (M1).", file=sys.stderr)
        sys.exit(1)
    # Deliberately not parsing YAML with a third-party lib here: the app
    # venv this unit predates (PR-1/2/3 blocker above) is the only place
    # PyYAML would come from at M0. A stdlib-only stopgap parser would be
    # its own source of bugs, so this is left as an explicit TODO rather
    # than either shipping a fragile hand-rolled parser or a fabricated
    # "it works" claim.
    raise NotImplementedError(
        "YAML parsing for friday-unattended.yaml is not implemented in the "
        "M0 stub — needs a decision on whether the image ships a minimal "
        "YAML parser or whether the unattended file format changes to JSON "
        "for the stub's sake. Record the decision in docs/DECISIONS.md "
        "before implementing."
    )


def create_lockbox(device: str, passphrase: str) -> None:
    """SPEC.md §5, §7.3 step 4. UNVERIFIED argon2id parameter syntax."""
    # UNVERIFIED: whether this cryptsetup build's luksFormat accepts
    # --pbkdf-memory in KiB directly for "2 GiB" — confirm with
    # `cryptsetup luksFormat --help` on the real base image.
    _run([
        "cryptsetup", "luksFormat", "--type", "luks2",
        "--pbkdf", "argon2id",
        "--pbkdf-memory", str(2 * 1024 * 1024),  # 2 GiB in KiB
        "--pbkdf-force-iterations", "4",
        device,
    ])
    # Passphrase is piped via stdin in the real implementation, never as an
    # argv value (would leak into `ps`). Left as a TODO marker: this stub
    # does not yet wire that up because it is not exercised by any test.
    raise NotImplementedError(
        "luksOpen, mkfs.btrfs, subvolume creation, and /etc/crypttab + "
        "mount-unit generation are not implemented in the M0 stub. Fill in "
        "once docs/VERIFY.md's cryptsetup/btrfs questions are answered."
    )


def main() -> int:
    load_unattended()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
