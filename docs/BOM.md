# Bill of Materials

Per SPEC.md Section 6: everything installed in the Containerfile, pinned,
with versions extracted from the *built* image. This file is empty of real
entries because no Containerfile exists yet — Section 14 (repo layout) and
the fallback path in Section 4.1 aren't decided, so there's nowhere to build
from and nothing to extract a version out of.

Structure this file will take once a build exists, so the shape is at least
decided:

## System packages

| Package | Pinned version | Source | Extracted from |
|---|---|---|---|
| (none yet) | | | |

## Inference binaries

| Binary | llama.cpp tag | Build flags | Compute target |
|---|---|---|---|
| `llama-server-cuda` | (unpinned — see VERIFY.md) | `GGML_CUDA=ON` | cc 7.5+ |
| `llama-server-vulkan` | (unpinned — see VERIFY.md) | `GGML_VULKAN=ON` | — |

## Application

| Item | Pin | Notes |
|---|---|---|
| `Agent-Friday` | Candidate: `v5.7.0` (see below) | Not yet confirmed as the final pin — depends on whether Section 13's required upstream PRs land on top of it or require a later tag. |
| Python | 3.12 (Fedora's) | Per spec; not yet verified against the chosen base image's default Python. |
| venv extras | `[voice-local-lite,local,compression,federation,google,compose,provenance]` | All seven confirmed to exist in `Agent-Friday`'s `pyproject.toml` at `v5.7.0` — see confirmation below. |
| `build/agent-friday.lock` | not yet generated | Spec requires a committed lockfile; none exists in this repo yet. |

### Extras confirmation (v5.7.0, `pyproject.toml`)

Checked each of the seven named extras against
`friday-desktop/pyproject.toml` at tag `v5.7.0`:

- `voice-local-lite` — exists (`faster-whisper`, `piper-tts`, `onnxruntime`)
- `local` — exists (`sentence-transformers`, `chromadb`)
- `compression` — exists (`headroom-ai[all]`)
- `federation` — exists (`pynacl`)
- `google` — exists (`google-api-python-client`, `google-auth-oauthlib`)
- `compose` — exists (`imageio-ffmpeg`)
- `provenance` — exists (`mutagen`)

All seven are real. No substitutions needed. Notably absent from both this
list and from `[all]`'s Windows-only members: `pyautogui`, `pynput`,
`pystray` are gated `sys_platform == 'win32'` inside `[all]` and are only
unconditionally pulled by the separate `[windows]` extra — which Section 6
correctly excludes. See `docs/DECISIONS.md` for the caveat about `keyring`
(an eighth extra that exists in `pyproject.toml` but is not in Section 6's
list, and appears to be required for the vault passphrase to have any
durable home on Linux).

### Agent-Friday pin candidate: v5.7.0

Confirmed via `git log -1 --format=%ai v5.7.0`: tagged 2026-08-29 17:47:35.
Current `friday-desktop` working tree (branch `wip/vibe-terminal-persistence`)
is 4 commits ahead of this tag, all docs/WIP commits explicitly marked
"INCOMPLETE, DO NOT SHIP" — none of the four look like Section 13 material,
but Section 13 hasn't been received to confirm either way.

## Voice assets

| Asset | Version | Source |
|---|---|---|
| Piper voice | app's current default — not yet identified by name | TBD |
| Whisper `small.en` CTranslate2 INT8 | not yet pinned | TBD |

## Fonts

Per spec list; not yet verified against Fedora repos (see VERIFY.md).
