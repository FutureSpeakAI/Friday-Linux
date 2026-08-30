# Friday Linux: System Specification v0.1

**Repo:** `FutureSpeakAI/Friday-Linux` (new)
**Consumes:** `FutureSpeakAI/Agent-Friday` (existing, pinned by release tag)
**Author:** Stephen C. Webster, FutureSpeak.AI, with Claude
**Status:** Draft for execution. Decisions marked DECIDED are not to be re-litigated by the executor; items marked OPEN require a human answer and are listed with a default the executor may proceed on.
**Date:** 30 August 2026

---

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

---

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
| G1 | Boots to a usable conversation on the reference desktop | Seconds from power button to the UI accepting a typed message, cold | ≤ 120 s | ≤ 60 s |
| G2 | Leaves no trace on the host | SHA-256 of the host disk's partition table, ESP contents and first 64 MiB of each partition, before and after a session | Identical | Identical |
| G3 | Protects data at rest | Data partition is LUKS2 with Argon2id; mounting it without the passphrase fails | Pass | Pass |
| G4 | Survives a bad update | Fault-injected image (broken `friday.service`) rolls back without user action | 100 % of 10 trials | 100 % of 25 |
| G5 | Roams | Same stick on two reference machines with different GPUs selects the ladder tier that fits each, with no manual configuration | Pass on 2 machines | Pass on 4 |
| G6 | Local inference is not degraded by the OS | `gemma4:12b` on RTX 4070, 12 GB, fully resident | ≥ 40 tok/s generation | ≥ 49 tok/s (README figure) |
| G7 | Image stays small enough to distribute | Compressed raw image size, no LLM weights | ≤ 8 GB | ≤ 5 GB |
| G8 | Nothing downloads without consent | Every model download has a consent record in `~/.friday/consents.jsonl` with a hash of what was downloaded | 100 % | 100 % |

---

## 2. Definitions

- **Friday Linux / the image**: the bootc OCI image and the raw disk image built from it.
- **Agent Friday / the app**: the Python application from `FutureSpeakAI/Agent-Friday`, installed into the image at a pinned tag.
- **OS mode**: Agent Friday running with `FRIDAY_OS_MODE=1`; changes defaults as specified in Section 13.
- **Deployment**: one bootable ostree state. The system keeps the current and the previous deployment; rollback means booting the previous one.
- **Lockbox / data partition**: the LUKS2-encrypted partition created at first boot that holds all user state, models and logs.
- **Roaming**: the same stick booted on different hardware.
- **Ladder**: the hardware-to-model table in `Agent-Friday/README.md` (8 GB card: `qwen3:4b`, 10 GB: `qwen3:8b`, 12 GB: `gemma4:12b`, 16 GB: `qwen3:14b`, 24 GB+: `qwen3:32b`), owned by `services/residency_policy.py`.
- **Seat**: a `llama-server` process the residency arbiter owns, serving one model on a loopback port from `PORT_BASE = 8090`.

---

## 3. Target hardware DECIDED

| Class | Support in v1 | Notes |
|---|---|---|
| x86-64 UEFI PC, Secure Boot on | Supported | MOK enrollment on first boot for the NVIDIA module (Section 7.2). |
| x86-64 legacy BIOS | Boots (hybrid image) | Untested beyond QEMU; no GPU testing. |
| NVIDIA, Turing or newer | Tier 1 | CUDA `llama-server` build. Reference: RTX 4070 12 GB, 32 GB RAM (Stephen's desktop). |
| AMD RDNA2 or newer | Tier 2 | Vulkan `llama-server` build via Mesa RADV. ROCm userspace is not in the v1 image. |
| Intel Arc | Tier 2 | Vulkan via Mesa ANV. |
| Integrated graphics only | Tier 3 | CPU inference, cloud-first posture. |
| RAM | 16 GB minimum for local seats; 8 GB boots into the degraded posture (Section 9.5) | Matches `KNOWN_ISSUES.md` §6. |
| Storage | USB 3.2 Gen 2 NVMe enclosure recommended; 128 GB minimum, 256 GB recommended | Cheap flash drives are unsupported for the data partition and the installer warns when it detects one (Section 7.4). |
| Laptops | Supported | Suspend/resume with NVIDIA requires the driver's suspend services enabled (Section 8.6). |

Reference machines for acceptance testing (Section 16): (R1) Stephen's desktop, RTX 4070; (R2) a second machine with a different GPU class or no discrete GPU; (R3) QEMU/KVM with OVMF, no GPU, used by CI.

---

## 4. Architecture

```
 firmware (UEFI, Secure Boot)
   │  shim (Microsoft-signed) → GRUB → kernel + initramfs (Fedora-signed)
   ▼
 systemd  ── SELinux enforcing ── nftables (inbound: loopback only by default)
   │
   ├─ friday-firstboot.service   (once: layout, WiFi, passphrase, lockbox, MOK guidance)
   ├─ friday-lockbox.mount       (LUKS2 → btrfs → /var/lib/friday, /home/friday, /var/log/journal)
   ├─ friday.service             (Agent Friday, User=friday, FRIDAY_OS_MODE=1, 127.0.0.1:3000)
   ├─ friday-caddy.service       (TLS on loopback; optional LAN listener, off by default)
   ├─ friday-kiosk.service       (cage → chromium --kiosk, User=friday, tty1 autologin)
   ├─ greenboot                  (required checks; rollback on failure)
   ├─ bootc-fetch-apply-updates.timer (stage only; never reboots on its own)
   └─ podman (present, unused in v1; the seam for apps)

 Sealed /usr (ostree, read-only)        Lockbox (LUKS2 + btrfs, writable)
 ├─ Agent Friday venv (pinned tag)      ├─ @home      /home/friday (~/.friday lives here)
 ├─ llama-server-cuda, -vulkan          ├─ @models    /var/lib/friday/models (GGUF + manifest)
 ├─ NVIDIA kmod (MOK-signed) + userspace├─ @workshop  /var/lib/friday/workshop (self-improvement)
 ├─ Mesa/Vulkan, PipeWire, NetworkManager├─ @journal   /var/log/journal
 ├─ cage, chromium, caddy, greenboot    └─ @snapshots (btrfs snapshots of @home, daily, 7 kept)
 └─ piper voice + whisper small model
```

Trust boundaries: the firmware and hardware are trusted by necessity (as in Tails). The sealed OS is verified by ostree content addressing plus the sigstore signature on the image it was deployed from. The lockbox is trusted once unlocked. The network is untrusted. Everything an app or a web page returns is data, never instruction; that rule lives in Agent Friday, not here, and Friday Linux cannot enforce it.

### 4.1 Base image DECIDED

Base on Universal Blue's Fedora Atomic images rather than raw `fedora-bootc`, specifically the NVIDIA-enabled variant of their minimal base (the `base-main` / `base-nvidia` family under `ghcr.io/ublue-os`; the executor verifies current names and pins by digest). Rationale: Universal Blue publishes NVIDIA kernel modules built and signed for every Fedora kernel, with Secure Boot enrollment tooling, weekly rebuilds and a CI pattern proven by Bazzite and Bluefin. A one-person shop should not build and sign NVIDIA kmods itself in v1. Consequence: v1 users enroll Universal Blue's MOK key; moving to a Friday-owned key is P1 (Section 10.4). Pin the base by digest in the Containerfile and update the pin deliberately.

If the NVIDIA variant of the minimal base does not exist in a form suitable for a kiosk (it may carry a desktop), fall back to `fedora-bootc` plus Universal Blue's `akmods-nvidia` layer, following their documented layering pattern. Record which path was taken in `docs/DECISIONS.md`.

### 4.2 Why bootc DECIDED

One Containerfile produces three artifacts: an OCI image any `podman` can run (the macOS and Windows "container edition" from the design discussions), a raw disk image for USB and internal disks, and an installer ISO. Atomic updates with rollback and greenboot health gating come with it. The alternative (a hand-rolled live ISO with a persistent overlay) was rejected: overlays corrupt when full and cannot roll back.

---

## 5. Storage layout DECIDED

The shipped raw image contains only the OS. The lockbox is created at first boot on the remaining space of the boot device, so the shipped image is generic, no two sticks share encryption metadata, and growing to fill the drive is free.

| Partition | Size | FS | Contents |
|---|---|---|---|
| 1 ESP | 512 MiB | FAT32 | shim, GRUB, `friday-unattended.yaml` (optional, Section 7.6) |
| 2 boot | 1 GiB | ext4 | kernels, initramfs, ostree boot config |
| 3 root | 16 GiB fixed | btrfs (ostree) | sealed OS, two deployments, `/etc` and OS-side `/var` |
| 4 lockbox | remainder | LUKS2 (Argon2id, 2 GiB memory cost, 4 iterations minimum) → btrfs | subvolumes `@home`, `@models`, `@workshop`, `@journal`, `@snapshots` |

Mount plan: `@home` → `/home/friday`; `@models` → `/var/lib/friday/models`; `@workshop` → `/var/lib/friday/workshop`; `@journal` → `/var/log/journal` (journald `Storage=persistent`). `FRIDAY_HOME` is `/home/friday`, so the app's default `~/.friday` layout is unchanged.

Snapshots: a daily systemd timer takes a read-only btrfs snapshot of `@home` into `@snapshots`, keeps seven, and `friday os restore-home <date>` restores one. This is the "mechanic for the lockbox": the OS cannot corrupt itself, but a half-written database can, and snapshots are the rollback for data.

Unlock: systemd-cryptsetup prompts for the passphrase at boot with the keyboard layout from `/etc/vconsole.conf` baked into the initramfs (Section 7.3 explains why layout must be chosen before the passphrase). No TPM binding when running from removable media; TPM2 binding with a passphrase fallback is enabled only by `friday os install-to-disk` (M4).

Wear: `@journal` and `@models` are mounted `noatime`; btrfs `compress=zstd:1` on `@home` and `@workshop`; no compression on `@models` (GGUF does not compress).

---

## 6. Image bill of materials DECIDED

Everything below is installed in the Containerfile at build time, pinned, and listed in `docs/BOM.md` with versions extracted from the built image.

**System**: Universal Blue base (Section 4.1); `linux-firmware`; NVIDIA kmod and userspace from the base; Mesa with `vulkan-loader`, `mesa-vulkan-drivers`; `vulkan-tools` (for `vulkaninfo`); `NetworkManager` with `wifi`; `nftables`; `chrony`; `pipewire`, `wireplumber`, `pipewire-pulseaudio`, `bluez`; `cage`; `chromium`; `caddy`; `greenboot`; `cryptsetup`; `btrfs-progs`; `podman` (from base); `avahi` (P1, Section 8.7); `cups` (P1); `fonts`: `google-noto-sans-fonts`, `google-noto-emoji-color-fonts`, `google-noto-sans-cjk-fonts`; `nvidia` suspend services enabled.

**Inference**: two `llama-server` binaries built in CI from a pinned `ggml-org/llama.cpp` tag and installed as `/usr/libexec/friday/llama-server-cuda` (built with `GGML_CUDA=ON`, targeting compute capability 7.5 and up) and `/usr/libexec/friday/llama-server-vulkan` (`GGML_VULKAN=ON`), plus `llama-quantize` and `llama-gguf-split`. CUDA runtime libraries ship only as the minimal set `llama-server-cuda` links against, copied from the CUDA container image used at build time; the full CUDA toolkit is not installed. The Vulkan build is the fallback engine on every GPU vendor.

**Voice**: `piper-tts` and `faster-whisper` inside the app venv; one Piper voice (the app's current default) and the Whisper `small.en` CTranslate2 INT8 model baked at `/usr/share/friday/voice/`; the app's lazy-download path finds them there first (Section 13, PR-2).

**Application**: Python 3.12 (Fedora's), a venv at `/usr/lib/friday/venv` created with `uv` from `Agent-Friday` at a pinned tag with the extras `[voice-local-lite,local,compression,federation,google,compose,provenance]`, installed from a lockfile committed in this repo (`build/agent-friday.lock`). No `[windows]` extra. No `pyautogui`, no `pynput`, no `pystray`.

**Not included**: LLM weights (Section 9.4), Ollama, torch, ROCm, a desktop environment, SSH server enabled, any telemetry agent.

Size budget: root deployment ≤ 7 GB uncompressed; two deployments share ostree objects, so the 16 GiB root has headroom. CI fails the build if the compressed raw image exceeds 8 GB (G7).

---

## 7. Boot and first-boot experience

### 7.1 Every boot

1. Firmware loads shim (Microsoft-signed), GRUB, the Fedora-signed kernel.
2. The initramfs prompts for the lockbox passphrase using the baked keymap. Three failures reboot; there is no recovery shell on the stick.
3. `friday-lockbox.mount` mounts the subvolumes; `friday.service`, `friday-caddy.service` and `friday-kiosk.service` start in that order, gated on the mounts.
4. The kiosk shows a Friday-branded splash (a static HTML page served by Caddy from `/usr/share/friday/splash/`) until `/api/health` returns 200, then navigates to the app. The splash shows real progress from `/api/health` (which subsystem is loading), never a fake bar.
5. greenboot runs its required checks (Section 11.2) after `graphical.target`; if they fail on a freshly updated deployment, the machine reboots into the previous deployment and the splash says so in plain language.

### 7.2 Secure Boot and MOK

On a machine with Secure Boot on, the NVIDIA module loads only after the signing key is enrolled. The first-boot wizard detects `mokutil --sb-state` = enabled and the NVIDIA module absent, explains in one paragraph that a blue text screen will appear on the next reboot asking for a password, shows the password (the base image's documented enrollment password in v1; Section 10.4), runs the enrollment (`ujust enroll-secure-boot-key` or the underlying `mokutil --import`), and reboots. The wizard does not offer to disable Secure Boot; the docs explain that gaming anti-cheat requires it to stay on. Machines with Secure Boot off skip this step. AMD and Intel machines never see it.

### 7.3 First-boot wizard (`friday-firstboot.service`)

Runs once, before `friday.service`, as a small web app on `127.0.0.1:3001` served to the kiosk (the kiosk points at Caddy, which routes to the wizard until it marks itself done). Steps, in this order, with the reason the order matters:

1. **Language and keyboard layout.** First, because the passphrase is typed in step 4 and the initramfs keymap must match. Writes `/etc/vconsole.conf` and `/etc/locale.conf`; the initramfs is regenerated at the end of the wizard, before the reboot.
2. **Network.** Lists Wi-Fi networks via NetworkManager (`nmcli`, permitted for user `friday` by a polkit rule scoped to `org.freedesktop.NetworkManager.settings.modify.own` and `.network-control`). Ethernet just works. Skippable: Friday runs offline.
3. **Time zone.** From network geolocation if online (with the source shown), else a picker. Sets `timedatectl set-local-rtc 1` (Section 8.5).
4. **Passphrase.** Creates the lockbox: `cryptsetup luksFormat` on the free space, btrfs with the five subvolumes, mounts them, writes `/etc/crypttab` and the mount units. Minimum 12 characters; a strength meter that says what it measures. The wizard says plainly that there is no recovery if the passphrase is lost and offers to print or display a recovery key (a second LUKS keyslot with a generated 256-bit key shown once as words). OPEN: whether to offer the recovery key at all (default: yes, opt-in).
5. **Storage advisory.** Reads the boot device's sysfs (`/sys/block/*/removable`, USB speed, model string) and warns if the device is a USB 2.0 link or reports itself as a flash drive class device, with the recommendation from Section 3. Advisory only.
6. **Hardware profile and model plan.** Runs Agent Friday's `hardware_profile` and `residency_policy` (Section 9) and shows the plan in the ladder's own words: which model, how much download, why. Two buttons: download now (writes a consent record, G8) or run cloud-first for now. Nothing downloads before the button.
7. **Cloud keys.** Optional, matching the app's own `friday setup` semantics; stored through the app's credential store (Section 13, PR-5).
8. **Account.** Sets the `friday` user's password (used for `sudo` and the P1 screen lock), defaulting to the lockbox passphrase with the option to differ.
9. **Handoff.** Regenerates the initramfs with the chosen keymap, marks the wizard complete (`/var/lib/friday/.firstboot-done`), and either reboots (Secure Boot enrollment pending) or starts `friday.service`, at which point Agent Friday's own voice onboarding (`/api/onboarding/*`, `/api/setup/*`) takes over. The two wizards must not duplicate questions: the OS wizard owns machine setup, the app's onboarding owns personality and keys.

### 7.4 Model download and the loaded-stick path

The image carries no LLM weights (G7). After first boot, `friday os preload [--tier auto|<model>]` downloads the ladder tier for this hardware, or a named model, into `@models` with SHA-256 verification against the catalog (`services/residency_catalog.py`) and a consent record. `friday os preload --from /path/to/usb` copies GGUF files from a second drive for offline provisioning (P1).

### 7.5 Shutdown and removal

`poweroff` from the UI or the power button (logind `HandlePowerKey=poweroff`) flushes and unmounts the lockbox. The docs tell users to shut down before pulling the stick; a `friday os` check on next boot detects an unclean unmount and runs `btrfs check --readonly` plus a snapshot-based repair prompt (P1).

### 7.6 Unattended provisioning

If `friday-unattended.yaml` exists on the ESP, the wizard reads answers from it (layout, locale, timezone, Wi-Fi SSID and PSK, passphrase or a flag to generate one and print it to the console, model plan choice, account password) and runs without a display. This is how CI boots the image (Section 16.2) and how someone provisioning ten sticks avoids ten wizards. The file is deleted from the ESP after use.

---

## 8. Runtime services

All units live in `image/systemd/` in this repo and are copied to `/usr/lib/systemd/system/` in the Containerfile. Every unit has `Restart=on-failure`, `RestartSec=5`, and a `StartLimitBurst` that lets greenboot see a persistent failure.

### 8.1 `friday.service`

```
[Unit]
After=friday-lockbox.mount network-online.target
Requires=friday-lockbox.mount
ConditionPathExists=/var/lib/friday/.firstboot-done
[Service]
User=friday
Group=friday
EnvironmentFile=/etc/friday/os.env
EnvironmentFile=-/var/lib/friday/secrets.env
ExecStart=/usr/lib/friday/venv/bin/friday
WorkingDirectory=/home/friday
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/home/friday /var/lib/friday /tmp
PrivateTmp=yes
DeviceAllow=/dev/nvidia* rw
DeviceAllow=/dev/dri rw
SupplementaryGroups=video render audio
TimeoutStartSec=600
```

`/etc/friday/os.env` (in the image):

```
FRIDAY_OS_MODE=1
FRIDAY_HOME=/home/friday
FRIDAY_BIND_HOST=127.0.0.1
FRIDAY_PORT=3000
FRIDAY_LLAMA_SERVER_BIN=/usr/libexec/friday/llama-server-cuda:/usr/libexec/friday/llama-server-vulkan
FRIDAY_MODELS_DIR=/var/lib/friday/models
FRIDAY_VOICE_ASSETS=/usr/share/friday/voice
FRIDAY_LOG_TARGET=stdout
FRIDAY_TRUST_LOOPBACK=1
```

`/var/lib/friday/secrets.env` (lockbox, mode 0600, owner `friday`): `FRIDAY_PASSWORD` and `FRIDAY_SECRET_KEY`, both generated by the first-boot wizard with 256 bits of entropy. The human has one passphrase (the lockbox); the app's own vault and session keys are random and protected by the lockbox. `docs/SECURITY.md` states this trade-off: app-layer encryption adds no strength beyond disk encryption on Friday Linux, and it exists so the same app code runs unchanged.

### 8.2 `friday-caddy.service`

Caddy on loopback with its internal CA, adapted from `Agent-Friday/ops/Caddyfile` (Windows paths replaced; storage at `/var/lib/friday/caddy`). Serves `https://friday.local` and `https://localhost` to the kiosk, proxying to `127.0.0.1:3000`, and serves the splash and the first-boot wizard. The kiosk's Chromium trusts the Caddy CA via an NSS database seeded at first boot. LAN exposure is a single toggle in the app's Settings → System panel (Section 13, PR-10) that adds a listener on the LAN address, requires `FRIDAY_REMOTE_KEY` auth, opens `443/tcp` in nftables, and publishes `friday.local` via Avahi (P1). Default off.

### 8.3 `friday-kiosk.service`

Autologin on tty1 as `friday` running `cage -- chromium --kiosk --ozone-platform=wayland --enable-features=VaapiVideoDecoder --disable-pinch --overscroll-history-navigation=0 https://localhost/`. Chromium policy at `/etc/chromium/policies/managed/friday.json` sets `AudioCaptureAllowedUrls` and `VideoCaptureAllowedUrls` to the Friday origin so the mic works without a prompt, disables sync, sign-in, password manager, and default browser prompts, and sets `HomepageLocation`. A watchdog restarts the session if Chromium exits. `Ctrl+Alt+F2` reaches a login prompt for the `friday` user (terminal access, `sudo` with password); this is the advanced escape hatch and is documented.

HiDPI: cage honours the output scale; the wizard's layout step sets a scale factor written to the Chromium flags. Multi-monitor: cage uses one output; others are off in v1 (P2).

### 8.4 Audio

PipeWire and WirePlumber run in the `friday` user session started by the kiosk unit (`systemd --user` is enabled for `friday` with lingering). Default sink and source follow WirePlumber's priority; Bluetooth headsets pair through the app's Settings → System panel calling `bluetoothctl` (P1). The app's local voice loop uses the browser's audio pipeline, so nothing in Agent Friday touches ALSA directly.

### 8.5 Time

`chrony` for NTP. The hardware clock is set to local time at build (`/etc/adjtime` with `LOCAL`) so dual-booting Windows machines do not drift by the timezone offset after a Friday session. Documented in `docs/INSTALL.md` because it is the first thing a Windows user notices when it is wrong.

### 8.6 Power

logind: lid close suspends on laptops; power key powers off; idle does nothing in v1 (P1: dim and lock). NVIDIA suspend/resume services enabled with `PreserveVideoMemoryAllocations=1` so loaded seats survive suspend. On battery below 20 %, the residency arbiter is told to release seats (Section 9.6, P1).

### 8.7 Networking

NetworkManager with Wi-Fi and Ethernet; captive portals are handled by opening the portal URL in a second cage window (P1). nftables ruleset in the image: inbound drop by default, loopback allowed, established/related allowed, `443/tcp` opened only when the LAN toggle is on, mDNS opened with it. Outbound is allowed at the kernel level; the application-level egress gate (`services/egress_gate.py`) remains the policy authority. P2: render the egress gate's allowlist into an nftables output chain so the OS enforces the same policy.

### 8.8 Logging and diagnostics

journald persistent in `@journal`, `SystemMaxUse=2G`. `FRIDAY_LOG_TARGET=stdout` sends the app's logs to the journal (PR-2). `friday os diagnostics` writes a tarball to `/home/friday/Diagnostics/` containing the journal for the last boot, `bootc status`, the hardware profile, the residency plan, `nvidia-smi` and `vulkaninfo --summary` output, and `dmesg`, with a redaction pass that removes anything matching the app's PII scrubber patterns plus Wi-Fi PSKs and any line containing `KEY`, `SECRET`, `PASSWORD` or `TOKEN`.

---

## 9. Inference and residency in OS mode

### 9.1 Engine discovery DECIDED

The arbiter resolves the engine from `FRIDAY_LLAMA_SERVER_BIN`, a colon-separated list tried in order; each candidate is probed once per boot with `--version` and, for the CUDA binary, a load of a 100 MB probe GGUF baked at `/usr/share/friday/probe.gguf` with `-ngl 1`. A candidate that fails the probe is memoised as unavailable for this boot (`_ENGINE_MEMO` in `residency_arbiter.py` already exists for this purpose). The Windows path (`AppData/.../llama-server.exe`) becomes the Windows default of the same variable rather than a hardcoded lookup.

### 9.2 GPU probes DECIDED

`hardware_profile.detect_gpus()` gains a second probe: `vulkaninfo --summary` parsed for device name, vendor ID and `VkPhysicalDeviceMemoryProperties` device-local heap size, run when `nvidia-smi` is absent or returns no devices. Output is normalised to the same record shape with `vendor` in `{nvidia, amd, intel, other}` and `backend` in `{cuda, vulkan, cpu}`. On NVIDIA, per-process VRAM attribution uses `nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits`, which works on Linux (the "Windows only for the moment" comment at `hardware_profile.py:280` becomes Linux-first). Software Vulkan devices (llvmpipe) are excluded by vendor ID and device type.

### 9.3 Roaming DECIDED

The hardware profile is recomputed on every boot and cached at `/var/lib/friday/hwprofile/<fingerprint>.json`, where the fingerprint is a SHA-256 of DMI product name and serial, CPU model, total RAM and the GPU list. The residency plan for a fingerprint persists, so a machine Friday has seen before boots into its last known-good plan immediately and re-verifies in the background. A new fingerprint triggers the plan step from Section 7.3 step 6 inside the app (a one-screen consent, not the whole wizard).

### 9.4 Model store DECIDED

`@models` holds GGUF files named `<model_id>/<quant>.gguf` with a `manifest.json` per model recording source URL, SHA-256, size, license, and the consent record ID. The catalog (`services/residency_catalog.py`) is the source of truth for the ladder; the store is a cache of it. Ollama's blob store is not used. Multimodal projectors (`mmproj`) live beside their model.

### 9.5 Memory floor and the 8 GB posture DECIDED

`OS_RESERVE_MIB["linux"]` stays at 4096. On a machine where the policy engine resolves zero seats, OS mode does not refuse; it starts in a documented degraded posture: cloud providers if keys exist, otherwise a CPU seat for the smallest catalog model with a banner in the UI stating why. This replaces the refusal behaviour recorded in `KNOWN_ISSUES.md` §6 for OS mode only.

### 9.6 Seat lifecycle on the OS

Seats are children of `friday.service`; systemd's cgroup kills them on stop, which removes the orphan-reaping problem the arbiter solves on Windows with PowerShell. `_alive`, `_listening_ports`, the `Win32_Process` name filter and `_seat_num_ctx` are reimplemented on `psutil` (`pid_exists`, `net_connections(kind="tcp")`, `process_iter(["name","cmdline"])`, `Process.cmdline()`), which is already a core dependency. On the OS, the arbiter additionally receives `SIGUSR1` from `friday-power.service` (P1) to release seats on low battery.

---

## 10. Security posture

### 10.1 Threat model (in `docs/SECURITY.md`, this is the summary)

| Threat | Control | Residual risk |
|---|---|---|
| Lost or stolen stick | LUKS2 Argon2id on the lockbox; nothing user-related outside it | Passphrase strength; the recovery key if printed |
| Tampered firmware or hardware ("evil maid") | None beyond Secure Boot | Accepted, as Tails accepts it; documented |
| Tampered OS image | ostree content addressing; sigstore signature verified by `containers-policy.json` before any deployment; greenboot | Compromise of the signing key |
| Malicious content reaching the model (prompt injection via web, mail, apps) | Agent Friday's egress gate and tier gating | Model-layer; cannot be closed by the OS |
| Network attacker on the LAN | Inbound drop by default; LAN listener off; auth required when on | Misconfiguration |
| A bad update | Staged deployments, greenboot required checks, automatic rollback, `bootc rollback` for the human | An update that passes checks but misbehaves later |
| Data corruption on removable media | btrfs checksums, daily snapshots, unclean-unmount detection | Media failure; backups are the user's job until P1 |

### 10.2 Controls in the image

SELinux enforcing (never permissive in any unit or script); no root password; `friday` is the only login user; SSH server installed but disabled with no host keys generated (enabling it generates keys and is a System panel action, P1); nftables as in 8.7; `NoNewPrivileges`, `ProtectSystem=strict` and device allow-lists on every Friday unit; Chromium policies from 8.3; no telemetry, no crash upload, no update pings beyond the registry pull; `FRIDAY_SECRET_KEY` and `FRIDAY_PASSWORD` generated per install; dependency lockfile for the app venv; weekly automated image rebuild in CI to pick up base and package security updates.

### 10.3 Image signing and verification

CI signs every image with cosign (keyless sigstore with the GitHub OIDC identity, plus an offline key held by Stephen for release tags). The image's `/etc/containers/policy.json` requires a valid signature from the release identity for `ghcr.io/futurespeakai/friday-linux`; `bootc upgrade` refuses unsigned or mis-signed images. The verification identity and how to rotate it are documented in `docs/SECURITY.md`.

### 10.4 Secure Boot key custody

v1 enrolls the Universal Blue MOK because their signed NVIDIA kmods are consumed as-is (Section 4.1). P1: generate a Friday MOK offline, keep the private key out of CI except as a signing secret with restricted scope, re-sign the kmods in CI, and provide `friday os rekey-secure-boot` to enroll the new key and remove the old one. Documented as a known trust dependency until then.

---

## 11. Updates and rollback

### 11.1 Flow

`bootc-fetch-apply-updates.timer` runs daily: pulls the image for the configured channel (`stable` by default; `testing` opt-in in the System panel), verifies the signature, stages the deployment, and does nothing else. The UI shows "Update ready; applies at next restart" with the changelog pulled from the image's `/usr/share/friday/CHANGELOG.md`. The machine never reboots on its own.

### 11.2 greenboot required checks (`image/greenboot/required.d/`)

1. `10-lockbox.sh`: all five subvolumes mounted and writable.
2. `20-friday-service.sh`: `friday.service` active within 300 s of boot.
3. `30-health.sh`: `GET /api/health` returns 200 and a JSON body with `boot_critical_ok: true` (PR-6 defines the contract). Model seats are explicitly not boot-critical; a machine that cannot load a model must still boot.
4. `40-kiosk.sh`: `friday-kiosk.service` active and cage has an output.

Any failure on a newly staged deployment triggers greenboot's rollback; the same failure on an established deployment is logged and surfaced in the splash without rollback (nothing to roll back to). `friday os rollback` is the manual path; the System panel exposes it.

### 11.3 How app releases become OS releases

An `Agent-Friday` release tag triggers a workflow in this repo that bumps the pinned tag, rebuilds the lockfile, builds, tests (Section 16) and publishes to the `testing` channel; promotion to `stable` is a manual approval in GitHub Actions. Base image digest bumps follow the same path.

---

## 12. Self-improvement in OS mode

Agent Friday's learning (skills, personality, memory, generated UI parts) lives in `~/.friday` on the lockbox and is unaffected by the sealed OS. Modification of the app's own code follows three steps:

1. **Learn**: unchanged; data only.
2. **Experiment**: a git clone of `Agent-Friday` at the deployed tag lives in `@workshop`. The app may edit it, run its test suite there, and ask to try it live. Trying it live means `friday os overlay on` (which runs `bootc usr-overlay` to lay a transient writable overlay on `/usr` until reboot), `uv pip install -e /var/lib/friday/workshop/Agent-Friday` into the venv, and a service restart. The System panel shows an "experimental code is live until reboot" banner. Reboot discards it.
3. **Promote**: `friday os propose` pushes a branch to the user's fork of `Agent-Friday` and opens a pull request. The change lands in the OS only through Section 11.3. The app never writes to the sealed layer.

Governance: steps 2 and 3 sit behind Ring 3 in the app's privilege model and require explicit user enablement per session. `FRIDAY_OS_MODE=1` makes the app refuse to `pip install` into its own venv outside an overlay session, and skill dependencies are installed into a per-skill venv under `@workshop/envs/<skill>/` or, P1, a Podman container per skill. This is the forced answer to `KNOWN_ISSUES.md` §3: a skill is data; its dependencies are isolated environments; the OS layer is code.

---

## 13. Required changes in `Agent-Friday` (upstream PRs)

Friday Linux consumes `Agent-Friday` at a tag. These PRs land upstream first, in this order, each behind `FRIDAY_OS_MODE` where behaviour changes, so Windows users see no difference. Each PR ships with tests that run in the existing CI matrix (`windows-latest`, `ubuntu-latest`) plus a new `os-mode` job (PR-8). File references are to `src/agent_friday/` at the current `main`.

**PR-1 Path consolidation.** Create `core/paths.py` exporting `friday_home()`, `models_dir()`, `runtime_dir()`, `voice_assets_dir()`, each reading its env var (`FRIDAY_HOME`, `FRIDAY_MODELS_DIR`, `FRIDAY_RUNTIME_DIR`, `FRIDAY_VOICE_ASSETS`) with the current defaults. Replace every `Path.home() / ".friday"` with `friday_home()`. Twenty-two files currently hardcode it: `cli.py`, `ui/liquid_ui.py`, `friday_tray.py`, `services/distributions.py`, `services/extension_security.py`, `services/egress_gate.py`, `services/subagents.py`, `services/model_catalog.py`, `services/recipes.py`, `services/model_discovery.py`, `services/provider_registry.py`, `services/hints.py`, `governance/proof_of_integrity.py`, `skillopt_engine.py`, `epistemic_engine.py`, `source_trust_federation.py`, `dynamic_rings.py`, `people_graph.py`, `source_trust_graph.py`, `privacy/vault_crypto.py`, `privacy/vault_encrypt_migrate.py`, `cognitive_memory.py`, `setup_wizard.py`. Acceptance: `grep -r 'Path.home() / ".friday"' src` returns nothing; the test suite passes with `FRIDAY_HOME` pointed at a temp directory.

**PR-2 OS mode switch.** `FRIDAY_OS_MODE=1` changes defaults in one place (`core/os_mode.py`) that other modules query: credential store strictness (PR-5), engine search path (PR-4), tray disabled, `FRIDAY_LOG_TARGET=stdout` routes logging to stderr in journald-friendly single-line format, computer-control tools reported as unavailable by `services/capability_preflight.py` with the reason "no desktop to control in kiosk mode", `_open_app` in `services/agent.py` answers honestly that no applications are installed, clipboard tool disabled, voice asset lookup checks `FRIDAY_VOICE_ASSETS` before downloading. Acceptance: starting the server with `FRIDAY_OS_MODE=1` on Ubuntu with no Windows-only package installed reaches `/api/health` 200; the tool registry sent to the model contains no computer-control tools.

**PR-3 Packaging.** Move `data/` and `skills/` into the package as `agent_friday/seed/` (package data) and add a first-run step that copies seed skills into `friday_home()/skills` when absent, so `pip install "agent-friday @ git+https://github.com/FutureSpeakAI/Agent-Friday@<tag>"` yields a working install. Commit a `uv.lock`. This resolves `KNOWN_ISSUES.md` §3 with the decision from Section 12: a skill is data. Acceptance: a fresh venv installed from a git tag, not a clone, runs the career pipeline smoke test the KNOWN_ISSUES entry describes.

**PR-4 Residency on Linux.** In `services/residency_arbiter.py`: replace the four PowerShell invocations (`_alive`, `_listening_ports`, the `Win32_Process` name filter, `_seat_num_ctx`) with `psutil`; make `_ollama_llama_server()` the Windows default of `FRIDAY_LLAMA_SERVER_BIN` and implement the colon-separated search with per-boot probing (Section 9.1); gate `_POPEN_FLAGS` and `CREATE_NO_WINDOW` on `sys.platform` (already done in `hardware_profile.py`, not everywhere). In `services/hardware_profile.py`: add the Vulkan probe and the `backend` field (Section 9.2); make per-process attribution Linux-first; add the roaming fingerprint cache (Section 9.3). In `services/residency_policy.py`: keep the unified-memory refusal (Apple silicon is out of scope) but add the degraded posture (Section 9.5) under OS mode. Acceptance: on an Ubuntu machine with an NVIDIA card and a `llama-server` binary on the search path, a seat loads, answers on its port, and is killed by the arbiter; on a machine with no NVIDIA card but a Vulkan device, `detect_gpus()` returns it with `backend: vulkan`; unit tests mock `psutil` and `vulkaninfo` output.

**PR-5 Credentials.** In `services/credential_store.py`: consult `keyring` (already used by `services/vault_passphrase.py`) before DPAPI; under OS mode, require the vault key and fail closed with a clear error instead of writing plaintext (the current fallthrough at the `WARNING: no FRIDAY_PASSWORD and no DPAPI` branch). Verify that `core/__init__.py`'s persisted random `FRIDAY_SECRET_KEY` path is used when the env var is absent, and document it in `KNOWN_ISSUES.md` §7 if the "known default" claim there is stale. Acceptance: with `FRIDAY_OS_MODE=1` and no `FRIDAY_PASSWORD`, storing a key raises and nothing is written; with `FRIDAY_PASSWORD` set, the blob carries the vault magic; on Ubuntu with a Secret Service backend, the keyring path is exercised in tests via the `keyring` null/in-memory backend.

**PR-6 Health contract.** `/api/health` gains a documented schema: `{status: ok|degraded|failed, boot_critical_ok: bool, subsystems: {name: {ok, detail}}, version, deployment}`. Boot-critical subsystems are: config loaded, credential store readable, memory database opens, HTTP serving. Model seats, voice, and cloud providers are non-critical. `friday health --exit-code` returns 0 only when `boot_critical_ok` is true. A health check that cannot actually fail is a bug; every subsystem check must have a test that makes it fail. Acceptance: greenboot's `30-health.sh` (Section 11.2) consumes this endpoint unchanged.

**PR-7 Web-first setup.** The console prompts in `setup_wizard.py` are already mirrored by `/api/setup/status`, `/api/setup/skip`, `/api/setup/complete` and `/api/onboarding/*` in `routes/core_routes.py`. Under OS mode the console path is disabled, the passphrase and vault steps are skipped (the OS owns them), and a `GET /api/setup/os-handoff` reports what the OS wizard already collected so the app's onboarding does not ask again. Acceptance: with `FRIDAY_OS_MODE=1` and the handoff file present, the onboarding flow asks only personality and provider questions.

**PR-8 CI.** Add an `os-mode` job on `ubuntu-latest` that runs the suite with `FRIDAY_OS_MODE=1`, `FRIDAY_HOME=$RUNNER_TEMP/home`, no `[windows]` extra installed. Add `macos-latest` to the matrix as a separate, allowed-to-fail job so the Mac port has a signal (unrelated to the OS; cheap to add now). Acceptance: both jobs green on the PR.

**PR-9 Notifications.** `notifications.py` produces payloads (`to_os_toast`); add a Linux sink that calls `notify-send` when a D-Bus session exists, and no-op otherwise. In kiosk mode the UI's own notification surface is primary. Acceptance: unit test with a fake `notify-send` on PATH.

**PR-10 System panel and `friday os` bridge.** New blueprint `routes/os_routes.py`, registered only under OS mode and bound to loopback, exposing: `GET /api/os/status` (from `bootc status --json`), `POST /api/os/update/check`, `POST /api/os/update/apply-on-reboot`, `POST /api/os/rollback`, `POST /api/os/reboot`, `POST /api/os/poweroff`, `GET/POST /api/os/lan` (the LAN toggle), `POST /api/os/overlay` (Section 12, Ring 3), `POST /api/os/diagnostics`, `GET /api/os/journal?unit=&lines=`. The Python side shells to a single setuid-free helper, `/usr/libexec/friday/friday-os-helper`, invoked through `sudo` with a `sudoers.d` rule limited to that binary's subcommands; the helper lives in this repo (Section 14) and is the only privileged surface. The UI gets a Settings → System panel reading these routes; the tray's responsibilities (restart, logs) move here. Acceptance: every route returns 404 when OS mode is off; the helper rejects any argument not in its allowlist; a test proves the sudoers rule cannot be used to run anything else.

Order of landing: PR-1, PR-3, PR-2, PR-5, PR-6, PR-4, PR-7, PR-9, PR-10, PR-8 alongside each. Friday Linux M0 (Section 15) can start on `main` with PR-1 through PR-3 merged; M2 needs PR-4 through PR-6; M4 needs the rest.

---

## 14. Repository layout for `Friday-Linux`

```
Friday-Linux/
├── Containerfile                  # FROM <ublue base>@sha256:...; installs Section 6
├── build/
│   ├── agent-friday.lock          # uv lockfile for the app venv
│   ├── agent-friday.pin           # tag or commit of Agent-Friday
│   ├── disk.toml                  # bootc-image-builder disk customisations (Section 5)
│   ├── llama.cpp.pin              # tag of ggml-org/llama.cpp
│   └── build-llama.sh             # builds -cuda and -vulkan in the CUDA and Fedora containers
├── image/
│   ├── systemd/                   # all units, timers, mounts from Section 8
│   ├── greenboot/required.d/      # Section 11.2
│   ├── firstboot/                 # the wizard: Python + static HTML, no framework beyond the stdlib
│   ├── polkit/                    # NetworkManager rule for user friday
│   ├── sudoers.d/friday-os-helper
│   ├── nftables/friday.nft
│   ├── chromium/policies/managed/friday.json
│   ├── caddy/Caddyfile
│   ├── etc/friday/os.env
│   ├── splash/                    # static status page
│   └── voice/                     # fetched at build, not committed: Piper voice, whisper small.en
├── helper/
│   └── friday-os-helper/          # Python, argparse, strict subcommand allowlist; installed to /usr/libexec/friday/
├── cli/
│   └── friday_os/                 # `friday os` subcommands (status, update, rollback, overlay, preload, diagnostics, restore-home, install-to-disk)
├── ci/
│   ├── build.yml                  # build, sign, push (GHCR), size check
│   ├── boot-test.yml              # QEMU/KVM boot with OVMF, unattended file, /api/health assertion
│   ├── rollback-test.yml          # fault-injected image, greenboot rollback assertion
│   ├── weekly-rebuild.yml
│   └── promote.yml                # testing → stable with manual approval
├── scripts/
│   ├── write-image.sh             # Linux/macOS: dd with sanity checks (refuses non-removable targets)
│   └── write-image.ps1            # Windows: guidance for Rufus in DD mode, plus a checksum verify
├── tests/
│   ├── hardware-checklist.md      # Section 16.3
│   └── unit/                      # helper and wizard tests
├── docs/
│   ├── INSTALL.md  HARDWARE.md  SECURITY.md  BOM.md  DECISIONS.md  MILESTONES.md  VERIFY.md  UPDATES.md
│   └── TRADEMARKS.md              # "built on Fedora" wording; no Fedora or NVIDIA marks in branding
└── LICENSE (MIT for this repo; third-party licences enumerated in docs/BOM.md)
```

The `friday os` CLI is a separate package in this repo, installed into the same venv as the app, so `friday os ...` works through the app's `friday` entry point via a registered subcommand group (the app's `cli.py` gains a plugin hook in PR-10).

---

## 15. Milestones and acceptance criteria

Each milestone ends with an entry in `docs/MILESTONES.md` containing the exact commands run, their output, and the image digest tested.

**M0: Scaffold and first boot (no GPU).**
Deliverables: Containerfile on the pinned base with the app venv, `llama-server-vulkan` only, systemd units, a stub wizard that only creates the lockbox from the unattended file, greenboot checks, CI build and boot test.
Acceptance:
- [ ] `podman build` succeeds; image pushed to `ghcr.io/futurespeakai/friday-linux:testing`, signed.
- [ ] `bootc-image-builder` produces a raw image ≤ 8 GB compressed.
- [ ] QEMU/KVM with OVMF boots it with `friday-unattended.yaml`; `/api/health` returns 200 with `boot_critical_ok: true` within 300 s over a port forward.
- [ ] `bootc status` shows one deployment; `/usr` is read-only (`touch /usr/x` fails).
- [ ] Lockbox exists, is LUKS2 with Argon2id, and holds the five subvolumes.

**M1: First-boot wizard, kiosk, rollback.**
Deliverables: the full wizard (Section 7.3) with unattended mode, cage plus Chromium kiosk with policies, splash page, Caddy on loopback, greenboot rollback proven.
Acceptance:
- [ ] Interactive wizard completes on R3 with a virtual display; layout chosen before passphrase; initramfs keymap matches (test with a non-US layout and a passphrase containing layout-sensitive characters).
- [ ] Kiosk reaches the app; mic permission is granted by policy (verified by the browser's permission state, not by a prompt appearing).
- [ ] Rollback test: build an image whose `friday.service` has a deliberately wrong `ExecStart`; stage it as an update; boot; greenboot rolls back; the previous deployment boots and `/api/health` is 200. Ten consecutive trials in CI.
- [ ] `friday os status`, `rollback`, `reboot`, `poweroff`, `diagnostics` work through the helper; the helper rejects an unlisted subcommand with exit 2.
- [ ] G2 no-trace test passes in QEMU with a second attached disk containing a fake Windows layout.

**M2: NVIDIA reference machine.**
Deliverables: `llama-server-cuda`, MOK enrollment step, residency seats on the OS, local voice loop, PR-4 through PR-6 merged upstream.
Acceptance (on R1):
- [ ] Secure Boot on; enrollment completes; `nvidia-smi` works after the second boot.
- [ ] The wizard's plan step proposes `gemma4:12b`; consent record written; download verified by hash.
- [ ] A seat loads fully on the GPU; generation ≥ 40 tok/s (G6); seat is killed cleanly on service stop (no orphan `llama-server`).
- [ ] Voice round trip (speak, transcribe locally, answer, speak) works in the kiosk with no cloud key.
- [ ] G1 cold boot to accepting a message ≤ 120 s, measured three times.

**M3: Roaming.**
Deliverables: fingerprint cache, degraded posture, Vulkan path exercised, `friday os preload`.
Acceptance:
- [ ] Same stick on R1 then R2: different tiers selected with no manual step; R1's plan restored from cache on return.
- [ ] R2 with no discrete GPU boots into the degraded posture with the banner; a CPU seat answers.
- [ ] If R2 has an AMD or Intel GPU: `backend: vulkan` seat loads and answers.
- [ ] `friday os preload --from` provisions a model offline with hash verification.

**M4: Hardening, updates, install-to-disk, docs.**
Deliverables: LAN toggle with auth, update channels and promotion workflow, `friday os install-to-disk` (whole-disk, TPM2-bound passphrase fallback), `friday os restore-home`, `docs/*` complete, hardware checklist run on R1 and R2, weekly rebuild live.
Acceptance:
- [ ] LAN off by default; with LAN on, an unauthenticated request from another host is refused; `friday.local` resolves (Avahi) when on.
- [ ] `testing` → `stable` promotion requires the manual approval; a stable machine ignores testing images.
- [ ] Install-to-disk on R2 wipes only the chosen disk after a typed confirmation of the device model string; the installed system boots with TPM2 auto-unlock and accepts the passphrase when the TPM is reset.
- [ ] `docs/HARDWARE.md` lists R1 and R2 with measured numbers.

P1 items (post-v1, tracked in `docs/ROADMAP.md`): screen lock, Bluetooth pairing UI, captive portal window, Friday-owned MOK key, per-skill Podman environments, low-battery seat release, unclean-unmount repair, offline preload from a second Friday over LAN, Syncthing, restic backup target, CUPS. P2: minimal desktop session, multi-monitor, nftables rendering of the egress gate, accessibility (Orca) and full localisation, aarch64.

---

## 16. Test plan

### 16.1 Continuous

- App unit and integration suites run upstream (PR-8 adds `os-mode`).
- This repo: helper and wizard unit tests; Containerfile lint; SELinux policy check that every Friday unit runs in the expected context; a test that `/etc/containers/policy.json` rejects an unsigned image.

### 16.2 Image boot tests in CI DECIDED

GitHub-hosted Ubuntu runners expose KVM. `ci/boot-test.yml` runs `qemu-system-x86_64` with OVMF (Secure Boot off in CI; the MOK step is hardware-only), 8 GB RAM, the raw image, a second blank disk, and `-nic user,hostfwd=tcp::3000-:3000`, with `friday-unattended.yaml` injected into the ESP. Assertions: health within 300 s, sealed `/usr`, lockbox layout, no-trace hash on the second disk. `ci/rollback-test.yml` stages the fault-injected image over a good one and asserts the rollback (M1).

### 16.3 Hardware checklist (`tests/hardware-checklist.md`, run per machine, results into `docs/HARDWARE.md`)

Boot from USB with Secure Boot on; MOK enrollment; Wi-Fi join in the wizard; passphrase with a non-US layout; GPU detected and backend chosen; ladder tier proposed; download consent recorded; seat loads; tok/s at 512-token generation; voice round trip; suspend and resume with a seat loaded; clean shutdown; pull the stick; Windows boots normally; Windows clock correct; second Friday boot restores the plan from cache; `friday os diagnostics` produces a redacted bundle.

### 16.4 Security checks before each stable promotion

Signature verification of the promoted digest; `nft list ruleset` matches the committed ruleset; no unit runs with `SELinux permissive`; a scan of the image for private keys and known secret patterns; `secrets.env` permissions; Chromium policy file matches the committed one.

---

## 17. Open questions

| # | Question | Owner | Blocking? | Default |
|---|---|---|---|---|
| Q1 | Offer a printable LUKS recovery key in the wizard? | Stephen | No | Yes, opt-in, shown once |
| Q2 | Ship a "loaded stick" artifact with weights pre-downloaded, or only the lean image plus `preload`? | Stephen | No | Lean image only; `preload --from` for offline |
| Q3 | Include ROCm userspace in the image for AMD compute, at several GB, or stay Vulkan-only? | Stephen | No | Vulkan-only in v1 |
| Q4 | Exact Universal Blue base image name and whether a kiosk-suitable NVIDIA variant exists | Executor (verify) | Yes for M0 | `fedora-bootc` + `akmods-nvidia` layering if not |
| Q5 | Fedora release to pin (44 at time of writing) | Executor (verify) | Yes for M0 | Current stable |
| Q6 | Trademark wording: "Friday Linux, built on Fedora" acceptable under the Fedora remix guidelines? | Stephen (read the guidelines) | No | Use "built on Fedora Linux" in docs only, no logos |
| Q7 | Should the LAN listener use Caddy's local CA (users install the CA on their phone) or a self-signed leaf the PWA pins? | Stephen | No | Local CA; document the phone install |
| Q8 | Who holds the offline release signing key and the future MOK key | Stephen | No for v1 | Stephen, hardware token |

---

## 18. Executor operating rules

1. Start by writing `docs/DECISIONS.md` with ADR-001 (bootc), ADR-002 (Universal Blue base), ADR-003 (no client hypervisor in v1), ADR-004 (lockbox created at first boot), ADR-005 (skills are data; OS layer is code), each with the rationale from this document, before writing the Containerfile.
2. Then write `docs/VERIFY.md` listing every external fact this spec assumes that you cannot check from the sandbox (image names, package names, `bootc-image-builder` disk customisation syntax, greenboot paths, GitHub runner KVM availability), with the verification command for each. Stephen runs these on his machine and returns the results before M0 is declared done.
3. Build M0 end to end before polishing anything. A booting image with a stub wizard beats a beautiful wizard on an image that does not boot.
4. Keep the Containerfile readable: one `RUN` per concern, comments stating why a package is present, and the pin file read at build time so a version bump is a one-line diff.
5. Every unit file, policy file and script carries a header comment naming the section of this spec it implements.
6. Upstream PRs (Section 13) are opened against `Agent-Friday` as separate branches, each with its own tests, in the stated order. Do not vendor patches into this repo to avoid the upstream PR; the app is consumed at a tag.
7. When something in the spec cannot work as written (a package does not exist, a systemd directive conflicts with SELinux), do the smallest thing that preserves the intent, record it in `docs/DECISIONS.md` under "Deviations", and continue.
8. Report at the end of each milestone: what passed, what was deviated, what is in `docs/VERIFY.md` awaiting a human, and the image digest.

---

## Amendment A1 (30 Aug 2026): decouple M0 from upstream PRs

- `build/agent-friday.pin` points at the `v5.7.0` tag. Recorded as Deviation D-A1.
- Until PR-3 lands, the Containerfile clones Agent-Friday at the pin, installs it
  editable into `/usr/lib/friday/venv`, and copies `data/` and `skills/` to
  `/usr/share/friday/seed/`; `friday-firstboot` copies the seed into `FRIDAY_HOME` when
  absent. Deployment step, not a patch; removed when PR-3 lands.
- Until PR-2 lands, `os.env` keeps `FRIDAY_OS_MODE=1` (inert) and `secrets.env` supplies
  `FRIDAY_PASSWORD`. The model's tool registry may still list computer-control tools
  until PR-2; accepted for M0 and M1, recorded in `docs/VERIFY.md`.
- M0 acceptance: `/api/health` returns HTTP 200 within 300 s. The `boot_critical_ok`
  contract (PR-6) moves to M2; greenboot `30-health.sh` checks status code only until then.
- PR-1 is not an M0 blocker; it remains required before M4.
- Build and boot environment: WSL2 Ubuntu with rootful podman, bootc-image-builder,
  and QEMU with KVM via nested virtualization, or GitHub Actions `ubuntu-latest` once a
  remote exists. The Windows host is not a build environment.
- Q4 and Q5 are resolved by the executor with `skopeo inspect` against ghcr.io before any
  build; results go to `docs/VERIFY.md`, the digest into the Containerfile.

---

*End of specification v0.1, as amended by A1.*
