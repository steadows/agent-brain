<!-- Codex ultrareview round 2 (gpt-5.6-sol, max, 8-agent fleet), main...HEAD @ 7e8e466, 2026-08-04.
     ORCHESTRATOR NOTES: (1) the dash-coverage finding is CONFIRMED — the engine shebang is
     `#!/usr/bin/env sh`, so launching the harness with dash never ran the ENGINE under dash;
     my prior "sh AND dash" gate claims covered `dash -n` syntax only. Re-run with a dash-shebang
     engine copy via BRAIN_BIN: 60/60 and 15/15 under real dash runtime, so no dash bug was hidden.
     (2) jq locally is 1.7.1 so utf8bytelength resolves; the undeclared >=1.6 requirement stands.
     (3) ALL FIVE HIGH findings live in the claim/lease/recovery/budget machinery. -->

## Steadows Ultra Review

**Verdict: NOT READY**

**Scope:** `main...HEAD` on `fix/pretool-collision-warning` at `7e8e466`  
**Diff:** 28 files, `+7,944/-82`  
**Fleet:** Maximum 8-reviewer fleet under the 9-thread ceiling, covering queue correctness, filesystem/security, deployment, lease/budget behavior, POSIX portability, tests, contracts, and adversarial operations. Every deduplicated candidate received exactly two non-originating verifications; one disagreement received an adversarial tie-break.

### Findings

#### [HIGH] ID validation still permits permanent `NAME_MAX` head blocking — [bin/brain:361](/Users/amap3i/agent-brain/bin/brain:361)

**Problem:** `_dm_id_ok` treats shell globs like regexes. `[0-9]*` and `[1-9][0-9]*` accept arbitrary trailing whitespace, glob characters, and Unicode. Its “byte” limit uses `${#}`, which counts characters under macOS `/bin/sh`.

**Evidence:** `20260804T132000Z-12` plus 58 emoji is 77 shell characters but 251 bytes. `<id>.a0` is 254 bytes and fits, yet adding the claim suffix exceeds `NAME_MAX=255`. The validator accepts it under `/bin/sh`; claiming fails at [bin/brain:566](/Users/amap3i/agent-brain/bin/brain:566), leaves the early source pending, and blocks all later DMs. U.H5 and M11 cover only ASCII.

**Fix:** Enforce a complete ASCII producer grammar, including true digit-only PID/bump validation, and measure bytes with `LC_ALL=C ... | wc -c`.

**Verified:** 100/100 from both independent verifiers.

#### [HIGH] Locale-sensitive decimal validation reaches fatal arithmetic — [bin/brain:381](/Users/amap3i/agent-brain/bin/brain:381)

**Problem:** `[!0-9]` is locale-sensitive and does not guarantee an ASCII arithmetic operand.

**Evidence:** Under `LC_ALL=fa_IR.UTF-8`, macOS `/bin/sh` accepts Arabic-Indic `١` as a digit. A claim such as `20260804T120000Z-1.a0.c١-1` then terminates the shell at [bin/brain:517](/Users/amap3i/agent-brain/bin/brain:517) with arithmetic status 127. `dash` rejects the same operand. The malformed claim persists and blocks recovery and healthy pending delivery on every invocation.

**Fix:** Validate with explicit ASCII sets such as `[0123456789]`/`[!0123456789]`, or force C-locale validation before arithmetic. Add both-shell locale coverage.

**Verified:** 100/100; independently reproduced by the root review and both verifiers.

#### [HIGH] Claims created by live `dm take` have no lease scheduler — [bin/brain:691](/Users/amap3i/agent-brain/bin/brain:691)

**Problem:** `_dm_arm_lease_sweep` is called only recursively and from SessionStart at [bin/brain:1394](/Users/amap3i/agent-brain/bin/brain:1394). `cmd_dm_take` never arms it.

**Evidence:** After an empty boot, a live watcher can claim a message and then encounter digest, output, ack, or process failure. The claim remains in `claimed/`, but lease expiry itself creates no filesystem event. It can remain indefinitely until an unrelated DM, reboot, or manual take. U.H3/M9 cover only claims visible before SessionStart.

**Fix:** Establish a persistent per-lane recovery mechanism even when boot initially sees no claims. Scheduling only at the end of `dm take` retains a crash window.

**Verified:** 100/100.

#### [HIGH] Forty stale recoveries silently strand the entire batch — [bin/brain:1344](/Users/amap3i/agent-brain/bin/brain:1344)

**Problem:** SessionStart shares one 40-transition budget between recovery and claiming but provides no continuation when recovery consumes it.

**Evidence:** If a normal 40-message claimed batch crashes and later becomes stale, the next boot moves all 40 to `pending/`, leaving zero claim budget. Those mutations occur before the lane receives its watcher instruction. `claimed/` is then empty, so the lease scheduler starts no timer. All 40 DMs can remain silent until unrelated activity or another boot. U.H6 proves progress only by manually invoking `dm take` a second time.

**Fix:** Reserve/interleave claim capacity, or schedule an explicit bounded continuation whenever budget exhaustion leaves pending work.

**Verified:** 100/100.

#### [HIGH] Temp-sweep failure now suppresses delivery and can create perpetual 1 Hz retries — [bin/brain:418](/Users/amap3i/agent-brain/bin/brain:418)

**Problem:** This materially worsens the explicitly deferred temp-sweep issue. Any purge failure causes SessionStart to fabricate a fully consumed transition budget at [bin/brain:1346](/Users/amap3i/agent-brain/bin/brain:1346), suppressing otherwise healthy pending delivery.

**Evidence:** If a canonical stale claim also exists, the scheduler chooses a one-second delay, recovery fails again, and [bin/brain:684](/Users/amap3i/agent-brain/bin/brain:684) recursively re-arms another one-second sweep. Multiple SessionStarts can create parallel retry chains and continuously grow `.hook-errors.log`.

**Fix:** Return transition count independently from ancillary sweep status. Warn and continue appropriate work after a pre-transition purge failure, and use singleton scheduling with bounded backoff.

**Verified:** 100/100.

#### [MEDIUM] Budget-deferred malformed claims receive no continuation — [bin/brain:483](/Users/amap3i/agent-brain/bin/brain:483)

With 41 malformed claimed names, recovery routes 40 and stops. If the last has an unparsable timestamp, the lease armer skips it at [bin/brain:668](/Users/amap3i/agent-brain/bin/brain:668) and schedules nothing. It remains hidden until another external invocation. Schedule immediate bounded cleanup whenever residual invalid claims remain. **Verified: 100/100.**

#### [MEDIUM] Lease draining is unbounded and duplicates sleepers — [bin/brain:665](/Users/amap3i/agent-brain/bin/brain:665)

Each scheduler pass scans all claims, recovers at most 40, then scans the remainder again, yielding approximately `O(N²/40)` work. Every same-lane SessionStart can independently create another sleeper. Use singleton ownership plus bounded/resumable inspection. **Verified: 100/100.**

#### [MEDIUM] Reported dash runs do not execute the engine under dash — [test/dm.sh:198](/Users/amap3i/agent-brain/test/dm.sh:198)

Both harnesses directly execute `$BRAIN_BIN`; its `#!/usr/bin/env sh` shebang selects `sh`, even when the harness itself was launched with `dash`. The mutation probe only performs `dash -n`. Therefore the supplied dash results do not exercise engine runtime behavior—the exact distinction exposed by the Unicode failures above. Parameterize the engine interpreter and execute every baseline and mutant under both shells. **Verified: 100/100.**

#### [MEDIUM] jq 1.5 satisfies the documented dependency but cannot digest DMs — [bin/brain:646](/Users/amap3i/agent-brain/bin/brain:646)

The repository requires only unversioned `jq` at [README.md:164](/Users/amap3i/agent-brain/README.md:164), but `utf8bytelength` is absent from the [jq 1.5 manual](https://jqlang.org/manual/v1.5/) and present in the [jq 1.6 manual](https://jqlang.org/manual/v1.6/). On jq 1.5, sending succeeds but every digest fails to compile, retaining or eventually failing all messages. Require and preflight jq ≥1.6, or implement a compatible byte-length helper. **Verified: 100/100.**

#### [MEDIUM] Emitted absolute paths are not safely shell-escaped — [bin/brain:1339](/Users/amap3i/agent-brain/bin/brain:1339)

`$BRAIN/bin/brain` is interpolated inside textual double quotes. When that instruction is later executed through a shell—as D.P1 explicitly does—legal checkout paths containing `"`, `$()`, backticks, variables, or backslashes are reparsed. Quotes can break execution; substitutions can execute. Emit a correctly POSIX-single-quoted token or a structured/runtime-resolved invocation. **Verified: 100/100.**

#### [MEDIUM] The full protocol still resolves relative to stale sibling worktrees — [templates/navigation-standards.SKILL.md:75](/Users/amap3i/agent-brain/templates/navigation-standards.SKILL.md:75)

The installed skill points to `.brain/templates/DM-PROTOCOL.md`, while Phase 5 deploys the new file only into main at [AGENT_BRAIN_DM_GSD_PLAN.md:457](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:457). A sibling with a stale or missing `.brain` cannot follow that literal reference. Use an explicitly resolved main-vault path or install the protocol alongside the skill. **Verified: 100/100.**

#### [MEDIUM] Phase 5–6 still relies on an uninstalled bare `brain` command — [AGENT_BRAIN_DM_GSD_PLAN.md:460](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:460)

The runbook uses bare `brain install`, `brain inbox`, `brain dm take`, and `brain dm @all` at lines 460, 474, 482, and 494. Neither the runbook nor `cmd_install` establishes a PATH command, and none exists in the measured environment. Use the canonical `<main>/.brain/bin/brain` everywhere and state the required target-repository working directory. **Verified: 100/100.**

#### [MEDIUM] `_atomic_place` reports success when the destination is a directory — [bin/brain:68](/Users/amap3i/agent-brain/bin/brain:68)

If `SKILL.md` or `settings.json` is a directory—or a symlink to one—`mv temp dest` moves the temp inside that directory and exits zero. Installation then prints success without replacing the intended file. Reject non-regular/symlink destinations, validate parents, and verify the final destination type. **Verified: 100/100.**

#### [MEDIUM] Trailing-newline malformed names can permanently block failed routing — [bin/brain:441](/Users/amap3i/agent-brain/bin/brain:441)

`_dm_failed_dest` returns an arbitrary filesystem path through command substitution at [bin/brain:462](/Users/amap3i/agent-brain/bin/brain:462). POSIX command substitution strips trailing newlines. For invalid `pending/bad\n`, the helper checks `failed/bad\n` but returns `failed/bad`; if that path is occupied, routing aborts and the early pending entry blocks every retry. Return through state rather than text, or encode/hash malformed names. **Verified: 100/100.**

#### [MEDIUM] User-facing delivery semantics still promise exactly-once behavior — [AGENT_BRAIN_DM_GSD_PLAN.md:114](/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:114)

The plan promises “exactly once,” while the authority explicitly specifies duplicate-biased at-least-once recovery at [.context/seams/dm-v1.1-queue.md:135](/Users/amap3i/agent-brain/.context/seams/dm-v1.1-queue.md:135). The lane-facing protocol at [templates/DM-PROTOCOL.md:20](/Users/amap3i/agent-brain/templates/DM-PROTOCOL.md:20) does not warn that already-emitted work can replay. Correct the promise and tell consumers to make side effects idempotent or check durable state before repeating them. **Verified: 100/100.**

#### [MEDIUM] The deployment test never exercises the installed global dispatcher — [test/dm.sh:2316](/Users/amap3i/agent-brain/test/dm.sh:2316)

D.P1 calls the source engine directly. The install suite explicitly avoids checking merged settings contents, and M7 mutates emitted `$BRAIN/bin/brain` strings rather than the `$r/.brain/bin/brain` dispatchers at [bin/brain:1513](/Users/amap3i/agent-brain/bin/brain:1513). The current dispatcher appears correct, but a stale-sibling regression remains green. Install settings in the fixture and execute the installed hook command from the stale sibling. **Verified: 100/100.**

### Low findings

| Finding | Evidence and fix | Verification |
|---|---|---:|
| Mutation generation is BSD-only | [`sed -i ''`](\/Users/amap3i/agent-brain/test/mutation-probe.sh:91) fails closed under GNU sed. Use a portable temporary rewrite. | 100/100 |
| Phase 6.7 expects delivery too early | [The runbook](\/Users/amap3i/agent-brain/AGENT_BRAIN_DM_GSD_PLAN.md:511) says immediate reboot delivers, while fresh claims intentionally survive 600 seconds. Specify wait → pending event → watcher take. | 100/75 |
| Boot poison isolation is unpinned | [U.H2](\/Users/amap3i/agent-brain/test/dm.sh:2375) and M8 exercise only `dm take`, not the separate SessionStart loop. Add a mixed poison/healthy boot case. | 100/100 |
| Hook budget wiring is unpinned | [U.H6](\/Users/amap3i/agent-brain/test/dm.sh:2532) tests only live take; M4 mutates the global constant, not hook subtraction. Add a hook-specific scenario and mutant. | 100/100 |
| Directory-collision assertion can pass on forbidden nesting | [U.H4](\/Users/amap3i/agent-brain/test/dm.sh:2492) searches recursively, while M10 is killed by other limbs. Assert a distinct regular direct child. | 100/100 |
| Multi-site mutants overclaim per-line evidence | [M3/M7/M12](\/Users/amap3i/agent-brain/test/mutation-probe.sh:127) alter multiple sites, so an exact combined kill does not pin every changed limb. Split by site. | 100/100 |
| Install witness examines only the last writer | [`rename_verdict`](\/Users/amap3i/agent-brain/test/commit-install.sh:387) can accept unsafe direct overwrite followed by a safe rename. Reject every unsafe earlier writer. | 100/100 |
| Mutant fixtures derive a different distribution root | [Mutants live directly under `$PROBE_TMP`](\/Users/amap3i/agent-brain/test/mutation-probe.sh:12), while [`cmd_init`](\/Users/amap3i/agent-brain/bin/brain:1546) derives assets from `$0`. Preserve the production layout around the mutant. | 100/100 |

### Discarded Candidates

One verification-slate candidate was discarded. The proposed quoted-command/permission-rule mismatch does not occur in the installed Claude Code 2.1.221 matcher: it normalizes balanced quoting from the first executable token before applying the documented prefix rule. Quote normalization is not publicly guaranteed, so upgrades retain a small compatibility risk. See the current [Claude Code permission syntax](https://code.claude.com/docs/en/permissions).

### Checks Run

- Read the complete round-2 brief, full required source/test/template/runbook files, prior review, and `main...HEAD` diff.
- Eight independent FIND passes and eight verification roles; 25 candidates entered verification, 24 survived, one was discarded after tie-break.
- Read-only `/bin/sh`/`dash` probes for glob semantics, multibyte `${#}`, locale-sensitive decimals, arithmetic failure, and trailing-newline command substitution.
- Official jq and Claude Code documentation review; installed Claude Code matcher inspection.
- `git diff --check main...HEAD` found only trailing whitespace in historical review Markdown, excluded as non-material style noise.
- Per instruction, the test suites were not run. The orchestrator’s supplied `60/60`, `15/15`, syntax, shellcheck, and `12/12` mutation results were recorded; the claimed dash runtime coverage is limited by the verified harness issue above.
- No files were edited. The pre-existing untracked `docs/AGENT-DM-CHANNELS.md` remains unchanged and was excluded from the explicit `main...HEAD` target.

Codex session ID: 019fcded-0b9f-7e21-9510-b566deeef2b1
Resume in Codex: codex resume 019fcded-0b9f-7e21-9510-b566deeef2b1
