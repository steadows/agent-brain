# Changelog

## v1.2.2 — 2026-08-05 — enumeration is fatal-not-empty; paths, identities and the emit are byte-exact and pinned

Two hardening rounds (v1.2.2 + v1.2.2-r2) closing seam-map rulings 7-12 (`.context/seams/
dm-v1.1-queue.md` § v1.2.2 + § v1.2.3), each found by an adversarial gate on code the prior
gate passed. (The intermediate v1.2.1 round — rulings 1-6 + 1a — is recorded in the plan and
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
  messages. The send path resolves-and-pins too (no contract probes).
- **Collision names are re-checked against the byte cap at every suffix (ruling 11).** A
  candidate at NAME_MAX no longer overflows on its first `-<n>` bump; the compact checksum
  fallback reserves worst-case counter headroom.
- **`.tmp-*` is the only sanctioned hidden namespace (ruling 12).** Any other dot-prefixed
  child of `pending/` (`.poison`, `.DS_Store`, hostile symlinks) is enumerated and classified
  via the ruling-1 path (grammar-invalid → quarantine) instead of being invisible forever.
- **Suite: 75 scenarios** (V.R/67-75 added; each fix round RED-proven by A/B against its
  pre-fix engine),
  declared gap [Q6] for the scanner-internal TOCTOU witnesses, and the jq re-probe is now
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
