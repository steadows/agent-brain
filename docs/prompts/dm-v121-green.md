# GREEN dispatch — DM v1.2.1: the pre-PR review fix round

**Repo:** `/Users/amap3i/agent-brain` · branch `fix/pretool-collision-warning` @ `40aa6fe`
**Mode: GREEN-ONLY.** The RED suite is frozen at `test/dm.sh` — **66 scenarios, 55 passing / 11
failing**. The 11 failures are your work list. `test/commit-install.sh` (15/15) must stay green.

## Required reads, in order

1. `.context/seams/dm-v1.1-queue.md` — **the `# v1.2.1` section at the end is the DESIGN
   AUTHORITY** (six rulings + clarification 1a), amending the `# v1.2` section above it. Read both.
   Note especially **ruling 1a**: the batch cap bounds *entries EXAMINED*, not lines emitted — an
   implementation that increments the counter only on successful digest is **out of contract**.
2. `docs/reviews/lane-dm-v12-pre-pr-code-review.md` — the 5 HIGH / 9 MEDIUM findings these fixes
   close, including two orchestrator-reproduced transcripts.
3. `test/dm.sh` — the frozen contract. The failing scenarios are `V.Q/55`–`V.Q/66` (minus `V.Q/64`,
   a guard). **Read each scenario's comment block** — they carry the ruling each one pins and, for
   several, an explicit note on what is deliberately NOT asserted.
4. `bin/brain` — the engine you are editing.

## The work — 11 RED scenarios

Each maps to a ruling. Implement against the scenario, not against this summary:

| Scenario | What must become true |
|---|---|
| `V.Q/55` | A non-regular `pending/` entry (symlink, dir, FIFO…) is **quarantined into `failed/` as a directory entry, never dereferenced** — not retried forever. This is ruling 1; it closes a measured permanent starvation. |
| `V.Q/56` / `V.Q/57` / `V.Q/66` | Ruling 2: `_dm_jq_preflight` **probes** every jq contract the consume path relies on — the parse-error exit code AND the `error()` exit code. No hard-coded `5`. A jq whose behaviour cannot be established fails safe to **everything stays pending** (never quarantine). |
| `V.Q/58` / `V.Q/59` | Ruling 3, **both halves**: digit-only grammar enforcement in `_dm_id_ok`, AND no delimiter round-trip — collected filenames cross every boundary as quoted positional parameters, never a space-joined string re-split by unquoted `set --`. |
| `V.Q/60` / `V.Q/61` | Ruling 4: identity is derived, never inherited. Clear/ignore inherited `_DM_ID_TS`; require the clock helper to actually succeed (a masked failure must not yield an id); validate the id against the grammar **before** composing any path; assert the destination's literal parent is `pending/`. |
| `V.Q/62` | Ruling 6: a **taken bump** emits a `brain: `-prefixed diagnostic. |
| `V.Q/63` | Ruling 6: `dm take` warns when entries remain past the batch cap — **operator visibility only**. Do NOT add the SessionStart continuation contract here; ruling 6 scopes it away. |
| `V.Q/65` | The jq preflight must not run on an empty queue — gate it behind a fork-free emptiness probe in **both** consume paths. v1.1 paid zero DM forks on an empty boot; restore that. |

## ⚠ Two requirements NO test enforces — implement them anyway

The suite declares these as gaps ([Q1], [Q5]) because they are not drivable through the CLI. They
are still contract. A diff that omits them is incomplete even though it goes green:

1. **`_dm_id_in_use` must match the id AND any bumped variant** (ruling 5, first bullet) — change
   the exact-match scan to a `<id>*` glob per state. Rationale it is safe unproven: this is a
   **strict widening** of a safety check — it can report "in use" more often, never less, so it
   cannot introduce a new failure mode. (Reaching the fault needs same-second PID reuse, which is
   not deterministically drivable — see gap [Q1].)
2. **`_dm_collision_dest`'s internal failure returns must emit a `brain: ` diagnostic** (ruling 6's
   bump-CONSTRUCTION-failure half). Its two `|| return 1` paths (`_now_epoch`, `cksum`) are
   currently silent. Measured during the audit: an engine that adds only the bump-taken warn passes
   the entire suite — see gap [Q5]. Both halves of ruling 6 ship.

## Fences — hard limits

- Do NOT create, edit, or delete anything under `test/` — a diff touching `test/` is an automatic
  rejection. If a frozen test looks wrong, **say so in your report**; do not change it.
- Do NOT touch `templates/`, `docs/`, `.context/`, `ROADMAP.md`, `CHANGELOG.md`,
  `AGENT_BRAIN_DM_GSD_PLAN.md` — doc reconciliation is the orchestrator's and is already done.
- Do NOT commit. Leave changes uncommitted; the orchestrator runs gates and commits.

## Quality bar (constraints the frozen tests cannot teach you)

1. `bin/brain` is ONE POSIX-`sh` file — no bashisms, shebang stays `#!/usr/bin/env sh`, and your
   diff must pass `sh -n` AND `dash -n`. The v1.2 round shipped a bug that only appeared under real
   dash (fd allocation differs); assume the same class of hazard here.
2. **Fail-safe direction is asymmetric and load-bearing:** when a dependency's behaviour cannot be
   established, leave messages *pending* — never quarantine. Quarantine always requires proof. The
   two proofs are (a) not a regular file, (b) content failing the wire contract under a mechanism
   whose verdict does not depend on the jq build.
3. Reuse the existing house idioms — `_dm_collision_dest` for any occupied destination, `_warn` for
   every diagnostic (the `brain: ` prefix is what the suite counts), the existing `_dm_dir_ok`
   re-walks (they are the deliberate TOCTOU mitigation — do not "optimize" them away).
4. Emit-before-move is the invariant the whole feature exists to protect: nothing leaves `pending/`
   until it has been emitted, on every path including partial-batch failure.
5. Net complexity should stay flat or fall. If a fix makes you add state, a counter, or a retry
   budget — stop and say so in your report; ruling "Not adopted" explicitly rejects all three.

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

Your sandbox has previously rejected `mktemp` and blocked these suites (exit 2). Attempt one run of
`./test/dm.sh`; if it is blocked, do NOT chase it — verify with `sh -n`, `dash -n` and close reading,
and say plainly in your report that the suite did not run for you. The orchestrator re-runs
everything: `./test/dm.sh` must be **66/66**, `./test/commit-install.sh` 15/15, both under `sh` and
real `dash`, `shellcheck` at or below the 11-finding baseline.

## Report

1. Per-scenario: which change makes each of the 11 pass.
2. The two untested requirements above — where each landed in your diff.
3. Net line delta, and any place you had to add state (with justification).
4. Any frozen test you believe is wrong — say it, don't touch it.
5. Anything you could not verify in-sandbox.
