# Verify

Per SPEC.md §18 rule 2: every external fact this spec assumes that cannot be
checked from inside this sandbox, with the exact command to run. Stephen
runs these and returns results before M0 is declared done. Per rule 5,
values below are the most likely candidate, clearly marked as unverified —
none is a real pin.

**Standing limitation, not itself a §17 item but load-bearing for everything
below it:** this sandbox is Windows 11 (win32), with Git Bash / PowerShell
only. There is no `podman`, no `bootc`, no `bootc-image-builder`, no KVM, and
no Linux container runtime available here. Every command in this file that
needs to actually build, sign, or boot the image must run on a Linux host
with KVM (a real machine, WSL2 with nested virtualization enabled, or GitHub
Actions' `ubuntu-latest` runners per §16.2) — not in this session. Anything
in `M0`'s acceptance checklist that requires execution stays unchecked in
`docs/MILESTONES.md` until it runs somewhere that can actually run it.

## Already run, output kept for the record

### Repo identity

```sh
test -f "C:/Users/swebs/Projects/friday-desktop/src/agent_friday/services/residency_policy.py" && echo FOUND
test -f "C:/Users/swebs/Projects/friday-desktop/KNOWN_ISSUES.md" && echo FOUND
cd "C:/Users/swebs/Projects/friday-desktop" && git tag | grep -E "v5\.[67]" | sort -V
cd "C:/Users/swebs/Projects/Agent-Friday" && git remote -v && ls
```
Result: `friday-desktop` has both files; tags `v5.6.0`-`v5.6.6`, `v5.7.0`
exist there. `Agent-Friday` shares the same `origin` remote URL but is a
TypeScript/Electron tree (package.json, vite.config.ts, node_modules) with
no `services/` directory and no common git ancestor with `friday-desktop`.

### Ladder, `PORT_BASE`, and extras — confirmed against v5.7.0

Ladder in `README.md` (lines 73-79 at v5.7.0) matches §2's table exactly.
`PORT_BASE = 8090` confirmed at `services/residency_arbiter.py:47`. All
seven extras named in §6 (`voice-local-lite`, `local`, `compression`,
`federation`, `google`, `compose`, `provenance`) confirmed present in
`pyproject.toml` at v5.7.0 — see `docs/BOM.md`.

## Q4 (§17, blocking for M0): Universal Blue base image name and digest

```sh
skopeo inspect docker://ghcr.io/ublue-os/base-main:latest
skopeo inspect docker://ghcr.io/ublue-os/base-nvidia:latest
# If no minimal (non-desktop) NVIDIA variant exists under an obvious name,
# check the fallback layering path instead:
skopeo inspect docker://ghcr.io/ublue-os/akmods-nvidia:latest
```
Do not pin a digest from memory — §17's own default assumes the answer may
be "no," in which case ADR-002's fallback path (`fedora-bootc` +
`akmods-nvidia`) is taken and recorded in `docs/DECISIONS.md`.

## Q5 (§17, blocking for M0): Fedora release to pin

```sh
skopeo inspect docker://registry.fedoraproject.org/fedora-bootc:latest | grep -i version
```
§17 writes "44 at time of writing" as the default — that number came from
Stephen's draft, not from a check run here. Confirm current stable before
pinning; Fedora's release cadence means this may already have moved.

## `ggml-org/llama.cpp` tag to pin (§6, §14 `build/llama.cpp.pin`)

```sh
gh api repos/ggml-org/llama.cpp/tags --paginate | head -50
gh api repos/ggml-org/llama.cpp/releases/latest
```
llama.cpp does not use stable semantic versioning; historically it tags
frequently (`b####` build numbers). Pin the tag returned by this command at
build time and record the commit SHA, not just the tag name, in
`docs/BOM.md`.

## CUDA compute-capability / minimal runtime library set (§6)

```sh
# Once llama.cpp is built with GGML_CUDA=ON against a pinned CUDA container tag:
ldd /path/to/build/bin/llama-server | grep -i cuda
nvidia-smi --query-gpu=compute_cap --format=csv   # on R1, the RTX 4070 reference machine
```

## Fedora package availability for the §6/§8 BOM

```sh
dnf repoquery --available cage chromium caddy greenboot cryptsetup btrfs-progs \
  mesa-vulkan-drivers vulkan-loader vulkan-tools pipewire wireplumber \
  pipewire-pulseaudio bluez nftables chrony NetworkManager-wifi \
  google-noto-sans-fonts google-noto-emoji-color-fonts google-noto-sans-cjk-fonts \
  avahi cups
```
`caddy` in particular is sometimes only in a COPR, not base Fedora repos —
check that specifically. Run inside the actual base image once Q4 is
answered, not against the host.

## `keyring` Linux backend availability (surfaced by the vault-passphrase gap in DECISIONS.md)

```sh
dnf repoquery --available gnome-keyring libsecret kwallet5
python3 -c "import keyring; print(keyring.get_keyring())"   # inside the target image, with a Secret Service provider running
```
Needed to determine whether adding `keyring` to the venv extras is
sufficient on its own for PR-5's fix to have anywhere durable to write on
Friday Linux, or whether §6's system package list also needs a Secret
Service provider added.

## `bootc-image-builder` disk customisation syntax for `build/disk.toml` (§5, §14)

```sh
podman run --rm quay.io/centos-bootc/bootc-image-builder:latest --help
# and the disk-config TOML schema:
podman run --rm quay.io/centos-bootc/bootc-image-builder:latest \
  --config /dev/null --help-config 2>&1 || true
```
§5's four-partition layout (ESP/boot/root/lockbox-left-for-firstboot) needs
to be expressed in whatever `disk.toml` schema the current
`bootc-image-builder` release actually accepts; that schema has changed
across releases and should not be guessed from an older example.

## `greenboot` required-check path and script contract (§11.2, §14)

```sh
rpm -ql greenboot | grep required.d
man greenboot-healthcheck   # or: greenboot --help, if installed
```
§11.2 assumes scripts drop into `image/greenboot/required.d/` and are copied
to the path greenboot actually scans; confirm that path and the exit-code
contract (0 = pass) against the installed package rather than assuming it
matches upstream greenboot's GitHub README, which can drift from what
Fedora/Universal Blue ships.

## GitHub-hosted runner KVM availability for `ci/boot-test.yml` (§16.2)

```sh
gh api /repos/FutureSpeakAI/Friday-Linux/actions/runners  # once the repo exists
# or, inside a throwaway workflow run:
ls -la /dev/kvm && kvm-ok
```
§16.2 states GitHub-hosted Ubuntu runners expose KVM; this has been true on
standard `ubuntu-latest` runners but is worth a smoke-test workflow before
relying on it, since GitHub has changed runner images and nested-virt
availability before without much notice.

## `mokutil`/`ujust enroll-secure-boot-key` exact invocation (§7.2, §10.4)

```sh
ujust --list | grep -i secure-boot
mokutil --sb-state
```
§7.2 names both `ujust enroll-secure-boot-key` and "the underlying `mokutil
--import`" as alternatives; confirm which one the chosen Universal Blue base
(once Q4 is answered) actually ships, since `ujust` recipes are
base-image-specific.

## TPM2 tooling for `install-to-disk` (§5, M4)

```sh
systemd-cryptenroll --tpm2-device=list
```
§5/§14 assume TPM2-bound passphrase fallback via `friday os install-to-disk`
(M4 only — not needed for M0-M3). Confirm `systemd-cryptenroll` version and
TPM2 support on R1/R2 before M4 planning; not a blocker now.

## cosign / sigstore keyless signing identity (§10.3)

```sh
cosign sign --help | grep -i oidc
```
§10.3 assumes GitHub OIDC keyless signing plus an offline key for release
tags; confirm the exact `cosign` invocation and `containers-policy.json`
schema version against whatever `cosign` release CI actually pins, once CI
is scaffolded.

## 2026-08-30 — Fedora package availability: RESOLVED via actual CI `dnf install` (no COPR needed)

CI run 33319006210 (`podman build` on `ubuntu-latest`) ran the full §6/§8 BOM
`dnf install` against `registry.fedoraproject.org/fedora-bootc:44` for real:
`linux-firmware mesa-vulkan-drivers vulkan-loader vulkan-tools NetworkManager
NetworkManager-wifi nftables chrony pipewire wireplumber
pipewire-pulseaudio bluez cage chromium caddy greenboot cryptsetup
btrfs-progs google-noto-sans-fonts google-noto-emoji-color-fonts
google-noto-sans-cjk-fonts`. All 271 transaction steps completed
(`Complete!`), including `caddy-0:2.10.2-9.fc44` and `chromium-0:151.0.7...`
straight from Fedora's own repos — **no COPR needed for `caddy`**, contrary
to this file's earlier flag. Superseded: the `dnf repoquery` command listed
above under "Fedora package availability for the §6/§8 BOM" is no longer
needed; the real install is the stronger check and it passed.

## Explicitly not verified, and not to be guessed

- Whether the specific §13 upstream PRs have actually been opened/merged
  against `Agent-Friday` — that's tracked in `Agent-Friday`'s own repo, not
  here, and this repo's M0-M4 gating depends on their real merge state per
  §13's landing order, not on this document's description of them.
- Exact wording Stephen wants in `docs/TRADEMARKS.md` pending his own read
  of the Fedora remix guidelines (§17 Q6) — default text noted in
  MILESTONES.md but not drafted here.

## 2026-08-30 — Step B1 (WSL2 build environment): DEFERRED, collision risk detected

Dispatched to set up a WSL2 Ubuntu environment (podman rootful + skopeo +
qemu-system-x86 + ovmf + bootc-image-builder pull + KVM/loop-device checks)
per Step B1. Executed the required pre-flight re-verification before touching
anything, per the dispatch's collision-hazard warning about the concurrent
`Friday-Models` (Gemma fine-tuning) mission also planning WSL2 + `.wslconfig`
for CUDA training.

**Prior `.wslconfig`:** did not exist at `%USERPROFILE%\.wslconfig` (`cat`
returned "No such file or directory"). No change was made to it — see below.

**Running-distro check (fresh, at time of check):**
```
wsl --list --running
> There are no running distributions.

wsl --list --verbose
  NAME                   STATE     VERSION
* docker-desktop         Stopped   2
  Ubuntu-24.04            Stopped   2
```
Nothing is currently running. However, this itself is new information: the
orchestrating session's "moments ago" pre-check reported `wsl --list
--verbose` showing **only** `docker-desktop`, with **no Ubuntu distro
registered at all**. My fresh check shows `Ubuntu-24.04` now registered
(Stopped). That distro was not there moments ago and is there now.

**Decisive evidence of concurrent active work:** checking
`C:\Users\swebs\Projects\Friday-Models` for signs of an active job (per the
dispatch's heuristic) found:
- `git log -3`: HEAD is `9c489d3`, "M0: scaffold repo layout, copy spec
  verbatim, record initial environment/GPU/WSL2 findings" — committed
  2026-08-30 09:29:28, i.e. minutes before this check.
- `git status`: one untracked path, `env/`.
- `env/wslconfig.example` (untracked, so postdates that commit) has mtime
  **09:35**, i.e. **about one minute before** this check was run (checked at
  09:36). Its contents:
  ```
  [wsl2]
  memory=26GB
  swap=16GB
  ```

This is a live session actively iterating on WSL2/`.wslconfig` planning for
Friday-Models *right now*, not a stale scaffold from hours ago. The newly
appeared `Ubuntu-24.04` registration is consistent with that same concurrent
session having already begun WSL2 setup on its own. Per the dispatch's
explicit instruction ("if there's any other evidence of an active
long-running job in WSL... DO NOT run `wsl --shutdown`"), this qualifies.

**Decision: deferred.** Did not write/modify `.wslconfig`, did not run `wsl
--shutdown`, did not touch the newly-registered `Ubuntu-24.04` distro, and
did not install anything inside it. No WSL state was changed by this
session. `Ubuntu-24.04`'s existing packages (if any) were not inspected
beyond the `wsl --list --verbose` listing above, to avoid any interaction
with a distro another session may currently be provisioning.

**Fallback:** per the governing spec's Amendment A1, Step B2 (GitHub Actions
`ubuntu-latest` runners) should be used for the build-and-boot steps instead
of a local WSL2 podman+QEMU/KVM environment, until this collision risk with
Friday-Models' concurrent WSL2 use clears (i.e. until that session's
`.wslconfig`/distro work is confirmed finished and no job is live inside
WSL2).

**Recommended next step for Stephen:** re-run Step B1 once Friday-Models'
WSL2 work is confirmed idle (no running distro, no fresh commits/file
activity in that repo's `env/`, `train/`, `logs/`, `artifacts/` in the last
few hours). At that point the `.wslconfig` block this task would have
written is still just:
```
[wsl2]
nestedVirtualization=true
memory=26GB
```
merged non-destructively with whatever Friday-Models' own `.wslconfig` needs
turn out to be (note its example file wants `swap=16GB` too, which B1 did
not ask for — reconcile the two missions' `.wslconfig` requirements with
Stephen before writing a shared file, since both are Windows-machine-global,
not per-project).

**Confirmed by the owning session (projects-0b, 2026-08-30):** Friday-Models'
WSL2 setup is real, active work, not a stale scaffold — `Ubuntu-24.04` is
installed, `.wslconfig` (`memory=26GB swap=16GB`) is applied, and a CUDA
toolkit + `llama.cpp` (CUDA) build was starting at time of contact. `wsl
--shutdown` must not run until that session signals a safe window. No GPU
contention expected either, since Friday Linux's QEMU boot tests don't need
the GPU and are running via GitHub Actions instead (see B2/B3 below).

## 2026-08-30 — Step B2: GitHub remote created

Per Stephen's explicit go-ahead (checkpoint required by the dispatch before
touching any GitHub remote): created the private repo
`FutureSpeakAI/Friday-Linux`, pushed `main`. `gh auth status` was already
confirmed authenticated (FutureSpeakAI account, `repo` scope) before this.

**Bug found and fixed:** `ci/build.yml` and `ci/boot-test.yml` (SPEC.md §14's
named paths) were never picked up by GitHub Actions after the push —
`gh api repos/FutureSpeakAI/Friday-Linux/actions/workflows` returned
`{"total_count":0}` despite `build.yml` having a `push: branches: [main]`
trigger. Root cause: GitHub Actions only discovers workflows under
`.github/workflows/`, not an arbitrary `ci/` directory. Moved both files
there with `git mv` (content unchanged); confirmed registered
(`total_count: 2`) and running after the next push. Recorded as a deviation
in `docs/DECISIONS.md`.

Both workflows are now genuinely gating (not skipped, not silently green):
- `build` failed at its deliberate `exit 1` "Fail fast if pins are
  unresolved" step before this session's pin-resolution work below (expected
  — `build/llama.cpp.pin` didn't exist yet and `agent-friday.pin` still held
  its pre-Amendment-A1 placeholder text).
- `boot-test` failed immediately with "workflow file issue" on the same push
  that introduced it, because it references `workflow_run: workflows:
  [build]` and `build` hadn't completed a run yet at that point in the same
  push. Expected to resolve itself once `build` has completed at least one
  run under its current name; watch the next push to confirm rather than
  assuming.

## 2026-08-30 — Q4/Q5/llama.cpp pin: RESOLVED via registry API (no skopeo on this Windows host — used token-authenticated `curl` against the same v2 registry API skopeo would use)

**Q4 (Universal Blue base image):** `ublue-os/base-nvidia` (the NVIDIA-enabled
minimal base ADR-002 wanted first) is confirmed dead — `curl` against
`https://ghcr.io/v2/ublue-os/base-nvidia/tags/list` returns tags no newer
than 2023 (`37-*`, `pr-42`), nothing referencing a current Fedora release.
Its sibling `ublue-os/base-main` is alive and rebuilt daily (`tags/list`
shows `44`, `44-20260611`, `latest-20260611` etc.) but has no NVIDIA variant.
So ADR-002's own documented fallback applies: base directly on
`fedora-bootc`, and layer NVIDIA support in separately for GPU milestones
rather than getting it "for free" from the base image.

**Q5 (Fedora release):** confirmed via
`registry.fedoraproject.org/v2/fedora-bootc/tags/list` (no auth token
required, unlike ghcr.io) — tags run `40` through `46` plus `rawhide`.
Compared digests with `curl -D-` (Docker-Content-Digest response header):
`fedora-bootc:latest` and `fedora-bootc:44` return the identical digest
(`sha256:e8f93cc9b1a0089216c674d5d9e8319e8cc40911dc9ee23d07d49ceea5177590`),
while `45` and `46` are different (newer/branched, not yet "latest"). **44 is
confirmed current stable**, matching §17's own default guess — but confirmed
by digest comparison, not assumed. Pinned by digest in the Containerfile.

**New finding, not anticipated by SPEC.md or DECISIONS.md before now: a real
Fedora-version mismatch that blocks M2, not M0.** `ublue-os/akmods-nvidia`
(the fallback NVIDIA kmod source ADR-002 names) is alive, but its only
current kmod builds target `coreos-stable-42` and `centos-10` kernels —
**nothing for Fedora 44.** `curl` against
`https://ghcr.io/v2/ublue-os/akmods-nvidia/tags/list` shows no `44` or
`fc44` tag of any kind. Pinning the base to Fedora 44 (correct for M0, which
needs no GPU per SPEC.md §15) means akmods-nvidia's NVIDIA kmod cannot be
layered onto this exact base as-is when M2 needs it — a kernel/kmod version
mismatch is normally fatal (kmods only load against the exact kernel they
were built for). Options for M2, none decided here: (a) wait for Universal
Blue to publish a Fedora-44-matched akmods-nvidia build, (b) move this
project's base pin back to Fedora 42 to match akmods-nvidia's current build
(costs the newer base's fixes/packages), (c) source NVIDIA kmods some other
way. Flagging now, before M2 planning starts, rather than letting it surface
as a build failure later.

**llama.cpp tag:** `gh api repos/ggml-org/llama.cpp/releases/latest` →
`v0.3.0`, published 2026-08-25; `target_commitish`
`c1d0e7a004015f23bc0233470b747b596f29b264`. Note SPEC.md's own text warned
llama.cpp "does not use stable semantic versioning... tags frequently with
`b####` build numbers" — that appears to be stale relative to the project's
current practice, which uses `vX.Y.Z` release tags now. Recorded both the
tag and the commit SHA in `build/llama.cpp.pin` per rule 5.

**What's still open, deliberately not guessed:** `build/build-llama.sh`
(compiles `llama-server-vulkan` for M0; `-cuda` comes later), the Vulkan
build's exact CMake flags, `build/disk.toml` (bootc-image-builder's disk
customisation schema — still unverified per the entry above), and
`build/agent-friday.lock` (a real lockfile for the Amendment-A1 editable
-install path, which doesn't match the git-tag-install path the originally
planned lockfile assumed). These block `build.yml` from getting past its
next step once pins stop being the first failure; left for the M0 execution
pass rather than authored here without ever having run them.

## 2026-08-30 — Unresolved CI quirk: `boot-test.yml` fails pre-job with "workflow file issue"

On both pushes so far, `.github/workflows/boot-test.yml` completes as a
failed run with **zero jobs created** (`gh api .../jobs` returns
`{"total_count":0}`, no check-run output text available via the API) even
though its YAML validates by inspection (no CRLF, no BOM, no tabs, correct
2-space indentation — checked with `cat -A` on the exact committed blob via
`git show`). GitHub's UI attributes it to "a workflow file issue" but the
API surfaces no annotation explaining which line/key. Its trigger is
`workflow_run: workflows: [build]` (matching `build.yml`'s `name: build`,
confirmed via the registered-workflows list) plus `workflow_dispatch:`.
Not chased further because every step in this file is a placeholder TODO
(SPEC.md §16.2 isn't implementable until M0's build succeeds) — nothing of
substance runs there yet regardless. Whoever picks up the boot-test
implementation for real should re-diagnose this from scratch rather than
assume the trigger block above is correct just because it looks right.
