# Dispatch brief — DM v1.2.2 fix round 7: sweep-r5 findings (the last round)

Same per-arc override (Steve, 2026-08-05). Engine + test edits yours; do NOT commit. All
standing fences apply — and note the DOC fence: you own `test/dm.sh`'s own header prose and
`test/mutation-probe.sh`; the orchestrator owns CHANGELOG / plan / docs/reviews. Required
reading: `.context/seams/dm-v1.1-queue.md` rulings 7, 8, 14, and **13b** (the signed witness
ceiling — this round touches NO witness code; a witness finding is answered by that
paragraph).

## Z1 (MEDIUM) — make the status path actually fork-free, as the r6 brief claimed

`_dm_ensure_tree` creates `failed/` before `cmd_status` runs, so the healthy path takes the
validated-leaf branch and pays a subshell via `$(_dm_failed_count …)`. Fix with the house
variable-return idiom (ruling 8's pattern, as used by `_DM_COLLISION_DEST` / `_WHOAMI` /
`_DM_PENDING_DIGEST`): have the counter set a caller-visible scalar; keep a thin stdout
wrapper only if an existing caller needs one. Both the empty and positive paths must be
subshell-free. **If you conclude fork-free is not achievable without ugliness, say so and
recommend withdrawing the claim instead — do not contort the code to hit it.**

TEST: the ordinary state — `failed/` EXISTS and is EMPTY (not the `rmdir`-manufactured
absent-leaf state V.Y/89 uses) — plus the positive count path.

## Z2 (MEDIUM) — revalidate after enumeration, and pin the defense

`_dm_failed_count` trusts its glob without post-expansion validation: a permission flip
mid-scan leaves both patterns literal and yields zero, which ruling 14 forbids (zero must
mean proven-empty). Add the both-sides revalidation already used by `_dm_dir_has_entries`
and `_dm_id_in_use`.

Its r6 ancestor block is also unpinned — deleting lines ~802-807 leaves V.Y/86-89 green
because `cmd_status` gates the only call with its own `_dm_failed_state`. Either (a) collapse
to ONE authoritative tri-state+count call so the redundancy disappears (preferred — narrowing
beats pinning), or (b) keep both and add root-absent / lane-absent controls that discriminate
the counter's own block.

**Instrument budget, explicit:** you may add AT MOST ONE new probe mutant for the count
consumer, and only if option (a) leaves a genuinely unpinned defense. If neither (a) nor a
single mutant works, DECLARE it as a `[Q7]` gap in the suite header instead. Do not build
new harness machinery.

## Z3 (MEDIUM) — the probe's M6 anchor is ambiguous, and the manifest doesn't catch it

`^  if [ "$#" -gt 0 ]; then$` matches THREE engine lines (~1418, ~1503, ~1526); M6 currently
hits the intended one only because it is first and followed by a four-space `case`. The
anchor manifest self-check validates the replacement, not the address cardinality.

Fix both halves: (a) re-address M6 to something unique (the `_esc_payload` case line, or
scope it inside `_emit_session_ctx_pinned`); (b) extend the manifest self-check so EVERY
mutant's sed ADDRESS is cardinality-checked against the engine, not just its replacement —
this is the probe's own integrity guarantee and is the highest-value item in this round.
Audit all 16 mutants for the same ambiguity class while you are in there and report what you
find (fix any that are ambiguous).

## Z4 — test-file prose

`test/dm.sh`'s AUTHORITY header: add ruling 14's ancestor-validation → V.Y/86-89 mapping and
whatever V.V/80-85 mapping is missing; mention erratum 13b as the witness ceiling so a future
reader does not re-open it. Probe header stays current.

## Gates — full battery on the FINAL tree, paste real output

Both suites × sh AND real dash; sh -n/dash -n; shellcheck vs 11 baseline + code set;
`sh test/mutation-probe.sh` (including the new address-cardinality self-check). Re-run
everything LAST. Report: verdict first, per-fix table, A/B evidence naming which scenarios
fail against the unfixed engine, the M6/ambiguity audit result, gate outputs, and fence
self-declarations.
