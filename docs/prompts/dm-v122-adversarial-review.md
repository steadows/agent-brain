# Adversarial second-opinion brief — DM v1.2.2 pre-PR code review (round: 7c9da79)

You are a senior adversarial code reviewer working ALONE — do NOT spawn sub-agents or fan
out; a single-agent review is a hard requirement (the multi-agent fleet belongs to the
post-PR ultrareview gate, not this one). Your job is to find issues that a thorough
first-pass review MISSED — not to repeat what was already found. Findings only — do not
edit code.

## Scope

`git diff 2e8ccff..7c9da79` in this repo — the DM v1.2.2 hardening round: bin/brain
(engine), test/dm.sh (V.R/67–70 additions + make_unreadable_dir), test/mutation-probe.sh
(anchor/count/kill-set updates). POSIX sh; must behave identically under /bin/sh and dash.
Read the post-diff bin/brain DM sections in full, plus `.context/seams/dm-v1.1-queue.md`
§ v1.2.2 (rulings 7/8/9 — the design authority) and § rulings 1–6.

## What the first-pass review already caught — SKIP these, no duplicates

Quality clusters (a /simplify pass; fixes batched for the next round):
- jq probe-triple duplicated between `_dm_jq_preflight` and `_dm_jq_contract_holds`
- redundant middle-layer `_dm_dir_ok` at cmd_dm_take/hook/_dm_send call sites
- `_dm_ensure_tree` create-loop + validate-loop merge
- presence-slug idiom inlined at 2 sites beside `_agent_slug`
- exact-path witness re-inlines `_dm_dest_occupied`'s predicate
- `_resolve_whoami` does not `_feat_ok` an inherited `BRAIN_FEATURE` (validate-at-the-seam fix pending)
- consuming loops (`cmd_dm_take`, `_hook_session_start`) don't re-validate the dir after
  their own glob expansion / after loop exhaustion (probe→loop TOCTOU window)
- `_dm_write_json` (send path) still invokes unpinned bare `jq`

Code-review findings (5-agent pass, confidence-filtered):
- VERSION constant not bumped to 1.2.2
- `_hook_session_start` nesting grew to depth 5
- jq-contract-changed warn repeats once per remaining pending entry (up to the 40-cap)
  instead of aborting the batch after the first systemic failure; warn omits `$_DM_JQ_BIN`
- test/dm.sh AUTHORITY header / run banner / V.R divider / SHIM DISCIPLINE enumeration /
  probe header prose all stale re v1.2.2; CHANGELOG missing v1.2.2; ROADMAP jq-site count
- TEST GAP (deletion-verified): V.R/67 pins only `_dm_ensure_tree`'s upfront gate — the
  scanner-internal `_dm_dir_ok` checks in `_dm_id_in_use`/`_dm_dir_has_entries` are not
  independently exercised (undrivable single-invocation; heading for a declared gap)
- TEST GAP (deletion-verified): V.R/69's self-DELETING shim means `_dm_jq_contract_holds`
  is never called anywhere in the suite — a self-OVERWRITING shim (same path, hostile
  content returning the probed rc) would drive it; fix pending
- V.R/67's `chmod 755 || fatal` deviates from the suite's `|| true` restore idiom;
  read/-side collision-dest reachability note missing

## Your mandate

1. SKIP everything above.
2. Blind-spot categories to hunt:
   - Subtle logic errors only manifesting under specific input combinations (hostile
     filenames beyond trailing-newline: leading `-`, globs chars, NUL-adjacent, 255-byte
     names, names that collide with the collision-suffix grammar itself)
   - Cross-file interaction bugs (engine change breaking an assumption in test harness,
     mutation-probe anchors, templates, the PreToolUse/SessionStart hook wrappers, or
     `cmd_commit`'s DM purge/secret-scan interplay with the new quarantine artifacts)
   - TOCTOU/trust-boundary issues the new both-sides validation pattern still misses
   - Concurrency: two engine invocations racing on one lane's queue (send vs take vs
     SessionStart), collision-bump races, mint races on `<ts>-<pid>` ids
   - Error-handling gaps where failures cascade silently (rc conflation anywhere the new
     0/1/2 and 0/1/2/3 dispatches meet older boolean callers)
   - Backward compatibility: v1.2.1-created queues/artifacts consumed by v1.2.2 and vice
     versa (the 5.6 rollback runbook's assumptions)
   - State-machine violations: any transition that can strand a message outside
     pending/read/failed, double-emit, or emit-without-archive under a mid-batch failure
3. For each finding: **File / Line / Category / Severity (CRITICAL|HIGH|MEDIUM) /
   Finding (what was missed, why it matters) / Evidence (why real, not speculative —
   reproduce where possible) / Fix (concrete)**.
4. If the first-pass review was thorough and you cannot find material issues, say so
   explicitly. Do not invent findings to justify your existence.
