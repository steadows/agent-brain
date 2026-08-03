# Adversarial review — Agent-Brain lane-to-lane DM

You are a senior adversarial code reviewer working **ALONE** — do NOT spawn sub-agents or fan
out; single-agent review is a hard requirement (the multi-agent fleet belongs to the post-PR
ultrareview gate, not this one). Your job is to find what a thorough first-pass review MISSED —
not to repeat what it already found. **Findings only — do not edit code.**

## What this is

`~/agent-brain` is a portable POSIX-`sh` coordination vault (`bin/brain`, ~950 lines) shared by
**13 concurrent Claude Code agent lanes** working in sibling git worktrees of one repo. It runs as
a **SessionStart** and **PreToolUse** hook for every one of those lanes. This diff adds
lane-to-lane direct messaging.

## Scope

```
git -C ~/agent-brain diff 26fb14b..HEAD    # commits 7d824ec, 77c67a0, and the review-fix commit
```

Read in full (post-diff state): `bin/brain`, `templates/DM-PROTOCOL.md`,
`templates/navigation-standards.SKILL.md`. Reference: `AGENT_BRAIN_DM_GSD_PLAN.md` (the reviewed
plan — its rulings are decisions, see "off-limits" below).

`test/dm.sh` is a **frozen** 24-scenario suite (survived a 4-round adversarial audit; 25 mutation
engines driven against it). It is context, not review target — but if you find a scenario that
would pass against a *wrong* implementation, that IS a finding worth reporting.

## The feature in one paragraph

`brain dm @<lane> "<msg>"` appends one jq-encoded JSON line (`from`/`to`/`ts`/`content`) to
`.brain/dm/<lane>/inbox.jsonl`; `brain dm @all` fans into every registered inbox but the sender's.
A receiving lane watches its inbox for live delivery. At **SessionStart** the hook rotates a
non-empty inbox to `dm/<lane>/read/<ts>-<pid>.jsonl`, injects the (bounded) contents into the
session's startup context, then arms on the now-empty file — so a DM to a lane that was *down*
arrives at its next boot, exactly once. The journal records a **call-log line only, never the
message body** (`journal/` is committed; the commit secret scan is line-anchored and cannot see a
mid-line body). `dm/` is gitignored.

## Already found by the first pass — do NOT re-report these

1. `cmd_init` writes `.gitignore` only on a fresh scaffold, so vaults created before this feature
   would commit inbox bodies. **Fixed:** `cmd_commit` now self-heals the `dm/` ignore line *and*
   un-stages anything already staged under `.brain/dm`.
2. `brain inbox '../../x'` created directories outside `.brain/` (no slug validation). **Fixed:**
   `_feat_ok` validates in `_inbox_path`.
3. `_dm_send` / `_inbox_ensure` write failures were unchecked — `cmd_dm` printed success and wrote
   a **false "delivered" line into the committed journal**. **Fixed:** failure propagates, `cmd_dm`
   dies, broadcast warns per-recipient and exits non-zero on partial delivery.
4. `_require_brain`'s short-circuit trusted an inherited `BRAIN` env var (a refactor regression),
   silently redirecting writes. **Fixed:** requires `ROOT` to be set too.
5. `_inbox_rotate` failure was invisible (stderr swallowed, return code ignored) and read as "no
   mail". **Fixed:** warns to `.hook-errors.log` and delivers in place (at-least-once).
6. Unbounded injection of inbox contents into startup context. **Fixed:** `_dm_digest` caps
   lines/columns; `DM_MAX_BODY` caps the body at send time.
7. Absolute machine path in the committed journal transcript pointer. **Fixed:** vault-relative.
8. A lane registered as `all` was unreachable (broadcast keyword wins). **Fixed:** reserved-slug
   guard in `cmd_new_feature`.
9. Docs co-change (README / BUILD-SPEC / CHANGELOG / ROADMAP / INDEX). **Fixed.**
10. Coverage gaps filed as follow-ups: no direct `cmd_announce` test, no test for the `@`-less
    argument form, no test for the hook's no-identity early-exit.

## Off-limits — these are ratified plan decisions, not defects

- **No lock on the send path** (`_lock_acquire` has no staleness break; one killed sender would
  wedge a lane's inbox permanently). Attacking the *premise* (e.g. the body cap that keeps appends
  sub-`PIPE_BUF`) is fair game; re-litigating the decision is not.
- Call-log-only journaling; `<ts>-<pid>` archive naming; `@all` deliberately not gated on apparent
  liveness (presence `updated:` is not a liveness signal); the documented sub-second rotate/send
  race that delays a message to the next boot rather than losing it.

## Your mandate

1. **SKIP** everything in the "already found" list — no duplicates.
2. Focus on blind spots automated reviewers miss:
   - Subtle logic errors that only fire on specific input combinations
   - **Cross-function interaction bugs** — e.g. the new `_require_brain` short-circuit changes
     behavior for *every* subcommand that composes another; `_announce_as` split the journal
     writer; `_feat_ok` now gates a path used by several callers. What breaks two functions away?
   - Security in "normal"-looking code: TOCTOU, trust boundaries, symlinks in `.brain/dm/`,
     the gitignore/un-stage guard itself (can it be defeated, or can it destroy real work — note
     `git rm --cached` on a path a user *intended* to track?)
   - **Concurrency:** 13 lanes, shared filesystem. Two lanes booting as the same feature; a send
     landing mid-rotation; two `brain commit`s; the `$$`-suffixed archive name under a PID reuse
     or a subshell (does `$$` mean what the code assumes inside `$( )`?).
   - Error cascades and silent failure paths that survived the fixes above
   - Backward/forward compatibility: an OLD `bin/brain` running against a NEW vault state, and
     vice versa (deploy is a `cp` into a live vault used by all 13 lanes, no staged rollout)
   - State-machine violations in rotate → deliver → arm
3. For each finding give: **File**, **Line**, **Category** (security | correctness | concurrency |
   compatibility | cascade-failure | state-machine), **Severity** (CRITICAL | HIGH | MEDIUM),
   **Finding**, **Evidence** (why it is real, not speculative — reproduce it if you can), **Fix**.
4. If the first pass was thorough and you find nothing material, **say so explicitly**. Do not
   invent findings to justify the dispatch.
