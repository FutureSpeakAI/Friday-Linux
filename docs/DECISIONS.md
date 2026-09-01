# Decisions

Per SPEC.md §18 rule 1, this file leads with the five required ADRs before
any Containerfile work. Per rule 2, challenges to DECIDED items go under
"Challenges" and do not change what gets built. Per rule 3, OPEN items (§17)
get their default recorded here when a milestone actually depends on one.
Per rule 7, deviations from the spec go under "Deviations."

## ADR-001: bootc as the build/update mechanism

**Decision:** One Containerfile builds three artifacts — an OCI image, a raw
disk image, and an installer ISO — via bootc, rather than a hand-rolled live
ISO with a persistent overlay.

**Rationale (§4.2):** Overlays corrupt when full and cannot roll back.
Atomic updates with rollback and greenboot health gating come with bootc for
free, and the same Containerfile serves the "container edition" use case
(any `podman` can run the OCI image directly) discussed for macOS/Windows
without a second build pipeline.

## ADR-002: Universal Blue base image, not raw `fedora-bootc`

**Decision:** Base on Universal Blue's Fedora Atomic images (`ghcr.io/ublue-os`
`base-main`/`base-nvidia` family), falling back to `fedora-bootc` +
`akmods-nvidia` layering if no kiosk-suitable NVIDIA-enabled minimal variant
exists.

**Rationale (§4.1):** Universal Blue already builds and signs NVIDIA kernel
modules for every Fedora kernel with Secure Boot enrollment tooling and
weekly rebuilds, proven in production by Bazzite and Bluefin. A one-person
shop should not build and sign NVIDIA kmods itself in v1. Cost: v1 users
enroll Universal Blue's MOK key, not a Friday-owned one (P1, §10.4).

**Path taken:** Not yet determined — blocked on VERIFY.md Q4/Q5 (image
name/digest, Fedora release). Whichever path is taken gets recorded here
before the Containerfile is written, per this ADR's own rule.

## ADR-003: no client hypervisor in v1

**Decision:** Friday Linux does not run the host's installed Windows or
macOS as a guest.

**Rationale (§1.1):** GPU contention, TPM/BitLocker friction, and Apple's
boot policy make that a separate, later, hardware-listed project. Bundling
it into v1 would mean solving three hard problems (GPU passthrough,
BitLocker-safe guest boot, Apple virtualization entitlements) before
shipping the sovereignty claim the OS actually exists to make.

## ADR-004: the lockbox is created at first boot, not shipped in the image

**Decision:** The shipped raw image contains only the OS (16 GiB fixed root).
The LUKS2 lockbox is created on the remaining space of the boot device
during the first-boot wizard.

**Rationale (§5):** Keeps the shipped image generic — no two sticks share
encryption metadata — and makes "grow to fill the drive" free regardless of
whether the drive is 128 GB or 2 TB. The alternative (pre-provisioning a
lockbox partition sized at build time) would force a choice of drive size
into the image itself.

## ADR-005: skills are data; the OS layer is code

**Decision:** Agent Friday's self-improvement (§12) may edit its own code in
`@workshop`, test it, and run it live via a transient `bootc usr-overlay`
that is discarded on reboot, promoting only through an upstream pull request
(§11.3). Skill dependencies install into per-skill venvs under
`@workshop/envs/<skill>/`, never into the app's own venv.

**Rationale:** This is the forced answer to `KNOWN_ISSUES.md` §3's problem —
skill dependency installation was untested and unbounded. Under
`FRIDAY_OS_MODE=1` the app is made to refuse `pip install` into its own venv
outside an overlay session (§12), so a skill cannot silently widen what code
runs sealed. A skill is data; the sealed `/usr` never changes except through
a signed image.

---

## Repo identity (not a spec item, but cost time before)

`C:\Users\swebs\Projects\Agent-Friday` is a dead Electron/TypeScript line
(package.json, vite.config.ts, tsconfig.json, node_modules — no Python, no
`services/`) sharing the `FutureSpeakAI/Agent-Friday` GitHub remote with the
real project but with no common git ancestor. The real source is
`C:\Users\swebs\Projects\friday-desktop`. See `docs/VERIFY.md` for the
confirmation commands and output.

## Challenges to DECIDED items

None. Nothing in the now-complete document contradicts a DECIDED item at the
decision level. The gap list below is about whether the current
`Agent-Friday` code already does what Section 13's upstream PRs propose to
make it do — which is a statement about *readiness*, not a disagreement with
the *decision*. Section 13 exists precisely because the gaps below were
already anticipated; reading the real code confirms the PRs are aimed at
real problems, not imagined ones.

## Gap list: what §13's upstream PRs assume vs. what `Agent-Friday` v5.7.0 actually contains

Kept per Stephen's instruction, since it is still the highest-value
early-verification work — it tells us which PRs are pointed at real code and
which specifics in the PR descriptions are already slightly off. Every
figure below was re-checked with `git show v5.7.0:<path>` against the real
`friday-desktop` checkout, not the `Agent-Friday` decoy.

- **PR-2's target, `core/os_mode.py`, does not exist at v5.7.0.** Confirmed
  (`git show v5.7.0:src/agent_friday/core/os_mode.py` → fatal: does not
  exist). Expected — PR-2 is the PR that creates it. Noted only because it
  means `FRIDAY_OS_MODE` currently does *nothing*: grepping the whole tree
  at v5.7.0 returns zero hits. Every "under OS mode, X changes" sentence in
  §§7-13 describes code that must be written from scratch, not code that
  exists and needs its default flipped.

- **PR-4's target, `FRIDAY_LLAMA_SERVER_BIN`, does not exist at v5.7.0.**
  Zero hits repo-wide. Confirms the engine-discovery mechanism in §9.1 is
  entirely new, not a rename of an existing variable. The thing it replaces
  is real and precisely as described: `services/residency_arbiter.py:337`
  (`ollama_engine_path()`, hardcoded `...\Ollama\lib\ollama\llama-server.exe`)
  and `:545` (`self.binary = ... / "llama-server.exe"` in the seat-spawning
  class) — both Windows-only paths, exactly as PR-4 states. `KNOWN_ISSUES.md`
  §6 confirms in prose: "On Linux, no llama-server seat can load at all (the
  engine candidates are `.exe`), so you are Ollama-only."

- **PR-4's GPU-probe target is confirmed exactly as described.**
  `services/hardware_profile.py:204` (`detect_gpus()`) shells out only to
  `nvidia-smi`; no Vulkan, AMD, or Intel probe exists anywhere in the file.
  The "Windows only for the moment" comment PR-4/§9.2 cites is real, at
  `hardware_profile.py:280`, on `live_display_mib()` — the function's own
  docstring says so verbatim: "Windows only for the moment... the reading
  comes from the OS performance counters instead." §9.2's claim that this
  "becomes Linux-first" is therefore a real rewrite, not a flag flip: the
  Linux replacement (`nvidia-smi --query-compute-apps`) needs its own
  implementation, since the current code path for Linux doesn't exist yet
  either.

- **PR-5's target line is exact.** `services/credential_store.py:151`:
  `print("[credstore] WARNING: no FRIDAY_PASSWORD and no DPAPI — credentials "...)`.
  PR-5 proposes making this fail closed under OS mode instead of falling
  through to plaintext. Separately, `services/vault_passphrase.py:305-343`
  (`store()`) is the *other* place this same class of gap lives — it writes
  to `keyring` if importable and to a DPAPI file if `dpapi_available()`
  (`os.name == "nt"`), and on Linux without `keyring` installed, both
  branches no-op and `store()` returns `[]`. PR-5 names `credential_store.py`
  specifically; whether it also intends to fix `vault_passphrase.py`'s
  identical failure mode isn't stated. Worth confirming before M2, since
  Section 6's BOM venv extras list (`[voice-local-lite,local,compression,
  federation,google,compose,provenance]`) still does not include `keyring`,
  and no Secret Service provider (`gnome-keyring`, gcr, etc.) appears in
  Section 6's system package list either — so even after PR-5 lands,
  `store()` has nowhere durable to write on Friday Linux unless both of
  those are also added. Flagging for M2 planning, not blocking M0.

- **PR-1's 22-file list checks out.** Verified every named file at v5.7.0
  contains some form of `Path.home() / ".friday"` (a couple use the split
  form `Path(friday_dir or Path.home() / ".friday")`, which is why a naive
  exact-string grep undercounts — checked each file individually and all 22
  are real hits). No stale entries, no missing ones found.

- **Ladder ownership, corrected.** §2 attributes the hardware ladder to
  `services/residency_policy.py`; the actual VRAM-tier → model-id table
  lives in `services/model_plan.py` (`MODELS` list, e.g.
  `model_plan.py:141` for `qwen3:4b`). `residency_policy.py` is the
  per-role placement/refusal engine (`plan()`, `ROLES`, `ROLE_RESIDENCY`)
  that consumes model sizes but does not define the tier table itself. This
  doesn't affect any §13 PR text, which correctly cites
  `services/residency_policy.py` for the *refusal/degraded-posture* logic
  (§9.5, PR-4) rather than the ladder — only §2's glossary entry is loose.
  Friday Linux code that needs the ladder itself (e.g. the wizard's plan
  step, §7.3 step 6) should read `model_plan.py`.

- **`pystray` aborts test collection when absent, unrelated to any PR.**
  Single unconditional `import pystray` at
  `src/agent_friday/friday_tray.py:21`. The `[windows]` extra gates it at
  install time and Friday Linux's extras list correctly excludes
  `[windows]`, so the *installed image* is unaffected. The gap is in the
  *test suite*: something under `tests/` imports `friday_tray` without a
  platform guard, so pytest collection aborts on Linux without `pystray`
  installed. PR-8 adds an `os-mode` CI job on `ubuntu-latest` with no
  `[windows]` extra — if this import guard isn't fixed first, that job
  cannot even collect tests. Worth surfacing to whoever picks up PR-8.

- **Deviation D-A2: removed the `COPY image/systemd/nvidia-suspend-override.conf`
  line from the Containerfile instead of authoring the file.** Found while
  actually trying to get `podman build` to succeed in CI (this repo's M0
  execution pass, 2026-08-30): the previous pass's Containerfile referenced
  this file in a `COPY` instruction, but the file was never created anywhere
  in `image/systemd/`, so the build would fail unconditionally on a missing
  build-context path — before even reaching the venv-install step, i.e.
  before any of the previously-flagged blockers (pins, PR-1/2/3) could even
  be exercised. Since M0 builds from plain `fedora-bootc` with no NVIDIA
  layer at all (Q4/Q5 resolution above), there is no `nvidia-suspend.service`
  unit for an override file to attach to yet regardless — so the fix is to
  remove the line, not invent plausible override contents, and let M2 (which
  actually adds the NVIDIA layer) add both the service and its override
  together.

- **Deviation D-A3: dropped the `local` extra from the venv-install step,
  because it silently pulls `torch` in violation of §0 rule 7.** Found by
  actually running the venv-install `RUN` step in CI (run 33319580279,
  2026-08-30): `uv pip install -e ".[voice-local-lite,local,compression,
  federation,google,compose,provenance]"` resolved `torch==2.13.0` plus a
  full CUDA 13 wheel stack (`nvidia-cublas`, `nvidia-cudnn-cu13`,
  `nvidia-cufft`, `triton`, ten-plus `nvidia-*` packages in all), which then
  exhausted the GitHub runner's disk ("no space left on device") while
  writing `torch/lib/libtorch_cpu.so` into the layer. Traced the cause to
  Agent-Friday's own `pyproject.toml` at v5.7.0: `local = ["sentence-
  transformers>=2.2", "chromadb>=0.5"]`, and `sentence-transformers` hard-
  depends on `torch` and `transformers`. This is not a disk-space problem to
  work around with a bigger runner or a CPU-only torch index — §0 rule 7
  lists "adding `torch` to the image" as a prohibited shortcut
  unconditionally ("regardless of convenience"), and §1.1's non-goals table
  says outright: "Bundling PyTorch... the packaged product does not ship
  torch. Local voice is CTranslate2 and ONNX." §6's own extras list names
  `local` anyway — that's the spec not accounting for what `local` actually
  installs, i.e. exactly the "cannot work as written" case rule 7 (§18)
  describes. Smallest fix preserving intent: install everything else in
  §6's extras list, omit `local`. Consequence: the M0 (and, until resolved,
  later) image ships without on-device semantic memory/embeddings
  (`sentence-transformers`/`chromadb`). Re-adding it needs either a
  torch-free embedding path (there is prior art for this exact pattern one
  extra over: `voice-local-lite` explicitly chose `faster-whisper` +
  `onnxruntime` over a torch-based ASR stack for the same reason) or an
  explicit decision from Stephen to relax rule 7 — not something this
  executor can decide unilaterally either way. Flagged for M1+ planning.

- **Deviation D-A4: replaced Agent-Friday's `compression` extra
  (`headroom-ai[all]`) with a bare `headroom-ai` install, no extras.**
  Immediately after D-A3 (dropping `local`), CI run 33319881454 still
  resolved `torch==2.13.0`, `sentence-transformers==5.7.0` and the full CUDA
  wheel stack and ran out of disk again — proving `local` was not the only
  source. Checked headroom-ai's PyPI metadata directly (`curl
  https://pypi.org/pypi/headroom-ai/json`): `compression = ["headroom-ai
  [all]>=0.22"]` in Agent-Friday's `pyproject.toml` expands `[all]` to
  `[code,evals,html,image,mcp,memory,ml,otel,proxy,relevance,reports,
  spreadsheet,voice]`, and the `ml`, `voice`, and `memory` extras each carry
  a marker like `(platform_machine != "x86_64" and extra == "ml") or
  (sys_platform != "darwin" and extra == "ml")` — on Linux, `sys_platform !=
  "darwin"` is unconditionally true, so the OR makes the whole marker true
  regardless of `platform_machine`, meaning `headroom-ai[all]` pulls
  `torch`, `transformers`, and `sentence-transformers` on every Linux
  install, x86_64 included, not just the non-x86_64/non-macOS case the
  marker was presumably written for. Read `context_compressor.py` at v5.7.0
  to check what Agent-Friday actually calls: `from headroom import
  compress`, a base-package import with a documented graceful fallback to
  uncompressed messages on `ImportError` — none of `code`/`html`/`image`/
  `memory`/`ml`/`voice`/`proxy` is load-bearing for that call. Fix: install
  bare `headroom-ai>=0.22` (its own base dependencies are `tiktoken`,
  `pydantic`, `litellm`, `click`, `rich`, `opentelemetry-api`,
  `ast-grep-cli`, `pyyaml`, `tomlkit` — no torch) as a second `uv pip
  install`, separate from the `-e .[...]` editable install of Agent-Friday
  itself, and drop `compression` from that editable install's extras list.
  This is Friday-Linux choosing what to install into its own venv, not a
  patch to Agent-Friday's source, so it does not need an upstream PR (rule 6
  is about not vendoring source patches to avoid the PR process — this is
  neither). Consequence: headroom's code-aware, HTML-aware, and image-aware
  compression modes, plus its unrelated proxy/agent-framework integrations,
  are unavailable in the M0 image; the JSON/text/prose compression path
  `context_compressor.py` actually exercises is unaffected.

- **Deviation D-A5: `build/build-llama.sh` now builds llama.cpp with
  `-DBUILD_SHARED_LIBS=OFF`, static rather than CMake's shared-library
  default.** CI run 33320543663 was the first to get the new `llama-build`
  stage all the way to a successful `podman build` (after two rounds of
  missing Vulkan-toolchain packages — `spirv-headers-devel`,
  `glslang-devel` — fixed the same way, by reading what CI's own `dnf`/
  `cmake` output actually said was missing). Reading that build's log
  showed `llama-server`, `llama-quantize`, and `llama-gguf-split` were each
  linked against a same-named shared library built alongside them
  (`libllama-server-impl.so`, `libllama-quantize-impl.so`) plus
  `libllama.so`/`libggml*.so`/`libggml-vulkan.so` — CMake's default for
  this project. The Containerfile's `COPY --from=llama-build` lines only
  copied the three executables, not any `.so` files, which would have
  shipped a binary that fails at first run with a missing-shared-library
  error — nothing in `podman build` executes the binary, so this would not
  have surfaced until real boot testing. Fixed by adding
  `-DBUILD_SHARED_LIBS=OFF` to the CMake configure line, which statically
  links everything into the three executables — matching SPEC.md §14's own
  plan of one self-contained file per binary at
  `/usr/libexec/friday/llama-server-vulkan`, with no lib directory or
  RPATH/`LD_LIBRARY_PATH` to manage. Added an `ldd`-based verification step
  to `build-llama.sh` itself (fails the build if a binary still references
  `libllama*`/`libggml*` or reports "not found") so this class of bug
  cannot silently reappear and go unnoticed the way it did on the first
  pass.

- **Deviation D-A6: reclaim GitHub runner disk space; stop caching uv
  wheels inside the built layer.** CI run 33321625110 ran the runner out of
  disk a third time — `no space left on device` while unpacking the venv-
  install layer, after the llama-build stage (D-A5) had already used a
  meaningful chunk of the runner's ~14 GiB free disk. Two independent
  causes, both fixed: (1) `UV_CACHE_DIR=/tmp/uv-cache` (added for the
  earlier `/root` symlink fix, see the `RUN` step's own comment) writes
  every downloaded wheel into the build container's filesystem, where it
  gets committed into the layer alongside the packages `uv` already
  extracted into the venv — roughly doubling that layer's footprint for a
  cache that is never read again after the `RUN` exits. Fixed by `rm -rf
  /tmp/uv-cache` at the end of the same `RUN` (must be the same layer, or
  the space isn't actually reclaimed — an earlier layer already paid for
  it). (2) `build/build-llama.sh` left the full llama.cpp source + build
  tree (object files for every CPU dispatch variant plus Vulkan shaders)
  on disk after copying the built binaries out; even though the llama-build
  stage's layers never reach the final image, podman/buildah still writes
  every stage's layers to local storage during the build itself, so an
  unclean build tree there still costs real disk for the whole job. Fixed
  with `rm -rf "${SRC_DIR}"` at the end of the script. Additionally added a
  "Free disk space on the runner" step to `build.yml`, removing GitHub's
  preinstalled `.NET`, Android SDK/NDK, GHC, Azure CLI, and JVM toolchains
  before the build starts — none of which this repo uses — for real,
  measured headroom rather than relying on cache tuning alone against a
  build that is genuinely disk-heavy (a C++ compile plus a ~90-package
  Python venv, both in the same job).

- **Deviation D-A7: move the built image into root's podman storage with
  `podman save`/`sudo podman load`, instead of rebuilding under `sudo`.**
  CI run 33322712869 confirmed the rootless/rootful podman storage split:
  `bootc-image-builder` (needs `sudo`, for loop-device access) couldn't see
  an image built by plain `podman build` (rootless storage) — "image not
  known." The first fix tried, `sudo podman build` for the whole
  Containerfile (D-A6/prior commit), traded that problem for a new one: CI
  run 33323791375's `sudo` environment hit `dnf`'s `$releasever` failing to
  expand and "database disk image is malformed" during the exact same `RUN
  dnf install -y git uv` line that had already succeeded cleanly (rootless)
  in every prior run — a root-podman-specific environment issue on this
  runner, not a Containerfile bug — and cost a full ~20-minute rebuild to
  discover. Fixed properly: build once, rootless (reliable, already proven
  across many runs), then `podman save -o /tmp/friday-linux.tar
  localhost/friday-linux:testing` followed by `sudo podman load -i
  /tmp/friday-linux.tar` — a tar round-trip that moves the already-built
  image into root's store without re-running the build at all.

## Blocking dependency: PR-1/2/3 not yet merged upstream

§13's last paragraph is explicit: "Friday Linux M0 (Section 15) can start on
`main` with PR-1 through PR-3 merged." Checked both `v5.7.0` and the current
`friday-desktop` HEAD (4 commits past `v5.7.0`, all docs/WIP work explicitly
marked "INCOMPLETE, DO NOT SHIP," unrelated to PR-1/2/3): neither
`core/os_mode.py` (PR-2) nor `core/paths.py` (PR-1) exists at either point,
and there is no packaged `agent_friday/seed/` (PR-3).

This means `build/agent-friday.pin` cannot be filled in with a real value
yet — the app has nowhere to pin that makes `FRIDAY_OS_MODE=1` do anything,
which is load-bearing for essentially every service definition in §8. This
is not something Friday-Linux-the-repo can work around: PR-1/2/3 are
upstream `Agent-Friday` work, tracked in that repo, not this one. Recorded
here rather than silently substituting `v5.7.0` and pretending OS mode
works, and flagged in the executor's report as the single most important
scheduling fact in the whole document.

What can proceed in the meantime, per rule 3 (a §17-style default, though
this isn't a numbered open question): author the Containerfile, systemd
units, and CI skeleton against a placeholder pin, since none of that content
depends on PR-1/2/3's code existing — only the final `podman build` step
(installing the venv from the pinned tag) is blocked.

## Deviations

Per rule 7: the smallest change that preserves intent, recorded rather than
silently made, for each place the spec's text couldn't be used verbatim.

- **Deviation D-A8: Workstream A's final tag is `v5.9.0`, not `v5.8.0`.**
  The orchestrator's dispatch brief named `v5.8.0` as the tag Workstream A
  (the five upstream Agent-Friday PRs) ends at, and named it as the value
  `build/agent-friday.pin` and this repo's greenboot/health-contract
  restoration (dispatch Step B5) move to once Workstream A completes. Before
  any of the five PRs landed, an entirely unrelated feature (a weekly
  update-check, PR #7 on `Agent-Friday`) merged to `main` and was tagged and
  **published as a public GitHub Release under `v5.8.0`** first. That tag is
  live and may already be downloaded; it is not to be moved, forced, or
  deleted. Workstream A's target is therefore corrected to **`v5.9.0`** —
  the next version after what's actually shipped, not a renumbering of
  anything already public. Nothing in this repo's `SPEC.md` (Amendment A1)
  or `DECISIONS.md`/`VERIFY.md`/`MILESTONES.md` referenced `v5.8.0` by name
  before this entry (confirmed by a repo-wide grep before writing this), so
  no other document needed correcting — only Step B5's future action (not
  yet started; blocked on Workstream A finishing) is affected, and it now
  reads `v5.9.0` wherever the original dispatch said `v5.8.0`.

- **PR-6 (health contract, not yet started) must build on
  `services/app_version.py`, not add a fourth version source.** The same
  update-check feature that claimed `v5.8.0` also added
  `services/app_version.py` as the single source of truth for "what version
  is actually running," replacing three prior separate implementations —
  including one inside `/api/health` that fell back to a hardcoded
  `"5.0.0"`. A committed test, `test_one_version_source.py`, fails if a
  second implementation reappears. PR-6's `/api/health` schema work must
  read its version field from `app_version.py`'s existing function, not
  reintroduce a fourth answer. Recorded here so whoever picks up PR-6 (after
  PR-2 and PR-5) inherits this constraint rather than rediscovering it.

- **`[Install]` sections added to every systemd unit.** §8.1 gives
  `friday.service`'s `[Unit]`/`[Service]` blocks verbatim with no
  `[Install]` section; without one, `systemctl enable` (which the
  Containerfile runs) fails with "unit has no installation config." Added
  `WantedBy=multi-user.target` (or `graphical.target` for the kiosk unit) to
  every authored unit. This is standard systemd plumbing, not a behavioral
  choice — flagged here only because rule 2 says DECIDED text is kept
  verbatim and this technically appends to it.

- **`friday-lockbox.mount` is a single outer mount, not five.** §5 mounts
  five btrfs subvolumes to five different paths, but `friday.service`'s
  given text (§8.1) names exactly one unit, `friday-lockbox.mount`, in its
  `After=`. Implemented `friday-lockbox.mount` as the outer LUKS+btrfs mount
  at `/run/friday-lockbox`, with the five subvolume-specific mounts to be
  generated by the first-boot wizard (per §7.3 step 4's own text: "writes
  /etc/crypttab and the mount units") once the lockbox exists. Full
  reasoning and the open question about whether `friday.service` should
  additionally depend on the per-subvolume units is in that file's header
  comment. Not resolved here because it needs a real systemd install to
  check `systemctl enable` and dependency ordering against, which this
  sandbox cannot do.

- **`image/caddy/Caddyfile` is adapted from a real read of
  `Agent-Friday/ops/Caddyfile` at v5.7.0** (via `git show`), not written
  from the one-line description in §8.2. Site address changed from
  `agent.friday` (the Windows version) to `friday.local`/`localhost` to
  match §8.2's own text and what `friday-kiosk.service` (§8.3) actually
  navigates Chromium to. Storage path changed from a Windows ProgramData
  path to `/var/lib/friday/caddy`, since Friday Linux has no SYSTEM-vs-user
  account split (both services run as `User=friday`) — the reason the
  Windows version used a machine-wide path doesn't apply here.

- **CI workflows (`ci/build.yml`, `ci/boot-test.yml`) contain deliberate
  `exit 1` steps** where a command's exact syntax is UNVERIFIED
  (`bootc-image-builder` invocation, `cosign` invocation, the QEMU boot
  command). These fail loudly rather than being written as a plausible
  guess that could pass CI without actually doing anything — per rule 5,
  never invent a version or a syntax and present it as working.

- **`image/firstboot/wizard.py` raises `NotImplementedError` for lockbox
  creation and unattended-file parsing**, rather than shipping a plausible
  but unverified `cryptsetup`/`mkfs.btrfs`/YAML-parsing implementation. Same
  reasoning as the CI deviation above: a script that looks complete but was
  never run against a real cryptsetup/btrfs version is worse than one that
  states exactly what's missing.

- **Deviation D-A1: M0 decoupled from upstream PR-1/2/3, per Amendment A1
  (30 Aug 2026, appended to `SPEC.md`).** The "Blocking dependency" note above
  (PR-1/2/3 not yet merged upstream) is real and was going to stall M0
  indefinitely. Amendment A1 unblocks it: `build/agent-friday.pin` is set to
  `v5.7.0` (not a hypothetical post-PR-3 tag); until PR-3 lands, the
  Containerfile clones Agent-Friday at that pin and copies `data/`/`skills/`
  to `/usr/share/friday/seed/` itself (a deployment-time workaround, not a
  vendored patch — removed the moment PR-3 merges); until PR-2 lands,
  `os.env`'s `FRIDAY_OS_MODE=1` is inert and `secrets.env` supplies
  `FRIDAY_PASSWORD` directly, and the tool registry may still list
  computer-control tools (accepted for M0/M1 only). M0's `boot_critical_ok`
  gate is deferred to M2; `greenboot/required.d/30-health.sh` checks HTTP
  status code only until PR-6 lands. This is why `build/agent-friday.pin` in
  the M0 entry below is no longer "deliberately left unresolved" — A1 gives
  it a real, if temporary, value.

- **CI workflow files moved from `ci/` to `.github/workflows/`.** §14's
  repo layout lists `ci/build.yml` and `ci/boot-test.yml`. GitHub Actions
  only discovers and runs workflows placed under `.github/workflows/` — it
  does not scan an arbitrary `ci/` directory. Confirmed the hard way: after
  the repo was created and pushed to `main` (with a `push: branches: [main]`
  trigger already in `build.yml`), `gh api repos/FutureSpeakAI/Friday-Linux/
  actions/workflows` returned zero workflows. Moved both files with `git mv`
  to `.github/workflows/build.yml` and `.github/workflows/boot-test.yml` —
  file contents unchanged, so §14's `ci/` naming survives as their logical
  home in spec-speak even though their real path had to move. If `ci/` is
  meant to hold anything else non-workflow-shaped later (it currently holds
  nothing), that's unaffected by this move.

- **Deviation D-A9: root cause of `boot-test.yml`'s long-standing "workflow
  file issue / zero jobs" failure found and fixed — it was invalid YAML,
  not a `workflow_run` timing quirk.** `docs/VERIFY.md`'s entry on this
  ("Unresolved CI quirk") had guessed at `workflow_run` ordering and left it
  unchased since every step downstream was a placeholder anyway. Parsing
  the actual committed file with PyYAML (`yaml.safe_load`) reproduces the
  failure locally: `mapping values are not allowed here, line 38 column
  24`. Cause: several steps used a single-line `run: echo "TODO: curl
  http://...` form. YAML only treats the text after `run:` as a literal
  string when the whole thing is a `|`/`>` block scalar or is itself
  quoted at the mapping-value level; a bare `run: echo "TODO: ..."` is a
  *plain* scalar from YAML's point of view, and a plain scalar containing
  `: ` (colon-space) mid-string — "TODO: curl" — is parsed as a nested
  mapping key, which is illegal inside an already-open scalar context.
  GitHub Actions does not surface this as a normal step failure because
  the file never parses far enough to produce any jobs at all; it instead
  registers a zero-job failed run tagged with whatever event triggered the
  re-parse (a `push`, in every observed case — confirmed via `gh api
  .../actions/runs/<id>`, which reported `"event":"push"` even though the
  file's only real triggers were `workflow_run`/`workflow_dispatch`). Fixed
  by rewriting every `run:` value as either single-quoted or a `|` block
  scalar, and validating the file with PyYAML locally before pushing —
  now part of this session's own process for any workflow-file edit, not
  just this one fix.

- **Deviation D-A10: `build/disk.toml` written using the real,
  live-fetched bootc-image-builder schema, not a plausible guess.** Per
  `docs/VERIFY.md`'s standing question, fetched the actual current
  `osbuild/images` `bootc-image-builder/README.md` (that repo now hosts
  the canonical source; the older standalone `osbuild/bootc-image-builder`
  repo's README matches only partially) rather than recalling a schema
  from training data. Confirmed: the config file is mounted at the fixed
  container path `/config.toml` (no `--config` CLI flag exists — absent
  from `build --help`'s real captured output too); the only customization
  primitive is `[[customizations.filesystem]]` with `mountpoint` +
  `minsize`, and it is documented as covering *only* `/`, `/boot`, and
  subdirectories of `/var` — there is no primitive for an independent ESP
  size or for "leave N GiB of raw unpartitioned space at the end of the
  disk." `build/disk.toml` sets `minsize = "16 GiB"` for `/` and `"1 GiB"`
  for `/boot`, matching SPEC.md §5's fixed-root intent as closely as the
  tool allows. Consequence, recorded so ADR-004 isn't silently
  reinterpreted: the lockbox's "remaining space on the boot device" comes
  from the *device being larger than the shipped image's own footprint*
  (a real USB stick, or in CI, a deliberately grown QEMU raw disk file),
  never from a partition baked into the image itself — this was already
  ADR-004's literal wording ("created at first boot"), just confirmed here
  as the *only* way it can work given bootc-image-builder's real, checked
  feature set, not a design choice this session introduced.

- **Deviation D-A11: created the `friday` Linux user/group — missing
  entirely from every prior pass.** `friday.service`, `friday-caddy.service`,
  and `friday-kiosk.service` all specify `User=friday`/`Group=friday`
  (copied verbatim from SPEC.md §8.1/§8.2/§8.3), but nothing in this repo's
  Containerfile ever ran `useradd`. `systemctl start friday.service` would
  have failed at the very first boot with "user friday does not exist,"
  before any of the mount/health logic mattered at all. Found by reading
  the units against the Containerfile while preparing the M0 boot test,
  not by a CI failure (fixed proactively). Added `useradd --create-home
  --home-dir /home/friday --shell /bin/bash --groups
  video,render,audio friday` plus `passwd -l friday` (locked password — no
  interactive login path exists or is needed at M0; §7.3 step 8's "set the
  friday user's password" is M1 wizard scope).

- **Deviation D-A12: `friday-lockbox.mount`'s device dependency corrected
  from `RequiresMountsFor=/dev/mapper/friday-lockbox` to
  `BindsTo=`/`After=dev-mapper-friday\x2dlockbox.device`.** The previous
  draft's own header comment claimed `RequiresMountsFor` would "wait until
  this device node appears," which is not what that directive does — it
  expects a *path provided by some other mount*, not a `/dev` node.
  Systemd's real idiom for "order after / bind to a udev-visible device
  node" is a dependency on the auto-generated `.device` unit for that
  node's escaped path. Fixed while implementing image/firstboot/wizard.py's
  real `create_lockbox()`, which needs this unit to actually mount when
  started right after `cryptsetup open`, not silently no-op or hang on a
  directive that never resolves.

- **Challenge (not a Deviation — flagged per rule 2, not silently
  resolved): `/var/lib/friday/secrets.env`'s real location does not match
  SPEC.md §8.1's stated security property.** §8.1 calls the file
  "(lockbox, mode 0600, owner friday)" and states "the human has one
  passphrase (the lockbox); the app's own vault and session keys are
  random and protected by the lockbox." But the file's given path,
  `/var/lib/friday/secrets.env`, is not on any of SPEC.md §5's five lockbox
  subvolumes — only `/var/lib/friday/models` and `/var/lib/friday/workshop`
  are lockbox-mounted subpaths; `/var/lib/friday/` itself is the sealed
  OS's own persistent `/var` (ostree does not wipe `/var` between
  deployments, so the file does survive updates, but it is protected only
  by the root filesystem's own permissions, not LUKS2 encryption). As
  implemented (`image/firstboot/wizard.py:write_secrets_env`), the file is
  created exactly where §8.1 says, generating random `FRIDAY_PASSWORD`/
  `FRIDAY_SECRET_KEY` — but the "protected by the lockbox" claim is not
  actually true for it. Fixing this for real means either extending §5's
  mount plan (a new subvolume or a bind-mount reaching into `/var/lib/
  friday` itself) or moving the file under `/home/friday` (already
  lockbox-backed via `@home`) — both are SPEC.md §5 changes, not something
  this executor resolves unilaterally. Flagged for Stephen; M0 proceeds
  with the file where §8.1 literally puts it, since M0's own acceptance
  checklist only requires the lockbox to exist with its five subvolumes,
  not this specific property.

- **Deviation D-A13: added `friday-boot-test-probe.service` and
  `friday-boot-test-relay.service` — not named anywhere in SPEC.md.** Both
  exist solely to make M0's acceptance checklist (SPEC.md §15) observable
  from a headless GitHub Actions QEMU boot test with no SSH server enabled
  (§10.2 — installed but disabled, no host keys) and `friday.service` bound
  to loopback only (§8.1). The relay solves reaching `/api/health` from
  outside the guest (a plain QEMU `hostfwd` cannot reach a loopback-only
  bound service — see the unit's own header). The probe solves observing
  `bootc status` and a `/usr` write-test, neither of which is exposed by
  any HTTP API at M0 (PR-10's `/api/os/status` is M4 scope). Both are
  gated by `ConditionPathExists=/var/lib/friday/.provisioned-unattended`, a
  marker the wizard writes *only* when it actually consumes a real
  `friday-unattended.yaml` (i.e., unattended/CI provisioning) — never on a
  normal interactive install — so both are a single, cheap condition check
  and otherwise complete no-ops on every real deployment. Neither opens a
  network listener beyond the CI-only relay's own unprivileged port 3001,
  and neither is reachable unless this exact marker file already exists.

- **Deviation D-A14: `friday-kiosk.service` is installed but not
  `systemctl enable`d at M0.** The real cage+Chromium kiosk experience is
  explicit M1 scope (SPEC.md §15: "M1: First-boot wizard, kiosk,
  rollback"), and its TLS chain (`image/caddy/Caddyfile`) is still a
  first-draft per this file's own earlier entry. Enabling a unit that is
  very likely to fail its own greenboot check (`40-kiosk.sh`) on every M0
  boot adds risk (retry-looping, a possibly-noisy journal, an unclear
  interaction with greenboot's rollback logic on a system with no kiosk
  wizard steps 1-3/5-9 yet) for zero M0 benefit — M0's own acceptance
  checklist (SPEC.md §15) does not mention the kiosk. Left present,
  disabled, matching the same pattern §10.2 already uses for `sshd`; M1
  only has to flip it on.

- **Decision: `build/agent-friday.lock` is not written, and will not be
  under Amendment A1's current install path.** SPEC.md §14 names it as a
  "uv lockfile for the app venv," and §6 says the venv is "installed from
  a lockfile committed in this repo." That describes PR-3's landed state:
  `pip install "agent-friday @ git+...@<tag>"` resolving against a
  committed `uv.lock`. Amendment A1's actual M0 mechanism is different and
  incompatible with that model: the Containerfile `git clone`s the full
  repository at the pin and runs `uv pip install -e "<clone>[extras]"` —
  an **editable** install of a **local path**, not a package install from
  a git URL. `uv lock` / `uv pip compile` for an editable local-path
  install would lock the same `pyproject.toml` dependency *ranges* that
  are already being resolved fresh at every build anyway; the output would
  not pin anything not already pinned by `build/agent-friday.pin` (the git
  tag itself) plus whatever `uv` resolves against PyPI at build time — the
  same non-reproducibility SPEC.md's own lockfile requirement exists to
  close, since a fresh `uv pip install -e` with no lockfile can resolve
  different transitive versions on different days even at the same pinned
  tag. A real fix (generating a `requirements.txt`-style lock from the
  pin's `pyproject.toml` via `uv pip compile` and having the Containerfile
  install from *that* instead of a bare `-e` install) is a genuine
  improvement worth doing, but changes the install mechanism itself
  (mixing an editable install with a separately-locked dependency set is
  not a one-line addition) and was not attempted this pass to avoid
  destabilizing the now-green `build.yml` while the M0 boot test was the
  session's primary focus. Recorded here as a real, open decision rather
  than left silently unresolved a second time: **not written now; revisit
  when `build/agent-friday.pin` moves to a post-PR-3 tag** (PR-3 makes the
  install-from-git-tag path SPEC.md originally assumed real, at which
  point a genuine `uv.lock` is both meaningful and straightforward), or
  sooner if reproducibility problems from the unlocked `-e` install
  actually surface in CI.

- **Deviation D-A15 (workaround, not a spec deviation to Agent-Friday's
  own code): `image/firstboot/wizard.py` pre-seeds
  `/home/friday/.friday/.setup_complete`.** Read `cli.py` at the pinned
  tag (`v5.7.0`, via the real `friday-desktop` checkout, not guessed):
  `friday` with no arguments runs `cmd_start()`, which calls
  `_is_existing_user()` and, if false, calls `rich.prompt.Confirm.ask(...)`
  — an interactive prompt with no fallback for a non-tty `stdin`.
  `friday.service` runs under systemd with no terminal attached, so this
  would either hang or raise `EOFError` on every first start, since
  nothing else pre-creates that marker before PR-2/PR-7 land (PR-7's
  `/api/setup/os-handoff` is the real, upstream fix for this exact
  problem, per SPEC.md §13 — it is M4-ordered work, not available at M0).
  This is an Amendment-A1-era workaround, not a permanent fixture: it goes
  away the moment PR-7 lands and the app itself understands OS mode.

- **Deviation D-A17: `friday-lockbox.mount` moved from `Where=/run/friday-lockbox`
  to `Where=/friday/lockbox` — a real boot failure, not a preemptive
  guess.** CI run 33340378275 (the first successful QEMU boot of this
  image, KVM confirmed working, OVMF fixed) got far enough to show
  systemd itself refusing the unit at early boot: `friday-lockbox.mount:
  Where= setting doesn't match unit name. Refusing.` Confirmed against
  systemd's real source (`src/basic/unit-name.c`,
  `unit_name_unescape()`): every literal `-` in a unit name is converted
  back to `/` when deriving its expected path — there is no other
  representation of `/` in a unit name, so a literal hyphen *within* a
  single path component must be escaped as `\x2d` to survive
  round-tripping. `/run/friday-lockbox` would therefore need to be named
  `run-friday\x2dlockbox.mount`, not the literal `friday-lockbox.mount`
  that SPEC.md's `friday.service` text (§8.1, kept verbatim) requires.
  The only path whose escaped form is exactly `friday-lockbox.mount` is
  `/friday/lockbox` (two real path components — the hyphen in the unit
  name IS the separator representing that real `/`). Moved `Where=`
  there; `/friday/lockbox` is now `mkdir -p`'d in the Containerfile so
  the mountpoint directory exists in the sealed, read-only image (mount
  needs an existing directory entry, not write access, at runtime).
  `image/firstboot/wizard.py`'s `LOCKBOX_RUN_MOUNT` and
  `friday-boot-test-probe.service`'s `btrfs subvolume list` call both
  updated to match. This is the header comment's own long-standing
  "FIRST-DRAFT / NEEDS REVIEW" flag getting resolved by the very thing
  its text said was needed: "a real systemd install to check ... against,
  which this sandbox cannot do" — now it can, via the boot test itself.

- **Deviation D-A18: relabeled SELinux port 3000 as `http_port_t` —
  the actual, confirmed blocker for `/api/health` across every boot test
  in this pass.** CI run 33413256821's console log looked like the whole
  system had gone silent partway through every boot (docs/MILESTONES.md
  has several dated entries chasing this as a possible hang or a
  console-visibility bug). It was neither: `systemd-journald`'s own
  userspace status-line reporting stopped working after the `@journal`
  remount (see the next entry below), which is what made grepping for
  `[ OK ]`/`[FAILED]` lines look like total silence — but the kernel's own
  audit/printk output, which bypasses journald's userspace formatting
  entirely, kept flowing the whole time and had the real answer:
  `avc: denied { name_connect } for pid=1630 comm="friday" dest=3000
  scontext=system_u:system_r:init_t:s0
  tcontext=system_u:object_r:ntop_port_t:s0 tclass=tcp_socket
  permissive=0`, repeating from ~78s onward. `friday.service` starts
  successfully; SELinux (correctly enforcing, `permissive=0` — never
  disabled, per §0 rule 7 / §10.2) blocks the app from actually using port
  3000, because port 3000 carries `ntop_port_t` in the base policy
  (reserved by an unrelated tool's own policy module) rather than the
  generic `unreserved_port_t` an arbitrary free port would default to.
  Fixed in the Containerfile: `semanage port -a -t http_port_t -p tcp
  3000` (falling back to `-m` since `-a` fails on a port that already has
  an explicit type), plus `policycoreutils-python-utils` added to the
  package list (provides `semanage` — not already present; `restorecon`,
  used elsewhere in this repo, comes from the separate `policycoreutils`
  base package which was already available). `http_port_t` is the
  standard, broadly-permitted SELinux type for a real HTTP server port,
  which is exactly what this is. `friday.service` running under the
  generic `init_t` domain (no dedicated SELinux type was ever created for
  it) is a separate, real gap worth reconsidering later — the port-label
  fix alone is expected to be sufficient for M0, and is verified by the
  absence of new `avc: denied` lines in the next boot's log, not merely
  by `/api/health` responding (either alone is weaker evidence than both
  together).

  **Correction, CI run 33420423832: the port relabel alone was NOT
  sufficient.** The relabel itself is confirmed working (the denial's own
  `tcontext` changed from `ntop_port_t` to `http_port_t`), but the
  connect attempt is still denied — `init_t` (the domain friday.service's
  process actually runs in — it does not auto-transition to
  `unconfined_service_t` the way many generic systemd-started executables
  do, a separate question worth investigating later, not solved here) is
  not granted `name_connect` to ANY port type by Fedora's targeted policy
  by default; that domain is deliberately narrow for early-boot/init
  work. Added a small custom SELinux policy module
  (`image/selinux/friday-network.te`, compiled and loaded at build time
  via `checkmodule`/`semodule_package`/`semodule` — `checkpolicy` added
  to the package list for `checkmodule`) granting exactly `allow init_t
  http_port_t:tcp_socket name_connect;` — nothing broader, and SELinux
  stays enforcing throughout (§0 rule 7 / §10.2). Not yet re-verified.

  **Confirmed working, CI run 33431293345: no `avc: denied` lines for
  port 3000 anywhere in the log, and `friday.service` itself now starts
  cleanly (`[ OK ] Started friday.service.`).** `/api/health` still did
  not respond, and a second, independent bug was found causing it —
  `friday-boot-test-relay.service` (the CI-only relay that makes port
  3000 reachable from the host at all — see that unit's own header) had
  the *exact same* "condition checked once too early, never retried" flaw
  `friday.service` itself had before Deviation D-A17's fix: it is
  `ConditionPathExists`-gated on the same `.provisioned-unattended`
  marker plus plain `WantedBy=multi-user.target`, with nothing
  re-triggering it once that marker actually exists. This means the relay
  has likely never actually been running in *any* boot test so far —
  sufficient on its own to explain every prior `/api/health` failure,
  independent of the SELinux and `@home`-mount fixes that were also
  genuinely necessary. Fixed the same way: `wizard.py` now explicitly
  runs `systemctl start --no-block friday-boot-test-relay.service` (and
  the same for `friday-boot-test-heartbeat.service`, which had the
  identical flaw) right after writing the `.provisioned-unattended`
  marker. Not yet re-verified.

- **Deviation D-A19 (lower priority, not fixed this pass, recorded so it
  does not cost someone else time later): `systemd-journald` repeats
  "Failed to open user journal file, falling back to system journal: No
  such file or directory" after the `@journal` subvolume is mounted live
  over `/var/log/journal` (`docs/MILESTONES.md`'s 2026-08-31 entries cover
  the fix: `systemctl kill --signal=SIGUSR1 systemd-journald.service` in
  `image/firstboot/wizard.py`, chosen over a full restart specifically
  because the restart broke console-log forwarding for the rest of
  boot).** This does not block M0 — the *system* journal
  (`journalctl` without `--user`) keeps working, which is all the boot
  probes in this repo rely on — but it means journald's own per-user
  journal file handling is not fully healthy after the live remount, and
  it pollutes every future log capture with repeated noise. Root cause
  not investigated (the live `@journal` mount is inherently an unusual
  sequence — a filesystem swapped out from under an already-running
  journald instance, signaled rather than restarted specifically to avoid
  the console-forwarding disruption a full restart caused — so some
  rough edges surviving that are not the *system* journal are plausible). Flagged for whoever next
  touches the first-boot wizard's `@journal` handling, rather than left
  to be silently rediscovered.

- **Deviation D-A20: fixed D-A19's journald "Failed to open user journal
  file" for real — it was actively blocking diagnosis of a real
  regression (B5's repin to v5.9.0, commit e51a2f0), not just a nuisance.**
  Confirmed against systemd's own real `tmpfiles.d/systemd.conf` source
  (not memory): `/var/log/journal` must be mode `2755`, owned
  `root:systemd-journal` (setgid, so journald's own per-user journal
  files created under it inherit that group). A plain `btrfs subvolume
  create` gives a fresh subvolume default `root:root` ownership with no
  setgid bit — wrong for this path, and the actual cause of "Failed to
  open **user** journal file" (the *system* journal was never affected,
  which is why every real confirmation elsewhere in this project's M0
  pass — `bootc status`, `/usr` read-only, the lockbox subvolumes — kept
  working regardless). Fixed in `image/firstboot/wizard.py`:
  `systemd-tmpfiles --create --prefix=/var/log/journal` right after the
  `@journal` mount succeeds, before the existing `SIGUSR1` signal —
  re-applies the real, shipped tmpfiles.d rule to the freshly-mounted
  directory, the same mechanism that sets this up on any normal boot.

- **CHALLENGE, not resolved unilaterally (B5 regression, real crash reason
  confirmed via CI run 33479726929's direct diagnostic evidence — commit
  a2adfd1's `image/scripts/boot-test-probe.sh`): SPEC.md §5's own stated
  assumption about `FRIDAY_HOME` is factually wrong against Agent-Friday
  v5.9.0's real `friday_home()` implementation.** SPEC.md line 143 says
  "`FRIDAY_HOME` is `/home/friday`, so the app's default `~/.friday`
  layout is unchanged", and line 247's `os.env` template sets
  `FRIDAY_HOME=/home/friday` accordingly. The real PR-1 source
  (`agent_friday/paths.py`, checked directly against the `friday-desktop`
  checkout at tag `v5.9.0`) does not behave that way:
  ```
  def friday_home() -> Path:
      env = os.environ.get("FRIDAY_HOME")
      if env:
          return Path(os.path.expanduser(env))       # <- used AS-IS, no ".friday" appended
      return Path.home() / ".friday"                  # <- ".friday" only added in the fallback
  ```
  When `FRIDAY_HOME` is set (which `os.env` deliberately does), the
  returned path is the override value *itself* — the `.friday` suffix is
  only appended in the *unset* fallback branch. So with
  `FRIDAY_HOME=/home/friday`, `cli.py`'s `SETUP_MARKER` resolves to
  `/home/friday/.setup_complete`, one directory level above where
  `image/firstboot/wizard.py`'s `seed_app_setup_marker()` actually writes
  it (`/home/friday/.friday/.setup_complete`, per SPEC.md §8.1's own
  Amendment-A1 text and this project's existing convention). Confirmed
  directly, not inferred, via the new probe: `FRIDAY_HOME env = '/home/friday'`,
  `friday_home() = /home/friday` (no `.friday`), `cli.SETUP_MARKER =
  /home/friday/.setup_complete exists = False`, while
  `/home/friday/.friday/.setup_complete` genuinely exists on the real,
  correctly-mounted `@home` lockbox subvolume (`ls -la` shows it, `cat`
  shows `friday-linux-os-wizard`, `findmnt /home/friday` shows
  `/dev/mapper/friday-lockbox[/@home]` mounted `rw` at `/var/home/friday`
  — the mount-timing/shadowing theory considered before finding this is
  ruled out). This is why `_is_existing_user()` returns `False` and
  `cmd_start()` hits `Confirm.ask()` -> `EOFError` under systemd (no tty),
  crash-looping `friday.service` every `RestartSec=5` — a real regression
  introduced by B5's v5.7.0 -> v5.9.0 repin (PR-1 landing changed
  `SETUP_MARKER`'s resolution from a literal `Path.home() / ".friday"`
  expression to this env-var-aware one; v5.7.0 had no `FRIDAY_HOME`
  concept at all, so `os.env`'s pre-existing `FRIDAY_HOME=/home/friday`
  line was inert and harmless until now).

  Not fixed here: doing so means changing either the literal value SPEC.md
  §5/§13 documents for `FRIDAY_HOME` (to `/home/friday/.friday`, matching
  `friday_home()`'s real semantics) or removing the line from `os.env`
  entirely (letting it fall through to `Path.home() / ".friday"`, which
  resolves identically since `friday`'s `$HOME` is `/home/friday`) —
  either way, a documented SPEC.md line no longer reads the way SPEC.md
  wrote it, which is a call for whoever owns SPEC.md, not something to
  silently patch around in `image/etc/friday/os.env`.

- **Executable bits are set in the Containerfile, not relied on from git.**
  Confirmed via `git ls-files -s` after committing: every file this repo
  tracks landed as mode `100644`, including the `.sh` scripts and the
  `friday-os-helper` binary that were `chmod +x`'d locally — Windows Git
  does not preserve the Unix execute bit through commit. The Containerfile
  now `chmod`s the greenboot scripts and the wizard explicitly (the helper
  already was). Worth a repo-level fix later (a pre-commit hook or
  `git update-index --chmod=+x` run from a real Linux/macOS clone) so this
  isn't a standing trap for the next person who edits these files from
  Windows and forgets the Containerfile compensates for it.
