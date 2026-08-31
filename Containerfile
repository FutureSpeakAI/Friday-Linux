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
        policycoreutils-python-utils \
        jq \
        google-noto-sans-fonts google-noto-emoji-color-fonts google-noto-sans-cjk-fonts \
    && dnf clean all
# jq (B5, 2026-08-31): needed by the restored greenboot 30-health.sh, which
# parses boot_critical_ok out of the real JSON body now that PR-6 has landed
# — see that script's own header for the full history of why it was
# checking the HTTP status code alone until now.

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
# friday.service's SupplementaryGroups= line (§8.1).
#
# CORRECTED TWICE (CI runs 33334408813 and 33335275371, real failures, not
# guessed): the original version of this comment assumed `video`/`render`/
# `audio` already exist via Mesa/PipeWire's package scriptlets. They do
# not, at this point in a container build — `useradd: group 'video' does
# not exist` (and same for `render`, `audio`). The first fix tried,
# `groupadd -f video` (idempotent-by-design: exits 0 if the group already
# exists), produced NO output at all (groupadd is silent on every success
# path) and yet `useradd` immediately after still reported all three
# groups missing — meaning `groupadd` itself believed it succeeded (or
# had nothing to do) while `useradd`'s own NSS lookup could not see the
# result. Rather than guess a second time at why (a plausible but
# unconfirmed theory: some of these groups exist only via `nss-systemd`'s
# dynamic-user mechanism, which requires a running systemd instance to
# resolve — absent inside a `podman build` layer — so `groupadd -f` treats
# them as "already there" via that same broken lookup, silently skips
# real creation, and `useradd`'s classic NSS "files" path then finds
# nothing), this fix bypasses the ambiguity entirely: append directly to
# `/etc/group` with a freshly computed, guaranteed-unused GID for any name
# not already present. This is materially the same file `groupadd` itself
# writes for a "files"-backed group — no NSS module indirection involved,
# so there is no dynamic-lookup path left for it to be invisible through.
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
    NEXT_GID=$(awk -F: '{print $3}' /etc/group | sort -n | tail -1) && \
    for g in video render audio; do \
        if ! grep -q "^${g}:" /etc/group; then \
            NEXT_GID=$((NEXT_GID + 1)); \
            echo "${g}:x:${NEXT_GID}:" >> /etc/group; \
            echo "created ${g} with GID ${NEXT_GID}"; \
        else \
            echo "${g} already present in /etc/group, not touching it"; \
        fi; \
    done && \
    tail -5 /etc/group && \
    useradd --create-home --home-dir /home/friday --shell /bin/bash \
        --groups video,render,audio friday \
    && passwd -l friday

# ── Lockbox outer-mount point (SPEC.md §5, image/systemd/friday-lockbox.mount) ──
# REAL BOOT FAILURE, CI run 33340378275: systemd refused
# friday-lockbox.mount at boot ("Where= setting doesn't match unit name")
# when Where= was /run/friday-lockbox. Confirmed against systemd's own
# source that the unit's literal name only round-trips to /friday/lockbox
# (see that unit file's own header for the full derivation) — moved
# Where= there. /friday/lockbox must exist as a real directory in the
# sealed image itself: mount does not need write access to its target at
# runtime (fine on read-only /), but it does need the directory to already
# exist, and nothing creates arbitrary new top-level directories on a
# read-only root at runtime.
RUN mkdir -p /friday/lockbox

# ── SELinux port label for friday.service's port (SPEC.md §8.1 FRIDAY_PORT) ──
# REAL BOOT FAILURE, CI run 33413256821 (found by reading the raw kernel
# audit lines in the captured console log directly — journald's own
# userspace status-line reporting had stopped working after the @journal
# remount, which is what made it look like the whole console had gone
# silent; the kernel's own audit/printk output kept flowing the entire
# time and had the real answer): friday.service starts successfully
# ("[ OK ] Started friday.service"), but the app can never actually serve
# on its port:
#   avc: denied { name_connect } for pid=1630 comm="friday" dest=3000
#   scontext=system_u:system_r:init_t:s0
#   tcontext=system_u:object_r:ntop_port_t:s0 tclass=tcp_socket
#   permissive=0
# SELinux is correctly enforcing (permissive=0 — not disabled, per §0
# rule 7 / §10.2, "SELinux enforcing, never permissive"). Port 3000 is
# pre-labeled `ntop_port_t` in the base policy (reserved by an unrelated
# tool's own policy module, "ntop"), not the generic `unreserved_port_t`
# an arbitrary high port would default to — colliding with Agent-Friday's
# own use of 3000 (SPEC.md §8.1 FRIDAY_PORT=3000). friday.service runs
# under the generic `init_t` domain (no dedicated SELinux type was ever
# created for it — a real gap worth reconsidering later, but the port
# label collision is the actual, sufficient blocker here). Fixed by
# relabeling port 3000 as `http_port_t`, the standard, broadly-permitted
# type for a real HTTP server port (which is exactly what this is — a
# Flask server) — `-a` (add) if the port has no override yet, falling
# back to `-m` (modify) since `ntop_port_t`'s existing explicit
# assignment means `-a` alone fails ("port already defined").
RUN semanage port -a -t http_port_t -p tcp 3000 \
      || semanage port -m -t http_port_t -p tcp 3000 \
    && semanage port -l | grep -w 3000

# ── Custom SELinux policy module (SPEC.md §8.1 FRIDAY_PORT) ─────────────
# REAL BOOT FAILURE, CI run 33420423832: the port relabel above was
# confirmed to take effect (the denial's own tcontext changed from
# ntop_port_t to http_port_t) but the connect was STILL denied — init_t
# (the domain friday.service's process actually runs in; see
# image/selinux/friday_network.te's header for the full finding) is not
# granted name_connect to ANY port type by Fedora's targeted policy by
# default. `checkpolicy` (provides `checkmodule`) added for this —
# `semodule_package`/`semodule` come from `policycoreutils`/
# `policycoreutils-python-utils`, already present above.
#
# REAL BUILD FAILURE, CI run 33424454295: checkmodule requires the source
# file's own base name (before the extension) to match the module name
# declared inside it (`module friday_network 1.0;`) — the file was
# originally named with a hyphen (`friday-network.te`), and checkmodule
# refused outright: "Module name friday_network is different than the
# output base filename friday-network". SELinux module names cannot
# contain hyphens, so the file (not the module declaration) was renamed
# to match, everywhere this Containerfile references it.
RUN dnf install -y checkpolicy && dnf clean all
COPY image/selinux/friday_network.te /tmp/friday_network.te
RUN checkmodule -M -m -o /tmp/friday_network.mod /tmp/friday_network.te \
    && semodule_package -o /tmp/friday_network.pp -m /tmp/friday_network.mod \
    && semodule -i /tmp/friday_network.pp \
    && semodule -l | grep -w friday_network \
    && rm -f /tmp/friday_network.mod /tmp/friday_network.pp /tmp/friday_network.te

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
# B5 (docs/SPEC.md dispatch, 2026-08-31): Amendment A1's seed-copy workaround
# is REMOVED here. PR-3 (merged upstream in Agent-Friday v5.9.0) moved
# data/ and skills/ into the installable package proper as
# agent_friday.seed.*, with the app's own ensure_seed_skills_installed()
# (called from cli.cmd_start()/setup_wizard.main()) copying them into
# friday_home()/skills on first run — no separate /usr/share/friday/seed/
# staging directory needed; confirmed nothing else in this repo ever read
# from that path (grepped before removing it, not assumed). A plain
# `pip install ... @ git+...@<tag>` now carries the seed data automatically,
# which is the whole point PR-3 shipped.
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
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache uv venv /usr/lib/friday/venv && \
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache uv pip install --python /usr/lib/friday/venv/bin/python \
        "agent-friday[voice-local-lite,federation,google,compose,provenance] @ git+https://github.com/FutureSpeakAI/Agent-Friday.git@${AGENT_FRIDAY_TAG}" && \
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache uv pip install --python /usr/lib/friday/venv/bin/python \
        "headroom-ai>=0.22" && \
    rm -rf /tmp/uv-cache
# The `rm -rf /tmp/uv-cache` above matters for more than tidiness: CI run
# 33321625110 ran the GitHub runner out of disk space a third time, this
# time on THIS layer, because UV_CACHE_DIR=/tmp/uv-cache writes every
# downloaded wheel into the build container's own filesystem, where it gets
# committed as part of the layer alongside the packages uv already
# extracted into the venv — roughly doubling this layer's on-disk footprint
# for no runtime benefit (the cache is never read again after this RUN
# exits). Removing it in the same RUN/layer (so it never appears in the
# layer's diff at all, rather than a later RUN which would still leave it
# in an earlier layer) fixes that.
#
# Explicitly excluded per §6 and §18 rule 7 (prohibited shortcuts): the
# [windows] extra, and therefore pyautogui, pynput, and pystray.
#
# UNVERIFIED, flagged not guessed: this is the first time this repo installs
# directly from a git tag reference rather than a local editable clone. If
# `pip`/`uv`'s git+https VCS install of agent-friday at this tag does not
# correctly resolve to a wheel/sdist that includes agent_friday/seed/ (PR-3's
# packaging relies on setuptools package-data declarations that a VCS
# install exercises differently than the editable-from-clone path this
# repo used before), that will surface as a real CI failure at this step or
# as a missing seed at first boot — read the real error before assuming
# which, per this project's own standing rule.
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
COPY image/systemd/friday-boot-test-probe-late.service /usr/lib/systemd/system/friday-boot-test-probe-late.service
COPY image/systemd/friday-boot-test-probe-late.timer   /usr/lib/systemd/system/friday-boot-test-probe-late.timer
COPY image/systemd/friday-boot-test-relay.service  /usr/lib/systemd/system/friday-boot-test-relay.service
COPY image/systemd/friday-boot-test-heartbeat.service /usr/lib/systemd/system/friday-boot-test-heartbeat.service
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
# friday-boot-test-probe.service, friday-boot-test-probe-late.
# service/.timer, and friday-boot-test-relay.service are new, not named in
# SPEC.md: all are ConditionPathExists-gated on
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
# friday-boot-test-probe-late.timer (not the .service — the timer is what
# needs [Install]/WantedBy=; it triggers the .service on its own schedule)
# exists because the early probe fires right after wizard.py exits, too
# soon to know whether friday.service (a full Python app) has actually
# finished starting — CI runs so far only ever saw a snapshot from
# seconds into boot. Fires once, 200s in, well inside boot-test.yml's
# 300s health-check window.
RUN systemctl enable friday-lockbox.mount friday.service friday-caddy.service \
        friday-firstboot.service friday-boot-test-probe.service \
        friday-boot-test-probe-late.timer \
        friday-boot-test-relay.service friday-boot-test-heartbeat.service \
        nftables.service \
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

# ── Disable bootc's generic-image auto-grow fallback (SPEC.md §5) ───────
# REAL FINDING, CI run 33353739418: root grew from the disk.toml-specified
# 16 GiB to fill the ENTIRE disk at every boot (confirmed via the boot
# probe's diagnostic: `bootc-generic-growpart.service - Bootc Fallback
# Root Filesystem Grow` started successfully; `systemd-repart.service`
# was independently confirmed as NOT the mechanism — its own log says
# "skipped, no trigger condition checks were met," since no
# /usr/lib/repart.d config exists in this image). `bootc-image-builder`
# invokes `bootc install to-filesystem --generic-image` internally (seen
# in its own manifest log), and that flag is what installs this fallback
# unit — it exists so a genuinely generic bootc image (no known target
# disk size) still fills whatever disk it lands on. SPEC.md §5/ADR-004
# want the opposite for Friday Linux specifically: a FIXED 16 GiB root
# with the remainder left for the first-boot wizard to claim as the
# lockbox. Masking (not just disabling) so nothing can start it via a
# dependency either — this is a deliberate, permanent product choice for
# this image, not a temporary workaround.
RUN systemctl mask bootc-generic-growpart.service

# ── Prohibited-shortcut guard (SPEC.md §0 rule 7) ────────────────────────
# Not a real check yet — a placeholder for the CI lint step named in
# docs/DECISIONS.md's not-yet-written CI section: no service may bind
# non-loopback by default, SELinux stays enforcing, no torch, no telemetry.
