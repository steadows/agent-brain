# Pre-PR code review — lane-DM v1.1 branch

**Target:** `fix/pretool-collision-warning` vs `main` @ `8c7a81c` · **Date:** 2026-08-04
**Method:** 5 parallel Claude reviewers → per-finding confidence scoring (discard <50,
50–74 → LOW) → single-agent Codex adversarial sweep (`gpt-5.6-sol --effort max`, brief at
`docs/prompts/lane-dm-v11-adversarial-codereview.md`). Every Codex finding was
re-verified by the orchestrator before inclusion.

**Result: NOT READY — 5 HIGH, 11 MEDIUM.** The adversarial sweep found 4 issues the
first pass missed, two of which are among the most severe on the list. This gate runs
*after* the 7.4 ultrareview (10 findings, all closed) and *after* the `/simplify` pass —
both HIGH findings from the Claude pass and both from Codex are in code that those
earlier gates already looked at.

---

## Summary

The v1.1 queue is structurally sound — the design authority (`.context/seams/dm-v1.1-queue.md`)
holds up under adversarial reading, the security surface is clean (no injection, no
traversal, jq is used with `--arg` throughout), and the deliberate shapes (both `cmd_commit`
purges, the temp-index dance, the wall-clock lease, the poison cap) all survived scrutiny.

The defects are at the **consumer boundary**: the code that reads the queue trusts its own
producer's grammar more than it should, and three separate paths turn a recoverable
condition into a permanent or silent one. The single biggest concern is that **two of these
make DM delivery stop working entirely and stay broken** — one for any vault whose path
contains a space, one for any queue that acquires a single malformed filename.

---

## HIGH — fix before the PR

### H1. A space in the repo path silently breaks all DM delivery — `bin/brain:522`, `:1167`
**Problem:** `_dm_claim_all` prints full absolute paths (`$BRAIN/dm/<lane>/claimed/<name>`),
and both consumers split them with unquoted `set -- $_claims`. The guarding comment
("queue grammar forbids whitespace") is true of the *filename* but says nothing about
`$BRAIN`, which is the repository's own filesystem path. Any vault under a
space-containing path shreds every claimed path into fragments; `_dm_dir_ok` then
fail-closes on each fragment, so `_dm_digest` returns 1 for every batch, forever. Messages
aren't lost — they cycle the lease and land in `failed/` after 3 attempts — but the entire
feature is silently non-functional, with the only signal buried in `.hook-errors.log`.
Reproduced under both `dash` and `/bin/sh` (confidence 100).
**Fix:** Stop round-tripping paths through word-splitting. Either have `_dm_claim_all`
emit names (not full paths) into a `while IFS= read -r` loop, or use a newline-only IFS
for the split.

### H2. Digest bounds are bypassable by valid JSON — `bin/brain:493-510`
**Problem:** `_dm_digest` bounds *files* (`DM_INJECT_MAX_LINES`) and truncates only
`.content` (`DM_INJECT_MAX_COLS` budget). It does not require one object per file and does
not strip unknown fields. Verified: a single file containing 3 JSON objects emits 3
records (so the 40-file cap does not bound emitted records), and a 200-byte `extra` field
passes through untouched alongside a truncated `.content`. Worse, there is a **no-tampering
producer path**: `cmd_dm` takes `_from` from `cmd_whoami`, which returns `$BRAIN_FEATURE`
unvalidated, so a lane can put an unbounded string in `.from`. Since the digest is injected
directly into another agent's SessionStart context, the bound that protects the receiving
lane's context window is not actually enforced.
**Fix:** At the consumer boundary, require exactly one object per file, reconstruct only
the four contract fields (`from`/`to`/`ts`/`content`), bound each, and apply a final
aggregate byte cap before emission.

### H3. A single malformed claim filename permanently wedges SessionStart — `bin/brain:417-428`
**Problem:** `_dm_recover_stale` validates fields with `case ... in ''|*[!0-9]*)` — which
**accepts leading zeros** — then immediately does arithmetic on them. Verified: `08` passes
the digit check and then kills the shell (`dash: Illegal number: 08`, rc 2; `sh: value too
great for base`, rc 127). The hook's `|| true` does **not** catch it — arithmetic expansion
failure is fatal — so one crafted or corrupted filename in `claimed/` terminates
SessionStart before any delivery, on every boot, permanently. Same class of wedge as UR-4a,
through a different door. Separately, an over-range attempt value wraps negative
(`9223372036854775807 + 1` → negative), producing a `.a-…` pending name that `_dm_claim_all`
then rejects forever — a silent stuck state.
**Fix:** Require canonical bounded decimals before any arithmetic (no leading zeros except
`0`, bounded epoch width, attempts within the state-machine range); route anything else to
`failed/` with a warn instead of evaluating it.

### H4. `_dm_ack` intercepts its own "claim was recovered" soft path — `bin/brain:466-483`
**Problem:** `_dm_dir_ok "$_ak_claim"` runs *before* the `mv`. When another session has
already lease-recovered the claim (the realistic case — the file has been gone for the
whole digest+emit duration), `_dm_dir_ok` warns "refusing non-regular dm message" and
returns 1, so the dedicated ENOENT branch below it ("dm claim disappeared before ack…",
return 0) is only reachable in a sub-millisecond TOCTOU window. The seam map designs this
exact case as *warn, never die*. Effect: `brain dm take` exits nonzero even though the
digest emitted correctly and the message will be delivered by whoever holds it now — a
misleading exit-code contract for any script or agent calling it. The frozen suite declares
this limb untested, so no gate caught it.
**Fix:** Attempt the `mv` first (or have `_dm_dir_ok` distinguish "absent" from "wrong
type"), so the existing soft-landing fires for the realistic case.

### H5. Unbounded per-message forks at SessionStart — `bin/brain:441-463`, `:485-489`
**Problem:** `_dm_claim_all` claims the *entire* pending backlog with one `mv` fork per
message, and `_dm_ack_all` acks with one fork per message. `DM_INJECT_MAX_LINES` caps only
what is *displayed*. Because broadcast to dormant lanes is explicitly designed as
harmless-and-deferred, a lane that sleeps through a run of broadcasts wakes to N claims +
N acks — 100–200 subprocesses for a plausible 13-lane backlog, paid synchronously before
the session can boot.
**Fix:** Bound the claim batch (claim at most K, leave the rest pending for the next
touch), so boot latency is bounded regardless of backlog depth.

---

## MEDIUM

### M1. An ambiguous identity is silently attributed to `system` — `bin/brain:556`
`cmd_whoami` deliberately returns 1 with no output when it cannot disambiguate ownership
("refuse to guess" — the spec's rule). `cmd_dm` does `_from=$(cmd_whoami);
_from=${_from:-system}`, discarding that status: the DM and its **committed journal line**
claim to come from `system`, and broadcast then fails to skip the real sender (the lane
DMs itself). Fix: capture the status separately; fall back to `system` only on a
*successful* empty resolution, abort on ambiguity.

### M2. Poison messages are invisible to anyone but the dead lane — `bin/brain:427-431`, `:680-685`
Routing to `failed/` writes no journal or announce line, and the only surfacing is a
`brain status` banner gated on the *owning* lane's identity. The scenario the poison cap
exists for is a lane that keeps dying — exactly the lane that will never render its own
banner. Fleet-health checks (`@pm`) see nothing without impersonating each lane. Fix:
count `failed/` per lane inside the existing presence loop, and/or journal the routing.

### M3. A temp-sweep failure silently disables lease recovery — `bin/brain:405`
`_dm_recover_stale` runs `_dm_purge_stale_temps || return 1` *before* the recovery loop, so
any sweep failure skips stale-claim recovery for that boot; the warn text mentions only
temps, and the hook call site is `|| true`. A crashed prior session's claims quietly stay
stuck. Fix: don't let an ancillary sweep gate recovery — warn and continue.

### M4. The rollback drain runbook isn't executable as written — `AGENT_BRAIN_DM_GSD_PLAN.md:472-477`
Task 5.6(a) says confirm every lane's `pending/`+`claimed/` are empty via "`brain dm take`
on each", but `cmd_dm_take` takes no lane argument (always `cmd_whoami`), and `cmd_inbox`
prints only the pending *path*, no counts. The documented fleet-wide drain requires the
undocumented `BRAIN_FEATURE` override. Fix: document the override in 5.6, or give
`dm take`/`inbox` a lane argument.

### M5–M7. Doc/state drift introduced or left by the branch
- `ROADMAP.md:155` claims `test/dm.sh` has **24 scenarios**; it has **45** (CHANGELOG in
  the same branch says 45+15).
- `bin/brain:11` `VERSION="1.1.0"` has **no matching CHANGELOG heading** (newest is
  "Unreleased"), and the constant skipped 1.0.1 entirely though CHANGELOG documents that
  release. `brain version` prints a number the changelog doesn't know.
- `AGENT_BRAIN_DM_GSD_PLAN.md`: the top Status line still says "next = 7.4 → Phase 5
  deploy" though 7.4 ran and §7.5 declares ALL 10 CLOSED — and every UR-1…UR-10 bullet
  under that line still carries a `[ ]` marker, contradicting the prose two lines above.

### M8–M11. Zero-coverage paths (need new scenarios in a future suite rev — the current suites are frozen)
- **The branch's namesake fix has no test at all**: nothing invokes `brain hook pre-tool`;
  the harness hardcodes `BRAIN_PRETOOL_MODE=allow`. `_emit_pretool` (both branches),
  `_hook_pre_tool`, and `_detect_collisions` are entirely unpinned.
- `cmd_new_feature`'s reserved-name guard (`all|system|take`) — never exercised.
- Direct `brain announce` — only ever driven indirectly through `cmd_dm`.
- The hook's whoami-empty exit — every scenario sets a concrete lane, so the branch that
  now gates the whole recover→claim→digest→emit→ack sequence never fires in tests.

---

## LOW (verified, non-blocking)

- One corrupt file blocks the *whole* claimed batch's digest (jq aborts at first bad
  input; partial output discarded), retrying across lease cycles with a generic warn that
  names no file.
- `_relpath_any` adds a `git rev-parse` fork per Edit/Write hook call from sibling
  worktrees (the normal case); a cheap fork-free alternative isn't obviously available.
- `brain inbox` rejects `@feature` (which `brain dm` requires) and silently creates queue
  trees for unregistered lanes — two CLI inconsistencies between sibling subcommands.
- `find -mmin` is new to the codebase, non-POSIX, undeclared in README's dependency list,
  and carries no BSD/GNU note (unlike the pre-existing `_days_ago` date dance).
- `README.md`'s command table omits `brain dm take`.
- `cmd_commit` is 122 lines (was 35) with six responsibilities; the algorithm is a ruled
  deliberate shape, but the *function* has obvious extraction seams.
- The `/simplify` pass's claim-side `_dm_id_ok` tightening and `_dm_ack`'s narrowed
  `read/` validation are both unpinned — reverting either would still pass 45/45.
- **Commit hooks are bypassed** by `commit-tree`+`update-ref` where `main` used
  `git commit` (so `pre-commit`/`commit-msg` no longer run). Verified real, but neither
  this repo nor the deploy-target repo has any non-sample git hook, so there is no live
  population — latent compatibility change, not a present defect.

## Discarded as false positives / intentional
`DM_*` constants not being env-overridable (cross-process consistency argues for fixed);
`inbox.jsonl` residue detection (that layout never shipped anywhere); splitting `cmd_dm`
(57 lines, noise); the nav-skill's trailing "Project hooks" heading (that empty section is
its documented purpose — deployed copies append below it); `_dm_failed_count` counting
symlinked entries (display-only).

---

## Verdict

**Fix before the PR:** H1–H5. H1 and H3 both end in *permanent, silent* loss of the
feature's only promise, which is the same bar that made UR-1 ship-blocking. H2 is the
context-window bound not actually holding. H4 is a wrong exit-code contract on the
documented consume command. H5 is bounded work with a one-line-ish fix.

**Fix soon (not blocking):** M1 (mis-attributed journal authorship is committed history),
M2, M3. The doc drift (M5–M7) is cheap and should ride along. The coverage gaps (M8–M11)
need a suite rev — the frozen suites cannot absorb them.
