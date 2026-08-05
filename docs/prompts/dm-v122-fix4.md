# Dispatch brief — DM v1.2.2 fix round 4: structural witnesses (rulings 13–14)

Same per-arc override as fix rounds 2–3 (Steve, 2026-08-05): you own engine AND test edits.
Do NOT commit. All standing fences apply (commit-install.sh byte-frozen; no
cmd_install/_write_project_settings/templates/.brain; existing scenarios frozen except where
a fix names them; probe declarations may strengthen, never weaken). Required reading:
`.context/seams/dm-v1.1-queue.md` — rulings 13–14 (§ v1.2.4) are THE spec for this round;
read the trust-boundary paragraph carefully: the witnesses are deliberately CHEAP (`case`
checks on values the engine knows are glob-safe). Do NOT build shell-side JSON parsing,
escaping, or byte-matching of arbitrary content — a finding that needs a forged well-shaped
payload is answered by the map's boundary paragraph, not by code.

## W1 (ruling 13, digest witness) — HIGH

`_dm_pending_digest`: an rc-0 digest is provisional until: non-empty, `{`-prefixed, and
contains `"id":"<message-name>"` (the name is already grammar-checked — digits, one `T`, `Z`,
`-`; safe inside a `case` pattern). A failed witness = systemic dependency failure: set
`_DM_JQ_SYSTEMIC_FAILURE=1`, warn once naming `$_DM_JQ_BIN`, return 1 (leave pending). Both
consume paths then already abort/discard via the existing r3 machinery — verify that
composition rather than adding new branches.

## W2 (ruling 13, envelope witness) — HIGH

`_emit_session_ctx_pinned`: the staged payload must additionally be `{`-prefixed and, when
messages are staged (`$# -gt 0`), contain the FIRST staged message's id (pass it in or use a
caller-visible variable — never `$( )` for anything path-derived; the id itself is glob-safe).
Failure → no emit claim, no archive, everything pending, one warn.

## W3 (ruling 13, send witness) — HIGH

`_dm_write_json` output must be non-empty, `{`-prefixed, and contain all four field keys
(`"from"` `"to"` `"ts"` `"content"`) before `_atomic_place` publishes it. Any miss fails the
send (nonzero, diagnostic naming the binary) and MUST NOT write the delivery journal line
(check `cmd_dm`'s announce ordering — direct and @all paths both).

## W4 (ruling 14, status banner) — MEDIUM

`_dm_failed_count` failure (rc 1) must not render as 0: `cmd_status` prints an explicit
"⚠ DM failed/ state cannot be inspected for @<lane>" style banner on that path. Zero is
reserved for proven-empty. Keep the hook/status rc contracts unchanged.

## Tests (you own them)

- Take + hook + send variants of the rc-0 `{}` same-path shim (passes all probes, answers
  payload calls with `{}` rc 0): assert nothing archived / nothing published / no journal
  delivery line / everything pending or send failed / one warn naming the binary / stable-jq
  retry works. The send variant must also assert the pending/ file was never created (or was
  cleaned) and the journal has NO dm call-log line for the failed send.
- Unreadable-failed/ status scenario: `failed/` 0300 with an entry → banner says
  cannot-inspect, not zero. Reuse `make_unreadable_dir`.
- A/B: state in the report that each new scenario fails against the unfixed engine
  (baff2ee) and name the exact failing assertions.

## Gates — full battery on the FINAL tree, paste real output

Both suites × sh AND real dash; sh -n/dash -n; shellcheck vs 11-baseline + code set;
`sh test/mutation-probe.sh` (re-anchor minimally if a witness moves an anchored line).
Re-run everything LAST. Report: verdict first, per-fix table, A/B evidence, gate outputs,
fence self-declarations.
