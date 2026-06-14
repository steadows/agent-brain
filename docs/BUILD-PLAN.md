# Build Plan — The Agent Brain (`.brain/`)

> A shared, self-governing coordination vault so the concurrent feature-build agents pull each other's knowledge instead of waiting for the harness to push it. Personal dev-workflow tooling — never touches `src/`, the product, or Neo4j. No architecture-first hard-lock.

**Status:** ready to build. v1 is filesystem-only (zero servers, zero open dependencies). obra and the write-MCP are deferred to governed later phases — see the call in §1 and §6.

---

## 1. Decisions locked

| # | Decision | Resolution |
|---|---|---|
| D1 | **Vault home** | One vault at `<main>/.brain/` (absolute path: `~/research-dashboard/enterprise_research_dashboard/.brain`). Every agent in every worktree reads/writes *this one folder* — sharing comes from the **absolute path**, not from any server process. |
| D2 | **Read surface (v1)** | **Built-in `Read`/`Grep`/`Glob`.** They already span every md the brief §6 lists (`.brain/`, `.context/`, `docs/`, `.claude/skills/`, `~/.agents/skills/`, the memory store), are always-fresh, agent-initiated *pull* (the §2 driver), and zero-install. They cover the §6 *breadth* better than obra ever could (obra is single-root — source-verified). |
| D3 | **Write surface (v1)** | **Built-in `Write`/`Edit`** for presence/connection/research notes; **atomic shell append** (`printf '…' >> journal/$(date +%F).md`) for the journal. Scoping to `.brain/` is a nav-skill convention — same trust boundary as `src/`; the threat model is "stale read," not exfiltration (§7). |
| D4 | **obra (intelligence layer)** | **DEFERRED to Phase 2**, gated on the vault outgrowing grep. See the call below. |
| D5 | **Write-MCP (mcpvault)** | **DEFERRED to Phase 2**, ships with obra. Built-in write + convention covers v1. |
| D6 | **Governance principle** | "Freedom to extend, governance on the core." v1 mechanism is dead simple: friction → **journal line** → **Steve edits the nav skill at `/wrap`**. The nav-standards skill is the **single source of truth**; Steve is the **single reconciler**; **only the main session amends it** (no concurrent-wrap clobber). Formal `_proposals/` + drift-debt = Phase 3, only if friction warrants. |
| D7 | **Commit path** (resolves the two blocker contradictions) | **`.brain/` is committed by the MAIN-worktree session only**, path-scoped (`git -C <main> commit -- .brain/`), aborting if main is mid-rebase/merge. **Sibling worktrees never commit `.brain/`.** This kills both governance blockers (A1 contradiction, B3 sweeping LangGraph's main index). Live coordination never needs the commit — the shared folder *is* the channel; the commit is durability-only. |
| D8 | **Agent namespace** (resolves E1) | The four brain agents — `langgraph-runtime`, `workbench`, `graph`, `cockpit` — are identified by a gitignored **`.brain-agent` sentinel** at each registered worktree root. Every hook **allowlists on that file's presence** and no-ops in the other 9 worktrees and in unregistered sessions. |
| D9 | **Safety (v1)** | Three structural layers, no indexer needed: (a) nav-skill convention "write only under `.brain/`"; (b) built-in reads are read-only over the broad set; (c) git-tracked roots surface any stray write in `/wrap` Phase 4 `git status`. The secrets denylist / `indexignore` ships **with obra in Phase 2** (nothing is indexed in v1). |
| D10 | **Harness-independence (honest framing, F1)** | The brain makes context **content** pull-based. It does **not** remove harness reliance for **bootstrap**: an agent still depends on the `SessionStart` hook (harness) to learn the brain exists. State this plainly; do not over-promise. |

### The obra call (overriding the §4 "obra is chosen" lock — flagged for Steve, not taken silently)

**I am deferring obra and the write-MCP past v1.** The brief locks "obra is chosen," but that lock rests on two premises that source-reading disproved:

- The companion lock "**obra is read-only**" is **false** — obra ships 3 write tools (`kg_create_node`/`kg_annotate_node`/`kg_add_link`); the surfaces-obra slice verified this at source.
- The §6 model "**obra indexes a multi-root curated set**" is **not buildable** — obra is **single-root** (`KG_VAULT_PATH`, one path, throws if unset; `config.ts:15-23`). It physically cannot span `.brain/` + `.context/` + `docs/` + skills + memory in one instance.

When a locked decision's factual basis is wrong, it deserves re-examination, not blind execution. The simplicity case seals it: the vault is **11 notes on day one** (4 presence + 6 connections + 1 journal). obra's headline value (Louvain communities, betweenness bridges, PageRank) is *large-graph* intelligence — over a dozen nodes it produces noise, and semantic search over 11 notes loses to `grep`. obra also carries real cost to merely not corrupt itself: clone-pin-build (not on npm), dormant + effectively unlicensed, **stale-on-write until a manual `kg index`**, a per-worktree `kg.db`, a launcher script, and a 3-moment re-index cadence. **Dropping the MCP layer also deletes the design's two biggest open dependencies** — the nav-skill's "write-MCP tool names unbound" risk and the surfaces slice's "not buildable as written."

The §4 lock's *actual value* — "one shared folder, writes visible immediately, no commit/merge" — comes from the **absolute path**, which built-in `Write` to `<main>/.brain/` delivers identically. **obra becomes a clean, fully-specified additive Phase 2** (§6) the moment the vault outgrows grep. Steve can veto this and pull obra into v1; the v1 schema is designed to make that a pure addition.

---

## 2. Thin-slice v1 — the smallest build that pays off day one

The day-one payoff (brief §3/§14) is exactly two things: **the 6 seed connection notes visible to all agents**, and **the 3 announce moments firing**. v1 delivers both with a folder of markdown, one hook, two tiny `/wrap` edits, and the nav skill — **no servers**.

```
.brain/
  INDEX.md                    static [[links]] + 2 simple Dataview tables (human dashboard)
  .gitignore                  .DS_Store
  bin/session-start.sh        the one v1 hook (filesystem-direct, fail-open, allowlisted)
  presence/                   4 seeded (graph, cockpit, workbench, langgraph-runtime)
  connections/                6 seeded — THE PAYOFF
  journal/2026-06-13.md       seeded init line
  research/                   empty (schema documented; grown live)
```
Plus: `.claude/skills/navigation-standards/SKILL.md` (deliverable #1), `.claude/settings.json` + global `~/.claude/settings.json` (the SessionStart hook), `.brain-agent` sentinels in the 4 registered worktrees, and three surgical `/wrap` additions.

Everything else — obra, mcpvault, `_proposals/` governance, the plan-status auto-mirror parser, the `pre-pr` and `stop-mention` hooks, `indexignore` — is **deferred** (§6) and is a clean additive upgrade.

---

## 3. Build phases & tasks

Legend: **[v1]** ships now · **[v1.1]** fast-follow · **[P2]** deferred (obra) · **[P3]** deferred (formal governance).

### Phase 0 — Pre-flight  **[v1]**
- **0.1** Create skeleton: `.brain/{presence,connections,journal,research,bin}/`. → *Verify:* `ls -d .brain/presence .brain/connections .brain/journal .brain/bin` all exist.
- **0.2** Write `.brain/.gitignore` containing `.DS_Store`; add `/.brain-agent` to the repo root `.gitignore`. → *Verify:* `git check-ignore .brain-agent` returns the path.
- **0.3** Seed the `.brain-agent` sentinel (one line = the slug) in each of the 4 registered worktree roots: `langgraph-runtime` → `<main>`, `graph` → `…-dt520`, `cockpit` → `…-cockpit`, `workbench` → `…-workbench`. → *Verify:* `cat <each>/.brain-agent` prints its slug; the other 9 worktrees have none.

### Phase 1 — Navigation-standards skill — DELIVERABLE #1  **[v1]**
- **1.1** Write `~/research-dashboard/enterprise_research_dashboard/.claude/skills/navigation-standards/SKILL.md` (full content below). Written against **built-in tools** (deletes the unbound-tool risk); a one-line "Tool binding" addendum swaps to obra/mcpvault in P2 — the **note schema is the stable contract, not the tool name**. → *Verify:* file exists; frontmatter has `name` + `description`; `/navigation-standards` is loadable.

<details><summary><strong>SKILL.md content (ready to write)</strong></summary>

````markdown
---
name: navigation-standards
description: The Agent Brain constitution — the Find / Read / Write / Announce / Evolve protocol every concurrent coding agent follows to coordinate through the shared .brain/ vault. Auto-invoked at session start. Read this first, every session.
---

# Agent Brain — Navigation Standards (the constitution)

You are one of several Claude Code agents building separate features in separate git worktrees
**at the same time**. You cannot see the other agents' working trees. You coordinate through
**one shared folder** at `~/research-dashboard/enterprise_research_dashboard/.brain/`
— the same absolute path from every worktree. Notes you write are visible to the others the
instant they hit disk — no commit, no merge.

**Honest scope (don't over-promise).** The brain makes context *content* pull-based — you query
on-disk markdown instead of waiting for the harness to inject it. It does **not** remove the
harness from *bootstrap*: the SessionStart hook is what tells you the brain exists and who else
is active. Content = pull; discovery = still a harness hook.

**Knowledge is pull, not push.** When you have a question — "who else edits `agent.ts`?",
"what's Cockpit's phase?", "did anyone research Exa?" — **go read the brain yourself.**

**Scope limit:** the brain shares *knowledge*, not *execution*. It never touches `src/`, the
product, or Neo4j. You write coordination notes; you never copy memories, skills, plans, or
docs into it — point at them by `[[link]]` or path.

---

## Your identity this session
- **Agent id** = the one line in `<your-worktree>/.brain-agent` → one of `langgraph-runtime`,
  `workbench`, `graph`, `cockpit`. If that file is absent, you are **not** a registered brain
  agent — do nothing with the brain.
- **Your presence note** = `.brain/presence/<agent-id>.md`.
- **"Your files"** = the repo-root-relative paths in your presence `touches[]`.

## Tool binding (v1 = built-in tools)
- **Read/Find = built-in `Grep` / `Glob` / `Read`** over `.brain/` (and the broader md set:
  `.context/`, `docs/`, `.claude/skills/`, the memory store). Always fresh, agent-initiated.
- **Write = built-in `Write` / `Edit`**, and an **atomic shell append** for the journal:
  `printf -- '- %s %s …\n' "$(date +%H:%M)" "<agent-id>" >> .brain/journal/$(date +%F).md`.
  Only ever write **under `.brain/`**. Never write anywhere else through these.
- *(A later build may swap Read→obra `kg_*` and Write→a scoped MCP. The note schemas below are
  the contract; the tools may change.)*

---

## 1. FIND
1. **Start at the index:** read `.brain/INDEX.md` (active agents, open connections).
2. **Question by keyword:** `Grep` for the path / contract / feature in `.brain/`.
3. **Open a hit and chase its `[[wiki-links]]`** — they are the graph edges. `Read` the linked notes.
4. **Broader md:** the same `Grep`/`Read` reach `.context/`, `docs/`, skills, the memory store.

## 2. READ — boot sequence (run at session start, before touching code)
1. **Read your own `presence/<agent-id>.md`.** Confirm branch, phase, `touches[]`. Fix if stale.
2. **Pull open connections touching you:** `Grep` `connections/` for your agent-id and each path
   in `touches[]`; read every hit with `status: open|watch`. (The SessionStart hook pre-surfaces
   these — re-query if you change scope mid-session.)
3. **Before touching a shared file, ask who else is in it.** `Grep` that path across
   `presence/*.md`; if another **active** agent (`status` not `done|idle`, `updated` within ~2
   days) lists it, read their connection note — and if none exists, **create one** before editing.
4. **Your plan status lives in your presence note** (HTML `*_GSD_PLAN.html` plans aren't grep-
   friendly as state). You wrote it; trust it. It is refreshed at `/wrap`.

## 3. WRITE — coordination notes only, under `.brain/`
Rules for every note: **one fact per note**; filename = `slugify(<title>)`; wiki-link targets
match filenames; **frontmatter = state, body = prose, `[[links]]` = edges**; never paste
canonical content — `[[link]]` it. **Basename must be globally unique inside `.brain/`** (a
connection and a research note may never both slug to `cytoscape`).

**presence/`<agent-id>`.md** — your live status (one file per agent → zero contention). Update at
every phase boundary and when `touches[]`/`blocked_on` changes. `Edit` the frontmatter; don't recreate.
```yaml
---
type: presence
agent: graph
feature: "Graph Explorer (/graph)"
worktree: ~/research-dashboard/enterprise_research_dashboard-dt520
branch: feat/dt-520-graph-pg1-read-surface
plan: GRAPH_FEATURE_GSD_PLAN.html
jira: DT-520
phase: PG1
status: active            # active | blocked | idle | done
blocked_on: []            # [[connection]] slugs and/or external ids e.g. GLOBE-17599
touches:                  # repo-root-relative paths (must match `git diff --name-only`)
  - src/api/routes/graph.py
updated: 2026-06-13
---
```

**connections/`<slug>`.md** — one note per cross-feature edge (the blackboard). **Search before
you create** (`Grep connections/` for the feature pair) — if a note already links both features,
**append to it, don't make a second**. Flip `status: open → resolved` only at `/wrap`; **never
rename a connection file** (it orphans every `[[link]]`).
```yaml
---
type: connection
features: [graph, cockpit]
status: open              # open | watch | resolved
severity: high            # high | medium | low
kind: divergence          # divergence | contract | gate-handoff | shared-file
files: [web/src/app/_views/]
blocks: []
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
```

**journal/YYYY-MM-DD.md** — append-only comms timeline. **Append only** (atomic shell `>>`);
never edit prior lines:
```
- 14:20 graph — PG1 started; touching src/api/routes/graph.py [[api-exploration-architecture-edge]]
```

**research/`<slug>`.md** — a compact summary + a pointer (path) to the full gitignored
`docs/research/` doc. If a note already covers your topic, **read it instead of re-researching.**

## 4. ANNOUNCE — three moments, posted without being asked
| Moment | Write |
|---|---|
| **Phase start** | `Edit` presence (`phase`, `status: active`, refresh `touches[]`, `updated`); append a journal line "phase X started; touching …". |
| **Phase end / gate** | `Edit` presence (next phase, or `status` change); append a journal line stating the phase is done **and "what's now unblocked for `<feature>`"** — name any downstream feature whose blocker you cleared, `[[link]]` its presence note. If a `gate-handoff` connection is now satisfiable, update it. |
| **About to PR** | For each changed shared path, `Grep presence/*.md`; if another **active** agent's `touches[]` lists it, that's a **live collision** — append a journal warning, create/refresh a `connection`, and agree merge order before pushing. Then append a journal line announcing the PR + its changed surface. *(A `pre-PR` hook will later backstop this; announce yourself regardless.)* |

## 5. EVOLVE — changing the brain itself
**Freedom to extend, governance on the core.**
- **Additive + local = just do it.** New connection, new research note, new journal line, a
  presence value change, a connection `status` flip — no permission needed.
- **Structural + shared = journal it, Steve reconciles.** Changing a frontmatter **field/enum**,
  adding a note **type**, renaming a folder, or editing **this skill's protocol** → **do not just
  do it.** Append a journal line: the friction + the change you want. Steve reconciles at `/wrap`
  by editing this skill (the single source of truth). **Only the main session amends this skill.**
- **One change touches four consumers in lockstep.** A schema field/enum lives in *four* places:
  this skill, `bin/session-start.sh`'s `sed`/`grep`, `INDEX.md`'s Dataview, and the seed notes.
  "Accept a schema change" means updating **all four + migrating existing notes** as one edit.
- **New brain helper-skills route through `/learn-eval`**, and **default to Project scope**
  (`<repo>/.claude/skills/learned/`) — they encode *this* repo's `.brain/` layout and don't
  transfer. Override `/learn-eval`'s "when in doubt, Global" default unless the skill names no
  `.brain/` path. Helper skills carry **automation only, never a convention** — conventions go in
  this skill via the journal→/wrap path first.
````
</details>

### Phase 2 — Seed the vault  **[v1]** (the payoff)
- **2.1** Write the 4 `presence/*.md` notes (§5). → *Verify:* `ls .brain/presence/*.md` = 4; each has `type: presence` + flat frontmatter.
- **2.2** Write the 6 `connections/*.md` notes (§5). → *Verify:* 6 files; each body `[[link]]`s the presence notes on both sides.
- **2.3** Write `journal/2026-06-13.md` with the init line. → *Verify:* file exists; one `- HH:MM …` line.
- **2.4** Write `INDEX.md` — static `[[links]]` header + **two plain Dataview tables** (active agents; open connections), `SORT updated DESC` (no `choice()` trick — human can eyeball severity). → *Verify:* tables render in Obsidian; raw `[[presence]]`/`[[connections]]` links present for grep.

### Phase 3 — SessionStart hook  **[v1]**
- **3.1** Write `.brain/bin/session-start.sh` (below): allowlist on `.brain-agent`; surface other **live** agents (skip `updated` > ~2 days, E2) + open/watch connections touching this agent; fail-open; ~35 lines, jq-free, filesystem-direct. → *Verify:* run in a registered worktree → prints agents + connections; run where `.brain-agent` is absent → no output, exit 0.
- **3.2** Write `.claude/settings.json` with the `SessionStart` entry (absolute script path). Mirror the identical block into `~/.claude/settings.json` for immediate day-one coverage of all 4 in-flight worktrees (safe — the script self-gates and no-ops everywhere else). → *Verify:* a fresh session in a registered worktree emits the nav-skill directive; a session in `…-dt453` emits nothing.

<details><summary><strong>session-start.sh (ready to write)</strong></summary>

```sh
#!/bin/sh
# SessionStart hook. Inject nav-skill directive + live agents + connections
# touching this agent. Allowlisted to registered brain worktrees. Fail-open.
set -u
BRAIN="~/research-dashboard/enterprise_research_dashboard/.brain"
CWD=$(pwd)
[ -d "$BRAIN/presence" ] || exit 0
[ -f "$CWD/.brain-agent" ] || exit 0          # allowlist: only registered worktrees (E1)
ME=$(head -1 "$CWD/.brain-agent")
[ -n "$ME" ] || exit 0
fld() { sed -n "s/^$1:[[:space:]]*//p" "$2" | head -1; }
fresh() { # arg=file; true if updated within ~2 days (E2 liveness)
  u=$(fld updated "$1"); [ -n "$u" ] || return 1
  d=$(( ($(date +%s) - $(date -j -f %Y-%m-%d "$u" +%s 2>/dev/null || echo 0)) / 86400 ))
  [ "$d" -le 2 ]
}
AGENTS=""
for f in "$BRAIN"/presence/*.md; do
  [ -e "$f" ] || break
  a=$(fld agent "$f"); [ "$a" = "$ME" ] && continue
  s=$(fld status "$f"); case "$s" in done|idle) continue ;; esac
  fresh "$f" || continue
  AGENTS="${AGENTS}  - ${a} [$s] $(fld branch "$f") @ $(fld phase "$f")
"
done
CONNS=""
for f in "$BRAIN"/connections/*.md; do
  [ -e "$f" ] || break
  case "$(fld status "$f")" in open|watch) ;; *) continue ;; esac
  grep -qiF "$ME" "$f" || continue
  CONNS="${CONNS}  - [$(fld severity "$f")] $(fld kind "$f"): $(basename "$f" .md)
"
done
printf '%s\n' "AGENT-BRAIN // run the \`navigation-standards\` skill NOW before other work.
You are agent: ${ME}.
Other live agents:
${AGENTS:-  (none)}
Open connections touching you:
${CONNS:-  (none)}"
exit 0
```
</details>

### Phase 4 — `/wrap` integration  **[v1]** — three surgical edits (full text in §4)
- **4.1** Extend **`## Phase 1 — Plan Audit`** (after `### HTML plans (e.g. \`*GSD_PLAN.html\`)`): the agent hand-writes its own `presence/<agent>.md` (`phase`/`status`/`blocked_on`/`updated`) from the `gsd-state` it just audited — **no new parser** (it already knows its phase). Flip any `connections/*.md` settled this session `open → resolved`. → *Verify:* a /wrap run updates the agent's presence + resolves a settled connection.
- **4.2** Extend **`## Phase 4 — Git Hygiene`**: **main-session-only** `chore(brain):` commit, path-scoped (`git -C <main> commit -- .brain/`), abort if `<main>/.git/rebase-merge|MERGE_HEAD` present; siblings skip entirely (D7). → *Verify:* main /wrap → one `chore(brain):` commit touching only `.brain/`; sibling /wrap → no brain commit.
- **4.3** Add one line to **`## Phase 6 — /learn`**: brain helper-skills route through `/learn-eval`, **default Project**. → *Verify:* line present.

### Phase 5 — pre-PR overlap hook  **[v1.1 fast-follow]**
- **5.1** Write `.brain/bin/pre-pr-overlap.sh` (`PreToolUse`/`Bash`, triggers on `git push`/`gh pr create`): diff changed files vs `merge-base main`, `grep -Ff` against other **live** agents' presence `touches[]`; on a hit, **atomic `>>` journal warning** + surface to the model. **Default non-blocking** (`permissionDecision: allow` + `additionalContext`) so it never pauses Steve's push; the blocking `ask` variant is a documented one-line knob. Hook journal writes use shell `>>` (atomic O_APPEND) — same lane as agent appends, so no clobber (B1). → *Verify:* stage a file another agent's presence claims, attempt `git push` → journal warning appears, push proceeds.

### Phase 6 — obra intelligence layer  **[P2, deferred — gated on vault outgrowing grep]**
Clean additive upgrade; nothing in v1 blocks it. When grep demonstrably stops scaling:
- Clone + pin-SHA + build obra under `~/.brain/obra-knowledge-graph` (not on npm; dormant, no LICENSE → treat as local personal tooling). Embedder is local (`Xenova/all-MiniLM-L6-v2`, transformers.js) — **headless, credential-free, offline** after a one-time ~25MB fetch.
- `scripts/brain/obra-mcp.sh` launcher → per-worktree `KG_DATA_DIR=$HOME/.brain-index/<worktree>` (no SQLite write contention), `KG_VAULT_PATH=<main>/.brain` (absolute).
- Add the write-MCP (`@bitbonsai/mcpvault`, 1.4k★/MIT/headless) **only** for its `update_frontmatter` — **gate the build on a 5-min `O_APPEND` smoke test** (B1); if append is read-modify-write, give it a separate journal lane.
- Checked-in `.mcp.json` (materializes in every worktree); register obra read + scoped mcpvault write.
- **`kg index` must run in the SessionStart hook itself** before pre-warming (resolves A2 — no slice owned it; it's credential-free/offline so this is cheap) and at `/wrap`.
- **`indexignore` denylist gate** (resolves A3): a wrapper greps the to-be-indexed `.md` set against a `.brain/indexignore` reusing the `tool_egress_denylist.yml` pattern (flat YAML, comment header, `BRAIN_INDEXIGNORE` env override, case-insensitive substring incl. `millerknoll`/`herman miller`) and **refuses to index on a hit**. obra reads no ignore file itself (source-verified) — *our* index driver is the only enforcement, so document "always index via the driver."
- Swap the nav-skill **Find→`kg_*`** and **Write→mcpvault**; add the freshness caveat (within a session, use `kg_search fulltext:true` — semantic/community metrics lag until `kg index`). **Correct the constitution: "one shared *folder*; your obra index is a per-session cache that lags other sessions until `kg index`"** (A4 — never assert "one process").
- **Withhold obra's 3 write tools** from the agent allowlist (D9/§5) — mcpvault is the only writer.

### Phase 7 — formal `_proposals/` governance  **[P3, deferred — gated on brain-evolution friction]**
Only if the lightweight journal→/wrap loop proves insufficient: add a `proposal` note type + lifecycle, a new `## Phase 3.5 — Brain Reconcile` in `/wrap`, and a **per-agent** drift-debt stop (scoped to *your own* ≥3 open proposals; excludes stale/inactive authors and proposals older than N days — D1/D2). Connections get a **liveness/TTL** auto-resolve signal ("both features' branches merged → resolved") so an absent agent can't wedge the shared gate.

---

## 4. Governance & self-evolution

**The v1 model (lightweight, well-governed):**
- **Additive + local = free.** New connection / research note / journal line / presence value / connection `status` flip — agents just do it.
- **Structural + shared = gated, but the gate is one journal line.** Field/enum/note-type/folder/protocol changes → the agent journals the friction + proposed change; **Steve reconciles at `/wrap` by editing the nav skill.** No proposal note type, no lifecycle enum, no drift-debt counter, no blast-radius template in v1 — that's ARCHITECTURE.md's hard-lock cloned onto coordination notes for a one-owner vault (Phase 3 if ever).
- **Single source of truth = the nav-standards `SKILL.md`. Single reconciler = Steve. Single writer of the constitution = the main session only** (resolves C2 — concurrent wraps can't clobber the skill).
- **Schema lockstep (resolves C1).** A schema lives in four consumers: nav-skill prose, `session-start.sh` grep fields, `INDEX.md` Dataview, and seed notes. "Change the schema" = edit **all four + migrate notes** as one change. v1 keeps `INDEX.md` to two plain tables to minimize this surface.

**Race/drift fixes folded in from the governance critique:**

| Critique | Fix adopted |
|---|---|
| **A1 / B3 (blockers)** — commit specified two ways; sibling commit sweeps LangGraph's main index | **Main-session-only, path-scoped commit** (`git -C <main> commit -- .brain/`, abort if mid-op). Siblings never commit `.brain/`. (D7) |
| **A2** — `kg index` owned by nobody | N/A in v1 (no obra). In P2 the SessionStart hook runs it explicitly. |
| **A3** — indexignore driver orphaned | N/A in v1 (no indexer). Ships *as* the index-driver wrapper in P2. |
| **A4** — constitution says "one process" (false) | v1 says "one shared **folder**"; P2 adds "your obra index is a per-session lagging cache." |
| **B1** — journal lost-update / two writers | v1 journal writes use **atomic shell `>>`** (agents and the pre-PR hook share the same O_APPEND lane). P2 mcpvault append gated on an `O_APPEND` smoke test. |
| **B2** — connection double-create/split | Nav-skill READ mandates **search-before-create**; **create-if-absent → else append**; never rename on resolve. |
| **C1** — schema quadruplicated | "Accept" = update all four consumers + migrate, atomically (above). |
| **C2 / C3** — concurrent wraps edit the skill | **Only the main session amends the skill / commits brain.** Single writer. |
| **C4** — mixed-schema during adoption | Schema changes are **additive-within-session**; renames get a one-session deprecation. |
| **D1 / D2** — abandoned proposals wedge a global drift-debt stop | No global counter in v1. Phase 3's stop is **per-agent**, excludes stale authors; connections get TTL/auto-resolve. |
| **E1** — 13 worktrees, design assumes 4 | Hooks **allowlist on `.brain-agent`**; no-op everywhere else. (D8) |
| **E2** — stale presence → false collisions | Liveness: presence with `updated` > ~2 days is treated non-live by the hook and the nav-skill collision check. |
| **E3** — down write-MCP fails quiet | N/A in v1 (write path is built-in `Write`/`Edit` — can't be "down"). P2 adds a degraded-mode fallback + loud journal line. |
| **F1** — harness-independence over-promised | Plan + nav skill state plainly: **content = pull; discovery (and P2 freshness) = harness hook.** |
| **G4** — `/learn-eval` Global default conflicts | Nav-skill EVOLVE overrides it: brain helpers **default Project** unless they name no `.brain/` path. |

**Exact `/wrap` edits** (quoting the real headers from `~/.claude/skills/wrap/SKILL.md`):

> **Extend `## Phase 1 — Plan Audit`** — add a sub-step after `### HTML plans (e.g. \`*GSD_PLAN.html\`)`:
> *`### Brain: mirror status into presence/`* — From the `gsd-state` you just audited, write this agent's current `phase`, `status`, `blocked_on[]`, `updated` into `<main>/.brain/presence/<agent>.md` (you already know them — no parser). Flip any `connections/*.md` whose edge settled this session `open → resolved` and append a one-line resolution. The presence/connection **schemas are fixed** — changing a field is a journaled, Steve-reconciled change, not a silent edit.

> **Extend `## Phase 4 — Git Hygiene`** — add a sub-step:
> *`### Brain: commit .brain/`* — **Only if this is the main worktree session.** Abort if `<main>/.git/rebase-merge` or `MERGE_HEAD` exists. Stage path-scoped and commit standalone: `git -C ~/research-dashboard/enterprise_research_dashboard add .brain/ && git -C … commit -- .brain/ -m "chore(brain): …"`, then rebase onto fresh `origin/main` + **fast-forward only, never force-push** (shared-main discipline). **Sibling-worktree sessions skip this step.** The live MCP-less folder already shared every write; this commit is durability-only.

> **Extend `## Phase 6 — /learn`** — add one line:
> A brain helper-skill candidate routes through **`/learn-eval`** and **defaults to Project scope** (`<repo>/.claude/skills/learned/`), overriding `/learn-eval`'s "when in doubt, Global" default unless the skill names no `.brain/` path.

**`/learn-eval` integration:** unchanged machinery; the Project-default override lives **in the nav skill's EVOLVE section** (we don't edit the global `/learn-eval` command). The nav-standards skill is the one **hand-authored** skill governed by journal→/wrap, never by `/learn-eval`.

---

## 5. Seeded content (drop-in, day one)

### `presence/` (4 notes)

**`presence/graph.md`**
```yaml
---
type: presence
agent: graph
feature: "Graph Explorer (/graph)"
worktree: ~/research-dashboard/enterprise_research_dashboard-dt520
branch: feat/dt-520-graph-pg1-read-surface
plan: GRAPH_FEATURE_GSD_PLAN.html
jira: DT-520
phase: PG1
status: active
blocked_on: []
touches:
  - src/api/routes/graph.py
  - web/src/app/_views/
updated: 2026-06-13
---
PG0 (architecture + contract freeze) merged; **PG1** LLM-free GET endpoints in worktree, not merged.
Edges touching my files: [[api-exploration-architecture-edge]], [[label-entity-id-convention]],
[[cytoscape-shared-wrapper-divergence]].
```

**`presence/cockpit.md`**
```yaml
---
type: presence
agent: cockpit
feature: "Project Cockpit (DT-238)"
worktree: ~/research-dashboard/enterprise_research_dashboard-cockpit
branch: feat/dt-513-cockpit-mini-graph
plan: docs/plans/COCKPIT_INTELLIGENCE_GSD_PLAN.html
jira: DT-238
phase: P3
status: active
blocked_on: [[[composer-handoff-gate]]]
touches:
  - web/src/app/_views/cockpit-graph-canvas.tsx
  - web/src/lib/agent.ts
updated: 2026-06-13
---
P0–P1 done; **P3** mini-graph in worktree (built `cockpit-graph-canvas.tsx` importing cytoscape
directly). P4 "Send to Workbench" blocked on Workbench Composer (1.9). Edges:
[[cytoscape-shared-wrapper-divergence]], [[agent-ts-shared-contract]], [[composer-handoff-gate]],
[[label-entity-id-convention]].
```

**`presence/workbench.md`**
```yaml
---
type: presence
agent: workbench
feature: "Workbench (DT-470)"
worktree: ~/research-dashboard/enterprise_research_dashboard-workbench
branch: feat/dt-487-board-composer
plan: DT-470_GSD_PLAN.html
jira: DT-470
phase: P1
status: active
blocked_on: []
touches:
  - web/src/lib/agent.ts
updated: 2026-06-13
---
**P1** 9/13; building Composer (1.9) and Board (1.10). Composer 1.9 is the gate Cockpit P4 waits
on. Edges: [[agent-ts-shared-contract]], [[composer-handoff-gate]].
```

**`presence/langgraph-runtime.md`**
```yaml
---
type: presence
agent: langgraph-runtime
feature: "LangGraph agent runtime (DT-206)"
worktree: ~/research-dashboard/enterprise_research_dashboard
branch: main
plan: LANGGRAPH_RUNTIME_GSD_PLAN.html
jira: DT-206
phase: P4
status: blocked
blocked_on: [GLOBE-17599]
touches: []
updated: 2026-06-13
---
P0–P2 done; **P4** 4 tasks (4.4–4.7) **BLOCKED on GLOBE-17599**; P5 gated on P4. Develops on
`main` itself — this is the only session that commits `.brain/`. Edges:
[[globe-17599-external-blocker]], [[api-exploration-architecture-edge]].
```

### `connections/` (6 notes — the payoff)

**`connections/cytoscape-shared-wrapper-divergence.md`**
```yaml
---
type: connection
features: [graph, cockpit]
status: open
severity: high
kind: divergence
files: [web/src/app/_views/, web/src/app/_views/cockpit-graph-canvas.tsx]
blocks: []
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
Graph PG2 owns the shared Cytoscape wrapper in `web/src/app/_views/` (ADR-0003, **D-G7**), but
[[cockpit]] P3 already shipped `cockpit-graph-canvas.tsx` importing `cytoscape` directly — neither
agent knew. **Whoever merges second collapses onto the shared wrapper.** Owners: [[graph]]
(wrapper) · [[cockpit]] (consumer). Related: [[label-entity-id-convention]].
```

**`connections/agent-ts-shared-contract.md`**
```yaml
---
type: connection
features: [workbench, cockpit]
status: watch
severity: medium
kind: shared-file
files: [web/src/lib/agent.ts]
blocks: []
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
`web/src/lib/agent.ts` is edited by **both** [[workbench]] (P0, on main) and [[cockpit]] (P4) on
separate branches — silent merge-order dependency. Coordinate before either pushes a change to it.
```

**`connections/composer-handoff-gate.md`**
```yaml
---
type: connection
features: [cockpit, workbench]
status: open
severity: high
kind: gate-handoff
files: []
blocks: [cockpit]
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
[[cockpit]] P4 ("Send to Workbench") cannot start until [[workbench]] task **1.9 (the Composer)**
reading the handoff merges. Workbench: announce when 1.9 lands so Cockpit P4 unblocks.
```

**`connections/label-entity-id-convention.md`**
```yaml
---
type: connection
features: [graph, cockpit]
status: watch
severity: medium
kind: contract
files: [graph_envelopes.py]
blocks: []
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
The `Label:entity_id` invariant is shared by [[graph]] (`graph_envelopes.py`) and [[cockpit]]
(C-2). Change one side → update the other. Per-label uniqueness, label-scoped edges.
```

**`connections/api-exploration-architecture-edge.md`**
```yaml
---
type: connection
features: [graph, cockpit, langgraph-runtime]
status: watch
severity: medium
kind: contract
files: []
blocks: []
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
All three backends route Neo4j access through the **`api → exploration`** ARCHITECTURE edge.
**Do not add a second parallel edge.** Touches [[graph]], [[cockpit]], [[langgraph-runtime]].
```

**`connections/globe-17599-external-blocker.md`**
```yaml
---
type: connection
features: [langgraph-runtime]
status: open
severity: high
kind: gate-handoff
files: []
blocks: [langgraph-runtime]
discovered: 2026-06-13
resolved: null
updated: 2026-06-13
---
[[langgraph-runtime]] P4 tasks 4.4–4.7 are **BLOCKED on external ticket GLOBE-17599**; P5 is gated
on P4. External — flip to `resolved` only when GLOBE-17599 clears.
```

### `journal/2026-06-13.md`
```yaml
---
type: journal
date: 2026-06-13
---

- 14:30 brain — initialized; seeded 4 presence + 6 connections. Agents: query the brain yourself, pull not push.
```

### `INDEX.md`
```markdown
# Brain Index
Run the **navigation-standards** skill at session start. Query the brain with built-in
`Grep`/`Read` — these Dataview blocks are the *human* dashboard (agents don't need them).
Folders: [[presence]] · [[connections]] · [[journal]] · [[research]]

## Active agents
```dataview
TABLE feature AS "Feature", phase AS "Phase", status AS "Status", branch AS "Branch", blocked_on AS "Blocked on", updated AS "Updated"
FROM "presence"
WHERE type = "presence" AND status != "done"
SORT updated DESC
```

## Open connections
```dataview
TABLE severity AS "Severity", kind AS "Kind", features AS "Features", files AS "Files", updated AS "Updated"
FROM "connections"
WHERE type = "connection" AND status != "resolved"
SORT updated DESC
```
```

---

## 6. Cut / deferred (so nothing creeps back silently)

**Cut from v1 (deferred to a named phase):**
- **obra + the whole MCP read layer** → **P2**, gated on the vault outgrowing grep. (Source-verified single-root + stale-on-write + clone/pin/build cost; graph algos are noise over 11 nodes; built-in grep is fresher and broader.)
- **Write-MCP (mcpvault)** → **P2**, ships with obra. Built-in `Write`/`Edit` + atomic `>>` covers v1; sandbox-scoping is theater under the "stale read, not exfiltration" threat model.
- **The entire `_proposals/` subsystem** (proposal note type, lifecycle enum, Friction/Blast-radius/Rollback template, the 12-row free/gated table, the global drift-debt stop) → **P3**, only if brain-evolution friction warrants. v1 governance = journal line → Steve edits the nav skill.
- **`stop-mention.sh` hook** → cut indefinitely. Author-admitted premature ("ship only once the @mention convention lands"); it's the only hook that can block exit.
- **Plan-status auto-mirror parser** (the `/BLOCKED|GLOBE-\d+/i` prose-scan derivation over `gsd-state`) → cut. The agent already knows its phase; it hand-writes presence at `/wrap`. (P2 may auto-derive.)
- **`indexignore` + pre-index denylist driver** → **P2** (ships as obra's index-driver wrapper). Nothing is indexed in v1, so there is nothing to gate.
- **The `choice()`-rank Dataview sort trick** → cut. Load-bearing only for a human dashboard; plain `SORT updated DESC` is enough.
- **2nd obra instance on the memory store** → cut. `MEMORY.md` already indexes it and memories are already injected.
- **The git-race choreography** (`.gitattributes merge=union`, elaborate rebase ceremony specific to `.brain/`) → cut. Main-session-only commit + existing shared-main discipline suffices; if a rare conflict happens, Steve resolves it.
- **`research/` seeding** → folder documented, **empty** day-one (grown on first real "almost re-researched X" moment).

**Deferred but fast-follow:**
- **`pre-pr-overlap.sh`** → **v1.1**, **non-blocking** by default (`allow` + `additionalContext`); blocking `ask` is a documented knob.

---

## 7. Open risks

1. **obra is the biggest unverified dependency — but v1 doesn't touch it.** If/when P2 lands: it's dormant + effectively unlicensed (v0.1.0, `license: none`, no LICENSE) → **pin a SHA, vendor the clone, treat as local personal tooling**. Headless/offline is *source-confirmed* (local MiniLM embedder), so the headless requirement (§13-Q1) is met. De-risk before relying: run `kg index` once on `.brain/` and confirm the model fetch + offline operation.
2. **mcpvault `update_frontmatter` / append atomicity (P2)** — load-bearing for presence updates and the journal; internals are from grounding, not source-read. **Gate the P2 build on a 5-min `O_APPEND` + frontmatter-update smoke test**; `smith-and-web/obsidian-mcp-server` (`append-to-section`) is the drop-in fallback. (v1 avoids this entirely via built-in writes + shell append.)
3. **v1 journal concurrency** — agents append via atomic shell `>>` (O_APPEND, safe). The residual risk is two agents editing the *same presence file* — but presence is one-file-per-agent, so there is no cross-agent contention. Low, acceptable for 4 human-paced agents.
4. **Day-one settings distribution** — a project `.claude/settings.json` only reaches a feature branch after merge. Mitigation: install the SessionStart hook in **global `~/.claude/settings.json`** now (safe — the script self-gates on `.brain-agent` and no-ops in the other 9 worktrees and all other projects); make project `.claude/settings.json` the canonical home going forward.
5. **`.brain-agent` sentinels must be seeded in all 4 registered worktrees** (Phase 0.3) or that agent silently won't participate. Verify each before declaring v1 live.
6. **Schema-lockstep discipline is manual in v1** — a field/enum change must hit nav-skill + `session-start.sh` grep + INDEX.md + seeds together. v1 keeps the surface small (two plain Dataview tables); P3 formalizes it if the brain's own evolution generates churn.
7. **Harness-bootstrap dependency is real and stated, not hidden** (D10/F1) — if the SessionStart hook doesn't fire, an agent won't know the brain exists. That is the honest boundary of "harness-independent knowledge": content is pull, discovery is still a hook.