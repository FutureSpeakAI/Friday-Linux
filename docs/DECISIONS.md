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
