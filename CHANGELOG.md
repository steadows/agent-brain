# Changelog

## v1.2.3 — 2026-08-06 — nothing is marked delivered that was not delivered

Two ways a message could be marked read without ever reaching an agent — one in the DM queue, one
in the CHANGES banner — plus the diagnostic that made the first undiagnosable. Design record:
`.context/seams/pr10-cursor-and-diagnostic.md`.

- **The serializer validated only the FIRST staged message id while the caller archived all of
  them.** A partial envelope — first id kept, 2..N dropped — passed the guard, and
  `_hook_session_start` archived every staged name to `read/` as delivered. Silent loss, in the
  one check whose whole purpose is catching it. The serializer now validates every staged id and
  rejects the entire batch if any is missing.
- **`cmd_status` no longer advances the CHANGES bookmark as a side effect of RENDERING the
  banner.** The SessionStart hook captures that render and can discard the payload when the
  widened check above rejects — so the bookmark moved, the banner was never delivered, and every
  later healthy boot silently omitted it. Permanently. Widening the id check widened that path,
  which is how the regression arrived with the fix. The count is now snapshotted **once, before**
  the render, and the two callers commit it: the hook only after a successful emit, the CLI
  immediately as before. Committing early loses the notification; failing to commit merely repeats
  it — this errs the second way, deliberately. `brain status` behaviour is otherwise unchanged.
- **A rejected batch names its offender.** The reject discarded which ids were missing, and the
  caller's sole warning named the `jq` binary — byte-identical for an envelope-framing rejection
  and a per-id one, so an operator could not tell which check fired. It now lists **every** missing
  staged id in one warning. Naming all of them rather than the first is deliberate: `pending/`
  preserves the staged set but never the omissions, and the extent is the diagnosis — a contiguous
  run reads as truncation, a scattered subset as non-deterministic corruption.
- **The bookmark can no longer outrun the file it describes.** Three adversarial convergence passes
  found three ways the CHANGES count and the file could disagree, each one exposed by the fix for
  the last. A render that SHRANK mid-flight committed a count the file no longer supported
  (`V.D/112`). Splitting the count and the integrity token into two reads then let the file change
  and change back between them — and the first repair for that, reordering the two reads, closed
  one direction while opening its exact mirror (`V.D/114`). **The count and the token are now
  derived from ONE read of `CHANGES.md`**: any ordering of two reads leaves a window in one
  direction or the other, one read has none. Measured against six hand-built candidate engines, not
  argued. A commit that cannot record the bookmark now says so rather than failing silently
  (`V.D/113`), and the commit-time integrity check tests `cksum`'s exit status **before** comparing
  — previously an unreadable file yielded an empty string that compared equal to an empty token and
  passed the guard.
- **Suite: 103 scenarios** (V.B/107-108 pin the diagnostic; V.D/109-111 pin the delivery-conditioned
  commit, its two guards rejecting "never commit from the hook" and "defer for every caller";
  V.D/112-114 pin the three snapshot-integrity faults above). Mutation probe at **19 mutants** —
  M12 envelope-first-id-only, M13 early-cursor-commit, M14 hook-cursor-commit.
- **Four gaps are declared in the seam map rather than closed**, and each is a ruling, not an
  oversight: the reject diagnostic is suite-pinned but not mutation-covered; M14 covers the
  missing-commit fault but not the adjacent misplacement; the MIRROR of the ABA window is untested
  because `V.D/114`'s shim can only append on the token read (this gap already cost one shipped
  defect, and `V.D/114`'s header now says so); and the validate→write race is **accepted** — it is
  check-then-act rather than a two-read problem, it is pre-existing and strictly wider on `main`,
  and its blast radius is the banner alone, never DM delivery.

## v1.2.2 — 2026-08-05 — enumeration is fatal-not-empty; paths, identities and the emit are byte-exact and pinned

Seven hardening rounds (v1.2.2 + r2-r7) closing seam-map rulings 7-14 (`.context/seams/
dm-v1.1-queue.md` § v1.2.2 / v1.2.3 / v1.2.4 + errata 13a/13b), each round found by an
adversarial gate on code the prior gate passed. (The intermediate v1.2.1 round — rulings 1-6 + 1a — is recorded in the plan and
seam map; its entry was never added here.)

- **Enumeration failure is operation-fatal, never "empty"/"free" (ruling 7).** A queue dir
  that is writable+searchable but not readable (0300) defeated every glob scan: ids read as
  free, non-empty queues read as empty, `dm take` returned success with messages sitting
  there. Scans now validate read+search on BOTH sides of an empty expansion and return a
  distinct "unestablishable" rc; every consumer aborts with a diagnostic and leaves messages
  pending. The consuming loops also re-validate after exhaustion — their own glob expansion
  is a scan too.
- **A path is an opaque byte string; nothing travels through `$( )` (ruling 8).** Command
  substitution strips trailing newlines, which let a hostile basename permanently defeat
  quarantine and reinstate head-of-line starvation. `_dm_collision_dest`, whoami/lane
  identities, and the presence-slug derivation all return via caller-visible variables now;
  an invalid inherited `BRAIN_FEATURE` is rejected at the resolver with a diagnostic.
- **jq identity is pinned per operation (rulings 9 + 10).** One PATH resolution per consume;
  every probe, digest, and the SessionStart serialization invoke that exact binary. A digest
  failure authorizes quarantine only if the recorded exit-code contract still holds for the
  same executable; a systemic contract change aborts the batch once, names the binary, and
  leaves everything pending — and invalidates the WHOLE staged SessionStart batch, including
  entries digested before the failure. SessionStart archives only after a staged,
  verified-non-empty, pinned emit succeeds — a jq exiting 0 with empty output can no longer archive undelivered
  messages. The send path resolves-and-pins too (no contract probes). Every payload-bearing call
  additionally gates on a cheap structural witness (object-shaped, carries the known id /
  the four field keys) — a probe-passing binary returning well-formed-looking `{}` with
  rc 0 can no longer archive, publish, or journal anything; the fully-byzantine
  forged-payload adversary is declared out of the threat model in the seam map. An
  uninspectable `failed/` renders an explicit cannot-inspect banner in `brain status`,
  never a silent zero (ruling 14).
- **Collision names are re-checked against the byte cap at every suffix (ruling 11).** A
  candidate at NAME_MAX no longer overflows on its first `-<n>` bump; the compact checksum
  fallback reserves worst-case counter headroom.
- **`.tmp-*` is the only sanctioned hidden namespace (ruling 12).** Any other dot-prefixed
  child of `pending/` (`.poison`, `.DS_Store`, hostile symlinks) is enumerated and classified
  via the ruling-1 path (grammar-invalid → quarantine) instead of being invisible forever.
- **The witness layer STOPS at r5 — ruling 13b, signed (erratum, `b5b5b83`).** Convergence
  sweeps 3 and 4 each holed the shell-side JSON witnesses; the cause is structural (POSIX
  shell cannot parse JSON, payload bytes are unconstrained), so tightening is
  non-convergent. Witness-passing-but-invalid output folds into ruling 13's byzantine
  boundary (requires a deliberately defective jq on PATH); residual exposure — a message
  archived undelivered, recoverable from `read/` — is accepted on the record.
- **Status absence is PROVEN through validated ancestors (r6, ruling 14 completion).** A
  `dm/` root or `dm/<lane>` corrupted into a regular file / symlink / unsearchable dir used
  to make the failed-banner gate silently skip (leaf `-e`/`-L` false ≠ proven absent).
  `_dm_failed_state` now walks root→lane tri-state: missing under validated parents =
  proven absent (silent); malformed/uninspectable ancestor = the cannot-inspect banner.
- **One authoritative failed-count call, fork-free and revalidated (r7).** `_dm_failed_count`
  runs the tri-state walk itself, revalidates the directory AFTER glob expansion (a mid-scan
  permission flip cannot render zero), and returns via `_DM_FAILED_COUNT` — no `$( )` on
  either the empty or positive status path. The probe gained an address-cardinality
  self-check: every sed selector (21 across 16 mutants) is asserted against its declared
  engine match count (M6 matched 3 lines; re-addressed to 1). Sweep 6 then showed count
  alone still admits a selector drifting to a DIFFERENT set of N lines (r8): the
  multi-count selectors' line sets (M7 ×2, M10 ×5) now sit in the exact-line manifest —
  bounded by count AND exact lines — and V.N/50 asserts the bounded-backlog continuation
  instruction carries the exact absolute receiving-vault engine invocation (must-survive
  #7), so that regression is caught behaviorally, not just structurally.
- **Suite: 91 scenarios** (V.R/67-75, V.U/76-79, V.V/80-85, V.Y/86-89, V.Z/90-91 added;
  each fix round RED-proven by A/B against its pre-fix engine),
  declared gaps [Q6] (scanner-internal TOCTOU witnesses) and [Q7] (fork-free/revalidation
  internals not CLI-observable; no hollow mutant spent on them), and the jq re-probe is now
  genuinely driven (an in-place-overwriting PATH shim; stub-flip verified). Mutation probe
  re-anchored; M8/MQ1 kill sets strengthened.


## v1.2.0 — 2026-08-04 — the claim layer is deleted

Steve's ruling (`.context/seams/dm-v1.1-queue.md` § v1.2), after three consecutive adversarial
gates each landed their HIGH findings inside the claim/lease/recovery/budget subsystem: **one
active session per lane is the operating model** (parallel work spawns a second lane, the
`graph`/`graph-secondary` pattern), so a per-message claim protocol was arbitrating between
sessions the system already declares unsupported.

- **Deleted:** `claimed/` as a state · claim timestamps/PIDs · `DM_CLAIM_MAX_AGE` leases ·
  stale-claim recovery · the `.a<k>` attempt counter · the poison cap · the background lease
  sweeper · the cross-state transition budget · `_dm_decimal_ok`/`_dm_attempt_ok`. Net
  **−126 lines**.
- **Consume is now:** a bounded batch from `pending/` → validate each message independently →
  emit → move only successfully-emitted files to `read/` (collision-safe via the shared
  `_dm_collision_dest` bump idiom). Emit-before-move is unchanged and load-bearing.
- **Contract stated honestly: at-least-once.** A crash between emit and archive may replay a
  message; it is never lost. "Exactly once" wording struck from the plan; digest records now
  carry the message `id` so a replay is recognizable.
- **Quarantine only on structural proof.** The digest's jq exit codes are translated (its own
  `error()` = proof; any system error = transient, message stays pending) — a v1.2 GREEN bug
  caught by the frozen suite under real dash, where a closed stdout misrouted a healthy
  message to `failed/`. `dm take` now refuses an unusable stdout outright, leaving everything
  pending; a global `jq` preflight failure does the same.
- **Suite rewritten and frozen first** (54 scenarios: 46 guard / 8 RED at freeze): claim-era
  scenarios retired — including the disjoint-concurrent-consumers requirement, which encoded
  the rejected contract — and crash-window, isolation, backlog-continuation, collision and
  quarantine scenarios added. Key instruments proven by mutation before freeze.

## v1.1.0 — 2026-08-04 — lane-to-lane DM

Adds a **fast tier** to coordination. Until now every signal travelled at the speed of the
other lane's next session boot; `brain dm` reaches a running lane in seconds, which removes
the human from the relay loop between two lanes that are both already awake.

- **`brain dm @<feature> "<msg>"`** — one jq-encoded JSON message (`from`/`to`/`ts`/`content`)
  written as **its own file** into `.brain/dm/<feature>/pending/`, made visible only by the
  final same-directory rename (maildir-style send). No lock on the send path — rename
  arbitration is the only concurrency control, and a lock with no staleness break would let
  one killed sender wedge a lane's queue permanently. Bodies are capped (`DM_MAX_BODY`) to
  bound storage and digest work.
- **`brain dm @all "<msg>"`** — fans into every registered queue (skipping the sender), for
  status broadcast and merge coordination. Deliberately not gated on who looks "live":
  presence `updated:` is not a liveness signal.
- **`brain dm take`** — claim, print, and acknowledge up to 40 of this lane's pending DMs: the
  bounded live-consumption path a running lane invokes when its queue watch fires. Further
  messages stay pending and claimable on the next touch.
- **`brain inbox [<feature>]`** — prints (and creates) the `pending/` queue directory an
  agent arms its watch on.
- **Per-message lifecycle: `pending/` → `claimed/` → `read/` (or `failed/`).** Claims carry a
  wall-clock lease (`DM_CLAIM_MAX_AGE`); an interrupted consumer's messages are recovered to
  `pending/` at the next queue touch and redelivered. Delivery is **at-least-once** — a crash
  window can duplicate a message, never lose one — and **process-crash-safe** (POSIX sh
  cannot fsync, so power-loss durability is deliberately not claimed). A message that defeats
  its consumer `DM_MAX_ATTEMPTS` times routes to terminal `failed/`, surfaced by
  `brain status`, never silently deleted. Design authority:
  `.context/seams/dm-v1.1-queue.md`.
- **SessionStart recovers → claims → delivers → acks.** Each boot claims at most 40 messages;
  the hook injects only one-object, four-field (`from`/`to`/`ts`/`content`) records with bounded
  fields and a final aggregate cap, while excess messages stay pending for the next touch. It
  injects claimed messages into the startup context and acknowledges them (move to `read/`)
  **only after the payload emitted successfully**, so an interrupted boot leaves every message replayable —
  and a DM sent to a *down* lane queues until it wakes. Injected content is bounded so a
  large backlog can't blow the lane's context window.
- **The journal records a call log, never the message body** — `dm → @lane (transcripts: …)`.
  `journal/` is committed and the secret scan is line-anchored, so a body written mid-line
  would be invisible to it. `dm/` is gitignored, and `brain commit` now self-heals that
  invariant (and un-tracks/un-stages queue files) for vaults initialised before this feature.
- **`dialog_with:`** — optional presence field, surfaced by `brain status`, so a lane-to-lane
  dialog left open an hour later is visible rather than silent.
- **Protocol** — the always-read nav skill gains the DM tier, triage rules, and the merge
  handshake; `templates/DM-PROTOCOL.md` carries the full dialog/anti-sycophancy/deadlock
  reference on demand, keeping the per-session context tax flat.
- **`test/dm.sh` + `test/commit-install.sh`** — the repo's first test suites (53 + 15
  scenarios, temp-repo fixtures), the thing ROADMAP has wanted since v1.

## v1.0.1 — 2026-08-02

Fix: the PreToolUse collision warning never reached the agent. Two dead switches in series
(found + fixes verified empirically — see `docs/research/agent-lane-dm-mechanisms-eval.md`
in the Enterprise Research Dashboard repo, evals E2/E9):

- **`_emit_pretool` emitted the warning in `permissionDecisionReason` on an `allow`
  decision** — Claude Code only renders that field on `ask`/`deny`; on `allow` it is
  silently dropped. Swapped to `additionalContext` (same hook, same event). The `ask`
  branch is unchanged — its reason renders in the permission prompt and always worked.
- **Edit/Write paths from sibling worktrees never matched.** `_relpath` only strips the
  MAIN worktree's `$ROOT` prefix, but agents live in sibling worktrees, so `file_path`
  stayed absolute and `_path_match` (exact-match) could never fire. New `_relpath_any`
  also strips the caller's own worktree root. (The related `git push` diff-target issue
  remains ROADMAP known-issue #1 — untouched.)

Verified live: a no-op Write to a path in another active feature's `touches`, from a
sibling-worktree session, surfaced "Shared-surface collision (proceeding; logged to
journal)" in the acting agent's context and wrote the journal line.

## v1.0.0 — 2026-06-13

Initial filesystem-only release. Built, seeded into a live 4-agent project, smoke-tested against the
BUILD-SPEC §10 scenarios, installed machine-global, and in active coordination use by day 2.

- **Engine** (`bin/brain`, POSIX sh): `init`, `install`, `new-feature`, `whoami`, `announce`,
  `status`, `reconcile` (validate + auto-resolve/downgrade), `commit` (locked, secret-scanned,
  ff-only), `wrap` (self-contained closeout = reconcile + commit-from-main), the governance gauntlet
  (`propose`/`apply`/`revert`), and the `hook` entry point.
- **Identity**: positional-slug exact-token matching against `owns_branches` (§2a) — `graph` ≠
  `langgraph`, the cockpit double-match killed, `main`-resident features resolve without an override.
- **Hooks** (global dispatcher only, no double-fire): SessionStart (orient + reconcile) and PreToolUse
  (non-blocking collision gate).
- **`/wrap` integration**: presence sync + reconcile (Phase 1), durability commit (Phase 4, main
  worktree only), research-stays-put note (Phase 6).
- **Templates**: presence / connection / journal / research / INDEX / the `navigation-standards` skill.
- **Notable build decisions**: `flock` → atomic `mkdir` lock (macOS has no flock); hooks live only in
  the global settings dispatcher because `.claude/settings.json` is gitignored; `BRAIN_TEST_BRANCH`
  test seam; `.brain/.gitignore` keeps runtime artifacts + Obsidian config + the Phase-2 index DB out
  of commits.

**Public-release hardening (pre-publish):**
- Genericized the engine — the default branch is now configurable (`BRAIN_MAIN_REF`, default
  `origin/main`) and the secret-scan denylist path is generic (`BRAIN_SECRET_DENYLIST` /
  `<vault>/secret-denylist.txt`) instead of an Enterprise-repo path.
- Fixed the `commit`/`wrap` secret-scan false-positive that aborted on the engine's own `VERSION=`
  line — the scan now skips `bin/` and `templates/` (code, not note content) and still catches real
  env-shaped secrets in notes.
- Added the harness-neutral `brain wrap` so persistence doesn't depend on any specific `/wrap`.

See [ROADMAP.md](ROADMAP.md) for known issues and the deferred Phase 2 / v2 work, and
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) for dependencies.
