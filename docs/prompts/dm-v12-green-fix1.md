# GREEN fix round 1 — V.N/47 fails under real dash: digest system errors misclassified as structural invalidity

**Repo:** `/Users/amap3i/agent-brain` · branch `fix/pretool-collision-warning` (working tree
carries your uncommitted v1.2 GREEN — do not commit).
**Mode: GREEN-ONLY.** Frozen suite `test/dm.sh` untouched, as before. Seam map:
`.context/seams/dm-v1.1-queue.md` § v1.2 (the design authority — re-read `## Poison, without
a counter`: quarantine ONLY a file **proven** structurally invalid).

## The failure (measured by the orchestrator — reproduce nothing, the diagnosis is complete)

Gate state: `./test/dm.sh` 54/54 under `sh`; **53/54 under real dash** (rewritten-shebang
engine). Failing scenario: **V.N/47 crash-before-emit-leaves-pending** — a `dm take` whose
stdout is closed (`>&-`) must leave the message in `pending/`; under dash it lands in
`failed/`.

Instrumented trace (debug engine copy):
```
DBG message_ok rc=0
DBG jq args: field_max=<248> line_max=<2000> id=<...>
jq: error: writing output failed: Bad file descriptor
DBG digest rc=2
brain: structurally invalid dm message: ... (routed to failed/@bravo ...)
```

Two stacked defects:

1. **Classification bug (shell-independent — the one that matters).** `_dm_pending_digest`'s
   final statement is `_dm_digest "$_pd_file" "$_pd_name"`, so it forwards **jq's raw exit
   code** as its own return value. jq's exit code space: `5` = the jq *program's own*
   `error("invalid dm object")` (proof of structural invalidity); `2` = system error (e.g. a
   write failure); `3` = program compile error. The function's OWN protocol is "return 2 ⇒
   structurally invalid, 1 ⇒ transient, leave pending" — so jq's system-error 2 collides with
   the protocol's structural 2, and `cmd_dm_take` quarantines a healthy message on a transient
   failure. A system error is not proof.
2. **Trigger (dash-specific).** With the engine's stdout closed at process start, dash's
   command-substitution pipe can land on the freed fd 1 (dash allocates low fds; bash-as-sh
   moves cmdsubst pipes to high fds, which is why `sh` passes by luck). The digest jq then
   writes to a bad fd → exit 2 → defect 1 misroutes the message.

## Required fix — two parts, both in `bin/brain`, nothing else

1. **Translate the digest exit code instead of forwarding it.** In `_dm_pending_digest`, call
   `_dm_digest`, capture its rc, and map: rc 0 → 0; **rc 5 → return 2** (the jq program's own
   `error()` is the only digest outcome that PROVES invalidity — and note `_dm_message_ok`
   already returned 0 by this point, so treat this belt-and-suspenders case honestly); **any
   other nonzero → warn + return 1** (transient — message stays pending). Keep the existing
   warn texts' shape (`brain: ` prefix — V.W/25 pins the diagnostic convention).
2. **Refuse to consume through an unusable stdout.** At the top of `cmd_dm_take` (after the jq
   preflight), detect a closed/unwritable fd 1 — the portable probe is a redirection dup,
   e.g. `if ! { true >&1; } 2>/dev/null; then _warn "...; leaving all messages pending"; return 1; fi`
   — and leave EVERYTHING pending. Do NOT reopen stdout to `/dev/null`: an emit that
   "succeeds" into the void archives an undelivered message, which is UR-1's silent loss.
   The SessionStart consume path builds its context differently (stdout is the hook pipe) —
   inspect whether it needs the same guard, and say what you concluded either way.

## Fences (unchanged from dm-v12-green.md)

No test files, no templates/, no docs/, no .context/, no commits. POSIX sh only; `sh -n` +
`dash -n` must pass; shebang stays `#!/usr/bin/env sh`. No new constants, no new state — this
is a classification and a guard, ~a dozen lines.

## Done means (the orchestrator re-runs all of these)

- `./test/dm.sh` → 54/54 under `sh` AND under the real-dash invocation
  (`sed '1s|.*|#!/usr/bin/env dash|' bin/brain > /tmp/brain-dash; BRAIN_BIN=/tmp/brain-dash ./test/dm.sh`)
- `./test/commit-install.sh` → 15/15 both shells
- `shellcheck bin/brain` at or below the 11-finding baseline

## Report

The diff summary, which of the two parts each hunk serves, your conclusion on the
SessionStart path, and anything you could not verify in-sandbox.
