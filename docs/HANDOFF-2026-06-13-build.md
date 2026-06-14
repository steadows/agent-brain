# Handoff — Agent Brain v1: ready to BUILD (hit "go")

> **Read me cold.** The Agent Brain is fully designed, reviewed, consistency-checked, and
> build-ready. Next session: Steve says "go" → execute the build below. The **authoritative build
> instructions are `docs/BUILD-SPEC.md`** — follow it section by section; this handoff
> is the execution plan + guardrails so you don't re-derive anything.

## TL;DR
Build the **Agent Brain** — a shared markdown coordination vault (`.brain/`) so the 4 concurrent
feature-agents (graph, cockpit, workbench, langgraph-runtime) see each other, share knowledge, and
surface cross-feature gotchas. **v1 = filesystem-only (no servers, no MCP).** Build the reusable tool
at **`~/agent-brain`** (plain folder, **no git**), then **`brain init`** into THIS project. Seed the 4
real features. **Hold the live machine-global step (`brain install` / hooks) for Steve's explicit ok.**

## The three durable docs (all in `.context/`)
- **`BUILD-SPEC.md`** — AUTHORITATIVE build instructions (file manifest, the `brain`
  command, the precise identity rule §2a, schemas, 2 hooks, governance gauntlet, seed content,
  verification). **Build from this.** All review fixes A–L are already folded in.
- **`STRATEGY.md`** — design rationale + decision log (the *why*; principles M1–M10).
- **`REVIEW.md`** — the multi-agent review (what was caught and fixed).

## Hit "go" — build steps, in order
1. **`mkdir ~/agent-brain`** (NO `git init` — Steve will add it to his personal repo later). Write the
   tool there per BUILD-SPEC §1–§7: the `brain` shell script (`bin/brain`) and `templates/`
   (`presence.md`, `connection.md`, `journal.md`, `research.md`, `INDEX.md` [static map, NOT Dataview],
   `navigation-standards.SKILL.md`).
2. **`brain init`** in this project (`~/research-dashboard/enterprise_research_dashboard`)
   → scaffolds `.brain/`, copies the tool in, seeds the **4 presence notes + 6 connections** (BUILD-SPEC
   §9 — apply the corrected transforms: `owns_branches` per §2a, legacy `kind` remap, static INDEX, ISO
   timestamps, `blocked_on` not stored), writes the project `.claude/settings.json` hook config.
3. **Smoke-test the `brain` command** (BUILD-SPEC §10) — PROVE BY RUNNING, not inspecting (Steve's
   rule): `init` idempotent; `new-feature`; `whoami` resolves all 4 correctly (cockpit→`cockpit` NOT
   `graph`; workbench→`board`; langgraph→`main`; an ambiguous case refuses); `reconcile`; the pre-PR
   gate warns + (no human) proceeds; the governance propose→validate→apply→revert loop.
4. **STOP before the live step.** `brain install` (installs the nav skill to `~/.claude/skills/` +
   the global hook to `~/.claude/settings.json`) is what makes the hooks fire for Steve's 4 running
   agents. **DO NOT run it until Steve explicitly says go** — it changes his in-flight sessions.

## On the MCP server (Steve: "obsidian on standby, need to connect the MCP")
**v1 needs NO MCP server — there's nothing to connect to hit go.** Agents read/write the vault with
plain file tools; **Obsidian just opens the `.brain/` folder directly as a vault** (the graph view
works on the `[[wiki-links]]` with no MCP). The Obsidian/`obsidian-brain` **superset MCP is PHASE 2**
(agent smart-search, turned on only once the vault has grown enough to be worth it). So: open `.brain/`
in Obsidian to *look* at it once built; don't spend time wiring an MCP server for v1. (If Steve wants
the superset pulled forward, that's a separate Phase-2 task — not required for v1.)

## Multi-machine (Steve runs from a second machine)
Everything the brain needs travels in the **committed `.brain/`** (script, templates, notes). On the
other machine: **`git pull` → `brain install`** (folds in the machine-global nav skill + global hook).
No `~/agent-brain` needed there — the committed `.brain/` is self-sufficient.

## Locked constraints — do NOT re-litigate
- Personal tooling; never touches product code / Neo4j. Project-agnostic (root via `--git-common-dir`).
- **M9** human never manages coordination · **M10** nothing ever blocks on the human.
- **Feature = identity unit, not worktree.** Identity = BUILD-SPEC §2a (positional-slug exact-token).
- **v1 filesystem-only.** CUT: Dataview (use `brain status`), the PostToolUse fast-awareness hook
  (SessionStart + PreToolUse only), the `.brain-agent` sentinel (use `brain whoami`).
- **Governance:** conventions self-evolve via the gauntlet (propose→lock→validate→apply→`CHANGES`
  →revert); **machinery is human-applied in v1** (autonomous machinery = v2).

## Deferred (recorded, not in v1)
- **Phase 2:** superset indexing (`sweir1/obsidian-brain`, scoped to `.brain/`, reads-via-superset /
  writes-stay-built-in).
- **v2:** autonomous machinery self-evolution (ask-when-attended / shelve-when-not + self-tests).

## Next action
Steve says **"go"** → do build steps 1–3, report the smoke-test → await ok for step 4 (`brain install`
/ live hooks). Nothing to prep beforehand (no MCP to connect).
