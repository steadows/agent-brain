# GREEN dispatch — DM v1.2: delete the claim layer, implement the direct consume path

**Repo:** `/Users/amap3i/agent-brain` · branch `fix/pretool-collision-warning` @ `503519b`
**Mode: GREEN-ONLY.** The RED suite is frozen at `test/dm.sh` (54 scenarios: 46 pass today, 8
RED). `test/commit-install.sh` (15/15) must stay green. You implement against them; you do not
touch them.

## Required reads, in order

1. `.context/seams/dm-v1.1-queue.md` — **the `# v1.2` section (lines 335–467) is the design
   authority**, decided and acked 2026-08-04. Its `## Delete` list, 8-item `## Must survive`
   checklist, `## Poison, without a counter`, and `## Suite consequences` sections ARE the spec.
   Read the whole file for the v1.1 design context the survivors came from.
2. `test/dm.sh` — the frozen contract. The 8 RED scenarios (V.N/46–53 series + V.N/54) define
   done. Scenario comments carry contract rationale — read them, especially V.C/24 (what the
   continuation instruction must and must not contain), V.N/49–51, V.N/53, V.N/54.
3. `bin/brain` — the engine you are editing. v1.1's claim machinery (~211 lines + 14 `DM_*`
   constants) is what you are deleting.

## The task

Implement v1.2 in `bin/brain` per the map:

**Delete** (the map's list, verbatim): `claimed/` as a state · claim timestamps and claimer
PIDs · `DM_CLAIM_MAX_AGE` leases · stale-claim recovery · the delivery-attempt counter
(`.a<k>`) · the poison cap and `DM_MAX_ATTEMPTS` · the background lease sweeper
(`_dm_arm_lease_sweep`) · the shared cross-state transition budget · `_dm_decimal_ok` /
`_dm_attempt_ok`. Deletion is the deliverable — do not replace deleted machinery with new
state of any kind.

**Consume becomes:** read a bounded batch of `pending/` entries → validate each independently
→ emit → move ONLY successfully-emitted files into `read/`. Quarantine into `failed/` only a
file **proven structurally invalid** against the wire contract (collision-safe via the house
bump idiom). A global-dependency failure (unusable `jq`) leaves EVERYTHING pending — preflight
once, before touching any message. Digest records are JSON objects carrying
`from,to,ts,content` plus the message `id` (must-survive #8). If entries remain after the
batch bound, the emitted context explicitly instructs continuation (absolute engine path +
`dm take`; the prose may honestly drop the word "claim").

**The 8-item Must-survive list is a checklist — verify each against your diff before
reporting.**

## Fences — hard limits

- Do NOT create, edit, or delete `test/*` — any test change is an automatic rejection.
- Do NOT touch `templates/`, `docs/`, `.context/`, `ROADMAP.md`, `CHANGELOG.md`,
  `AGENT_BRAIN_DM_GSD_PLAN.md` — doc reconciliation is the orchestrator's, sequenced after
  this dispatch.
- Do NOT commit. Leave all changes uncommitted in the working tree; the orchestrator runs the
  gates and commits.

## Quality bar (constraints the frozen tests cannot teach you)

1. `bin/brain` is ONE POSIX-`sh` file — no bashisms; the shebang stays `#!/usr/bin/env sh`;
   your diff must pass `sh -n` AND `dash -n`.
2. Reuse the house collision idiom (`_dm_failed_dest`'s bump pattern) for occupied `read/` and
   `failed/` destinations — do not invent a second collision mechanism.
3. Per-message isolation means the batch loop may never early-return on one file's failure —
   a malformed entry is handled and the loop continues.
4. The absolute-engine-path resolution (via `git rev-parse --git-common-dir`) and the
   emit-before-move ordering are load-bearing v1.1 survivors — preserve them through the
   deletion; do not re-derive either.
5. Net line count should go DOWN by roughly the deleted machinery's size. If your diff grows
   the engine, something went wrong — stop and say so.

## Test-proof boundary

Retain the cheapest requirement-backed regression test for each named fault. Temporary
mutants are validation evidence, not deliverables.

Do not request or implement new shared test state, cross-process coordination, persistent
fixtures, classifiers, normalizers, differential oracles, or general-purpose harness
machinery without an explicit dispatcher decision. If a previously settled design crosses
one of those boundaries during implementation, "settled" does not suppress the
proportionality challenge: stop and return the measured cost and the isolation/deletion
alternatives.

A review finding in test infrastructure does not authorize repairing that infrastructure.
First ask whether the helper should be deleted, narrowed, or replaced by isolated resources.

## Gate bar and your sandbox

Your sandbox has previously rejected `mktemp` and blocked these suites (exit 2). Attempt one
run of `./test/dm.sh`; if the sandbox blocks it, do NOT chase it — verify with `sh -n`,
`dash -n`, and close reading instead, and say plainly in your report that the suite did not
run for you. The orchestrator re-runs everything on return: `./test/dm.sh` must be 54/54,
`./test/commit-install.sh` 15/15, both under `sh` and real `dash`, `shellcheck` at or below
the 11-finding baseline.

## Report

1. Functions and constants deleted (names), net line delta.
2. The consume-path shape as implemented (batch bound value/source, validation order,
   quarantine trigger, continuation emission).
3. The 8 must-survive items → where each lives in your diff.
4. Any frozen test you believe is wrong — SAY IT, do not touch it.
5. Anything you could not verify in-sandbox.
