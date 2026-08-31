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

**2026-08-30 — CI run 33328948151: the entire `build` workflow is GREEN,
every step, for the first time.**
https://github.com/FutureSpeakAI/Friday-Linux/actions/runs/33328948151
```
Set up job                                                          success
Run actions/checkout@v4                                             success
Read pins                                                           success
Fail fast if pins are unresolved                                    skipped (pins are resolved)
Free disk space on the runner                                       success
podman build                                                        success
Push image to GHCR                                                  success
Copy built image into root's podman storage                         success
Discover bootc-image-builder CLI                                    success
Produce raw image (bootc-image-builder)                             success
Size check (G7)                                                     success
Sign with cosign — SKIPPED, out of scope for M0                     success (clean skip)
Complete job                                                        success
```
Real evidence pulled from this run's own log, not paraphrased:
- Image pushed to GHCR: `podman push ghcr.io/futurespeakai/friday-linux:
  testing` → `Login Succeeded!`, all blobs copied, `Copying config
  sha256:728b08e86d48604a5e50ef984a571094c273688f545f61ea60606b59ec0a4c61`,
  `Writing manifest to image destination`. **Image digest:
  `sha256:728b08e86d48604a5e50ef984a571094c273688f545f61ea60606b59ec0a4c61`.**
- `bootc-image-builder` produced `disk.raw` at `11168382976` bytes (~10.4
  GiB uncompressed) via a real ostree deployment (confirmed loop-device
  partition mounts and a real deployment commit hash in the log).
- G7 size check: `compressed size: 1719 MiB (budget: 8192 MiB, SPEC.md
  G7)` — PASS, well under budget.
- Signing step is a clean, intentional skip (exit 0, explanatory echo
  lines), not a failure — matches the executor's instruction that a
  deliberately out-of-scope step should not redden the whole job.

**Acceptance checklist, updated:**
- [x] `podman build` succeeds, including the real `llama-server-vulkan`
      build stage, AND the image is pushed to `ghcr.io/futurespeakai/
      friday-linux:testing` (digest `sha256:728b08e86d48604a5e50ef984a571
      094c273688f545f61ea60606b59ec0a4c61`, CI run 33328948151). Signing
      remains a deliberate, clearly-labeled skip (SPEC.md §10.3, out of
      scope for M0 per the executor's operating instructions — no
      `COSIGN_*` secret exists or is referenced).
- [x] `bootc-image-builder` produces a raw image ≤ 8 GB compressed — CI run
      33328948151, real command output: `compressed size: 1719 MiB (budget:
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

**Next concrete steps, updated 2026-08-30 after `build.yml` went fully
green (CI run 33328948151, see above) — items (1)-(3) below are DONE:**
1. ~~build `llama-server-vulkan` in a proper multi-stage Containerfile
   stage~~ — done, static-linked and `ldd`-verified (Deviation D-A5).
2. ~~discover `bootc-image-builder`'s real CLI/schema via CI~~ — done;
   `--rootfs xfs` plus bootc-image-builder's default disk layout produces a
   working raw image. `build/disk.toml` itself is still not written (a real
   gap, see the acceptance checklist above and `docs/VERIFY.md`).
3. ~~get a raw image built and size-checked~~ — done, 1719 MiB compressed
   against the 8192 MiB G7 budget.

**What's actually left for M0, in order:**
4. Write a real `build/disk.toml` expressing SPEC.md §5's exact partition
   scheme (16 GiB fixed root, remainder free for the lockbox) — needed
   before M1's wizard can rely on that free space existing.
5. `ci/boot-test.yml`: QEMU/KVM boot with the unattended file, `/api/health`
   200, sealed `/usr`, lockbox layout — a separate workflow with its own
   open, low-priority CI quirk (`docs/VERIFY.md`, "workflow file issue" with
   zero jobs created) that was out of this session's scope; needs its own
   pass once `build.yml`'s raw image is a settled artifact to boot from.
6. The first-boot wizard's real lockbox-creation implementation
   (`cryptsetup luksFormat` argon2id parameters, btrfs subvolumes,
   `/etc/crypttab` generation) — currently `NotImplementedError` stubs,
   deliberately not guessed (`docs/DECISIONS.md` Deviations).
7. `build/agent-friday.lock` — SPEC.md wanted a uv lockfile for the app
   venv; Amendment A1's editable-install-from-git-clone workaround doesn't
   fit that model. Not attempted this session; needs a decision recorded in
   `docs/DECISIONS.md` on whether a lockfile is meaningful under A1's
   approach or should be explicitly skipped.

**2026-08-30, new execution pass: `build/disk.toml` written, the `friday`
user (missing entirely — a real bug) created, `boot-test.yml`'s actual
root cause found and fixed, and `image/firstboot/wizard.py` given a real
implementation.** Not yet confirmed by a fresh CI run at the time this
paragraph was written — see `docs/DECISIONS.md` Deviations D-A9 through
D-A15 for the full list of what changed and why:
- `build/disk.toml` now exists, using the real bootc-image-builder schema
  (confirmed via a live docs fetch, not memory) — `minsize=16GiB` for `/`,
  `1GiB` for `/boot`. `build.yml`'s "Produce raw image" step now mounts it.
- The `friday` Linux user/group did not exist anywhere in this repo before
  this pass — `friday.service` would have failed at the first boot with
  "user does not exist." Fixed in the Containerfile.
- `boot-test.yml`'s long-standing "workflow file issue / zero jobs"
  failure (previously blamed on `workflow_run` timing) was actually
  invalid YAML (colon-space inside an unquoted plain scalar) — confirmed
  by parsing the committed file with PyYAML locally, fixed, and the file
  rewritten with a real (not placeholder) QEMU/OVMF pipeline. Trigger
  changed from `workflow_run` to `workflow_dispatch`-only for now (cost
  control while this file's own logic is being iterated on).
- `image/firstboot/wizard.py` replaced its `NotImplementedError` stubs
  with a real implementation: parses `friday-unattended.yaml` with
  `python3-pyyaml` (newly added to the Containerfile), finds the real boot
  disk via `/sysroot`, partitions remaining free space with `sgdisk`,
  creates the LUKS2/Argon2id lockbox and its five btrfs subvolumes, writes
  `/etc/crypttab` and four per-subvolume mount units, writes
  `/var/lib/friday/secrets.env`, and pre-seeds
  `/home/friday/.friday/.setup_complete` (an Amendment-A1-era workaround
  for `cmd_start()`'s interactive `Confirm.ask()`, confirmed against the
  real `friday-desktop` checkout at v5.7.0 — see D-A15).
- Two new, SPEC.md-unnamed units (`friday-boot-test-probe.service`,
  `friday-boot-test-relay.service`) exist solely to make M0's checklist
  observable from a headless CI QEMU boot with no SSH and a loopback-only
  app — both are inert no-ops on any real deployment (see D-A13).
- `friday-kiosk.service` is deliberately not enabled at M0 (D-A14) — kiosk
  is M1 scope.
- `build/agent-friday.lock`: decided NOT to write one under Amendment A1's
  editable-install-from-clone path — recorded as a real decision, not left
  unresolved a second time (see D-A16 in `docs/DECISIONS.md`).
- A real gap was found and flagged (not silently fixed): `secrets.env`'s
  SPEC.md-given path is not on any lockbox subvolume, so it is not
  actually "protected by the lockbox" as §8.1 claims — a Challenge, not a
  Deviation, since fixing it means changing §5's mount plan.

**2026-08-30 — CI run 33336423358: `build.yml` fully green with all of the
above real, after two genuine failures fixed via real CI output (not
guessed):**
1. First real failure (CI runs 33334408813, 33335275371): `useradd: group
   'video' does not exist` (same for `render`, `audio`) — these groups are
   not created by Mesa/PipeWire's packages at `dnf install` time inside a
   container build (no init system running to apply their `sysusers.d`
   drop-ins). `groupadd -f` did NOT fix this (produced no output, and
   `useradd` still reported all three missing immediately after — an
   unexplained NSS/groupadd interaction, recorded honestly as unresolved
   in `docs/DECISIONS.md` rather than a confident but wrong theory).
   Fixed deterministically by appending directly to `/etc/group` with a
   freshly computed free GID — CI run 33336423358's own log confirms
   `created video with GID 977`, `created render with GID 978`,
   `created audio with GID 979`, and the subsequent `useradd` succeeded.
2. `build/disk.toml` real effect confirmed, DESPITE a confusing log line:
   bootc-image-builder printed `blueprint validation failed for image
   type "raw": customizations.filesystem: not supported` during manifest
   generation, which looks like a hard failure but was not one — the step
   completed successfully and the REAL measured partition table proves
   the customization took effect: `/boot` is exactly 2097152 sectors (1.0
   GiB, matches `disk.toml`'s `minsize`) and `/` is exactly 33556447
   sectors (~16.00 GiB, matches `disk.toml`'s `minsize` almost exactly) —
   compare to the pre-disk.toml build (CI run 33328948151), where root was
   only 18685919 sectors (~8.9 GiB, sized to fit content, not fixed).
   Recorded as an open, unexplained discrepancy in `docs/VERIFY.md` (the
   warning text vs. the observed real effect) rather than asserted as
   fully understood.
3. Real evidence, this run:
   - Image digest: `sha256:98d902abcaeefc2eb15089854ca81163349d329a3073964ab8dc9270b9b979cb`
     pushed to `ghcr.io/futurespeakai/friday-linux:testing` (private,
     confirmed unchanged — `Login Succeeded!`, all blobs + config copied).
   - Raw disk: `disk.raw` size `18782093312` bytes (~17.5 GiB
     uncompressed, up from ~10.4 GiB pre-disk.toml — expected, since root
     is now genuinely fixed at 16 GiB instead of fit-to-content).
   - G7 size check: `compressed size: 1719 MiB (budget: 8192 MiB, SPEC.md
     G7)` — PASS, unchanged from the pre-disk.toml build, because the
     extra headroom in the now-fixed-size root partition is mostly unused
     space that `xz` compresses away almost entirely.
   - Real partition table (loop0, GPT): p1 BIOS-boot 2048 sectors, p2 ESP
     1026048 sectors (~501 MiB — SPEC.md wants 512 MiB; not independently
     configurable per `docs/DECISIONS.md` D-A10, close enough), p3 /boot
     2097152 sectors (1.0 GiB), p4 / 33556447 sectors (~16.0 GiB).

**Also fixed this pass, before the failures above (not yet independently
CI-confirmed as necessary, since the build never got far enough to prove
or disprove them on their own, but no evidence contradicts them either):**
`mkdir -p /var/home` before `useradd` (preempting a suspected `/home` →
`/var/home` ostree symlink, the same class of bug that already broke
`UV_CACHE_DIR`'s default path for `/root`) — the build got past this line
cleanly in all three attempts, consistent with the fix being either
correct or unnecessary, not with it being wrong.

**Next: dispatch `boot-test.yml` against this real image/digest, read the
actual CI output, and iterate** — none of M0's remaining three checklist
lines (QEMU boot + health, `bootc status`/`/usr` read-only, lockbox) are
checked off below until real command output says so.

**2026-08-30 — `boot-test.yml`'s long-standing "zero jobs" bug is fixed
for real, and it now produces genuine, informative boot-test runs.**
Dispatched four times against the real image, each run fixing one
concrete, CI-proven bug (not a guess) — this is the actual "M0 build
half was done, boot half was not" gap finally being closed:

1. CI run 33339218662 (first real job this workflow has EVER produced):
   got past KVM confirmation, OVMF/QEMU/gdisk install, and pulling the
   image, then failed at `bootc-image-builder`'s ostree pull: `no space
   left on device`. `boot-test.yml` never had the disk-reclaim step
   `build.yml` already needed (Deviation D-A6) — copied it over.
2. CI run 33339485078: `bootc-image-builder` actually printed "Build
   complete!" but the step still failed — a `chmod output/*.raw` glob
   didn't match because the real file is at `output/image/disk.raw`
   (nested). Fixed to use `find` recursively, matching the pattern the
   next step already used correctly.
3. CI run 33339954425: the "Boot under QEMU/KVM with OVMF" step failed
   silently. Real cause: Ubuntu's `ovmf` package ships
   `OVMF_CODE_4M.fd`/`OVMF_VARS_4M.fd`, not plain `OVMF_CODE.fd` — grep
   patterns matched nothing, both shell variables were silently empty,
   `cp ""` failed with no visible message. Fixed to the real filenames
   plus explicit non-empty assertions so a repeat of this exact class of
   bug fails loudly instead of three steps later with no output.
4. **CI run 33340378275 — real, substantial progress: KVM confirmed
   working on GitHub-hosted `ubuntu-latest` (SPEC.md §16.2's own
   assumption, now actually verified, not just trusted), OVMF fixed, and
   the image genuinely boots**: GRUB menu renders, "Fedora Linux 44
   (Forty Four) (ostree:0)" is selected and boots, the kernel loads,
   `systemd[1]: Successfully made /usr/ read-only.` appears (a real,
   very early, positive sign for the "/usr read-only" acceptance line),
   SELinux policy loads, and systemd reaches real targets
   (`sysinit.target`, `basic.target`, `local-fs.target`). It then hit a
   real, systemd-refused unit: `friday-lockbox.mount: Where= setting
   doesn't match unit name. Refusing.` Root-caused against systemd's own
   source (not guessed) and fixed — see `docs/DECISIONS.md` Deviation
   D-A17: `Where=` moved from `/run/friday-lockbox` to `/friday/lockbox`,
   the only path whose escaped form matches the literal unit name
   `friday-lockbox.mount` that SPEC.md's `friday.service` text requires.
   `/api/health` did not respond within 300s on this run (expected —
   without the crypttab/lockbox mount, `friday.service`'s
   `Requires=friday-lockbox.mount` can never be satisfied, so it never
   starts) — not yet a real M0 failure signal, since the actual blocker
   (the mount unit being refused outright) is now fixed and unverified
   against a fresh boot.

**Not yet checked off — next boot-test dispatch is the check**: `/api/health`
200 within 300s, `bootc status` one deployment, `/usr` read-only
(confirmed promising in the console log above but not yet asserted by the
probe unit, since the probe never got to run without the lockbox mounting
and `.provisioned-unattended` marker existing), lockbox LUKS2/Argon2id
with five subvolumes.

**2026-08-30/31 — CI run 33343357304: the `friday-lockbox.mount` fix
worked, real progress moved further into the wizard, and a new real bug
was found (and a real diagnostic gap fixed alongside it).** Console log
confirms: `friday-lockbox.mount` no longer gets refused by systemd (the
earlier "Where= doesn't match unit name" is gone) — it now behaves
exactly as a normal first-boot should, timing out waiting for a device
that legitimately doesn't exist yet (`Timed out waiting for device
dev-mapper-friday\x2dlockbox.device`), with `friday.service` correctly
reporting `Dependency failed` as a result (expected, not a bug — the
lockbox genuinely isn't there yet). `friday-firstboot.service` started,
found the unattended file, resolved the real boot disk as `/dev/vda`
(confirms `find_root_disk()`'s `/sysroot`-based logic works on this real
ostree layout), and then failed at `sgdisk -n 0:0:0 -t 0:8309 -c
0:friday-lockbox /dev/vda` with exit status 4 — but with no visible error
message, because `wizard.py`'s `_run()` used `capture_output=True` and
never printed anything it captured on failure. **Every command failure
so far in this wizard has been diagnosed blind** — fixed now: `_run()`
prints captured stdout/stderr unconditionally (they already land in the
journal via `friday-firstboot.service`'s default IO, which
`friday-boot-test-probe.service` already dumps to the console), so the
next run will show `sgdisk`'s own real error text instead of just a bare
exit code. Confirmed via the host-side "Grow the disk" step's own real
`sgdisk -p` output that 4.0 GiB of genuine free space exists on the raw
file before boot (`Total free space is 8386594 sectors (4.0 GiB)`), so
"no free space" is not the obvious suspect — the real cause is still
open pending the next run's actual error text.

**2026-08-31 — CI run 33346716623: the diagnostic fix worked, and it
surfaced the real `sgdisk` error for the first time.** `wizard.py`'s
journal now shows the actual failure: `sgdisk -n 0:0:0 ... stderr: Could
not create partition 5 from 0 to 2047`. Per sgdisk's own documented
semantics (start=0 means "start of the LARGEST available free block"),
this means the GUEST's `sgdisk` believes the largest free block on
`/dev/vda` is a mere 2048 sectors (1 MiB, the gap between the GPT
header/array and partition 1) — not the ~4 GiB block after partition 4
that the HOST's own `sgdisk -p` confirmed exists on this exact file
right before boot. Root cause not yet determined: added a diagnostic
(`blockdev --getsize64` + `sgdisk -p` from inside the guest, logged
before the `-n` attempt) rather than guess a fix for a disagreement that
isn't understood yet — next run's journal will show whether the guest
sees the disk as genuinely smaller than the host does (a QEMU/virtio
sizing issue) or sees the right size but computes free space differently
(a GPT header/`sgdisk -e` issue).

**2026-08-31 — CI run 33350200049: real, significant architectural
finding — something grows the ROOT PARTITION TABLE ENTRY itself to fill
the whole disk during boot, before the wizard ever runs.** The
diagnostic's real output settles the disagreement cleanly:
`blockdev --getsize64 /dev/vda` = 23077060608 bytes (~21.49 GiB) —
matches the host's expected size exactly, so this is NOT a QEMU/virtio
sizing bug. But the guest's own `sgdisk -p /dev/vda` shows **partition 4
(root) as 3127296-45072350, 20.0 GiB, "Total free space is 0 sectors"** —
whereas the HOST's `sgdisk -p` on the identical file, moments before
boot, showed partition 4 as 3127296-36683742, **16.0 GiB**, with 4.0 GiB
free after it. Something between "file written to disk" and "wizard.py
runs" has grown partition 4's own GPT table entry to consume every
remaining sector — not merely grown a filesystem inside a fixed
partition (`systemd`'s GPT GROWFS attribute, bit 59 per the real
Discoverable Partitions Specification, does the latter, not the former,
so it's ruled out as the mechanism, not assumed). `systemd-repart` (which
can genuinely grow a partition into following free space at boot — a
well-known "ship a small image, let it fill whatever disk it lands on"
pattern used by several bootc/ostree-based distros) is the live
hypothesis. Added a real diagnostic (filtered `journalctl -b` for
repart/growfs/resize/GPT lines, `find /usr/lib/repart.d /etc/repart.d`,
`systemctl status systemd-repart.service`) rather than writing a fix
against an unconfirmed mechanism. **This is the actual, real blocker for
"lockbox holds five subvolumes on the boot device's remaining free
space" (SPEC.md §5/ADR-004) if confirmed** — whatever is growing root
needs to be told to stop (or constrained to the disk.toml-specified 16
GiB) before the wizard's free-space-claiming logic can ever succeed on
real, larger media, not just in this CI test.

**2026-08-31 — CI run 33353739418: ROOT CAUSE CONFIRMED for real, not
guessed.** `systemd-repart.service` is independently ruled out — its own
journal line: `systemd-repart.service - Repartition Root Disk skipped, no
trigger condition checks were met` (no `/usr/lib/repart.d` config exists
in this image, confirmed by `find` coming back empty). The real
mechanism, found in the same run's console log:
`bootc-generic-growpart.service - Bootc Fallback Root Filesystem Grow`
started and completed successfully at boot. This is `bootc`'s own,
documented fallback behavior for a "generic" install — visible in
`bootc-image-builder`'s own manifest log from earlier runs: it invokes
`bootc install to-filesystem --source-imgref ... --generic-image ...`
internally, and `--generic-image` is exactly what installs this
fallback unit, whose entire purpose is to grow root to fill whatever disk
a generic image lands on. This is the correct, intended behavior for a
generic bootc image in general — and precisely the opposite of what
SPEC.md §5/ADR-004 want for Friday Linux specifically (a genuinely
fixed-size root with the remainder left for the lockbox). **Fixed**:
`RUN systemctl mask bootc-generic-growpart.service` added to the
Containerfile; `wizard.py`'s diagnostic step now permanently confirms the
mask holds (`systemctl is-enabled` should report `masked`, never
`enabled`/a successful start) rather than trusting it silently. Not yet
re-verified by a fresh boot — next dispatch is the check.

**2026-08-31 — CI run 33357468619: the growpart mask worked, and two more
real bugs found and fixed the same round.** Console log confirms the
fix: `systemctl is-enabled bootc-generic-growpart.service` → `masked`;
the guest's own `sgdisk -p` now shows partition 4 still at 16.0 GiB with
`Total free space is 8386594 sectors (4.0 GiB)` — matching the host
exactly, no more silent growth. `sgdisk -n 0:0:0 ...` ran with **no error
this time** — the lockbox partition create step that has failed on every
previous run finally got past its first real obstacle. Also confirmed
for real, from the probe's own output: **`USR_WRITABLE=no (touch: cannot
touch '/usr/.friday-boot-test-writeprobe': Read-only file system)`** —
one of M0's three remaining acceptance lines (`/usr` read-only) is now
directly verified, not inferred.

Two more real bugs found while reading why the probe only captured a
partial picture (it stopped right after the `sgdisk -n` line, with no
visibility into whether the rest of the wizard — luksFormat, mkfs.btrfs,
subvolumes, `.firstboot-done` — succeeded):
1. `friday-firstboot.service` was `Type=simple`, which means systemd
   considers a unit "started" the instant its process forks, not when it
   exits. `friday-boot-test-probe.service`'s `After=friday-firstboot.service`
   therefore raced ahead of the actual wizard run instead of waiting for
   it to finish. Changed to `Type=oneshot` with `RemainAfterExit=yes` —
   the correct semantic type for a run-once setup script, which also
   fixes the ordering for real.
2. `friday.service` is `WantedBy=multi-user.target`, so systemd attempts
   to start it early in boot as part of reaching that target — long
   before the lockbox exists. That attempt fails
   (`Requires=friday-lockbox.mount` unsatisfiable yet — matches "Dependency
   failed for friday.service" seen in earlier runs' logs) and systemd
   does **not** automatically retry a unit whose job already failed once
   its dependency later becomes available; `ConditionPathExists` is
   checked once per start attempt, not watched continuously. Without an
   explicit re-trigger, `friday.service` would simply never start on a
   given boot even after everything it needs exists. Fixed:
   `wizard.py`'s `main()` now explicitly runs `systemctl start
   friday.service` right after writing the `.firstboot-done` marker.

Not yet re-verified by a fresh boot with both fixes in place — next
dispatch is the check, and should finally show whether `/api/health`
responds and the lockbox actually completes end to end.

**2026-08-31 — CI run 33361356886: `sgdisk -n` succeeded for real this
time (`Total free space is 8386594 sectors (4.0 GiB)` before, partition 5
created after, `Operation has completed successfully`), and then hit one
more real, simple bug that killed `create_lockbox_partition()`'s own
device-name detection.** `lsblk -no NAME <disk>` defaults to tree-view
output, gluing box-drawing glyphs onto device names whenever a device has
siblings — e.g. `├─vda1`, `└─vda4` — with no whitespace separating the
glyph from the name, so `.split()` kept them glued together. Adding a
fifth partition changes which existing entries are "last" in the tree
(`└─` vs `├─`), so the `after - before` set difference picked up the
glyph-mangled `├─vda4` as a spurious "new" entry alongside the real
`vda5`, and `sorted(...)[-1]` chose the mangled one — the log shows the
resulting nonsense literally: `new lockbox partition: /dev/├─vda4`,
followed by `cryptsetup ... /dev/├─vda4` failing with "Device
/dev/├─vda4 does not exist." Fixed: added `-l`/`--list` to every `lsblk
... NAME` call in `create_lockbox_partition()`, which forces plain list
output with no tree formatting. Not yet re-verified — next dispatch is
the check.

**2026-08-31 — CI run 33365778055: MASSIVE real progress — `bootc status`,
`/usr` read-only, and the five-subvolume lockbox are all independently
confirmed for real, with one remaining bug found.** The `Type=oneshot`
fix worked (probe now waits for the actual wizard completion, running at
~74s instead of ~56s), and the probe's own captured output gives direct,
real evidence for two of M0's three remaining checklist lines:

- **`bootc status` shows one deployment** — CONFIRMED. Real
  `bootc status --json` output: `"booted":{...,"image":{"imageDigest":
  "sha256:c691a132677d21b17564e1cbfbb854dd55bec5cf2e866624070b63a7c9154
  1ee","version":"44.20260830.0"},...},"staged":null,"rollback":null`.
  Exactly one deployment (booted), nothing staged, nothing to roll back
  to.
- **`/usr` is read-only** — CONFIRMED, a second independent time:
  `USR_WRITABLE=no (touch: cannot touch
  '/usr/.friday-boot-test-writeprobe': Read-only file system)`.
- **Lockbox is LUKS2/Argon2id with five subvolumes** — CONFIRMED. Real
  `btrfs subvolume list /friday/lockbox` output lists all five: `@home`,
  `@models`, `@workshop`, `@journal`, `@snapshots`. Real `lsblk` output
  shows the full chain for real: `vda5` (4G, `crypto_LUKS`) →
  `friday-lockbox` (crypt, btrfs, 4G, mounted at `/friday/lockbox`) — a
  genuinely LUKS2-encrypted (Argon2id, per the `cryptsetup luksFormat`
  invocation) partition, opened, formatted, and mounted, holding all five
  subvolumes SPEC.md §5 names.
- Bonus real confirmation: `findmnt /boot/efi` → `/dev/vda2 /boot/efi
  vfat rw,relatime,...` — the ESP mount path `wizard.py` assumed
  (`/boot/efi`) is correct on this real layout, no longer just an
  assumption (docs/VERIFY.md's entry on this is resolved).

**One remaining real bug**: `systemctl list-units --failed` shows
`home-friday.mount loaded failed failed Friday lockbox subvolume @home ->
/home/friday` — the `@home` subvolume mount (only) failed, while
`@models`/`@workshop`/`@journal` are not shown as failed (implying they
mounted fine, though not independently confirmed active in this same
capture). Root cause not yet determined — the console log doesn't carry
enough detail (`systemctl list-units` doesn't show the failure reason).
Fixed the code around it either way: `create_lockbox()`'s
`systemctl enable --now <4 units in one call>` used `check=True`
(the default), meaning one failing unit would raise and abort the rest of
first boot (secrets.env, the `.firstboot-done` marker, starting
`friday.service`) before they ever ran — changed to one `systemctl
enable --now <unit>` call per subvolume with `check=False`, plus an
immediate `journalctl -u <unit>` dump on failure, so (a) one mount's
failure can no longer block the other three or the rest of first boot,
and (b) the next run's log will carry the real error text for `@home`
specifically instead of just its failed status. Not yet re-verified.

**`/api/health` still did not respond within 300s on this run** — with
`@home` failed but `.firstboot-done` apparently still written (since the
other evidence shows first boot completed enough to run the probe, which
requires `.provisioned-unattended`, set early, so this doesn't by itself
prove `.firstboot-done` was reached) and `friday.service`'s own explicit
restart call added last round, whether `friday.service` is actually
running (and, if not, why) still needs to be checked directly in the next
run — `journalctl -u friday-firstboot`/`-u friday.service` reported "--
No entries --" in this run's probe capture despite clear evidence the
wizard executed, an unexplained oddity noted here rather than chased
further right now since it isn't blocking — the next run's fuller,
per-unit diagnostics should clarify incidentally.

**2026-08-31 — CI run 33370623731: same result reproduced exactly**
(different image digest, `sha256:26fd3cf6e46623f4a0e6c0ffc98386fada29d97
829cd9abcf379c2a75ded3b02`, still exactly one deployment; `/usr`
read-only; five subvolumes; `/boot/efi` confirmed; `home-friday.mount`
still failed) — confirming this is a real, reproducible bug, not a
one-off flake. The new per-unit `journalctl -u <unit>` diagnostic added
last round did **not** appear anywhere in the probe's capture, and
`journalctl -u friday-firstboot`/`-u friday.service` again reported "--
No entries --" despite unambiguous proof the wizard ran (the lockbox,
subvolumes, and mount all exist). This journal-query anomaly is now
reproduced twice and is actively hiding the real `@home` failure reason.
Rather than chase the journal mystery itself further, worked around it:
`wizard.py`'s `_log()` now also appends every line to a plain file,
`/var/log/friday-firstboot.log`, which cannot be affected by whatever is
making the journal query come up empty for this unit — the boot probe
now `cat`s that file first, plus two alternate journalctl queries
(explicit `.service` suffix, and `-t wizard.py` by syslog identifier) in
case either of those turns out to work where `-u friday-firstboot`
doesn't. Not yet re-verified — next dispatch should finally reveal why
`@home` specifically fails to mount.

**2026-08-31 — CI run 33375529053: the plain-file log workaround worked
completely, and the real `@home` failure reason is now known for
certain.** `/var/log/friday-firstboot.log`'s content (surfaced via the
probe) shows the whole wizard run end to end for the first time,
including the exact error `journalctl -u home-friday.mount` gave:
`home-friday.mount: Mount path /home/friday is not canonical (contains a
symlink). Failed with result 'resources'.` systemd's `.mount` units
categorically refuse a `Where=` path with any symlink component — `/home`
is a symlink to `/var/home` on this ostree image (the same convention
that already broke `/root`'s default `uv` cache path and `useradd -m`
earlier in this project). The other three subvolume mounts
(`@models`/`@workshop`/`@journal`) succeeded without error, confirming
their paths don't cross a symlinked top-level directory. **Fixed**:
`@home` now mounts at the real, canonical `/var/home/friday` instead of
`/home/friday` — the symlink still transparently resolves everyone else's
`/home/friday` references (Agent-Friday's `Path.home()`, `/etc/passwd`'s
recorded home dir, this same wizard's own `os.chown`/`os.walk` calls) to
the exact same place. This also plausibly explains why `friday.service`
itself reported "A dependency job for friday.service failed" even after
`.firstboot-done` was written and this wizard explicitly ran `systemctl
start friday.service`: SPEC.md §8.1's `ReadWritePaths=/home/friday` on
that unit causes systemd to implicitly add
`RequiresMountsFor=/home/friday`, which was failing right alongside the
explicit `home-friday.mount` unit — fixing the mount should resolve both
in the same run. Not yet re-verified — next dispatch is the real test of
whether `friday.service` (and therefore `/api/health`) finally comes up.

**2026-08-31 — CI run 33383110581: all four subvolume mounts succeeded
cleanly for the first time (the `@home` fix held completely), and a new
real bug then surfaced: mounting `/var/log/journal` live broke the
running `systemd-journald` instance.** Console log shows, in order:
`friday-lockbox.mount` mounted, then `var-home-friday.mount`,
`var-lib-friday-models.mount`, `var-lib-friday-workshop.mount`, and
`var-log-journal.mount` — all four `[ OK ] Mounted ...` with zero
failures. Then: `systemd-journald[644]: Failed to open
/var/log/journal/<machine-id>: Permission denied`, and **every console
log line after that point simply stops appearing** — not just the boot
probe (which never ran, no `FRIDAY-BOOT-TEST-PROBE-BEGIN` anywhere in the
whole capture this run), but everything, right up until the health-check
timeout. Root cause: `systemd-journald` had already been actively writing
to the sealed OS's own `/var/log/journal` since early boot; mounting a
brand-new btrfs subvolume directly over that live path mid-boot shadows
its open file out from under it, and journald cannot reopen the new
location without being told to. This very plausibly explains the
earlier, separately-chased "`journalctl -u friday-firstboot` comes up
empty" anomaly too — once journald can't write/reopen its own active
journal, historical queries can come up empty. **Fixed**: after the
`@journal` mount succeeds, `wizard.py` now runs `systemctl restart
systemd-journald.service` so it reopens cleanly against the new,
persistent location. Also added `restorecon -R <mountpoint>` after every
successful subvolume mount (SELinux relabeling — new content under an
existing mountpoint does not inherit the label the policy expects for
that path; a plausible related class of bug even where mounting itself
had not visibly failed). Not yet re-verified.

**2026-08-31 — CI run 33388339294: the `journalctl --flush`-shaped fix was
needed after all — `systemctl restart systemd-journald.service` fixed the
write error but broke console visibility for the rest of boot.** Console
log confirms the restart itself worked cleanly this time (no more
"Permission denied" — `Creating journal file
/var/log/journal/<machine-id>/system.journal on a btrfs file system...`
appears, then `Started systemd-journald.service`), but **every line of
console output stops appearing immediately after that restart**, for the
rest of the ~320s capture window — not just this wizard's own log lines,
but systemd's own `[ OK ] Started ...` status lines too, which come from
a different mechanism entirely. Whatever relays journal/status output to
the QEMU serial console evidently does not survive `systemd-journald`
fully stopping and respawning mid-boot. The actual boot may well have
continued fine functionally; this specific run is just blind to it via
the console-log capture method from that point on. Fixed **properly**
this time (verified against the real `systemd-journald.service(8)` man
page, not memory): `journalctl --flush` sends `SIGUSR1`, "request that
journal data from /run/ is flushed to /var/ ... to make it persistent" —
the daemon process itself never restarts, so there is nothing for a
console-forwarding mechanism to lose track of. Not yet re-verified.

**2026-08-31 — CI run 33393997810: `journalctl --flush` did NOT fix
console visibility — same exact symptom, console goes silent right after
the `@journal` mount, no boot-test probe ever fires.** All four subvolume
mounts still succeeded cleanly (confirmed in the console log up to that
point), but nothing at all appears afterward, in either this run or the
`--flush` run, for the rest of the ~320s test window. Live suspect: the
wizard's own process is genuinely **hanging**, not just becoming
invisible on console — `journalctl --flush` is documented to
synchronously wait for journald to confirm the flush completed (not just
send a signal and return), and no `_run()` call in `wizard.py` had ever
had a timeout; combined with `friday-firstboot.service`'s own
`TimeoutStartSec=infinity` and the boot-test probe's `After=
friday-firstboot.service` (`Type=oneshot`, which only proceeds once that
unit's process actually exits), a single hung subprocess call would
silently wedge the entire first boot forever with nothing to report why —
consistent with what both of the last two runs show. Fixed two ways:
(1) `_run()` now has a default 60s timeout, raising `TimeoutExpired`
(loud, logged) instead of hanging silently; (2) switched the journald
signal from `journalctl --flush` (waits for confirmation) to `systemctl
kill --signal=SIGUSR1 systemd-journald.service` (fire-and-forget —
requests the identical flush action with nothing left to hang on). Not
yet re-verified.

**2026-08-31 — CI run 33400198551: the SIGUSR1 fix worked (no hang there),
and the new 60s timeout caught the REAL hang for certain: plain
`systemctl start friday.service` blocks synchronously.** The boot probe
finally fired this time (at ~134s guest-internal time, later than usual —
consistent with a 60s stall plus a 5s restart delay). Its captured
`/var/log/friday-firstboot.log` shows the entire wizard run end to end,
including the exact new failure: `$ systemctl start friday.service` /
`TIMED OUT after 60.0s`. `systemctl start` (with no flag) blocks until the
unit's own job completes (active or failed) — `friday.service` runs a
full Python app (venv imports, memory database, etc.) that evidently
takes longer than 60s to become ready, so this script's own new timeout
fired first. Real, actionable consequence found in the same log:
`.firstboot-done` was already written one line earlier, so `main()`'s
very first check (`if FIRSTBOOT_DONE.exists(): return 0`) means the
`Restart=on-failure` retry this crash triggers will NEVER reissue the
`systemctl start` call — it just exits successfully immediately. **Fixed
by not waiting at all**: `systemctl start --no-block friday.service`
dispatches the job and returns immediately, leaving systemd to actually
bring the service up at its own pace — the real "is it ready" signal was
always meant to be `boot-test.yml`'s own HTTP polling of `/api/health`
from the host (up to 300s), not this wizard synchronously waiting on the
systemd job. Also confirmed independently good news in this same run:
`systemctl list-units --failed` → `0 loaded units listed` (nothing
failed, `friday.service` was simply still starting when the probe ran) —
and all the now-familiar real confirmations repeated cleanly again:
`bootc status` one deployment, `/usr` read-only, `/boot/efi` correct, all
five subvolumes present. Not yet re-verified with the `--no-block` fix.

**2026-08-31 — CI run 33406554274: the `--no-block` fix worked completely —
`wizard.py` now finishes cleanly in ~78s with no hang or timeout
anywhere, and every early check keeps confirming real success.** Full
`/var/log/friday-firstboot.log` capture shows the whole run end to end
without incident: lockbox created, all four subvolume mounts succeeded,
journald signalled cleanly, `secrets.env` written, `.firstboot-done`
written, `systemctl start --no-block friday.service` returned
immediately (no timeout), and the unattended file was deleted per SPEC.md
§7.6 — a totally clean run. `systemctl list-units --failed` → `0 loaded
units listed` at ~78s (nothing failed yet). `/api/health` still did not
respond within the full 300s host-side window, but the only data point
available was from ~78s into boot — far too early to know whether
`friday.service` (a full Python app: venv imports, memory database, etc.)
was still legitimately starting, or had failed later for a reason no
snapshot ever captured. **Added a second, delayed diagnostic**:
`friday-boot-test-probe-late.timer` fires a matching probe at a fixed
200s into boot (comfortably inside the 300s health-check window),
dumping `systemctl status friday.service`, its full journal, `ss -tlnp`,
and a direct in-guest `curl 127.0.0.1:3000/api/health` — giving real
visibility into `friday.service`'s eventual fate instead of only ever
seeing a too-early snapshot. `boot-test.yml` updated to display this
block too. Not yet re-verified.

## M1-M4

Not started. Per rule 4, they don't start until M0's checklist above is
checked off with real command output and an image digest recorded here —
not before.
