# Dispatch brief — DM v1.2.2 fix round 6: ancestor-state validation on the status path (sweep-r4 M3)

Same per-arc override (Steve, 2026-08-05). Engine + test edits yours; do NOT commit. All
standing fences apply. Required reading: `.context/seams/dm-v1.1-queue.md` rulings 7, 14,
and **13b** (the ceiling — this round adds NO witness changes; a witness finding is
answered by 13b's paragraph, do not touch that layer).

## Y1 (MEDIUM, the only code fix) — absence must be PROVEN through validated ancestors

`cmd_status`'s failed-banner gate tests only the leaf (`-e`/`-L` on `dm/<lane>/failed`):
when `dm/<lane>` (or `dm/` itself) is a regular file, FIFO, symlink, or unsearchable dir,
the leaf test is false and status silently skips — contradicting ruling 14's "zero means
proven-empty". Same flaw inside `_dm_failed_count`'s early return.

Fix per rulings 7/14: absence may fast-path ONLY beneath validated ancestors. Walk root →
lane with the existing `_dm_dir_ok`-style tri-state (missing-under-valid-parent = proven
absent, no banner; malformed/unsearchable ancestor = the cannot-inspect banner). Reuse
existing helpers — do not build a new walker if `_dm_dir_ok` composition suffices. Keep the
common no-failures boot fork-free.

## Tests

Scenario variants: `dm/<lane>` as a regular file; `dm/` root as a symlink to a file;
lane dir 0300 (unsearchable) — each must produce the cannot-inspect banner from
`brain status`, never a silent skip, never a spurious zero. A genuinely absent
`dm/<lane>/failed` under healthy ancestors stays banner-free. A/B: name which scenarios
fail against the unfixed engine (current HEAD).

## Gates — full battery on the FINAL tree, paste real output

Both suites × sh AND real dash; sh -n/dash -n; shellcheck vs 11 baseline + code set;
`sh test/mutation-probe.sh`. Re-run everything LAST. Report: verdict first, A/B evidence,
gate outputs, fence self-declarations.
