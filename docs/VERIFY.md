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

## Explicitly not verified, and not to be guessed

- Whether the specific §13 upstream PRs have actually been opened/merged
  against `Agent-Friday` — that's tracked in `Agent-Friday`'s own repo, not
  here, and this repo's M0-M4 gating depends on their real merge state per
  §13's landing order, not on this document's description of them.
- Exact wording Stephen wants in `docs/TRADEMARKS.md` pending his own read
  of the Fedora remix guidelines (§17 Q6) — default text noted in
  MILESTONES.md but not drafted here.
