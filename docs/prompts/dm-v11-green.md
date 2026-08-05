# GREEN — DM v1.1 per-message-file queue (implement against the frozen RED suite)

You are implementing GREEN + REFACTOR only. The RED-phase tests are **already written and
FROZEN** at `test/dm.sh` (commit `d8834d3`, 45 scenarios: 33 RED you must turn green, 12 guards
that must STAY green). **Do NOT modify, weaken, skip, or delete any test.** If a test looks
wrong, say so in your final report instead of changing it — a diff touching `test/dm.sh` is an
automatic review flag.

## Required reads, in order

1. `.context/seams/dm-v1.1-queue.md` — **the design contract.** Layout, filename grammar,
   lifecycle, lease/staleness rules (incl. the two rulings at the end: claim-ts = epoch seconds,
   fresh send = `.a0`), the reuse table, the new-seams section with signatures, and the altitude
   decisions. Implement THIS design; the tests pin it.
2. `test/dm.sh` — read the scenario comments; each states exactly what it proves.
3. `docs/lane-dm-ultrareview-findings.md` — UR-1/2/3 are the defects this rewrite exists to fix.
4. `ROADMAP.md` v1.1 entry — acceptance criteria.
5. `.context/dm-v11-suite-audit-round1.md` — the 3-round audit; explains WHY scenarios are
   shaped the way they are. Do not fight the suite.

## Scope

- `bin/brain` — replace the single-inbox DM transport with the per-message queue per the seam
  map: send (`_atomic_place`, dot-temp in `pending/`, `<ts>-<pid>[-<n>].a0` grammar), claim
  (`command mv -f --` into `claimed/<id>.a<k>.c<epoch>-<pid>`, lost-race vs real-error
  disambiguation), recover (lease `DM_CLAIM_MAX_AGE=600`s from the ENCODED epoch, attempt bump,
  `k+1 > DM_MAX_ATTEMPTS=3` → `failed/`), ack (rename into `read/`, warn-never-die on ENOENT),
  `brain dm take` (live path: recover → claim → print digested → ack), boot path
  (recover → claim → digest → emit → ack-each — ack strictly AFTER emit), `cmd_inbox` prints the
  `pending/` dir, symlink validation on EVERY component incl. the paths the old `_inbox_rotate`
  never checked (UR-2), digest over per-message files with content-field truncation (never emit
  broken JSON), `failed/` surfaced in `brain status`. Delete `_inbox_rotate` and the dead
  single-inbox machinery.
- `templates/DM-PROTOCOL.md` + `templates/navigation-standards.SKILL.md` — co-change: document
  `brain dm take` as the live-consumption command, drop the inbox-file watch instructions, and
  **narrow the `announce` promise to what `_recent_journal` actually does** (today-only,
  explicit-mention) — the 3.G scenarios pin this.
- **OUT of scope:** UR-4a/4b (`cmd_commit`) and UR-7 (`cmd_install`) — they have no RED yet and
  are sequenced separately. Touch `cmd_commit`/`cmd_install` ONLY if a frozen test forces it
  (none should).

## Quality bar (constraints the tests cannot express)

1. **The SessionStart hook runs on EVERY boot of 13 concurrent lanes** — the recover/claim/digest
   path is hot; no subshell-per-file loops where one pass does, nothing O(all-history), and an
   EMPTY queue must cost near-zero.
2. **No locks anywhere on the queue path** — rename arbitration IS the concurrency control;
   `_lock_acquire` has no staleness break and must not appear in any dm/take/boot code path.
3. **`_atomic_place` is the ONE temp+rename home** (5 declared consumers in the seam map) — build
   it as the shared helper; do not hand-roll a second temp+rename inside `_dm_send`.
4. **POSIX `sh` only** — no bashisms; must run under macOS `/bin/sh` AND `dash`. All queue moves
   `command mv -f --`.
5. Match the engine's existing conventions: `_warn`/`_die` prefixes, `_feat_ok` path discipline,
   comment style that states what is guaranteed and what is residual.

## Gate bar (all must pass before you report done)

- `./test/dm.sh` → **exit 0, 45/45**, zero guard failures (run it unpiped; the suite exits 3 on
  a guard regression — treat exit 3 as a hard stop and investigate).
- `sh -n bin/brain` clean; `dash test/dm.sh` same verdicts.
- `shellcheck bin/brain` → no NEW findings vs the 13-finding baseline on main (count with
  `grep -cE '^In .* line'`).

Leave your work as uncommitted working-tree changes (the orchestrator inspects and commits).
Report: what you implemented per seam, the final suite tally, shellcheck delta, and anything in
the frozen suite or seam map you believe is wrong (report, don't fix).
