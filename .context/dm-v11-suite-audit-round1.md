# DM v1.1 RED-suite audit — rounds 1–3 (spec-watchdog) — CLOSED: SOUND-TO-FREEZE

## ROUND 3 (2026-08-04) — verdict: **SOUND-TO-FREEZE**, no findings

All 4 round-2 hunks landed as claimed, nothing extra (diffed). R2-2 gate verified 5/5 directions
(now strictly better in both directions than its predecessor); R2-3 filter 5/5. Q.S/11↔Q.T/12
contradiction resolved; a CLASS-level sweep of all 13 consuming scenarios × 46 post-consume
assertions against the transition contract found NO sibling contradictions (the failure mode that
bit in both prior rounds — both introduced by repairs). Mutant spot-check (m1, m5+m6 control
pair, m8, m12): each flips exactly its own guard, exit 3. Dash parity, order-independence,
no scratch leaks. One no-action observation recorded: Q.S/11's read/ assertions only become
load-bearing under v1.1 (old engine's batch archive satisfies them; the lock invariant rests on
its rc checks + timing bound; take semantics pinned independently by Q.T/12-15).
Watchdog note on the writer's chmod-restore justification: fix right, stated risk slightly
overstated (empty 0500 dir IS removable — parent-write governs unlink); kept on convention
grounds. Orchestrator re-ran the suite unpiped at freeze: 45 scenarios, 33 RED / 12 guards,
0 guard failures, exit 1 — matches both agents' reports.

---

## ROUND 2 (2026-08-04) — verdict: one more round. 1 blocking, 2 real.

12/13 round-1 amendments verified correct (each one individually re-checked; full mutant harness
re-run — 12/12 guards now flip exactly their own minimal mutant, m-m8 hollow-guard witness dead).
All three writer deviations ACCEPTED on evidence; on F2 the watchdog measured every proximity
window 80→5 and refuted its own round-1 fix — no proximity regex can discriminate on this
template. Runtime correction: 55s, not the claimed 46s (no verdict change).

- **R2-1 · HIGH · BLOCKING · Q.S/11 unsatisfiable** — introduced by the F8 amendment: the
  positive control still asserts `pending/ == 1` AFTER a `dm take` that the same suite (Q.T/12)
  requires to EMPTY pending/. Under GREEN it fails forever. Fix: move the two `pending/`
  assertions to immediately after the send (inside the timing window), and after the take
  assert `read/` holds 1 carrying the content.
- **R2-2 · MEDIUM · Q.X/30 `added >= 2` gate wrong in both directions** — rejects a compliant
  consolidated one-line warning naming both entries; still admits a two-line single refusal that
  silently skips the other entry. Fix: names-primary (both entry names in the log ⇒ pass);
  fall back to `added >= 2` only when NEITHER name appears; declare the unnamed-two-line case
  uncloseable without naming.
- **R2-3 · LOW-MED · F3 residual** — a column-0 `- ` failed-queue banner would be eaten by the
  `^- ` filter (falsely reds Q.R/22). Fix: timestamp-anchored
  `grep -vE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T'` (matches the real `_announce_as` format, cannot
  eat a prose bullet — verified both directions).

Round-2 probes: scratchpad `dmaudit/` — `probe2.sh`, `mut-m1..m12`, `r2-m*.txt`, `h2.sh` (F8
timing), `h3.sh` (F1 two-shapes), `h4.sh` (mint fallback).

---

# ROUND 1 — verdict: HOLES-FOUND (13 findings, 3 blocking)

**Date:** 2026-08-04 · **Suite:** `test/dm.sh` @ working tree (43 scenarios, 32 RED / 11 guard)
**Probe harness:** `/private/tmp/claude-501/-Users-amap3i-research-dashboard-enterprise-research-dashboard-pm/e8cb3b9c-fa5a-428a-a816-d4db8c7785c8/scratchpad/dmaudit/` (`probe.sh`, `mut-m*.sh`, `r-m*.txt`) — re-runnable.

Verified clean by the watchdog: scenario/dispatcher parity, dash parity, order-independence,
no silent-pass path, all 32 REDs fail on the requirement (not fixtures), 10/11 guards flip
exactly their own minimal mutant, Q.X/26 live-reproduces UR-2, `age_claim` discriminates
encodings, mtime-lease and six other strong attacks are correctly killed by the suite.

## BLOCKING

- **F1 · HIGH · Q.R/24 limb (b) contradicts Q.R/21.** Limb (b) demands next-boot delivery of a
  surviving message; Q.R/21 forbids touching a claim younger than `DM_CLAIM_MAX_AGE`. The seam's
  natural take shape (emit-failure leaves a fresh claim in `claimed/`) obeys Q.R/21 and falsely
  fails Q.R/24(b). **Fix:** age any surviving claim (`age_claim "$c" $((DM_CLAIM_MAX_AGE + 300))`)
  before the recovery boot, as Q.R/20 does. Accepts both permitted shapes; still proves
  "never silently lost."
- **F2 · MEDIUM · 3.G/37 hollow — demonstrated.** Mutant rewrote "record is a connection note" →
  "home is"; guard stayed green (proximity regex satisfied by unrelated fragments). **Fix:**
  anchor to a single physical line: `grep -iE 'record is a connection note|connection note is the record'`.
- **F3 · MEDIUM · Q.R/22 negative control fires on unrelated wording.** `grep -qi 'failed'` over
  ALL of `brain status` — but status echoes the DM call-log journal line, whose pointer text the
  GREEN task must rewrite; any wording containing "failed" trips the control. **Fix:** scope the
  control to the failed-queue banner / exclude the journal-echo section.

## NON-BLOCKING, APPLY WHILE OPEN

- **F4 · MEDIUM ·** poison-cap boundary untested: add sibling at `k=2` — `failed/` empty, message
  delivered, lands in `read/` as `.a3` (distinguishes `>` from `>=`).
- **F5 · MEDIUM ·** `mint_stuck_claim`: keep engine-minted path primary, fall back to hand-minted
  `.c$(date +%s)-1` on rc 3 (fail-closed impl must not silently kill Q.R/20/21/22). Delete the
  stale "encoding is NOT pinned" rationale — the seam map ruled epoch seconds (2026-08-04).
- **F6 · MEDIUM-LOW ·** Q.D/31: assert `shown <= DM_INJECT_MAX_LINES` (40), not `< 45`.
- **F7 · MEDIUM-LOW ·** no over-cap body scenario: add one > `DM_MAX_BODY` (4096) send, pin the
  documented cap behavior (seam decision 8 KEEPS the cap).
- **F8 · MEDIUM-LOW ·** Q.S/11 (no-lock) drives send only: add `dm take` + a boot under the
  read-only `.locks` fixture, same `elapsed <= 3` bound.
- **F9 · LOW ·** runner: `[ "$GUARD_FAILED" -eq 0 ] || exit 3` before the generic exit 1, so a
  guard regression is visible in exit status during the GREEN loop.
- **F10 · LOW ·** (a) Q.X/30: assert both planted entries surfaced (≥2 lines or grep both names);
  (b) Q.R/24 limb (a): distinguish engine-warned from mv-stderr-leaked.
- **F11 · LOW ·** Q.S/2 comment misdescribes authority: `.a0` is now RATIFIED by the seam map
  (not "from the task brief") — fix the comment.
- **F12 · LOW ·** `_atomic_place` temp-cleanup-on-failure limb: add a DECLARED skip comment
  (hard to drive; silent absence today).
- **F13 · INFO ·** UR-4a's absence: cite the seam-map sentence ("sequenced with the rewrite, not
  inside it") in the header's declared-gaps note.
