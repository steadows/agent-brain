# Agent Brain — Strategy & File-Structure Record

> **What this is.** The living spec for the "Agent Brain": a shared coordination vault that
> lets multiple AI orchestrators working concurrent features on one repo see each other, share
> knowledge, and surface cross-feature gotchas. We build it folder-by-folder; each folder is
> marked **LOCKED** (agreed) or **TODO** (not yet specced). This record is the source of truth
> for the *refined* decisions made in conversation — it supersedes the earlier
> `BUILD-PLAN.md` where they differ (that plan is the detailed backing; this record
> is what we actually decided).
>
> **Companion docs:** `BRIEF.md` (original context + research) ·
> `BUILD-PLAN.md` (workflow's detailed build plan).

> **End goal: project-agnostic.** This is a methodology to drop into *any* repo where one person
> runs multiple features + multiple orchestrators. This project is the worked example, not the
> only target. So: nothing hardcodes paths or feature names — paths are discovered, the structure
> is templates + a couple of small commands.

---

## Principles

- **Personal dev-workflow tooling.** Never touches product code (`src/`), the product, or Neo4j.
  No architecture-first hard-lock.
- **Pull, not push.** Agents *read the brain themselves* instead of waiting for the harness to
  inject context. The brain gives harness-independent *knowledge*; the harness still runs the
  agents (it still takes a SessionStart hook for an agent to learn the brain exists — stated
  honestly, not hidden).
- **Knowledge, not execution.** Shares context/coordination; never copies memories, skills,
  plans, or docs into itself — it *points* at them.
- **Lightweight but well-governed.** Smallest thing that works; freedom to extend, governance on
  the core. Reuse existing machinery (`/wrap`, `/learn-eval`, the memory store, historian).

---

## Core model — decisions locked

| # | Decision | Detail |
|---|---|---|
| M1 | **One vault per repo** | `<repo-root>/.brain/`. All orchestrators (in any worktree) read/write the *same* folder via its absolute path — sharing comes from the shared path, not a server. Path is *discovered* (`git rev-parse --show-toplevel`), never hardcoded. |
| M2 | **Full view = built-in search** | An agent can already read/search *every* markdown in the repo (brain, docs, `.context/`, skills, memory store) with built-in Grep/Read — always fresh, zero setup. "Full view" needs no indexer. |
| M3 | **Writes = built-in** | Notes via Write/Edit; the journal via atomic shell append (`>> journal/<date>.md`). Bulletproof, no dependency. |
| M4 | **Smart index = additive, scoped to `.brain/`** | A smart-search layer (the `sweir1/obsidian-brain` *superset* — read+write+graph, auto-indexes on write, one server) is **optional and pointed at `.brain/` only**. It adds semantic/connection search; it does *not* gate access. Turn it on when the vault fills (near-empty day one = decoration). obra rejected (single-root, dormant, stale-on-write, unlicensed). |
| M5 | **The FEATURE is the unit of identity — not the worktree** | One persistent presence note per *feature*, living across all the feature's tickets/branches/PRs/worktrees. Worktrees are ephemeral (cut per ticket → die at PR) and never anchor identity. |
| M6 | **Branch-naming rule: the feature name is always in the branch** | Every branch a brain agent cuts contains its feature slug (e.g. `feat/dt-525-graph-…`). This makes identity resolution a single stable wildcard that never needs maintaining. Upheld by the agent's own branch-naming (nav skill) + a hook guard that flags a branch missing a known feature slug. |
| M7 | **Two instantiation levels** | Project-level `brain init` (scaffold the brain into a fresh repo from templates) + feature-level `brain new-feature <slug>` (register one feature, run once when a feature starts). No per-worktree/per-ticket registration. |
| M8 | **Governance: agents self-evolve; human is informed, never a gate** | Two tiers by blast radius. **Conventions** (note formats, rulebook protocols) self-evolve autonomously (even unattended) through an automated gauntlet (propose → lock → validate → apply in lockstep → `CHANGES` log surfaced to Steve → one-step revert) — airtight, non-blocking. **Machinery** (hooks + `brain` script) is **human-applied in v1** (agents propose only); autonomous machinery self-evolution is **v2**. See the Governance section. |
| M9 | **The human never manages or directs coordination** | Steve keeps no lists, declares no shared files, tends no notes, chases no stale items. Agents detect/declare/maintain/resolve everything; the discipline lives in the nav skill + hooks (the system polices itself). Day-to-day coordination = 100% agents, 0% human. |
| M10 | **Nothing ever blocks waiting on the human** | The brain never produces a to-do that gates Steve. Where something might "wait on Steve," the agent **decides and proceeds**, recording the call for *optional* after-the-fact review. Even a brain-structure-change proposal is non-blocking — the agent keeps working; Steve adopts it later only if he chooses. Steve looks at the brain when *he* wants; it never nags or gates him. No "needs your call" surface. |

---

## File structure (how it operates)

```
<repo-root>/.brain/
  INDEX.md           # LOCKED — self-filling dashboard (you) + map (agents); never a to-do
  presence/          # LOCKED — one note per FEATURE: where each agent is
  connections/       # LOCKED — one note per cross-feature gotcha (the blackboard)
  journal/           # LOCKED — append-only daily comms log
  research/          # LOCKED — shared findings (the durable home for research)
  templates/         # LOCKED — blank schemas (what makes it project-agnostic)
  bin/               # LOCKED — the `brain` command (init / new-feature / whoami / announce / status)
  .gitignore
```
Plus, outside the vault: the nav-standards skill (the constitution), the SessionStart hook
registration, and — if the smart layer is on — a `.mcp.json` + launcher for the superset.

Folder status: **SPEC COMPLETE — all content + plumbing LOCKED** (Presence · Connections · Journal ·
Research · INDEX · templates · brain command · hooks · /wrap). Superset indexing = a committed
**Phase 2** (after the spec). Next: multi-agent review + enhancement.

---

## `presence/` — LOCKED ✅

**One markdown note per feature**, `presence/<feature-slug>.md`. It is that feature-agent's live
status board and persists for the feature's entire life, across every ticket, branch, worktree,
and PR underneath it. ~one file per feature (this repo: graph, cockpit, workbench,
langgraph-runtime, + a 5th when it starts).

### Schema — identity (stable) vs live (churns)

```yaml
---
type: presence
agent: graph                       # slug = filename = wiki-link target
feature: "Graph Explorer"
status: active                     # active | blocked | idle | done
phase: PG1
# --- identity: set once at registration, lives the whole feature ---
owns_branches: ["*graph*"]         # wildcard(s) that identify this feature's branches
plan: GRAPH_FEATURE_GSD_PLAN.html
tracker_epic: DT-206               # generic "tracker" — not tied to Jira specifically
# --- live: auto-updated as the feature moves ticket → ticket → PR ---
current_branch: feat/dt-520-graph-pg1-read-surface
current_worktree: /Users/.../enterprise_research_dashboard-dt520
current_ticket: DT-520
touches: [src/api/routes/graph.py] # repo-root-relative paths it's editing → collision detection
blocked_on: []                     # connection slugs and/or external ids
updated: 2026-06-13
---
<one short paragraph: what it just did, what's next, [[links]] to connections touching its files>
```

### How it operates

- **Identity resolution.** A session figures out which feature it is by matching its current
  branch (`git branch --show-current`) against each presence note's `owns_branches`. That same
  match is the hook **allowlist** — a branch matching no feature → hooks no-op (so the repo's
  other, non-brain worktrees are ignored automatically). No per-worktree sentinel file.
- **Branch rule (M6).** Because every branch carries the feature slug, `owns_branches` is one
  stable wildcard (`*graph*`) set once — it never needs appending. (Safety net: if a branch ever
  slips the pattern, the agent — which knows its feature — adds it on boot. Prefer broadening the
  wildcard over listing branches one-by-one; a feature keeps ~1–3 patterns, not a branch log.)
- **Live fields** (`current_branch`/`worktree`/`ticket`, `phase`, `touches`, `blocked_on`,
  `updated`) are refreshed by the agent as it moves ticket-to-ticket and at phase boundaries.
  Worktree churn is invisible to the brain.
- **Liveness.** An `idle`/`done` agent, or one whose `updated` is older than ~2 days, is skipped
  by collision checks so a stale/parked feature doesn't raise false alarms.

### Instantiation — starting a new feature-agent

Run **once per feature** (e.g. the not-yet-started 5th), from inside that feature's worktree:

```
brain new-feature <slug>
```
It: discovers the brain; scaffolds `presence/<slug>.md` from `templates/presence.md`,
auto-filling `current_branch`/`current_worktree` from git and seeding `owns_branches: ["*<slug>*"]`
+ `status: idle`; leaves `feature`/`plan`/`phase` as `TODO`; appends a journal line announcing the
newcomer. The agent completes the stub on its first real session and flips `idle → active`.
A feature can be **pre-registered as `idle`** before work starts (shows as "upcoming" in INDEX,
skipped by collision checks) or instantiated the moment it kicks off — both are one command.

**No per-ticket / per-worktree / per-PR registration** — those just update the live fields.

---

## `connections/` — LOCKED ✅

The cross-feature blackboard — where one feature **calls something out** to the others. A
connection is a **standing relationship between features that lasts until it's settled** — that's
the line that separates it from the journal:

- **Connection** = something another feature must *do* or *keep in mind* over time. Persists.
- **Journal** = a moment-in-time heads-up ("about to push"). Scrolls by.
- Rule of thumb: *needs another feature to act/remember over time → connection; just a heads-up → journal.*

### The four kinds (covers every real case)

- **clash** — two features building the same thing, unaware. *(Graph + Cockpit both made a canvas.)*
- **shared-file** — two features edit the same file/zone; whoever merges second inherits the other's changes. *(`agent.ts`.)*
- **waiting-on** — one feature can't move until another (or something external) ships. Directional. *(Cockpit ← Workbench Composer; LangGraph ← GLOBE-17599.)*
- **shared-rule** — a convention both must keep in step; change one side, update the other. *(`Label:entity_id`; `api → exploration`.)*

### Schema

```yaml
---
type: connection
features: [graph, cockpit]        # internal features involved (external named in body)
kind: clash                       # clash | shared-file | waiting-on | shared-rule
status: open                      # open (act now) | watch (stay aware) | resolved (kept as history)
severity: high                    # high | medium | low → dashboard sort
blocks: [cockpit]                 # which feature(s) are stuck — empty if symmetric (direction)
files: [web/src/app/_views/]      # shared file or zone (dir prefix) → matched vs presence `touches`
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
What the edge is, who owns resolving it, what each side must do. Links both sides: [[graph]] · [[cockpit]].
```

### How it operates (all agent-driven — see M9, the human never touches this)

- **Born when an agent spots the edge.** Main trigger: the presence "before touching a shared
  file, who else is in it?" check — overlap with another active feature + no note yet → the agent
  writes one (after a search, so no duplicates). Same for realizing it's waiting on another
  feature or notices a shared rule. Creating one is additive = free.
- **Delivered without paging anyone.** The other side gets it at *their* session start (boot
  surfaces connections naming them or touching their files) and before they touch the same file.
  The connection *is* the call-out.
- **Closed when settled** — flip `status → resolved`. **Kept as history** (never deleted — records
  *why*), **never renamed** (orphans the links).
- **Two-way linked to presence** — presence `blocked_on: [connection-slugs]` ↔ the connection
  links back to the presence notes. That back-and-forth *is* the graph.

### Declaring a file as shared (M9 — hands-off)

A file becomes "shared" two ways, both producing the same artifact — a `shared-file` connection:
- **Declared up front:** create a `shared-file` connection with `status: watch` naming the file or
  **zone** (a directory prefix like `web/src/app/_views/` → anything created there triggers
  coordination). That note *is* the declaration; no separate registry.
- **Detected automatically:** two active features' `touches` overlap on a path with no note yet →
  the second agent writes it. Catches the ones nobody foresaw (the Cytoscape clash).
- **At inception** an agent cross-checks its planned `touches` vs everyone else's + existing
  declarations; hits → coordinate. Steve declares nothing and keeps no list (M9).

### Liveness (also automatic)

A `waiting-on` connection self-resolves when the blocking feature finishes/merges, so a blocked
feature never sits stuck on a note nobody's tending. Detailed in the governance pass. The human
never chases stale connections.

### Project-agnostic

The four kinds + schema are universal to any multi-feature repo. `templates/connection.md` is the
blank; agents fill it. (Optional `brain connect <a> <b>` helper, but connections are free-to-create
so a template suffices.)

---

## `journal/` — LOCKED ✅

The append-only, time-ordered comms timeline — the *ephemeral* half of the connection/journal
split. **One file per day** (`journal/YYYY-MM-DD.md`); agents only ever **add lines to the end**,
never edit past ones (keeps the timeline trustworthy + append is the safe concurrent-write
primitive). The daily file is **auto-created on the first line of the day**.

### Line format
```
- 14:20 graph — PG2 started; touching web/src/app/_views/ [[cytoscape-shared-wrapper-divergence]]
- 15:05 workbench — 1.9 Composer merged; @cockpit you're unblocked [[composer-handoff-gate]]
```
Time + feature + short message + optional `[[links]]`. Daily file carries a tiny header
(`templates/journal.md`).

### What goes in it
The three announce moments (**phase start**, **phase end / gate**, **about to PR**), ad-hoc
heads-ups, "new feature joined," and direct call-outs (`@feature`).

### How an agent reads it (not the whole thing)
Pulls only what's relevant: lines that mention **its feature**, **@-mention it**, or **touch its
files**, and only **since it was last active** (derived from its presence `updated` — no separate
"last read" bookkeeping).

### Delivery — three tiers (cheap → guaranteed)
1. **Startup catch-up** — at session start, surface relevant lines since last active.
2. **Fast awareness (after every action)** — a check runs after each tool the agent uses; if the
   journal **changed** and there's a **new line mentioning this agent**, it injects it. Drops
   call-out latency from "next startup" to "within one action" (seconds for a busy agent).
   **Cost: zero model tokens to run** (a shell `stat`+`grep`); silent unless changed *and* relevant;
   injects only the few most-recent lines that mention this agent.
   - **Honest ceiling:** delivery is *between actions*, not mid-thought — the harness only injects
     at action/turn boundaries. "Real-time" = next action boundary, not literally instant.
   - **Reassess tripwire (Steve, 2026-06-13):** fine as long as it's cheap; if heavy simultaneous
     chatter makes it a token hog, throttle to @mentions-only or fall back to before-action only.
3. **Hard gate (before a risky action)** — a check *right before* `git push` / editing a declared
   shared file can **pause and ask**. This is the *guarantee* (catches it even if every earlier
   heads-up was ignored). Awareness ≠ guarantee; layer both.

### @mentions
`@feature` in a line. The target catches it via the tiers above (startup, after-action, before its
own risky action). **Not a blocking interrupt** — the "block exit until ack" hook was cut as too
aggressive.

### Who writes it (never the human — M9)
Agents (nav skill, three moments + ad hoc) and hooks (session-start, after-action, pre-PR), all via
atomic shell append to the same daily file.

### Relationship to connections
Journal = the **event** ("merged the wrapper — clash resolved"); connection/presence = the **state**
(the actual `resolved` flip). One moment often does both.

### Project-agnostic
Daily-file timeline with timestamped, feature-stamped lines is universal. `templates/journal.md` =
the daily header; line format = a nav-skill convention.

---

## `research/` — LOCKED ✅

The key realization: **research is the one kind of knowledge with no durable shared home today.**
Memories, skills, plans, docs all live somewhere canonical the brain just *points* at — but
research docs (`docs/research/`) are **gitignored and per-worktree**, so a pointer to one is
useless to another agent (the file isn't in its worktree). So `research/` can't just point — it
**carries the finding itself.** The brain is research's home.

- **`docs/research/`** = an agent's raw scratch — full deep-dive, gitignored, only in the worktree
  that made it.
- **`.brain/research/`** = the curated, committed, shared, **indexed** version — a distilled,
  self-sufficient summary (and the full doc too, when a finding is worth keeping verbatim).

### Schema
```yaml
---
type: research
topic: exa-search-output-cap
title: "Exa search output-cap calibration"
by: graph                       # which feature produced it
status: current                 # current | stale | superseded
sources:                        # best-effort pointers (scratch may not exist in your worktree)
  - docs/research/dt-395-exa-cap.md
  - https://exa.ai/docs/...
tags: [exa, tools]
updated: 2026-06-13
---
The finding, distilled enough to act on WITHOUT the original. [[links]] to related notes.
```

### How it operates (agent-driven — M9)
- **Before researching X** → check `research/` (and grep). Found → read it, don't repeat (de-dup).
- **After researching X** → drop a distilled, self-sufficient note so the other features benefit.
- **Freshness** → dated + `status`; an agent that finds one stale updates/marks it. Carries a
  "verify if old" caveat (like the memory store). Never the human's job.

### Decision: research lives in the brain; it does NOT auto-graduate (Option B)
**`/learn`/`/learn-eval` stay independent of the research shelf.** Research is *information*; a
skill is a *reusable pattern* — the two are not the same, and "researched" ≠ "skill-worthy." So
there is **no automatic "researched → skill" pipe** (it would junk up the skill library). A
finding can still become a skill/memory, but **only by deliberate judgment**, never automatically.
The brain is the durable home for shared research; skills/memories remain the deliberately-curated
reusable library.

### Project-agnostic
`templates/research.md` = the blank; schema is generic. The "research has no shared home → the
brain is it" insight holds in any repo.

---

## `INDEX.md` — LOCKED ✅

The brain's **home page** — one file, two audiences:

- **For Steve (in Obsidian):** a **self-filling dashboard.** Dataview blocks auto-render the live
  state from the notes — *active agents*, *open connections (by severity)*, *research on the shelf*
  — plus a link to today's journal. Nobody maintains it; Obsidian rebuilds it from the notes on
  every open.
- **For agents (reading raw markdown):** a **map + protocol nudge** — the folder links and "run the
  `navigation-standards` skill first." Agents can't render Dataview, and they don't need to: their
  live "who's active" orient comes from the **SessionStart hook + grep**, not from INDEX's tables.

**No "Needs your call" surface (M10).** INDEX is pure status you glance at when *you* choose — never
a to-do list that waits on you. If a feature is blocked on a human product-decision, that lives in
its GSD plan (your existing system), and the agent makes the call where it can; the brain never
nags.

**Stays current by itself (M9):** header + folder map written once at `brain init` (static — change
only via a governed structural edit); dashboards are Dataview (auto). Nobody updates it.

**Project-agnostic:** `templates/INDEX.md` is the blank; the Dataview queries key off the generic
`type:` field, so it drops into any repo unchanged.

---

## Plumbing — how it builds and runs

### `templates/` — LOCKED ✅
The blank schemas that make the brain portable. `brain init` copies these into a fresh repo;
agents/commands scaffold notes from them. All generic — nothing project-specific.
- `templates/presence.md` · `connection.md` · `journal.md` · `research.md` — the locked schemas
  with `TODO` placeholders.
- `templates/INDEX.md` — the dashboard (Dataview queries keyed on the generic `type:` field).
- `templates/navigation-standards.SKILL.md` — the constitution, installed into
  `.claude/skills/navigation-standards/` at init.

### The `brain` command — LOCKED ✅
One portable shell script, `.brain/bin/brain`, that travels with the brain (no Claude-specific
deps). Lean subcommand set — setup, identity, journal, orient:
- **`brain init`** — scaffold into a repo: discover repo root (git), create `.brain/` folders, copy
  templates, write `INDEX.md`, install the nav skill into `.claude/skills/`, register the hooks in
  `settings.json`, write `.gitignore`. One-time per repo.
- **`brain new-feature <slug>`** — register a feature once: scaffold `presence/<slug>.md` (auto-fill
  `current_branch`/`current_worktree` from git; seed `owns_branches:["*<slug>*"]`, `status: idle`),
  append a journal "joined" line. No per-worktree/ticket registration.
- **`brain whoami`** — resolve the current feature by matching `git branch --show-current` against
  every presence note's `owns_branches`. Empty = not a brain branch. **The single identity
  resolver** (replaces the per-worktree sentinel); reused by every hook.
- **`brain announce "<msg>"`** — atomic-append a `- HH:MM <feature> — <msg>` line to today's journal
  (auto-creates the daily file). One canonical journal-write path, reused by agents + hooks.
- **`brain status`** — print the text dashboard (active agents + open connections touching me) for
  terminals / agents / the session-start hook — the agent-readable form of INDEX (agents can't
  render Dataview).
Hooks are thin wrappers over these; `brain` is the engine.

### The hooks — LOCKED ✅
Registered in `settings.json` (project + global, for day-one coverage of in-flight worktrees). All
thin wrappers over `brain`, all **fail-open and quiet**, all **allowlist on `brain whoami` being
non-empty** (a branch matching no feature → no-op; this is how the repo's other ~9 worktrees are
ignored).
1. **SessionStart** — `whoami` non-empty → inject "run the `navigation-standards` skill" + `brain
   status`. The agent boots oriented.
2. **PostToolUse (fast awareness)** — the cheap one: only if the journal mtime moved **and** a new
   line mentions this feature → inject the few recent relevant lines. Shell-only (zero model tokens
   to run), silent otherwise. Reassess tripwire on file: throttle to @mentions-only if it ever hogs.
3. **PreToolUse — the hard gate** — before `git push` / `gh pr create` (and before Edit/Write to a
   *declared shared* file): compute changed/target paths, check vs other **live** agents' `touches`
   + shared-file connections; on a real collision, `brain announce` a warning + inject it.
   **Non-blocking by default** (`allow` + context); `ask` (pause) is a one-line knob. This gates the
   *agent's risky action*, never Steve (M10-safe).

### `/wrap` integration — LOCKED ✅
Three surgical edits to `~/.claude/skills/wrap/SKILL.md` (real phase headers):
- **Phase 1 — Plan Audit:** the agent writes its own `presence/<feature>.md` live fields from the
  `gsd-state` it just audited (no parser — it knows its state); flip `connections/*.md` settled this
  session `open → resolved`; **liveness auto-resolve** — any open connection whose blocking feature
  is now `done`/merged resolves itself (M9/M10 — never waits on Steve).
- **Phase 4 — Git Hygiene:** **main-worktree session only** — path-scoped `chore(brain):` commit
  (`git -C <main> commit -- .brain/`), abort if mid-rebase/merge, ff-only onto fresh `origin/main`.
  Sibling sessions skip (the live folder already shared every write; the commit is durability-only).
- **Phase 6 — /learn:** brain **helper-skills** (agent-built automation) route through `/learn-eval`
  (default Project). Brain **research does NOT auto-graduate** (Option B) — `/learn` is unaffected by
  the research shelf.

---

## Phase 2 (planned — after the spec, per Steve) — indexing via the superset

Committed addition, **not built in v1**: fold in **`sweir1/obsidian-brain`** (the superset —
read+write+graph, auto-indexes on write, Apache-2.0) as the smart-search layer.
- **Scoped to `.brain/` only** (single-folder is exactly right there). A checked-in `.mcp.json` +
  a `.brain/bin/` launcher; its index DB lives outside the vault (gitignored).
- **Reads** (smart search / find-connections / themes) go through the superset; **writes stay
  built-in** (`Write`/`Edit` + `brain announce`) so the write path never depends on it. **Grep stays
  the live truth**; the index is the smart layer on top.
- Turn on **when the vault has enough notes to be worth it** (near-empty day one = decoration). It's
  a **pure addition** — the v1 schema/folders are designed so nothing changes when it lands.

---

## Governance & self-evolution — LOCKED ✅

**Principle:** the agents evolve the brain themselves; Steve is **informed and can veto, never a
gate** (M9/M10). Split by blast radius:

- **Conventions** — note formats, the protocols in the rulebook (nav skill). Low blast. **Agents
  self-evolve them autonomously, even unattended.**
- **Machinery** — the hooks + the `brain` script that *run* coordination. High blast. **v1: agents
  do NOT change machinery autonomously** — an agent that wants a machinery change writes a proposal
  (surfaced to Steve) and keeps working with the current machinery; Steve/the operator applies it
  deliberately.

**The convention-change gauntlet (checks & balances — all automated, reuses reconcile + git):**
1. **Propose first** — written down, *not yet live* (journal the change *before* applying, not after).
2. **Lock** — one structural change in flight at a time → two agents can't make conflicting changes.
3. **Auto-validate** — reconcile dry-run: every existing note still parses, nothing dangling or
   contradictory. **Fail → rejected + rolled back.** A broken or conflicting change cannot go live.
4. **Apply in lockstep** — rulebook + template + notes together.
5. **Record + surface** — a dedicated `CHANGES` log (not the noisy journal); `brain status` shows
   **"⚠ N brain changes since you last looked"** at the top. Brought to attention, never buried.
6. **One-step revert** — every change is a committed diff (`brain revert <id>`). Veto with teeth,
   without being a gate.

This is **not** the heavyweight ratification/voting model (rejected by the review) — it's a lock +
an automated check + a visible log.

**Deferred to v2 — autonomous machinery self-evolution.** Letting agents change machinery during
*unattended* runs (the context-aware "ask when a human is attached / shelve when not" gauntlet +
machinery self-tests) is a v2 feature. v1 keeps machinery human-applied so it stays airtight and an
overnight/autonomous run can never hang on a machinery change.

---

## Decision log

- **2026-06-13** — Methodology must be **project-agnostic** (templates + discovery, not hardcoded).
- **2026-06-13** — Identity anchors to the **feature, not the worktree** (M5); worktrees are
  ephemeral (cut per Jira ticket/PR). One persistent presence note per feature.
- **2026-06-13** — **Feature name always in the branch** (M6) → `owns_branches` is a set-once
  wildcard; never maintained.
- **2026-06-13** — Smart index = the **superset scoped to `.brain/`**, additive, on when the vault
  fills; obra rejected (M4).
- **2026-06-13** — Full view comes from **built-in search**, not an indexer (M2). Presence
  **LOCKED**.
- **2026-06-13** — **The human never manages or directs coordination** (M9). Confirmed against
  shared-file declaration: agents detect/declare/maintain; Steve keeps no list, chases nothing.
- **2026-06-13** — Connections **LOCKED**: four kinds (clash / shared-file / waiting-on /
  shared-rule), connection-vs-journal line = "act/remember over time vs heads-up," shared-file
  declared via a `watch` note or auto-detected, liveness auto-resolves blockers.
- **2026-06-13** — Journal **LOCKED**: daily append-only file; three-tier delivery (startup /
  after-every-action fast awareness / before-risky-action hard gate). Fast-awareness approved as
  long as it stays cheap — shell-only, mtime-gated, relevant-lines-only; reassess if it becomes a
  token hog (throttle to @mentions-only or before-action-only). No blocking interrupt.
- **2026-06-13** — Research **LOCKED** with **Option B**: the brain is research's durable home;
  `/learn` stays independent (no automatic researched→skill pipe — research ≠ reusable pattern).
  Promotion to a skill/memory is deliberate-only. Brain note is self-sufficient (gitignored scratch
  doesn't travel across worktrees).
- **2026-06-13** — INDEX **LOCKED**: self-filling dashboard (human) + map (agents); **no "needs your
  call" box**. Added **M10 — nothing ever blocks waiting on the human** (agents decide & proceed;
  Steve is never a gate). All five content pieces now locked.
- **2026-06-13** — Plumbing **LOCKED** (one-pass): `templates/` + the portable `brain` command
  (init / new-feature / whoami / announce / status) + 3 fail-open hooks (session-start /
  after-action fast-awareness / before-PR-or-shared-edit gate) + 3 `/wrap` edits. **SPEC COMPLETE.**
- **2026-06-13** — Superset indexing confirmed as a committed **Phase 2** (after the spec): the
  `sweir1/obsidian-brain` superset scoped to `.brain/`, reads-via-superset / writes-stay-built-in,
  on when the vault fills. Pure addition. → Next: multi-agent review + enhancement.
- **2026-06-13** — Spec review done (`REVIEW.md`): "sound in shape, not yet sound to
  build." 2 blockers (root via `--git-common-dir` not `--show-toplevel`; identity wildcard mis-resolves
  3/4 features) + cluster of mostly-subtraction fixes (A–L). **Steve: cut the fast-awareness PostToolUse
  hook for v1** (ship SessionStart + PreToolUse only).
- **2026-06-13** — **Governance LOCKED** (M8 revised): agents self-evolve, Steve informed not gating.
  **Conventions** self-evolve autonomously via the gauntlet (propose → lock → validate → apply →
  `CHANGES` log surfaced → revert). **Machinery is human-applied in v1** (agents propose only) —
  **autonomous machinery self-evolution deferred to v2** so an unattended run can never hang on it.
  → Remaining before build: one mechanical pass to fold the review fixes A–L into the spec sections.
- **2026-06-13** — Build-ready spec written (`BUILD-SPEC.md`, folds A–L) → **consistency
  agent** pass → found + fixed the identity-loop imprecision (positional-slug exact-token rule + §2a
  table resolves all 4 features incl. workbench `board` & langgraph `main`) and the seed-transform gaps
  (legacy `kind` remap, `owns_branches` synthesis, static INDEX not Dataview) + small clarifications
  (`reconcile --check`, noclobber loser, `.env` regex, machinery-proposal slug). **Spec is build-ready.**
  Build method = one-shot direct build by me (not a workflow — tightly coupled, must-run artifact) +
  run-it smoke test. **Build wires hooks into settings.json + installs the nav skill machine-global →
  gated on Steve's go (environment change touching live sessions).**

---

## Next

**Spec is complete.** Next: a **multi-agent review + enhancement** pass over this whole record
(correctness/consistency, simplicity/over-engineering, portability, governance & the M9/M10
invariants, superset-readiness) → fold the keepers in → then build v1 → then Phase 2 (superset
indexing).
