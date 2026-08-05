# Thought partnership — should the DM queue's claim/lease layer be deleted?

You are a senior engineer acting as a **thought partner**, not an implementer and not a
reviewer. Work ALONE — no sub-agent fan-out. **Do not edit code.** Your job is to pressure-test
a judgment call and tell me if I am wrong.

**I have a position. I want you to try to break it.** If you agree, say why in a way I could
act on; if you disagree, say so bluntly and show me the case I missed. Do not soften a real
objection to be agreeable, and do not agree just because I laid the argument out confidently.
An answer of "your simplification is wrong, here is what it costs you" is the most valuable
outcome available here.

## The situation

`~/agent-brain` — a POSIX-sh, filesystem-only coordination vault for ~13 AI coding agent
"lanes" sharing one git repo. The feature under review: lane-to-lane direct messages, so a
running lane hears something in seconds instead of at its next session boot. The durable
record is elsewhere (a committed journal + connection notes); **the DM is explicitly the
fast, lossy-tolerant signal tier, not the record.**

### The delivery contract (verbatim, from the design authority `.context/seams/dm-v1.1-queue.md`)

> False staleness ⇒ duplicate delivery — the mandated direction; a backwards clock step
> biases the same way.

> At-least-once + automatic recovery = a message that reliably kills its consumer is
> redelivered forever, to every boot. SQS's answer is the dead-letter queue after N receives.

And from the shipped CHANGELOG:

> Delivery is **at-least-once** — a crash window can duplicate a message, never lose one —
> and **process-crash-safe** (POSIX sh cannot fsync, so power-loss durability is
> deliberately not claimed).

**So: duplicates are explicitly acceptable. Loss is not.**

### The current design

Send: one JSON message per file, dot-temp + same-directory `rename` into
`dm/<lane>/pending/` (maildir-style). Then a full claim/lease layer:

`pending/<id>.a<k>` → `claimed/<id>.a<k>.c<claim-ts>-<pid>` → `read/<id>.a<k>`, with:
- a 600s wall-clock lease (`DM_CLAIM_MAX_AGE`), no PID/liveness check
- stale-claim recovery renaming back to `pending/<id>.a<k+1>`
- a per-message delivery-attempt counter in the filename
- a poison cap: `k+1 > DM_MAX_ATTEMPTS=3` → terminal `failed/`
- a background lease-sweep scheduler (`_dm_arm_lease_sweep`, sleeps + re-arms)
- a shared per-invocation transition budget (`DM_TRANSITION_MAX=40`) spanning recovery,
  invalid-routing and claiming

**Measured size:** the layer is `_dm_decimal_ok`, `_dm_attempt_ok`, `_dm_route_failed`,
`_dm_failed_dest`, `_dm_dest_occupied`, `_dm_recover_stale`, `_dm_claim_all`,
`_dm_arm_lease_sweep`, `_dm_purge_stale_temps` ≈ **211 lines of a 1628-line engine**, plus
**14 `DM_*` constants**.

### The evidence that prompted this

Three consecutive adversarial gates, each on code the previous gate had passed:

| Gate | Verdict |
|---|---|
| Ultrareview #1 (v1.0 engine) | NOT READY — 10 findings; engine rewritten |
| 5-agent code review (v1.1) | NOT READY — 5 HIGH (two = silent permanent loss of ALL DM delivery) |
| Ultrareview #2 (v1.1) | NOT READY — 6 HIGH (incl. a deploy model that shipped a no-op feature) |
| Ultrareview #3 (post-fix) | NOT READY — 5 HIGH |

**In round 3, all five HIGH findings are inside the claim/lease/recovery/budget layer:**
1. Over-long ID passes validation, then the **claim suffix** pushes the name past `NAME_MAX`
   → `mv` fails → the entry blocks every later message forever.
2. Locale-sensitive digit validation lets a non-ASCII digit reach `$(( ))` → **fatal shell
   exit** → SessionStart dies every boot. The operands are the **claim** ts/pid/attempt.
3. `cmd_dm_take` never arms the **lease** scheduler → a live-claimed message can strand
   indefinitely.
4. 40 stale **recoveries** exhaust the shared **budget** → nothing claimed, no timer armed →
   a whole 40-message batch goes silent.
5. A **temp-sweep** failure now suppresses healthy delivery AND can spin a 1 Hz re-arm chain
   that grows `.hook-errors.log` without bound.

Rounds 2 and 3 each also introduced NEW HIGH defects while closing old ones.

## My position (attack this)

The claim/lease/recovery/attempt/poison/budget machinery exists to prevent **duplicate
delivery** — and duplicate delivery is a thing this design has already declared acceptable.
So we are ~211 lines and three review rounds deep defending against an outcome we said was
fine.

**Proposed simplification:** delete the `claimed/` intermediate state and everything that
serves it. Consume becomes: read `pending/`, emit, then `rename` each into `read/`. A crash
between emit and rename ⇒ redelivery at the next touch ⇒ at-least-once, exactly the stated
contract. That deletes leases, the sweeper, stale recovery, attempt counters, the poison cap,
the transition budget, and (I claim) the large majority of findings from all three rounds.

**Crucially, this does NOT reintroduce the bug that killed v1.0.** v1.0 lost messages because
SessionStart moved them to `read/` *before* emitting, so an interrupted boot lost them
permanently. Emit-then-move keeps the fix: nothing leaves `pending/` until it has been emitted.

## Where I am least sure — push hardest here

1. **The poison case.** Without an attempt counter, a message that reliably kills its consumer
   is retried forever. Is that actually worse in practice than the poison machinery's own
   failure modes (findings 1, 2, 4 above all involve the attempt counter or the budget)? Is
   there a cheaper poison defence than a counter in the filename?
2. **Two concurrent sessions of one lane.** Without claims, both emit the same message. The
   contract says duplicates are fine — but is there a case where a *coordination* message
   being delivered twice to two sessions of the same lane causes real harm (double-acting on
   an instruction, duplicated work, a feedback loop)?
3. **Am I pattern-matching "delete complexity" onto a case that genuinely needs it?** The
   research that produced this design cited dirq and SQS as prior art. Maybe the claim layer
   is table stakes and I am about to remove load-bearing structure because it happens to be
   where the bugs clustered — bugs cluster where the code is, and 211 lines is 13% of the
   engine but the most intricate 13%.
4. **Sunk-cost inversion.** The 60-scenario suite and the mutation probe largely test this
   machinery. Am I proposing to delete the most-tested part of the system and keep the
   least-tested? What is the real risk profile of that trade?
5. **Is there a third option** better than both "harden round 4" and "delete the layer"?

## What I want back

1. A blunt verdict: **simplify, keep-and-harden, or something else** — and your confidence.
2. The strongest argument AGAINST my position, made properly rather than as a token caveat.
3. If you agree: what specifically must survive the deletion, and what breaks that I have not
   listed.
4. If you disagree: what is the actual root cause of three failed gates, if not
   over-engineering?
5. Any framing I am missing about what this feature is *for* — it is a nudge between agents
   whose durable record lives elsewhere.

Read `bin/brain`, `.context/seams/dm-v1.1-queue.md`, and the three reports under
`docs/reviews/` before answering. Ground every claim in something you actually read.
