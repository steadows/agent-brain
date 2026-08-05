# Fix brief — final ultrareview findings (6 HIGH + the deploy model)

Execute this fully using your **steadows-tdd** skill: RED → GREEN → REFACTOR. You own the
whole loop — write the failing tests first, make them pass, then refactor. Findings come
from `docs/reviews/lane-dm-v11-final-ultrareview-findings.md` (**read it first** — it
carries the evidence, file:line, and a fix sketch for each).

Repo: `~/agent-brain`, branch `fix/pretool-collision-warning`. Engine: `bin/brain`,
**POSIX sh — must run on `/bin/sh` AND `dash`. No bashisms.**

## Required reads

1. `docs/reviews/lane-dm-v11-final-ultrareview-findings.md` — this round's findings.
2. `.context/seams/dm-v1.1-queue.md` — **the design authority.**
3. `docs/reviews/lane-dm-v11-pre-pr-code-review.md` — last round (context: what H1–H5 were).
4. `AGENT_BRAIN_DM_GSD_PLAN.md` Phase 5 — the deploy runbook you are about to change.

## Hard rules

- **The 53 + 15 existing scenarios are FROZEN.** Append only. Never edit, weaken, reorder,
  or delete one. Final counts must be 53+N and 15+M with zero failures, and every
  previously-passing scenario still passing.
- **Do not touch the deliberate shapes**: both `cmd_commit` purges; the temp-index dance's
  four-way constraint; the bare wall-clock lease; the poison cap; at-least-once delivery;
  no fsync. `brain dm take` stays bounded and does NOT loop.
- **Never weaken a bound or delete a scenario to reach green.** The seam map decides.
- Every new test must be **falsifiable**: break your own fix, prove the scenario goes RED,
  and say so. Extend `test/mutation-probe.sh` with a mutant per fix below.
- `3.G/40` pins the nav skill's line budget — respect it when editing that template.

## Part 1 — the deploy model (do this FIRST; it changes what the other fixes are tested against)

**The problem, verified live:** `.brain/bin/brain` is a **tracked file**, so all 16 sibling
worktrees carry their own copy — every one currently v1.0.0. Phase 5 deploys only to the
main worktree. The SessionStart hook resolves correctly (the global dispatcher already uses
`git rev-parse --git-common-dir`), but the text it *emits* — and both protocol templates —
tell the agent to run the **relative** `.brain/bin/brain dm take`, which from a sibling
worktree resolves to that lane's stale v1.0.0 copy where `dm take` does not exist. There is
no global `brain` on PATH. Net effect: deploy "succeeds" and the feature silently does
nothing for every lane.

**Required fix:** every engine invocation a lane is instructed to run must resolve to the
ONE deployed engine at `<main-worktree>/.brain/bin/brain`, from any sibling worktree,
**without requiring lanes to rebase**.

- `_hook_session_start` already knows the absolute path (`$BRAIN/bin/brain`) — emit that,
  not a relative one.
- `templates/navigation-standards.SKILL.md` and `templates/DM-PROTOCOL.md` are static and
  cannot hardcode an absolute path. Give them a resolution the agent can actually run
  (the `--git-common-dir` → `dirname` idiom the dispatcher already uses), or direct the
  agent to the absolute path printed in its session context. Prefer **one canonical
  launcher** over repeating the idiom in three places.
- Update `AGENT_BRAIN_DM_GSD_PLAN.md` Phase 5 to match, and state explicitly why deploying
  to the main worktree alone is now sufficient.
- **Test it the way it actually fails:** a fixture with a main worktree plus a sibling
  worktree holding an OLDER engine copy; assert the instructions emitted to the sibling
  lane execute the NEW engine. A test that runs from the main worktree proves nothing.

## Part 2 — the six HIGH findings

Full evidence is in the report; summarised so you can plan the work:

1. **(covered by Part 1)** stale sibling engines.
2. **One poison file terminally discards its healthy batchmates** — `_dm_digest` rejects the
   whole batch, so nothing is acked; the valid files accrue the bad file's retry count and
   reach terminal `failed/` **without ever being emitted**. That is message *loss*, and it
   violates at-least-once. Fix: validate/route per file; emit and ack the valid ones; a
   poison file must never increment a peer's attempt counter.
3. **A post-claim crash can strand a message indefinitely** — an immediate restart preserves
   a fresh claim, but nothing ever watches for lease expiry (the lane watches `pending/`
   only), so recovery may never run again. Fix: sweep `claimed/` on a schedule, or arm on
   the earliest lease expiry. Add crash → immediate restart → idle past lease → delivered.
4. **Queue transitions can overwrite or eject messages** — recovery and `_dm_route_failed`
   `mv -f` to unchecked destinations; a pre-existing symlink-to-directory relocates a
   message out of the queue, a directory nests it, a regular file is clobbered. No race
   needed. Fix: reject occupied/non-regular destinations; collision-preserving names in
   `failed/` so forensic records are never destroyed.
5. **An overlong ID permanently blocks claiming** — `_dm_id_ok` bounds charset but not
   length, so a 252-byte ID makes a legal pending name and an over-`NAME_MAX` claim name;
   `mv` fails, the source remains, and an early-sorting entry blocks every later message on
   every take and boot. Fix: byte bound reserving the maximum claim suffix; route violations
   to `failed/`.
6. **The 40-message bound is bypassable** — the cap counts only successful pending claims,
   while stale recovery and invalid-routing are unbounded, recreating the boot-latency
   defect H5 closed. Fix: one total per-invocation transition budget across recovery,
   routing, and claiming, with fair resumable ordering.

## Part 3 — two small carries (in scope, stated deliberately)

- **`jq length` counts code points, not bytes** (report's Unicode finding). You are
  rewriting `_dm_digest` for #2 anyway, and leaving this means the caps we just fixed still
  do not hold for multibyte content — measure with `utf8bytelength` and add a multibyte
  boundary case. Doing this now is cheaper than a third round.
- **`test/mutation-probe.sh` can certify an incomplete suite** — `run_suite` ignores exit
  status and does not require the 53-scenario summary, so a suite that dies early reads as
  a clean baseline or an exact kill. This is the instrument the rest of the verification
  leans on; make it require a complete run and a zero baseline exit.

Everything else in the report (rollback windows, the commit-tree/index race, unborn-HEAD
CAS, sh/dash locale divergence in `_feat_ok`) is **deferred by decision — do not fix it**.

## Gates — run unpiped, all must pass before you report

```
./test/dm.sh                 # 53+N, exit 0
./test/commit-install.sh     # 15+M, exit 0
dash ./test/dm.sh            # same
dash ./test/commit-install.sh
sh -n bin/brain && dash -n bin/brain
sh test/mutation-probe.sh    # every mutant kills exactly what it declares
shellcheck bin/brain         # count with: grep -cE '^In .* line'  — must stay <= 11
```

Do not run `/steadows-code-review` or `/steadows-verify` — those are the orchestrator's.
Commit on this branch with conventional messages. Do not open a PR, do not merge, do not
touch `main`. If a fix proves impossible without violating a hard rule above, stop and say
so rather than working around it.
