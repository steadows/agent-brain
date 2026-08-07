# Seam map — PR #10 bundle: the cursor-advance regression + the reject diagnostic

Pre-code design pass for the two fixes bundled onto `fix/serializer-batch-integrity` (Steve
authorized the bundle 2026-08-06 ~07:15, so the ~30-minute mutation probe runs once rather than
twice). `/simplify` verifies the finished diff against this map.

---

## ⚠ ERRATA — read before trusting a line number or a ruling below (2026-08-07)

This document is now tracked and ships with the repo, so its errors travel. Three corrections,
all found by review rather than by the author:

1. **Line numbers below are as-of-the-ruling and have DRIFTED.** The engine grew ~30 lines across
   this arc. Most consequentially, §4 discusses the per-id envelope reject as `bin/brain:1422`;
   that line is now **`:1451`** (and `:1422` is today `cmd_revert`'s rewrite call). The framing
   check is **`:1449`**. `_changes_snapshot` is **`:896`**, `_changes_commit` **`:912`**.
   **§4's probe co-change instructions read off these numbers — re-derive them, don't copy them.**
2. **"Clearing `_CHANGES_CURSOR` at process entry breaks `_atomic_place`" is NO LONGER TRUE.** It
   was true when written — an empty path made `_ap_dir=${""%/*}`=`""`, targeting `/.tmp-$$`. The
   consumer guard added in the same round (`[ -n "${_CHANGES_CURSOR:-}" ] || return 0`) means
   `_changes_commit` now returns before ever reaching the helper. Measured under `sh` and `dash`:
   an empty cursor produces **zero** helper calls. The guard is still the right place for the
   check; the absolute warning attached to it is stale.
3. **The "accepted append race" is no longer live.** A plain append between render and commit is
   **not** marked read on this branch — the content token mismatches and the commit is skipped.
   What remains is narrower and purely a test-coverage gap: nothing in the suite rejects a
   hypothetical implementation that re-counts at commit time and commits the re-counted value.

**Scope:** `bin/brain` (implementation) + `test/mutation-probe.sh` (a REQUIRED co-change, §4).
`test/dm.sh` is frozen RED — GREEN must not touch it. No new dependencies, no new module, so no
`ARCHITECTURE.md` change and no hard-lock trigger.

---

## 1. Reuse inventory — what exists and must NOT be rewritten

| Helper | Location | Use as-is |
|---|---|---|
| `_warn <msg>` | `:58` | `printf 'brain: %s\n' "$*" >&2` — **stderr, so it is stdout-safe inside `_emit_session_ctx_pinned`**, whose stdout IS the hook payload. This is why a diagnostic may be emitted at the reject site rather than plumbed out through a variable. Either shape is permitted; §4 constrains only the line's *silhouette*. |
| `_DM_JQ_SYSTEMIC_FAILURE` | set `:693,:700,:1420,:1422`; read `:754,:1484,:1497` | the existing systemic-failure channel. **Three real readers** — an earlier review agent called it "dead/inert" and was wrong. Do not repurpose or retire it. |
| `cmd_status` | `:891` | renders live state. The CHANGES banner block is `:944–953`. |
| `_hook_session_start` | `:1445` | the consume→stage→emit→archive discipline. Calls `cmd_status` at `:1521`, `_emit_session_ctx_pinned` at `:1530`, checks `_emit_rc` at `:1535`. |

Nothing new is needed. Both fixes are edits inside functions that already exist.

---

## 2. Seam decision A — the CHANGES cursor: ONE counter, ONE writer, split render from commit

**The defect.** `cmd_status` advances the on-disk bookmark as a *side effect of rendering the
banner* (`:951`). `_hook_session_start` **captures** that render into `_st` (`:1521`) and may then
discard the whole payload when `_emit_session_ctx_pinned` rejects (`:1530`). Bookmark moved, banner
never delivered, and every later healthy boot silently omits it — permanently.

**Settled scope (do not re-litigate; @pm escalated this as a CLI-contract question on 2026-08-06
and withdrew the escalation after checking):**

- The bookmark is read in exactly one place (`:946`) and written in exactly one place (`:951`),
  both inside the banner block. **Nothing else in the engine reads it.** It is gitignored
  (`:1718`) and per-machine.
- **The CLI cannot hit this bug.** `brain status` (`:1770`) prints straight to the terminal —
  once printed, delivered. Only capture-then-maybe-discard loses it.
- Erring either way is cheap **relative to each other**: marking read too early → today's silent
  loss; failing to mark read → the banner repeats (annoying, harmless). That ranking says which
  way to err *when forced*. It does **not** license never marking read — see the correction below.

**Therefore: the HOOK must not commit the bookmark on a boot that did not DELIVER; it must still
commit on a boot that did. The CLI is left exactly as-is.** A narrow bug fix, not a contract change.

> ⚠ **CORRECTION, 2026-08-06 — this sentence previously read "stop the HOOK from committing the
> bookmark," full stop.** `spec-watchdog` caught that during the RED audit: read literally, that is
> an instruction to never commit from the hook at all, which is a *different* implementation
> (`test-writer`'s mutant A) that passes `V.D/109` and **fails the `V.D/110` guard** — the banner
> would then nag on every boot forever. The condition is delivery, not caller. Wording fixed here
> because GREEN reads this file and the frozen suite would have rejected the shape it described.

**The seam constraint — the one thing that must not be got wrong:**

> **`_total` is computed in exactly one place.** The count is `grep -c '^- ' "$BRAIN/CHANGES.md"`
> (`:945`). A fix that has `_hook_session_start` re-count CHANGES.md so it knows what value to
> commit after `_emit_rc = 0` creates **two independent definitions of "how many changes exist"**,
> which drift the first time the CHANGES format changes. The grep stays singular.

### The shape — settled by the 2026-08-06 Codex consult, with one @pm amendment

Two candidate shapes were eliminated on evidence, not taste:

- **A pending-value global assigned inside `cmd_status` is BROKEN.** `:1521` is
  `_st=$(cmd_status 2>/dev/null)` — a **command substitution**, i.e. a subshell. Filesystem side
  effects survive it; shell-variable assignments do not. **Verified empirically under both `sh`
  and `dash`** (`X` set inside the substituted function; parent still reads its original value).
  Any design where `cmd_status` tells the caller what to commit dies here.
- **Caller-side stash-and-restore is RACY.** Cursor is 5; the hook stashes 5 and renders/writes 8;
  the CLI concurrently delivers change 9 and writes 9; the hook then rejects and restores 5 —
  overwriting another invocation's legitimate commit. 13 lanes run this concurrently. Rejected.

**The surviving shape — parent-prepared snapshot:**

1. Extract the count + read at `:944–951` into **one** helper (`_changes_snapshot <identity>`).
   The `grep` exists only there.
2. The caller prepares the snapshot **before** `:1521`, so the values live in the parent.
3. The command-substitution child inherits them and **renders only**.
4. The caller commits that exact snapshot after `_emit_rc = 0` (`:1536`).
5. The CLI at `:1770` prepares, renders, and commits immediately — behaviour unchanged.

Snapshotting *before* the render is load-bearing: re-counting at commit time would silently mark
read any CHANGES lines added between render and commit. Same defect class, narrower window.

> ⚠ **DECLARED GAP — no test enforces this, and no test will.** The `spec-watchdog` audit built the
> re-count-at-commit-time implementation and it **passes all scenarios**. Reaching it requires a
> `CHANGES.md` append *between* the render and the commit inside one hook invocation, which is not
> drivable without a concurrent writer or a bespoke interruption harness — precisely the class of
> instrument the proportionality rules exclude. **Ruled an acceptable gap** on this section's own
> cost reasoning: the exposure is a few lines silently marked read during a race, not the permanent
> silencing this fix removes.
>
> **Consequence, said out loud rather than assumed:** the "`_total` is computed in exactly one
> place" constraint above is **not guarded by the RED suite** — an implementation with two
> independent counts is green. It is a `/simplify` and `/steadows-code-review` obligation. Check it
> by reading the diff, not by trusting the gate.

> ⚠ **DECLARED GAP #2 — the MIRROR of the ABA window is untested (added 2026-08-07).** The count
> and the token must describe **one** read of `CHANGES.md`. `V.D/114` drives only one of the two
> ways two reads can disagree: its `cksum` shim appends its phantom entry on the **token** read, so
> a count taken *first* never sees the append and the scenario passes. The mirror — an entry seen
> by the COUNT and reverted before the token, leaving a cursor of 6 on a 5-entry file — **is not
> drivable by this instrument** and no scenario rejects it.
>
> **This gap has already cost one shipped defect.** `a89ecc7` reordered the two reads to
> count-before-token, `V.D/114` went green, and the branch shipped a mirror-image of the fault it
> had just closed. Reaching the mirror needs a second shim limb that appends before the count;
> **Steve ruled on 2026-08-07 not to build it** (the same ruling that waived the
> `test-writer` + `spec-watchdog` pair for this arc). Declared here instead.
>
> **What this means for any future edit to `_changes_snapshot`:** a green suite does **not** tell
> you the snapshot is coherent — it only tells you the token-side window is closed. The invariant
> to hold by reading the diff is that **exactly one** read of `CHANGES.md` feeds both
> `_CHANGES_TOTAL` and `_CHANGES_TOKEN`. Any construction that reads the file twice is wrong in one
> direction or the other, however the two reads are ordered; both orderings were measured failing.

**@pm amendment — no defer sentinel. `cmd_status` renders; CALLERS commit.**
The consult sketched a `_STATUS_CHANGES_DEFER` sentinel to tell `cmd_status` which mode it is in.
Drop it and make `cmd_status` a pure renderer that never commits, with both call sites owning the
commit explicitly. Reasons:

- It is the honest expression of the bug — render and commit were *conflated*; splitting them is
  the fix, and a mode flag re-conflates them behind a boolean.
- **It fails in the safe direction.** A future third caller that forgets to commit → the banner
  repeats (annoying, harmless). With a defer flag, a future caller that forgets to *set* it →
  silent loss, the exact defect being fixed. Prefer the failure mode that nags over the one that
  hides.
- It deletes a piece of state rather than adding one, and removes the need to clear an inherited
  sentinel at process entry (the `_BRAIN_RESOLVED` precedent at `:13`).

`cmd_status` has exactly two callers, both verified — the cost of explicitness is two lines.

**Ownership:** the *count* stays with the snapshot helper. The *decision to commit* belongs to the
caller that knows whether the render was delivered. Do not invert that — the hook has no business
knowing the CHANGES file format, and `cmd_status` has no business knowing about emit success.

---

## 3. Seam decision B — the reject diagnostic: one offender, at the site that knows it

**The defect.** When the per-id loop rejects (`:1422`) nothing records *which* id was missing. The
caller's sole diagnostic (`:1546`) names the `jq` binary, never the message, and is byte-identical
for two different faults — the envelope-FRAMING rejection (`:1420`) and the per-id one (`:1422`).
House style contradicts this: `:297–321` name their offender uniformly
(`invalid dm lane component: $_do_lane`).

**RULING — name EVERY missing id.** ⚠ This REVERSES @pm's initial "first only" lean, on the
2026-08-06 Codex consult's refutation, which @pm accepts:

- **`pending/` preserves the input set, not the omissions.** Once `_esc_payload` is discarded at
  `:1422` there is no record of *which* ids vanished. So "the batch is retained anyway" was a
  rationalisation: retention tells an operator what was staged, never what the serializer dropped.
- **The extent is the diagnosis.** Missing 2–40 reads as truncation or a serializer boundary;
  missing 2, 7, 19 reads as non-deterministic corruption; one consistently-missing id reads as a
  data-dependent interaction. A single id cannot distinguish those three, and they take different
  investigations.
- **The `:297–321` analogy is weak.** Those reject *one path* at its first invalid component. This
  is *one serializer invocation* producing one atomic batch result with potentially many
  simultaneous omissions — a set, not a sequence of independent decisions.
- **The cost argument collapsed.** "First" was cheaper only if the one-line silhouette trick
  worked; §4 shows it does not (the mutants erase the added mechanism). Both rulings now pay the
  same full co-change, so the cheaper-shape argument buys nothing.

Bounded by construction: the batch is capped at `DM_INJECT_MAX_LINES=40` (`:20`, enforced at
`:1477`), and stable ids are whitespace-free by grammar (`:393–417`,
`<YYYYmmddTHHMMSSZ>-<pid>[-<bump>]`), so a space-separated accumulator is safe. Initialize the
accumulator before every early return — `set -u` is in force.

**⚠ THE WARNING GOES AT THE CALLER, NOT THE REJECT SITE — and there must be exactly ONE.**
Found by the `spec-watchdog` RED audit, 2026-08-06, by measurement:

> `V.U/77` and `V.V/84` both pin the **per-id** path at **exactly one** `brain:` line — not the
> framing path, as the suite's own comment wrongly claimed. `write_rc0_empty_payload_jq` emits
> `{}`, which *passes* the `\{*\}` framing case at `:1420` and rejects in the id loop at `:1422`.
> A GREEN that adds a second `_warn` at the reject site scores **98/100**, failing both.

So the per-id reject path must emit **one** `brain:` line that simultaneously: contains the jq
binary path (`V.U/77`, `V.V/84`), names the missing id(s) (`V.B/107`), and differs from the framing
line (`V.B/108`). A **single enriched caller warning at `:1546`** satisfies all four. An added
`_warn` inside `_emit_session_ctx_pinned` does not — and would put GREEN under pressure to "fix"
two frozen, currently-passing scenarios.

**RULING (@pm, 2026-08-06) — name the MISSING ids, never the ids that were present.** The audit
built an implementation naming every *staged* id at the reject site; it passed **all 100
scenarios** while carrying zero information about the omission. `pending/` already preserves the
staged set, so re-listing it is redundant with what an operator can already see; the omission set
is precisely what `pending/` cannot tell them. A verbose `"staged: a b c; missing: b c"` shape is
deliberately rejected — mixing the two sets is what made that implementation indistinguishable
from a correct one. `V.B/107` now pins this directly.

The frozen RED is compatible with this ruling unchanged: `V.B/107` asserts the first missing id is
**present** and never that the others are absent; `V.B/108` pins only that the two reject classes
differ. No test edit is owed.

The frozen RED is deliberately compatible with either ruling — `V.B/107` asserts the first missing
id is **present** and never that the others are absent, so a later "name them all" ratification
costs no test edit. `V.B/108` pins only that the two reject classes emit **different** text; no
wording is frozen.

---

## 4. ⚠ The sharp edge — `bin/brain:1422` is a whole-line-exact mutation-probe anchor

This is what forced the diagnostic fix to be deferred last session. It is the highest-risk part of
this bundle.

`test/mutation-probe.sh` declares its anchors **whole-line-exact** (`grep -xF`, `:152–188`) and its
mutant addresses with declared cardinalities (`:200–219`). Line `1422` is load-bearing in **three**
places:

| Where | Form |
|---|---|
| anchor manifest `:161–187` | the literal line, `grep -xF`, must match exactly 1 |
| M6 `digest-drops-id` `:393` | sed address `^ *case "\$_esc_payload" in \*.*_DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac$`, cardinality 1 |
| M12 `envelope-first-id-only` `:497` | the same address, cardinality 1 |

The address requires a literal `*` immediately after `in `, which is why it selects `:1422` and
**not** `:1420` (`in \{*\}`). That disambiguation is load-bearing — preserve it.

### ⛔ The "keep it to one line" trick is REJECTED — it is regex-safe but semantically unsafe

@pm's initial plan was to preserve the line's silhouette by assigning the offender *earlier on the
same line*, so the address's `.*` spans the insertion and both sed addresses keep cardinality 1.
**The cardinality reasoning is correct and the plan is still wrong.** The 2026-08-06 consult found
why, and it reproduces on inspection of the two sed programs (`:396`, `:498`):

> **Both mutants replace the ENTIRE matched line with fixed text.** M6 substitutes
> `case "$_esc_payload" in *id*) ;; *) _DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac`; M12
> substitutes its own first-id variant. Neither replacement contains the offender assignment — so
> the mutant silently deletes the **diagnostic** mechanism as well as the **envelope-check**
> mechanism.

That breaks the probe's own contract, declared in its header at `:4`: *"Every mutant breaks ONE
load-bearing production mechanism."* A two-mechanism mutant makes its verdict unattributable —
exactly the reason M12 already rejected a bare `*"$1"*` pattern. Worse, if the caller then reads an
uninitialized accumulator, `set -u` can truncate the mutant suite outright.

**Therefore GREEN takes the honest shape** — a non-fail-fast accumulator loop per §3 — **and the
probe follows it.** The full price, to be paid deliberately and not discovered at gate time:

| # | Co-change | Where |
|---|---|---|
| 1 | Replace the whole-line anchor | `test/mutation-probe.sh:172` |
| 2 | Re-derive **both** sed addresses | `:218`, `:219` |
| 3 | Update M6's + M12's **replacement programs** so they preserve accumulation | `:396`, `:498` |
| 4 | Re-check changed-line cardinalities (can stay 3 and 1 if the accumulator case remains one target line) | `:211–219` |
| 5 | Add the measured new kills to the declared REQUIRED sets | `:393`, `:497` |
| 6 | Run the **complete** probe after GREEN — its baseline needs a green `dm.sh`, so it cannot be measured meaningfully against a still-RED tree | `:316` |

**Kill sets WILL move — measure, do not predict.** Both mutants are expected to gain `V.B/107`,
`V.B/108` **and `V.D/109`** as REQUIRED. M6 relaxes the witness to `*id*` so nothing rejects; M12
tests `"$1"` every iteration and all three fixtures keep the first id while dropping a later one.
Those are **genuine** kills — the engine really would archive undelivered messages — not instrument
damage. But the declared sets get whatever the probe actually reports, because undeclared
collateral fails the gate too. This is the same trap that bit M6 last session.

> **`V.D/109` was NOT in @pm's original prediction.** The `spec-watchdog` audit measured it against
> M6- and M12-equivalent engines and found it dies under both: its premise is that the per-id check
> rejects, and both mutants make it accept. This is **structural, not shape-dependent** — any GREEN
> satisfying `V.B/103` has the property. Worth knowing before the ~30-minute probe run rather than
> after it fails on undeclared collateral.

### ⚠ The cursor fix is anchor-free but NOT mutation-covered — one new mutant is authorized

`:951` and `:1521` are absent from the `ANCHORS` heredoc — verified. **"Not currently anchored"
does not mean "covered."** The delivery-conditioned commit is a *new load-bearing mechanism*, and
the probe is the only thing that proves the suite pins it rather than merely exercising it.

**Dispatcher decision, stated out loud (@pm, 2026-08-06):** ONE new focused mutant is approved —
it removes the hook's deferred commit / restores the early commit, and its REQUIRED kill is the
cursor-regression scenario. Bounded and named: one mutant, one mechanism, one required kill. This
is the cheapest instrument that discriminates the named fault, and it is *evidence*, not harness —
no new shared state, no fixtures, no coordination. **Nothing beyond this one mutant is authorized**;
if GREEN finds it wants more probe machinery, it stops and reports instead of building.

> **AMENDED after the `/simplify` gate — a SECOND mutant (M14) is authorized, and that is the
> ceiling.** The altitude pass showed M13 covers only one of four discriminations the suite claims
> for the new mechanism. Three guards assert properties the committed probe cannot reproduce:
> that the hook commits at all (`V.D/110`), that the commit sits **outside** the
> `[ "$#" -gt 0 ]` archive block (`V.D/110` boots 3–4), and that the CLI still commits
> (`V.D/111`). The `spec-watchdog` audit measured all three against hand-built engines — but that
> proves a check discriminated *once*, and does nothing after a later edit hollows it out, which
> is the entire reason the probe exists.
>
> **M14** deletes the hook's `_changes_commit` (`:1549`); REQUIRED kill `V.D/110`.
>
> ⚠ **CORRECTION (code review, 2026-08-06) — @pm's claim that "one mutant covers rows 2 and 3,
> since the misplacement fails the same boots" is MEASURABLY FALSE.** Measured: M14 kills
> `V.D/110` at boots **2 and 4**; the archive-block misplacement kills at boot **4 only**
> (`test/dm.sh:5616` states this itself — "DMs (boot 4 alone)"). So **M14 covers row 2 only.**
> Row 3 is discriminated by `V.D/110`'s boots 3–4 and is **NOT mutation-covered**: if those boots
> were ever deleted, M14 would still pass on the strength of boot 2, and the misplacement would
> go unguarded. That is exactly the "a check discriminated once, then a later edit hollowed it
> out" failure this amendment cites as the reason the probe exists.
>
> **Ruled: document it, do not add a third mutant.** The two-mutant ceiling stands — the suite
> does pin row 3 today, and the gap is that the *probe* cannot re-prove it. Declared here rather
> than left to be rediscovered.
>
> ⚠ **A second declared mutation gap: the reject DIAGNOSTIC has ZERO mutation coverage.** No
> mutant touches `bin/brain:1561` — verified, `grep` returns 0 — because both M6's and M12's
> replacement programs deliberately preserve the `_DM_MISSING_IDS` accumulator. `V.B/107`,
> `V.B/108` and `V.D/109` DO appear in both mutants' REQUIRED sets, but they die there on a
> **removed premise** (the mutants stop the rejection, so the diagnostic is never reached), not
> on the diagnostic mechanism itself. The declared sets therefore read as though the diagnostic
> has mutation coverage when it has none. The suite does pin it — a wrong implementation naming
> every *staged* id dies to `V.B/107` alone, measured — but say so here rather than let the kill
> sets imply otherwise.
>
> **Row 4 (CLI) gets no mutant — ruled, not overlooked.** Its failure direction is the harmless
> one (the banner nags on an interactive command), `V.D/111` guards it in the suite, and the
> budget is one added mutant per new mechanism. Two is the ceiling for this bundle.
>
> ⚠ **Authoring trap:** `^    _changes_commit$` matches **two** lines (`:1549` hook, `:1791` CLI),
> both at four-space indent. The address must be scoped or M14 silently mutates the wrong site —
> the same cardinality trap that produced the `\{*\}` disambiguation at `:206`.

Budget note: each added mutant costs one more full suite run (~150s at the current scenario count),
and each added *scenario* costs ~19× that (1 baseline + 18 mutants). Know the price before adding
either.

> **THIRD declared mutation gap (convergence pass 1, 2026-08-07).** `V.D/112` (a shrinking
> `CHANGES.md` must not silence later entries) and `V.D/113` (an unrecordable bookmark must be
> diagnosed) are **suite-pinned but not mutation-covered** — the two-mutant ceiling for this bundle
> was already spent on M13/M14. Their discriminating power was measured instead by `spec-watchdog`,
> which built **ten** wrong implementations: unconditional-suppression shapes die to the `V.D/110`
> and `V.D/111` guards, a hook-only cursor guard dies to `V.D/112`'s CLI arming, and an
> unconditional breadcrumb dies to `V.D/111`'s silence assertion. That is proof they discriminated
> *once*; the probe cannot re-prove it after a later edit. Declared, not closed.

**Kill sets WILL move, and undeclared collateral fails the gate.** The two new RED scenarios sit
directly under both mutants:

- **M6** relaxes the case to `*id*`, so every staged id is accepted and nothing rejects. `V.B/107`
  (expects a reject that names the offender) and `V.B/108` (expects two distinguishable rejects)
  both die on it.
- **M12** tests `"$1"` on every iteration, so a batch that keeps the first id and drops the rest is
  accepted. `V.B/107`'s fixture is exactly that shape; `V.B/108`'s first run likewise.

Both are **genuine** kills — the engine really would archive undelivered messages — so they are
`REQUIRED`, not `PERMITTED`. **Measure them, don't predict them**, then update the declared kill
sets at `:393` and `:497`. This is the same trap that bit M6 last session (it gained
`V.B/103/105/106` and they had to be measured and declared).

The cursor fix touches `:951` and `:1521`. **Neither is in the anchor manifest** — verified against
the `ANCHORS` heredoc. It is anchor-free unless GREEN moves an anchored line.

---

## 5. Dependency direction

Unchanged. `cmd_status` does not learn about DMs or emit success; the hook does not learn the
CHANGES file format. The serializer keeps returning a payload on stdout and rc on failure; only its
*stderr* diagnostic gets richer. No new coupling either way.

---

## 6. Altitude check

Both fixes are the smallest change that removes the named fault. Explicitly **not** in scope:

- A general "cursor manager" abstraction — one counter, one reader, one writer.
- A structured error-code channel for reject classes — two classes, and `_DM_JQ_SYSTEMIC_FAILURE`
  already exists.
- Touching the CLI path's observable behaviour (§2) — it still prepares, renders and commits in
  one go; only the *place* the commit is written from moves.
- **Memoizing `_resolve_whoami`, or deleting `cmd_status`'s own `_require_brain`/`_resolve_whoami`
  at `:907–908`.** `cmd_status` re-resolves identity inside the command substitution, so `brain
  status` resolves twice and every hook boot re-runs `brain_root` + the presence scan (~74 execs).
  **Ruled: accept.**

  > ⚠ **@pm's first statement of this ruling gave a WRONG reason and is corrected here.** I wrote
  > that it was confined to the interactive CLI path because "the hook resolves identity once and
  > passes it in." The efficiency pass measured that and it is false: `_hook_session_start`
  > resolves at `:1457`, then `cmd_status` re-resolves at `:908` inside the substitution at
  > `:1533`, and `cmd_hook` sets `BRAIN` without setting `_BRAIN_RESOLVED` so `:907` re-runs
  > `brain_root` too. The duplication IS on the 13-lane hot path.
  >
  > **The ruling survives on the real grounds, which are stronger:** it is **pre-existing, not
  > introduced by this diff** — exec counts for `hook session-start` are *identical* across the
  > change (1351 → 1351, byte-identical per-tool distribution), and the reject path is now
  > strictly cheaper because `_changes_commit` is gated where the old inline code wrote
  > unconditionally. Fixing it is out of scope under surgical-changes.
  >
  > The zero-state alternative (delete `:907–908`, since both callers already resolve) is also
  > **declined**: `cmd_status` uses `_me=$_WHOAMI` throughout, so deleting it makes identity
  > another caller-set global — deepening precisely the coupling Fix 1 was applied to remove.
- A defer/mode sentinel on `cmd_status` (§2 amendment) — considered and rejected as failing unsafe.
- Any probe machinery beyond the single authorized mutant (§4).
- The still-open degrade-to-raw-text fallback when the reject fires — that changes what 13 lanes
  see at boot in a failure mode. **Escalated to Steve, deliberately not fixed here.**
