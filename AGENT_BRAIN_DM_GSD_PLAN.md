# Agent-Brain Lane DM — GSD Plan

**Status:** `[~]` P0–P4 ✅ DONE 2026-08-03 — suite frozen (4-round audit), then GREEN landed:
**24/24 scenarios pass** (engine + hook + protocol + presence). **Next is Phase 5 deploy — STOP:
machine-wide and instant for all 13 lanes; needs Steve's go**
**Owner:** @pm · **Repo:** `~/agent-brain` (branch `fix/pretool-collision-warning`) → deployed to `<main-worktree>/.brain/`
**Evidence:** `docs/research/agent-lane-dm-mechanisms-eval.md` (E0–E15) in `enterprise_research_dashboard-pm`
**Predecessor:** `~/agent-brain/docs/AGENT-DM-CHANNELS.md` (2026-06-15, superseded in part)

---

## Context

Lanes coordinate **pull-only** — each reads `.brain/` at session start. Fine for state, useless for a
timely signal. The live vault has **25 `waiting-on` edges and exactly 1 `clash`**: lanes aren't
fighting over files, they're waiting on each other.

**What this actually buys (corrected 2026-08-03, Steve).** The headline case is *not* reaching a lane
that is asleep. In practice Steve drives the blocking and blocked lanes **simultaneously** — an
unblock signal rarely needs to survive dormancy, because the recipient is already running. What waits
is **Steve, relaying by hand**. This removes the human from the relay loop between two lanes that are
both already awake.

The dormant case is real but secondary: a **broadcast** ("merging X, re-sync before your gates",
task 1.6) genuinely goes out to a crew that is mostly shut down. That is why task 2.1 exists — it
makes a message to a sleeping lane *arrive late* rather than *vanish*. Point-to-point urgency is the
headline; broadcast durability is the tail, and both are covered.

The evidence supports that framing better than the one this plan originally used: **E15 measured an
*idle* lane — a running session with no human attached — waking and acting on an inbox message in
~12s.** Idle is not offline; idle is exactly the state Steve's lanes sit in between prompts.

### Three tiers — say the division of labour out loud

Each has a different job. Nothing here replaces the other two.

| Tier | Mechanism | Reaches | Job |
|---|---|---|---|
| **Fast** | `brain dm` → inbox, watched live | a **running** lane, in seconds | the nudge |
| **Everyone-eventually** | `brain announce` → journal | every lane, at its next boot | the broadcast |
| **Permanent** | `connections/` note (task 3.3) | anyone reading the vault, forever | the **record** |

The DM is a signal, never the record — a decision that exists only in an inbox did not happen.
`connections/` notes are already used this way (`research-pm-dt659-gold-set.md` is a real multi-turn
thread), so this is existing practice, not an invention.

**Read/unread makes the fast tier survive dormancy** (task 2.1). The watcher attaches at end-of-file,
so anything already in the inbox when a lane boots is invisible to it — a message to a sleeping lane
would be *lost*, not queued. Rotating the inbox at session start turns that into "read the moment it
wakes up." Without it, this feature works only lane-to-live-lane.

⚠ Even so, for "main moved" **git is the real source of truth** — every lane rebases onto `origin/main`
at start and discovers it whether or not a message lands. The broadcast is a courtesy that saves a
lane from finding out mid-gate. Do not build correctness machinery on top of it.

This adds a DM path so those signals land in seconds, plus a **dialog mode** for two lanes to hold a
real technical conversation to convergence — as domain experts and critical consultants, not
agreeable peers.

Every mechanism is already verified end-to-end on this machine. Load-bearing results: **E15** above;
and a lane **verifies a claim against presence notes before acting**, refuses bare orders, and refuses
hostile escalation (E14, n=3). This is a build, not a spike.

**Governance:** engine + hooks are **machinery** (human-applied in v1); note formats and the nav skill
are **conventions** (self-evolving). This touches both — Steve's approval is the human application.

---

## Dependency graph

```
P0 review + seams + frozen RED ──▶ P1 transport ──▶ P2 hook ──┐
                                                              ├──▶ P5 deploy ──▶ P6 e2e ──▶ P7 review+ship
                               P3 protocol ───────────────────┤
                               P4 presence ───────────────────┘

P3 / P4 are CONCURRENT with P1+P2 (docs vs engine — no shared files).
P5 requires ALL of P1–P4. P6 requires P5. P7 requires P6.

⚠ P0 is a HARD gate on everything: the RED suite must exist and FAIL before P1 starts.
Every phase gate runs the scoped verify (see Gates & workflow).
```

## Where this is built, tested, and deployed (two repos — do not conflate them)

| | Repo / path | Role |
|---|---|---|
| **Source** | `~/agent-brain` (branch off `fix/pretool-collision-warning`) | where the engine + templates are edited and committed |
| **Test bed** | throwaway git repos under the session scratchpad, each with its own `.brain/` | where P1/P2 gates run — **never the live vault** |
| **Production** | ARDOS repo `<main-worktree>/.brain/` | deployed engine + the real 13-lane vault |

**P1–P4 never touch the ARDOS repo.** Code is written and committed in `~/agent-brain`; gates 1.G and
2.G run against disposable scratch repos, exactly the method that produced E1–E15.

**Test in scratch repos, not the live vault — this is not fastidiousness.** `dm @all` (1.6) fans a
line into *every* registered inbox, and 2.1 injects a lane's inbox into its startup context. Exercising
either against the real vault sprays test strings into 13 real lanes' next boot. The secret-scan probe
in gate 1.G is worse — it deliberately writes `AWS_SECRET_ACCESS_KEY=abc123` and then greps for it;
that string must never enter a vault @pm commits and pushes.

**P5 is the first contact with production, and it is all-at-once** (see the Phase 5 warning). **P6
verifies with scratch lanes** but checks the *real* main worktree for git pollution (gate 6.6) —
because by then the deployed engine is live for everyone.

**Branch/PR note:** the base branch `fix/pretool-collision-warning` is unmerged and needs Steve's PR
click on `github.com/steadows/agent-brain` — the `gh` CLI here is authenticated as the work EMU
account and cannot open a PR on the personal repo. Stack the DM work on it regardless; it carries the
hook fix this depends on.

---

## Done when

`brain dm @<lane>` reaches a **running** lane in seconds and a **dormant** lane at its next boot,
exactly once; `brain dm @all` reaches the whole crew; no message body ever enters a commit; and two
real lanes hold a technical dialog in which the responder finds a **planted flaw** and, on a sound
proposal, declines to invent one. Anything short of all five is not done.

## Gates & workflow

The standing pipeline (`~/.claude/rules/common/development-workflow.md`), applied to this build.
**Two deliberate deviations, both justified below** — read them before assuming a gate was forgotten.

| Order | Gate | Where |
|---|---|---|
| 1 | Plan review | P0.1–0.2 ✅ |
| 2 | Seams — scoped reuse pass | **P0.3** |
| 3 | **RED written + frozen by `test-writer` → audited by `spec-watchdog`** | **P0.4–0.5** |
| 4 | GREEN against frozen tests | P1–P4 |
| 5 | Scoped verify — **every phase gate** | 1.G / 2.G / 3.G / 4.G / 6.x |
| 6 | `/simplify` | **P7.1** |
| 7 | `/steadows-code-review` (orchestrator-side) | **P7.2** |
| 8 | PR — **Steve clicks** | **P7.3** |
| 9 | `/steadows-ultrareview` → Codex, small fleet | **P7.4** |

**The orchestrator never hand-writes a test** — unconditional, and now mechanically enforced by the
`enforce-tdd-pair.py` PreToolUse hook, which denies orchestrator writes to test files. `test/dm.sh`
(P0.4) is authored by **`test-writer`**, audited by a separate **`spec-watchdog`** pass, and frozen
before any engine line is written. If some instruction appears to forbid dispatching the pair, raise
that instruction — do not drop the rule.

### Deviation 1 — the phase gates ARE the test suite, and they are executable

There is no test suite in this repo. `ROADMAP.md:76-78` already asks for one, built exactly the way
E1–E15 were run: *temp-repo init → scenarios → assert*. This plan's gates are prose descriptions of
those scenarios, so **P0.4 captures them as `test/dm.sh` instead of inventing a parallel harness.**
That is the ROADMAP's own ask scoped to this feature, not new scope — and it turns every gate below
from "I checked" into "the script exited 0."

### Deviation 2 — scoped verify, NOT `/steadows-verify`

`/steadows-verify` covers build · types · lint · tests · security · infra · observability · supply
chain · deploy readiness. In a POSIX-shell repo with no build, no type system, and no package
manifest, **most of those stages have nothing to evaluate and would report PASS regardless** — which
is precisely the DT-924 failure @observatory just found in this org's own pipeline (a layer gate that
had been passing vacuously for months because it was never configured). Reproducing that here would
manufacture evidence of compliance nobody checked.

**The scoped verify — four checks that can actually fail, run at every phase gate:**

1. `sh -n bin/brain` — syntax
2. `shellcheck bin/brain` — lint (installed at `/opt/homebrew/bin/shellcheck`)
3. `test/dm.sh` — the frozen suite, exit 0
4. **secret-leak probe** — send a DM containing `AWS_SECRET_ACCESS_KEY=abc123`, then
   `grep -r 'abc123' <vault>/journal/` returns nothing

⚠ This substitution is a **deliberate, reasoned choice, not an oversight.** Do not "restore"
`/steadows-verify` here without first making its stages non-vacuous for a shell repo.

## Pre-existing state (read before starting)

- `[!]` ~37 lines of this feature are **already written and uncommitted** in `~/agent-brain/bin/brain`
  (`_inbox_path`, `cmd_inbox`, `cmd_dm`, ~L181–215) — **written BEFORE this plan and before review.**
  **Treat as a draft, not a head start:** validate line-by-line against the *final reviewed* plan and
  **rewrite or delete it if the review says so.** It has **never executed** — it is unregistered in
  the dispatch `case`, so `brain dm` prints `unknown subcommand` and the code is unreachable. The
  verified E1–E15 mechanisms were exercised through hand-built scratch fixtures, not this code.
- `[!]` **Engine copies have drifted.** Source has the DM code; deployed `<main>/.brain/bin/brain`
  does not. Only an explicit `cp` reconciles them.
- `[!]` **Base branch is unmerged.** The collision-warning fix lives on
  `fix/pretool-collision-warning`; an earlier `git reset --keep` removed it from `main`'s working
  tree. Stack on that branch. It needs Steve's PR click (the `gh` CLI is the work EMU account and
  can't open a PR on the personal repo).
- `[x]` `connections/` notes are **already used as threaded lane-to-lane conversations**
  (`research-pm-dt659-gold-set.md` is a 5-turn @pm ↔ @research exchange). The dialog convergence
  artifact is existing practice, not an invention.

---

## Phase 0 — Plan review · seams · frozen RED `[x]`

- `[x]` 0.1 Fable agent plan review in a fresh session — **READY WITH CHANGES** (1 critical, 3 high,
      5 medium, 3 low, 4 factual errors). Verified plan claims against `bin/brain` source + deployed,
      the live vault, `templates/`, `AUTONOMOUS_WORK.md`, and `src/utils/text.py`.
- `[x]` 0.2 **GATE:** findings addressed 2026-08-03 — C1 → task 1.2 (Steve's call: call-log line, no
      body); H1 → premise corrected in Context (the offline case is not a real case; the durable
      record is the `connections/` note) and task 1.3 cut; H2 → new task 5.3; H3 → gate 6.3 redesigned
      (planted flaw + negative control); M1 → 3.5 relabelled + the empty-contest tell routed to
      `cmd_status`; M2 + the whole of Phase 3b → **cut** (Steve's call); M3/M5 → Phase 3 preamble;
      M4 → task 1.4 (lock dropped); L1/L2/L3 → Risks, gate 6.6, and the line-number fix in 1.5.
      All 4 factual errors corrected.
- `[x]` 0.3 **Seams — scoped.** Normally skippable (single file, no new deps), but four genuine reuse
      decisions must be settled *before* anyone types, not extracted afterwards:
      **(a)** does `dm @all` (1.6) call the single-send path or duplicate the jq encoding + journal
      line? **(b)** where does the rotation logic live so `_hook_session_start` (2.1) and `cmd_inbox`
      share one implementation? **(c)** does `test/dm.sh` get a shared temp-repo fixture helper, given
      every scenario needs one? **(d)** where do the ERD-specific referents (§3.1, `.brain/research/`)
      live so the generic template stays project-agnostic (M3)?
      Four decisions, not a document. Record them here; `/simplify` (7.1) verifies the finished diff
      against them.
      **DECIDED 2026-08-03:**
      **(a) One send path, journaling at the command level.** Extract `_dm_send <to> <msg>` — jq
      encoding + the single `O_APPEND` write, nothing else. `cmd_dm` = validate → `_dm_send` → ONE
      call-log journal line; `@all` = loop `_dm_send` over `presence/*.md` (skip self) → ONE
      broadcast journal line. Journaling stays in the command, never the helper, so one invocation
      = one journal line — the fan-out must not produce 13.
      **(b) Rotation is one new helper; ensure-exists is reused, not duplicated.**
      `_inbox_rotate <feat>` does the `mv` → `dm/<feat>/read/<ts>-<pid>.jsonl` (no-op on
      empty/missing; the `-<pid>` suffix ratified under 2.1 makes same-second rotations
      collision-free) and prints the archived path. `_hook_session_start` composes: `_inbox_rotate` → inject
      contents → `cmd_inbox` to re-create the empty inbox (it already owns mkdir+touch+print).
      `_inbox_path` stays the single path authority.
      **(c) Yes — one `make_vault` fixture helper inside `test/dm.sh`.** Builds a throwaway git
      repo + `.brain/` + N presence notes under `mktemp -d`, echoes its path; identity via the
      existing env seams (`BRAIN_FEATURE`, `BRAIN_TEST_BRANCH`, `BRAIN_MAIN_REF`,
      `BRAIN_SKILLS_DIR`, `BRAIN_GLOBAL_SETTINGS`) — zero engine changes for testability. Single
      file for v1; extract `test/lib.sh` only when a second suite exists.
      **(d) The deployed vault template IS the project layer.** The generic
      `templates/navigation-standards.SKILL.md` in this repo gets a marked `## Project hooks`
      placeholder section only; the ERD referents (§3.1, `.brain/research/`) are added to the
      **deployed copy** `<main>/.brain/templates/navigation-standards.SKILL.md` — that copy is
      committed with the vault, and `brain install` cp's *from* it, so the project layer survives
      installs and is only clobbered by the forbidden `init --force` (5.4). Gate 3.G's grep runs
      against this repo's generic template. Deploy consequence folded into 5.3.
- `[x]` 0.4 **RED — `test/dm.sh`, authored by `test-writer`.** Captures every gate below as an
      executable temp-repo scenario, per `ROADMAP.md:76-78`. **The orchestrator does not write this
      file** — `enforce-tdd-pair.py` denies it at the tool layer, and the rule is unconditional
      regardless. Must fail against the current engine before any GREEN line is written.
      **Done 2026-08-03:** 24 scenarios (20 red + 4 guards), one `make_vault` fixture, all under
      `mktemp -d`; shellcheck clean.
- `[x]` 0.5 **`spec-watchdog` audit of the frozen suite** — separate pass, dispatched at the finished
      files with `Bash` so it can run them. Hunting the hollow suite: an assertion that would pass
      against the unmodified engine, a scenario narrower than the gate it claims to encode, the
      exactly-once check that never actually boots twice.
      **Done 2026-08-03 — FOUR rounds, not one.** The watchdog built an honest reference
      implementation (proving every scenario reachable), then drove 25 single-point mutations:
      round 1 found 6 CRITICALs (deliver-once-ever; truncated body leak; liveness-gated broadcast;
      archive destroyed by same-name mv; global lock; echo-to-sender), round 2 found the
      multi-message-queue hole (deliver-newest-only passed) + 3 MAJORs, round 3 found the
      sender-attribution hole (contents-only injection passed) + the suffix-distinctness
      overclaim, round 4 returned CLEAN. Two residuals ACCEPTED AND DECLARED in the suite's
      comments: a clock-derived archive suffix (plan ratifies `-<pid>`; enforced at review) and
      roster-gaming attribution (no plausible motivation; proximity tightening documented).

**Gate 0.G** `[x]` **CLOSED 2026-08-03** — 0.3 decisions recorded · `test/dm.sh` fails against the
current engine (verified independently by orchestrator AND watchdog: exit 1, 20 non-guard FAIL,
the 4 passes are exactly the 4 guards) · watchdog round 4 verdict CLEAN, no unaddressed finding

## Phase 1 — Transport `[x]` (machinery · `~/agent-brain/bin/brain`)

**Wire format (ratified 2026-08-03, watchdog finding m2):** one jq-encoded JSON object per inbox
line, keys exactly `from` / `to` / `ts` / `content` — matches the E1–E15 fixtures and the draft
encoder. The frozen suite pins these keys; changing them is a plan change, not an implementation
choice.

- `[x]` 1.1 Register `dm)` and `inbox)` in the dispatch `case` (~L799–816) **and** in `usage()`
      — the single reason the existing code is dead
- `[x]` 1.2 **Journal a call-log line, never the message body** (Steve's call, 2026-08-03).
      `cmd_announce` writes `- <ts> <feat> — <msg>`, so a verbatim body lands **mid-line**, where the
      commit secret scan's `^[A-Z][A-Z0-9_]*=.+` anchor (`bin/brain:447`) can never match — and
      `journal/` **is** committed. Write `dm → @<to> (transcript: <inbox path>)` instead: keeps the
      audit trail, and carries a **retrievable pointer** to the full text, which stays in the
      gitignored inbox. Steve's stated requirement: a lane or a human must be able to follow the line
      back to the real transcript. Secondary effect fixed for free — a verbatim body would be injected
      into **every** lane its text names via `_recent_journal` at SessionStart
      (`bin/brain:218-222`, `279-282`), not just the addressee.
- `[x]` 1.3 Add `dm/` to `cmd_init`'s `mkdir -p` (~L748) and to the `.gitignore` `printf` (~L759),
      in the existing *"Brain runtime artifacts — per-machine, transient"* section
- `[x]` 1.4 **Drop the `dm-<to>` lock.** `_lock_acquire` (`bin/brain:113–121`) has no staleness break,
      so a `brain dm` killed mid-critical-section wedges every later send to that lane permanently —
      and DM frequency will be far higher than commit's. One `printf` append of one jq-encoded line is
      a single `O_APPEND` write, atomic at these sizes; that is also what keeps the receiver's
      line-by-line `tail -F` framing intact.
- `[x]` 1.5 Fix the stale doc reference in the `_emit_pretool` comment (**~L584–586**, working-tree
      numbering) — points at a path that exists only in the `-pm` worktree
- `[x]` 1.6 **Broadcast: `brain dm @all "<msg>"`.** The protocol names *status broadcast* and *merge
      coordination* among its six shapes (3.1), but `cmd_dm` is strictly point-to-point — the plan
      described a shape the transport could not do (found by Steve, 2026-08-03).
      Fan the same line into **every** registered inbox (loop `presence/*.md`, skip self), plus one
      `cmd_announce` line. Live lanes get it in seconds; dormant lanes get it at next boot via 2.1's
      rotation. **Do not gate the fan-out on who looks "live"** — presence `updated:` is unreliable
      (see Risks). Writing to a dormant lane's inbox costs one line and is harmless.

**Gate 1.G** `[x]` **PASSED 2026-08-03** (suite 24/24; shellcheck at baseline parity — 13
pre-existing findings, none in new code) — **scoped verify** (syntax · shellcheck · `test/dm.sh` exit 0 · secret probe), with
these P1 scenarios now GREEN in the frozen suite: `brain inbox` prints+creates · `brain dm @graph "x"`
writes one valid JSON line to the inbox **and** one journal line containing the inbox path and **not**
the body · **a DM body containing `AWS_SECRET_ACCESS_KEY=abc123` leaves no trace of that string
anywhere under `journal/`** · `brain dm @all "x"` lands in **all 13** registered inboxes and **not** the
sender's · unknown recipient fails cleanly · self-send refused · `git status` in the main worktree
shows **no** `.brain/dm/`

## Phase 2 — Hook `[x]` (machinery · same file)

- `[x]` 2.1 **Rotate, deliver, then arm — in that order.** In `_hook_session_start`, before anything
      else: if `dm/<me>/inbox.jsonl` is non-empty, `mv` it to `dm/<me>/read/<ts>-<pid>.jsonl` and
      inject its contents into the session's startup context alongside the existing "run
      navigation-standards" block. Then arm the watcher on a now-empty inbox.
      **Archive name ratified 2026-08-03 (test-writer's open question):** `<ts>` alone is not
      collision-free — two rotations in the same clock second overwrite each other and the second
      `mv` silently destroys the first transcript. The `-<pid>` suffix makes uniqueness structural
      (each boot is its own process); the transcript pointer (1.2) is only honest if archives are
      durable.
      **Why this order is load-bearing:** the watcher attaches at end-of-file, so anything already in
      the inbox is invisible to it. Without the rotate step, a DM sent while the lane was down is
      **lost, not queued** — the lane boots, starts listening from that instant, and never sees what
      is sitting above it. This is the whole read/unread mechanic.
      **Why `mv` and not read-in-place:** delivery must be **exactly once**. Left in place, the same
      message is re-injected every session forever.
      **Why the hook and not an instruction:** "check your inbox at boot" is compliance an agent can
      skip; a hook is machinery that runs whether or not the agent is paying attention. Precedent for
      the failure mode: the collision warning that never fired, and the agent-frontmatter `hooks:`
      block that never fires.
- `[x]` 2.2 Extend the same injected block with the arm-your-inbox instruction carrying the concrete
      `cmd_inbox` path

**Gate 2.G** `[~]` **scriptable clauses PASSED 2026-08-03** (offline delivery, exactly-once,
collision-free archives — all green in the frozen suite). **The live-arming clause is deferred to
P6 by design** — "a cold lane arms the Monitor unprompted, mid-task delivery" needs a real Claude
session, which is exactly scenarios 6.1/6.2; it cannot be a `test/dm.sh` scenario. Full gate text:
**scoped verify**, plus: cold scratch lane arms the Monitor **unprompted** and a DM
from another process arrives mid-task · **offline delivery:** send to a lane that is **not running**,
then boot it — it reports the message as part of waking up, `inbox.jsonl` is empty, and the line is in
`read/<ts>.jsonl` · **exactly-once:** boot that same lane a second time and it does **not** re-report
the message

## Phase 3 — Protocol `[x]` (convention · `templates/navigation-standards.SKILL.md`) — CONCURRENT with P1/P2

**Done 2026-08-03:** always-read DM section in the skill (78 lines, ≤80 budget) + the on-demand
`templates/DM-PROTOCOL.md` carrying 3.1–3.8 in full + a `## Project hooks` placeholder in both
(seam d — ERD referents go in the DEPLOYED copies at 5.3, never here).

The engine is ~40 lines; the protocol is the product.

⚠ **Every lane reads this skill every session** (`bin/brain:612`), so its length is a per-session
context tax across all 13 lanes. The template is 64 lines today. Keep the always-read skill to the
triage rules (3.2) plus the arm-your-inbox instruction; push dialog and convergence detail into an
on-demand reference file the skill points at.

⚠ **Keep ERD-specific referents out of the generic template.** `bin/brain:774` declares the tool
project-agnostic, but 3.6/3.8 cite `docs/AUTONOMOUS_WORK.md` §3.1 and `.brain/research/`, which exist
only in this project. Put those in a project-hooks section or in the deployed skill copy.

- `[x]` 3.1 **The six shapes** (measured from the vault, not invented): status broadcast ·
      intake/handoff · heads-up/warning · unblock (`waiting-on`) · merge coordination · dialog
- `[x]` 3.2 **Rules of engagement — triage by cost, not authority:** read everything · **ack
      everything even when deferring** · do it now if small · **do it now if it invalidates your
      current work** (the "main moved" case) · else finish your task first · **write it down when you
      defer** (punch list / connection note — never held only in context, which dies at compaction)
- `[x]` 3.3 **Merge coordination needs a handshake** — the one shape where **silence means NO
      agreement**. An unacked "hold your merge until mine lands" is *not agreed*. DM = signal;
      the existing `waiting-on` connection note = record
- `[x]` 3.4 **Dialog mode** — `dialog_with:` set in your presence note while engaged, cleared after.
      Both ends opt in. **Push toward convergence; do not go forever** — converge / deadlock /
      escalate. Convergence *is* writing the shared conclusion to a `connections/` note
- `[x]` 3.5 **Anti-sycophancy.** Be honest about which of these is machinery and which is compliance:
      the **convergence artifact** and the **go-get-evidence step (3.7)** are structural; "cite
      evidence" and "critique first" are rules nothing enforces. Label them as such rather than
      claiming enforcement that doesn't exist. Lanes are technical experts in their own surface and
      *critical but helpful consultants*:
      - standing to say "that breaks X" about **your** surface — that's why you were asked
      - **cite evidence** (file, line, presence note, prior decision); an assertion with no referent
        doesn't count — the same rule E14 showed lanes already apply to inbound claims
      - the responding lane's **first turn must be a critique, not an endorsement**
      - the convergence note records **what was contested and the tradeoff accepted**; if nothing was
        contested, say so explicitly — and a note recording *nothing contested* **surfaces in
        `cmd_status`** for the PM sweep, so the tell is read by someone rather than confessed to no one
- `[x]` 3.6 **RESEARCH FIRST — never assert or ask cold.** A mid-dialog question with multiple
      defensible answers that depends on an external standard → **dispatch a research agent before
      taking a position** (`~/.claude/rules/common/research-before-asking.md`, applied lane-to-lane).
      Bring file paths / issue numbers / doc URLs, not opinions. Check `.brain/research/` first
      (83 notes — it may already be answered); drop a self-sufficient note when it isn't.
      *This is the other half of anti-sycophancy: two lanes trading unevidenced opinions converge on
      whoever is more confident.*
- `[x]` 3.7 **Deadlock protocol — go get evidence, then reconvene** (Steve, 2026-08-03). When two
      lanes are stuck, they **agree to go do research and/or thought partnership**, **share what they
      produce** (documents, reviews, research write-ups) with each other, **discuss it**, and
      **converge**. That is the entire procedure. It is a protocol *between the two lanes* — not an
      escalation to a referee, and not an escalation to Steve.
- `[x]` 3.8 **Name the split** (`docs/AUTONOMOUS_WORK.md` §3.1's own framing): *research finds what
      others do; thought partnership stress-tests what we should do.* Research when there's a
      documented answer; thought partnership when it's judgment. §3.1 already carries the full
      dispatch discipline — **cite it, don't restate it.**
      ⚠ §3.1 lives in the **main** worktree's copy — the `-pm` copy is 332 lines stale

**Gate 3.G** `[x]` **PASSED 2026-08-03** — 78 lines measured; 3.G/16–18 positive scenarios + both
guards green; every act-on rule is in the always-read part. Original gate text:
A doc phase still needs a falsifiable gate, or it ships nothing and nobody notices.
Always-read skill is **still ≤ ~80 lines** (M5 — measure it, don't estimate) · every rule an agent is
expected to *act* on appears in the always-read part, not only the on-demand reference · **zero
ERD-specific paths** in the generic template (M3 — `grep -c 'AUTONOMOUS_WORK\|\.brain/research' templates/navigation-standards.SKILL.md`
returns 0) · a fresh reader can state the three tiers and which one is the record

## Phase 3b — CUT (Steve, 2026-08-03)

Was: a COSTAR+XML fill-in template for escalating a deadlocked dialog to Codex as a referee.
**Cut before implementation.** Reasons: it services a sub-case (deadlock) of a sub-case (judgment
call) of a feature (dialog mode) that has never run once; `docs/AUTONOMOUS_WORK.md` §3.1 already
documents the full dispatch discipline it would have encoded; its gate required a live billable Codex
dispatch to validate an artifact with zero demonstrated demand; and its one novel element (prompt
fencing) had no mechanism behind it — `fence_untrusted()` / `neutralize_prompt_section_tags()` are
Python in the ERD repo (`src/utils/text.py:19,39`) that nothing in agent-brain would ever invoke, so
the gate would have verified one instance of agent compliance, not a mechanism.

Task **3.7** carries the whole remaining rule. **Revisit only if a real deadlock actually occurs.**

## Phase 4 — Presence field `[x]` (convention · `templates/presence.md`) — CONCURRENT

- `[x]` 4.1 Add optional `dialog_with:` to the presence schema
- `[x]` 4.2 Surface it in `cmd_status` so an open dialog is visible to other lanes and to Steve
      (a conversation still open an hour later becomes visible rather than silent)

**Gate 4.G** `[x]` **PASSED 2026-08-03** (4.G/13a red + 13b/13c guards all green) — **scoped verify**, plus: a presence note **with** `dialog_with:` shows the open
dialog in `brain status` · a note **without** it renders unchanged (the field is genuinely optional —
13 existing notes must not break) · `brain reconcile` does not flag the new field as stealth-structural

## Phase 5 — Deploy `[ ]` (requires P1–P4)

⚠ **Deploy is machine-wide and instant.** Both hooks resolve the engine through
`git rev-parse --git-common-dir`, so **every lane in every worktree executes the single deployed
`<main>/.brain/bin/brain`**, whatever branch that lane is on. There is no staged rollout and no
per-lane opt-in: the moment 5.2 lands, all 13 lanes are running the new engine. Sequence accordingly.

- `[ ]` 5.1 **FIRST — hand-add `dm/` to the DEPLOYED `<main-worktree>/.brain/.gitignore`.**
      **This must land BEFORE the engine, not after.** Task 1.3 edits only `cmd_init`'s `printf`,
      which affects **fresh inits only**, and 5.4 correctly forbids the one command that would
      regenerate the deployed file — so nothing else will ever add it. Deploy the engine first and any
      DM sent in the gap leaves inbox files untracked-and-unignored; **@pm is the agreed brain
      committer** and `cmd_commit` stages the whole vault with a single pathspec, so the very next
      `brain commit` sweeps them in — which then poisons every lane's `touches[]` and fires
      `_detect_collisions` on every push. The window is small and the blast radius is every lane.
- `[ ]` 5.2 Explicit `cp` source → `<main-worktree>/.brain/bin/brain`
- `[ ]` 5.3 Deploy the skill in two steps (seam decision d): cp the updated generic template into
      the deployed `<main>/.brain/templates/`, add the ERD project-hooks section to **that** copy,
      then `brain install` (which cp's from the vault copy, not this repo)
- `[!]` 5.4 **Never run `brain init --force`** — it unconditionally overwrites `.gitignore` and
      `INDEX.md`, and the deployed `.gitignore` is a hand-commented variant that would be clobbered

## Phase 6 — End-to-end verification `[ ]` (two real lanes — the method used throughout E0–E15)

- `[ ]` 6.1 Two cold scratch lanes, each armed only by the hook
- `[ ]` 6.2 Lane A DMs B an unblock signal → B acts within ~15s with no human
- `[ ]` 6.2a **The Steve scenario — merge broadcast to a mixed-liveness crew.** With B running and a
      third lane C **shut down**, A runs `brain dm @all "merging X, re-sync before your gates"`.
      Assert: B acts within ~15s; then boot C and assert **C reports the message as part of waking
      up** and acts on it. This is the case that motivated 1.6 + 2.1 and the one the pre-review plan
      would have silently dropped on the floor.
- `[ ]` 6.3 **Anti-sycophancy — planted flaw + negative control. Both must pass.**
      (a) Seed the dialog with a proposal containing a **real flaw B was not told about**; assert B's
      objection finds **that flaw**. (b) Separately seed a **sound** proposal; assert B does **not**
      manufacture an objection and the convergence note records *nothing contested*.
      The original form of this gate — "assert B's first turn contains an objection" — was **theatre**:
      3.5 instructs lanes to open with a critique, so the gate passed by compliance and could never
      fail for the reason it existed. Worse, on a sound proposal that rule forces a fabricated
      objection. Mirrors the standing rule to adjudicate acceptances as hard as refusals.
- `[ ]` 6.4 Seed a question with a real external standard; **assert a lane researches before taking a
      position** rather than asserting from priors
- `[ ]` 6.5 Convergence writes a `connections/` note recording the contested point
- `[ ]` 6.6 `git status` in the **real main worktree** (`<main>/`, not the scratch fixtures 6.1 uses)
      shows no `.brain/dm/` churn, and `git log -p` on the journal shows no DM body

## Phase 7 — Review gates & ship `[ ]` (requires P6)

- `[ ]` 7.1 **`/simplify`** on the full diff — reuse / simplification / efficiency / altitude. Quality
      only, not a bug hunt. **Verify the diff against the 0.3 seam decisions** — that is what closes
      the loop between design-time and post-green.
- `[ ]` 7.2 **`/steadows-code-review`** — orchestrator-side (Claude Code), never a Codex skill run. If
      its adversarial second-opinion step dispatches Codex, scope that prompt to a **single agent, no
      fan-out**; the fleet belongs to 7.4.
- `[ ]` 7.3 **PR — Steve clicks it.** `github.com/steadows/agent-brain`; the `gh` CLI here is the work
      EMU account and cannot open it. Base: `fix/pretool-collision-warning` (itself still awaiting its
      own PR — 7.3 may end up merging both).
- `[ ]` 7.4 **`/steadows-ultrareview`** → dispatched to Codex, **explicitly invoking the skill**.
      **Small fleet** — the diff is a few dozen lines of POSIX shell plus markdown. Not the smallest:
      it touches a shared multi-agent vault and a secret-egress path, so size for that, not for the
      line count.
- `[ ]` 7.5 Address CRITICAL/HIGH from every gate before merge; fix MEDIUM where reasonable.

**Gate 7.G** `[ ]` **scoped verify** green on the final diff · no unaddressed CRITICAL/HIGH · the five
"Done when" conditions demonstrably met, each pointing at the scenario in `test/dm.sh` or the P6 run
that proves it

---

## Risks

- `[!]` **`dm/` MUST be gitignored — not optional.** `cmd_commit` stages the whole vault
  (`git add -- .brain`, single-pathspec allowlist, no denylist). Worse: `cmd_reconcile`'s auto-fix
  sets each lane's `touches[]` from `git diff --name-only origin/main`, so tracked inbox files would
  land in `touches[]` and make **every lane collide with every other lane** on `.brain/dm/*`.
- `[!]` **The secret scan cannot see a DM body — on either path.** It is line-anchored
  (`^[A-Z][A-Z0-9_]*=.+`, `bin/brain:447`); `jq -cn` inbox output starts with `{`, and a journalled
  body would sit mid-line after `- <ts> <feat> — `. **Two mitigations, both required:** `dm/` is
  gitignored (the inbox never reaches a commit) **and** task 1.2 keeps the body out of the journal
  entirely. Neither alone suffices — `journal/` is committed and is not covered by the `dm/` ignore.
  This is why the earlier "gitignoring `dm/` resolves it completely" claim was wrong.
- `[!]` **`brain install` is an unconditional `cp`** to `~/.claude/skills/navigation-standards/SKILL.md`
  — it destroys local hand-edits. Edit the template, never the installed copy.
- `[ ]` **Presence `updated:` is not a reliable liveness signal** — do not build a staleness warning
  on it. `cmd_reconcile`'s auto-fix bumps it whenever it runs against a dirty tree, and sources
  `touches[]` from `git -C $ROOT diff --name-only`, where `$ROOT` is **always the main worktree**,
  never the lane's own. Observed 2026-08-03 on `presence/pm.md`: timestamp refreshed and `touches[]`
  populated with *another lane's* uncommitted files, while the narrative fields stayed two weeks old.
  Knock-on, **out of scope here but worth its own ticket**: `_detect_collisions` reads that same
  `touches[]`, so it can attribute files to a lane that never touched them.
- `[ ]` **Read archives grow unbounded.** Task 2.1's rotation keeps `inbox.jsonl` short (emptied every
  session), but `dm/<lane>/read/` accumulates one file per boot forever. Both sit under the gitignored
  `dm/` so nothing reaches a commit — it is disk only. Acceptable for v1; note it rather than build a
  reaper for it.
- `[ ]` **Rotation has a narrow write race** — a DM appended between the `mv` and the watcher arming
  lands in the archived file, not the new inbox, so it is delivered at the *next* boot rather than
  immediately. Sub-second window, no message lost. Accepted; do not add a lock (see task 1.4).
- `[ ]` **`whoami` is empty off a brain branch** — a DM from `main`/detached HEAD has no resolvable
  sender; falls back to `$BRAIN_FEATURE`, then `system`.

## Out of scope

- **The Codex escalation template** (was Phase 3b) — cut 2026-08-03; build it the first time a real
  deadlock happens, not before
- **A stale-recipient warning** (was task 1.3) — cut 2026-08-03, for two independent reasons: task
  2.1's rotation means a DM to a dormant lane is **delivered at its next boot**, not lost, so there is
  nothing to warn about; and the `updated:` field the warning would key on is unreliable (see Risks).
  The original justification — that the unblock case is always driven with both lanes live — still
  holds but is no longer the load-bearing one, since `dm @all` (1.6) deliberately does reach dormant
  lanes.
- A brain test suite (ROADMAP wants one; verification here is the live two-lane run)
- Cross-machine DM — same-machine only; the journal line is the only part that travels
- Any `claude`-harness team-join mechanism (E10/E13: one-way, and the two-way form requires @pm to
  spawn every lane — rejected by Steve)
