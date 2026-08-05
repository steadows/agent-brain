# Ultrareview — lane-DM v1.1 FINAL diff (pre-deploy gate)

Execute this using your **steadows-ultrareview** skill, explicitly. **Review-only — report
findings, do not edit code.** Scale a **full-size fleet**: this diff is concurrency-heavy,
touches a security-relevant commit path, and ships code that runs unattended in every
session of a 13-lane fleet. Do not downscale on the grounds that most added lines are tests.

## Why this runs a second time

An ultrareview already ran on this branch (2026-08-03) against the **v1.0 engine** and
returned NOT READY with 10 findings — all since closed. The engine was then **rewritten**
(the v1.1 per-message-file queue), so *the code you are reviewing is not the code that
review saw.* Since that rewrite, a `/simplify` pass and a 5-agent pre-PR code review have
landed; the code review found **5 HIGH** defects in the rewritten engine, two of which
silently and permanently disabled DM delivery. Those are now fixed.

**The relevant prior: every gate so far has found real defects in code the previous gate
had already passed.** Assume this one will too. The two worst defects to date were both
*silent permanent* failures that no test caught and that read as harmless code.

## Scope

`git diff main...HEAD` in this repo (33 commits, 24 files, ~6.9k insertions). Read in full:

- `bin/brain` — the engine (POSIX sh; **must run on `/bin/sh` AND `dash`**). ~1.1k diff lines.
- `.context/seams/dm-v1.1-queue.md` — **the design authority.**
- `test/dm.sh` (53 scenarios), `test/commit-install.sh` (15), `test/mutation-probe.sh`.
- `templates/DM-PROTOCOL.md`, `templates/navigation-standards.SKILL.md` — deployed to lanes.
- `AGENT_BRAIN_DM_GSD_PLAN.md` Phase 5–6 — the deploy runbook this gates.

## Deliberate shapes — do NOT re-litigate

Each looks wrong and is proven load-bearing; the seam map carries the measurement.

- **Both purge blocks in `cmd_commit` are live code.** The pre-`git add` purge looks dead
  on the fixed engine and is not — it stages a DM deletion *before* the secret scan.
- **The temp-index commit dance** (read-tree HEAD → add `.brain` → purge dm → write-tree →
  commit-tree → update-ref → `git reset -q HEAD -- .brain`) satisfies a **four-way**
  constraint. Four independent candidate fixes — including a prior review's own sketch —
  broke one of the four while still scoring 12/12.
- Bare wall-clock lease, no PID/liveness check (matches dirq/SQS practice).
- Poison cap → terminal `failed/`; **at-least-once** delivery (duplicates OK, loss not);
  no fsync, so power-loss durability is explicitly not claimed — only process-crash safety.
- The symlink-check TOCTOU residual is documented as unclosable in POSIX sh.
- The legacy-vault secret-scan wedge is a recorded ROADMAP known issue (pre-existing).
- `brain dm take` is deliberately bounded and does **not** loop; the caller repeats.

## Already found — do not re-report as new (escalate only if materially worse than rated)

**Closed (10):** the 2026-08-03 ultrareview findings — see
`docs/lane-dm-ultrareview-findings.md`.

**Closed this round (5 HIGH)** — see `docs/reviews/lane-dm-v11-pre-pr-code-review.md`:
path word-split on space-containing repo paths; digest bounds bypassable via extra fields /
multi-object files; leading-zero + over-range decimals reaching arithmetic (fatal, wedged
every boot); `_dm_ack` intercepting its own ENOENT soft-landing; unbounded per-message
claim forks at boot.

**Known-open MEDIUM/LOW, deliberately deferred** (in that same report — do not re-report):
poison `failed/` invisible cross-lane; `_dm_purge_stale_temps` failure skipping lease
recovery; ambiguous `cmd_whoami` attributed to `system`; rollback-drain runbook not
executable cross-lane; `find -mmin` undeclared; commit hooks bypassed by `commit-tree`;
`brain inbox` `@`-prefix / unregistered-lane inconsistencies; one corrupt file blocking a
batch digest; four zero-coverage paths (pre-tool hook, reserved names, direct `announce`,
whoami-empty hook exit).

## Where to aim

The last two gates found their worst defects in the **consumer boundary** — code that reads
the queue and trusts its own producer's grammar. Weight accordingly, and specifically hunt:

1. **Anything that turns a recoverable condition into a permanent or silent one.** That is
   the shape of every serious defect found so far. A message that stalls, a boot that dies,
   a state nothing can leave, an error that only reaches `.hook-errors.log`.
2. **The newly-added validators themselves** — `_dm_decimal_ok`, `_dm_attempt_ok`,
   `_dm_id_ok`, `_dm_route_failed`. They are the fix for the last round's worst bug and have
   existed for hours. Are they complete? Ordered correctly relative to the operations they
   guard? Does `_dm_route_failed` introduce a collision, a loop, or a new wedge of its own?
3. **The rewritten `_dm_digest`** — recursive jq `bounded()`, a subshell `cd`, per-file
   validation, an aggregate cap. Does the recursion terminate for every input? Can any
   input still exceed the caps, produce invalid JSON, or make jq abort a whole batch?
4. **Concurrency beyond rename arbitration** — two live sessions of one lane, sender racing
   consumer, recover racing claim/ack, `brain commit` racing an active queue, the claim cap
   interacting with lease recovery (starvation: can a message at the back of a >40 backlog
   be starved indefinitely, or ride to `failed/` without ever being delivered?).
5. **`sh` vs `dash` divergence** in anything added — arithmetic, `case` patterns,
   parameter expansion, `local`-free scoping, subshell exit-status propagation.
6. **Deploy-time correctness** — Phase 5 swaps this engine into a live vault where 13 lanes
   are mid-session. Does anything in the diff break a *running* old-engine session, or a
   new-engine session reading state an old one left?
7. **The test suites as instruments** — a scenario that passes for the wrong reason, an
   assertion that cannot fail, a fixture that doesn't reach the code it names. The suites
   are frozen and append-only; `test/mutation-probe.sh` records which mutants kill which
   scenarios — check its declarations are honest.

## Output

Standard ultrareview report: severity-ranked findings with file:line, concrete failure
scenario, evidence (reproduce where cheap — `dash` is available), and a fix recommendation.
State a READY / NOT READY verdict for deploying this engine into the live 13-lane vault.
If the diff is genuinely clean, say so — do not manufacture findings.
