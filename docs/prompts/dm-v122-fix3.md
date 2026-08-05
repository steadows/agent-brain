# Dispatch brief — DM v1.2.2 fix round 3: final-sweep findings F1–F3

Same per-arc override as `dm-v122-fix2.md` (Steve, 2026-08-05): you own engine AND test
edits. Do NOT commit. Every fence from `docs/prompts/dm-v122-full-round.md` §3 applies
(commit-install.sh byte-frozen; no cmd_install/_write_project_settings/templates/.brain;
existing scenarios frozen except where a fix names them; probe kill declarations may
strengthen, never weaken). Required reading: `.context/seams/dm-v1.1-queue.md` rulings
1–12 (F1 is ruling 10's scope — "no archive may rest on an operation declared unsafe";
no new ruling is needed), then `docs/reviews/lane-dm-v122-pre-pr-code-review.md`, then
this file.

## F1 (HIGH) — the hook must discard its staged batch on a systemic jq failure

`_hook_session_start`: when `_DM_JQ_SYSTEMIC_FAILURE=1` breaks the loop, `_digest` and the
positional filenames staged by EARLIER successful digests survive, so the hook emits and
archives that prefix despite the engine declaring the operation systemically unsafe — and
the pinned `$_DM_JQ_BIN` doing that emit is the same binary that just failed the re-probe.
Fix: on the systemic break, discard exactly like the post-exhaustion unestablishable path
already does (`_digest=""; _more_dm=0; set --`) — one shared discard, not two copies, if
you can do it without adding nesting. `cmd_dm_take` is NOT affected (it emits per message
before archiving each; already-emitted messages were genuinely delivered).

TEST (new limb or scenario beside V.R/71): pinned shim digests message 1 normally, returns
the recorded parse status for message 2, fails the contract re-probe, then answers the
serialization call with `{}` rc 0. Assert: NOTHING archived (read/ empty), BOTH messages
still pending, one systemic warn naming the binary, and the emitted hook context does NOT
contain message 1's digest. Then stable-jq retry delivers both. V.N/53 shim discipline.
State in your report that you verified the fix-absent version fails exactly this limb
(A/B against the unfixed engine).

## F2 (MEDIUM) — `_dm_failed_count` must see dot-named quarantine artifacts

Ruling 12 quarantines `.poison`-style entries into `failed/` under their byte-exact dot
names; `_dm_failed_count` enumerates only `failed/*`, so the status banner reads 0 and is
suppressed. Fix: enumerate `*` and `.*`, filtering only `.` and `..` (a quarantined
`.tmp-*` in failed/ SHOULD count — the exclusion is a pending/-side send-staging rule, not
a failed/-side rule). TEST: extend V.R/74 (or a status scenario) to assert the failed-DM
banner counts a quarantined dot entry.

## F3 (MEDIUM) — drop the `.*` scan from `_dm_id_in_use`

Minted ids are digit-leading, so no dot basename can ever satisfy the `"$_iu_id"*` case —
the second glob only adds an unbounded walk over quarantine residue to every send. Revert
that one widening (keep the exact witness + `<id>*` glob + both-sides validation; keep
hidden-entry enumeration in `_dm_dir_has_entries` and both consume loops, where it is
load-bearing). Update probe anchors if this moves an anchored line.

## Gates — full battery on the FINAL tree, paste real output

`./test/dm.sh` + `./test/commit-install.sh` under sh AND real dash; `sh -n`/`dash -n`;
shellcheck count vs 11 baseline + identical code set; `sh test/mutation-probe.sh`. Re-run
everything LAST on the delivered tree. Report: verdict first, per-fix table, A/B evidence
for the F1 limb, gate outputs, fence self-declarations.
