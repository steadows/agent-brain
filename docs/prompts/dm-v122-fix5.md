# Dispatch brief — DM v1.2.2 fix round 5: witness tightening per ruling 13a

Same per-arc override as rounds 2–4 (Steve, 2026-08-05; he approved this round explicitly).
You own engine AND test edits. Do NOT commit. All standing fences apply. Required reading:
`.context/seams/dm-v1.1-queue.md` ruling **13a** (the erratum — THE spec for this round),
then the round-3 findings in `docs/prompts/dm-v122-final-sweep-r3.md`'s result (summarized
below). Witnesses stay `case`-pattern cheap — still no shell-side JSON parsing.

## X1 (HIGH) — framing: all three witnesses require the closing `}`

Digest (`_dm_pending_digest`), envelope (`_emit_session_ctx_pinned`), send
(`_dm_write_json`): add the `}`-terminated check (`case ... in *\})`). Mind the values'
provenance: digest/envelope/send payloads all pass through `$( )` which strips trailing
newlines, so the last byte IS the payload's last byte.

## X2 (HIGH) — send witness matches key syntax

`"from":` `"to":` `"ts":` `"content":` (colon included), not bare quoted words.
`{"values":["from","to","ts","content"]}` must now fail the witness.

## X3 (HIGH) — envelope witnesses the escaped digest fragment

Match `\"id\":\"<first-staged-id>\"` (backslash-quote forms — the digest block inside the
serialized context string necessarily carries them; plain status text cannot). Build the
pattern from the staged name without `$( )`. A context whose DM block was dropped but whose
status text contains the bare id must now FAIL the witness.

## X4 (MEDIUM) — ruling 14 fast path is absence-only

`cmd_status`'s `-d` gate: any existing `failed/` path (file, FIFO, symlink, dir) goes
through `_dm_failed_count`; only proven absence skips. A regular file at `failed/` must
produce the cannot-inspect banner.

## Tests (you own them)

- rc-0 final-delimiter-removal shims (delegate to real jq, strip the final `}`/byte) for
  digest, envelope, and send paths — assert nothing archived/published/journaled, pending
  intact, one warn naming the binary, stable retry delivers.
- The wrong-object send payload (`{"values":[...]}`) — direct and @all: send fails, no
  pending file, no journal delivery line.
- The envelope false-positive: receiver presence `current_ticket` set to the pending
  message id + a serializer shim that keeps only the status portion of the context —
  assert NOT archived, pending intact.
- `failed/` as a regular file → cannot-inspect banner.
- A/B: name the exact scenarios that fail against the unfixed engine (3774640).
- Prose: update test/mutation-probe.sh's header label to v1.2.4 (it still says v1.2.3
  despite carrying the v1.2.4 compound mutants) — sweep-r3 M5's test-file half.

## Gates — full battery on the FINAL tree, paste real output

Both suites × sh AND real dash; sh -n/dash -n; shellcheck vs 11 baseline + code set;
`sh test/mutation-probe.sh` (re-anchor minimally; declarations may strengthen only).
Re-run everything LAST. Report: verdict first, per-fix table, A/B evidence, gate outputs,
fence self-declarations.
