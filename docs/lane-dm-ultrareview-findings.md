## Steadows Ultra Review

**Scope:** `fix/pretool-collision-warning`, `main...HEAD` at `b0b67d6`; accepted prior findings #1/#6/#11 excluded. The related untracked `docs/AGENT-DM-CHANNELS.md` was read as context but excluded from the explicit branch target.  
**Diff:** 14 tracked files, `+2355/-20` lines.  
**Fleet:** Maximum 8-reviewer fleet under the 9-thread ceiling: concurrency, security, POSIX shell, Git/secret guard, deployment, tests, integration, and adversarial operations. A fresh 8-task verification round routed all 13 deduplicated candidates to exactly two non-originating reviewers; one disagreement received an additional adversarial tie-break.  
**Verdict:** **NOT READY**

### Findings

#### [HIGH] SessionStart retires messages before delivery succeeds — [bin/brain](/Users/amap3i/agent-brain/bin/brain:786)

**Category:** Crash consistency / silent message loss  
**Finding:** SessionStart moves the inbox into terminal `read/` state before digesting or emitting startup context. A timeout, cancellation, unreadable archive, or output failure afterward permanently removes those messages from automatic delivery because later boots inspect only `inbox.jsonl`.  
**Evidence:** The durable `mv` occurs before digest creation, reconciliation, status rendering, and `_emit_session_ctx`. `_hook_session_start` then exits zero, while `cmd_hook` also fails open. No path scans `read/` for unacknowledged archives. This requires no concurrent sender and is distinct from accepted finding #1. The frozen suite tests only uninterrupted hooks.  
**Fix:** Introduce retryable `pending/claimed/acked` state. Keep messages replayable until handoff succeeds, recover stale claims, and test kill-after-claim plus digest/output failure. Prefer duplicate delivery over silent loss.  
**Verified:** **100/100** from both verifiers; independently confirmed through shell control flow and failure-status semantics.

#### [HIGH] Symlink hardening is bypassed by rotation and unchecked ancestors — [bin/brain](/Users/amap3i/agent-brain/bin/brain:225)

**Category:** Security / prompt injection / secret egress  
**Finding:** `_inbox_ensure` checks only the immediate lane directory and inbox. It never validates `.brain/dm`, while `_inbox_rotate` validates neither the inbox nor `read/` and runs before `_inbox_ensure` during SessionStart.  
**Evidence:** A symlinked inbox passes `-s`, is moved into `read/`, and is then dereferenced by `_dm_digest`, injecting arbitrary external content. A symlinked `dm` root or `read/` destination can instead route JSONL bodies into a tracked canonical directory such as `.brain/research`; the `.brain/dm` purge misses that path, and the built-in anchored secret check misses JSON lines beginning with `{`. The suite contains no symlink/commit scenario.  
**Fix:** Validate every component—`dm`, lane directory, inbox, and `read`—before every read, append, or move; require real directories and regular files. For a meaningful same-user boundary, use descriptor-relative operations with `O_NOFOLLOW`/`openat`/`renameat`. Scan final staged blobs and add send, rotation, injection, and commit regressions.  
**Verified:** **100/100**; both verifiers independently confirmed the context-injection and tracked-path egress traces.

#### [MEDIUM] Every live-observed DM is replayed as unread at next boot — [bin/brain](/Users/amap3i/agent-brain/bin/brain:253)

**Category:** State-machine correctness  
**Finding:** Live watching observes an append but neither the engine nor protocol claims, removes, or marks that line read. The next SessionStart rotates the still-nonempty inbox and injects the already-acted-on message again.  
**Evidence:** `_dm_send` only appends; the navigation skill instructs the lane to watch and acknowledge but defines no storage mutation. The frozen suite covers send-before-boot, never live-read-then-reboot. This uses one session and is distinct from accepted finding #11’s simultaneous consumers.  
**Fix:** Give messages stable IDs and an atomic claim/ack lifecycle so boot recovery replays only unacknowledged messages. Add a live-read → reboot scenario.  
**Verified:** **100/100**; deterministic static trace confirmed by both verifiers.

#### [MEDIUM] The commit guard certifies a false ignore state and cannot finish tracked-inbox cleanup — [bin/brain](/Users/amap3i/agent-brain/bin/brain:592)

**Category:** Git index integrity / secret-egress guard  
**Finding:** Two related flaws remain:

- Checking for a literal `dm/` line does not establish effective Git ignore behavior; later negations can re-include the directory.
- For an already-tracked inbox, `git rm --cached` stages the intended deletion, but the final `git diff --cached --name-only` treats that deletion as a failure and aborts forever.

**Evidence:** Retrying cannot recover: the deletion remains staged, `git add -- .brain` does not re-add the ignored path, and every later final check aborts again. The command also leaves other vault changes staged. Simply allowing deletions is unsafe because `git commit -- .brain` uses pathspec semantics and can read the still-present working-tree inbox. None of the 24 scenarios invokes `brain commit`; deleting the whole guard leaves the suite unchanged.  
**Fix:** Verify effective ignore behavior with `git check-ignore --no-index`. Build and scan a controlled temporary index, remove all DM entries there, commit that sanitized index without pathspec semantics, and preserve unrelated real-index state. Add legacy tracked/staged inbox, overridden-ignore, repeated-commit, and committed-tree secret tests.  
**Verified:** Cleanup wedge **100/100**; effective-ignore defect **100/75**. Commit-suite coverage was independently confirmed and merged into this finding.

#### [MEDIUM] Rolling back the engine strands pending DM state — [bin/brain](/Users/amap3i/agent-brain/bin/brain:305)

**Category:** Rollback compatibility / confidentiality  
**Finding:** The new engine is the only consumer of `.brain/dm/*/inbox.jsonl`. Rolling back to `main` leaves pending direct and broadcast messages permanently unread by subsequent old-engine boots.  
**Evidence:** The old engine contains no inbox rotation, digest, or DM dispatch. Broadcast call logs mention only `@all`, which does not match recipient-specific journal filtering. If rollback also restores the old ignore state, the old commit path can stage JSONL bodies while its anchored secret scan misses them.  
**Fix:** Make `dm/` ignore a permanent forward-compatible invariant. Refuse downgrade while inboxes are nonempty, or quiesce and drain them before rollback; retain a backward-compatible delivery shim where necessary. Test new-state/old-engine transitions.  
**Verified:** **100/100**; both verifiers compared HEAD’s persistent state with `main`’s consumer and commit behavior.

#### [MEDIUM] Atomic deployment leaves already-running lanes unwatched — [bin/brain](/Users/amap3i/agent-brain/bin/brain:783)

**Category:** Deployment transition  
**Finding:** Inbox creation and watcher instructions occur only during SessionStart. Sessions that already started under the old engine are not re-armed by the atomic executable swap or skill installation.  
**Evidence:** PreToolUse contains no lazy inbox bootstrap. A send to one of those running sessions succeeds but remains queued until its next boot, defeating the advertised seconds-latency during the machine-wide cutover. The arming test always starts with the new SessionStart path.  
**Fix:** Require an explicit restart/reorientation-and-ack gate for every active lane before declaring DM live, or add a versioned one-time bootstrap through an existing hook. Test old-session/new-engine behavior.  
**Verified:** **100/75**; both verifiers kept it as a fleet-wide deployment-readiness regression.

#### [MEDIUM] Skill installation can falsely report success and expose a partial protocol — [bin/brain](/Users/amap3i/agent-brain/bin/brain:891)

**Category:** Installation / engine-protocol compatibility  
**Finding:** `cmd_install` does not check `mkdir` or `cp`, and it overwrites the live skill in place. It can continue through settings installation, print success, and exit zero while leaving the old or truncated navigation protocol.  
**Evidence:** The copy implementation predates this branch, but the branch now makes the expanded DM protocol a functional deployment dependency. The frozen suite uses `init --no-install` and never exercises this path.  
**Fix:** Check every directory/copy operation; copy to a same-directory temporary file, validate or compare it, and atomically rename it over `SKILL.md`. Test injected copy failure and replacement of an existing installed skill.  
**Verified:** **75/100**; both verifiers retained it as an in-scope co-change failure.

#### [MEDIUM] The new “everyone-eventually” protocol promise is false — [templates/DM-PROTOCOL.md](/Users/amap3i/agent-brain/templates/DM-PROTOCOL.md:10)

**Category:** Protocol/runtime contract  
**Finding:** The new documentation says `brain announce` reaches every lane at its next boot, but SessionStart surfaces only today’s last five journal lines that name the current lane as author or explicit `@recipient`.  
**Evidence:** A generic announcement from Alpha is invisible to Bravo. A `dm @all` call log also names only `@all`, so it matches no concrete recipient. The frozen template scenario merely checks that the word `announce` appears.  
**Fix:** Either narrow the documentation to explicit mentions, or implement bounded per-lane journal cursors that include global/`@all` announcements across date boundaries. Add an Alpha-announce → Bravo-boot scenario.  
**Verified:** **100/100**; both verifiers independently applied the exact `_recent_journal` filter.

#### [MEDIUM] The frozen wire-format test accepts an unescaped JSON encoder — [test/dm.sh](/Users/amap3i/agent-brain/test/dm.sh:339)

**Category:** Suite adequacy / data contract  
**Finding:** Every test message uses JSON-safe ASCII. A naïve interpolated JSON encoder would pass all current validity and field assertions while corrupting quotes, backslashes, tabs, or literal newlines. The current `jq` implementation is correct; the frozen contract is not sufficient to preserve it.  
**Evidence:** No DM scenario supplies JSON-special content, although the CLI accepts it and the implementation explicitly promises jq-safe one-line framing.  
**Fix:** Send a body containing `"`, `\`, tab, and an internal newline. Assert exactly one physical JSONL record, successful parsing, and exact decoded-content round trip.  
**Verified:** **100/100**; both verifiers exhaustively inspected the suite’s DM bodies.

#### [MEDIUM] “Never journal the body” tests permit reversible encoded leakage — [test/dm.sh](/Users/amap3i/agent-brain/test/dm.sh:378)

**Category:** Suite adequacy / secret egress  
**Finding:** The scenarios reject only literal fragments of the body. A call-log line containing the required pointer plus `base64(content)` passes every assertion while committing a reversible credential. The current implementation is clean; this is a frozen-suite hole.  
**Evidence:** The encoded AWS probe contains none of `AWS_`, `AWS_SECRET_ACCESS_KEY`, or `abc123`, while the line can still contain `@bravo`, the inbox pointer, and remain a single journal entry.  
**Fix:** Pin the complete post-timestamp call-log grammar, or compare journal payloads for two different bodies and require body-independence. Cover direct and broadcast paths, then commit and inspect the resulting journal tree.  
**Verified:** **100/75**; both verifiers kept the issue, with reduced confidence only for the likelihood of an encoded-body implementation.

### Discarded Candidates

One verified candidate was discarded after adversarial tie-break: the three-recipient `@all` fixture does not literally exercise 13 lanes, but the proposed fixed-three mutation was judged implausible roster-gaming rather than a natural implementation failure. Two candidate clusters were merged into the commit-guard finding. Accepted prior limits and unrelated pre-existing observations were excluded before verification.

### Checks Run

- Read the full `main...HEAD` diff, repository guidance, prior adversarial report, plan context, branch history, and complete post-diff versions of `bin/brain`, both protocol templates, and `test/dm.sh`.
- `sh -n bin/brain` and `sh -n test/dm.sh`: **passed**.
- ShellCheck: 13 diagnostics, all matching the `main` baseline; no new DM-path diagnostic.
- `git diff --check main...HEAD`: reported only two trailing-space lines in the historical prior-review document.
- `./test/dm.sh`: **not executed successfully**. The read-only sandbox blocked its initial `mktemp` with `Operation not permitted` (exit 2), so this review does not claim 24/24 green.
- Manual/static probes covered POSIX exit propagation, old/new engine capability differences, journal filtering, Git pathspec semantics, and candidate test mutations.
- No code or index state was changed. Final status contains only the pre-existing untracked `docs/AGENT-DM-CHANNELS.md`.

Codex session ID: 019fc9c2-9676-7f51-ba18-723cabbccb1e
Resume in Codex: codex resume 019fc9c2-9676-7f51-ba18-723cabbccb1e
