# Final adversarial sweep — lane-DM branch at fe1a329 (pre-PR convergence gate)

You are a senior adversarial code reviewer working ALONE — do NOT spawn sub-agents or fan
out; single-agent is a hard requirement. Find what every prior gate MISSED on the FINAL
tree. Findings only — no code edits. If you cannot find material issues, say so explicitly;
a clean verdict from you is the gate this branch needs to reach the PR, so do not invent
findings — but do not go easy either: every prior round found real HIGHs in code earlier
rounds passed.

## Scope

`git diff main...HEAD` — the whole lane-DM branch (v1.1 queue → v1.2 claim-layer deletion →
v1.2.1 → v1.2.2 → v1.2.2-r2). The NEWEST, least-reviewed code is `fe1a329` (the r2 fix
round: pinned emit staging, per-suffix cap recheck, hidden-entry classification, jq measure
factoring, batch-abort flag, digest-via-variable, post-exhaustion revalidation, resolver
identity gate). Weight your attention accordingly. Read the post-diff `bin/brain` DM
sections in full and `.context/seams/dm-v1.1-queue.md` end-to-end (rulings 1–12).

## Already found and FIXED across five prior gates — do not re-report; VERIFYING a fix is
## in scope only if you find the fix itself introduces a NEW defect

v1.2.2 round: unreadable-dir fail-open, trailing-newline path truncation, jq identity
pinning (rulings 7/8/9). Pre-PR review + sweep: unpinned/unverified SessionStart emit
before archive, NAME_MAX collision overflow, dot-entry invisibility (rulings 10/11/12),
warn spam/naming, VERSION, nesting, prose staleness, V.R/67 layer-pinning gap ([Q6]
declared), V.R/69 shim self-delete gap (now the in-place-overwrite shim, stub-flip
verified). /simplify clusters: probe-triple duplication, middle-layer validations,
ensure_tree loop merge, slug twin, dest-occupied witness, resolver BRAIN_FEATURE gate,
post-exhaustion revalidation, send-path jq pinning.

## Blind-spot mandate (fresh eyes on the final composition)

1. Interactions BETWEEN this round's fixes: the systemic-failure flag's lifetime across
   preflights/operations in one process; digest-via-variable vs every caller; the hook's
   discard-staged-batch path vs `_more_dm`/`_dm_block` consistency; hidden-entry
   enumeration vs the batch cap and vs `_dm_id_in_use`'s id-prefix filter; the compact
   collision fallback's uniqueness under same-second same-pid collisions.
2. POSIX sh + dash semantics in the newest code: `.*` glob portability, `$?` propagation
   through the new `if/case` shapes, `set -u` interactions with the new globals.
3. State-machine walk on the final engine: any path that strands, double-emits, archives
   undelivered, or quarantines healthy content — especially mid-batch failure orderings.
4. Cross-file: mutation-probe anchors vs the final engine text (each sed must match exactly
   once); `cmd_commit`'s DM purge/secret-scan vs the new quarantine artifact names;
   templates' behavioral promises vs the final engine.
5. Concurrency: send vs take vs SessionStart racing on one lane at the new code's windows
   (collision-dest occupancy recheck, emit-then-archive, post-exhaustion revalidation).

## Report

For each finding: File / Line / Category / Severity (CRITICAL|HIGH|MEDIUM) / Finding /
Evidence (reproduce where the sandbox allows; name the exact input otherwise) / Fix.
Verdict line FIRST: READY or NOT READY.
