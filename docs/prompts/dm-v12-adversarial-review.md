# Adversarial second-opinion review — DM v1.2 arc (pre-PR gate)

You are a senior adversarial code reviewer working ALONE — do NOT spawn sub-agents or fan
out; a single-agent review is a hard requirement (the multi-agent fleet belongs to the
post-PR ultrareview gate, not this one). Your job is to find issues that a thorough
first-pass review MISSED — not to repeat what was already found. Findings only — do not
edit code. Your sandbox blocks the test suites (`mktemp` rejected) — do not attempt to run
them; the orchestrator has them green (54/54 + 15/15 under sh AND real dash at `bac6d9a`).

## Scope

Range `503519b..bac6d9a` (`git diff 503519b..bac6d9a`): the v1.2 claim-layer deletion in
`bin/brain` (GREEN commit `6d9199a`), the V.N/47 dash fix, the doc reconciliation
(`79333cf`), and the `/simplify` refactor (`bac6d9a`). Post-diff files worth reading in
full: `bin/brain` (DM region: constants, `_atomic_place`, `_dm_*` helpers, `cmd_dm_take`,
`_hook_session_start`), `.context/seams/dm-v1.1-queue.md` § v1.2 (the design authority),
`templates/DM-PROTOCOL.md`. The frozen suites `test/dm.sh` (54 scenarios) and
`test/commit-install.sh` (15) are the contract; `test/mutation-probe.sh` is mid-rewrite —
ignore it.

## What the first-pass review already caught — SKIP all of these, no duplicates

1. jq parse-error exit code varies by version (1.6 → 4 on Debian/Ubuntu stable, 1.7 → 5);
   `_dm_pending_digest` hard-codes 5 as "structurally invalid" → on jq 1.6 corrupt files
   never quarantine, retry forever, and can starve the 40-slot batch window (HIGH).
2. `_dm_purge_stale_temps`/`DM_TEMP_MAX_AGE` deleted though not on the ruling's delete
   list → orphaned `.tmp-*` leak forever; ROADMAP misdiagnosed it as evaporated (HIGH).
3. `_dm_jq_preflight` forks jq on every boot including empty-queue (v1.1 paid zero);
   broken-jq environments warn every boot; `dm take` rc flips 0→1 on the empty no-op (HIGH).
4. `_dm_id_in_use` exact-match is blind to `_dm_collision_dest`'s bumped names → id reuse
   after an archive collision (MEDIUM).
5. `cmd_dm_take` collapses rc-3 (invalid AND quarantine failed) into the generic branch —
   hook path has a dedicated warn; rc-3 also has zero suite coverage on either path (MEDIUM).
6. Archive collisions bump silently (v1.1 refused loudly); `_dm_collision_dest`'s internal
   failure returns carry no warn (MEDIUM).
7. take-path 40-cap has no "more remain" signal — adjudicated NOT a seam-map breach
   ("emitted context" is the SessionStart payload), still flagged as an operator-visibility
   asymmetry (MEDIUM, disputed severity).
8. `_hook_session_start` at nesting depth 5 / 83 lines (MEDIUM); digest `id` injected
   outside `bounded()`'s truncation with the ≤255-byte dependency undocumented and the item
   missing from ROADMAP's carry list (MEDIUM).
9. Plan task 5.6 rollback runbook still references the deleted `claimed/` state and misses
   the real rollback mechanism (v1.1 grammar QUARANTINES v1.2-minted names as invalid);
   seam-map migration quiesce note reflected nowhere in Phase 5 (MEDIUM).
10. `templates/navigation-standards.SKILL.md` lacks any at-least-once/replay note; the
    idempotency guidance is gated behind the dialog-only DM-PROTOCOL read (MEDIUM).
11. Suite declared-gap [F14] prose now stale; mutation-probe M1 anchor broken by the
    refactor (LOW, already queued for the probe rewrite).

## Your mandate

1. SKIP anything already covered above — no duplicates.
2. Focus on the blind-spot categories that a first pass commonly misses:
   - Subtle logic errors that only manifest under specific input combinations (e.g. glob
     ordering, filename edge cases the `_dm_id_ok` grammar admits, empty vs unset shell
     variables, `set --` interactions in `_hook_session_start`)
   - Cross-file interaction bugs (engine vs templates vs plan vs the deploy model — every
     worktree carries a TRACKED stale engine copy; the continuation instruction must
     resolve the main worktree's engine)
   - Security issues hiding in "normal" code (TOCTOU between validate and mv, symlink
     swaps mid-consume, trust boundaries around the digest reaching the hook context,
     `_dm_write_json`/jq argv injection)
   - Concurrency hazards (13 lanes send concurrently into one consumer's pending/;
     sender crash mid-`_atomic_place`; two sends colliding on an id; consume racing a send)
   - Error handling gaps where failures cascade silently (`2>/dev/null` on mv/jq, rc
     conflation beyond finding 5)
   - Backward compatibility (the emitted hook-context format is parsed by 13 live lanes;
     `brain inbox`/`status`/CLI rc contracts)
   - State machine violations (pending→read/failed only; no hidden intermediate states —
     v1.0's loss bug was archive-before-emit; verify emit-before-move truly holds on every
     path including partial-batch failures)
3. For each finding: **File / Line / Category** (security | correctness | concurrency |
   compatibility | cascade-failure | state-machine) / **Severity** (CRITICAL | HIGH |
   MEDIUM) / **Finding** (what was missed, why it matters) / **Evidence** (why this is
   real, not speculative — cite the exact code path) / **Fix** (concrete).
4. If the first-pass review was thorough and you cannot find material issues, say so
   explicitly. Do not invent findings to justify your existence.
