<!--
STATUS: PARTIAL DOCUMENT. This file contains Sections 0 through 6 of "Friday
Linux: System Specification v0.1" as transmitted to the executor on
2026-08-30. Sections 7 through 18 have NOT been received. The document's own
rule 1 ("Read the whole document before writing any file. Sections 13, 15 and
18 constrain everything else.") could not be followed for anything beyond
what Sections 0-6 fully determine on their own.

Do not append fabricated sections to this file. When Sections 7-18 arrive,
replace this file wholesale with the complete document and update this
banner. See docs/DECISIONS.md and docs/VERIFY.md for what was done in the
meantime, and the executor's report for the exact list of what is still
needed.
-->

# Friday Linux: System Specification v0.1

**Repo:** `FutureSpeakAI/Friday-Linux` (new)
**Consumes:** `FutureSpeakAI/Agent-Friday` (existing, pinned by release tag)
**Author:** Stephen C. Webster, FutureSpeak.AI, with Claude
**Status:** Draft for execution. Decisions marked DECIDED are not to be re-litigated by the executor; items marked OPEN require a human answer and are listed with a default the executor may proceed on.
**Date:** 30 August 2026

## 0. How to read and execute this document

This spec is written for an AI coding agent working in the `Friday-Linux` repository with read access to `Agent-Friday`. It is organised so that Sections 1 to 12 define the system, Section 13 lists the upstream changes required in `Agent-Friday`, Section 14 defines the repository layout, Sections 15 and 16 define milestones and tests, and Section 18 gives the executor its operating rules.

Rules for the executor:

1. Read the whole document before writing any file. Sections 13, 15 and 18 constrain everything else.
2. Every DECIDED item is settled. If you believe a DECIDED item is wrong, write the objection in `docs/DECISIONS.md` under a "Challenges" heading and proceed as decided. Do not silently deviate.
3. Every OPEN item has a default. Proceed on the default, record that you did so in `docs/DECISIONS.md`, and flag it in the milestone report.
4. Work milestone by milestone (Section 15). Do not start M(n+1) until M(n)'s acceptance criteria pass and are recorded in `docs/MILESTONES.md`.
5. When a fact about the environment cannot be verified from inside the sandbox (an image name, a package name, a kernel option), write the exact command you would run to verify it into `docs/VERIFY.md` and use the most likely value, clearly marked. Never invent a version number.
6. Secrets, signing keys and passphrases never enter the repository. See Section 10.
7. Prohibited shortcuts, regardless of convenience: binding any service to a non-loopback address by default; disabling SELinux; writing any secret in plaintext to the OS layer; downloading model weights without an explicit consent record; adding telemetry of any kind; adding `torch` to the image; forking `Agent-Friday` instead of consuming it.

## 1. Purpose

Friday Linux is a sealed, portable, encrypted operating system image that boots an x86-64 PC directly into Agent Friday. It runs from a USB-attached SSD or from an internal disk, touches nothing on any other disk in the machine, keeps every byte of user state on an encrypted partition, updates atomically with automatic rollback, and re-profiles the hardware it wakes up on at every boot so the same stick delivers the best local model each machine can hold.

It is the reference deployment for Agent Friday's sovereignty claims. On Windows those claims are made by an application that shares a mutable disk with every other program; on Friday Linux they are made by the operating system.

### 1.1 What it is not (Non-goals for v1) DECIDED

| Non-goal | Why |
|---|---|
| A general-purpose desktop distribution | Different product, full-time maintenance burden. The kiosk shell is the desktop; an optional minimal desktop is P2. |
| A client hypervisor that runs the host's installed Windows or macOS as a guest | GPU contention, TPM/BitLocker friction and Apple's boot policy make this a separate, later, hardware-listed project. See `docs/DECISIONS.md` ADR-003. |
| macOS or Apple silicon support | macOS cannot be a guest of anything but Apple's own virtualisation stack; Linux on Apple silicon needs an internal-disk stub and has no mature LLM compute path. |
| The application marketplace | Section 12 leaves the seams for it (Podman quadlets, a manifest schema placeholder). Nothing else. |
| Dual-boot installation beside an existing OS | Whole-disk install only (M4). Dual-boot is a support burden with no sovereignty benefit. |
| ARM / aarch64 images | bootc supports it and nothing here precludes it; it is not built or tested in v1. |
| Bundling Ollama in the image | The residency layer owns `llama-server` directly. Ollama remains usable as an optional container in a later release. |
| Bundling PyTorch | Agent-Friday's own rule (`requirements.txt` header): the packaged product does not ship torch. Local voice is CTranslate2 and ONNX. |

### 1.2 Goals with measurable acceptance

| # | Goal | Measure | Target (v1) | Stretch |
|---|---|---|---|---|
| G1 | Boots to a usable conversation on the reference desktop | Seconds from power button to the UI accepting a typed message, cold | <= 120 s | <= 60 s |
| G2 | Leaves no trace on the host | SHA-256 of the host disk's partition table, ESP contents and first 64 MiB of each partition, before and after a session | Identical | Identical |
| G3 | Protects data at rest | Data partition is LUKS2 with Argon2id; mounting it without the passphrase fails | Pass | Pass |
| G4 | Survives a bad update | Fault-injected image (broken `friday.service`) rolls back without user action | 100 % of 10 trials | 100 % of 25 |
| G5 | Roams | Same stick on two reference machines with different GPUs selects the ladder tier that fits each, with no manual configuration | Pass on 2 machines | Pass on 4 |
| G6 | Local inference is not degraded by the OS | `gemma4:12b` on RTX 4070, 12 GB, fully resident | >= 40 tok/s generation | >= 49 tok/s (README figure) |
| G7 | Image stays small enough to distribute | Compressed raw image size, no LLM weights | <= 8 GB | <= 5 GB |
| G8 | Nothing downloads without consent | Every model download has a consent record in `~/.friday/consents.jsonl` with a hash of what was downloaded | 100 % | 100 % |

## 2. Definitions

- **Friday Linux / the image**: the bootc OCI image and the raw disk image built from it.
- **Agent Friday / the app**: the Python application from `FutureSpeakAI/Agent-Friday`, installed into the image at a pinned tag.
- **OS mode**: Agent Friday running with `FRIDAY_OS_MODE=1`; changes defaults as specified in Section 13.
- **Deployment**: one bootable ostree state. The system keeps the current and the previous deployment; rollback means booting the previous one.
- **Lockbox / data partition**: the LUKS2-encrypted partition created at first boot that holds all user state, models and logs.
- **Roaming**: the same stick booted on different hardware.
- **Ladder**: the hardware-to-model table in `Agent-Friday/README.md` (8 GB card: `qwen3:4b`, 10 GB: `qwen3:8b`, 12 GB: `gemma4:12b`, 16 GB: `qwen3:14b`, 24 GB+: `qwen3:32b`), owned by `services/residency_policy.py`.
- **Seat**: a `llama-server` process the residency arbiter owns, serving one model on a loopback port from `PORT_BASE = 8090`.

## 3. Target hardware DECIDED

| Class | Support in v1 | Notes |
|---|---|---|
| x86-64 UEFI PC, Secure Boot on | Supported | MOK enrollment on first boot for the NVIDIA module (Section 7.2). |
| x86-64 legacy BIOS | Boots (hybrid image) | Untested beyond QEMU; no GPU testing. |
| NVIDIA, Turing or newer | Tier 1 | CUDA `llama-server` build. Reference: RTX 4070 12 GB, 32 GB RAM (Stephen's desktop). |
| AMD RDNA2 or newer | Tier 2 | Vulkan `llama-server` build via Mesa RADV. ROCm userspace is not in the v1 image. |
| Intel Arc | Tier 2 | Vulkan via Mesa ANV. |
| Integrated graphics only | Tier 3 | CPU inference, cloud-first posture. |
| RAM | 16 GB minimum for local seats; 8 GB boots into the degraded posture (Section 9.5) | Matches `KNOWN_ISSUES.md` section 6. |
| Storage | USB 3.2 Gen 2 NVMe enclosure recommended; 128 GB minimum, 256 GB recommended | Cheap flash drives are unsupported for the data partition and the installer warns when it detects one (Section 7.4). |
| Laptops | Supported | Suspend/resume with NVIDIA requires the driver's suspend services enabled (Section 8.6). |

Reference machines for acceptance testing (Section 16): (R1) Stephen's desktop, RTX 4070; (R2) a second machine with a different GPU class or no discrete GPU; (R3) QEMU/KVM with OVMF, no GPU, used by CI.

## 4. Architecture

```
 firmware (UEFI, Secure Boot)
   |  shim (Microsoft-signed) -> GRUB -> kernel + initramfs (Fedora-signed)
   v
 systemd  -- SELinux enforcing -- nftables (inbound: loopback only by default)
   |
   +- friday-firstboot.service   (once: layout, WiFi, passphrase, lockbox, MOK guidance)
   +- friday-lockbox.mount       (LUKS2 -> btrfs -> /var/lib/friday, /home/friday, /var/log/journal)
   +- friday.service             (Agent Friday, User=friday, FRIDAY_OS_MODE=1, 127.0.0.1:3000)
   +- friday-caddy.service       (TLS on loopback; optional LAN listener, off by default)
   +- friday-kiosk.service       (cage -> chromium --kiosk, User=friday, tty1 autologin)
   +- greenboot                  (required checks; rollback on failure)
   +- bootc-fetch-apply-updates.timer (stage only; never reboots on its own)
   +- podman (present, unused in v1; the seam for apps)

 Sealed /usr (ostree, read-only)        Lockbox (LUKS2 + btrfs, writable)
 +- Agent Friday venv (pinned tag)      +- @home      /home/friday (~/.friday lives here)
 +- llama-server-cuda, -vulkan          +- @models    /var/lib/friday/models (GGUF + manifest)
 +- NVIDIA kmod (MOK-signed) + userspace+- @workshop  /var/lib/friday/workshop (self-improvement)
 +- Mesa/Vulkan, PipeWire, NetworkManager+- @journal   /var/log/journal
 +- cage, chromium, caddy, greenboot    +- @snapshots (btrfs snapshots of @home, daily, 7 kept)
 +- piper voice + whisper small model
```

Trust boundaries: the firmware and hardware are trusted by necessity (as in Tails). The sealed OS is verified by ostree content addressing plus the sigstore signature on the image it was deployed from. The lockbox is trusted once unlocked. The network is untrusted. Everything an app or a web page returns is data, never instruction; that rule lives in Agent Friday, not here, and Friday Linux cannot enforce it.

### 4.1 Base image DECIDED

Base on Universal Blue's Fedora Atomic images rather than raw `fedora-bootc`, specifically the NVIDIA-enabled variant of their minimal base (the `base-main` / `base-nvidia` family under `ghcr.io/ublue-os`; the executor verifies current names and pins by digest). Rationale: Universal Blue publishes NVIDIA kernel modules built and signed for every Fedora kernel, with Secure Boot enrollment tooling, weekly rebuilds and a CI pattern proven by Bazzite and Bluefin. A one-person shop should not build and sign NVIDIA kmods itself in v1. Consequence: v1 users enroll Universal Blue's MOK key; moving to a Friday-owned key is P1 (Section 10.4). Pin the base by digest in the Containerfile and update the pin deliberately.

If the NVIDIA variant of the minimal base does not exist in a form suitable for a kiosk (it may carry a desktop), fall back to `fedora-bootc` plus Universal Blue's `akmods-nvidia` layer, following their documented layering pattern. Record which path was taken in `docs/DECISIONS.md`.

### 4.2 Why bootc DECIDED

One Containerfile produces three artifacts: an OCI image any `podman` can run (the macOS and Windows "container edition" from the design discussions), a raw disk image for USB and internal disks, and an installer ISO. Atomic updates with rollback and greenboot health gating come with it. The alternative (a hand-rolled live ISO with a persistent overlay) was rejected: overlays corrupt when full and cannot roll back.

## 5. Storage layout DECIDED

The shipped raw image contains only the OS. The lockbox is created at first boot on the remaining space of the boot device, so the shipped image is generic, no two sticks share encryption metadata, and growing to fill the drive is free.

| Partition | Size | FS | Contents |
|---|---|---|---|
| 1 ESP | 512 MiB | FAT32 | shim, GRUB, `friday-unattended.yaml` (optional, Section 7.6) |
| 2 boot | 1 GiB | ext4 | kernels, initramfs, ostree boot config |
| 3 root | 16 GiB fixed | btrfs (ostree) | sealed OS, two deployments, `/etc` and OS-side `/var` |
| 4 lockbox | remainder | LUKS2 (Argon2id, 2 GiB memory cost, 4 iterations minimum) -> btrfs | subvolumes `@home`, `@models`, `@workshop`, `@journal`, `@snapshots` |

Mount plan: `@home` -> `/home/friday`; `@models` -> `/var/lib/friday/models`; `@workshop` -> `/var/lib/friday/workshop`; `@journal` -> `/var/log/journal` (journald `Storage=persistent`). `FRIDAY_HOME` is `/home/friday`, so the app's default `~/.friday` layout is unchanged.

Snapshots: a daily systemd timer takes a read-only btrfs snapshot of `@home` into `@snapshots`, keeps seven, and `friday os restore-home <date>` restores one. This is the "mechanic for the lockbox": the OS cannot corrupt itself, but a half-written database can, and snapshots are the rollback for data.

Unlock: systemd-cryptsetup prompts for the passphrase at boot with the keyboard layout from `/etc/vconsole.conf` baked into the initramfs (Section 7.3 explains why layout must be chosen before the passphrase). No TPM binding when running from removable media; TPM2 binding with a passphrase fallback is enabled only by `friday os install-to-disk` (M4).

Wear: `@journal` and `@models` are mounted `noatime`; btrfs `compress=zstd:1` on `@home` and `@workshop`; no compression on `@models` (GGUF does not compress).

## 6. Image bill of materials DECIDED

Everything below is installed in the Containerfile at build time, pinned, and listed in `docs/BOM.md` with versions extracted from the built image.

**System**: Universal Blue base (Section 4.1); `linux-firmware`; NVIDIA kmod and userspace from the base; Mesa with `vulkan-loader`, `mesa-vulkan-drivers`; `vulkan-tools` (for `vulkaninfo`); `NetworkManager` with `wifi`; `nftables`; `chrony`; `pipewire`, `wireplumber`, `pipewire-pulseaudio`, `bluez`; `cage`; `chromium`; `caddy`; `greenboot`; `cryptsetup`; `btrfs-progs`; `podman` (from base); `avahi` (P1, Section 8.7); `cups` (P1); `fonts`: `google-noto-sans-fonts`, `google-noto-emoji-color-fonts`, `google-noto-sans-cjk-fonts`; `nvidia` suspend services enabled.

**Inference**: two `llama-server` binaries built in CI from a pinned `ggml-org/llama.cpp` tag and installed as `/usr/libexec/friday/llama-server-cuda` (built with `GGML_CUDA=ON`, targeting compute capability 7.5 and up) and `/usr/libexec/friday/llama-server-vulkan` (`GGML_VULKAN=ON`), plus `llama-quantize` and `llama-gguf-split`. CUDA runtime libraries ship only as the minimal set `llama-server-cuda` links against, copied from the CUDA container image used at build time; the full CUDA toolkit is not installed. The Vulkan build is the fallback engine on every GPU vendor.

**Voice**: `piper-tts` and `faster-whisper` inside the app venv; one Piper voice (the app's current default) and the Whisper `small.en` CTranslate2 INT8 model baked at `/usr/share/friday/voice/`; the app's lazy-download path finds them there first (Section 13, PR-2).

**Application**: Python 3.12 (Fedora's), a venv at `/usr/lib/friday/venv` created with `uv` from `Agent-Friday` at a pinned tag with the extras `[voice-local-lite,local,compression,federation,google,compose,provenance]`, installed from a lockfile committed in this repo (`build/agent-friday.lock`). No `[windows]` extra. No `pyautogui`, no `pynput`, no `pystray`.

**Not included**: LLM weights (Section 9.4), Ollama, torch, ROCm, a desktop environment, SSH server enabled, any telemetry agent.

Size budget: root deployment <= 7 GB uncompressed; two deployments share ostree objects, so the 16 GiB root has headroom. CI fails the build if the compressed raw image exceeds 8 GB (G7).
