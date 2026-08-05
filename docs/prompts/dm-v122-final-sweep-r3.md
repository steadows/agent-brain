# Final adversarial sweep, round 3 — lane-DM branch at 3774640 (pre-PR convergence gate)

Same contract as rounds 1–2 (`dm-v122-final-sweep.md`, `dm-v122-final-sweep-r2.md`): you
work ALONE (no sub-agents, no fan-out), findings only, no code edits. If you cannot find
material issues, say READY explicitly — do not invent findings. Do not go easy either.

## Scope

`git diff main...HEAD`. Newest code is `3774640` (r4): the structural witnesses of map
rulings 13–14 (`.context/seams/dm-v1.1-queue.md` § v1.2.4) — digest id-witness in
`_dm_pending_digest`, envelope witness in `_emit_session_ctx_pinned`, send-encoder witness
in `_dm_write_json`, the uninspectable-failed/ status banner — plus scenarios V.U/76–79 and
the adapted probe mutants (M3/M5/M6 compound mutations). Weight attention there. Read the
map end-to-end (rulings 1–14), INCLUDING ruling 13's trust-boundary paragraph.

## Skip list

Everything in both prior rounds' skip lists, PLUS: rc-0 `{}`/empty acceptance on digest,
envelope, and send (G1/G2 → W1–W3); the status zero-on-failure (G3 → W4); plan/CHANGELOG
convergence wording and the missing review artifact (G4 → fixed; the record is
`docs/reviews/lane-dm-v122-convergence-sweeps.md`).

**Boundary reminder:** a finding that requires a PATH binary which passes the full probed
contract AND forges structurally well-shaped payloads (correct id, four keys) is answered
by ruling 13's declared trust boundary — do not file it. Findings INSIDE the boundary
(accidental breakage shapes, witness bypasses cheaper than full forgery, composition bugs
between the witnesses and the discard/abort machinery) are exactly what this round is for.

## Fresh angles

1. The witnesses' own edges: the digest witness's `case` pattern vs ids containing `-<bump>`
   suffixes; the envelope witness matching the staged id as a bare substring of the escaped
   context (false-positive match risk — could an id-shaped string in unrelated context text
   satisfy it while the actual digest block was dropped?); `_dm_write_json`'s payload now
   crossing `$( )` (content, not a path — but confirm no byte-loss matters); interaction of
   the send witness's warn with the `@all` partial-failure accounting.
2. The adapted probe mutants: do M3/M5/M6's compound seds still discriminate what their
   comments claim, and does any anchor now match more than once only by luck?
3. Anything the narrowing ladder predicts next, INSIDE the boundary.
4. Doc drift from `a2eb0de`.

## Report

Verdict line FIRST: READY or NOT READY. Findings: File / Line / Category / Severity /
Finding / Evidence / Fix.
