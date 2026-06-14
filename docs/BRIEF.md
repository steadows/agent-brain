# Brief — The Agent Brain: a shared, self-governing coordination vault

> **Read me cold.** This brief captures everything decided in the design conversation that
> spawned it. It is the shared context for a workflow that will decide *how to build* a
> personal-dev-workflow "second brain" so multiple concurrent coding agents can coordinate.
> Every design agent should read this in full before proposing anything. Status: **design /
> decide-how-to-build** — no implementation yet.

---

## 1. Purpose (and what this is NOT)

**Purpose.** Steve runs **four feature builds concurrently**, each driven by its own Claude
Code orchestrator in its own git worktree (LangGraph runtime, Workbench, Graph, Cockpit).
They can't see each other. We want a **shared "second brain"**: one durable place where any
agent can (a) store and read memory, (b) read the *status* of the other concurrent plans,
(c) broadcast and discover cross-feature **gotchas and connections**, and (d) pull *any*
markdown it needs (briefs, plans, memories, skills, research) — **by reading it directly,
not by waiting for the Claude harness to inject it.** Pull, not push.

**This is personal dev-workflow tooling — a meta-layer ABOVE the four feature builds.**

Non-goals (explicitly out of scope):
- ❌ **NOT a product feature.** It never touches `src/`, the FastAPI/Next.js product, or users.
- ❌ **NOT Neo4j / the production knowledge graph.** "Graph" here = the *Obsidian* graph the
  agents read + the human watches. Zero coupling to the product's Neo4j substrate, schema,
  or invariants.
- ❌ **NOT a replacement for the harness.** It removes harness *over-reliance for
  context-sharing* (the part that bites). The harness still runs the agents, loads skills as
  behavior, and executes hooks. The brain gives harness-independent **knowledge**, not
  harness-independent **execution**. State this limit plainly; do not over-promise.

## 2. Core intent — harness-independent, pull-based knowledge

Today agents get memories via system-reminder injection, skills via the skill-loader, and
context via the conversation window — all **harness-mediated push**. If the harness doesn't
surface it, the agent doesn't know it exists. The brain inverts this: a durable on-disk vault
the agent **actively queries** ("what do I know about the `agent.ts` contract?", "what's
Cockpit's plan status?", "has anyone researched Exa?"). The intelligence layer (obra) makes
that queryable as MCP tools. This is the single most important design driver.

## 3. Concurrent-development context (and the real edges to seed)

The four features and their live state (from a repo-mapping research pass):

| Feature | Plan | Worktree / branch | State |
|---|---|---|---|
| LangGraph runtime | `LANGGRAPH_RUNTIME_GSD_PLAN.html` (DT-206) | main | P0–P2 done; **P4 4 tasks BLOCKED on GLOBE-17599**; P5 gated on P4 |
| Workbench | `DT-470_GSD_PLAN.html` | `enterprise_research_dashboard-workbench` / `feat/dt-487-board-composer` | P1 9/13; building Composer 1.9, Board 1.10 |
| Graph | `GRAPH_FEATURE_GSD_PLAN.html` | `enterprise_research_dashboard-dt520` / `feat/dt-520-graph-pg1-read-surface` | PG0 done; PG1 in worktree, not merged |
| Cockpit | `docs/plans/COCKPIT_INTELLIGENCE_GSD_PLAN.html` (DT-238) | `enterprise_research_dashboard-cockpit` / `feat/dt-513-cockpit-mini-graph` | P0–P1 done; P3 mini-graph in worktree |

**Seed `connections/` notes from these real, currently-uncoordinated edges** (this is the
day-one payoff — these exist right now and the agents don't know about each other's choices):

1. **Cytoscape divergence (open, high).** Graph PG2 is supposed to own the shared Cytoscape
   wrapper in `web/src/app/_views/` (ADR-0003, decision D-G7), but Cockpit P3
   (`feat/dt-513`) already built its own `cockpit-graph-canvas.tsx` importing `cytoscape`
   directly. Neither agent knows. Whoever merges second reconciles.
2. **`agent.ts` shared contract (watch).** `web/src/lib/agent.ts` is edited by **both**
   Workbench (P0, on main) and Cockpit (P4) on separate branches — silent merge-order
   dependency.
3. **Composer → handoff (blocker).** Cockpit P4 ("Send to Workbench") is blocked on Workbench
   task 1.9 (the Composer) reading the handoff. Cockpit P4 cannot start until 1.9 merges.
4. **`Label:entity_id` convention (invariant).** Shared by Graph (`graph_envelopes.py`) and
   Cockpit (C-2). Change one side → update the other.
5. **`api → exploration` ARCHITECTURE edge (contract).** All three backends route Neo4j
   access through it. Do not add a second parallel edge.
6. **GLOBE-17599 (external blocker).** LangGraph P4 (4.4–4.7) blocked; gates P5.

## 4. Locked architecture decisions

These are **decided** — the workflow refines *how*, not *whether*:

- **One vault, shared via MCP.** A single `.brain/` Obsidian vault lives at
  `<main-worktree>/.brain/`. All agents — regardless of worktree — read/write it **through one
  MCP server pointed at that one folder**. This dissolves the worktree-visibility problem
  (worktrees can't see each other's working trees, but they all hit the same MCP server →
  one copy of every note, writes visible immediately, no commit/merge needed).
- **Two surfaces:**
  - **Write (scoped):** a **folder-reading, headless-capable** Obsidian vault read/write MCP
    server, scoped to `.brain/`. Agents append/update coordination notes here only.
    *Headless is non-negotiable* — it must work in autonomous/cron/remote runs with no
    Obsidian desktop app foregrounded.
  - **Read (broad, read-only):** **obra/knowledge-graph** (Jesse Vincent; MIT; SQLite
    sqlite-vec + FTS5; exposes ~10 MCP tools: semantic + keyword search, path-find,
    shared-connections, N-hop, subgraph, Louvain communities, betweenness bridges, PageRank).
    obra indexes a **curated set of roots in place** (no copying) to give the unified
    "see any and all md" query surface.
- **obra is chosen** as the intelligence/query layer. It reads the live vault *in place*
  (files = nodes, `[[wiki-links]]` = edges) — a better fit for a *living* vault than graphify,
  which ingests a folder and *emits* its own derived copy + `graph.json`. **graphify is
  rejected as the foundation** (2 months old, single maintainer, ~2 releases/day breaking
  churn); it may return *additively* much later only if a large-corpus token-compressed wiki
  crawl is ever needed. Do not design around graphify.
- **Curated roots, not whole-repo** (the chosen scope for what obra indexes — see §6).

## 5. Vault anatomy (what goes in)

Plain markdown; **frontmatter = structured state (obra + Dataview query it); body = prose;
`[[wiki-links]]` = the graph edges.** Reuse the existing Claude memory-store conventions
(one-fact-per-file, `name`/`description`/`type` frontmatter, an INDEX, `[[ ]]` cross-refs)
and `slugify` from `src/utils/text.py` for stable ids.

```
.brain/
  INDEX.md          ← dashboard: a Dataview query auto-listing active agents + open connections
  presence/         ← one note per agent: branch, phase, status, files it `touches`, blocked-on
  connections/      ← one note per cross-feature edge/gotcha (the blackboard) — seed from §3
  journal/          ← journal/YYYY-MM-DD.md, append-only, timestamped one-liners (the comms timeline)
  research/         ← compact summaries + pointers to gitignored docs/research/ (no re-researching)
  _proposals/       ← proposed structural changes to the brain itself (governance — see §8)
```

Example `presence/` note frontmatter: `type, agent, branch, phase, status, touches[], updated`.
Example `connections/` note frontmatter: `type, features[], status (open|resolved|watch),
severity, kind (divergence|contract|gate-handoff|shared-file), updated`.

**HTML-plan wrinkle:** the feature plans are `*_GSD_PLAN.html`, not markdown — obra/Obsidian
won't read them as notes. Mirror each plan's *status* (current phase + blocked items) into its
`presence/` note, refreshed from the plan's embedded JSON state at `/wrap`.

## 6. The read surface — what obra indexes (curated roots)

Read-only, in place, no duplication:

| Root | Gives agents |
|---|---|
| `.brain/` | live coordination (presence, connections, journal, research) |
| `.context/` | handoffs, snapshots, briefs, ticket notes |
| `docs/` | design docs, ADRs, research outputs |
| feature plan status | via the mirrored `presence/` notes (HTML plans aren't indexable directly) |
| `.claude/skills/`, `~/.agents/skills/` | skills as *readable reference* |
| `~/.claude/projects/<encoded>/memory/` | Claude memories + `MEMORY.md` (canonical path = main worktree) |

## 7. Safety boundary ("safe vault for them to see any and all md's")

1. **Read-only over the broad set; write only to `.brain/`.** Agents browse
   memories/skills/plans/docs; they mutate only coordination notes. The write-MCP is scoped to
   `.brain/`.
2. **Secrets denylist on what gets indexed** — exclude `.env*`, `data/` (vault snapshots hold
   real content), `.git/`, `node_modules/`, anything credential-shaped. Reuse the existing
   denylist pattern (`data/canonical/tool_egress_denylist.yml`) → a `.brain/indexignore`.
3. **Local-only**, no network exposure. Threat model is "agent reads something stale," not
   exfiltration.

## 8. Self-evolution & governance (the agents develop this themselves)

The brain is **agent-run and self-improving**, governed so self-improvement doesn't become the
drift it's meant to prevent. **Principle: freedom to extend, governance on the core.**

- **Additive + local = free.** New research note, new helper skill, new connection — just do it.
- **Structural + shared = proposal-gated.** Schema changes, new note *types*, folder renames →
  drop a proposal in `.brain/_proposals/`, reconciled at `/wrap`. Mirrors the repo's
  ARCHITECTURE.md update-first hard-lock and `drift_debt` discipline.
- **The loop (reuses existing machinery):** friction → proposal note (or new helper skill) →
  surfaces in journal → reconciled at **`/wrap`** → the **navigation-standards skill (single
  source of truth) is updated once** → next session every agent picks it up. New brain-skills
  route through **`/learn-eval`** (its quality gate + Global-vs-Project decision).
- **Recursion to name:** the brain coordinates its own development the same way it coordinates
  features (proposals + journal + reconcile). Same mechanism, applied to itself.

## 9. Navigation-standards skill — DELIVERABLE #1 (the constitution)

Every agent invokes this **at session start** (SessionStart hook enforces it) so all four share
one protocol. It is the brain's constitution. It must define:

1. **Find** — read `INDEX.md`; query obra for what you need (*don't wait for harness injection*);
   follow `[[links]]`.
2. **Read** — on boot: your `presence/` note + open `connections/` touching your files; before
   touching a shared file, query who else is in it.
3. **Write** — frontmatter schema per note type; one-fact-per-note; append-only journal; link
   liberally; update presence at phase boundaries; create a connection note on discovering an edge.
4. **Announce** — the three moments (phase start, phase end/gate, pre-PR) and what to post.
5. **Evolve** — how to change the brain itself (the §8 proposal→reconcile path).

Everything else depends on agents sharing this protocol → it is built first.

## 10. Trigger model — where coordination is enforced

Layered: **hooks** for deterministic real-time guardrails, **GSD gate-steps** for plan-native
announcements, **`/wrap`** for durable reconciliation. The answer to "wrap or hooks?" is *both*.

| Moment | Mechanism | Behavior |
|---|---|---|
| Session start | `SessionStart` hook | invoke nav skill; surface active agents + connections touching this agent's files into context |
| Phase start / end (gate) | GSD gate-step (+ optional hook) | post phase-start / phase-end + "what's now unblocked for <feature>" to presence + journal |
| About to PR | `PreToolUse` hook on `gh pr create` / `git push` | identify branch + changed files; check vault/obra for overlaps with other active agents; announce; **warn on a live collision** |
| @mention waiting | optional `Stop` hook | block exit until an @mentioned agent acknowledges (the published ikangai pattern) |
| Session end | `/wrap` (extended) | commit `.brain/`; reconcile resolved connections; update presence; historian snapshot |

Hooks are shell scripts the harness runs — they hit the vault write-MCP / obra over HTTP (curl)
directly, no agent in the loop. Wire them via `settings.json` (the `/update-config` path).

## 11. Reuse inventory — do NOT reinvent

- **The Claude memory store is already a mini-Obsidian vault** (one-fact-per-file + frontmatter
  + `[[wiki-links]]` + `MEMORY.md`). Extend its conventions; don't invent a new schema.
- `src/parsers/parser_helpers.py:parse_wiki_links()`, the frontmatter regex, `split_h2_sections()`
  — generic markdown helpers, reusable verbatim if any in-repo parsing is needed.
- `slugify()` in `src/utils/text.py` — canonical id generator for note names / wiki-link targets.
- **`/wrap`** already does plan-audit, decision capture (`.context/`), memory consolidation,
  historian snapshot, handoff doc — the reconciliation hooks already exist; we *extend* phases.
- **`/learn-eval`** already gates + places new skills.
- **historian** agent already writes session-end snapshots to `.context/snapshots/`.
- The repo already has a **denylist convention** (`tool_egress_denylist.yml`).

## 12. Constraints & principles

- **Lightweight, but careful, intentional, dynamic, well-governed.** Don't over-build; don't
  under-govern. v1 sets the rules + seeds structure; agents grow it.
- **Immutability / single source of truth** — the read surface points at canonical files in
  place; never copy/duplicate memories, skills, or plans into the brain.
- **Simplicity first** (global rule) — no abstractions for single-use code; if it can be 50
  lines, don't write 200.
- Match existing repo conventions (pathlib, module-level loggers, etc.) for any scripts.

## 13. Open questions the workflow must resolve

1. **obra operational specifics** — verify: does it run fully headless (no Obsidian app)? install
   path / runtime (Node/TS)? how does it index multiple roots & re-index on change? what exactly
   are its MCP tools and their inputs? (This is the one external dependency to ground.)
2. **The vault write-MCP server** — pick a concrete **folder-reading, headless** Obsidian
   read/write MCP server (NOT one requiring the Obsidian desktop app + Local REST API plugin
   foregrounded). Name it, with evidence it's headless + maintained.
3. **Worktree write-path mechanics** — agents in sibling worktrees writing to
   `<main>/.brain/` via the MCP server: confirm the concrete wiring (one server process, fixed
   absolute vault path) and how `/wrap` commits those writes without racing concurrent commits
   to `main`.
4. **Exact `/wrap` and hook edits** — the precise step list to add to the `/wrap` skill and the
   exact `settings.json` hook entries (SessionStart, PreToolUse).
5. **Navigation-standards skill** — author the actual skill content (the §9 protocols).
6. **Sequencing** — the build order, with the nav skill as deliverable #1, plus what's seeded on
   day one vs. grown live.

## 14. What the workflow must produce

A **single, coherent, lightweight build plan** (markdown) that:
- Resolves every §13 open question with concrete, evidence-grounded answers.
- Specifies the vault layout, schemas, the two MCP servers + their config, the indexignore, the
  nav-standards skill content, the hook scripts, and the `/wrap`/`/learn-eval` integration.
- Sequences the build (nav skill first), names what's seeded vs grown.
- Has passed an **adversarial governance/drift critique** and a **simplicity/over-engineering
  critique**, with their findings folded in.
- Is buildable as personal tooling — no product code, no Neo4j, no architecture-first hard-lock.

---

### Appendix — research findings (evidence behind the decisions)

- **graphify (`safishamsi/graphify`, 66k★, MIT):** purpose-built "folder → agent-crawlable
  graph/wiki/MCP," reference repo `lucasrosati/claude-code-memory-setup` (766★) does this exact
  Claude-Code-memory use case. BUT it's an *indexer*, not a store; owns its own `graph.json`
  (Neo4j only an export target); `--neo4j-push` would collide with our invariants (irrelevant now
  — no Neo4j); 2 months old, single maintainer (596 vs 7 commits), ~2 releases/day breaking churn,
  already branch v8; loses Leiden community detection silently on Python 3.13. **Verdict: rejected
  as foundation; additive-future-only.**
- **obra/knowledge-graph (82★, MIT, TS, active):** reads an Obsidian vault in place →
  SQLite (sqlite-vec + FTS5) → ~10 MCP tools (semantic/keyword search, path-find,
  shared-connections, N-hop, subgraph, Louvain communities, betweenness bridges, PageRank). Chose
  SQLite because single-user/local. **Verdict: chosen** — intelligence-as-callable-MCP-tools is
  exactly the model; read-in-place fits a living vault.
- **Vault read/write surface:** `obsidian-local-rest-api` (2.4k★) + `mcp-obsidian` (3.9k★) are the
  maintained agent-access surfaces, **but Local REST API requires the Obsidian app running** —
  disqualifying for headless. Workflow must find a folder-reading headless alternative.
- **Prior-art patterns (validated, not experimental):** atomic-note-per-file + YAML-frontmatter-
  as-schema + an index + append-only event log + wiki-links-as-graph (jrcruciani/obsidian-memory-
  for-ai, "Obsidian Mind", agentmemory). Coordination = **blackboard** (Hearsay-II) +
  **append-only shared log + per-agent read cursor** + claim/status flags + git-worktree isolation.
  Anthropic's documented sweet spot: **2–4 concurrent agents** (we have 4). The dead end: HEmile's
  `obsidian-neo4j-graph-view` is abandoned (2021) and self-deprecated — do not resurrect it.
