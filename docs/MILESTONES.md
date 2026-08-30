# Milestones

Per SPEC.md §18 rule 4: work proceeds milestone by milestone; M(n+1) does
not start until M(n)'s acceptance criteria pass and are recorded here with
exact commands, output, and the image digest tested.

## M0: Scaffold and first boot (no GPU) — IN PROGRESS, NOT PASSED

**Authored this pass:** Containerfile; systemd units
(`friday.service`, `friday-lockbox.mount`, `friday-caddy.service`,
`friday-kiosk.service`, `friday-firstboot.service`) and `os.env`;
`image/greenboot/required.d/*.sh` (all four checks from §11.2); the
first-boot wizard stub (`image/firstboot/wizard.py`, M0 scope only —
lockbox creation from an unattended file); `image/caddy/Caddyfile` (adapted
from a real read of `Agent-Friday/ops/Caddyfile` at v5.7.0); nftables
baseline; Chromium managed policy; the polkit NetworkManager rule; the
`friday-os-helper` and its sudoers rule; the splash page; `ci/build.yml` and
`ci/boot-test.yml` skeletons; `build/agent-friday.pin` (deliberately left
unresolved — see below).

**2026-08-30, execution pass on GitHub Actions `ubuntu-latest` (this
session): `podman build` now genuinely succeeds.** Real CI run, not a local
guess: https://github.com/FutureSpeakAI/Friday-Linux/actions/runs/33320159178
(job 99280596866, commit on `main` at push time). All 22 `STEP`s completed;
final lines of the actual log:
```
STEP 22/22: RUN systemctl disable sshd.service
COMMIT friday-linux:testing
--> c1a3e545cee4
Successfully tagged localhost/friday-linux:testing
```
Getting here from the prior "cannot run" state took five real, CI-verified
bug fixes (each with its own commit and failing-run evidence), all recorded
in full in `docs/DECISIONS.md`:
1. Containerfile referenced `image/systemd/nvidia-suspend-override.conf`,
   a file that was never authored — unconditional build failure (D-A2).
2. The venv-install `RUN --mount=type=cache,target=/root/.cache/uv` failed
   because `/root` doesn't exist yet in a Fedora bootc build container.
3. The same `RUN` step read `build/agent-friday.pin` from a path that only
   exists on the build host, not inside the container — never `COPY`'d in.
4. `uv venv`/`uv pip install` failed under `$HOME=/root` because `/root` is
   a symlink into `/var/roothome`, which doesn't exist at build time in a
   bootc image (`/var` is state, populated at first real boot, not build
   time) — fixed with `HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache`.
5. The `local` and `compression` (`headroom-ai[all]`) extras from §6's
   given pip-extras list both silently pulled `torch` + a full CUDA wheel
   stack on Linux (confirmed via two separate CI runs that ran the GitHub
   runner out of disk space), a direct violation of SPEC.md §0 rule 7's
   absolute prohibition on shipping `torch`. Fixed per Deviations D-A3/D-A4:
   dropped `local` entirely (its feature — on-device embeddings — is
   genuinely absent from the image now) and replaced Agent-Friday's
   `compression` extra with a bare, extras-free `headroom-ai` install that
   still satisfies the one thing Agent-Friday's code actually calls
   (`from headroom import compress`, base package, graceful ImportError
   fallback).

A genuinely useful side-finding from the same run: the full §6/§8 Fedora
package list (`chromium`, `caddy`, `cage`, `greenboot`, etc.) installed
cleanly from Fedora 44's own repos with **no COPR needed for `caddy`**,
contradicting this file's and `docs/VERIFY.md`'s earlier flag — recorded
and superseded in `docs/VERIFY.md`.

**Still not done, in progress:** `podman build` succeeding is necessary but
not sufficient for the first M0 checklist line — GHCR push and cosign
signing haven't been attempted yet (signing is explicitly out of scope per
the executor's operating rules until a later milestone: no `COSIGN_*`
secret exists or should be created). The `bootc-image-builder` step (next
checklist line) is still a deliberate `exit 1` placeholder and is this
session's next target.

**2026-08-30, continued: llama-server-vulkan now builds too, and
bootc-image-builder is real (not the placeholder) but not yet producing a
raw image.** CI run 33322712869:
```
6 podman build                                                    success
7 Discover bootc-image-builder CLI (disk.toml question)            success
8 Produce raw image (bootc-image-builder)                          failure
```
`podman build` now includes a real `llama-build` stage (static-linked
`llama-server-vulkan`, `llama-quantize`, `llama-gguf-split`, verified with
`ldd` inside `build/build-llama.sh` itself — see Deviation D-A5). Getting
the multi-stage build green took three more real fixes: two missing Vulkan
CMake dependencies (`spirv-headers-devel`, `glslang-devel`), the shared-
library/static-link bug (D-A5), and a third disk-space exhaustion from
`uv`'s cache being committed into its own layer plus GitHub's preinstalled
toolchains eating the runner's disk budget (D-A6, includes a "Free disk
space on the runner" step in `build.yml` that reclaims real, measured
space). `bootc-image-builder --help` now runs for real in CI (its full
output is in that run's log, not reproduced here — read it there rather
than trusting a description). The raw-image step itself failed with a
useful, specific error, not a guess: `localhost/friday-linux:testing: image
not known` — `podman build` ran unprivileged (rootless storage) while
`bootc-image-builder` runs under `sudo` (rootful storage, needed for
loop-device access), so the two steps were looking at two different image
stores. Fixed by building with `sudo podman build` too, so both steps share
root's storage; also dropped the now-default (and warned-about) `--local`
flag. Not yet re-run to confirm — this session's next check.

**2026-08-30, M0's `build` workflow is fully green for the first time.** CI
run 33326572437, every step:
```
podman build                                                       success
Push image to GHCR                                                 (added after this run — see below)
Copy built image into root's podman storage                        success
Discover bootc-image-builder CLI (disk.toml question)               success
Produce raw image (bootc-image-builder)                             success
Size check (G7)                                                     success
  compressed size: 1719 MiB (budget: 8192 MiB, SPEC.md G7)
Sign with cosign (keyless, GitHub OIDC)                              (was exit-1 placeholder; now a clean skip)
```
Two more real fixes got here from the previous entry's rootless/rootful
storage mismatch:
1. **`sudo podman build` was the wrong fix.** Re-running the whole build
   under `sudo` (to share root's podman storage with `bootc-image-builder`)
   traded the storage mismatch for a *different*, sudo-environment-specific
   failure (CI run 33323791375: `dnf`'s `$releasever` failed to expand,
   "database disk image is malformed", on a `dnf install` line that works
   fine rootless) and cost a full ~20-minute rebuild to discover. Fixed
   properly (Deviation D-A7): build once, rootless (proven reliable), then
   `podman save -o /tmp/friday-linux.tar ...` + `sudo podman load -i
   /tmp/friday-linux.tar` — a tar round-trip, not a second build.
2. **`bootc-image-builder`'s manifest step needed `--rootfs xfs`.** First
   real attempt (CI run 33325393238) reached genuine manifest generation and
   failed with `missing required info: DefaultRootFs`. `--rootfs xfs` (a
   best-effort guess, Fedora's traditional default, flagged UNVERIFIED in
   `docs/VERIFY.md` when tried) turned out to be correct — CI run
   33326572437's log shows real partitioning and an actual ostree deploy:
   `/dev/loop0p2` (EFI), `/dev/loop0p3` (boot), `/dev/loop0p4` (xfs root),
   `Deployment root at 'ostree/deploy/default/deploy/
   108dd3da32004bbb9a5ae2b8da3160f60cf9876f912ad063d2487abb6cd345e7.0'`,
   `disk.raw` size `11168382976` bytes (~10.4 GiB uncompressed), compressing
   to 1719 MiB — a real disk image, not a stub.

Added after this run, not yet re-confirmed in a fresh CI run: a "Push image
to GHCR" step (uses the auto-issued `GITHUB_TOKEN` via a job-level
`permissions: packages: write`, no secret created) and converting the
cosign step from a failing placeholder into an explicit, clearly-labeled
skip — signing stays out of scope for M0 per the executor's operating
instructions, but a deliberately-deferred step should not make the whole
`build` job report failure once everything ahead of it is real and green.

**`build/disk.toml` is still not written** — SPEC.md §5's exact partition
layout (16 GiB fixed root, remainder free for the lockbox) is not what got
built; `--rootfs xfs` plus bootc-image-builder's own defaults produced
*some* working partition table, which is enough to satisfy M0's literal
"produces a raw image ≤ 8 GB compressed" line but is a real, tracked gap
before M1 (the wizard needs specific free space to exist for the lockbox).
Not silently treated as done.

**Acceptance checklist, updated:**
- [x] `podman build` succeeds, including the real `llama-server-vulkan`
      build stage (CI run 33326572437). Image tag `localhost/friday-linux:
      testing`. GHCR push step added same session, not yet reconfirmed by a
      fresh run. Signing remains a deliberate, clearly-labeled skip (SPEC.md
      §10.3, out of scope for M0 per the executor's operating instructions).
- [x] `bootc-image-builder` produces a raw image ≤ 8 GB compressed — CI run
      33326572437, real command output: `compressed size: 1719 MiB (budget:
      8192 MiB, SPEC.md G7)`. Uses bootc-image-builder's default disk
      layout plus `--rootfs xfs`, NOT a verified `build/disk.toml` — SPEC.md
      §5's exact partition scheme remains a real, tracked gap for M1.
- [ ] QEMU/KVM boots it, `/api/health` 200 within 300 s — **cannot run from
      this session**: no KVM in this sandbox, and `boot-test.yml` is a
      separate workflow with its own unresolved, lower-priority CI quirk
      (docs/VERIFY.md) — out of this session's scope per its own mandate.
- [ ] `bootc status` one deployment, `/usr` read-only — needs a real boot
      (QEMU or hardware), not exercised by `build.yml`.
- [ ] Lockbox is LUKS2/Argon2id with five subvolumes — **cannot run**;
      also the wizard stub deliberately raises `NotImplementedError` for
      this step rather than shipping unverified `cryptsetup` syntax (see
      `docs/DECISIONS.md` Deviations), and `build/disk.toml`'s gap above
      means the free space for the lockbox to claim isn't guaranteed to
      exist yet either.

**Superseded (kept struck through for the record, not deleted, per §18 rule
7's "record, don't silently overwrite"): the three blockers listed in the
previous pass of this file** — unresolved `agent-friday.pin`, no Linux/KVM
environment, and several unverified external facts — **are resolved as of
Amendment A1 and this session's execution pass.** Amendment A1 pinned
`agent-friday.pin` to `v5.7.0` and worked around PR-1/2/3 directly (see
SPEC.md, "Amendment A1" and `docs/DECISIONS.md` Deviation D-A1); GitHub
Actions' `ubuntu-latest` runners are the real Linux/KVM environment in use
(no WSL2, no local podman — see the standing limitation note in
`docs/VERIFY.md`, unchanged); Q4/Q5/llama.cpp pins were all resolved via
registry API queries before this session started (`docs/VERIFY.md`,
2026-08-30 entries). This session's own work is the fourth item —
`disk.toml`'s schema — still open, tracked below.

**Next concrete steps, in order:** (1) build `llama-server-vulkan` in a
proper multi-stage Containerfile stage from `build/llama.cpp.pin`
(`build/build-llama.sh` does not exist yet — M0 explicitly needs this
binary per SPEC.md §15, it is not optional); (2) discover
`bootc-image-builder`'s real `disk.toml` schema by having a CI step actually
invoke `podman run --rm quay.io/centos-bootc/bootc-image-builder:latest
--help` rather than guessing from old examples, then replace `build.yml`'s
placeholder `exit 1` step with the real invocation; (3) get a raw image
built and size-checked; (4) boot-test in QEMU/KVM (separate workflow,
lower priority than build.yml per this session's mandate — see its own
open CI quirk in `docs/VERIFY.md`).

## M1-M4

Not started. Per rule 4, they don't start until M0's checklist above is
checked off with real command output and an image digest recorded here —
not before.
