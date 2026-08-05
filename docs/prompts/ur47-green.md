# GREEN — UR-4a / UR-4b / UR-7 (implement against the frozen suite)

GREEN + REFACTOR only. The RED tests are **already written and FROZEN** at
`test/commit-install.sh` (commit `fc84630`, 15 scenarios: 7 RED to turn green, 8 guards that must
STAY green). **Do NOT modify, weaken, skip, or delete any test — in either suite.** If a test
looks wrong, say so in your report instead of changing it; a diff touching either test file is an
automatic review flag.

`test/dm.sh` (45 scenarios) is separately frozen and currently **45/45 green**. It must stay that
way — run it too.

## Required reads, in order

1. `.context/seams/dm-v1.1-queue.md` — §"UR fixes riding along". **Read the UR-4a ruling in full.**
   It states a FOUR-way constraint and names the verified implementation shape. Two of those four
   constraints exist because a fix for the previous one broke them; do not rediscover that.
2. `test/commit-install.sh` — the scenario comments state exactly what each proves and does not.
3. `docs/lane-dm-ultrareview-findings.md` — UR-4a, UR-4b, UR-7 as originally reported.
4. `ROADMAP.md` — the "Known issue — `brain commit` wedges for one class of legacy vault" entry.

## The work

**UR-4a — `cmd_commit` cleanup wedge.** All four constraints must hold simultaneously:
1. **Unwedge, permanently.** A staged deletion of an intentionally-untracked DM path must not
   abort — and must not abort on retry either. A one-shot success is not the fix.
2. **No pathspec semantics on the commit.** `git commit -- .brain` re-reads the WORKING TREE for
   those paths, so a live inbox on disk can be committed after the index was purged.
3. **Still path-scoped in effect.** ONLY `.brain` paths may land in the commit. The engine
   advertises "path-scoped" in its usage; dropping the pathspec makes `git commit` take the whole
   index and sweeps a developer's unrelated staged work into the vault commit.
4. **The real index must agree with the new HEAD for `.brain` afterward** — and the developer's
   unrelated staged paths must remain staged. Otherwise the next ordinary `git commit -a`
   silently reverts the sync.

   The verified shape: temp index seeded from **HEAD** → stage only `.brain` into it (DM excluded)
   → `write-tree` → `commit-tree` → `update-ref` → **`git reset -q HEAD -- .brain`**. A blanket
   `git read-tree HEAD` satisfies (4)'s first half and silently un-stages unrelated work — the
   suite catches that; do not go there.

   ⚠ **Both purges in `cmd_commit` are live code.** The pre-`git add` purge looks dead on the
   fixed engine (removing it breaks no test) but is what pulls a tracked inbox into the secret
   scan. Do not delete either as "redundant" — see the ROADMAP known issue.

**UR-4b — ignore check.** Replace `grep -qxF 'dm/'` with a behavioral check
(`git check-ignore --no-index`). A string match cannot see a later negation re-including the
path; the suite parametrizes over `!dm/`, `!/dm/` and `!dm`, so a smarter grep will not pass.

**UR-7 — `cmd_install`.** Check **every** `mkdir` and `cp`; never print success after a failure.
Route the skill placement through `_atomic_place` (`bin/brain:55`) and create the settings temp
file **in the destination directory**, not `$TMPDIR` — the existing `mktemp`→`mv` into `$HOME` is
a cross-device rename and therefore not atomic. A failed install must leave the PREVIOUS skill
intact, never a truncated one. `_write_project_settings` is the third `_atomic_place` consumer and
should land in the same change (verified safe: it keeps the suite at 15/15).

## Quality bar (constraints the tests cannot express)

1. **`cmd_commit` runs with the `commit` lock held.** Every new early-exit path must
   `_lock_release commit` before dying — a leaked lock has no staleness break and wedges the lane.
2. **Clean up the temp index** on every path including failure; never leave `.git/*index*` litter.
3. **POSIX `sh` only** — no bashisms; must run under macOS `/bin/sh` AND `dash`.
4. Match existing conventions: `_warn`/`_die` prefixes, `--` terminators on git pathspecs.
5. Do not touch the DM queue code — it is green and separately frozen.

## Gate bar (all must pass before reporting done)

- `./test/commit-install.sh` → **exit 0, 15/15**, zero guard failures (run unpiped; exit 3 means a
  guard regression — hard stop, investigate).
- `./test/dm.sh` → **exit 0, 45/45**, unchanged.
- Both suites also green under `dash`.
- `sh -n bin/brain` clean; `shellcheck bin/brain` → no NEW findings vs the `main` baseline
  (3 SC2015, 5 SC2016, 3 SC2086, 2 SC3012).

Leave changes uncommitted (the orchestrator inspects and commits). Report: what you implemented
per finding, both suite tallies, shellcheck delta, and anything in the frozen suites or the seam
map you believe is wrong — report, don't fix.
