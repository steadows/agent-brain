# Lane-to-lane DM — adversarial review findings

**Reviewed snapshot:** `26fb14b..379b6e6` (`HEAD` at review time)  
**Review mode:** single agent, findings only, no implementation edits  
**Task:** `task-msdqe49w-p6g6z1`

## 1. In-flight sends can be permanently stranded during rotation

- **File:** `bin/brain`
- **Line:** 241–246, 256–276, 747–776
- **Category:** state-machine
- **Severity:** HIGH
- **Finding:** `mv` does not fence writers that already opened the old inbox. Such a writer can append to the renamed archive after `_dm_digest` has read it. That archive is never processed again, while the new inbox remains empty.
- **Evidence:** A timing-controlled fixture paused a sender after opening the append redirection, completed SessionStart rotation/delivery, then released the write. Sender and two subsequent boots all exited 0; the message existed in `read/*.jsonl`, appeared in neither boot context, and the inbox was empty.
- **Fix:** Replace rotating JSONL with uniquely named per-message files written to temporary files and atomically renamed into a pending queue, then atomically claim them at delivery. Add an interleaving test around open → rotate → write.

## 2. Concurrent inbox creation can truncate a successful DM

- **File:** `bin/brain`
- **Line:** 220–246
- **Category:** concurrency
- **Severity:** HIGH
- **Finding:** `_inbox_ensure` implements creation as `[ -f "$_ie" ] || : > "$_ie"`. Two senders can both observe absence; one can create and append, after which the other executes `: >` and erases the first message. Both commands subsequently report and journal success.
- **Evidence:** A scheduling barrier paused sender B after its failed `-f` test. Sender A completed successfully; B then resumed. Both returned 0, but the inbox contained one line, retaining B and losing A. The frozen suite sends sequentially and does not catch this.
- **Fix:** Never truncate during ensure; `: >> "$_ie"` provides non-truncating create semantics. Add a two-sender absent-inbox race test.

## 3. The new commit guard can still commit DM bodies

- **File:** `bin/brain`
- **Line:** 567–598
- **Category:** security
- **Severity:** HIGH
- **Finding:** The remediation is neither comprehensive nor fail-closed. It removes only paths appearing in `diff --cached`; already-tracked inboxes are unaffected because ignore rules do not apply to tracked files. It also continues when appending `dm/` fails, then executes `git add -- .brain`, restaging the inbox.
- **Evidence:** Two isolated reproductions:
  - With an already-tracked inbox, `brain commit` returned 0, added `dm/` to `.gitignore`, but left the inbox tracked and committed a new `SECRET_BODY_TRACKED` record.
  - With an untracked inbox and read-only `.brain/.gitignore`, the append emitted `Permission denied`, yet `brain commit` returned 0 and committed `SECRET_BODY_UNIGNORED`.
  - A DM created after the pre-check but before `git add` is an additional TOCTOU path.
- **Fix:** Fail if the ignore invariant cannot be written and verified; remove every path returned by `git ls-files -- .brain/dm`, not merely staged diffs; construct the index, purge DM paths again, and abort unless the final index contains none. Scan final staged blobs rather than pre-add working files.

## 4. Inbox symlinks escape the vault and inject external files

- **File:** `bin/brain`
- **Line:** 212–224, 241–246, 256–276
- **Category:** security
- **Severity:** HIGH
- **Finding:** Slug validation confines the textual path but no code rejects symlinked lane directories, inboxes, or `read/` directories. Sending follows an inbox symlink for append; rotation moves that symlink and `_dm_digest` follows it for startup injection.
- **Evidence:** With `dm/target/inbox.jsonl` linked to a file outside `.brain`, `brain dm` returned 0 and appended JSON to the external file. SessionStart also returned 0 and injected the external file’s pre-existing secret into `additionalContext`; the archive remained a symlink.
- **Fix:** Reject symlinks and non-regular inbox objects throughout the path. If same-user lanes are a security boundary, shell-level prechecks are still TOCTOU-prone; use a small `openat`/`O_NOFOLLOW` helper with trusted directory descriptors.

## 5. The `_require_brain` remediation still accepts a poisoned variable pair

- **File:** `bin/brain`
- **Line:** 139–146
- **Category:** security
- **Severity:** HIGH
- **Finding:** Requiring `ROOT` alongside inherited `BRAIN` does not establish provenance or require `BRAIN="$ROOT/.brain"`. Supplying both still bypasses `brain_root()` completely for every composed command.
- **Evidence:** From a real git repository containing its own `.brain`, invoking DM with inherited `ROOT` and `BRAIN` pointing at a second non-git tree returned 0 and wrote exclusively to the second tree.
- **Fix:** Reset a non-exported resolution sentinel at process entry. Only short-circuit after this process has run `brain_root()`, canonicalized the result, and established the exact `$ROOT/.brain` relationship.

## 6. The lock-free record-size premise is false

- **File:** `bin/brain`
- **Line:** 13–18, 235–246, 288–291
- **Category:** concurrency
- **Severity:** MEDIUM
- **Finding:** The cap measures source characters, not the encoded JSON record. Escaping can more than double its size, and sender/recipient metadata is uncapped. More fundamentally, `PIPE_BUF` guarantees apply to pipes/FIFOs, not concurrent appends to regular files, and POSIX does not require shell `printf` to issue one write.
- **Evidence:** On this machine `PIPE_BUF` reports 512 bytes. A permitted 4,096-character ASCII body encoded to 4,167 bytes; 4,096 quote characters encoded to 8,263 bytes. The frozen suite exercises only short records.
- **Fix:** Prefer the per-message atomic-rename queue described above. If JSONL is retained, validate encoded byte size after `jq` and use a one-syscall helper under an explicitly documented filesystem guarantee.

## 7. Journal failures are swallowed after delivery

- **File:** `bin/brain`
- **Line:** 185–197, 310–327
- **Category:** cascade-failure
- **Severity:** MEDIUM
- **Finding:** Direct and broadcast DM paths ignore `_announce_as` failure. A DM can therefore be delivered without its required call-log record while stdout and exit status claim success.
- **Evidence:** With today’s journal read-only, direct DM returned 0, printed `dm → @target`, and stored the message. The journal contained no call-log line; stderr alone showed `Permission denied`.
- **Fix:** Check journal creation and append results. Because delivery already happened, return nonzero with an explicit “delivered but audit logging failed” result rather than suggesting the caller resend blindly.

## 8. The production deployment omits the new protocol file

- **File:** `AGENT_BRAIN_DM_GSD_PLAN.md`, `bin/brain`, `templates/navigation-standards.SKILL.md`
- **Line:** Plan 448–450; engine 852–856; skill 73
- **Category:** compatibility
- **Severity:** MEDIUM
- **Finding:** Phase 5 copies only the updated navigation template, while `brain install` likewise copies only that skill. Existing-vault `brain init` is a no-op and `--force` is forbidden. Consequently `.brain/templates/DM-PROTOCOL.md` is never deployed, although the installed skill directs agents to read it.
- **Evidence:** Following the documented deployment sequence leaves the referenced on-demand file absent in the production vault.
- **Fix:** Explicitly deploy and verify both `navigation-standards.SKILL.md` and `DM-PROTOCOL.md` before enabling the engine.

## 9. The machine-wide engine deployment is not atomic

- **File:** `AGENT_BRAIN_DM_GSD_PLAN.md`
- **Line:** 434–450
- **Category:** compatibility
- **Severity:** MEDIUM
- **Finding:** The plan specifies an in-place `cp` over the one script used by all 13 lanes. `cp` may truncate the destination before rewriting it; a concurrent SessionStart, PreToolUse, DM, or commit invocation can execute an empty or partial mixed-version script.
- **Evidence:** POSIX `cp` provides no atomic replacement guarantee, while the plan explicitly states deployment is live and machine-wide.
- **Fix:** Copy to a same-directory temporary file, set permissions, run `sh -n`, then atomically `mv` it over the deployed engine.

## 10. Idle lanes hide an uncleared open dialog

- **File:** `bin/brain`
- **Line:** 348–356
- **Category:** correctness
- **Severity:** MEDIUM
- **Finding:** `dialog_with` is read only inside the `active|blocked` branch. An idle lane remains visible in status but its open-dialog marker disappears—the exact stale state the field is intended to expose.
- **Evidence:** A fixture with `status: idle` and `dialog_with: bravo` returned 0 and listed the idle lane, but emitted no dialog information. The frozen positive scenario tests only `status: active`.
- **Fix:** Render `dialog_with` independently of active/blocked status, with a stale warning for idle/done states, and cover those combinations.

## 11. Two sessions for one feature become duplicate live consumers

- **File:** `bin/brain`, `templates/navigation-standards.SKILL.md`
- **Line:** Engine 747–776; skill 66–67
- **Category:** concurrency
- **Severity:** MEDIUM
- **Finding:** Every SessionStart for a feature is instructed to watch the same inbox, with no receiver ownership or deduplication. Two simultaneous sessions for one feature therefore both observe and act on every subsequent live DM.
- **Evidence:** Both hooks resolve the same concrete path; the frozen test checks only that the path is injected and never starts competing watchers.
- **Fix:** Add a stale-safe receiver lease, or introduce message IDs plus an atomic claim/ack ledger so only one session processes each message.
