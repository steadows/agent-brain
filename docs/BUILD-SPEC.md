# Agent Brain — v1 Build Spec (review-corrected, AUTHORITATIVE)

> The single source of truth **to build from.** Folds in all review fixes (A–L) + the during-build
> notes from `REVIEW.md`, and the locked governance model. Design rationale lives in
> `STRATEGY.md`; this doc is the corrected *mechanics*. Where they differ, **this wins.**
>
> Scope: personal dev-workflow tooling; never touches product code, the product, or Neo4j.
> Project-agnostic. v1 is filesystem-only (built-in Read/Grep read; Write/Edit + shell append write).
> Superset indexing = Phase 2; autonomous machinery self-evolution = v2.

---

## 0. File manifest (what `brain init` creates)

```
<repo-root>/.brain/
  bin/brain                         the portable engine (one shell script, all subcommands)
  bin/hook-session-start            thin wrapper → brain hook session-start
  bin/hook-pre-tool                 thin wrapper → brain hook pre-tool
  templates/presence.md
  templates/connection.md
  templates/journal.md
  templates/research.md
  templates/INDEX.md
  templates/navigation-standards.SKILL.md   canonical source of the nav skill (committed)
  presence/                         one note per FEATURE (seeded: graph, cockpit, workbench, langgraph-runtime)
  connections/                      seeded: the 6 real cross-feature edges
  journal/<today>.md                seeded init line
  research/                         empty (grown live)
  INDEX.md                          static map + pointer to `brain status`
  CHANGES.md                        the governance changelog (structural changes)
  .indexignore                      reserved for Phase 2 (templates/ + bin/); empty-effect in v1
<repo-root>/.claude/settings.json   hooks registered (jq-merged, never clobbered)
~/.claude/skills/navigation-standards/SKILL.md   the nav skill, installed machine-global
~/.claude/settings.json             the global hook dispatcher (no-ops in repos without a brain)
```
No `.brain/.gitignore` (nothing to ignore in v1). `.brain/` IS tracked; the index DB (Phase 2) will be gitignored then.

---

## 1. Root discovery (fix A) — the one function everything reuses

```sh
brain_root() { CDUP=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  printf '%s\n' "$(cd "$(dirname "$CDUP")" && pwd -P)"; }   # canonical; works from ANY worktree
```
`--git-common-dir` resolves to the **main** worktree's `.git` from every sibling worktree, so the
brain is always the *one* `<main>/.brain/`. (`--show-toplevel` would have pointed each sibling at its
own non-existent `.brain/` — the original blocker.) Every subcommand and hook resolves the vault via
`brain_root`; nothing is hardcoded → project-agnostic.

---

## 2. The `brain` command (`.brain/bin/brain`)

Portable POSIX sh, no Claude-specific deps. Subcommands:

- **`brain init`** — idempotent. Resolve canonical root; if `<root>/.brain/` exists → no-op + notice
  (`--force` re-templates). Else: create folders, copy templates, write `INDEX.md`/`CHANGES.md`,
  install the nav skill to `~/.claude/skills/navigation-standards/` from the committed template,
  **jq-merge** the hooks into `<root>/.claude/settings.json` (append-dedupe into existing `hooks.*`
  arrays — never clobber, never touch `settings.local.json`), install the **global dispatcher** hook
  into `~/.claude/settings.json`, and **allowlist `<root>/.brain/**` as a writable path** in settings
  (so sibling-worktree agents can write into main's `.brain/` without a sandbox prompt — fix L).
- **`brain install`** — idempotent **machine-global setup** (the "fold the settings in" command for a
  new machine). Reads the committed `.brain/` and installs the per-machine pieces that do NOT travel
  with git: the nav skill → `~/.claude/skills/navigation-standards/` (from the committed template) and
  the global dispatcher hook → `~/.claude/settings.json`. **Multi-machine flow = `git pull` → `brain
  install`.** `brain init` calls this at the end; a machine that already has `.brain/` via git just
  needs `brain install`. The committed `.brain/` is self-sufficient — a second machine does NOT need
  `~/agent-brain` (that's only for `init`-ing brand-new projects).
- **`brain new-feature <slug>`** — register a feature once. Scaffold `presence/<slug>.md` from the
  template: auto-fill `current_worktree` (from `git rev-parse --show-toplevel`) and `current_branch`;
  seed `owns_branches` per **§2a** (`[<slug>]`, plus the branch's positional slug if it differs, + an
  M6 warn). `status: idle`; leave `feature`/`plan`/`phase` as `TODO`. Append a journal "joined" line.
  (No per-worktree/ticket registration — ever.) Note: `current_worktree` intentionally uses
  `--show-toplevel` = the agent's *local* worktree — correct here, and distinct from §1's brain-root.
- **`brain whoami`** — resolve the current feature: (1) if `$BRAIN_FEATURE` is set, use it
  (main-resident / override — fix B-iv); else (2) extract the branch's **positional slug** and exact-match it against every presence note's
  `owns_branches` (precise rule + the four real features in **§2a**); (3) on multi-match, disambiguate
  by `current_worktree`; (4) still ambiguous → **print nothing + exit non-zero** (refuse to guess).
  Empty result = not a brain branch.
- **`brain announce "<msg>"`** — atomic-append `- <ISO-time> <feature> — <msg>` to today's journal
  (auto-creates the daily file). The single canonical journal writer (agents + hooks).
- **`brain status`** — print the text dashboard: active features (status active/blocked, or idle with
  a note) + open|watch connections touching me + a "⚠ N brain changes since you last looked" line if
  `CHANGES.md` advanced + any `.hook-errors.log` breadcrumbs. **This is the single live-state source**
  for both humans and agents (replaces the cut Dataview dashboard — fix F).
- **`brain reconcile`** — the coherence keeper (fold-in of validation; no separate `brain doctor`):
  validate every note parses under the current schema, flag colliding `owns_branches`, dangling
  `[[links]]`, stale-but-`active` features, and stealth-structural notes (a `type:` allowlist check).
  Then the **cheap auto-fixes**: refresh this feature's `touches` from `git diff --name-only
  origin/main`; auto-resolve `waiting-on` connections whose blocker is `git branch --merged
  origin/main` OR presence `status: done` (fired by the **blocker's** session — fix J); downgrade a
  *stale/abandoned* blocker `open→watch` + journal "blocker appears abandoned — proceeding". Runs at
  **SessionStart and at `/wrap`** (robust to a never-wraps agent — fix I). **`brain reconcile --check`**
  validates only (no mutation) — used by the governance gauntlet (§7).
- **`brain commit`** — durability. Path-scoped (`git -C <main> add .brain/ <nav-skill-template>`),
  **`flock` singleton** (no `index.lock` race), **secret-scan** staged `.brain/` against
  `data/canonical/tool_egress_denylist.yml` + an `.env`-shaped regex (`^[A-Z][A-Z0-9_]*=.+`, abort on a hit), commit
  standalone `chore(brain): …`, rebase onto fresh `origin/main` **ff-only, never force-push**. Callable
  by anyone; not pinned to the main-resident feature being awake (fix I).
- **`brain revert <change-id>`** — one-step undo of a structural change (a committed diff).
- **`brain hook <event>`** — the hooks’ entry point (below). Keeps logic in one place.
- **`brain propose <…>` / `brain apply`** — the governance gauntlet (§7).

---

## 2a. Identity rule (precise) — pins fixes #1–#3

**Branch → positional slug.** A branch's *slug* = the first `-`-delimited token **immediately after the
ticket id** in `feat/<ticket>-<slug>-…`. If the branch isn't `feat/…`-shaped (e.g. `main`), the slug =
the whole branch name. (`feat/dt-520-graph-…`→`graph`; `feat/dt-513-cockpit-mini-graph`→`cockpit`;
`feat/dt-487-board-composer`→`board`; `main`→`main`.)

**Match (whoami):** a feature matches iff the branch's positional slug is an **exact member** (token
equality, never substring) of its `owns_branches`. So `graph` never matches `langgraph`, and the
`graph` *inside* cockpit's branch is never even extracted (only `cockpit`, the positional slug, is).
Order: `$BRAIN_FEATURE` → positional-slug exact-match → multi-match tiebreak by `current_worktree` →
still ambiguous = refuse (exit non-zero) → none = empty.

**Seeding (`new-feature <slug>` on branch B):** `owns_branches=[<slug>]`; if B's positional slug ≠
`<slug>`, append it + warn (M6). Main-resident → also include `"main"`.

| feature | branch today | positional slug | owns_branches |
|---|---|---|---|
| graph | `feat/dt-520-graph-…` | `graph` | `["graph"]` |
| cockpit | `feat/dt-513-cockpit-mini-graph` | `cockpit` | `["cockpit"]` |
| workbench | `feat/dt-487-board-composer` | `board` | `["workbench","board"]` |
| langgraph-runtime | `main` | `main` | `["main","langgraph-runtime"]` |

Resolves all four with one rule: kills `graph⊂langgraph` + the cockpit double-match (positional +
exact-token), resolves workbench (`board`), resolves langgraph-on-`main` (`main` is an exact
owns_branches member — no `BRAIN_FEATURE` needed; it's a manual override only).

---

## 3. Schemas (corrected)

### presence/<slug>.md
```yaml
---
type: presence
agent: graph
feature: "Graph Explorer"
status: active                    # active | blocked | idle | done  (liveness gates on this FIRST)
phase: PG1
# identity (set once; lives the whole feature)
owns_branches: ["graph"]          # delimited-token match; list; seeded by new-feature
plan: GRAPH_FEATURE_GSD_PLAN.html
tracker_epic: DT-206
# live (machine-maintained; do not hand-tend)
current_worktree: /…/enterprise_research_dashboard-dt520   # whoami tiebreaker; ephemeral/machine-local
current_branch: feat/dt-520-graph-pg1-read-surface         # best-effort display
current_ticket: DT-520                                      # best-effort display
touches: [src/api/routes/graph.py]   # DERIVED from `git diff --name-only origin/main` at reconcile
updated: 2026-06-13T15:00:00Z        # full ISO timestamp (sharpens liveness + journal cursor)
---
<one paragraph; [[links]] to connections touching its files>
```
- **`blocked_on` is NOT stored** — the blocked feature computes "am I blocked?" by reading its
  referenced connections' live `status` at boot (a `resolved`/`watch` edge auto-clears, no cross-note
  write).
- **Liveness:** `active`/`blocked` always count; `idle`/`done` skip; `updated`-age is a *secondary*
  hint, one named constant ≈ **5 days** (Fri→Mon parks don't age out).

### connections/<slug>.md
```yaml
---
type: connection
features: [graph, cockpit]
kind: clash                       # clash | shared-file | waiting-on | shared-rule  (LABEL ONLY — drives no logic)
status: open                      # open | watch | resolved
severity: high
blocks: [cockpit]                 # direction; empty if symmetric
files: [web/src/app/_views/]      # COLLISION MATCH (fix D): trailing "/" = zone (prefix-match); else exact file
discovered: 2026-06-13T…Z
resolved: null
updated: 2026-06-13T…Z
---
```
- **Deterministic slug** = sorted-feature-pair + kind → concurrent creation collapses to one file
  (create with `noclobber`; on `EEXIST` the loser **reads the winner's note and proceeds — no second
  write**; never a silent dup).
- **Boot surfacing** is filtered to `status: open|watch` (resolved is history you grep on demand).
- Same trailing-`/` zone rule applies to presence `touches`.

### journal/<YYYY-MM-DD>.md — append-only; lines `- <ISO-time> <feature> — <msg>` (+ optional `[[links]]`).
### research/<slug>.md — self-sufficient summary + `sources:` pointers (Option B: stays in the brain; no auto-graduate).
### templates/* — the blanks above with `TODO` placeholders. INDEX template = static map + "run `brain status`".

---

## 4. Navigation-standards skill (fix G)

Lives **machine-global** at `~/.claude/skills/navigation-standards/SKILL.md` (like `/wrap`), because
`.claude/skills/*` is gitignored here AND a committed in-repo skill wouldn't reach sibling feature
branches until merge. The **canonical source is committed** at
`.brain/templates/navigation-standards.SKILL.md`; `brain init` installs from it; a structural edit to
the skill edits the global file **and** updates the committed template (and `brain commit`'s pathspec
includes it). Content = the Find / Read / Write / Announce / Evolve protocols (per STRATEGY.md),
written against built-in tools (a one-line "Tool binding" note swaps to the superset in Phase 2 — the
note *schemas* are the stable contract, not the tools).

---

## 5. Hooks (two only — fast-awareness cut, fix E)

Both are thin wrappers calling `brain hook <event>`; both **fail-open** (drop a line to
`.brain/.hook-errors.log` on error, exit 0) and **allowlist on `brain whoami` non-empty**.

1. **SessionStart** — order matters:
   - **(a) self-onboard pre-check (fix C):** `whoami` empty BUT branch is `feat/…`-shaped → inject an
     **informational** "no presence note — if this is a tracked feature, run `brain new-feature <slug>`"
     (slug from branch; harmless if ignored on a non-brain worktree — an optional committed
     `templates/non-brain-globs` suppresses it). Keeps M9 (agent onboards itself; human never runs it).
   - **(b)** cache `BRAIN_FEATURE` for the session.
   - **(c)** run `brain reconcile` (cheap auto-fixes — robust to never-wraps).
   - **(d)** inject "run the `navigation-standards` skill" + `brain status` (incl. relevant **recent
     journal lines** since `updated`, the agents+connections summary, and the `CHANGES`/error banners).
2. **PreToolUse — the hard gate** on `git push` / `gh pr create` (and Edit/Write to a *declared shared*
   path): compute *my* changed/target paths live from git, match against other **live** agents'
   presence `touches` + shared-file connection `files` (trailing-`/` zone vs exact — fix D); on a real
   collision `brain announce` a warning + inject it. **This hook also emits the "about to PR" journal
   line** (announce + gate unified). **Non-blocking by default** (`allow` + context). The `ask` (pause)
   variant is a knob — but **forbidden when no human is attached** (no TTY / autonomous): it
   force-downgrades `ask → allow + loud journal` (fix K — closes the M10 hole; an overnight run never
   freezes).

Global dispatcher (in `~/.claude/settings.json`) is the only entry registered there:
`root="$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")"; [ -x "$root/.brain/bin/brain" ] && exec "$root/.brain/bin/brain" hook "$@" || exit 0` — no-ops in every repo without a brain.

---

## 6. `/wrap` integration

Three one-line *calls* (the logic lives in `brain`, so `/wrap` — a user-global skill — stays portable):
- **Phase 1 (Plan Audit):** agent writes its own presence live fields from the `gsd-state` it just
  audited; `brain reconcile` resolves settled/abandoned connections.
- **Phase 4 (Git Hygiene):** `brain commit` (path-scoped, flock, secret-scanned, ff-only). **Only one
  session commits** — but `brain commit` is safe from any worktree (not pinned to main-resident being
  awake). **No sibling worktree ever stages/commits its own checked-out `.brain/`** (fix L — else a PR
  3-way merge reverts evolving brain state).
- **Phase 6 (/learn):** brain **helper-skills** route through `/learn-eval` (default Project); brain
  **research does NOT auto-graduate** (Option B).

---

## 7. Governance gauntlet (conventions self-evolve; machinery human-applied in v1)

A **convention** change (note format / nav-skill protocol) runs:
`brain propose` (writes the change, **not live**, takes a **lock** — one in flight) → **auto-validate**
(`brain reconcile --check` dry-run; fail → reject + rollback) → `brain apply` (rulebook + template +
notes in lockstep) → record in `CHANGES.md` (surfaced by `brain status`) → `brain revert <id>` undoes
it. Conventions auto-apply **even unattended**.
A **machinery** change (hooks / the `brain` script) in v1: the agent files a **proposal note** (a
persistent `watch` connection slugged `machinery-<kebab-desc>` — no feature-pair — + a journal event) and keeps working with current
machinery; **a human applies machinery changes deliberately.** (Autonomous machinery self-evolution =
v2.) `brain reconcile`'s `type:`-allowlist check flags any stealth-structural note.

---

## 8. Operational invariants (must hold)

1. **One active session per feature** (presence is single-writer-per-feature → no cross-agent clobber).
2. **No sibling worktree stages/commits its local `.brain/`** — only `brain commit` from the agreed
   committer; everyone else only *reads/writes note content*, never `git add .brain` (fix L).
3. **Sibling agents write into `<main>/.brain/`** (the resolved absolute path) — the settings allowlist
   from `brain init` must cover it or every coordination write prompts.
4. **`feature name in the branch`** is the going-forward rule (M6); main-resident features
   (langgraph) match via `owns_branches: ["main"]` (see §2a) — `BRAIN_FEATURE` is a manual override only.

---

## 9. Seed content (day-one payoff)

Take the `BUILD-PLAN §5` seeds as a **draft only** and apply ALL these transforms (do not copy verbatim):
- **presence (4):** add `owns_branches` per §2a (graph `["graph"]`, cockpit `["cockpit"]`, workbench
  `["workbench","board"]`, langgraph `["main","langgraph-runtime"]`); rename `worktree→current_worktree`,
  `branch→current_branch`; split `jira:` → `tracker_epic` + `current_ticket` (graph DT-206/DT-520;
  cockpit DT-238/DT-513; workbench DT-470/DT-487; langgraph DT-206/—); **drop** stored `blocked_on`
  (derived at boot); `updated` = ISO timestamp.
- **connections (6):** **remap legacy `kind`** — `divergence→clash`, `gate-handoff→waiting-on`,
  `contract→shared-rule` (shared-file unchanged); deterministic slug = sorted-feature-pair + kind; ISO times.
- **INDEX.md:** seed from `templates/INDEX.md` (the **static map + `brain status`** template) — NOT the
  BUILD-PLAN §5 Dataview INDEX (cut, fix F).
- journal init line; `research/` empty; `CHANGES.md` empty.

---

## 10. Build verification (prove it by RUNNING it)

1. `brain init` in a scratch checkout → folders/templates/skill/settings created; idempotent on re-run.
2. `brain new-feature demo` from a feature worktree → presence scaffolded, journal "joined" line, `whoami` returns `demo`.
3. Identity edge cases: confirm cockpit branch resolves to `cockpit` (not `graph`); langgraph via `BRAIN_FEATURE`; an ambiguous case refuses.
4. SessionStart hook in a registered worktree → nav-skill directive + `brain status`; in a non-brain worktree → silent, exit 0.
5. PreToolUse gate: stage a file another feature's presence claims → journal warning + (no human) proceeds; never hangs.
6. `brain reconcile` resolves a `waiting-on` whose blocker is merged; downgrades an abandoned one.
7. Governance: `brain propose`→validate→apply a trivial convention change; confirm `CHANGES.md` + `brain status` banner; `brain revert` undoes it.

---

## 11. Deferred (recorded, not built)

- **Phase 2 — superset indexing** (`sweir1/obsidian-brain`, scoped to `.brain/`, reads-via-superset /
  writes-stay-built-in, on when the vault fills; `.indexignore` already reserved). Pure addition.
- **v2 — autonomous machinery self-evolution** (context-aware ask-when-attended / shelve-when-not +
  machinery self-tests).
