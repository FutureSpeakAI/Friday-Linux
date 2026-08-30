# Decisions

This file records, per SPEC.md rules 2 and 3: objections to DECIDED items,
and which default was taken for each OPEN item, plus any path choice the spec
asked to be recorded (e.g. Section 4.1's base-image fallback).

No milestone work has started (Sections 15/18 not yet received), so nothing
below is a build-time decision yet. This first entry is ground-truth
established while reading `Agent-Friday` in preparation, per the task's
instruction to record every gap between what the spec assumes and what the
code contains.

## Repo identity (not a spec item, but cost time before)

`C:\Users\swebs\Projects\Agent-Friday` is a dead Electron/TypeScript line
(package.json, vite.config.ts, tsconfig.json, node_modules — no Python, no
`services/`) sharing the `FutureSpeakAI/Agent-Friday` GitHub remote with the
real project but with no common git ancestor. The real source is
`C:\Users\swebs\Projects\friday-desktop`. See `docs/VERIFY.md` for the
confirmation commands and output.

## Challenges to DECIDED items

None yet. Sections 0-6 contain no DECIDED item the ground-truth read
contradicts at the decision level — the contradictions found are about where
things live and whether they exist at all in `Agent-Friday` today, which are
factual gaps rather than disagreements with a decision. See the executor's
report for the full gap list; the two most load-bearing are:

1. **Section 4/6 assume the residency layer can spawn `llama-server` on
   Linux.** As of `v5.7.0` it cannot — see "Gap: engine binaries are
   Windows-only" below. This isn't a challenge to the DECIDED architecture,
   it's a statement that the architecture currently has no floor to stand on
   until an upstream change lands. That upstream change is presumably in
   Section 13, not yet received.
2. **Section 2's definition attributes the hardware ladder to
   `services/residency_policy.py`.** The ladder (VRAM tier -> model id) is
   actually owned by `services/model_plan.py`; `residency_policy.py` is the
   per-role placement/refusal engine that consumes model sizes but does not
   itself define the tier table. Not a DECIDED item, so recorded here as a
   correction rather than a challenge — Friday Linux's own code should read
   the ladder from `model_plan.py`.

## OPEN items and defaults taken

None yet — no OPEN items have been reached, because Sections 7-18 (which is
where most of the spec's own OPEN items are expected to live, based on the
Section 0 outline) have not been transmitted. Sections 0-6 as received
contain no item explicitly marked OPEN.

## Gaps between spec assumptions and `Agent-Friday` ground truth

Full detail with file:line citations lives in the executor's report for this
session. Summary, ranked by how much they block Sections 0-6's architecture:

- **`FRIDAY_OS_MODE` does not exist anywhere in `Agent-Friday` at `v5.7.0`.**
  Grepped the full tree; zero hits. Section 2 defines it and Section 4 wires
  it into `friday.service`, but there is currently nothing on the app side
  for it to switch. This is almost certainly a Section 13 upstream PR; noted
  here so it isn't lost.
- **The residency layer's engine binaries are hardcoded to Windows
  `.exe` paths** — `services/residency_arbiter.py:337` (`ollama_engine_path()`
  building `...\Ollama\lib\ollama\llama-server.exe`) and `:545`
  (`self.binary = ... / "llama-server.exe"` in the seat-spawning class).
  `KNOWN_ISSUES.md` §6 confirms this in prose: "On Linux, no llama-server seat
  can load at all (the engine candidates are `.exe`), so you are Ollama-only."
  Section 6's BOM ships `llama-server-cuda`/`llama-server-vulkan` at
  `/usr/libexec/friday/`, but nothing in the app today knows to look there
  instead of a `.exe`. This has to be a Section 13 item.
- **GPU detection is NVIDIA-only.** `services/hardware_profile.py:204`
  (`detect_gpus()`) shells out to `nvidia-smi` and nothing else — no Vulkan,
  no AMD, no Intel probe anywhere in the file. `KNOWN_ISSUES.md` §6: "AMD GPUs
  are invisible on every platform — `nvidia-smi` is the only probe." Section 3
  commits Friday Linux to Tier 2 support for AMD RDNA2+ and Intel Arc via
  Vulkan; the upstream hardware profiler cannot see those cards at all today.
- **The vault passphrase has no durable home on Linux without the `keyring`
  extra, and Section 6's venv extras list does not include `keyring`.**
  `services/vault_passphrase.py:305-343` (`store()`) writes to the OS keychain
  via the `keyring` package if importable, and to a DPAPI-wrapped file if
  `dpapi_available()` (`os.name == "nt"`, hardcoded Windows-only). On Linux
  without `keyring` installed, both branches no-op and `store()` returns `[]`
  — the function's own docstring: "An empty return means nothing durable could
  be written." This is exactly what Stephen flagged as tonight's finding.
  Fix is plausibly two-sided: add `keyring` to the venv extras (it does
  support Linux via Secret Service/kwallet) *and* Section 6's BOM would need
  to add a Secret Service provider or equivalent to the image, since none is
  currently listed. Whether that's the intended fix or whether Section 13
  does something else is unknown without Section 13.
- **`pystray` aborts test collection when absent.** Single unconditional
  `import pystray` at `src/agent_friday/friday_tray.py:21`. The `[windows]`
  extra gates it at install time (`pyautogui`, `pynput`, `pillow`,
  `pystray`), and Friday Linux's extras list correctly omits `[windows]`, so
  the *installed image* is fine. The gap is in the *test suite*: something
  under `tests/` imports `friday_tray` (transitively or directly) without a
  platform/import guard, so pytest collection aborts on any machine — Linux
  CI included — that doesn't have `pystray` installed. Relevant to Section 16
  (tests), not yet received, but worth surfacing now since it'll block CI on
  this repo the moment tests are added if upstream doesn't fix it first.

## Path taken for Section 4.1 fallback

Not yet applicable — no image build has started. `docs/VERIFY.md` lists the
commands needed to check whether the NVIDIA-enabled minimal Universal Blue
base exists in kiosk-suitable form before this decision can be made for real.
