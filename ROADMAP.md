# Roadmap & Enhancements

What's deferred, what's known-broken-but-minor, and the decisions we made about what *not* to build.
v1 is filesystem-only and deliberately small; this is the backlog for "further development."

---

## Known issues (small, recorded — none block v1)

1. **`reconcile` touches-refresh reads the main worktree's diff, not the agent's own.**
   In `cmd_reconcile`, the auto-refresh runs `git -C "$ROOT" diff --name-only origin/main`, where
   `$ROOT` is the *main* worktree (from `brain_root`). For a sibling agent it should diff the agent's
   **own** worktree (`git rev-parse --show-toplevel`). Low impact today because agents set their own
   `touches` during `/wrap`, but the auto-refresh can write main's diff into a sibling's note.
   **Fix:** diff the local worktree (`show-toplevel`), not `$ROOT`.

2. **`announce` attribution follows the running shell, not the intended author.**
   `brain announce` stamps the line with `whoami` of the shell it runs in. An agent that runs it from
   the *main* worktree (e.g. while doing cross-worktree work) gets stamped `langgraph-runtime` (or
   whatever owns `main`). The live agents already hit this and worked around it with a manual
   `[attribution corrected: …]` note. **Workaround:** `BRAIN_FEATURE=<feature> brain announce …`.
   **Enhancement:** a `brain announce --as <feature>` flag.

3. **Research notes drift from the template schema.**
   `research/` is the most free-form note type, and agents have written valid-but-off-template
   frontmatter (`features:` / `source:` instead of `by:` / `sources:` / `tags:`). `reconcile` only
   checks `type:`, so it passes. **Enhancement:** a light per-type required-field check in
   `reconcile` (warn, don't fail).

---

## Decisions recorded (won't-do / deferred-by-design)

- **`whoami` worktree-path fallback for detached HEAD — NOT building.**
  When a feature merges and `/wrap` deletes the branch, the worktree parks at a detached `origin/main`
  and `whoami` goes empty until the next branch is cut. We considered a fallback that matches the
  worktree path against each presence note's `current_worktree`. **Rejected:** the M6 convention
  ("the feature name is always in the branch") already self-heals the gap the instant real work starts
  on the next branch — observed live on day 2. Adding the fallback would reintroduce worktree-coupling
  against M5 to fix a gap that closes itself. Reconsider only if "park without cutting a new branch"
  becomes a real, recurring pattern.

- **No Dataview, no `.brain-agent` sentinel, no PostToolUse fast-awareness hook** — all cut from v1 on
  purpose (see STRATEGY decision log). `brain status` replaces Dataview; `brain whoami` replaces the
  sentinel; SessionStart + PreToolUse replace the third hook.

---

## Phase 2 — superset MCP indexing (additive)

Fold in a smart-search layer (`sweir1/obsidian-brain`, the read+write+graph superset, Apache-2.0),
**scoped to `.brain/` only**:

- **Reads** (semantic search, find-connections, themes) go through the superset; **writes stay
  built-in** (`Write`/`Edit` + `brain announce`) so the write path never depends on a server. Grep
  stays the live truth; the index is the smart layer on top.
- The index DB lives outside the committed vault (`.brain/.gitignore` already ignores `index/`,
  `*.db`; `.indexignore` already reserves `templates/` + `bin/`).
- **Turn it on when the vault is big enough to be worth it** — near-empty, grep wins and an index is
  decoration. The v1 note schemas are designed so nothing changes when it lands; it's a pure addition.
- Obsidian (the app) needs none of this — it opens `.brain/` as a folder vault and renders the
  `[[wiki-link]]` graph today, with no MCP.

## v2 — autonomous machinery self-evolution

v1 splits change by blast radius: **conventions** (note formats, the nav skill) self-evolve through
the governed gauntlet even unattended; **machinery** (the hooks, the `brain` script) is human-applied
— an agent files a proposal and keeps working. v2 lets agents change machinery during *unattended*
runs via a context-aware gauntlet (ask-when-a-human-is-attached / shelve-when-not) plus machinery
self-tests, so an overnight run can evolve the engine without ever hanging on it.

---

## Smaller enhancements (nice-to-have)

- **A real test suite.** v1 was proven by running (the BUILD-SPEC §10 scenarios). Capture those as a
  `test/` script (temp-repo init → new-feature → whoami edge cases → reconcile resolve/downgrade →
  governance → hooks) so regressions are caught mechanically. The `BRAIN_TEST_BRANCH` env override and
  `BRAIN_SKILLS_DIR` / `BRAIN_GLOBAL_SETTINGS` redirects already exist for exactly this.
- **`brain connect <a> <b> <kind>`** helper to scaffold a connection from the template (connections
  are free-to-create today, so a template suffices, but a helper would enforce the deterministic slug).
- **`brain research <topic>`** helper to scaffold a research note.
- **Re-add the PostToolUse fast-awareness hook** (shell-only, mtime-gated, @mention-only) if
  between-actions latency on `@mentions` ever bites — currently a mention lands at the next session
  start or the next pre-tool gate.
- **An Obsidian workspace preset** (`.obsidian/` is gitignored, but a shipped, opt-in graph-view
  config could make the human dashboard nicer out of the box).

---

## Packaging checklist (before publishing)

- [x] **Public scrub** — author's absolute paths de-usernamed across all docs; full secret-scan clean
      (no keys, tokens, emails, or org/employer references). Engine carries no project-specific paths.
- [x] **Engine genericized** — configurable default branch (`BRAIN_MAIN_REF`) and secret-denylist
      (`BRAIN_SECRET_DENYLIST`); no hardcoded repo paths.
- [x] **`LICENSE`** — MIT.
- [ ] **`git init` and push.** Built deliberately without git so it could move into a personal repo
      cleanly. Note: `docs/` still use the Enterprise Research Dashboard as the *worked example*
      (feature names, Jira-key-style ids) — not sensitive, but trim further if you want a fully
      neutral case study.
