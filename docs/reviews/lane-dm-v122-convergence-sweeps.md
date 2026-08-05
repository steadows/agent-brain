# Convergence sweeps — lane-DM pre-PR gate (running record)

Single-agent Codex `gpt-5.6-sol --effort max`, review-only, one sweep per fix round, per
the arc's cadence. The gate closes only on a clean (READY) sweep. Briefs are committed
beside this file in `docs/prompts/` (audit trail); orchestrator verification accompanies
every accepted finding — the Codex sandbox denies the suite's `mktemp`, so no sweep claims
a runtime run; every reproduction below was re-established locally before acceptance.

## Round 1 — on `fe1a329` (v1.2.2-r2) → NOT READY, 1 HIGH / 3 MEDIUM → fix round r3

Brief: `docs/prompts/dm-v122-final-sweep.md` · Job: task-msfuks3s-zpwhc4

1. **HIGH — late systemic jq failure kept the staged SessionStart batch.** The systemic
   break left `_digest`/positional names intact, so the hook could emit `{}` and archive a
   prefix the engine had declared unsafe. Orchestrator-verified by code inspection (the r2
   discard covered only the post-exhaustion path). → r3 F1: shared discard condition +
   V.R/75 (two-message shim: digest one, turn systemic on two, capture the serializer's
   real payload). A/B: only-F1-removed engine fails exactly V.R/75.
2. **MEDIUM — dot-named quarantine artifacts invisible to `_dm_failed_count`.** → r3 F2 +
   V.R/74 status-banner assertion.
3. **MEDIUM — `.*` walk in `_dm_id_in_use` was pure hot-path waste** (no dot basename can
   match a digit-leading id). → r3 F3 (reverted that one widening).
4. **MEDIUM — BUILD-SPEC still described the deleted claim/lease lifecycle.** → F4, fixed
   by the orchestrator (`5b3cacc`).

## Round 2 — on `baff2ee` (r3) + docs `5b3cacc` → NOT READY, 2 HIGH / 2 MEDIUM → fix round r4

Brief: `docs/prompts/dm-v122-final-sweep-r2.md` · Job: task-msfxu35b-li2c4c

1. **HIGH — rc-0 `{}` digest accepted unvalidated** (same-path byzantine jq: passes every
   probe, lies on payload calls) — healthy message archived after emitting `{}`.
2. **HIGH — send path acknowledges empty/`{}` encoder output** — publishes an empty wire
   object and journals a delivery that never carried content.
3. **MEDIUM — `cmd_status` maps an uninspectable `failed/` to zero** (fail-open on the
   display path).
4. **MEDIUM — plan/CHANGELOG declared convergence while this gate was open**, and named
   review artifacts that had not been committed. Fixed by the orchestrator (plan reworded;
   this file is the artifact).

**Adjudication (orchestrator, on the record):** findings 1–2 require a PATH binary that
answers the full probed contract correctly and forges well-shaped output — a strictly
stronger adversary than any prior round's. Per the proportionality brake the response
NARROWS rather than deepens: map ruling 13 (`ef6d9cd`) adopts cheap structural witnesses
(non-empty, object-shaped, carries the known glob-safe id / the four field keys) that kill
the named rc-0/`{}` attacks and every accidental-breakage shape — and DECLARES the
fully-byzantine forged-payload adversary out of the threat model (code-execution-
equivalent). Ruling 14 covers finding 3. Fix round r4 (`docs/prompts/dm-v122-fix4.md`)
implements W1–W4.

## Round 3 — on `3774640` (r4) → NOT READY, 3 HIGH / 2 MEDIUM → fix round r5

Brief: `docs/prompts/dm-v122-final-sweep-r3.md` · Job: task-msg25kca-pxuhdi
Findings: truncated rc-0 payloads passed the {-prefix witnesses (falsified ruling 13's own
coverage claim -> erratum 13a, `aa34b98`); send witness matched quoted words not key syntax;
envelope bare-id substring satisfiable by status text; status banner bypassed when failed/
is a non-directory; CHANGELOG/probe-header drift. All mechanical; Steve approved r5
explicitly (first decision after waking).

## Round 4 — on `c879468` (r5) → NOT READY, 2 HIGH / 2 MEDIUM → ruling 13b + fix round r6

Brief: `docs/prompts/dm-v122-final-sweep-r4.md` · Job: task-msg6oxid-54yuvl
(r5 had landed X1-X4 — V.V/80-85, RED-proven; full orchestrator regate green: 85/85
sh+dash, 15/15 both, shellcheck 11 = baseline, probe 16/16 byte-restored.)

1. **HIGH — framing witnesses mistake an inner/data `}` for the outer delimiter** — a
   truncated envelope emits and authorizes archival; a truncated send body publishes.
2. **HIGH — the escaped-ID witness is not unique to the DM block** — a status field
   containing `"id":"<pending-id>"` satisfies it while the DM block is dropped.
3. **MEDIUM — absence not proven through ancestors**: `dm/<lane>` as a regular file /
   unsearchable dir makes both leaf tests false and status silently skips the banner;
   `_dm_failed_count` early-returns zero the same way.
4. **MEDIUM — audit-trail drift**: plan named `fe1a329` as "the final sweep", CHANGELOG
   still said 79 scenarios.

**Adjudication (orchestrator + Steve, on the record):** findings 1–2 are the SECOND
consecutive round holing the witness layer (round 3 was the first). The root cause is
structural — POSIX shell cannot parse JSON, message content may contain any byte, so no
`case` pattern separates an outer delimiter from a data byte; tightening is non-convergent
by construction. **Steve signed ruling 13b (`b5b5b83`): the witness layer STOPS at r5.**
Witness-passing-but-invalid output folds into ruling 13's byzantine boundary (requires a
deliberately defective jq on PATH = code execution as the user); residual exposure — a
message archived without delivery, recoverable from `read/` — accepted on the record.
Finding 3 → fix round r6 (`d30c736`): `_dm_failed_state` tri-state root→lane walk,
V.Y/86-89. Finding 4 → orchestrator (`e3e7dc3`).

## Round 5 — on `d30c736` (r6) → NOT READY, 0 HIGH / 4 MEDIUM → fix round r7

Brief: `docs/prompts/dm-v122-final-sweep-r5.md` · Job: task-msgaoe8u-dwgo60
The brief declared the 13b ceiling and invited a one-paragraph "boundary objection" if the
sweep believed the ceiling wrong. **No objection was filed.** Zero findings landed on the
witness layer or message lifecycle — the round moved entirely to performance-claim,
instrument, and record hygiene:

1. **MEDIUM (Z1) — healthy status path not fork-free as the r6 brief claimed** (`$( )`
   around `_dm_failed_count`; V.Y/89 tested a manufactured absent-leaf, not the ordinary
   existing-empty state).
2. **MEDIUM (Z2) — `_dm_failed_count` trusts its glob without post-expansion revalidation**,
   and its r6 ancestor block was redundant with `cmd_status`'s own gate (deleting it left
   V.Y/86-89 green).
3. **MEDIUM (Z3) — probe M6's sed address matches THREE engine lines**, hits the intended
   one by ordering luck; the manifest self-checked replacements, not address cardinality.
4. **MEDIUM (Z4) — records stopped at r5/85** while the branch held r6/89 (this file's
   round 4 still read IN FLIGHT).

**Disposition:** Z1-Z3 + the test-header half of Z4 → fix round r7
(`docs/prompts/dm-v122-fix7.md`, job task-msgbgefd-z6ez9j): `_dm_failed_count` became the
one authoritative tri-state+count call returning via `_DM_FAILED_COUNT` (fork-free both
paths, post-enumeration revalidation), the probe gained an address-cardinality self-check
over all 21 selectors × 16 mutants (M6 re-addressed: 3 matches → 1 — RED-proven, the old
address fails the new check), scenarios V.Z/90-91 pin the ordinary empty/positive states,
and the non-drivable revalidation defense is DECLARED as suite gap [Q7] rather than
spending the round's one-mutant budget on a hollow probe (zero new mutants). Doc half of
Z4 → orchestrator (this reconciliation). Orchestrator regate on the delivered tree: 91/91
+ 15/15 under sh AND dash, sh -n/dash -n clean, shellcheck 11 = baseline (same 4 codes),
A/B vs `d30c736` confirms V.Z/90-91 are guards (pass both engines — the engine change is
a refactor + a declared-non-drivable defense; the discriminating gain is the probe's own
RED: old M6 address = 3 matches, re-addressed = 1, measured independently).

## Round 6 — on `1249b99` (r7) + docs `2cb0021` → NOT READY, 0 HIGH / 1 MEDIUM → fix round r8

Brief: `docs/prompts/dm-v122-final-sweep-r6.md` · Job: task-msgeseja-af0b2i
Steve's explicit call after r7 (offered "declare convergence" as the alternative; he chose
the sweep). Zero product findings; zero witness-layer findings; no 13b boundary objection.
The one finding is in the INSTRUMENT:

1. **MEDIUM — the r7 cardinality check bounds multi-count selectors by COUNT only.** M7
   (×2) and M10 (×5) were deliberately excluded from the exact-line anchor manifest, so a
   selector can drift to a DIFFERENT set of N lines with every integrity check green.
   Composed counterexample (orchestrator-CONFIRMED by measurement — the Codex sandbox
   denied `mktemp`, so all evidence was re-established locally): break the engine's
   backlog-continuation instruction (absolute → relative path, a real must-survive #7
   regression) + plant a compensating comment → M10 cardinality still 5, changed-line
   count still 5, no anchor breaks, `continuation_signal()` matches broad wording only,
   probe still reports `M10 killed exactly [V.C/24]`.

**Disposition:** fix round r8 (`docs/prompts/dm-v122-fix8.md`, job task-msgfl286-mz10tn) —
**W1** V.N/50 additionally asserts the continuation instruction carries the exact expanded
receiving-vault engine invocation (rung-1 behavioral assertion; the broad #4 alternation
and its negative control unchanged); **W2** M7's 2 + M10's 5 lines join the exact-line
manifest (bounded by count AND exact lines), M10's required kill set gains V.N/50. The
sweep's suggested ">40-message sibling-worktree test that extracts and executes the
continuation command" was **DECLINED per the proportionality brake** (new harness
machinery; a review finding is evidence, not authorization; W1+W2 discriminate the named
fault at strictly lower cost). Zero new mutants, zero new helpers. Orchestrator regate:
91/91 + 15/15 under sh AND dash, syntax clean, shellcheck 11 = baseline, probe 16/16 with
`M10 killed exactly [V.C/24 V.N/50]`, and the counterexample A/B now discriminates both
ways — the drifted engine fails EXACTLY V.N/50 (90/91) and its continuation anchor is
absent from the manifest (0 matches vs 1 on the real engine).

**Round-landing split, on the record (per the proportionality convention):** sweeps 5 and
6 combined — 0 product defects, 5 instrument/record defects. Production code has not
changed since `1249b99`; the engine has not changed since `d30c736` except r7's fork-free
refactor. The loop's findings have moved fully off the shipping surface.
