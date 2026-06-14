# Design Docs

The full design record for the Agent Brain, in reading order. Start at the top for the *why*, drop to
**BUILD-SPEC** for the authoritative *how*.

| Doc | What it is |
|---|---|
| [STRATEGY.md](STRATEGY.md) | **Start here.** Design rationale + the locked decision log (principles M1–M10). The source of truth for *why* it's shaped this way. |
| [BUILD-SPEC.md](BUILD-SPEC.md) | **The authoritative build spec.** The corrected mechanics — file manifest, the `brain` command, the precise identity rule (§2a), schemas, the two hooks, the governance gauntlet, seed content, and the run-it verification (§10). Where it and STRATEGY differ, this wins. |
| [REVIEW.md](REVIEW.md) | The multi-agent review that hardened the design — the two blockers (root resolution, identity mis-match) and the cluster of subtraction fixes (A–L) it caught. |
| [BRIEF.md](BRIEF.md) | The original context + research that kicked it off (the `obsidian-brain` superset vs `obra`, why a server wasn't needed for v1, the pull-not-push framing). |
| [BUILD-PLAN.md](BUILD-PLAN.md) | An earlier, detailed build plan. Superseded by BUILD-SPEC where they differ; kept for the fuller backing notes and the seed-content drafts. |
| [INTEGRATIONS.md](INTEGRATIONS.md) | Dependencies (git / jq / sh), the Claude Code platform boundary, the optional closeout wiring, and every environment variable. |
| [HANDOFF-2026-06-13-build.md](HANDOFF-2026-06-13-build.md) | The cold-start "hit go" handoff used to drive the actual build. |

> **Note on the worked example.** These docs use the *Enterprise Research Dashboard* — a real,
> internal multi-worktree project — as the worked example, so they reference internal Jira keys
> (`DT-…`, `GLOBE-…`), absolute paths, and feature names (graph / cockpit / workbench /
> langgraph-runtime). **The tool itself is project-agnostic** — nothing in `bin/` or `templates/`
> hardcodes any of it. If this repo goes public, genericize or trim these docs first.
