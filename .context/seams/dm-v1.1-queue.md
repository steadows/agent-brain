# Seam map — DM v1.1: per-message-file queue   (2026-08-03)

**Status:** `[~]` DRAFT — reuse table and new seams pending the Stage-2 inventory.
**Authorities:** `docs/lane-dm-ultrareview-findings.md` (verdict NOT READY, 10 findings) ·
`AGENT_BRAIN_DM_GSD_PLAN.md` §7.5 (disposition of all 10) · `ROADMAP.md` v1.1 entry
(promoted to ship-blocking, Steve 2026-08-03).

## Scope

Replace the single shared `.brain/dm/<lane>/inbox.jsonl` with **one file per message**: write to a
temp name, atomically rename into `dm/<lane>/pending/`, atomically claim at delivery, ack after
the message has actually reached the receiving session. This removes the interleaving surface
that produced accepted findings #1/#6/#11, and — the reason it became ship-blocking — closes
**UR-1**, where SessionStart moves the inbox to terminal `read/` state *before* digesting or
emitting it, so an interrupted boot loses those messages with no concurrency involved. It also
absorbs **UR-3** (a live-observed message is never claimed, so it replays as unread at the next
boot) and **UR-4a** (the commit guard's cleanup wedges permanently once an inbox is tracked).

Riding along, because they are small and must land before any deploy: **UR-2** (symlink
validation on every path component, including `_inbox_rotate`, which validates nothing), **UR-4b**
(`git check-ignore` instead of grepping `.gitignore` for a literal line), **UR-7** (`cmd_install`
checks neither `mkdir` nor `cp` and can report success over a partial skill).

Everything lives in **one module** — `bin/brain` — plus the frozen `test/dm.sh` and the two
templates. There is no cross-module dependency question to answer.

## Flags

- **No `ARCHITECTURE.md` in this repo, and none is warranted.** `agent-brain` is a single
  1,020-line POSIX-`sh` script with one logical module; the architecture-first rule's threshold is
  3+ logical modules. Recording the decision here so a later session does not re-open it. The
  dependency-direction stage of this pass is therefore vacuous, not skipped.
- **The frozen suite pins the OLD storage contract.** `test/dm.sh` (24 scenarios) asserts
  `inbox.jsonl` semantics directly — a per-message queue changes what those scenarios mean, so the
  suite genuinely reopens. Every test change routes through `test-writer` + `spec-watchdog`,
  unconditional and mechanically enforced. UR-9 and UR-10 (two suite-adequacy holes) get fixed in
  the same reopening at no extra cost.
- **POSIX `sh` cannot close the symlink race properly.** `openat`/`O_NOFOLLOW` are unavailable, so
  UR-2's fix restores *parity with what the code already claims* and the same-user TOCTOU residual
  remains a documented limit. Do not let the fix's wording overclaim.

## Verified independently by the orchestrator (not taken on the reviewer's word)

- **UR-1** — `_inbox_rotate` (`bin/brain:268`) performs `mv "$_ri" "$_ra"` and only then does
  `_hook_session_start` build `_dm_block` and call `_emit_session_ctx`. Nothing anywhere scans
  `read/`. Confirmed by reading the control flow.
- **UR-2** — `_inbox_ensure` (`bin/brain:225`) tests `-L` on the lane directory and the inbox, but
  never on the `dm` root; `_inbox_rotate` performs no validation at all and runs *first* at
  SessionStart. Confirmed.
- **UR-8** — `_recent_journal` (`bin/brain:347`) greps **today's journal only** for
  `(^| )<lane> | @<lane>` and takes the last 5 lines. A generic `announce` is authored by the
  sender, so it matches no other lane's filter, and nothing crossing a date boundary matches at
  all. `templates/DM-PROTOCOL.md:10` nonetheless advertises "every lane, at its next boot".
  Confirmed — and slightly broader than reported (the date-boundary limb is real too).

## Reuse table

| capability | existing (`file:line`) | verdict | note |
|---|---|---|---|
| atomic file placement | **none — no helper exists** | **NEW** | 6 inline temp+rename sites, no function wrapping any of them. This is the headline seam. |
| ↳ bare rename as claim | `_inbox_rotate` `bin/brain:274` | USE (pattern) | `mv "$_ri" "$_ra"` — the closest existing analogue to a claim. |
| ↳ first-file-in-dir + break | `cmd_apply` `bin/brain:717` | **USE** | `for _f in …/*.md; do [ -e "$_f" ] && { _pf="$_f"; break; }; done` — the strongest existing analogue for a claim loop. |
| filename-safe timestamp | `_now_compact` `bin/brain:38` | **USE as-is** | `%Y%m%dT%H%M%SZ`; lexicographic sort == chronological. 1-second resolution. |
| ts+pid uniqueness recipe | `_inbox_rotate` `bin/brain:273` | EXTEND | `$(_now_compact)-$$` — but `$$` is constant for a process, so N sends from ONE invocation collide. Needs a per-message discriminator. |
| slug from a filename | `_agent_slug` `bin/brain:90` | USE | The inverse read of a queue filename. |
| slug-component validation | `_feat_ok` `bin/brain:210` | **EXTEND (defect — see below)** | Rejects `''`, `.*`, `*/*`, `..`, space. Does NOT reject a leading `-`, tab/newline, glob chars, backslash, `~`, or over-long names. |
| symlink refusal | `_inbox_ensure` `bin/brain:229,231` | EXTEND | These two `-L` tests are the **complete census** for the whole 1,020-line file. No `readlink`, no `realpath` anywhere. |
| canonicalization | `brain_root` `bin/brain:31` | USE | `cd … && pwd -P` is the only canonicalization idiom present. |
| locking | `_lock_acquire/_release` `bin/brain:126` | **do NOT use on the queue path** | mkdir-spin, ~5s ceiling, **no staleness break, no `trap`**. The documented reason DM avoids it (`bin/brain:249`) still holds under the new design. |
| bounded render for injection | `_dm_digest` `bin/brain:280` | **EXTEND (signature change)** | Takes ONE file, line-oriented (`wc -l`/`tail`/`cut`), equates lines with messages. N files → must change. |
| injection bounds | `DM_INJECT_MAX_LINES/COLS` `bin/brain:21` | USE as-is | 40 / 2000. |
| body-size cap | `DM_MAX_BODY` `bin/brain:20` | **RECONSIDER** | Exists solely to keep one append under `PIPE_BUF`; that rationale **evaporates** under one-file-per-message. |
| glob-safe dir iteration | idiom at 12 sites, e.g. `bin/brain:162` | USE the idiom | `for f in dir/*; do [ -e "$f" ] || continue` — absorbs literal-pattern-on-no-match. A helper would be premature. |
| gitignore self-heal + index purge | `cmd_commit` `bin/brain:591,599,627` | **USE unchanged** | All six `dm` literals are **prefix-scoped**, so `dm/<lane>/pending/` is already covered by the existing `dm/` rule and the `rm -r --cached` recursion. No new-layout work needed here. |
| install `mkdir`/`cp` | `cmd_install` `bin/brain:892,895` | EXTEND | Return values unchecked (confirms UR-7). |

## Defects found during this pass that the ultrareview did NOT report

Recorded here because a seams pass is not supposed to silently absorb discoveries.

1. **`_feat_ok` (`bin/brain:210`) is looser than it should be — but the "option injection" reading
   does NOT hold, and I am recording that correction rather than banking the scarier claim.**
   The validator rejects only `''`, `.*`, `*/*`, `..` and a literal space, so it accepts a leading
   `-`, tab/newline, glob metacharacters, backslash and `~`. The inventory agent inferred that a
   slug like `-rf` therefore reaches `mv`/`cp`/`git` as an **option**. **Traced every call site —
   it does not.** All three consumers (`_inbox_path` `:219`, `_inbox_ensure` `:226`,
   `cmd_new_feature` `:435`) interpolate the slug into an **absolute** `$BRAIN/...` path, so the
   dash is never the first character of an argument. Globbing does not fire either: every
   expansion is quoted. The genuine residuals are (a) an embedded tab/newline surviving into a
   path that line-oriented consumers then mis-handle, and (b) no length bound. **Verdict:
   tighten as defence-in-depth alongside UR-2, and add `--` terminators — but do NOT file or
   describe this as a security vulnerability.** Severity: LOW, hygiene.
2. **Two temp+rename sites use a FIXED `.tmp` name** — `_set_fm_inline` (`bin/brain:122`) and
   `cmd_revert` (`bin/brain:743`). Two concurrent callers on the same file collide and one loses.
   Exactly the class of bug the new atomic-placement seam exists to prevent; converting these is
   nearly free once the helper exists.
3. **`cmd_install` and `_write_project_settings` `mktemp` into `$TMPDIR` and `mv` into `$HOME`** —
   a **cross-device** rename, which degrades to copy+unlink and is therefore **not atomic**.
   UR-7 asks for an atomic install; naïvely "checking the return value" would not have fixed this.
   The temp file must be created in the destination directory.
4. **`cmd_apply` releases a `governance` lock it never acquires** (`bin/brain:723,730`; acquired in
   `cmd_propose` at `:692`) — the lock is held *across process invocations*, and `_lock_release`
   has no ownership check, so it releases whoever's lock is there. Out of scope for v1.1; flagged.
5. **`_dm_digest`'s `cut -c1-2000` truncates mid-JSON**, emitting a syntactically broken object
   into a session's startup context. In scope, since the digest is being rewritten anyway.

## Design decisions — grounded in prior art, not invented

The per-message-file queue is a **maildir** (qmail, 1996) with one extra state, and the recovery
policy is **CERN dirq**'s. Deviating from either needs a reason; none was found.

1. **Storage layout:** `dm/<lane>/pending/` (maildir `new/`) → `dm/<lane>/claimed/` (maildir
   `cur/`) → `dm/<lane>/read/` (ack archive — keeps the existing transcript-pointer contract),
   plus terminal `dm/<lane>/failed/` (poison cap, decision 6b). Separate directories per state,
   because glob-per-state is the natural `sh` idiom. All plain siblings on one filesystem —
   never a mount/tmpfs overlay on any of them (`EXDEV` breaks every rename). ⚠ Scope honesty:
   maildir is the authority for send-side atomicity ONLY; it has NO claim protocol (it assumes
   one consumer — Dovecot ended up locking). The claim step's authority is lease-based queueing
   (SQS visibility-timeout contract) + dirq precedent, and the seam map says so rather than
   borrowing maildir's name for it.
2. **Send = write temp, atomic rename.** Maildir's core rule: "moving needs to be done using the
   atomic filesystem `rename()`"; link-then-unlink "risks message duplication" (Bernstein's spec,
   corroborated via Courier/Dovecot docs). **Temp = dot-prefixed name in `pending/` itself**
   (`.tmp-<id>`), not a separate `tmp/` dir: same-directory rename guarantees same-filesystem
   atomicity by construction, and `sh` globs skip dotfiles, so a torn temp is invisible to every
   reader with zero code. (This also dodges the cross-device trap found in `cmd_install`.)
3. **Message ID = filename = `<_now_compact>-<pid>` + a collision bump.** Time+pid is Bernstein's
   own convention; he also names PID reuse as the known hazard. We add a `-<n>` suffix bump if the
   target exists (possible only under same-second PID reuse — vanishingly rare locally, one `[ -e ]`
   test to close). Stable ID satisfies UR-3's "stable message IDs" requirement for free.
4. **Claim = rename `pending/<id>` → `claimed/<id>`.** `rename(2)` arbitration means two
   concurrent sessions of one lane each win a disjoint set — **structurally closes accepted
   finding #11** (double-consume) with no lock. Dovecot's docs confirm rename-as-claim is sound;
   its extra lock exists for `readdir`-consistency/IMAP-UID reasons that don't apply to us.
5. **Ack = rename `claimed/<id>` → `read/<id>`, ONLY after emission succeeded** (UR-1's fix: the
   terminal transition happens after delivery, not before). Hook path: claim → digest → emit →
   ack. Live path: claim → print → ack (print IS delivery there).
6. **Staleness recovery = wall-clock lease (SQS "visibility timeout" contract), judged from a
   claim-time stamp ENCODED IN THE CLAIM NAME — not file mtime.** ⚠ My first draft said
   "mtime lease, dirq-style" and that was a **bug the research caught**: dirq's mtime works
   because its claim primitive (`mkdir`/`link`) *creates* a fresh entry; ours is `rename`, which
   **preserves the send-time mtime** — a message that waited 10 minutes in `pending/` would look
   instantly stale the moment it was claimed. So: claim renames `pending/<id>.a<k>` →
   `claimed/<id>.a<k>.c<claim-ts>-<claimer-pid>`, and recovery judges `<claim-ts>` against
   **`DM_CLAIM_MAX_AGE=600`s** (dirq's `maxlock` default). No `kill -0` (PID reuse makes it
   unsound — LWN 773459), no boot-id sophistication (attested nowhere in real file queues), no
   locks. False staleness ⇒ duplicate delivery — the mandated direction; a backwards clock step
   biases the same way. Stale `.tmp-*` purged after 300s (dirq `maxtemp`). The claimer-pid
   component is **diagnostics/attribution only**, never a liveness test — and the unique claim
   name also closes an **ack-collision hazard** my draft had: with same-name claims, a stalled
   session A could ack a message that had been recovered and re-claimed by B; with per-claim
   names, A's ack targets a path that no longer exists and fails visibly (ENOENT).
6b. **Poison-message cap — `failed/` terminal state (research finding ①, adopted).** At-least-once
   + automatic recovery = a message that reliably kills its consumer is redelivered forever, to
   every boot. SQS's answer is the dead-letter queue after N receives. Name grammar carries a
   delivery-attempt counter: `pending/<id>.a<k>`; recovery renames with `k+1`, and at
   `k+1 > DM_MAX_ATTEMPTS=3` routes to `dm/<lane>/failed/` instead — surfaced in `brain status`,
   never auto-deleted. Adopted NOW because it changes the name grammar the reopened suite pins —
   structurally awkward to retrofit, cheap today. The immutable `<id>` substring is preserved
   across every transition (Bernstein's "preserve the uniq string" rule).
6c. **Claim-loss vs real-error are DIFFERENT failures (research consequence 2).** `mv` exits
   non-zero both when the source vanished (lost the race — normal) and on ENOSPC/EACCES/EXDEV
   (real trouble). Conflating them turns a full disk into "someone else took it." Contract: after
   a failed claim, re-test `[ -e pending/<name> ]` — gone ⇒ lost race, continue silently; still
   there ⇒ real error, warn loudly to `.hook-errors.log` and stop claiming. All queue `mv`s are
   `command mv -f --` (alias-proof, prompt-proof, option-terminated).
6d. **Durability boundary, stated honestly:** the design is robust against **process death**
   (kill, crash, interrupt — the entire realistic failure mode for 13 agent lanes) and NOT
   against power loss/kernel panic — POSIX `sh` cannot `fsync`. The docs say "process-crash-safe",
   never bare "crash-safe". (Research: rename atomicity is an observer guarantee, not a
   power-loss guarantee — the ext4 delayed-allocation lesson.)
7. **Wire format unchanged** (`from`/`to`/`ts`/`content`, jq-encoded, one JSON object per file).
   Ratified in v1; nothing in the redesign touches it.
8. **`DM_MAX_BODY` kept, rationale rewritten.** Its `PIPE_BUF` justification evaporates (no shared
   appends), but an unbounded body is still a storage/injection foot-gun. Same constant, new
   comment: bounds storage and digest cost, not atomicity.

## New seams

### `_atomic_place <content-producer> <dest>` — the ONE temp+rename home
consumers: `_dm_send` (message files) · `cmd_install` + `_write_project_settings` (UR-7 — temp
must move into the DESTINATION dir, fixing the cross-device non-atomicity found in Stage 2) ·
`_set_fm_inline` + `cmd_revert` (their fixed-`.tmp` collision bug) — **5 consumers, decided now**.
contract: write to `<dest-dir>/.tmp-$$-<n>`, then `mv -- tmp dest`; non-zero + temp cleanup on any
failure; never clobber-checks (rename semantics are wanted). deps: none. owns: nothing.

### `_dm_dir_ok <path>` — component validator (UR-2's fix)
consumers: `_dm_send`, `_dm_claim`, `_dm_recover`, `_dm_ack`, `_dm_digest`, `cmd_inbox` — every
queue touch. contract: reject symlink (`-L`) / non-directory at EVERY level walked (`dm` root,
lane dir, state dir); message files additionally `-L`-checked and required regular (`-f`).
Replaces the two-site ad-hoc checks in `_inbox_ensure`; `_inbox_rotate`'s zero-validation gap
dies with `_inbox_rotate` itself. TOCTOU residual documented at the helper, once.

### `_dm_new_id` — message-ID mint
consumers: `_dm_send` only (but the format is contract — filenames ARE message IDs).
contract: `$(_now_compact)-$$`, bump `-<n>` while target exists. Reuses `_now_compact` as-is.
**A fresh send mints attempt counter ZERO: `<id>.a0`** (gap (b) closed 2026-08-04 — the map was
silent; the RED suite pins `.a0` at Q.S/2 and this ruling ratifies it).

### `<claim-ts>` encoding — RULED: Unix epoch seconds (gap (a) closed 2026-08-04)
The map pinned `.c<claim-ts>-<claimer-pid>` without choosing an encoding. Ruling: **epoch
seconds** (`date +%s`), NOT `_now_compact`. Reason it isn't a coin flip: staleness is judged by
arithmetic (`now - claim_ts > DM_CLAIM_MAX_AGE`), and epoch seconds make that a portable integer
compare — parsing `_now_compact` back to epoch requires `date -j -f` (BSD) vs `date -d` (GNU),
exactly the portability fork a POSIX-sh engine must not stand on. Digits are filename-safe. The
RED suite's `age_claim` instrument detects either encoding, so no test change is forced by this
ruling — but the implementation and any future scenario pin epoch seconds.

### `_dm_claim_all <lane>` / `_dm_recover_stale <lane>` / `_dm_ack <lane> <claimed-name>` — lifecycle
consumers: `_hook_session_start` (recover → claim → digest → emit → ack-each) and the new live
path `cmd_dm_take` (claim → print → ack). contract: claim = `command mv -f --` of
`pending/<id>.a<k>` → `claimed/<id>.a<k>.c<claim-ts>-<pid>`; on failure re-test the source
(gone ⇒ lost race, skip silently; present ⇒ real error, warn + stop — decision 6c). recover =
parse `<claim-ts>` from the name, >600s ⇒ rename back to `pending/<id>.a<k+1>`, except
`k+1 > 3` ⇒ `failed/` (decision 6b). ack = rename the FULL claimed name into `read/<id>.a<k>`;
ENOENT on ack means the claim was recovered out from under us — warn, never die. All through
`_dm_dir_ok` first. Iteration guard everywhere: `[ -e "$f" ] || [ -L "$f" ] || continue`
(a broken symlink must be SEEN and refused, not silently skipped).

### `cmd_dm_take` — the live-consumption command (UR-3's fix)
consumers: the receiving lane's watcher (protocol tells the agent: on inbox activity, run
`brain dm take`). contract: recover → claim all → print each (digest-bounded) → ack each; exits 0
with no output when empty. This is what makes a live-observed message *claimed* instead of
merely *seen* — the next boot cannot replay it.

### `_dm_digest` — signature change (EXTEND, in place)
input becomes a directory-or-file-list of per-message files; keeps `DM_INJECT_MAX_LINES/COLS`
bounds; fixes the mid-JSON `cut` truncation (defect 5) by truncating the *content field*, not the
serialized object.

### Deleted, not extended
`_inbox_rotate` (its job — batch move + archive naming — no longer exists) · the `<ts>-<pid>`
archive-name recipe and its comment block · `_inbox_ensure`'s append-creation semantics
(`cmd_inbox` now ensures the directory tree and prints the `pending/` dir to arm on).

## Altitude decisions

- **No generic "queue library."** These helpers are DM-specific by name and path; the only
  consumer is the DM feature. A parameterized any-directory queue serves a hypothetical consumer —
  YAGNI, rejected.
- **No `tmp/` directory** — dot-prefix inside `pending/` does the same job with one fewer
  directory and zero reader-side code (globs skip dotfiles by default).
- **No lock anywhere on the queue path** — rename arbitration IS the concurrency control; reusing
  `_lock_acquire` (no staleness break) would reintroduce the wedge the design exists to remove.
- **No PID/liveness/boot-id staleness checks** — conform to the dirq convention (see decision 6);
  the sophistication would buy nothing but code.
- `_atomic_place` IS generic (not DM-named) because it has 5 consumers across 3 unrelated
  features today — the generality is paid for by current consumers, not hypothetical ones.

## UR fixes riding along (small, self-contained — sequenced with the rewrite, not inside it)

- **UR-4a:** `cmd_commit`'s cleanup wedge — allow the staged-deletion case: after the re-purge,
  the final fail-closed check must distinguish *staged additions* (refuse) from *staged deletions
  of un-tracked-on-purpose paths* (proceed). Commit via a sanitized index path per the
  ultrareview's sketch. The existing prefix-scoped `dm/` literals already cover the new subtree
  (Stage-2 finding) — no layout work.
  **⚠ RULING 2026-08-04 — UR-4a is a THREE-way constraint, not two.** The obvious fixes satisfy
  two and silently break the third. All three are mandatory:
  1. **Unwedge** — a staged deletion of an intentionally-untracked DM path must not abort, and
     must not abort on RETRY either (permanence is the defect; a one-shot success proves nothing).
  2. **No pathspec semantics on the commit** — `git commit -- .brain` re-reads the WORKING TREE
     for those paths, so a live inbox on disk can be committed even after the index was purged
     (the ultrareview's own reason for the sanitized-index sketch).
  3. **Still path-scoped IN EFFECT** — ONLY `.brain` paths may land in the commit. The engine
     advertises "path-scoped" in its usage (`bin/brain:1232`) and the current call is
     pathspec-scoped (`:866`). Dropping the pathspec to satisfy (1)+(2) makes `git commit` take
     the WHOLE index, sweeping a developer's unrelated staged work into
     `chore(brain): sync coordination vault`. **Measured by the audit: four independent candidate
     fixes — including the ultrareview's own temp-index sketch and the RED author's prototype —
     all did exactly this and still scored 12/12** before the path-scoping assertion existed.
  4. **The real index must agree with the new HEAD for `.brain` afterward** (added 2026-08-04,
     round 2 — this constraint was discovered *because* the fix for (3) broke it). The temp-index
     shape leaves the real index holding the PRE-sync `.brain` state while HEAD moves forward, so
     the just-synced files read as **staged deletions** against the new HEAD — and the developer's
     next ordinary `git commit -a` silently reverts the vault sync it just made. Measured: today's
     engine leaves `git status` clean and the marker survives; the temp-index prototype leaves
     `D .brain/research/marker.md` staged and the next `git commit -a` empties it. Today's engine
     avoids this only as a side effect of the pathspec form updating those index entries.
     **A commit the next git command undoes is not durability**, which is `cmd_commit`'s whole
     contract. Pin: after a successful commit, `git diff --cached --quiet HEAD -- .brain`.
  The shape that satisfies (1)-(3): seed a temp index from **HEAD**, stage only `.brain` paths
  into it (DM entries excluded), then `write-tree` → `commit-tree` → `update-ref`, leaving the
  real index untouched. This is NOT the same as seeding the temp index from the CURRENT index —
  that is precisely what swept the unrelated work. **But it does not satisfy (4) on its own**: the
  implementation must additionally reconcile the real index's `.brain` entries with the new HEAD
  WITHOUT disturbing any other staged path. **The verified shape is `git reset -q HEAD -- .brain`
  after `update-ref`** — NOT a blanket `git read-tree HEAD`, which fixes the index but silently
  un-stages the developer's unrelated work (measured: read-tree fails the "still staged" limb and
  nothing else). `reset` with a pathspec is index-only, so the working tree is never touched.
  Adversarially verified against partially-staged files inside AND outside `.brain`, a staged
  deletion, and a rename inside `.brain` — byte-identical to today's engine on every axis.
  **⚠ KNOWN LIMITATION, pre-existing, NOT closed by this fix (recorded 2026-08-04, round 3).**
  UR-4a's cleanup still wedges **permanently** for one class of legacy vault: `dm/` never ignored,
  the inbox **tracked and unmodified**, and its body containing a line matching the commit secret
  scan's `^[A-Z][A-Z0-9_]*=.+`. Mechanism: the pre-purge stages the DM deletion *before* the scan,
  and that staged deletion is what pulls the still-on-disk file into the scan's list — so
  `brain commit` aborts, and the staged deletion persists, so it aborts again on every rerun.
  (Remove the pre-purge and the file is tracked-and-unmodified, appears in neither
  `--others --modified` nor `diff --cached`, is never scanned, and the commit succeeds — which is
  why the pre-purge is **live code, not dead**, despite no scenario catching its removal.)
  Exposure is bounded: a real `inbox.jsonl` line starts with `{` and cannot match, so the trigger
  needs a truncated write, a hand-edit, or a pre-v1 body format. Today's engine behaves
  identically, so this is not a regression — but the fix does not complete the cleanup for every
  legacy vault, and any future claim that a purge is redundant must name both its architecture
  AND this secret-scan path.
- **UR-4b:** replace the `grep -qxF 'dm/'` ignore check with `git check-ignore --no-index`.
  **Audit note:** a fixed-string grep that special-cases the fixture (`grep 'dm/' && ! grep '!dm/'`)
  scores 12/12 — the negation spelling is the only discriminating axis, and `!dm/`, `!/dm/` and
  `!dm` all re-include while all three heal. The RED must parametrize over all three; that raises
  any non-`check-ignore` implementation to "reimplement gitignore matching."
- **UR-7:** `cmd_install` — check every `mkdir`/`cp`, route the skill copy through
  `_atomic_place`. (`cmd_init`'s `|| true` copies are out of scope — pre-existing, not
  deploy-load-bearing.)

## Flags (final)

- No `ARCHITECTURE.md` and none warranted (single-module repo; recorded above).
- The frozen suite reopens through `test-writer` + `spec-watchdog` — the storage contract it pins
  is being replaced wholesale. UR-9/UR-10 land in the same reopening.
- Templates co-change: `DM-PROTOCOL.md` + `navigation-standards.SKILL.md` must describe the take
  command and drop the inbox-file watch instructions; **UR-8's false `announce` promise gets
  narrowed in the same edit** (doc says "every lane at next boot"; code filters today-only +
  explicit-mention — verified at `bin/brain:347`).
- Deploy runbook additions (UR-5 rollback drain, UR-6 restart-and-ack gate) are plan-phase edits,
  not engine code.
