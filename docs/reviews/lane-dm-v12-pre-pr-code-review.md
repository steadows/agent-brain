# Pre-PR code review — DM v1.2 arc (`503519b..bac6d9a`)

**Verdict: NOT READY — 5 HIGH / 7 MEDIUM.** Gate run 2026-08-04 by @pm (orchestrator-side,
5 Claude reviewers + confidence scoring + a single-agent Codex adversarial sweep at `--effort max`).

**Where this round landed: 12/12 product-code defects, 0 test-infrastructure defects.** This is
not the DT-792 shape — the frozen suite is doing its job; the defects are in the engine.

Suites at review time: `test/dm.sh` 54/54, `test/commit-install.sh` 15/15 under `sh` AND real
dash; `shellcheck` 11 = baseline. **Every finding below is invisible to those suites.**

---

## HIGH — fix before PR

### H1. Non-regular queue entries starve every message behind them — MEASURED
`bin/brain:297` (`_dm_dir_ok`), `:485` (`_dm_pending_digest`), `:539` (take loop), `:1191` (hook loop)

A symlink/directory/FIFO in `pending/` **consumes a batch slot but is never quarantined**: the
loop counts the entry, `_dm_dir_ok` rejects it, `_dm_pending_digest` returns 1 (transient), and it
stays pending forever. 40 of them fill the entire `DM_INJECT_MAX_LINES` window on every
invocation.

**Reproduced** (scratchpad fixture, 40 symlinks lexically ahead of one valid message):
```
planted 41 entries
rc=1   emitted HEALTHY? 0   lines emitted: 0
valid msg STILL in pending? YES-STARVED
failed/: 0   read/: 0
SECOND run (does it ever drain?): 0
```
Permanent head-of-line blocking, reachable by the in-scope same-user-plants-a-file threat model,
and it happens **before** jq is ever consulted (independent of H2).

**Fix:** treat a non-regular direct child of `pending/` as structurally invalid — collision-safely
rename the *directory entry* into `failed/` without dereferencing it. Parent components still
validated. Needs a scenario with ≥40 rejected entries followed by a valid message.

### H2. jq's parse-error exit code is version-dependent; the classifier hard-codes 5
`bin/brain:495-504` (`_dm_pending_digest`)

Quarantine-vs-transient is decided by `_dm_digest`'s jq exit code, with `5` meaning "structurally
invalid." **Verified in Docker: jq 1.6 (Debian bookworm, Ubuntu 22.04 — current stable) exits `4`
for a JSON parse error; jq 1.7.1 exits `5`.** On jq 1.6 a corrupt file is never quarantined,
retries on every boot forever (v1.2 deliberately deleted the attempt counter, and the map rejects
age-based expiry), and — combined with the 40-slot cap — a handful at the front of the queue
starve everything behind them. `_dm_jq_preflight` cannot catch this: it probes `utf8bytelength`
and `tojson`, never the exit-code contract.

**Fix (preferred):** stop deriving invalidity from a magic exit code — probe the deployed jq's
actual parse-error code once in `_dm_jq_preflight` and classify against the recorded value; or
split validation so the verdict rides on jq's stable `-e` boolean contract.

### H3. The `error()`-exit-code contract is a second undeclared jq dependency
`bin/brain:437-441` (`_dm_jq_preflight`) vs `:495-500`

Related to H2 but distinct: the preflight's probe program never calls `error()`, so it provides
**zero evidence** about this jq's `error()` exit convention — which is exactly what the classifier
depends on. Verified locally as 5 on jq 1.7.1; declared nowhere.

**Fix:** extend the preflight with `jq -n 'error("x")' >/dev/null 2>&1; [ $? -eq 5 ]` (ANDed with
the existing check) so a divergent jq fails safe into "leave everything pending," matching how a
missing `utf8bytelength` already behaves.

### H4. A filename with embedded whitespace archives an un-emitted message — MEASURED
`bin/brain:353` (`_dm_id_ok`), `:1237` / `:1249` (`set -- $_valid_names`)

`_dm_id_ok`'s `[0-9]*` case-glob admits **whitespace** inside the PID field, and the SessionStart
path round-trips accepted names through a space-delimited string reparsed with unquoted `set --`.

**Reproduced** (grammar + splitting harness):
```
ACCEPT: [20260803T000000Z-12 20260805T000000Z-123]
set-- split of the crafted name yields 2 args: [$1=20260803T000000Z-12] [$2=20260805T000000Z-123]
```
With a 41-entry queue (crafted name first, 39 ordinary, and a real `20260805T000000Z-123` last),
the hook digests only the first 40 — but the split promotes the *last* file's name into the
archive list, moving a message to `read/` **whose body was never emitted**. That is an
emit-before-move violation: UR-1's silent loss, through a new door.

*Nuance vs the sweep's wording:* glob metacharacters are correctly **rejected** in that position
(`20260803T000000Z-1*` → reject). Whitespace is the live hole.

**Fix:** enforce the producer grammar with explicit digit-only checks, **and independently** drop
the delimiter round-trip — accumulate archive names as quoted positional parameters so a filename
is always exactly one element. Both, not either.

### H5. Inherited `_DM_ID_TS` can redirect a send outside `pending/` — PRE-EXISTING
`bin/brain:374-375` (`_dm_new_id`), `:388` (`_dm_send`)

`_dm_new_id` trusts a non-empty inherited `_DM_ID_TS` and `_dm_send` never validates the minted id
before composing a path. `_DM_ID_TS='../read/20260804T000000Z'` places the file directly into
terminal `read/` — `cmd_dm` reports success, no consumer ever emits it; more `../` escapes
`.brain/dm` entirely. Also, a `_now_compact` failure is masked by the later successful `printf`,
yielding a malformed `-<pid>` id that `_dm_send` still uses.

**Provenance: present identically in v1.1 at `503519b:396` — NOT introduced by this arc.** The
file clears a different vault-resolution sentinel at process entry but never this one. Reported
because a security HIGH that predates the diff is still a security HIGH; the arc is simply not its
author.

**Fix:** clear/ignore inherited `_DM_ID_TS`, require `_now_compact` to succeed, validate the final
id against the strict grammar before path composition, and assert the destination's literal parent
is the intended `pending/`.

---

## MEDIUM

### M1. jq forks on every boot, including the empty-queue common case (score 80)
`bin/brain:527-530`, `:1187-1190` — the preflight runs *before* any emptiness check. v1.1 paid
**zero** DM jq forks on an empty-queue boot (verified at `503519b`: `[ -n "$_dt_claims" ] || return 0`).
With a broken jq the warn fires on **every** boot with nothing to digest, permanently polluting
`.hook-errors.log` and tripping `cmd_status`'s banner; and `dm take` on an empty queue returns
**1** where v1.1 returned **0** — an unannounced rc contract change on a no-op.
**Fix:** gate the preflight behind a fork-free "is there anything here" probe, in both paths.

### M2. `_dm_id_in_use` is blind to collision-bumped names (score: confirmed, second-order)
`bin/brain:342-349` vs `:400-417`. v1.2 pairs an *exact-match* id scan with a *bumping* archive.
Once `read/<id>` is bumped to `<id>.collision-…`, the plain slot reads free and the same id can be
minted again — defeating the id's role in replay recognition (must-survive #8). v1.1 was safe by
accident: its glob (`<id>.a*`) still matched bumped names, and its ack refused rather than bumped.
**Fix:** glob-match `…/$_iu_id*` per state.

### M3. Archive collisions bump silently; `_dm_collision_dest` failures are traceless (score 75)
`bin/brain:509-521`, `:404`, `:408`. v1.1's `_dm_ack` refused an occupied destination **with a
warn**; v1.2 silently bumps. `_now_epoch`/`cksum` failures return 1 with no diagnostic, and
`cmd_dm_take`'s `|| _dt_rc=1` adds none — so a post-emit archive abandonment can be completely
invisible. **Fix:** warn on bump-taken, warn inside both internal failure returns.

### M4. `id` sits outside `bounded()`'s truncation invariant (score 100)
`bin/brain:469`. Every other digest field is sliced by `[0:$limit]`; `id` is not. The per-line
≤2000-byte guarantee now silently depends on `_dm_id_ok`'s 255-byte cap upstream, and
`DM_DIGEST_ENVELOPE=512` was sized for a **4**-field envelope. Not reachable with engine-minted
ids — but the bound stopped being a proof. **Also: this item was declared "routed to code review"
in `bac6d9a`'s commit message but never landed on ROADMAP's carry list.** Fix the comment, add the
carry entry.

### M5. Phase 5.6 rollback runbook is stale and names the wrong failure mode
`AGENT_BRAIN_DM_GSD_PLAN.md:486,489` — still says "confirm every lane's `pending/` and `claimed/`
are empty"; `claimed/` no longer exists. Worse, the real rollback hazard is misdescribed: a v1.1
engine does not merely strand v1.2-minted messages, it **quarantines** them — `_dm_claim_all`'s
`.a<k>` grammar rejects every bare-`<id>` name on first contact, so an operator seeing a non-zero
`failed/` after rollback has no documented reason to suspect false-positive grammar rejection.
Collision-bumped names are **not** a hazard (both engines' suffix grammar is identical and lives
only in `read/`/`failed/`). Also: the seam map's blocking "quiesce detached sweepers before swap"
migration gate appears **nowhere** in Phase 5 (currently inert — v1.1 was never deployed — but the
invariant is general). **Fix:** update 5.6's drain check, name the quarantine mechanism, fold a
one-line process check into 5.2.

### M6. `navigation-standards.SKILL.md` never mentions the replay contract (score 75)
The at-least-once/idempotency guidance lives only in `DM-PROTOCOL.md`, explicitly gated to "read
before your first dialog, not every session." A lane receiving only broadcasts/nudges never sees
it and can double-act on a replayed digest line. **Fix:** one line in the SKILL's DM section.

### M7. `_hook_session_start` at 83 lines / nesting depth 5 (score 75)
`bin/brain:1167-1249`; v1.1 topped out at depth 4. Extract the pending-batch scan.

### M8 (disputed severity). The take path emits no "more remain" signal
Reviewers split, both positions recorded. **Performance/API:** *not* a seam-map breach — "the
emitted context" is the map's term of art for the SessionStart payload, the silent cap is
unchanged v1.1 shape, and `DM-PROTOCOL.md` already prescribes repeat-while-pending.
**Observability:** the diff *introduces* the signal on one consume path and not its sibling,
creating a fresh asymmetry; an operator cannot distinguish "drained" from "capped, N left."
**Dispatcher resolution:** add a stderr warn (observability), do **not** claim the map requires it
(contract), and declare the scoping in the suite's gaps list.

---

## Adversarial sweep (Codex, single agent, `gpt-5.6-sol --effort max`, 23m46s)

Found **4 issues the 5-agent Claude pass missed** — H1, H4, H5 above, plus:

### M9. `_more_dm` reflects a stale glob snapshot; the watch-then-arm order strands mail
`bin/brain:1186`, `:1220`, `:1230`. A send renamed into `pending/` *after* the glob expands is
absent from the snapshot, and its filesystem event fires before the agent has armed its watcher —
while `_more_dm` stays 0. Likewise a transient digest failure among ≤40 entries leaves its source
pending without setting the flag, and an archive failure happens *after* the continuation text was
already emitted. With no later queue mutation the message can sit silent for an entire session.
**Fix:** watch-then-drain — arm the watcher, immediately `dm take` until empty, *then* react to
events; and set the continuation flag on pre-emission outcomes that leave a source pending.

**Disagreements with Claude findings:** none. **Verification:** H1 and H4 were independently
reproduced by the orchestrator before acceptance (see the transcripts inline above); H5's
provenance was checked against `503519b` and corrected from the sweep's framing.

---

## Verdict

**NOT READY for PR.** H1–H5 are fix-before-PR. H1, H2 and H4 each independently break the
feature's one promise — a message that is never delivered (H1), never quarantined and retried
forever (H2), or archived without being emitted (H4). M1–M9 are fix-soon; M5 is deploy-blocking in
practice because it is the runbook an operator follows *during* a rollback.

The frozen suite passed all 54 scenarios against every one of these defects — which is the
strongest argument for keeping this gate, and for the coverage additions listed with each fix.
