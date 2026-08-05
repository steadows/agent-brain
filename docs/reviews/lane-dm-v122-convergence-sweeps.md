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

## Round 4 — on r5 — IN FLIGHT

r5 landed X1-X4 (V.V/80-85, RED-proven; full orchestrator regate green: 85/85 sh+dash,
15/15 both, shellcheck 11 = baseline, probe 16/16 byte-restored).
