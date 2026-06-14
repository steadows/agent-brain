# Dependencies & Integrations

What the Agent Brain needs to run, what's optional, and how it plugs into an agent harness.

---

## Hard dependencies

Three things, all standard on macOS and Linux:

- **`git`** — root discovery (`git rev-parse --git-common-dir`), diffs, and the `commit` path.
- **`jq`** — merging hook config into settings JSON, and emitting hook output. *(Not always
  preinstalled — `brew install jq` / `apt install jq`.)*
- **POSIX `sh` + coreutils** — `date`, `sed`, `awk`, `grep`, `tr`, `cut`, `mkdir`, `printf`, etc.

No language runtime, no package manager, no build step, no database, no server. macOS ships without
`flock`, so the commit/governance lock uses an atomic `mkdir` — nothing to install.

---

## Platform: the agent harness

The **CLI and the vault are harness-agnostic** — any agent that can read/write files and run a shell
can use `brain whoami` / `status` / `announce` and read the markdown notes directly.

The **automation layer is Claude Code-specific**. Two pieces, both installed by `brain install`:

- **Hooks** → `~/.claude/settings.json` (a global dispatcher that fires `brain hook session-start` /
  `pre-tool`). This is what makes agents auto-orient on boot and get the collision gate on push.
- **The `navigation-standards` skill** → `~/.claude/skills/` — the protocol agents follow.

Porting to another harness means re-expressing those two hooks and surfacing the skill in that
harness's own mechanism. The note **schemas** and the CLI don't change — that's the stable contract.

---

## Optional: session-closeout integration

The brain persists itself by committing `.brain/` (durability + multi-machine). **This is not a hard
dependency on any particular `/wrap` command** — the brain ships its own closeout:

```sh
brain wrap     # reconcile (self-heal settled/abandoned edges) + commit (from the main worktree only)
```

Run it at the end of a session, or wire it into whatever closeout command you already have. If you
keep a richer closeout skill, add these three calls instead of (or alongside) `brain wrap`:

**1. After your plan audit** — sync presence + reconcile:
```sh
BRAIN="$(cd "$(git rev-parse --git-common-dir)" && dirname "$(pwd)")/.brain"
[ -d "$BRAIN" ] && "$BRAIN/bin/brain" whoami    # your feature, or empty if not a brain branch
# then: write your live fields into $BRAIN/presence/<you>.md (phase/status/touches), flip any
#       settled connection to status: resolved, and run:
"$BRAIN/bin/brain" reconcile
```

**2. In git hygiene** — durability commit, **main worktree only** (the single agreed committer):
```sh
[ "$(git rev-parse --show-toplevel)" = "$(dirname "$BRAIN")" ] && "$BRAIN/bin/brain" commit
# sibling worktrees skip — the live folder already shared every write; hand-staging a sibling's
# checked-out .brain/ would let a PR 3-way merge revert evolving brain state.
```

**3. In your /learn step** — research stays put: brain `research/` notes do **not** auto-graduate to
skills (research ≠ reusable pattern); promotion is deliberate-only.

> The reference implementation of this wiring (for Claude Code's `/wrap`) lives in the build record;
> `brain wrap` is the harness-neutral equivalent.

---

## Environment variables

All optional — sensible defaults; override only when you need to.

| var | default | purpose |
|---|---|---|
| `BRAIN_FEATURE` | *(unset)* | manual identity override (e.g. a detached HEAD or a non-standard branch) |
| `BRAIN_MAIN_REF` | `origin/main` | the integration branch the vault diffs/commits against — set to `origin/master` etc. |
| `BRAIN_SECRET_DENYLIST` | `<vault>/secret-denylist.txt` | extra secret-scan terms for `brain commit` (one per line; optional) |
| `BRAIN_PRETOOL_MODE` | `allow` | set to `ask` to make the collision gate pause (only when a human is attached; else forced to `allow`) |
| `BRAIN_SKILLS_DIR` | `~/.claude/skills` | where `brain install` writes the nav skill (override for testing) |
| `BRAIN_GLOBAL_SETTINGS` | `~/.claude/settings.json` | where `brain install` merges the dispatcher (override for testing) |
| `BRAIN_TEST_BRANCH` | *(unset)* | test-only: override the resolved branch for `whoami` |
