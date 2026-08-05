# Final adversarial sweep, round 2 — lane-DM branch at baff2ee (pre-PR convergence gate)

Same contract as `docs/prompts/dm-v122-final-sweep.md`: you work ALONE (no sub-agents, no
fan-out), findings only, no code edits. Your predecessor's four findings are all FIXED and
listed below — do not re-report them; verifying a fix is in scope only if the fix itself
introduces a NEW defect. If you cannot find material issues, say READY explicitly — do not
invent findings; but every prior round found real HIGHs, so do not go easy.

## Scope

`git diff main...HEAD`. The newest, least-reviewed code is `baff2ee` (r3): the shared
batch-discard condition in `_hook_session_start` (systemic-flag OR unestablishable
post-exhaustion), the dot-inclusive `_dm_failed_count`, the reverted `.*` scan in
`_dm_id_in_use`, scenario V.R/75 (stateful two-call jq shim) and the V.R/74 status-banner
extension. Weight attention there, then the r2 surfaces they compose with. Read
`.context/seams/dm-v1.1-queue.md` rulings 1–12 and the post-diff engine DM sections in full.

## Fixed by prior rounds — skip

Everything in `docs/prompts/dm-v122-final-sweep.md`'s skip list, PLUS: the staged-batch
survival on systemic jq failure (F1 → shared discard + V.R/75); dot-named artifacts
invisible to `_dm_failed_count` (F2); the hot-path `.*` walk in `_dm_id_in_use` (F3);
BUILD-SPEC's claim-era prose (F4 → rewritten to the shipped contract).

## Fresh angles for this round

1. The r3 composition itself: the shared discard condition's short-circuit order; the
   systemic flag's reset discipline (`_dm_jq_preflight` zeroes it — any path that consumes
   DMs without passing through preflight first?); `_dm_failed_count`'s new dot glob vs
   `_dm_dir_ok` failure modes; V.R/75's shim-state instrument vs suite rerun/parallel-run
   safety.
2. Anything the narrowing pattern predicts: round 1 found "messages vanish", round 4 found
   "messages vanish if jq turns systemic mid-batch" — what is the next-narrower loss or
   starvation window on the emit/archive/quarantine seams?
3. Cross-file drift introduced by the docs commit `5b3cacc` (CHANGELOG/plan/BUILD-SPEC
   claims vs the actual engine at `baff2ee`).

## Report

Verdict line FIRST: READY or NOT READY. For each finding: File / Line / Category /
Severity (CRITICAL|HIGH|MEDIUM) / Finding / Evidence (name the exact input; reproduce where
the sandbox allows) / Fix.
