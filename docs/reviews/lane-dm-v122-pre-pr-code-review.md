# Pre-PR Code Review — DM v1.2.2 round (2e8ccff..7c9da79)

**Date:** 2026-08-05 (overnight) · **Pipeline:** /steadows-code-review — 5 parallel reviewers
(security+correctness, performance+interface, maintainability+co-change, observability+rollback,
test quality), confidence filter (11 factual claims batch-verified, all CONFIRMED; behavioral
findings carried their own deletion-test/live-repro evidence), then a single-agent Codex
adversarial sweep at max (`docs/prompts/dm-v122-adversarial-review.md`).

## Summary

The v1.2.2 engine work itself is sound: security/correctness and performance both returned CLEAN
with empirical verification (dash-tested PATH-walk edge cases, zero new forks on the empty-boot
path, all whoami call sites rc-equivalent, templates make no broken promises). What survived is
(a) one real HIGH the sweep found in a surface no prior gate had walked — the SessionStart emit —
plus two narrow MEDium state-machine edges, and (b) two HIGH test-gap findings proving the new
suite pins ruling 7/9 behavior at the wrong layer in two places. Verdict: **NOT READY** until the
combined fix round lands; nothing here invalidates the v1.2.2 rulings themselves.

**Round-landing split (proportionality rule):** 7 product-code findings / 5 test-infrastructure /
5 doc-prose. The two test-infra HIGHs are gaps (missing discrimination), not apparatus bloat —
the mandated response is one new drivable limb (T1/T5), one declared gap ([Q6]), and prose fixes;
no new shared state, no coordination, no instrument deepening.

## Issues (confidence-filtered survivors)

#### [HIGH] V.R/67 pins the upfront gate, not the scanners — test/dm.sh:3318
Deletion-verified: removing the scanner-internal `_dm_dir_ok` checks in `_dm_id_in_use` AND
`_dm_dir_has_entries` leaves the suite fully green — only `_dm_ensure_tree`'s gate is exercised.
The mid-process permission flip is not drivable from a single CLI invocation. **Fix:** declared
gap [Q6] naming the mechanism (T2), per the suite's Q1–Q5 convention.

#### [HIGH] `_dm_jq_contract_holds` is never called by any scenario — test/dm.sh:3431
Deletion-verified two ways (stub `return 0` → suite green; entry-marker fires 0× across 70
scenarios). V.R/69's shim self-DELETES, so digest fails "not found" and skips the re-probe
branch. **Fix:** self-OVERWRITING shim, same path, hostile content returning the recorded rc (T1).

#### [MEDIUM] jq-contract warn spams per-entry and never names the binary — bin/brain:637
Live-reproduced: 3 queued messages → identical warn 3× in one invocation (cap 40; 13 lanes share
`.hook-errors.log`). **Fix:** batch-abort on systemic failure + `${_DM_JQ_BIN}` in the warn (E9).

#### [MEDIUM] VERSION not bumped — bin/brain:11
`brain --version` misreports the deployed hardening level. **Fix:** E10.

#### [MEDIUM] `_hook_session_start` nesting reached depth 5 — bin/brain:1337
The consume path's bug history lives at this depth. **Fix:** E11 (flat form returns with E2).

#### [MEDIUM] Doc/prose co-change misses
test/dm.sh AUTHORITY header, run banner, V.R divider, SHIM DISCIPLINE enum; probe header;
CHANGELOG v1.2.2 entry; ROADMAP jq-site count. **Fix:** T3 (test files) + orchestrator docs pass.

#### [LOW] Restore-idiom deviation (`|| fatal` vs `|| true`) — test/dm.sh:3355; read/-side
collision-dest reachability note missing. **Fix:** T4/T2.

## Adversarial Sweep (Codex, single agent, max)

Three findings, all verified against the code by the orchestrator before acceptance; map
rulings 10–12 (§ v1.2.3) written and committed standalone ahead of implementation.

#### [HIGH] SessionStart can archive DMs after emitting zero bytes — bin/brain:1293,1381
`_emit_session_ctx` re-resolves bare `jq` post-digest, and its raw-text fallback makes the
archive gate nearly always true — a jq exiting 0 with empty output archives messages that were
never delivered. UR-1's loss class through the emit door. **Fix:** E12 (pinned + staged +
non-empty-verified emit before any archive) + T5.

#### [MEDIUM] Collision counter can exceed NAME_MAX after the one-time length check —
bin/brain:498. Overlong candidate reads as "free", quarantine `mv` fails, invalid entry stays
pending. **Fix:** E13 + T6.

#### [MEDIUM] Dot-prefixed hostile entries are invisible to every queue scan — bin/brain:459
`pending/.poison` is never delivered, never quarantined, no diagnostic; queue reads empty.
**Fix:** E14 (classify hidden entries; `.tmp-*` remains the ONLY sanctioned hidden namespace —
its exclusion is load-bearing for send atomicity) + T7.

Sweep sandbox note: read-only sandbox denied `mktemp`, so Codex claims no runtime green — all
its evidence was re-established locally by the orchestrator.

## Verdict

**NOT READY.** 2 HIGH product (S1/emit; plus the two HIGH test gaps), fix round dispatched:
`docs/prompts/dm-v122-fix2.md` (E1–E14, T1–T7, P1) under the same per-arc Codex-owns-both
override, followed by full independent regate and a fresh clean-sweep verification at max.
