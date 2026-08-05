<!-- Codex ultrareview (gpt-5.6-sol, effort max, 8-agent fleet) of main...HEAD @ 59987ea, 2026-08-04.
     Orchestrator-verified: finding 1 reproduced live (16/16 worktree engines at v1.0.0, no global
     brain on PATH); finding 2 traced in code. Suites could NOT be run by Codex (read-only sandbox
     rejected mktemp) — the orchestrator ran them separately: 53/53 + 15/15 on sh and dash. -->

## Steadows Ultra Review

**Verdict: NOT READY** — 6 HIGH and 6 MEDIUM verified findings.

**Scope:** `main...HEAD` at `59987ea` on `fix/pretool-collision-warning`  
**Diff:** 34 commits, 25 tracked files, `+7041/-73`  
**Fleet:** Maximum eight-agent fleet under the nine-thread ceiling, covering queue correctness, digest validation, concurrency, Git/security, POSIX portability, deployment, testing, and adversarial integration. All 14 candidate clusters received exactly two non-originating verifications; three disagreements received adversarial tie-breaks.

### Findings

#### [HIGH] Live DM instructions resolve to stale sibling engines

**Problem:** Phase 5 replaces only the main worktree engine, but SessionStart and the installed protocol instruct sibling lanes to invoke relative `.brain/bin/brain` or bare `brain` commands. Those resolve to frozen sibling copies—or nowhere—not the newly deployed engine. See [SessionStart](/Users/amap3i/agent-brain/bin/brain:1262), [navigation skill](/Users/amap3i/agent-brain/templates/navigation-standards.SKILL.md:62), and [deployment step](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:447).

**Evidence:** The candidate engine reports v1.1.0; all 16 checked live-vault worktree engines report v1.0.0, which lacks `dm take`, and no global `brain` executable is on PATH. Restarting a lane does not solve this: the correctly resolved hook then emits the stale relative command.

**Fix:** Resolve every engine and protocol path through `git --git-common-dir`, preferably through one canonical launcher. Test the exact emitted commands from a real sibling worktree.

**Verified:** 100/100 from both verifiers.

#### [HIGH] One poison file terminally discards healthy batchmates

**Problem:** `_dm_digest` rejects the entire claimed batch when any file is malformed. No file is acknowledged, so every valid peer accrues the poison file’s retry count and eventually enters terminal `failed/` without emission. See [digest validation](/Users/amap3i/agent-brain/bin/brain:550), [take handling](/Users/amap3i/agent-brain/bin/brain:603), and [retry transition](/Users/amap3i/agent-brain/bin/brain:470).

**Evidence:** One malformed file plus up to 39 valid files follows the same a0→a1→a2→a3→failed lifecycle. This materially escalates the deferred LOW “corrupt file blocks a batch” issue into permanent loss of unrelated valid messages.

**Fix:** Validate and route files independently; digest, emit, and acknowledge valid claims without incrementing their attempts because of another file.

**Verified:** 100/100 from both verifiers.

#### [HIGH] A post-claim crash can strand a DM indefinitely

**Problem:** An immediate restart correctly preserves a fresh 600-second claim, but the restarted session watches only `pending/`. Lease expiry creates no event, timer, poll, or claimed-directory sweep, so recovery may never run again. See [fresh-claim test](/Users/amap3i/agent-brain/bin/brain:465), [watch instruction](/Users/amap3i/agent-brain/bin/brain:1262), and [the contradictory e2e gate](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:508).

**Evidence:** The message remains claimed until an unrelated DM, later reboot, or manual take happens after expiry. This preserves the deliberate wall-clock lease but violates the process-crash-safe delivery promise.

**Fix:** Schedule recovery at the earliest observed lease expiry or periodically sweep `claimed/`. Add crash→immediate restart→idle past lease→automatic delivery coverage.

**Verified:** Both verifiers scored 100; a severity tie-break rated it HIGH.

#### [HIGH] Queue transitions can overwrite or eject messages

**Problem:** Stale recovery moves to unchecked deterministic destinations with `mv -f`; `_dm_route_failed` rejects only destination symlinks before doing the same. See [failed routing](/Users/amap3i/agent-brain/bin/brain:419) and [stale recovery](/Users/amap3i/agent-brain/bin/brain:470).

**Evidence:** A pre-existing symlink-to-directory can move a recovered DM outside the queue; a directory nests it; a regular file is overwritten. Failed-state collisions likewise destroy retained forensic records. This requires no TOCTOU race—the target can exist before recovery starts.

**Fix:** Reject every occupied or non-regular destination, use collision-preserving terminal names, and use platform-appropriate no-follow behavior.

**Verified:** Recovery and failed-routing limbs each received 100/100.

#### [HIGH] An accepted overlong ID permanently blocks claiming

**Problem:** `_dm_id_ok` checks only characters, not canonical shape or byte length. A pending basename can fit `NAME_MAX`, then become too long when the claim suffix is appended. See [validator](/Users/amap3i/agent-brain/bin/brain:359) and [claim construction](/Users/amap3i/agent-brain/bin/brain:500).

**Evidence:** With `NAME_MAX=255`, a 252-byte ID produces a legal 255-byte pending filename but a roughly 273-byte claim filename. `mv` fails while the source remains, `_dm_claim_all` returns nonzero, and an early-sorting entry blocks every later DM on every take and boot.

**Fix:** Enforce producer grammar and a byte bound that reserves the maximum claim suffix; route violations safely to `failed/`.

**Verified:** 100/100 from both verifiers.

#### [HIGH] The 40-message work bound is bypassable

**Problem:** The cap counts only successful pending claims. Stale recovery processes every claim, while malformed pending files are routed without incrementing the counter. See [unbounded recovery](/Users/amap3i/agent-brain/bin/brain:438) and [claim counter](/Users/amap3i/agent-brain/bin/brain:490).

**Evidence:** Repeated interrupted consumers can accumulate hundreds of fresh claims. Once stale, the next unattended SessionStart forks one `mv` per claim before emitting context, recreating the unbounded boot-latency defect H5 was intended to close.

**Fix:** Apply one total per-invocation transition budget across recovery, invalid routing, and normal claiming, with fair resumable ordering.

**Verified:** Both verifiers scored 100; severity tie-break retained HIGH.

#### [MEDIUM] The rollback runbook leaves two unsafe transition windows

**Problem:** The runbook neither quiesces senders before its final empty-queue check nor restores the machine-global v1.1 skill when downgrading the engine. See [skill deployment](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:454), [rollback procedure](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:474), and [v1.1 commands](/Users/amap3i/agent-brain/templates/navigation-standards.SKILL.md:62).

**Evidence:** A send completing after the empty scan becomes unreadable by v1.0. Even with empty queues, the retained skill continues directing lanes to `dm` and `inbox` commands absent from v1.0.

**Fix:** Establish a no-send barrier, wait for in-flight sends, drain and recheck, then roll back engine, templates, installed skill, and active-session instructions together.

**Verified:** Each limb received 100/100.

#### [MEDIUM] Ref advancement and real-index reconciliation are raceable

**Problem:** `cmd_commit` advances HEAD and only afterward resets the real index’s `.brain` entries in a separate Git process. See [ref update](/Users/amap3i/agent-brain/bin/brain:1065) and [index reset](/Users/amap3i/agent-brain/bin/brain:1075).

**Evidence:** A concurrent ordinary commit in that window sees the old `.brain` index as staged reversions against the new HEAD and can commit them. The subsequent reset follows that newer HEAD and reports success even though the brain synchronization was undone.

**Fix:** Coordinate the ref/index handoff with Git-recognized locking or a safe transaction, and verify HEAD still names the generated commit before declaring success.

**Verified:** 100/100 from both verifiers.

#### [MEDIUM] Unborn-HEAD publication lacks compare-and-swap protection

**Problem:** When HEAD is unborn, the new implementation publishes its root commit using `update-ref HEAD <new>` without an expected zero OID. See [parent snapshot](/Users/amap3i/agent-brain/bin/brain:1031) and [unconditional publication](/Users/amap3i/agent-brain/bin/brain:1068).

**Evidence:** A concurrent first commit or branch switch during temporary-index construction can be silently overwritten and orphaned. The same-OID existing-branch limb was discarded as pre-existing; this unborn-ref outcome is introduced by the diff.

**Fix:** Use the all-zero OID as the expected old value and validate the intended symbolic/detached ref identity.

**Verified:** Initial 75/100 and 100/100; tie-break narrowed the finding and scored the surviving limb 100.

#### [MEDIUM] Unicode digest output exceeds the byte caps

**Problem:** The digest uses jq `length`, which counts Unicode code points, for serialized-line and aggregate limits documented and tested as bytes. See [line check](/Users/amap3i/agent-brain/bin/brain:580) and [aggregate check](/Users/amap3i/agent-brain/bin/brain:585).

**Evidence:** The exact filter accepted 40 records totaling 160,360 UTF-8 bytes against an 80,040-byte cap; individual records reached roughly 4,009 bytes against a 2,000-byte limit. Existing tests are ASCII-only.

**Fix:** Measure serialized values with `utf8bytelength` and add multibyte line and aggregate boundary cases.

**Verified:** 100/100 from both verifiers.

#### [MEDIUM] Feature and body validation varies by shell and locale

**Problem:** `_feat_ok` uses a locale-sensitive alphabetic range, while `${#...}` counts Unicode code points in macOS `/bin/sh` but bytes in `dash`. See [feature validation](/Users/amap3i/agent-brain/bin/brain:261) and [body cap](/Users/amap3i/agent-brain/bin/brain:639).

**Evidence:** Under `en_US.UTF-8`, macOS sh accepts names such as `café` that dash rejects. Identical multibyte bodies can likewise fall on opposite sides of the 4,096-character limit, despite both runtimes being supported.

**Fix:** Make the feature alphabet locale-invariant and define one portable body metric. Exercise the engine itself explicitly under both shells with Unicode inputs.

**Verified:** 100/100 from both verifiers.

#### [MEDIUM] The mutation probe can certify incomplete suites

**Problem:** `run_suite` reduces the suite through a pipeline and checks neither the underlying exit status nor the 53-scenario completion summary. See [run_suite](/Users/amap3i/agent-brain/test/mutation-probe.sh:24) and [baseline decision](/Users/amap3i/agent-brain/test/mutation-probe.sh:48).

**Evidence:** A suite that exits 2 before emitting `FAIL` is reported as a clean baseline. A partial run that emits the declared failure and then dies is reported as an exact mutant kill.

**Fix:** Capture output and status separately, require complete 53-scenario summaries, require baseline exit 0, and validate mutant completion before comparing failure IDs.

**Verified:** 100/100 from both verifiers.

### Discarded Candidates

Four raw LOW candidates were removed before formal verification: three suite-only coverage concerns and one retracted shell-test concern. The existing-branch same-OID CAS limb was discarded as pre-existing. Two duplicate pairs were merged into the transition and rollback findings above.

### Checks Run

- Read the full diff, complete engine and three test scripts, design authority, both protocol templates, Phase 5–6 runbook, prior review reports, README, and branch history.
- `sh -n` and `dash -n` passed for the engine and test scripts.
- ShellCheck returned 11 diagnostics; none was promoted without behavioral evidence.
- `git diff --check main...HEAD` reported trailing whitespace only in historical review documents.
- `test/dm.sh` and `test/commit-install.sh` could not run: the read-only sandbox rejected their initial `mktemp` calls with exit 2. No green-suite claim is made.
- The mutation probe was not run because it deliberately edits and restores `bin/brain`; its pipeline behavior was reproduced read-only.
- Final status is unchanged: only the pre-existing untracked `docs/AGENT-DM-CHANNELS.md` remains. No code was edited.

Codex session ID: 019fcd1d-fdf8-7161-890f-eb0dc0565816
Resume in Codex: codex resume 019fcd1d-fdf8-7161-890f-eb0dc0565816
