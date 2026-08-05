# Fix brief — lane-DM v1.1 pre-PR review findings (H1–H5 + doc drift)

Execute this fully using your **steadows-tdd** skill: RED → GREEN → REFACTOR. You own the
whole loop here — write the failing tests first, make them pass, then refactor. Findings
below come from the pre-PR review at `docs/reviews/lane-dm-v11-pre-pr-code-review.md`
(read it first — it carries the evidence for each item).

Repo: `~/agent-brain`, branch `fix/pretool-collision-warning`. Engine: `bin/brain`,
**POSIX sh — must run on `/bin/sh` AND `dash`. No bashisms.**

## Required reads before writing anything

1. `docs/reviews/lane-dm-v11-pre-pr-code-review.md` — the findings + evidence.
2. `.context/seams/dm-v1.1-queue.md` — **the design authority.** Layout, filename
   grammar, lifecycle, the 4-way UR-4a ruling, declared limitations.
3. `test/dm.sh` and `test/commit-install.sh` headers — their SAFETY discipline and
   declared-gaps lists.

## Hard rules

- **The 45 + 15 existing scenarios are FROZEN.** You may **append** new scenarios; you may
  **not** edit, weaken, reorder, or delete an existing one. At the end,
  `./test/dm.sh` must report **45 + N** and `./test/commit-install.sh` **15 + M**, with
  zero failures — and every originally-passing scenario still passing.
- **Do not touch these deliberate shapes** (each looks wrong and is proven load-bearing —
  the seam map explains why): both purge blocks in `cmd_commit`; the temp-index commit
  dance (read-tree HEAD → add .brain → purge dm → write-tree → commit-tree → update-ref →
  `git reset -q HEAD -- .brain`); the bare wall-clock lease with no PID check; the poison
  cap; at-least-once delivery; the absence of fsync.
- **Never weaken a bound to make a test pass.** If a test and the code disagree about a
  limit, the seam map decides.
- Every test you write must be **falsifiable**: before claiming GREEN, break the fix you
  just wrote and prove the new scenario goes RED. State that you did this.

## The fixes

### H1 — `set -- $claims` word-splits paths (`bin/brain:522`, `:1167`) — CRITICAL PATH
`_dm_claim_all` prints absolute paths; both consumers split them unquoted. Any vault whose
path contains a **space** shreds every path, `_dm_dir_ok` fail-closes on the fragments, and
DM delivery silently stops working forever (messages poison out after 3 attempts).
Reproduced on dash and sh.
**Fix direction:** stop round-tripping paths through word-splitting — emit names rather
than full paths and rebuild them consumer-side, or read with `while IFS= read -r`. Whatever
you choose must keep the claim list ordering stable and must not reintroduce a glob hazard.
**Test:** a fixture vault at a path containing a space, driving a real send → boot →
delivery → ack cycle. This is the single most important new scenario in the batch.

### H2 — digest bounds are bypassable (`bin/brain:493-510`)
`_dm_digest` bounds *files*, not JSON values, and truncates only `.content` while passing
unknown fields through. Verified: one file holding 3 objects emits 3 records (the 40-file
cap doesn't bound records); a 200-byte `extra` field survives alongside truncated content.
There is a no-tampering producer path — `cmd_dm` takes `_from` from `cmd_whoami`, which
returns `$BRAIN_FEATURE` unvalidated, so a lane can inject an unbounded `.from`.
**Fix direction:** at the consumer boundary require exactly one object per file,
reconstruct only the four contract fields (`from`/`to`/`ts`/`content`), bound each, and
apply a final aggregate cap before emission. Keep the existing content-truncation semantics
that Q.D/31–32 pin.
**Test:** a planted multi-object file; a planted extra-field file; an oversized `.from`.

### H3 — malformed claim filename permanently wedges SessionStart (`bin/brain:417-428`)
`case ... in ''|*[!0-9]*)` **accepts leading zeros**, then the value goes straight into
arithmetic: `08` → `dash: Illegal number: 08` (rc 2) / `sh: value too great for base`
(rc 127). Arithmetic-expansion failure is fatal — the hook's `|| true` does **not** catch
it — so one such filename in `claimed/` kills SessionStart before any delivery, on every
boot, permanently. Separately, an over-range attempt wraps negative (`…807 + 1` → negative),
producing a `.a-…` pending name `_dm_claim_all` rejects forever.
**Fix direction:** require canonical bounded decimals before any arithmetic (no leading
zeros except `0`, bounded epoch width, attempt within the state-machine range); route
anything else to `failed/` (or refuse with a warn) **without evaluating it**. Apply the
same discipline everywhere a queue-derived string reaches `$(( ))`.
**Test:** plant `…a0.c08-123` and prove the boot survives and still delivers other
messages; plant an over-range attempt and prove it reaches a visible terminal state rather
than an unclaimable one.

### H4 — `_dm_ack` intercepts its own ENOENT soft path (`bin/brain:466-483`)
`_dm_dir_ok "$_ak_claim"` runs before the `mv`, so a claim already lease-recovered by
another session hits "refusing non-regular dm message" + rc 1 instead of the dedicated
"claim disappeared before ack" branch (warn, return 0) sitting right below it. Result:
`brain dm take` exits nonzero even though the digest emitted correctly. The seam map
designs this case as *warn, never die*.
**Fix direction:** attempt the `mv` first, or have `_dm_dir_ok` distinguish "absent" from
"exists but wrong type", so the existing soft-landing fires for the realistic case. Keep
the symlink refusal intact — Q.X/29 pins it.
**Test:** remove the claim file between claim and ack, assert `brain dm take` exits 0 with
the "disappeared before ack" warn.

### H5 — unbounded per-message forks at boot (`bin/brain:441-463`, `:485-489`)
Claims and acks the entire pending backlog, one `mv` fork each, with only the *display*
capped. A dormant lane's accumulated broadcasts are all paid synchronously at boot.
**Fix direction:** bound the claim batch — claim at most a defined maximum per invocation
and leave the remainder pending for the next touch. Add the cap as a named constant beside
the other `DM_*` values. Delivery must stay at-least-once and the leftover must remain
claimable next time (no starvation, no loss).
**Test:** plant a backlog larger than the cap; assert exactly cap-many claimed per
invocation, the remainder still pending, and full delivery across successive invocations.

### Doc fixes (no tests needed, but must be exact)
- `ROADMAP.md:155` — "24 scenarios" → the true count after your suite additions.
- `CHANGELOG.md` — the newest section is "Unreleased" while `bin/brain:11` is
  `VERSION="1.1.0"`. Reconcile: give it a `## v1.1.0` heading (dated 2026-08-04) so
  `brain version` matches the changelog.
- `AGENT_BRAIN_DM_GSD_PLAN.md` — the top Status line still says next = "7.4 → Phase 5
  deploy" though 7.4 ran and §7.5 says ALL 10 CLOSED; and the UR-1…UR-10 bullets under
  that line still carry `[ ]` markers. Flip the markers to `[x]` and correct the header to
  the real next step (Phase 5 deploy, after this fix round).
- If your fixes change documented behavior, co-change `templates/DM-PROTOCOL.md` and
  `templates/navigation-standards.SKILL.md` — but note 3.G/40 pins the skill's line budget.

## Quality bar (what the tests can't tell you)

- Prefer one shared validator over per-site checks — H3 recurs anywhere a queue string
  meets arithmetic; fix the class, not the instance.
- Warn messages must name the offending **file or lane** — the existing
  `_dm_claim_all`/`_dm_recover_stale` warns are the standard to match.
- Keep the engine's helper style: `_`-prefixed locals with a function-unique prefix, guard
  clauses over nesting, no subshell where parameter expansion works.
- Comments explain *why*, not *what*, and any non-obvious invariant you rely on gets one.

## Gates — all must pass, run unpiped, before you report

```
./test/dm.sh                 # 45+N, exit 0
./test/commit-install.sh     # 15+M, exit 0
dash ./test/dm.sh            # same
dash ./test/commit-install.sh
sh -n bin/brain && dash -n bin/brain
shellcheck bin/brain         # count with: grep -cE '^In .* line'  — must stay <= 11
```

Do not run `/steadows-code-review` or `/steadows-verify` — those gates are the
orchestrator's. Commit your work on this branch with conventional messages; do not open a
PR, do not merge, do not touch `main`.
