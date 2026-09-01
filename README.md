# Friday Linux

A sealed, portable, encrypted OS image that boots an x86-64 PC directly into
[Agent Friday](https://github.com/FutureSpeakAI/Agent-Friday). It is built with
[bootc](https://containers.github.io/bootc/) on a Universal Blue / Fedora base:
the OS ships as a container image, updates atomically, and rolls back
automatically when a boot fails.

The design goal is that all user state lives on a LUKS2-encrypted partition
created at first boot, the host's own disks are never written to, and the same
USB-attached SSD re-profiles itself to whatever GPU it wakes up on.

---

## ⚠️ Project status: early. Do not run this on hardware you care about.

**This repository is at milestone M0 of five (M0–M4).** Read that literally:

**M0 means the image builds and boots in a virtual machine.** It does not mean
the system is finished, safe on real hardware, or usable as a daily driver. It
is published for transparency and review, not for installation.

What M0 actually proved, in CI, on QEMU/KVM with OVMF and no GPU:

- `podman build` succeeds and the image pushes to GHCR.
- `bootc-image-builder` produces a raw image well under the 8 GB budget.
- The VM boots unattended and Agent Friday's `/api/health` returns 200.
- `bootc status` shows exactly one deployment and `/usr` is read-only.
- The lockbox is created as real LUKS2 + Argon2id with its five btrfs subvolumes.
- Zero SELinux `avc: denied` lines in the boot log.

### What is NOT done

| Not done | Milestone |
|---|---|
| **Image signing.** Builds are pushed unsigned; cosign is a deliberate, documented skip. Do not treat a pulled image as verified. | M0 skip → later |
| **Any testing on real, physical hardware.** Everything above is a virtual machine. No bare-metal boot has been validated. | M2/M3 |
| **The first-boot wizard.** What exists is a stub that reads an unattended YAML file. There is no interactive wizard, no passphrase prompt, no recovery key. | M1 |
| **Automatic rollback, proven.** greenboot checks are installed; the fault-injection rollback test has not been run. | M1 |
| **Kiosk shell.** `friday-kiosk.service` ships installed but disabled. | M1 |
| **GPU / CUDA, model residency, local voice.** | M2 |
| **Roaming between machines, `preload`.** | M3 |
| **Install-to-disk, LAN access, update channels, hardware docs.** | M4 |

### Known blocking dependency

Friday Linux consumes Agent Friday by pinned tag and expects upstream changes
(`core/paths.py`, `core/os_mode.py`, a packaged seed) that **are not merged
upstream yet**. Until they are, `FRIDAY_OS_MODE=1` does not fully do what the
spec assumes, and several service definitions rely on documented workarounds
(see Amendment A1 in `docs/DECISIONS.md`). This is tracked honestly rather than
papered over.

### Safety notes if you build it anyway

- The unattended path takes a **literal passphrase from a YAML file**. The one
  in `.github/workflows/boot-test.yml` is a throwaway CI fixture, named as such.
  Never reuse it, and never ship a real passphrase that way.
- Secrets are generated at first boot into `/var/lib/friday/secrets.env`. Per a
  challenge recorded in `docs/DECISIONS.md`, that path is **not** on an
  encrypted lockbox subvolume — it is protected by root permissions only. That
  is a known gap against the spec's own stated security property.
- "Leaves no trace on the host" (goal G2) is a **design goal with a defined
  test, not a verified result.** That test has not been run.

---

## Repository layout

| Path | What it is |
|---|---|
| `Containerfile` | The bootc image build. |
| `build/` | Pins (`agent-friday.pin`, `llama.cpp.pin`), disk config, llama.cpp build script. |
| `image/` | Everything baked into the OS: systemd units, greenboot checks, firstboot wizard, Caddy, nftables, SELinux policy, polkit, sudoers. |
| `helper/` | `friday-os-helper` — the only privileged helper, with an argparse allowlist. |
| `.github/workflows/` | `build.yml` (image build + push) and `boot-test.yml` (QEMU/OVMF boot test). |
| `docs/SPEC.md` | The full system specification. Start here. |
| `docs/DECISIONS.md` | ADRs, challenges to decided items, and every deviation taken. |
| `docs/MILESTONES.md` | The real execution record, including the failures on the way. |
| `docs/VERIFY.md` | Facts assumed but not verifiable from the build sandbox, with the command to check each. |
| `docs/BOM.md` | Bill of materials. |

`docs/MILESTONES.md` deliberately keeps superseded, wrong intermediate states
rather than rewriting them. It is a log, not a summary.

## Documentation caveat

The `docs/` files were written as working documents for the build, not as
published material. They contain absolute paths from the author's own
development machine and reference sibling repositories that are not public.
They are kept as-is because they are the honest record; they are not a polished
external guide.

## Building

Requires Podman and a GHCR login.

```bash
podman build -t ghcr.io/futurespeakai/friday-linux:testing .
```

CI builds this on every push and runs the QEMU boot test on dispatch. The
published container package is **not** public — only this source is.

## License

MIT. See [LICENSE](LICENSE).

Friday Linux is built on Fedora Linux. It is not affiliated with, endorsed by,
or a product of the Fedora Project or Red Hat.
