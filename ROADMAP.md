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
   **Observed live 2026-08-03 — impact is worse than "low":** `presence/pm.md` had `updated:` bumped
   to the freshest of all 13 lanes and `touches[]` set to *another lane's* uncommitted files
   (@observatory's, attributed to @pm), while `phase:`/`current_ticket:` stayed two weeks stale. Two
   knock-ons: **(a)** `_detect_collisions` reads that same `touches[]`, so collision warnings can fire
   against a lane that never touched the file — and miss real collisions; **(b)** `updated:` is
   thereby useless as a liveness/staleness signal (`brain status` renders `phase`, so a lane can look
   maximally fresh while reporting two-week-old work). Do not build anything that keys on `updated:`
   until this is fixed.

2. **`announce` attribution follows the running shell, not the intended author.**
   `brain announce` stamps the line with `whoami` of the shell it runs in. An agent that runs it from
   the *main* worktree (e.g. while doing cross-worktree work) gets stamped `langgraph-runtime` (or
   whatever owns `main`). The live agents already hit this and worked around it with a manual
   `[attribution corrected: …]` note. **Workaround:** `BRAIN_FEATURE=<feature> brain announce …`.
   **Enhancement:** a `brain announce --as <feature>` flag. **Half-built:** the DM work added an
   internal `_announce_as <feat> <msg>` seam (the journal writer with identity supplied by the
   caller) — exposing the flag is now just arg-parsing on `cmd_announce`, not new plumbing.

3. **Research notes drift from the template schema.**
   `research/` is the most free-form note type, and agents have written valid-but-off-template
   frontmatter (`features:` / `source:` instead of `by:` / `sources:` / `tags:`). `reconcile` only
   checks `type:`, so it passes. **Enhancement:** a light per-type required-field check in
   `reconcile` (warn, don't fail).

---

## Known issue — `brain commit` wedges for one class of legacy vault (open, 2026-08-04)

Found by the UR-4a RED audit; **pre-existing, not introduced by v1.1**, and NOT closed by the
UR-4a fix. If a vault has `dm/` un-ignored, an inbox that is **tracked and unmodified**, and that
inbox's body contains a line matching the commit secret scan's `^[A-Z][A-Z0-9_]*=.+`, then
`brain commit` aborts on the scan — and because the pre-purge's staged deletion persists, it
aborts again on every rerun. Permanent, same as the UR-4a wedge it otherwise fixes.

Exposure is bounded: a real `inbox.jsonl` line starts with `{` and cannot match the anchored
pattern, so the trigger requires a truncated write, a hand-edit, or a pre-v1 body format.
No scenario covers it (the RED suite's fixtures use JSON bodies deliberately, to keep the scan
out of the way of the UR-4a assertions). Mechanism and full measurement in
`.context/seams/dm-v1.1-queue.md` under the UR-4a ruling. **Do not "simplify" either purge in
`cmd_commit` without reading it** — the pre-purge looks like dead code on the fixed engine and
is not.

## v1.1 — DM per-message queue (⚠ PROMOTED TO SHIP-BLOCKING, Steve 2026-08-03 evening)

> **Status changed the same day it was written.** The 7.4 ultrareview (report:
> `docs/lane-dm-ultrareview-findings.md`, verdict NOT READY) found a crash-consistency defect
> that needs **no concurrency at all**: SessionStart moves the inbox to the terminal `read/`
> archive *before* digesting or emitting it, and nothing ever scans `read/` again — an
> interrupted boot loses those messages permanently. That is qualitatively worse than the three
> races below, which only *delay* a message. **Steve ruled: this rewrite lands BEFORE any deploy
> — v1 does not ship with a window that silently loses mail.** It also absorbs ultrareview
> findings UR-1, UR-3 and UR-4a; full disposition of all 10 in `AGENT_BRAIN_DM_GSD_PLAN.md` §7.5.

The three findings below (full report: `docs/lane-dm-adversarial-review-findings.md`) are the
**known limits of v1's one-shared-JSONL-inbox design** that motivated the rewrite:

- **#1 (HIGH)** a send racing boot-time rotation is permanently stranded in the `read/` archive
  (never surfaced at any boot) — the old "delayed, not lost" acceptance was wrong and is withdrawn;
- **#6 (MEDIUM)** the no-lock append's atomicity premise is false (`PIPE_BUF` governs pipes, not
  regular-file appends; the body cap counts chars, not encoded bytes);
- **#11 (MEDIUM)** two live sessions of one lane both consume every message (no receiver claim).

**The one fix for all three:** one file per message — write to a temp name, atomic `rename` into
`dm/<lane>/pending/`, atomic claim at delivery. Removes the interleaving surface entirely, makes
the size cap irrelevant to atomicity, gives claim/ack a natural home. **Cost:** changes the
storage contract the frozen `test/dm.sh` pins → the suite reopens through the `test-writer` +
`spec-watchdog` pair. Roughly one session of work.

**Added acceptance criteria from the ultrareview** (these are what make the rewrite ship-blocking,
not optional polish):

- **Delivery must be recoverable, never terminal-before-success** (UR-1). A message stays
  replayable until handoff to the session actually succeeded; stale claims are recovered on a
  later boot. **Prefer duplicate delivery over silent loss.** Test kill-after-claim and
  digest/emit failure.
- **A live-observed message must be claimed, not just seen** (UR-3). Today the watcher observes an
  append and mutates nothing, so the next boot rotates and re-injects a message the lane already
  acted on. Stable IDs + atomic claim/ack. Test live-read → reboot.
- **The commit guard's cleanup must not wedge** (UR-4a). Once an inbox is already tracked,
  `git rm --cached` stages a deletion that the guard's own final check reads as failure — and no
  retry can clear it. Build and scan a sanitized temporary index; commit that, without pathspec
  semantics. Test legacy-tracked inbox and repeated `brain commit`.
- **A poison message must not loop forever** (added 2026-08-03 from the prior-art research —
  at-least-once + automatic stale-claim recovery is an infinite redelivery loop for any message
  whose processing kills its consumer). Delivery-attempt counter in the filename grammar; after
  3 failed deliveries the message routes to a terminal `failed/` directory, surfaced in
  `brain status`, never auto-deleted. Adopted now because it changes the name grammar the
  reopened suite pins.
- **Durability claims stay honest**: the queue is robust against process death (the realistic
  failure mode), NOT against power loss — `sh` cannot `fsync`. Docs say "process-crash-safe."

**Design authority:** the full seam map — layout, name grammar, lifecycle contracts, prior-art
citations (maildir/dirq/SQS), and the discarded alternatives — is at
`.context/seams/dm-v1.1-queue.md` (local, per-worktree). RED tests pin THAT contract.

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

- **A real test suite.** _Partly delivered:_ `test/dm.sh` (24 scenarios) now exists, built exactly
  this way — temp-repo fixtures via the `BRAIN_TEST_BRANCH` / `BRAIN_SKILLS_DIR` /
  `BRAIN_GLOBAL_SETTINGS` seams — but it covers the **DM slice only**. The pre-existing surface
  below is still uncovered; extend the same harness rather than starting a second one.
  v1 was proven by running (the BUILD-SPEC §10 scenarios). Capture those as a
  `test/` script (temp-repo init → new-feature → whoami edge cases → reconcile resolve/downgrade →
  governance → hooks) so regressions are caught mechanically. The `BRAIN_TEST_BRANCH` env override and
  `BRAIN_SKILLS_DIR` / `BRAIN_GLOBAL_SETTINGS` redirects already exist for exactly this.
- **`brain connect <a> <b> <kind>`** helper to scaffold a connection from the template (connections
  are free-to-create today, so a template suffices, but a helper would enforce the deterministic slug).
- **`brain research <topic>`** helper to scaffold a research note.
- ~~**Re-add the PostToolUse fast-awareness hook**~~ — **superseded** by `brain dm` (lane-to-lane
  DM). The latency this item existed to fix ("a mention lands at the next session start") is now
  addressed by a different mechanism: an inbox file the receiving agent watches, delivering in
  seconds without a third hook firing on every tool call. Revisit only if watching proves
  unreliable in practice.
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
