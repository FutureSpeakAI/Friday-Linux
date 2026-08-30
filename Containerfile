# Friday Linux — SPEC.md §4.1 (base image), §6 (bill of materials)
#
# STATUS: not buildable yet. Blocked on two independent things, both
# recorded in docs/DECISIONS.md and docs/VERIFY.md:
#   1. Q4/Q5 (SPEC.md §17) — the exact base image ref below is UNVERIFIED,
#      per rule 5 never to be pinned by digest from memory.
#   2. build/agent-friday.pin is empty — PR-1/2/3 have not landed upstream
#      in Agent-Friday yet, so there is no tag/commit to install where
#      FRIDAY_OS_MODE does anything. See docs/DECISIONS.md "Blocking
#      dependency: PR-1/2/3 not yet merged upstream."
#
# One RUN per concern, per SPEC.md §18 rule 4, with the pin files read at
# build time so a version bump is a one-line diff outside this file.

# UNVERIFIED (SPEC.md §17 Q4, docs/VERIFY.md): exact Universal Blue image
# name and digest not yet confirmed with `skopeo inspect`. This is the
# NVIDIA-enabled variant of the minimal base per ADR-002; if it does not
# exist in kiosk-suitable form, ADR-002's fallback (fedora-bootc +
# akmods-nvidia) replaces this line and gets recorded in docs/DECISIONS.md.
FROM ghcr.io/ublue-os/base-nvidia:latest

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

# ── NVIDIA suspend services (§8.6) ───────────────────────────────────────
# The base image ships the NVIDIA kmod/userspace (§4.1); this only enables
# the suspend/resume units so loaded seats survive suspend
# (PreserveVideoMemoryAllocations=1 is set in the service override below).
COPY image/systemd/nvidia-suspend-override.conf /usr/lib/systemd/system/nvidia-suspend.service.d/override.conf

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
# BLOCKED: build/agent-friday.pin is intentionally empty. See the header
# comment above and docs/DECISIONS.md. This step cannot run until it is
# filled in with a real tag/commit that includes PR-1 through PR-3.
#
# RUN --mount=type=cache,target=/root/.cache/uv \
#     AGENT_FRIDAY_TAG="$(cat build/agent-friday.pin)" && \
#     uv venv /usr/lib/friday/venv && \
#     uv pip install --python /usr/lib/friday/venv/bin/python \
#         --requirement build/agent-friday.lock \
#         "agent-friday[voice-local-lite,local,compression,federation,google,compose,provenance] @ git+https://github.com/FutureSpeakAI/Agent-Friday@${AGENT_FRIDAY_TAG}"
#
# Explicitly excluded per §6 and §18 rule 7 (prohibited shortcuts): the
# [windows] extra, and therefore pyautogui, pynput, and pystray.

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
    && chmod 0755 /usr/libexec/friday/friday-os-helper

# No SSH host keys are generated at build time (§10.2): the unit is present
# and disabled, matching "SSH server installed but disabled with no host
# keys generated."
RUN systemctl disable sshd.service

# ── Prohibited-shortcut guard (SPEC.md §0 rule 7) ────────────────────────
# Not a real check yet — a placeholder for the CI lint step named in
# docs/DECISIONS.md's not-yet-written CI section: no service may bind
# non-loopback by default, SELinux stays enforcing, no torch, no telemetry.
