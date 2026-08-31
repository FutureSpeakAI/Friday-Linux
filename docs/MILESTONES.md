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

## M1-M4

Not started. Per rule 4, they don't start until M0's checklist above is
checked off with real command output and an image digest recorded here —
not before.
