# Ultrareview ROUND 2 — lane-DM v1.1 (pre-deploy gate, re-run after the fix round)

Execute this using your **steadows-ultrareview** skill, explicitly. **Review-only — report
findings, do not edit code.** Scale a **full-size fleet**: concurrency-heavy, a
security-relevant commit path, and code that runs unattended in every session of a 13-lane
fleet. Do not downscale because most added lines are tests.

## Track record — read this before deciding how hard to look

This is the **third** adversarial gate on this branch. Every previous one found real
defects in code a prior gate had already passed:

| Gate | Result |
|---|---|
| Ultrareview #1 (v1.0 engine) | NOT READY — 10 findings; engine then **rewritten** |
| 5-agent code review (v1.1) | NOT READY — **5 HIGH**, two of them silent permanent loss of all DM delivery |
| Ultrareview #2 (v1.1) | NOT READY — **6 HIGH**, incl. a deploy model that would have shipped a feature doing nothing |

**Also relevant: the fix round you are now reviewing was itself unreliable.** The
implementing job *failed* mid-run, and the state it committed (`c5d515f`) was **2 scenarios
RED** — an over-strict id check was routing 40 deliverable messages into `failed/`. The
completing fix (`661327f`) was recovered from an uncommitted working tree. Treat the fix
round with the same suspicion as the code it fixes: **verify the fixes are complete and did
not introduce new defects**, rather than assuming a green suite means done.

## Scope

`git diff main...HEAD`. Read in full:
- `bin/brain` — POSIX sh, **must run on `/bin/sh` AND `dash`**.
- `.context/seams/dm-v1.1-queue.md` — the design authority.
- `test/dm.sh` (60 scenarios), `test/commit-install.sh` (15), `test/mutation-probe.sh`.
- `templates/DM-PROTOCOL.md`, `templates/navigation-standards.SKILL.md`.
- `AGENT_BRAIN_DM_GSD_PLAN.md` Phase 5–6 — the deploy runbook.
- `docs/reviews/lane-dm-v11-final-ultrareview-findings.md` — round 2's findings.

**Do not try to run the suites** — a read-only sandbox rejects their `mktemp`. The
orchestrator ran them on the shipped tree: **60/60 and 15/15 on `sh` and `dash`**, `sh -n`
and `dash -n` clean, shellcheck **11** (baseline), and `test/mutation-probe.sh` reports
**12/12 mutants killing exactly their declared scenarios** with its instrument self-check
passing. Review the *instruments' honesty*, not their exit codes.

## What changed since ultrareview #2 (this is what you are checking)

1. **Deploy model** — lanes were executing their own stale per-worktree `.brain/bin/brain`.
   The engine now emits an absolute `"$BRAIN/bin/brain"`; templates use a `<brain>`
   placeholder resolved via `--git-common-dir`; Phase 5 updated.
2. **Poison isolation** — per-file validation/routing so one bad message no longer sends
   its healthy batchmates to `failed/` unemitted.
3. **Lease sweep** — `claimed/` is swept so a crashed session's claim is actually recovered.
4. **Collision guard** — `_dm_dest_occupied`; transitions refuse occupied/non-regular
   destinations; collision-preserving names in `failed/`.
5. **ID byte bound** — `DM_ID_MAX_BYTES` reserving the claim suffix, so an over-`NAME_MAX`
   claim name can't wedge the queue.
6. **One total transition budget** — `DM_TRANSITION_MAX` spanning recovery, invalid
   routing, and claiming (previously only successful claims were counted).
7. **Carries** — `utf8bytelength` for the digest caps; mutation probe hardened (isolated
   engine copy per mutant, complete-summary requirement, instrument self-check).
8. **`_dm_id_ok`** — the id's bump suffix accepts any digit run (it is a filename token,
   never an arithmetic operand); `_dm_decimal_ok` still strictly rejects leading zeros on
   claim-ts/pid/attempt, the values that DO reach `$(( ))`.

## Deliberate shapes — do NOT re-litigate

Both `cmd_commit` purges are live code; the temp-index dance satisfies a four-way
constraint; bare wall-clock lease, no PID check; poison cap → terminal `failed/`;
at-least-once delivery; no fsync (process-crash-safe only, never "crash-safe");
`brain dm take` is bounded and does NOT loop (the caller repeats); the symlink TOCTOU
residual is documented as unclosable in POSIX sh; the legacy-vault secret-scan wedge is a
recorded pre-existing ROADMAP issue.

## Already found — do NOT re-report

- Ultrareview #1's 10 findings (`docs/lane-dm-ultrareview-findings.md`) — closed.
- The code review's 5 HIGH (`docs/reviews/lane-dm-v11-pre-pr-code-review.md`) — closed.
- Ultrareview #2's 6 HIGH — closed by the changes listed above.
- **Deliberately deferred, do not re-report unless materially worse than rated:** rollback's
  two unsafe windows; the `commit-tree`→index-reset race; unborn-HEAD CAS; `_feat_ok` /
  body-cap locale divergence between sh and dash; poison `failed/` invisible cross-lane;
  temp-sweep failure skipping lease recovery; `system` mis-attribution on ambiguous whoami;
  cross-lane drain ergonomics; `find -mmin` undeclared; `brain inbox` `@`-prefix and
  unregistered-lane inconsistencies; the four zero-coverage paths (pre-tool hook, reserved
  names, direct `announce`, whoami-empty exit).

## Where to aim

1. **The eight changes above are hours old and were written under a failed job.** Are they
   complete, correctly ordered relative to what they guard, and free of new defects? Does
   any fix undo or weaken an earlier one? (`_dm_id_ok`'s relaxation is the obvious one to
   scrutinise — prove the bump token genuinely never reaches arithmetic or a bound.)
2. **The recurring defect shape: anything that turns a recoverable condition into a
   permanent or silent one.** Every serious finding so far has been that. A message that
   stalls, a boot that dies, a state nothing can leave, an error reaching only
   `.hook-errors.log`.
3. **Interactions between the new bounds.** `DM_TRANSITION_MAX` now spans three operations
   that previously had independent limits — can a full budget of recoveries or invalid
   routings starve delivery entirely, permanently, or unfairly? Can a lane at the back of a
   large backlog ride to `failed/` without ever being emitted?
4. **The deploy resolution** — does it hold for every caller (hook, template, `dm take`,
   `inbox`, a detached HEAD, a bare/secondary checkout, a worktree whose `.brain` is
   missing)? Does anything still resolve relatively?
5. **The lease sweep** — new recurring work on a hot path. Cost, reentrancy, interaction
   with two live sessions of one lane, and with the transition budget.
6. **`sh` vs `dash`** in everything added — arithmetic, `case` patterns, parameter
   expansion, subshell status propagation, `utf8bytelength` availability.
7. **The test suites and the mutation probe as instruments.** 60 scenarios now. Does any
   new scenario pass for the wrong reason, assert something unfalsifiable, or name a
   mechanism it doesn't reach? Are the probe's 12 mutant declarations honest — does each
   mutant actually break what it claims, and is any declared kill-set over-broad in a way
   that hides a second defect?
8. **Deploy-time correctness** — Phase 5 swaps this engine into a live vault where 13 lanes
   are mid-session. Does anything break a running old-engine session, or a new-engine
   session reading state an old one left?

## Output

Severity-ranked findings with file:line, a concrete failure scenario, evidence (reproduce
where cheap — `dash` is available), and a fix recommendation. State a **READY / NOT READY**
verdict for deploying this engine into the live 13-lane vault. If it is genuinely clean,
say so plainly — do not manufacture findings to justify the fleet.
