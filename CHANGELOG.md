# Changelog

## v1.0.0 — 2026-06-13

Initial filesystem-only release. Built, seeded into a live 4-agent project, smoke-tested against the
BUILD-SPEC §10 scenarios, installed machine-global, and in active coordination use by day 2.

- **Engine** (`bin/brain`, POSIX sh): `init`, `install`, `new-feature`, `whoami`, `announce`,
  `status`, `reconcile` (validate + auto-resolve/downgrade), `commit` (locked, secret-scanned,
  ff-only), `wrap` (self-contained closeout = reconcile + commit-from-main), the governance gauntlet
  (`propose`/`apply`/`revert`), and the `hook` entry point.
- **Identity**: positional-slug exact-token matching against `owns_branches` (§2a) — `graph` ≠
  `langgraph`, the cockpit double-match killed, `main`-resident features resolve without an override.
- **Hooks** (global dispatcher only, no double-fire): SessionStart (orient + reconcile) and PreToolUse
  (non-blocking collision gate).
- **`/wrap` integration**: presence sync + reconcile (Phase 1), durability commit (Phase 4, main
  worktree only), research-stays-put note (Phase 6).
- **Templates**: presence / connection / journal / research / INDEX / the `navigation-standards` skill.
- **Notable build decisions**: `flock` → atomic `mkdir` lock (macOS has no flock); hooks live only in
  the global settings dispatcher because `.claude/settings.json` is gitignored; `BRAIN_TEST_BRANCH`
  test seam; `.brain/.gitignore` keeps runtime artifacts + Obsidian config + the Phase-2 index DB out
  of commits.

**Public-release hardening (pre-publish):**
- Genericized the engine — the default branch is now configurable (`BRAIN_MAIN_REF`, default
  `origin/main`) and the secret-scan denylist path is generic (`BRAIN_SECRET_DENYLIST` /
  `<vault>/secret-denylist.txt`) instead of an Enterprise-repo path.
- Fixed the `commit`/`wrap` secret-scan false-positive that aborted on the engine's own `VERSION=`
  line — the scan now skips `bin/` and `templates/` (code, not note content) and still catches real
  env-shaped secrets in notes.
- Added the harness-neutral `brain wrap` so persistence doesn't depend on any specific `/wrap`.

See [ROADMAP.md](ROADMAP.md) for known issues and the deferred Phase 2 / v2 work, and
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) for dependencies.
