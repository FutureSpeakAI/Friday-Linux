# Friday Linux — SPEC.md §4.1 (base image), §6 (bill of materials)
#
# STATUS: buildable for M0 (no GPU) as of 2026-08-30 — Q4/Q5 resolved below.
# Still blocked on one thing for the venv-install step, per Amendment A1:
# build/agent-friday.pin now points at v5.7.0 (a real, working tag), so this
# blocker is resolved for M0 too. See docs/DECISIONS.md "Deviation D-A1."
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
FROM registry.fedoraproject.org/fedora-bootc:44@sha256:e8f93cc9b1a0089216c674d5d9e8319e8cc40911dc9ee23d07d49ceea5177590

# ── System packages (§6 "System") ────────────────────────────────────────
# Package names are UNVERIFIED against Fedora repos — see docs/VERIFY.md
# "Fedora package availability." `caddy` in particular may need a COPR.
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
        cryptsetup btrfs-progs \
        google-noto-sans-fonts google-noto-emoji-color-fonts google-noto-sans-cjk-fonts \
    && dnf clean all

# avahi and cups are P1 (§6, §8.7) — not installed in v1.

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
# NOT YET BUILT. build/build-llama.sh builds llama-server-cuda and
# llama-server-vulkan from the pinned tag in build/llama.cpp.pin (currently
# also unpinned — see docs/VERIFY.md "ggml-org/llama.cpp tag to pin"). Until
# that pin exists this COPY has nothing to copy from; left here as the
# documented target per §14's layout rather than silently omitted.
# COPY --from=llama-build /out/llama-server-cuda   /usr/libexec/friday/llama-server-cuda
# COPY --from=llama-build /out/llama-server-vulkan /usr/libexec/friday/llama-server-vulkan
# COPY --from=llama-build /out/llama-quantize      /usr/libexec/friday/llama-quantize
# COPY --from=llama-build /out/llama-gguf-split    /usr/libexec/friday/llama-gguf-split

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
        -e "/usr/lib/friday/src[voice-local-lite,compression,federation,google,compose,provenance]" && \
    mkdir -p /usr/share/friday/seed && \
    cp -r /usr/lib/friday/src/data   /usr/share/friday/seed/data && \
    cp -r /usr/lib/friday/src/skills /usr/share/friday/seed/skills
#
# Explicitly excluded per §6 and §18 rule 7 (prohibited shortcuts): the
# [windows] extra, and therefore pyautogui, pynput, and pystray.
#
# Deviation D-A3 (see docs/DECISIONS.md): §6's given extras list is
# "[voice-local-lite,local,compression,federation,google,compose,provenance]"
# — this Containerfile installs everything in that list EXCEPT `local`.
# `local` = ["sentence-transformers>=2.2", "chromadb>=0.5"] per
# Agent-Friday's pyproject.toml at v5.7.0, and sentence-transformers hard-
# depends on torch + transformers. CI run 33319580279 resolved
# torch==2.13.0 plus a full CUDA wheel stack (nvidia-cublas, nvidia-cudnn,
# triton, etc.) the instant `local` was in the extras list, then ran the
# GitHub runner out of disk space trying to write them. §0 rule 7 prohibits
# "adding torch to the image" unconditionally, regardless of convenience,
# and §1.1 states plainly that local voice is CTranslate2/ONNX and the
# packaged product does not ship torch — so this is not a resource problem
# to work around, it is the DECIDED rule already telling us the right
# answer. `local`'s on-device embeddings/memory capability is therefore
# NOT in the M0 image; re-adding it needs either a torch-free embedding
# path (e.g. an ONNX sentence-embedding model, consistent with the ONNX
# path already used for voice) or a decision from Stephen to relax rule 7,
# neither of which is this executor's call to make unilaterally.
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
COPY image/etc/friday/os.env                   /etc/friday/os.env
COPY image/greenboot/required.d/               /etc/greenboot/check/required.d/
COPY image/chromium/policies/managed/friday.json /etc/chromium/policies/managed/friday.json
COPY image/caddy/Caddyfile                     /etc/caddy/Caddyfile
COPY image/nftables/friday.nft                 /etc/nftables/friday.nft
COPY image/polkit/                             /etc/polkit-1/rules.d/
COPY image/sudoers.d/friday-os-helper          /etc/sudoers.d/friday-os-helper
COPY image/firstboot/                          /usr/share/friday/firstboot/
COPY image/splash/                             /usr/share/friday/splash/
COPY helper/friday-os-helper/                  /usr/libexec/friday/

RUN systemctl enable friday-lockbox.mount friday.service friday-caddy.service \
        friday-kiosk.service friday-firstboot.service nftables.service \
    && chmod 440 /etc/sudoers.d/friday-os-helper \
    && chmod 0755 /usr/libexec/friday/friday-os-helper \
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
