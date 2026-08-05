# Ultrareview — Agent-Brain lane-to-lane DM (gate 7.4, pulled ahead of deploy)

Execute this fully using your **steadows-ultrareview** skill — the multi-agent verified-review
fleet. **Review-only: report findings, do not edit code.** Emit the complete final report as your
answer (your dispatch is read-only; the orchestrator captures and commits the report).

## Fleet sizing

**Small fleet, but sized for the surface, not the line count.** The diff is ~2,300 lines (most of
it a test suite and docs; the engine delta is a few hundred lines of POSIX `sh`), but it lands in
a **shared coordination vault executed continuously by 13 concurrent agent lanes** via
SessionStart/PreToolUse hooks, and it touches a **secret-egress path** (the journal is committed
to git; DM bodies must never reach it). Suggested: 5–8 reviewers with distinct lenses —
concurrency, security/trust-boundaries, shell correctness (POSIX sh, not bash), compatibility/
deploy, test-suite adequacy.

## What this is

`~/agent-brain` is a portable POSIX-`sh` coordination vault (`bin/brain`) shared by 13 concurrent
Claude Code agent lanes in sibling git worktrees of one repo. This branch adds lane-to-lane
direct messaging: `brain dm @<lane> "<msg>"` appends a jq-encoded JSON line
(`from`/`to`/`ts`/`content`) to `.brain/dm/<lane>/inbox.jsonl`; `@all` fans out to every
registered inbox but the sender's. At SessionStart the hook rotates a non-empty inbox to
`dm/<lane>/read/<ts>-<pid>.jsonl`, injects a bounded digest into startup context, then arms the
empty file — a DM to a down lane arrives at its next boot, exactly once. The journal records a
call-log line only, never the body; `dm/` is gitignored.

## Scope

```
git -C ~/agent-brain diff main...HEAD     # branch fix/pretool-collision-warning
```

The whole branch merges together, so the whole branch is in scope — weighted toward the DM
commits (`26fb14b..191b921`). Read post-diff state in full: `bin/brain`,
`templates/DM-PROTOCOL.md`, `templates/navigation-standards.SKILL.md`, `test/dm.sh`.
Reference (context, not target): `AGENT_BRAIN_DM_GSD_PLAN.md`.

`test/dm.sh` is a FROZEN 24-scenario suite (4-round adversarial audit, mutation-tested). It IS in
scope as a review target in one specific sense: a scenario that would pass against a wrong
implementation is a finding.

## Prior review context — do NOT re-report

Three gates already ran on this diff: `/simplify` (4 agents), `/steadows-code-review` (5 Claude
agents, findings fixed in `1bd9c81`), and a single-agent Codex adversarial sweep — **11 findings,
report at `docs/lane-dm-adversarial-review-findings.md`. Read it first.** Findings 2/3/4/5/7/10
are fixed (`d5879f5`), 8/9 became plan corrections, and **1/6/11 are ACCEPTED as documented v1
limits by the owner's ship ruling** (all three indict the shared-JSONL-inbox design under
split-second concurrency; the v1.1 per-message-file queue in `ROADMAP.md` is the fix). Do not
re-litigate accepted limits or ratified plan decisions (call-log-only journaling; `<ts>-<pid>`
archive naming; no liveness gating on `@all`; no lock on the send path). Attacking the *premises*
those decisions rest on (e.g. the body cap that keeps appends sub-`PIPE_BUF`) is fair game.

## What the fleet is for

The prior gates were function-scoped. You are the last review before this deploys machine-wide to
all 13 lanes with no staged rollout. Hunt what single-agent and checklist passes miss:

- Whole-system interactions: hook ↔ engine ↔ vault git state ↔ 13 concurrent executors
- Deploy-transition hazards: an OLD engine running against a NEW vault state and vice versa
  (the deploy is an atomic same-dir rename, but lanes mid-session straddle it)
- The gitignore/un-track guard in `cmd_commit` — can it be defeated, and can it destroy work?
- Trust boundaries: symlinks, path traversal residue, TOCTOU residue beyond what the findings
  report already documents as accepted
- Suite adequacy: a frozen scenario that proves less than its comment claims
- Anything that turns "delayed to next boot" (acceptable) into "silently lost" (not)

## Reporting

Per finding: **File · Line · Category · Severity (CRITICAL/HIGH/MEDIUM) · Finding · Evidence ·
Fix.** Reproduce where possible — your sandbox may block `./test/dm.sh` or writes; if a
verification step can't run, SAY SO explicitly rather than reporting it green. If the prior
gates held and you find nothing material, say that explicitly — do not invent findings to
justify the fleet.
