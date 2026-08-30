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

**None of M0's acceptance checklist has been executed:**
- [ ] `podman build` succeeds — **cannot run**: no `podman` in this
      Windows sandbox, and even with one, the venv-install step is blocked.
- [ ] `bootc-image-builder` raw image ≤ 8 GB compressed — **cannot run**:
      same blocker, plus `docs/VERIFY.md`'s `disk.toml` schema question is
      still open.
- [ ] QEMU/KVM boots it, `/api/health` 200 within 300 s — **cannot run**:
      no KVM in this sandbox; also nothing to serve `/api/health` yet
      (below).
- [ ] `bootc status` one deployment, `/usr` read-only — **cannot run**.
- [ ] Lockbox is LUKS2/Argon2id with five subvolumes — **cannot run**;
      also the wizard stub deliberately raises `NotImplementedError` for
      this step rather than shipping unverified `cryptsetup` syntax (see
      `docs/DECISIONS.md` Deviations).

**Why M0 cannot pass yet, ranked by how hard a blocker each is:**

1. **`build/agent-friday.pin` is unresolved.** §13's own landing order
   states M0 needs PR-1 through PR-3 merged into `Agent-Friday` upstream
   first. Checked both `v5.7.0` and current `friday-desktop` HEAD: neither
   exists. There is no tag or commit to install where `FRIDAY_OS_MODE` does
   anything, `core/paths.py` exists, or the app installs from a git tag
   without a full clone. This is `Agent-Friday`-repo work, not
   `Friday-Linux`-repo work, and it gates everything downstream of it in
   this checklist. **This is the critical path for the whole project right
   now.**
2. **No Linux/KVM build-and-boot environment.** This sandbox is Windows
   11 with Git Bash/PowerShell only — no `podman`, no `bootc`, no
   `bootc-image-builder`, no KVM. Even once (1) is resolved, M0's
   acceptance checklist requires running these somewhere that can actually
   run them: a real Linux machine, WSL2 with nested virtualization, or the
   `ci/*.yml` workflows on GitHub's `ubuntu-latest` runners once this repo
   has a remote (not created yet — see the note to Stephen below).
3. **Several external facts are still unverified** per `docs/VERIFY.md`:
   the exact Universal Blue base image ref (§17 Q4), the Fedora release to
   pin (§17 Q5), the `llama.cpp` tag, Fedora package availability for the
   full §6/§8 BOM, `bootc-image-builder`'s current `disk.toml` schema, and
   the `cosign` invocation for §10.3. None of these block *authoring* the
   scaffold — they block the Containerfile actually building.

**Next concrete steps, in order:** get PR-1/2/3 opened and merged in
`Agent-Friday` (or confirm a different plan for M0's app install — not this
repo's call to make unilaterally); answer VERIFY.md's Q4/Q5 and the
`disk.toml`/`cosign` questions; then run `ci/build.yml` and `ci/boot-test.yml`
on a real Linux+KVM runner and record the actual results here.

## M1-M4

Not started. Per rule 4, they don't start until M0's checklist above is
checked off with real command output and an image digest recorded here —
not before.
