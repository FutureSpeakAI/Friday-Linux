# Friday Linux — SPEC.md §4.1 (base image), §6 (bill of materials)
#
# STATUS (2026-08-30): `podman build` succeeds end to end on GitHub Actions
# `ubuntu-latest` (CI run 33320159178, image c1a3e545cee4 — see
# docs/MILESTONES.md). Q4/Q5 resolved below; the venv-install step uses
# Amendment A1's workaround (docs/DECISIONS.md Deviation D-A1); two silent
# `torch`-pulling extras were found and removed (Deviations D-A3/D-A4). The
# llama-build stage below (llama-server-vulkan) is newly wired up this pass
# and not yet confirmed green in CI — that is this session's next check.
#
# One RUN per concern, per SPEC.md §18 rule 4, with the pin files read at
# build time so a version bump is a one-line diff outside this file.

# RESOLVED (SPEC.md §17 Q4, docs/VERIFY.md, checked via registry API 2026-08-30):
# ublue-os/base-nvidia is DEAD — its newest tag is from 2023, Fedora 37. Its
# sibling base-main IS live (current tag "44", updated daily), but it carries
# no NVIDIA variant. So ADR-002's own fallback applies: fedora-bootc directly,
# with akmods-nvidia layered in later for GPU milestones (M2+) rather than in
# this base image. Fedora 44 confirmed current stable: fedora-bootc:latest
# and fedora-bootc:44 share the same digest below (registry-verified, not
# guessed). akmods-nvidia's newest available kmod build targets
# "coreos-stable-42" / "centos-10" kernels only — NOT Fedora 44 — so it
# cannot be layered onto this pin as-is. That mismatch doesn't block M0
# (no GPU, per SPEC.md §15), but IT BLOCKS M2 (NVIDIA reference machine)
# until one of: (a) Universal Blue publishes an akmods-nvidia build for
# Fedora 44, (b) this project's base pin moves back to Fedora 42 to match
# akmods-nvidia's current kmod, or (c) a different NVIDIA kmod source is
# used. Flagging now rather than waiting for M2 to discover it. Recorded in
# full, with the actual registry queries and their output, in docs/VERIFY.md.
# ── Builder stage: llama-server-vulkan (§6 "Inference", §14 build-llama.sh) ──
# Multi-stage so the compiler toolchain, llama.cpp's source tree, and Vulkan
# -devel headers never land in the shipped image — only the built binaries
# get COPYed into the final stage below. Uses the same digest-pinned Fedora
# 44 base as the runtime image (confirmed to have working dnf/repos in the
# runtime-stage build already) rather than introducing a second, unverified
# base image reference.
#
# UNVERIFIED (see build/build-llama.sh's own header and docs/VERIFY.md): the
# exact Fedora 44 package names for Vulkan headers/loader-devel and the
# GLSL-to-SPIR-V shader compiler llama.cpp's Vulkan backend needs at build
# time. Best-effort list below; CI's dnf install step is the real check.
FROM registry.fedoraproject.org/fedora-bootc:44@sha256:e8f93cc9b1a0089216c674d5d9e8319e8cc40911dc9ee23d07d49ceea5177590 AS llama-build
RUN dnf install -y \
        git cmake gcc-c++ make \
        vulkan-headers vulkan-loader-devel vulkan-tools \
        glslc spirv-headers-devel glslang-devel \
    && dnf clean all
COPY build/llama.cpp.pin   /tmp/llama.cpp.pin
COPY build/build-llama.sh  /tmp/build-llama.sh
RUN chmod +x /tmp/build-llama.sh && \
    /tmp/build-llama.sh /tmp/llama.cpp.pin /out /tmp/llama.cpp

# ── Runtime stage ─────────────────────────────────────────────────────────
FROM registry.fedoraproject.org/fedora-bootc:44@sha256:e8f93cc9b1a0089216c674d5d9e8319e8cc40911dc9ee23d07d49ceea5177590

# ── System packages (§6 "System") ────────────────────────────────────────
# Package names are UNVERIFIED against Fedora repos — see docs/VERIFY.md
# "Fedora package availability." `caddy` in particular may need a COPR.
#
# Two additions beyond §6's literal list, both needed for the first-boot
# wizard's real M0 implementation (image/firstboot/wizard.py), recorded in
# docs/DECISIONS.md rather than silently added:
# - `gdisk` (provides `sgdisk`): §5/ADR-004 say the lockbox partition is
#   created "at first boot" on whatever free space exists beyond the
#   shipped image's own partitions; sgdisk is the scriptable way to add
#   that GPT partition without a human running `parted` interactively.
# - `python3-pyyaml`: image/firstboot/wizard.py parses friday-unattended.yaml
#   (§7.6) before friday.service (and therefore the app's own venv) exists,
#   so it needs its own YAML parser. The app venv is not on this script's
#   path by design (it should not depend on Agent-Friday's own dependency
#   set), so this is a small, torch-free, system-level addition — not a
#   §0 rule 7 concern.
RUN dnf install -y \
        linux-firmware \
        mesa-vulkan-drivers vulkan-loader vulkan-tools \
        NetworkManager NetworkManager-wifi \
        nftables \
        chrony \
        pipewire wireplumber pipewire-pulseaudio bluez \
        cage \
        chromium \
        caddy \
        greenboot \
        cryptsetup btrfs-progs gdisk \
        python3-pyyaml \
        google-noto-sans-fonts google-noto-emoji-color-fonts google-noto-sans-cjk-fonts \
    && dnf clean all

# avahi and cups are P1 (§6, §8.7) — not installed in v1.

# ── The `friday` user (§8.1, §5 mount plan) ──────────────────────────────
# Genuinely missing from every prior pass: friday.service, friday-caddy.service
# and friday-kiosk.service all specify User=friday/Group=friday, but nothing
# in this repo ever created that user or group — `systemctl start
# friday.service` would fail immediately at boot with "user friday does not
# exist," before any of §8's ReadWritePaths/DeviceAllow sandboxing even
# matters. Found by reading the units against the Containerfile, not by a
# CI failure yet — fixed here rather than waiting for the boot test to
# discover it the hard way. `-m` creates /home/friday now (build time); it
# is later shadowed by the lockbox's @home subvolume once the first-boot
# wizard mounts it there (normal, expected: the mountpoint's prior contents
# become invisible under the mount, not deleted). Supplementary groups match
# friday.service's SupplementaryGroups= line (§8.1); `video`/`render` exist
# in the base image via Mesa, `audio` via PipeWire.
#
# `mkdir -p /var/home` first: ostree's standard layout makes /home a
# symlink into /var/home (the same "/usr is the only truly immutable tree;
# /home, /root, /mnt, /opt, /srv live under /var" convention that already
# broke UV_CACHE_DIR's default path for /root earlier in this file — see
# that comment). /var exists as a real, if sparse, directory at build time
# (confirmed by that earlier fix), but /var/home does not until created,
# so `useradd -m -d /home/friday` would otherwise try to create a home
# directory through a symlink to a nonexistent target.
RUN mkdir -p /var/home && \
    useradd --create-home --home-dir /home/friday --shell /bin/bash \
        --groups video,render,audio friday \
    && passwd -l friday

# ── Build-time-only tooling for the venv-install step below ──────────────
# `git` (to clone Agent-Friday at the pin) and `uv` (to create the venv) are
# not part of §6's BOM — they are not needed once the venv exists — but
# Amendment A1's workaround needs both during the build itself. Installed in
# the same layer rather than a separate build stage for now: multi-stage
# would keep them out of the shipped image (worth doing before the G7 size
# budget gets tight), but that is a size-optimization deferred past M0's
# "does it build at all" bar, not a correctness requirement. Recorded here
# rather than silently left unaddressed.
RUN dnf install -y git uv && dnf clean all

# ── NVIDIA suspend services (§8.6) ───────────────────────────────────────
# DEFERRED TO M2: §4.1 assumed the base image ships the NVIDIA kmod/userspace
# (the base-nvidia variant). That variant is confirmed dead (docs/VERIFY.md,
# 2026-08-30 — newest tag is 2023/Fedora 37); this Containerfile now builds
# from plain fedora-bootc (no NVIDIA at all) for M0, which needs no GPU
# (SPEC.md §15). The previous pass here left a `COPY` of
# `image/systemd/nvidia-suspend-override.conf`, a file that was never
# authored — that made the build fail unconditionally on a missing build
# context path. Removed rather than stubbed: there is no `nvidia-suspend.service`
# to override without the driver, so an override file has nothing to attach
# to until M2 adds the NVIDIA layer (akmods-nvidia or otherwise — see the
# header's Q4 note on the Fedora-44/akmods-nvidia kernel mismatch that still
# needs resolving before that layer can be added). Recorded as Deviation
# D-A2 in docs/DECISIONS.md.

# ── Inference binaries (§6 "Inference") ──────────────────────────────────
# M0 needs llama-server-vulkan only (SPEC.md §15: "no GPU"). llama-server-cuda
# is M2 scope (needs a CUDA-toolkit builder image and compute-capability
# flags per §6, neither of which exists yet) and is deliberately not built
# here — copying it in would be presenting an unbuilt binary as done.
COPY --from=llama-build /out/llama-server-vulkan /usr/libexec/friday/llama-server-vulkan
COPY --from=llama-build /out/llama-quantize      /usr/libexec/friday/llama-quantize
COPY --from=llama-build /out/llama-gguf-split    /usr/libexec/friday/llama-gguf-split

# ── Voice assets (§6 "Voice") ─────────────────────────────────────────────
# NOT YET FETCHED. Piper voice name and Whisper small.en CTranslate2 INT8
# model version are both TBD — see docs/BOM.md "Voice assets".
# COPY image/voice/ /usr/share/friday/voice/

# ── Application venv (§6 "Application") ──────────────────────────────────
# Per Amendment A1 (docs/SPEC.md, Deviation D-A1 in docs/DECISIONS.md):
# PR-3's packaging work (installable from a git tag with no separate seed
# copy step) has not landed upstream, so `pip install ... @ git+...@<tag>`
# alone would not carry data/ or skills/ into the venv. Until PR-3 lands,
# this repo does that copy itself as a deployment step, not a vendored
# patch — clone the pinned tag in full, install it editable, then copy
# data/ and skills/ out to the seed location friday-firstboot reads from.
# Removed the moment PR-3 merges and build/agent-friday.pin moves past it.
COPY build/agent-friday.pin /tmp/agent-friday.pin
# HOME=/tmp and an explicit UV_CACHE_DIR sidestep a bootc-image quirk: /root
# in a Fedora bootc container is a symlink into /var/roothome, and /var is
# intentionally near-empty in the built image (it's state, populated by
# systemd-tmpfiles at first boot, not at build time) — so `uv`'s default
# cache path under $HOME/.cache resolves to a broken symlink target and
# `uv venv` fails with "failed to create directory `/root/.cache/uv`: File
# exists (os error 17)". Confirmed by CI run 33319416403. Using /tmp (a real
# directory in the build container) avoids the whole class of problem rather
# than trying to pre-create /var/roothome.
RUN AGENT_FRIDAY_TAG="$(grep -v '^#' /tmp/agent-friday.pin | head -1)" && \
    git clone --branch "${AGENT_FRIDAY_TAG}" --depth 1 \
        https://github.com/FutureSpeakAI/Agent-Friday.git /usr/lib/friday/src && \
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache uv venv /usr/lib/friday/venv && \
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache uv pip install --python /usr/lib/friday/venv/bin/python \
        -e "/usr/lib/friday/src[voice-local-lite,federation,google,compose,provenance]" && \
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache uv pip install --python /usr/lib/friday/venv/bin/python \
        "headroom-ai>=0.22" && \
    mkdir -p /usr/share/friday/seed && \
    cp -r /usr/lib/friday/src/data   /usr/share/friday/seed/data && \
    cp -r /usr/lib/friday/src/skills /usr/share/friday/seed/skills && \
    rm -rf /tmp/uv-cache /usr/lib/friday/src/.git
# The `rm -rf /tmp/uv-cache` above matters for more than tidiness: CI run
# 33321625110 ran the GitHub runner out of disk space a third time, this
# time on THIS layer, because UV_CACHE_DIR=/tmp/uv-cache writes every
# downloaded wheel into the build container's own filesystem, where it gets
# committed as part of the layer alongside the packages uv already
# extracted into the venv — roughly doubling this layer's on-disk footprint
# for no runtime benefit (the cache is never read again after this RUN
# exits). Removing it in the same RUN/layer (so it never appears in the
# layer's diff at all, rather than a later RUN which would still leave it
# in an earlier layer) fixes that. `.git` in the shallow clone is a much
# smaller second cleanup in the same spirit.
#
# Explicitly excluded per §6 and §18 rule 7 (prohibited shortcuts): the
# [windows] extra, and therefore pyautogui, pynput, and pystray.
#
# Deviation D-A3 (see docs/DECISIONS.md): §6's given extras list is
# "[voice-local-lite,local,compression,federation,google,compose,provenance]"
# — this Containerfile installs neither `local` nor Agent-Friday's
# `compression` extra as such; both silently pull `torch`, which §0 rule 7
# prohibits unconditionally. `local` = ["sentence-transformers>=2.2",
# "chromadb>=0.5"] (torch is sentence-transformers' own hard dependency).
# `compression` = ["headroom-ai[all]>=0.22"], and headroom-ai's `[all]` extra
# expands to `[code,evals,html,image,mcp,memory,ml,otel,proxy,relevance,
# reports,spreadsheet,voice]` — its `ml`, `voice` and `memory` extras each
# carry a `sys_platform != "darwin"` marker that is true on Linux regardless
# of CPU architecture, so `headroom-ai[all]` pulls torch + transformers +
# sentence-transformers on every Linux build, not just non-x86_64 ones. CI
# run 33319881454 confirmed torch/sentence-transformers/CUDA packages were
# STILL resolved after `local` alone was dropped, tracing to this second,
# independent source. Read `context_compressor.py` at the pinned tag
# (`from headroom import compress`, base-package call, degrades to
# passthrough on ImportError) to confirm the feature Agent-Friday actually
# uses needs none of headroom-ai's extras — so the fix installs bare
# `headroom-ai` (no extras: just tiktoken, pydantic, litellm, click, rich,
# opentelemetry-api, ast-grep-cli, pyyaml, tomlkit — no torch anywhere in
# that list) as a second, separate `uv pip install`, instead of routing
# through Agent-Friday's `compression` extra name at all. This is a choice
# about which OS-image dependency set Friday-Linux's own Containerfile
# installs, not a patch to Agent-Friday's code, so it doesn't need an
# upstream PR (§18 rule 6 is about vendoring source patches). Consequence:
# code/HTML/image-aware compression modes and headroom's proxy/agent-
# framework integrations are unavailable; the base JSON/text/prose
# compression `context_compressor.py` actually calls is unaffected.
# `local`'s on-device embeddings/memory capability remains genuinely absent
# from the M0 image — re-adding it needs either a torch-free embedding path
# (consistent with the ONNX choice already made for voice) or a decision
# from Stephen to relax rule 7, neither of which is this executor's call.
#
# UNVERIFIED: this repo does not commit a lockfile compatible with the A1
# workaround (build/agent-friday.lock does not exist yet — it was written
# for the PR-3 git-tag-install path, which this isn't using). Editable
# install from the full clone uses Agent-Friday's own pyproject.toml
# dependency pins instead of a lockfile for now; a real uv.lock for this
# path should be generated the first time this actually builds in CI,
# not guessed here. Flagged in docs/VERIFY.md.

# ── systemd units, config, and the OS layer (§8, §14) ────────────────────
COPY image/systemd/friday.service              /usr/lib/systemd/system/friday.service
COPY image/systemd/friday-lockbox.mount        /usr/lib/systemd/system/friday-lockbox.mount
COPY image/systemd/friday-caddy.service        /usr/lib/systemd/system/friday-caddy.service
COPY image/systemd/friday-kiosk.service        /usr/lib/systemd/system/friday-kiosk.service
COPY image/systemd/friday-firstboot.service    /usr/lib/systemd/system/friday-firstboot.service
COPY image/systemd/friday-boot-test-probe.service  /usr/lib/systemd/system/friday-boot-test-probe.service
COPY image/systemd/friday-boot-test-relay.service  /usr/lib/systemd/system/friday-boot-test-relay.service
COPY image/etc/friday/os.env                   /etc/friday/os.env
COPY image/greenboot/required.d/               /etc/greenboot/check/required.d/
COPY image/chromium/policies/managed/friday.json /etc/chromium/policies/managed/friday.json
COPY image/caddy/Caddyfile                     /etc/caddy/Caddyfile
COPY image/nftables/friday.nft                 /etc/nftables/friday.nft
COPY image/polkit/                             /etc/polkit-1/rules.d/
COPY image/sudoers.d/friday-os-helper          /etc/sudoers.d/friday-os-helper
COPY image/firstboot/                          /usr/share/friday/firstboot/
COPY image/splash/                             /usr/share/friday/splash/
COPY image/scripts/boot-test-relay.py          /usr/libexec/friday/boot-test-relay.py
COPY helper/friday-os-helper/                  /usr/libexec/friday/

# friday-kiosk.service is deliberately NOT enabled at M0: the milestone's own
# scope (SPEC.md §15) puts the real cage+Chromium kiosk experience at M1
# ("First-boot wizard, kiosk, rollback"), and its Caddyfile/TLS chain is
# still a first-draft (docs/DECISIONS.md). The unit is still installed
# (present, disabled) so M1 only has to `systemctl enable` it — the same
# "installed but disabled" pattern §10.2 already uses for sshd. Its
# greenboot check (40-kiosk.sh) is expected to fail at M0 for the same
# reason; not chased here, since M0's own acceptance list (SPEC.md §15) does
# not require it and greenboot's rollback path only bites established/staged
# deployments, not this image's first-ever boot (recorded in
# docs/VERIFY.md — genuinely unverified from this sandbox either way).
#
# friday-boot-test-probe.service and friday-boot-test-relay.service are new,
# not named in SPEC.md: both are ConditionPathExists-gated on
# /var/lib/friday/.provisioned-unattended (written only by the wizard when it
# actually consumes a friday-unattended.yaml — i.e., only in unattended/CI
# provisioning, never on a normal interactive install), so they are always
# enabled but are a silent, zero-cost no-op on every real deployment. See
# their own file headers and docs/DECISIONS.md for why they exist: M0's
# acceptance checklist (SPEC.md §15) needs to observe `bootc status`, a
# `/usr` write-test, and reach /api/health from OUTSIDE the guest in a
# headless GitHub Actions QEMU boot with no SSH server enabled (§10.2) and
# friday.service bound to loopback only (§8.1) — this is how that observation
# happens without adding any permanent, always-on attack surface.
RUN systemctl enable friday-lockbox.mount friday.service friday-caddy.service \
        friday-firstboot.service friday-boot-test-probe.service \
        friday-boot-test-relay.service nftables.service \
    && chmod 440 /etc/sudoers.d/friday-os-helper \
    && chmod 0755 /usr/libexec/friday/friday-os-helper \
    && chmod 0755 /usr/libexec/friday/boot-test-relay.py \
    && chmod 0755 /usr/share/friday/firstboot/wizard.py \
    && chmod 0755 /etc/greenboot/check/required.d/*.sh
# Executable bits above are set explicitly rather than relied on from the
# checkout: this repo is authored from a Windows sandbox, where Git does
# not preserve the Unix execute bit (every file lands as 100644 in the
# git tree regardless of a local `chmod +x`). Confirmed via `git ls-files
# -s` after committing — see docs/DECISIONS.md.

# No SSH host keys are generated at build time (§10.2): the unit is present
# and disabled, matching "SSH server installed but disabled with no host
# keys generated."
RUN systemctl disable sshd.service

# ── Prohibited-shortcut guard (SPEC.md §0 rule 7) ────────────────────────
# Not a real check yet — a placeholder for the CI lint step named in
# docs/DECISIONS.md's not-yet-written CI section: no service may bind
# non-loopback by default, SELinux stays enforcing, no torch, no telemetry.
