# Verify

Per SPEC.md rule 5: facts about the environment that cannot be checked from
inside this sandbox get the exact command to run, plus the most likely value
clearly marked as unverified. Nothing here is a real version pin — pins get
extracted from a real build and recorded in `docs/BOM.md`.

## Repo identity — already run, output kept for the record

Confirms `friday-desktop` is the real `Agent-Friday` source and
`Agent-Friday` (the identically-named local checkout) is the dead Electron
decoy sharing the same remote.

```sh
test -f "C:/Users/swebs/Projects/friday-desktop/src/agent_friday/services/residency_policy.py" && echo FOUND
test -f "C:/Users/swebs/Projects/friday-desktop/KNOWN_ISSUES.md" && echo FOUND
cd "C:/Users/swebs/Projects/friday-desktop" && git tag | grep -E "v5\.[67]" | sort -V
cd "C:/Users/swebs/Projects/Agent-Friday" && git remote -v && ls   # package.json, vite.config.ts, node_modules — no Python
```

Result: `friday-desktop` has both files; tags `v5.6.0`-`v5.6.6`, `v5.7.0`
exist there. `Agent-Friday` shares the same `origin` remote URL but has no
`services/` directory, no `KNOWN_ISSUES.md`, and is a TypeScript/Electron
tree with zero common git ancestor with `friday-desktop`.

## Not yet run — needed before any Containerfile is written

### Universal Blue base image names and digests (Section 4.1)

```sh
skopeo inspect docker://ghcr.io/ublue-os/base-main:latest
skopeo inspect docker://ghcr.io/ublue-os/base-nvidia:latest
# If an NVIDIA variant of the *minimal* (non-desktop) base doesn't exist under
# an obvious name, check the akmods-nvidia layering path instead:
skopeo inspect docker://ghcr.io/ublue-os/akmods-nvidia:latest
```
Most likely value if asked to guess today: `ghcr.io/ublue-os/base-main` is a
real, actively published Universal Blue image as of general knowledge through
January 2026; whether an NVIDIA-flavored *minimal* variant exists under that
exact name, and what its current digest is, is not something to assert
without running the command above. **Do not pin a digest from memory.**

### `ggml-org/llama.cpp` tag to pin (Section 6)

```sh
gh api repos/ggml-org/llama.cpp/tags --paginate | head -50
gh api repos/ggml-org/llama.cpp/releases/latest
```
llama.cpp does not use stable semantic versioning; it tags frequently
(`b####` build numbers historically). Pin whatever tag that command returns
at build time, and record the commit SHA, not just the tag name, in
`docs/BOM.md`.

### Fedora package availability for the Section 6 BOM

```sh
# Run inside the actual base image / a matching Fedora container, not the host:
dnf repoquery --available cage chromium caddy greenboot cryptsetup btrfs-progs \
  mesa-vulkan-drivers vulkan-loader vulkan-tools pipewire wireplumber \
  pipewire-pulseaudio bluez nftables chrony NetworkManager-wifi \
  google-noto-sans-fonts google-noto-emoji-color-fonts google-noto-sans-cjk-fonts \
  avahi cups
```
Package names above are written as they are commonly spelled in Fedora
repos; confirm each resolves before it goes in a Containerfile. `caddy` in
particular is sometimes only available via a COPR, not the base Fedora repos
— check for that specifically.

### CUDA compute-capability / runtime library set for `llama-server-cuda`

```sh
# Once llama.cpp is built with GGML_CUDA=ON against a pinned CUDA container tag:
ldd /path/to/build/bin/llama-server | grep -i cuda
nvidia-smi --query-gpu=compute_cap --format=csv   # on the actual RTX 4070 reference machine
```
Section 6 specifies "compute capability 7.5 and up" and "the minimal set
`llama-server-cuda` links against" — both need to come from an actual build,
not be assumed.

### `keyring` Linux backend availability (surfaced by the vault-passphrase gap in DECISIONS.md)

```sh
dnf repoquery --available gnome-keyring libsecret kwallet5
python3 -c "import keyring; print(keyring.get_keyring())"   # inside the target image, with a Secret Service provider running
```
Needed to determine whether adding `keyring` to the venv extras is
sufficient on its own, or whether Section 6's system package list is also
missing a Secret Service provider — this sandbox cannot run a Secret Service
daemon to check.

## Explicitly not verified, and not to be guessed

- Section 13's actual required upstream PRs (not received).
- Section 15 milestone list and Section 16 acceptance tests (not received) —
  nothing above should be treated as a milestone gate until those arrive.
