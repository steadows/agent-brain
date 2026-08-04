# Adversarial second-opinion review — lane-DM v1.1 branch (pre-PR gate)

You are a senior adversarial code reviewer working ALONE — do NOT spawn sub-agents or fan
out; a single-agent review is a hard requirement (the multi-agent fleet belongs to the
post-PR ultrareview gate, not this one). Your job is to find issues that a thorough
first-pass review MISSED — not to repeat what was already found. Findings only — do not
edit code.

## Scope

Branch `fix/pretool-collision-warning` vs `main` in this repo (`git diff main...HEAD`).
Post-diff files worth reading in full: `bin/brain` (POSIX sh engine — must run on /bin/sh
AND dash), `.context/seams/dm-v1.1-queue.md` (the design authority),
`templates/DM-PROTOCOL.md`, `templates/navigation-standards.SKILL.md`. The two test
suites `test/dm.sh` (45 scenarios) and `test/commit-install.sh` (15) are FROZEN RED
suites — read them for context; never propose editing them.

## Deliberate shapes — NOT findings (ruled in prior reviews; see the seam map)

- Both purge blocks in `cmd_commit` are live code; the temp-index commit dance is a
  verified 4-way constraint.
- The claim lease is a bare wall-clock stamp in the claim filename, no PID/liveness check.
- Poison cap `DM_MAX_ATTEMPTS=3` → terminal `failed/`; delivery is at-least-once BY
  DESIGN (duplicates possible, loss not); no fsync — power-loss durability not claimed.
- The symlink-check TOCTOU residual is documented as unclosable in POSIX sh.
- The legacy-vault secret-scan wedge is a recorded ROADMAP known issue (pre-existing).
- 10 ultrareview findings already closed — see `docs/lane-dm-ultrareview-findings.md`.

## What the first-pass review already caught (SKIP these — no duplicates)

HIGH:
1. `set -- $claims` at `bin/brain:522` and `:1167` word-splits full claimed paths — a
   repo path containing a space breaks all DM delivery (confirmed, score 100).
2. `_dm_ack` (`bin/brain:466-483`) runs `_dm_dir_ok "$_ak_claim"` BEFORE the mv, so a
   claim recovered by another session hits "refusing non-regular dm message" + rc 1
   instead of the designed ENOENT soft-landing (warn, return 0).
3. `_dm_claim_all` claims an unbounded backlog with one `mv` fork per message at
   SessionStart (display is capped at 40, claims are not).

MEDIUM:
4. Poison routing to `failed/` journals/announces nothing; the status banner is gated on
   the owning lane's identity — invisible to fleet-health checks.
5. `_dm_recover_stale` aborts (incl. lease recovery) if `_dm_purge_stale_temps` fails;
   the warn doesn't name that coupling; hook call site is `|| true`.
6. Plan task 5.6 rollback drain isn't executable cross-lane (`dm take` has no lane arg;
   `BRAIN_FEATURE` override undocumented in the runbook).
7. ROADMAP.md:155 stale "24 scenarios"; VERSION="1.1.0" has no CHANGELOG heading; GSD
   plan header + UR checkbox markers contradict its own "ALL 10 CLOSED".
8. Zero test coverage: `brain hook pre-tool` path (incl. `_emit_pretool` ask/allow),
   `cmd_new_feature` reserved-name guard, direct `brain announce`, whoami-empty hook exit.

LOW (downgraded but known): one corrupt message blocks the whole batch digest with a
generic warn; `_relpath_any` adds a git fork per Edit/Write hook; `brain inbox` rejects
`@feature` and creates queues for unregistered lanes; `find -mmin` is a new undeclared
dependency; README table omits `dm take`; `cmd_commit` is 122 lines; the claim-side
`_dm_id_ok` tightening and missing-`read/` ack behavior are unpinned by the frozen suite.

## Your mandate

1. SKIP anything already covered above.
2. Focus on blind-spot categories:
   - Subtle logic errors that only manifest under specific input combinations
     (name-parsing edge cases in `_dm_recover_stale`/`_dm_claim_all`/`_dm_ack`,
     lease/epoch math, the `.a`/`.c` filename grammar under adversarial names)
   - Cross-file interaction bugs (engine vs templates vs deploy runbook vs hooks)
   - Security in "normal" code (trust boundaries: DM bodies rendered into another
     agent's context, frontmatter values, collision strings flowing into jq/awk/git)
   - Concurrency hazards BEYOND the accepted rename-arbitration design (two sessions of
     one lane, sender racing consumer, recover racing ack/claim, `brain commit` racing
     the queue)
   - Error handling gaps where failures cascade silently (fail-open hook paths)
   - Backward compatibility (existing subcommand contracts, hook JSON, exit codes)
   - State-machine violations in pending→claimed→read/failed (invalid transitions,
     stuck states, attempt-counter integrity across recover cycles)
3. For each finding: **File**, **Line**, **Category** (security | correctness |
   concurrency | compatibility | cascade-failure | state-machine), **Severity**
   (CRITICAL | HIGH | MEDIUM), **Finding** (what was missed and why it matters),
   **Evidence** (why this is real, not speculative — reproduce cheaply where possible),
   **Fix** (concrete recommendation).
4. If the first-pass review was thorough and you can't find material issues, say so
   explicitly. Do not invent findings to justify your existence.
