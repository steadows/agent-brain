# Agent Brain

> A shared, file-based coordination vault that lets several AI coding agents work concurrent
> features on **one repository** without stepping on each other — they see each other, share what
> they learn, and surface cross-feature gotchas before they bite.

**v1 is filesystem-only.** No servers, no database, no MCP. A folder of markdown notes, one POSIX
shell script, and two session hooks. It drops into any git repo and is project-agnostic — nothing is
hardcoded; paths are discovered, structure comes from templates.

---

## The problem

You run a feature in worktree A, another in worktree B, a third on `main`. Each is driven by its own
agent session. They share a repo but **not a brain**: agent B doesn't know A just shipped the file it's
about to edit, both build the same component unaware, and a "we already researched this" finding dies
in one worktree's gitignored scratch. There's no shared source of truth for *who is doing what, right
now, and what they've learned.*

## The solution

A `.brain/` vault at the repo's main worktree, shared by every agent through its absolute path:

```
.brain/
  presence/      one note per FEATURE — where each agent is (status, phase, branch, files it touches)
  connections/   the cross-feature blackboard — clash · shared-file · waiting-on · shared-rule
  journal/       append-only daily comms timeline (the three "announce" moments)
  research/      shared, self-sufficient findings — the durable home research never had
  bin/brain      the engine (this script travels with the vault)
  templates/     the blank schemas that make it project-agnostic
  INDEX.md       static map + pointer to `brain status`
  CHANGES.md     the governance changelog
```

Agents **pull, not push**: they read the vault themselves with built-in file tools and a small CLI.
Two hooks wire it into the session lifecycle. A skill (`navigation-standards`) is the protocol they
follow. That's the whole system.

---

## Quick start

```sh
# 1. Drop the brain into a repo (scaffolds .brain/, writes a project write-allowlist)
~/agent-brain/bin/brain init

# 2. Go live on this machine (installs the nav skill + the global hook dispatcher)
~/agent-brain/bin/brain install

# 3. Register each feature once, from inside its worktree
brain new-feature graph

# from then on, in any session:
brain whoami      # which feature am I? (empty = not a brain branch)
brain status      # who else is active + connections touching me
brain announce "PG2 started; touching web/_views/"
brain reconcile   # auto-resolve settled blockers, refresh state
```

Multi-machine: the committed `.brain/` travels via git. On a second machine, `git pull` then
`brain install` (the nav skill + global hook are the only per-machine pieces).

---

## How identity works

A feature is the unit of identity — **not** the worktree (worktrees are cut per ticket and die at the
PR). Each presence note declares `owns_branches`. An agent's feature is resolved from the **positional
slug** of its branch — the token right after the ticket id in `feat/<ticket>-<slug>-…`, or the whole
branch name otherwise — matched *exactly* against `owns_branches`:

| branch | positional slug | resolves to |
|---|---|---|
| `feat/dt-520-graph-pg1-read-surface` | `graph` | graph |
| `feat/dt-513-cockpit-mini-graph` | `cockpit` | cockpit (the inner "graph" is never extracted) |
| `feat/dt-487-board-composer` | `workbench` | workbench (owns `["workbench","board"]`) |
| `main` | `agent` | langgraph-runtime (owns `["main","langgraph-runtime"]`) |

Exact-token matching means `graph` never matches `langgraph`. A branch that matches nothing → `whoami`
is empty → the hooks no-op (that's how every *other* worktree in the repo is ignored automatically).
The one rule that keeps this maintenance-free: **the feature name is always in the branch.**

---

## The two hooks

Both are thin wrappers, both fail open (drop a line to `.hook-errors.log`, exit 0), both no-op unless
`brain whoami` resolves.

- **SessionStart** — on every boot in a registered worktree: runs `brain reconcile` (self-heals
  settled/abandoned edges) and injects "run the `navigation-standards` skill" + the live `brain
  status`. The agent boots oriented.
- **PreToolUse** — a hard backstop on `git push` / `gh pr create` and edits to a declared shared path:
  computes the agent's changed paths, matches them against other **live** agents' `touches` and
  shared-file connections, and on a real collision **announces it to the journal and proceeds**.
  Non-blocking by default; never freezes an unattended run.

Hooks live only in the **global** `~/.claude/settings.json` dispatcher (single registration, resolves
the brain dynamically via `git rev-parse --git-common-dir`, so it covers main + every sibling worktree
and no-ops in every repo without a brain). `brain install` is what puts them there.

---

## Commands

| command | what it does |
|---|---|
| `brain init [--force] [--no-install]` | scaffold `.brain/` into this repo |
| `brain install` | machine-global: nav skill → `~/.claude/skills/`, hook dispatcher → `~/.claude/settings.json` |
| `brain new-feature <slug>` | register one feature once |
| `brain whoami` | resolve the current feature (empty = not a brain branch) |
| `brain status` | live dashboard: active features, connections touching you, change/error banners |
| `brain announce "<msg>"` | atomic-append a line to today's journal |
| `brain reconcile [--check]` | validate + cheap auto-fixes (`--check` = validate only, no mutation) |
| `brain commit` | durability: path-scoped, locked, secret-scanned, ff-only |
| `brain wrap` | self-contained session closeout: reconcile + commit (from the main worktree) |
| `brain propose <convention\|machinery> "<desc>"` | open a governed change |
| `brain apply` / `brain revert <id>` | apply / undo the in-flight convention change |
| `brain hook <session-start\|pre-tool>` | hook entry point (wired via settings) |

---

## The coordination protocol (`navigation-standards`)

The skill the agents follow. Five verbs:

- **Find** — orient at session start: `brain status`, read your own presence, grep `connections/`.
- **Read** — before touching a shared file, check who else is in it (trailing `/` = a zone prefix).
- **Write** — keep your presence note honest (single-writer); create a connection on a real overlap
  (slug = sorted feature names + kind, so two agents detecting the same edge collapse to one file);
  drop a self-sufficient `research/` note instead of re-researching.
- **Announce** — three moments: phase start, phase end / gate (`@feature` the agent you unblocked),
  about to PR.
- **Evolve** — conventions self-evolve through a governed gauntlet; machinery is human-applied in v1.

The note **schemas** are the stable contract — not the tools — so the read path can swap to a smart
index later without touching how agents write.

---

## Design principles

Ten locked decisions (full rationale in [docs/STRATEGY.md](docs/STRATEGY.md)). The load-bearing ones:

- **Pull, not push.** Agents read the brain themselves; the harness only nudges at session start.
- **Knowledge, not execution.** The brain shares coordination + research; it never copies memories,
  skills, or plans into itself — it points at them. Research is the one exception (it had no shared
  home).
- **Feature = identity, not worktree** (M5). One presence note per feature, across all its tickets.
- **The human never manages coordination** (M9). Agents detect, declare, maintain, and resolve
  everything. You keep no lists and chase nothing.
- **Nothing ever blocks on the human** (M10). Where an agent might "wait on you," it decides and
  proceeds, recording the call for optional review.

---

## Dependencies

- **Hard:** `git`, `jq`, and POSIX `sh` + coreutils. macOS or Linux. No language runtime, no build
  step, no server. (macOS ships without `flock`, so the lock uses an atomic `mkdir` — nothing to do.)
- **Platform:** the **CLI and vault are harness-agnostic**; the **automation** (the two hooks +
  the skill, installed by `brain install`) is **Claude Code-specific**. Porting means re-expressing
  the two hooks in another harness — the note schemas and CLI don't change.
- **Optional:** a session-closeout step to persist `.brain/`. The brain ships its own (`brain wrap`),
  so it does **not** depend on any particular `/wrap` command.

Full breakdown, the closeout-wiring recipe, and every env var: **[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md)**.

## Project layout

```
agent-brain/
  bin/        the engine + two hook wrappers (copied into each repo's .brain/ at init)
  templates/  the blank schemas + the navigation-standards skill (the project-agnostic core)
  docs/       design docs, build spec, decision log, the multi-agent review  (see docs/README.md)
  README.md   this file
  ROADMAP.md  next steps, known issues, deferred phases
```

## Status & roadmap

v1 is filesystem-only and in active use. **Phase 2** adds an optional smart-search index
(`.brain/`-scoped superset MCP, reads-via-superset / writes-stay-built-in) once a vault grows big
enough to warrant it. **v2** adds autonomous machinery self-evolution. Known issues and the full plan
are in [ROADMAP.md](ROADMAP.md).

## License

MIT — see [LICENSE](LICENSE).
