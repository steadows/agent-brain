#!/usr/bin/env sh
# test/dm.sh — RED-phase suite for the Agent-Brain lane-DM feature, v1.2 (claim layer DELETED).
#
# AUTHORITY (in precedence order):
#   0. .context/seams/dm-v1.1-queue.md, the `# v1.2.2`, `# v1.2.3`, and `# v1.2.4`
#      CONTRACT ADDENDA — the latest rulings. Rulings 7/8/9 map to section V.R/67-71;
#      rulings 10/11/12 map to V.R/72-75; rulings 13/14 map to V.U/76-79; ruling 13a maps to
#      V.V/80-84; ruling 14's existing-leaf and ancestor validation map to V.V/85 and V.Y/86-89.
#      Erratum 13b is the signed witness ceiling: no later scenario may reopen shell-side JSON
#      witness tightening. Everything these rulings do not name is unchanged, so items 1-4 below
#      still govern.
#   1. .context/seams/dm-v1.1-queue.md, the `# v1.2.1 — CONTRACT ADDENDUM` section
#      (committed 33efc2d, authorized by Steve). It AMENDS the `# v1.2` section's
#      "Poison, without a counter" ruling and must-survive items 3 and 6; its six numbered
#      rulings are section V.Q's spec. Everything it does not name is unchanged, so items 2-4
#      below still govern the rest of this file.
#      docs/reviews/lane-dm-v12-pre-pr-code-review.md supplies the reproduced fixture shapes
#      (H1's 41-entry wall, H4's crafted name) — it is EVIDENCE, never authority.
#   2. .context/seams/dm-v1.1-queue.md, the `# v1.2` section (lines 335-467) — THE design
#      authority, DECIDED by Steve 2026-08-04. It supersedes decisions 4, 6, 6b and 6c for the
#      consume path; send-side atomicity (decisions 2 + 3) is explicitly UNCHANGED. Its "Delete"
#      list, its 8-item "Must survive" checklist, its "Poison, without a counter" ruling and its
#      "Suite consequences" retire/keep/add lists are this file's spec.
#   3. The same map's surviving v1.1 sections — decision 2 (dot-temp + same-directory rename),
#      decision 3 (message ID = filename = <_now_compact>-<pid>[+ collision bump]), decision 7
#      (wire format from/to/ts/content), decision 8 (DM_MAX_BODY kept), the `_dm_dir_ok` and
#      `_dm_digest` seams, and the altitude decision "no lock anywhere on the queue path".
#   4. docs/lane-dm-ultrareview-findings.md — UR-1 (emit before the terminal move), UR-2 (symlink
#      component refusal), UR-3 (a live-observed message is really consumed), UR-8 (no false
#      announce promise), UR-9/UR-10 (round-trip + body-independent journal).
#   5. AGENT_BRAIN_DM_GSD_PLAN.md task 5.7 (Steve, 2026-08-05) — a LATER and INDEPENDENT
#      authority, governing section V.P and nothing else. Its nine numbered "Requirements to pin
#      in RED", its named seam decision (ONE consume→emit→archive loop shared by
#      `_hook_session_start` and `_hook_pre_tool` — never a second copy) and its out-of-scope
#      list are V.P's spec. It reopens none of items 0-4, and items 0-4 say nothing about the
#      PreToolUse path, so the two do not compete.
# Implementation code is EVIDENCE, never authority. Where this suite pins something the map
# leaves open, the scenario comment says so out loud and names the choice that was forced.
#
# WHAT REPLACED WHAT: the v1.1 suite (60 scenarios) pinned `claimed/` as a state, claim
# timestamps and claimer PIDs, the DM_CLAIM_MAX_AGE lease, stale-claim recovery, the `.a<k>`
# delivery-attempt suffix, the poison cap / DM_MAX_ATTEMPTS, the detached lease sweeper, the
# shared transition budget, and — at Q.T/15 — two concurrent consumers receiving DISJOINT sets.
# Every one of those is deleted by the v1.2 ruling; Q.T/15 in particular encodes the
# exactly-once contract Steve REJECTED ("one active session per lane; delivery is at-least-once;
# duplicates acceptable"). All of them are retired here rather than weakened.
#
# FIXTURE GRAMMAR DISCIPLINE (the reason this suite has `plant_message` / `clone_queued`):
# v1.1 requires a queued file to be named `<id>.a<k>`; v1.2 deletes the suffix. A guard that
# hardcodes either spelling is a guard that must break at GREEN. So NO fixture here writes a
# queue filename by hand: every planted entry gets its name from a real `brain dm` send (its
# BYTES are then overwritten), or is cloned off such a name. Only the RED scenarios that pin the
# v1.2 grammar itself mention `.a<k>` — to forbid it.
#
# SAFETY: every scenario runs inside a throwaway git repo under a single mktemp -d root.
# The engine is never invoked with a real repository as CWD, and HOME is redirected into
# the fixture so no machine-global file can be touched. The secret probe string and every
# symlink target exist only in this file and inside those throwaway repos. Scenarios that
# chmod a directory read-only restore the mode BEFORE any early return, so the EXIT trap can
# still descend and remove the scratch root. `assert_disposable` runs in the PARENT shell
# (inside `_brain_env_run`, before the subshell) — never inside `_brain_exec`, where a `fatal`
# would kill only the subshell and the breach would render as PASS.
#
# DECLARED GAPS (absence here is a decision, not an oversight):
#   · UR-4a / UR-4b (`brain commit`) and UR-7 (`cmd_install`) have NO scenario in this file —
#     they live in test/commit-install.sh, which is frozen and out of scope for v1.2. [F13]
#   · `_atomic_place`'s "temp cleaned up on FAILURE" limb: V.S/3, V.S/11 and V.S/12 assert no
#     `.tmp-*` residue after a completed send and after both refusal paths, but a temp abandoned
#     by a crash BETWEEN create and rename is not drivable from the CLI. Not claimed. [F12]
#   · The `.tmp-*` STALE-SWEEP (v1.1's DM_TEMP_MAX_AGE=300, dirq maxtemp) has no scenario. It was
#     specified inside seam decision 6, which v1.2 supersedes "for the consume path" — and the
#     sweep is a SEND-side concern reached only from the deleted `_dm_recover_stale`. Whether it
#     survives is genuinely unresolved by the map. V.S/16 keeps the load-bearing half (a dot-temp
#     is invisible to every reader and is never delivered) and asserts nothing about ageing.
#     NON-BLOCKING open question — see the hand-off report. [F14]
#   · Two concurrent consumers of one lane: deliberately absent. The v1.2 ruling declares one
#     active session per lane, so a disjointness requirement would encode a rejected contract.
#   · SEND-side atomicity has no ENGINE-side witness. Must-survive #1's "dot-temp + same-directory
#     rename" is proven only from the READER side — V.S/3 and V.S/11/12 assert no `.tmp-*` residue
#     survives a completed or refused send, and V.S/16 asserts a dot-temp is invisible to every
#     reader and never delivered. Nothing here observes the rename itself: there is no CLI-drivable
#     interruption point inside `_atomic_place`, and manufacturing one would cost a bespoke
#     harness for a property the reader-side assertions already bound. Declared, not claimed. [L8]
#   · v1.2.1 ruling 1 names "a symlink, directory, FIFO, socket, or device node" as the unusable
#     class. V.Q/55 covers SYMLINK and DIRECTORY only. A FIFO was planted and then removed:
#     measured, it turns a dereferencing implementation's clean FAIL into an unbounded HANG (see
#     V.Q/55's own note). One predicate decides the whole class, and both hazards it names are
#     still exercised — but FIFO/socket/device-node handling is not claimed. [Q4]
#   · v1.2.1 ruling 6's bump-CONSTRUCTION-failure diagnostic is UNCOVERED. `_dm_collision_dest`
#     is reachable only THROUGH an already-occupied destination, so an engine that warns about
#     the occupancy before attempting the bump emits an indistinguishable `brain: ` line whether
#     or not the construction then fails silently. MEASURED against exactly that engine (a single
#     `_warn` added ahead of the `_dm_collision_dest` call, nothing else changed): V.Q/62 PASSED.
#     Separating the two anomalies needs the WORDING pinned, which this suite refuses to do
#     everywhere else (V.C/24's standing precedent). Reachability is NOT the obstacle — V.Q/62
#     limb B drives the failure today and is red on it; indistinguishability is. Dispatcher
#     ruling 2026-08-04: honest gap over hollow assertion. The "bump TAKEN" half of ruling 6 is
#     still pinned (V.Q/62 limb A) and V.Q/62 limb B is retained for the must-survive #2 property
#     it proves uniquely. NON-BLOCKING. [Q5]
#   · v1.2.1 ruling 5, first bullet (`_dm_id_in_use` must match the id AND any bumped variant)
#     has NO scenario. It is not drivable through the CLI: to observe it the engine must MINT an
#     id whose plain slot is free while a bumped variant exists, and the only mint inputs are
#     `_now_compact` and `$$`. Ruling 4 closes `_DM_ID_TS`, and `$$` differs on every invocation,
#     so a name matching a FUTURE mint cannot be pre-planted, and `dm @all` mints per-lane (no
#     intra-lane collision). Planting a bumped variant of a PAST id proves nothing — no later
#     send can reuse that base. Reaching the fault requires same-second PID REUSE to occur
#     naturally, which is not deterministically drivable. DISPATCHER RULING 2026-08-04: declare
#     the gap, build no structural witness, and land the fix in GREEN regardless — changing
#     `_dm_id_in_use` from exact-match to a `<id>*` glob is a STRICT WIDENING of a safety check
#     (it can report "in use" more often, never less), so it cannot introduce a new failure mode
#     even unproven by a scenario. An untested strict-widening is acceptable here; an untested
#     behaviour CHANGE would not be. NON-BLOCKING. [Q1]
#   · v1.2.1 ruling 5, second bullet (the digest `id` sits outside `bounded()`, permissible but
#     the dependency must be STATED at both sites, and DM_DIGEST_ENVELOPE's comment must say it
#     was sized for a four-field envelope) has no scenario: it is a COMMENT requirement on
#     `bin/brain`, with no observable behaviour to assert. The byte bound it rests on is already
#     pinned by V.W/27 and V.W/28. Deliberate omission. [Q2]
#   · V.Q/59 (ruling 3(b), the delimited-name round trip) is RED today for the right reason, but
#     it goes VACUOUSLY green once ruling 3(a)'s grammar lands: `_valid_names` is built only from
#     names that already passed `_dm_id_ok`, so with digit-only fields no whitespace-bearing name
#     can reach the collected set and the round-trip becomes unreachable from outside. Glob
#     metacharacters are already rejected in that position today, so they are not a second door.
#     The ruling itself calls the round trip "a live hazard for the NEXT name-shaped value" —
#     so once 3(a) lands, (b) is DEFENCE IN DEPTH against a future name-shaped value, NOT a
#     currently-reachable second bug. DISPATCHER RULING 2026-08-04: keep this behavioural, build
#     NO structural witness (a source-text grep prescribes a spelling and would need a bin/brain
#     mutation for its own negative control), and pin the discrimination at gate time with a
#     TEMPORARY probe mutant in test/mutation-probe.sh — grammar relaxed to accept whitespace,
#     after which this scenario must fire and only it. That mutant is owed by the probe rewrite,
#     which the dispatcher owns; it is NOT part of this file. Declared so the vacuity is never
#     mistaken for coverage. [Q3]
#   · The per-invocation batch size K is NOT pinned — only that a bound exists (V.N/50 caps
#     delivery at DM_INJECT_MAX_LINES over a 45-entry backlog), that bounding destroys nothing,
#     and that successive invocations drain the remainder without starvation. The map says "one
#     'process at most K entries' cap" and deliberately does not name K, so pinning a value here
#     would invent a ruling. A map decision, not an oversight. [L9]
#   · v1.2.2 ruling 7's scanner-INTERNAL post-expansion `_dm_dir_ok` checks in `_dm_id_in_use`
#     and `_dm_dir_has_entries` are not independently exercised. A permission flip after the
#     upfront probe but before the same process expands its glob is not drivable through one CLI
#     invocation without bespoke cross-process coordination. The upfront operation-fatal contract
#     remains pinned by V.R/67; the internal TOCTOU witnesses are declared, not claimed. [Q6]
#   · `_dm_failed_count`'s fork-free caller-visible scalar and post-expansion revalidation are
#     not independently observable through the CLI on a stable filesystem. V.Z/90-91 pin the
#     ordinary existing-empty and positive-count outcomes, while V.V/85 and V.Y/86-89 pin the
#     authoritative tri-state ancestor walk. Reintroducing command substitution preserves those
#     outputs, and deleting only the final revalidation needs the same permission-flip machinery
#     rejected at [Q6], so a single probe mutant would kill nothing. Per the round-7 instrument
#     budget: no new harness, no hollow mutant; this residual structural coverage gap is declared.
#     [Q7]
#   · Read-side `_dm_collision_dest` is unreachable for hostile names: `_dm_archive`'s grammar
#     gate precedes it. Hostile-name collision coverage therefore belongs to failed/ quarantine.
#
# RED DISCIPLINE: scenarios labelled "red" pin v1.2 behaviour and MUST fail against the current
# v1.1 engine. Scenarios labelled "guard:" are regression guards that pass against the current
# engine today and must keep passing through GREEN — they are the "keep" list of the map's
# Suite-consequences section, restated so that nothing they assert depends on deleted machinery.
#
# Usage: test/dm.sh          BRAIN_BIN=<path> overrides the engine under test.

# Scenario bodies are dispatched by name from `scenario`, so shellcheck cannot see the call.
# shellcheck disable=SC2329

set -u

# ── locate the engine under test ─────────────────────────────────────────────────────────
SUITE_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
REPO_ROOT=$(dirname "$SUITE_DIR")
BRAIN_BIN=${BRAIN_BIN:-$REPO_ROOT/bin/brain}
NAV_SKILL="$REPO_ROOT/templates/navigation-standards.SKILL.md"
DM_PROTOCOL="$REPO_ROOT/templates/DM-PROTOCOL.md"

# Fixed fixture environment. origin/main deliberately does NOT exist in a fixture, so
# reconcile's touches[] auto-fix stays a no-op and scenarios never mutate each other.
FIXTURE_BRANCH="main"
FIXTURE_MAIN_REF="origin/main"

# The bounds v1.2 KEEPS. DM_CLAIM_MAX_AGE, DM_MAX_ATTEMPTS, DM_TEMP_MAX_AGE and the shared
# transition budget are gone with the claim layer and are deliberately not restated here.
DM_MAX_BODY=4096          # seam decision 8  — body cap kept (rationale rewritten, value unchanged)
DM_INJECT_MAX_LINES=40    # seam "injection bounds" — USE as-is; also the v1.2 batch ceiling
DM_INJECT_MAX_COLS=2000   # seam "injection bounds" — BYTE cap per emitted line

# ── counters / current-scenario state ────────────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0
GUARD_FAILED=0
SC_FAILED=0
SC_REASONS=""
OUT=""
ERR=""

fatal() {
  printf 'test/dm.sh: FATAL %s\n' "$*" >&2
  exit 2
}

# ── disposable scratch root (the ONLY thing cleanup ever removes) ────────────────────────
SUITE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/brain-dm-test.XXXXXX") || fatal "mktemp failed"
SUITE_TMP=$(cd "$SUITE_TMP" && pwd -P) || fatal "cannot resolve scratch root"

cleanup() {
  case "$SUITE_TMP" in
    */brain-dm-test.*) ;;
    *) printf 'test/dm.sh: refusing to remove unexpected scratch root %s\n' "$SUITE_TMP" >&2
       return 0 ;;
  esac
  case "$SUITE_TMP" in
    *research-dashboard*)
      printf 'test/dm.sh: refusing to remove a path under a real project: %s\n' "$SUITE_TMP" >&2
      return 0 ;;
  esac
  [ -d "$SUITE_TMP" ] && rm -rf "$SUITE_TMP"
  return 0
}
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Abort the whole suite rather than operate anywhere outside the scratch root.
assert_disposable() {
  case "$1" in
    "$SUITE_TMP"/*) ;;
    *) fatal "refusing to operate outside the disposable scratch root: $1" ;;
  esac
  case "$1" in
    *research-dashboard*) fatal "refusing to operate on a real project path: $1" ;;
  esac
}

# ── preflight ────────────────────────────────────────────────────────────────────────────
[ -x "$BRAIN_BIN" ] || fatal "engine not executable: $BRAIN_BIN"
command -v jq  >/dev/null 2>&1 || fatal "jq is required (the engine itself depends on it)"
command -v git >/dev/null 2>&1 || fatal "git is required"

# ── fixture helpers ──────────────────────────────────────────────────────────────────────

# write_presence <repo> <slug> <status> [dialog_with] [updated]
# Minimal presence frontmatter, written directly so status/updated/dialog_with are fully
# controlled by the test and never depend on engine behaviour that is itself under test.
# <updated> defaults to now; pass an old timestamp to build a lane that LOOKS dormant.
write_presence() {
  _wp_repo=$1; _wp_slug=$2; _wp_status=$3; _wp_dialog=${4:-}
  _wp_updated=${5:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
  mkdir -p "$_wp_repo/.brain/presence" || return 1
  {
    printf -- '---\n'
    printf 'type: presence\n'
    printf 'agent: %s\n' "$_wp_slug"
    printf 'feature: "%s"\n' "$_wp_slug"
    printf 'status: %s\n' "$_wp_status"
    printf 'phase: fixture\n'
    printf 'owns_branches: ["%s"]\n' "$_wp_slug"
    printf 'plan: none\n'
    printf 'tracker_epic: none\n'
    printf 'current_worktree: %s\n' "$_wp_repo"
    printf 'current_branch: %s\n' "$FIXTURE_BRANCH"
    printf 'current_ticket: none\n'
    printf 'touches: []\n'
    if [ -n "$_wp_dialog" ]; then printf 'dialog_with: %s\n' "$_wp_dialog"; fi
    printf 'updated: %s\n' "$_wp_updated"
    printf -- '---\n'
    printf 'Fixture lane %s. No links, no TODO.\n' "$_wp_slug"
  } > "$_wp_repo/.brain/presence/$_wp_slug.md"
}

# make_vault <lane> [<lane>...]  →  prints the fixture REPO path (also creates a sibling
# fake HOME). Every lane is registered active. Errors go to stderr and return non-zero so
# a fixture bug aborts the suite instead of masquerading as a scenario failure.
make_vault() {
  _mv_base=$(mktemp -d "$SUITE_TMP/vault.XXXXXX") || { printf 'make_vault: mktemp failed\n' >&2; return 1; }
  _mv_base=$(cd "$_mv_base" && pwd -P) || return 1
  assert_disposable "$_mv_base"
  _mv_repo="$_mv_base/repo"
  mkdir -p "$_mv_repo" "$_mv_base/home/.claude" || return 1

  git init -q -b "$FIXTURE_BRANCH" "$_mv_repo" >/dev/null 2>&1 \
    || { printf 'make_vault: git init failed\n' >&2; return 1; }
  git -C "$_mv_repo" config user.email "brain-dm-test@example.invalid" || return 1
  git -C "$_mv_repo" config user.name  "brain dm test" || return 1
  git -C "$_mv_repo" config commit.gpgsign false || return 1
  printf 'disposable fixture repo for test/dm.sh\n' > "$_mv_repo/README-fixture.txt"
  git -C "$_mv_repo" add -- README-fixture.txt >/dev/null 2>&1 || return 1
  git -C "$_mv_repo" commit -q -m "fixture base" >/dev/null 2>&1 \
    || { printf 'make_vault: base commit failed\n' >&2; return 1; }

  run_brain "$_mv_repo" "" init --no-install
  if [ ! -d "$_mv_repo/.brain" ]; then
    printf 'make_vault: brain init did not scaffold .brain (stderr below)\n' >&2
    cat "$ERR" >&2 2>/dev/null
    return 1
  fi

  for _mv_lane in "$@"; do
    write_presence "$_mv_repo" "$_mv_lane" active \
      || { printf 'make_vault: could not write presence/%s.md\n' "$_mv_lane" >&2; return 1; }
  done

  printf '%s\n' "$_mv_repo"
}

# The engine invocation itself. Kept separate from the stream plumbing so the SAME environment
# is used whether the caller wants captured streams or a CLOSED stdout (the emit-failure
# instrument). Always run inside ( ) — it cd's and exec's.
_brain_exec() {
  _be_repo=$1; _be_id=$2; shift 2
  _be_base=$(dirname "$_be_repo")
  cd "$_be_repo" || exit 127
  exec env \
    HOME="$_be_base/home" \
    BRAIN_FEATURE="$_be_id" \
    BRAIN_TEST_BRANCH="$FIXTURE_BRANCH" \
    BRAIN_MAIN_REF="$FIXTURE_MAIN_REF" \
    BRAIN_SKILLS_DIR="$_be_base/home/.claude/skills" \
    BRAIN_GLOBAL_SETTINGS="$_be_base/home/.claude/settings.json" \
    BRAIN_PRETOOL_MODE=allow \
    "$BRAIN_BIN" "$@"
}

# _brain_env_run <outfile|'-'> <errfile> <repo> <identity> [args...]
# '-' as the outfile CLOSES stdout instead of redirecting it — that is how V.N/47 drives the
# "emit failed, so the message must stay pending" limb of must-survive #2.
# The disposability interlock lives HERE, in the parent shell: inside `_brain_exec`'s subshell a
# `fatal` would kill only the subshell and the breach would render as PASS.
_brain_env_run() {
  _br_out=$1; _br_err=$2; shift 2
  assert_disposable "$1"
  if [ "$_br_out" = "-" ]; then
    ( _brain_exec "$@" ) >&- 2>"$_br_err"
  else
    ( _brain_exec "$@" ) >"$_br_out" 2>"$_br_err"
  fi
}

# run_brain <repo> <identity> [args...] — invokes the SOURCE engine with CWD inside the
# fixture. Sets $OUT / $ERR to the captured streams; the caller reads $? for the status.
run_brain() {
  _rb_repo=$1
  _rb_base=$(dirname "$_rb_repo")
  OUT="$_rb_base/last.out"
  ERR="$_rb_base/last.err"
  _brain_env_run "$OUT" "$ERR" "$@"
}

# ── queue-layout helpers (seam decision 1, minus the deleted claimed/ state) ──────────────
# q_dir <repo> <lane> <state>  where state ∈ pending | read | failed
# (`claimed` is named in exactly one scenario — V.N/46 — to assert it does NOT exist.)
q_dir() { printf '%s' "$1/.brain/dm/$2/$3"; }

# journal entry lines ("- <ts> <feat> — <msg>") across every journal file in the vault
journal_entries() { grep -h '^- ' "$1"/.brain/journal/*.md 2>/dev/null || true; }
journal_entry_count() { journal_entries "$1" | wc -l | tr -d ' \n'; }
journal_raw_count() { cat "$1"/.brain/journal/*.md 2>/dev/null | wc -l | tr -d ' \n'; }
journal_since() { journal_entries "$1" | tail -n +"$(($2 + 1))"; }

line_count() { [ -f "$1" ] || { printf '0'; return 0; }; wc -l < "$1" | tr -d ' \n'; }
byte_size()  { [ -f "$1" ] || { printf '0'; return 0; }; wc -c < "$1" | tr -d ' \n'; }

# Longest line of <file> in BYTES. LC_ALL=C is load-bearing: awk's length() counts characters in
# a UTF-8 locale, and the wire caps the map names are byte caps (`utf8bytelength`).
max_line_bytes() {
  [ -f "$1" ] || { printf '0'; return 0; }
  LC_ALL=C awk '{ n = length($0); if (n > m) m = n } END { printf "%d", m + 0 }' "$1" 2>/dev/null
}

# Every queue iteration in this suite uses the seam's own guard — `[ -e ] || [ -L ]` — so a
# BROKEN symlink planted in a queue directory is COUNTED, not silently invisible to the test.
count_files() {
  _cf=0
  for _cf_f in "$1"/*; do
    [ -e "$_cf_f" ] || [ -L "$_cf_f" ] || continue
    _cf=$((_cf + 1))
  done
  printf '%s' "$_cf"
}

first_file() {
  for _ff in "$1"/*; do
    [ -e "$_ff" ] || [ -L "$_ff" ] || continue
    printf '%s' "$_ff"; return 0
  done
  return 1
}

# Dot-prefixed entries — the temp names (seam decision 2, UNCHANGED by v1.2: the temp is
# `.tmp-<id>` inside pending/ itself). A plain `for f in dir/*` never sees them, which is exactly
# the property the design relies on; this helper is how the suite checks what the glob cannot.
count_dotfiles() {
  _cd=0
  for _cd_f in "$1"/.*; do
    case "${_cd_f##*/}" in .|..) continue ;; esac
    [ -e "$_cd_f" ] || [ -L "$_cd_f" ] || continue
    _cd=$((_cd + 1))
  done
  printf '%s' "$_cd"
}

# The immutable message id. Under v1.2 the filename IS the id; under the v1.1 engine it carries a
# `.a<k>` tail. Stripping a `.a*` suffix that may not be there makes every id-preservation
# assertion in this file grammar-agnostic — it reads the same id from either engine.
msg_id_of() { _mi=${1##*/}; printf '%s' "${_mi%.a*}"; }

# the message id of whichever file in <dir> carries <needle> in its BODY (order-free lookup)
id_of_body() {
  for _ib in "$1"/*; do
    [ -e "$_ib" ] || continue
    if grep -qF -- "$2" "$_ib" 2>/dev/null; then msg_id_of "$_ib"; return 0; fi
  done
  return 1
}

# does any entry in <dir> carry message id <id> in its name?
dir_has_id() {
  for _dh in "$1"/*; do
    [ -e "$_dh" ] || [ -L "$_dh" ] || continue
    case "${_dh##*/}" in *"$2"*) return 0 ;; esac
  done
  return 1
}

str_has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

err_tail() { tr '\n' ' ' < "$ERR" 2>/dev/null | cut -c1-160; }

# `brain status` ECHOES recent journal lines verbatim, and the DM call-log pointer wording may
# legitimately contain the word "failed", so a control that grepped ALL of status would fire on
# the echo rather than on the quarantine banner. This looks ONLY at status's own rendering.
# The filter is anchored to the REAL journal entry format written by _announce_as —
# `- <ISO-8601-ts> <feat> — <msg>` — not to a bare "- " prefix. [F3/R2-3]
status_has_failed() { grep -vE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$1" 2>/dev/null | grep -qi 'failed'; }

# Journal-line SHAPE: the line with every digit removed. Timestamps, pids and message ids are
# all digit-bearing, so two sends of two different bodies must produce the SAME shape — while a
# base64/hex/encoded body leaves differing letters behind and breaks the equality. This is
# UR-10's "compare journal payloads for two different bodies and require body-independence".
journal_shape() { printf '%s' "$1" | tr -d '0-9'; }

# The startup context the SessionStart hook injects.
hook_context() { # <repo> <identity> → prints additionalContext, non-zero if it can't
  run_brain "$1" "$2" hook session-start
  _hc_rc=$?
  [ "$_hc_rc" = "0" ] || return 1
  jq -e -r '.hookSpecificOutput.additionalContext // empty' "$OUT" 2>/dev/null
}

# Must-survive #4: "If entries remain, the emitted context must explicitly instruct
# continuation — do not rely on a new directory event firing." The map does not pin the WORDING,
# so this is a broad alternation, and V.N/50 pairs it with a NEGATIVE CONTROL fixture whose
# backlog fits in one batch: the phrase must be ABSENT there. That control is what stops the
# alternation from being satisfied by boilerplate the boot always prints.
continuation_signal() { # <context-string>
  printf '%s' "$1" | grep -qiE 'remain|more (dm|message)|still (queued|pending)|again'
}

# ── assertion helpers — each records a reason and returns 1 so callers can short-circuit ─
fail() {
  SC_FAILED=1
  SC_REASONS="$SC_REASONS
      - $*"
  return 1
}

need_rc() { # <actual> <expected> <label>
  [ "$1" = "$2" ] && return 0
  fail "$3: exit $1, want $2 (stderr: $(err_tail))"
}

need_rc_nonzero() { # <actual> <label>
  [ "$1" != "0" ] && return 0
  fail "$2: exit 0, want non-zero"
}

need_eq() { # <actual> <expected> <label>
  [ "$1" = "$2" ] && return 0
  fail "$3: got '$1', want '$2'"
}

need_file() { [ -f "$1" ] && return 0; fail "$2: no such file: $1"; }
need_file_absent() { [ ! -e "$1" ] && [ ! -L "$1" ] && return 0; fail "$2: must not exist: $1"; }
need_dir_absent() { [ ! -d "$1" ] && return 0; fail "$2: directory should not exist: $1"; }
need_real_dir() {
  [ -d "$1" ] && [ ! -L "$1" ] && return 0
  fail "$2: not a real (non-symlink) directory: $1"
}
need_real_file() {
  [ -f "$1" ] && [ ! -L "$1" ] && return 0
  fail "$2: not a real (non-symlink) regular file: $1"
}

need_count() { # <dir> <expected> <label>
  _nc=$(count_files "$1")
  [ "$_nc" = "$2" ] && return 0
  fail "$3: $1 holds $_nc entr(y|ies), want $2"
}

need_file_has() { # <file> <needle> <label>
  grep -qF -- "$2" "$1" 2>/dev/null && return 0
  fail "$3: '$2' not found in $1"
}

need_file_lacks() { # <file> <needle> <label>
  grep -qF -- "$2" "$1" 2>/dev/null || return 0
  fail "$3: '$2' WAS found in $1 and must not be"
}

need_str_has() { # <haystack> <needle> <label>
  str_has "$1" "$2" && return 0
  fail "$3: '$2' not present in the captured output"
}

need_str_lacks() { # <haystack> <needle> <label>
  str_has "$1" "$2" || return 0
  fail "$3: '$2' IS present in the captured output and must not be"
}

need_tree_has() { # <dir> <needle> <label>
  if [ ! -d "$1" ]; then fail "$3: expected directory does not exist: $1"; return 1; fi
  grep -rqF -- "$2" "$1" 2>/dev/null && return 0
  fail "$3: '$2' not found anywhere under $1"
}

need_tree_lacks() { # <dir> <needle> <label>
  # a missing directory is a FAILURE, not a clean grep — otherwise "nothing leaked"
  # would be satisfied by there being nothing to leak into.
  if [ ! -d "$1" ]; then fail "$3: expected directory does not exist: $1"; return 1; fi
  if grep -rqF -- "$2" "$1" 2>/dev/null; then fail "$3: '$2' found somewhere under $1"; return 1; fi
  return 0
}

need_dir_has_id() { # <dir> <id> <label>
  dir_has_id "$1" "$2" && return 0
  fail "$3: no entry carrying message id '$2' under $1"
}

need_dir_lacks_id() { # <dir> <id> <label>
  dir_has_id "$1" "$2" || return 0
  fail "$3: an entry carrying message id '$2' IS under $1 and must not be"
}

# The message must still be SOMEWHERE the engine can reach — the loss guard that is neutral
# between v1.1 (which parks a mid-flight message in claimed/) and v1.2 (which leaves it in
# pending/). The v1.2-specific "and it is in pending/" claim is asserted only by the RED
# scenarios V.N/47, V.N/48 and V.N/51, where it is the thing under test.
need_not_lost() { # <repo> <lane> <needle> <label>
  need_tree_has "$1/.brain/dm/$2" "$3" "$4 (the message must not be destroyed by a failed transition)"
}

# Every rendered digest record must be a JSON object carrying all four contract fields, with no
# key outside {from,to,ts,content,id}.
#
# SUPERSET-BOUNDED on purpose. The v1.1 suite asserted `keys == ["content","from","to","ts"]`,
# which is unsatisfiable against must-survive #8 (the message id must be exposed and the map does
# not say how). This restores everything that equality actually bought — one value per record,
# object-ness, all four fields present, unknown producer fields refused — while PERMITTING `id`.
# It does not REQUIRE `id`: that is V.N/52's job, and double-pinning it here would make three
# guards flip red for a reason they are not about.
need_digest_records_wellformed() { # <file> <label>
  jq -e -s '
    length > 0
    and (map(
      (type == "object")
      and (has("from") and has("to") and has("ts") and has("content"))
      and (((keys) - ["content", "from", "id", "to", "ts"]) | length == 0)
    ) | all)
  ' "$1" >/dev/null 2>&1 && return 0
  fail "$2: the emitted digest is not a sequence of well-formed records — each must parse as a JSON object carrying from/to/ts/content, with no key outside {from,to,ts,content,id}"
}

# v1.2 queue-name grammar: `<_now_compact>-<pid>[-<n>]`, with NO delivery-attempt suffix and no
# claim stamp. Authority: seam decision 3 ("Message ID = filename = <_now_compact>-<pid> + a
# collision bump"), which the v1.2 ruling leaves UNCHANGED, minus `.a<k>` and `.c<ts>-<pid>`,
# which its Delete list removes ("the delivery-attempt counter (`.a<k>`)", "claim timestamps and
# claimer PIDs").
need_v12_queue_name() { # <path> <label>
  _nq=${1##*/}
  case "$_nq" in
    *.a[0-9]*)
      fail "$2: '$_nq' still carries a .a<k> delivery-attempt suffix — the v1.2 Delete list removes the attempt counter"
      return 1 ;;
    *.c[0-9]*)
      fail "$2: '$_nq' still carries a .c<claim-ts>-<pid> claim stamp — the v1.2 Delete list removes claim timestamps and claimer PIDs"
      return 1 ;;
  esac
  printf '%s' "$_nq" | grep -qE '^[0-9]{8}T[0-9]{6}Z-[0-9][0-9]*(-[0-9][0-9]*)?$' && return 0
  fail "$2: '$_nq' does not match the v1.2 name grammar <ts>-<pid>[-<n>] (seam decision 3, unchanged; _now_compact is %Y%m%dT%H%M%SZ)"
}

# ── instruments ──────────────────────────────────────────────────────────────────────────

# make_readonly_dir <dir> — chmod 0500 plus a POSITIVE CONTROL that a rename INTO it really
# fails here. Without the control, "the engine could not write" is indistinguishable from
# "the test is running as root and the block never engaged".
# Returns 0 (blocked, instrument live), 1 (fixture error), 2 (instrument blind).
make_readonly_dir() {
  _mr_d=$1
  mkdir -p "$_mr_d" || return 1
  chmod 500 "$_mr_d" || return 1
  _mr_probe="$_mr_d.probe.$$"
  : > "$_mr_probe" || { chmod 755 "$_mr_d" 2>/dev/null; return 1; }
  if mv "$_mr_probe" "$_mr_d/probe" 2>/dev/null; then
    rm -f "$_mr_d/probe" 2>/dev/null
    chmod 755 "$_mr_d" 2>/dev/null
    return 2
  fi
  rm -f "$_mr_probe" 2>/dev/null
  return 0
}

# make_unreadable_dir <dir> — chmod 0300 (write+search, no read) plus both sides of the
# permission instrument: an exact child path must still resolve while the ordinary glob must
# not enumerate it. The probe is removed by exact path before returning, while search is live.
# Returns 0 (instrument live), 1 (fixture error), 2 (instrument blind, e.g. running as root).
make_unreadable_dir() {
  _mu_d=$1
  mkdir -p "$_mu_d" || return 1
  _mu_probe="$_mu_d/permission-probe-$$"
  : > "$_mu_probe" || return 1
  chmod 300 "$_mu_d" || { rm -f "$_mu_probe" 2>/dev/null; return 1; }
  if [ ! -e "$_mu_probe" ]; then
    chmod 755 "$_mu_d" 2>/dev/null
    return 2
  fi
  _mu_seen=0
  for _mu_f in "$_mu_d"/*; do
    [ -e "$_mu_f" ] || [ -L "$_mu_f" ] || continue
    _mu_seen=1
    break
  done
  rm -f "$_mu_probe" 2>/dev/null || { chmod 755 "$_mu_d" 2>/dev/null; return 1; }
  if [ "$_mu_seen" = 1 ]; then
    chmod 755 "$_mu_d" 2>/dev/null
    return 2
  fi
  return 0
}

# write_rc0_empty_payload_jq <dest> <real-jq> <payload-arg-name>
# Build one stable-path jq shim that delegates every capability probe to the real binary but
# returns `{}` with rc 0 for the selected payload call. `id`, `c`, and `f` select the digest,
# SessionStart envelope, and send encoder respectively. This is deliberately an argv case-check,
# not a JSON parser or a cross-process state machine.
write_rc0_empty_payload_jq() {
  _we_dest=$1; _we_real=$2; _we_name=$3
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '_prev=""\n'
    printf 'for _arg in "$@"; do\n'
    printf '  if [ "$_prev" = "--arg" ] && [ "$_arg" = "%s" ]; then printf "{}\\n"; exit 0; fi\n' "$_we_name"
    printf '  _prev=$_arg\n'
    printf 'done\n'
    printf 'exec "%s" "$@"\n' "$_we_real"
  } > "$_we_dest" || return 1
  chmod +x "$_we_dest"
}

# write_rc0_truncated_payload_jq <dest> <real-jq> <payload-arg-name>
# Delegate the selected payload call to real jq in compact form, then remove its final byte while
# preserving rc 0. A terminal space keeps the caller's command substitution from exposing the
# nested envelope's preceding `}` after it removes trailing newlines; the removed byte is still
# exactly real jq's outer closing delimiter.
write_rc0_truncated_payload_jq() {
  _wt_dest=$1; _wt_real=$2; _wt_name=$3
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '_prev=""; _hit=0\n'
    printf 'for _arg in "$@"; do\n'
    printf '  if [ "$_prev" = "--arg" ] && [ "$_arg" = "%s" ]; then _hit=1; break; fi\n' "$_wt_name"
    printf '  _prev=$_arg\n'
    printf 'done\n'
    printf 'if [ "$_hit" = 1 ]; then\n'
    printf '  _payload=$("%s" -c "$@") || exit $?\n' "$_wt_real"
    printf '  printf "%%s \\n" "${_payload%%?}"\n'
    printf '  exit 0\n'
    printf 'fi\n'
    printf 'exec "%s" "$@"\n' "$_wt_real"
  } > "$_wt_dest" || return 1
  chmod +x "$_wt_dest"
}

# write_rc0_wrong_send_payload_jq <dest> <real-jq>
# Delegate ordinary calls, but return a framed wrong object for the send encoder payload call.
write_rc0_wrong_send_payload_jq() {
  _ww_dest=$1; _ww_real=$2
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '_prev=""\n'
    printf 'for _arg in "$@"; do\n'
    printf '  if [ "$_prev" = "--arg" ] && [ "$_arg" = "f" ]; then\n'
    printf '    printf '\''{"values":["from","to","ts","content"]}\\n'\''; exit 0\n'
    printf '  fi\n'
    printf '  _prev=$_arg\n'
    printf 'done\n'
    printf 'exec "%s" "$@"\n' "$_ww_real"
  } > "$_ww_dest" || return 1
  chmod +x "$_ww_dest"
}

# write_status_only_envelope_jq <dest> <real-jq>
# For the SessionStart serializer only, retain the status tail of additionalContext and drop the
# staged digest block. This transforms an engine value, not JSON; real jq still serializes it.
write_status_only_envelope_jq() {
  _ws_dest=$1; _ws_real=$2
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf 'if [ "$#" -eq 5 ] && [ "$1" = "-n" ] && [ "$2" = "--arg" ] && [ "$3" = "c" ]; then\n'
    printf '  _status=$(printf "%%s\\n" "$4" | sed -n '\''/^Active features:/,$p'\'')\n'
    printf '  exec "%s" -n --arg c "$_status" "$5"\n' "$_ws_real"
    printf 'fi\n'
    printf 'exec "%s" "$@"\n' "$_ws_real"
  } > "$_ws_dest" || return 1
  chmod +x "$_ws_dest"
}

# plant_message <repo> <lane> <marker> — send a REAL message from alpha carrying <marker>, then
# print the path of the file the engine queued for it.
#
# WHY THIS EXISTS (and why it is the cheapest thing that works): several wire-contract fixtures
# cannot be produced through the CLI at all — a second JSON object in one file, an unknown field,
# a 6 KB `from`, multibyte in `to`/`ts`, invalid JSON. The v1.1 suite hand-wrote the filenames,
# which hardcoded `<id>.a<k>` into eleven fixtures. v1.2 deletes that suffix, so every one of
# those guards would have had to break at GREEN. Letting the ENGINE mint the name and overwriting
# only the file's BYTES keeps the fixture valid under both grammars, with no name parsing, no
# grammar table and no per-engine branch.
plant_message() {
  _pm_fx=$1; _pm_lane=$2; _pm_marker=$3
  run_brain "$_pm_fx" alpha dm "@$_pm_lane" "$_pm_marker" || return 1
  for _pm_f in "$(q_dir "$_pm_fx" "$_pm_lane" pending)"/*; do
    [ -e "$_pm_f" ] || continue
    if grep -qF -- "$_pm_marker" "$_pm_f" 2>/dev/null; then printf '%s' "$_pm_f"; return 0; fi
  done
  return 1
}

# clone_queued <src-file> <count> <marker-prefix> — mint <count> additional queued entries whose
# NAMES are derived from an engine-minted one, so a large backlog costs one engine invocation
# instead of N. The bump is inserted before whatever suffix the engine uses (`.a0` under v1.1,
# none under v1.2), which is exactly seam decision 3's `-<n>` collision bump in both grammars.
# Each clone carries `<marker-prefix><NN>-marker` so deliveries can be counted individually.
clone_queued() {
  _cq_src=$1; _cq_n=$2; _cq_pre=$3
  _cq_dir=${_cq_src%/*}; _cq_base=${_cq_src##*/}
  _cq_id=${_cq_base%%.*}; _cq_sfx=${_cq_base#"$_cq_id"}
  _cq_i=1
  while [ "$_cq_i" -le "$_cq_n" ]; do
    jq -cn --arg c "$_cq_pre$(printf '%02d' "$_cq_i")-marker" \
      '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:$c}' \
      > "$_cq_dir/$_cq_id-$_cq_i$_cq_sfx" || return 1
    _cq_i=$((_cq_i + 1))
  done
}

# drain_takes <repo> <lane> <max-invocations> — run `brain dm take` until pending/ is empty or
# the invocation budget runs out. Prints the number of invocations used. Used only to prove the
# bounded batch RESUMES (must-survive #4), never to define the bound.
drain_takes() {
  _dt_fx=$1; _dt_lane=$2; _dt_max=$3; _dt_i=0
  while [ "$_dt_i" -lt "$_dt_max" ]; do
    [ "$(count_files "$(q_dir "$_dt_fx" "$_dt_lane" pending)")" = 0 ] && break
    run_brain "$_dt_fx" "$_dt_lane" dm take
    _dt_i=$((_dt_i + 1))
  done
  printf '%s' "$_dt_i"
}

# ── scenario runner ──────────────────────────────────────────────────────────────────────
scenario() { # <kind: red|guard> <name> <function>
  SC_FAILED=0
  SC_REASONS=""
  "$3"
  TOTAL=$((TOTAL + 1))
  _sc_label=$2
  [ "$1" = "guard" ] && _sc_label="guard: $2"
  if [ "$SC_FAILED" = "0" ]; then
    PASSED=$((PASSED + 1))
    printf 'PASS  %s\n' "$_sc_label"
  else
    FAILED=$((FAILED + 1))
    [ "$1" = "guard" ] && GUARD_FAILED=$((GUARD_FAILED + 1))
    printf 'FAIL  %s\n' "$_sc_label"
    printf '%s\n' "$SC_REASONS" | sed '/^$/d'
  fi
}

# ══════════════════════════ V.S — send / storage layout (all guards) ═════════════════════
# Must-survive #1 (atomic send: unique stable id, dot-temp, same-directory rename) and the
# journal-secrecy half of #6. Nothing in this section touches the deleted claim layer.

# V.S/1 — `brain inbox` prints the pending/ DIRECTORY to arm on, and the retired single-inbox
# file is never created.
#   DOES NOT   pin which sibling state directories are created eagerly — the map says "the
#   PROVE      directory tree" without enumerating. V.N/46 is what forbids `claimed/`.
sc_inbox_prints_pending_dir() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha inbox
  rc=$?
  need_rc "$rc" 0 "brain inbox" || return 0

  path=$(head -1 "$OUT")
  need_eq "$(line_count "$OUT")" 1 "brain inbox stdout line count" || return 0
  [ -n "$path" ] || { fail "brain inbox printed nothing"; return 0; }

  case "$path" in
    "$fx"/*) ;;
    *) fail "printed path is not an absolute path inside the vault: $path" ;;
  esac
  case "$path" in
    */dm/alpha/pending) ;;
    *) fail "brain inbox must print the pending/ DIRECTORY to arm on, got: $path" ;;
  esac
  need_real_dir "$path" "the printed arming target"
  need_file_absent "$fx/.brain/dm/alpha/inbox.jsonl" \
    "the retired single-shared-inbox file (nothing may re-create it)"
}

# V.S/2 — the dispatcher and usage() must both know the live-consumption command. Without
# `dm take` in usage(), UR-3's fix is undiscoverable by the agent that has to run it.
sc_usage_lists_dm_and_take() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha help
  rc=$?
  need_rc "$rc" 0 "brain help" || return 0
  need_file_has "$OUT" "brain announce" "usage() baseline (an existing command is listed)" || return 0
  need_file_has "$OUT" "brain dm" "usage() must list the dm subcommand"
  need_file_has "$OUT" "brain inbox" "usage() must list the inbox subcommand"
  need_file_has "$OUT" "dm take" "usage() must list the live-consumption command (UR-3's fix)"
}

# V.S/3 — must-survive #1. ONE message is ONE file: a single JSON object, no temp residue, and
# no copy anywhere but the recipient's pending/.
#   REJECTS    an append-based encoder (jq -s length would be > 1), a shared-inbox regression
#              (count in pending/ would be 0), a temp left behind by a completed send, and a
#              self-copy that boot delivery would read back to the sender.
#   NAME       the filename grammar is deliberately NOT asserted here — it is the one part of
#              the send contract v1.2 changes, so it is pinned by V.N/46 (RED) instead.
sc_send_writes_one_message_file() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  need_count "$pd" 0 "bravo's pending/ before any send" || return 0

  run_brain "$fx" alpha dm @bravo "hello-queue-7f1"
  rc=$?
  need_rc "$rc" 0 "brain dm @bravo" || return 0

  need_count "$pd" 1 "message files in bravo's pending/ after ONE send" || return 0
  need_eq "$(count_dotfiles "$pd")" 0 \
    "dot-prefixed temp entries left in pending/ (seam decision 2: the temp is .tmp-<id> in pending/ and a completed send must leave none)"

  f=$(first_file "$pd")
  need_real_file "$f" "the queued message" || return 0

  if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    fail "the message file is not a single JSON object: $(head -c 200 "$f")"
    return 0
  fi
  need_eq "$(jq -s 'length' "$f" 2>/dev/null)" 1 \
    "JSON values in the message file (one message = one file = one object; >1 means the append model survived)"
  need_eq "$(jq -r '.from    // ""' "$f")" "alpha" "message .from"
  need_eq "$(jq -r '.to      // ""' "$f")" "bravo" "message .to"
  need_eq "$(jq -r '.content // ""' "$f")" "hello-queue-7f1" "message .content"
  need_eq "$(jq -r 'has("ts")' "$f")" "true" "message has a ts field"
  [ -n "$(jq -r '.ts // ""' "$f")" ] || fail "message .ts is empty"

  # point-to-point: neither an uninvolved lane nor the SENDER may hold a copy. A self-copy
  # would be delivered back to alpha at its next boot — a lane reading its own outbound mail.
  need_count "$(q_dir "$fx" charlie pending)" 0 "charlie (uninvolved lane) pending/"
  need_count "$(q_dir "$fx" alpha pending)" 0 "the sender's OWN pending/ after a p2p send"
}

# V.S/4 — three sends land as three DISTINCT files. Sends from separate processes in the same
# clock second differ only by <pid>, which is exactly what seam decision 3 (UNCHANGED by v1.2)
# relies on; a timestamp-only id would collapse them and lose messages silently.
sc_rapid_sends_stay_distinct() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  for m in rapid-a1 rapid-b2 rapid-c3; do
    run_brain "$fx" alpha dm @bravo "$m"
    rc=$?
    need_rc "$rc" 0 "brain dm @bravo ($m)" || return 0
  done

  need_count "$pd" 3 "message files after three sends (a colliding id would show fewer)" || return 0
  for m in rapid-a1 rapid-b2 rapid-c3; do
    need_tree_has "$pd" "$m" "every sent body must still be in pending/ ($m)"
  done
}

# V.S/5 — the body cap survives. Seam decision 8: "DM_MAX_BODY kept, rationale rewritten"; the
# v1.2 ruling does not reopen it. An over-cap send is REFUSED outright: nothing queued, nothing
# journalled, no temp residue.
# This guards against a rewrite quietly DROPPING the cap while rewriting the comment that
# justifies it — an implementer reading "that rationale evaporates" could reasonably delete it.
sc_over_cap_body_refused() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  over=$(awk -v n="$(( DM_MAX_BODY + 64 ))" 'BEGIN{ s = ""; for (i = 0; i < n; i++) s = s "y"; printf "%s", s }')
  need_eq "${#over}" "$(( DM_MAX_BODY + 64 ))" "fixture: the over-cap probe body is the intended length" || return 0

  run_brain "$fx" alpha dm @bravo "under-cap-probe"
  rc=$?
  need_rc "$rc" 0 "positive control: an UNDER-cap send is still accepted" || return 0
  before=$(count_files "$pd")
  before_entries=$(journal_entry_count "$fx")

  run_brain "$fx" alpha dm @bravo "$over"
  rc=$?
  need_rc_nonzero "$rc" "brain dm with a body over DM_MAX_BODY ($DM_MAX_BODY chars)"
  [ -s "$ERR" ] || fail "an over-cap send wrote nothing to stderr"
  need_eq "$(count_files "$pd")" "$before" "pending/ count after a REFUSED over-cap send"
  need_eq "$(count_dotfiles "$pd")" 0 "temp residue after a refused over-cap send"
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 0 \
    "journal entry lines added by a REFUSED over-cap send"
}

# V.S/6 — UR-9. A body carrying `"`, `\`, a tab and an INTERNAL NEWLINE must round-trip byte for
# byte, in storage AND through delivery. Every pre-UR-9 test body was JSON-safe ASCII, so a
# naïvely interpolated encoder passed them all while corrupting exactly these four characters.
sc_json_special_body_round_trip() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending)
  body=$(printf 'ur9mark q="dq" bs=\\ tab:\tX\nsecond physical line')

  run_brain "$fx" alpha dm @bravo "$body"
  rc=$?
  need_rc "$rc" 0 "brain dm with a JSON-special body" || return 0

  need_count "$pd" 1 "message files after one JSON-special send" || return 0
  f=$(first_file "$pd")
  if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    fail "JSON-special body did not encode to a valid JSON object: $(head -c 200 "$f")"
    return 0
  fi
  need_eq "$(jq -s 'length' "$f" 2>/dev/null)" 1 \
    "JSON values in the file — an unescaped internal newline would make this 2 (or invalid)"

  jq -r '.content' "$f" > "$base/ur9.got" 2>/dev/null
  printf '%s\n' "$body" > "$base/ur9.want"
  if ! cmp -s "$base/ur9.got" "$base/ur9.want"; then
    fail "decoded .content is not byte-identical to the sent body (UR-9 round trip); got $(byte_size "$base/ur9.got") bytes, want $(byte_size "$base/ur9.want")"
  fi

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take (JSON-special body)" || return 0
  need_file_has "$OUT" "ur9mark" "the JSON-special message must actually be delivered by take"
}

# V.S/7 — must-survive #6 (journal body exclusion). The journal keeps a POINTER, never the body.
#   The pointer's exact path form is deliberately NOT pinned: the map never restates the call-log
#   grammar, so this asserts only that the line names the recipient and points into that lane's
#   dm tree. V.S/8 closes UR-10's encoded-body hole; this is the literal-leak half.
sc_dm_journals_pointer_not_body() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  # A REPEATED short marker: every substring of the body >= 4 chars contains 'zzq7', so a
  # partial/truncated leak ("journal the first 16 chars") is caught as surely as a verbatim one.
  marker="zzq7"
  body="zzq7-zzq7-zzq7-zzq7-zzq7"
  before_entries=$(journal_entry_count "$fx")
  before_raw=$(journal_raw_count "$fx")

  run_brain "$fx" alpha dm @bravo "$body"
  rc=$?
  need_rc "$rc" 0 "brain dm @bravo" || return 0
  need_count "$(q_dir "$fx" bravo pending)" 1 "the send actually delivered" || return 0

  after_entries=$(journal_entry_count "$fx")
  after_raw=$(journal_raw_count "$fx")
  need_eq "$((after_entries - before_entries))" 1 "journal entry lines added by one dm" || return 0
  need_eq "$((after_raw - before_raw))" 1 "raw journal lines added by one dm"

  new=$(journal_since "$fx" "$before_entries")
  need_str_has "$new" ".brain/dm/bravo" "journal line must carry a transcript pointer into the recipient's dm tree"
  need_str_has "$new" "@bravo" "journal line must name the recipient"
  need_str_lacks "$new" "$marker" "journal line must NOT carry the message body (not even a fragment)"
  need_tree_lacks "$fx/.brain/journal" "$marker" "message-body fragment anywhere under journal/"
  # positive control: the body really did travel, so a clean journal is a real result
  need_tree_has "$(q_dir "$fx" bravo pending)" "$body" "the body reached the queue (positive control)"
}

# V.S/8 — UR-10. Literal-fragment assertions alone let a call-log line carrying `base64(content)`
# pass while committing a reversible credential.
#   INSTRUMENT the journal line with every DIGIT removed. Timestamps, pids and message ids are
#              digit-bearing, so two sends of two DIFFERENT bodies must normalise to the SAME
#              string. Any body-derived component — base64, hex, a length, a hash, a prefix —
#              leaves differing letters behind and breaks the equality.
#   FIXTURE    the two bodies are the same LENGTH and contain no digits, so a length field or a
#              digit-only encoding cannot smuggle a difference past the normaliser either.
#   COVERS     the direct path AND the @all broadcast path (the finding requires both).
#   Verified DISCRIMINATING against a mutant engine that appends [b64:<body>] to the call-log
#   line: that mutant satisfies every literal-fragment assertion and is rejected by the shape
#   comparison.
sc_journal_body_independent() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  b1="mikeoscarpapaquebecromeosierrax"    # 31 chars, letters only
  b2="tangouniformvictorwhiskeyxrayzu"    # 31 chars, letters only, no shared 4-gram

  # ── direct path ──
  n0=$(journal_entry_count "$fx")
  run_brain "$fx" alpha dm @bravo "$b1"
  rc=$?
  need_rc "$rc" 0 "direct send #1" || return 0
  n1=$(journal_entry_count "$fx")
  need_eq "$((n1 - n0))" 1 "journal lines added by direct send #1" || return 0
  l1=$(journal_since "$fx" "$n0")

  run_brain "$fx" alpha dm @bravo "$b2"
  rc=$?
  need_rc "$rc" 0 "direct send #2" || return 0
  n2=$(journal_entry_count "$fx")
  need_eq "$((n2 - n1))" 1 "journal lines added by direct send #2" || return 0
  l2=$(journal_since "$fx" "$n1")

  s1=$(journal_shape "$l1"); s2=$(journal_shape "$l2")
  [ -n "$s1" ] || fail "instrument check: the normalised direct journal line is empty"
  need_eq "$s1" "$s2" \
    "DIRECT call-log line is not body-independent (UR-10): two different bodies produced different digit-stripped lines, so something body-derived is on the line"
  need_str_lacks "$l1" "$b1" "direct call-log line carries the body verbatim"
  need_str_lacks "$l2" "$b2" "direct call-log line carries the body verbatim"

  # ── broadcast path ──
  n3=$(journal_entry_count "$fx")
  run_brain "$fx" alpha dm @all "$b1"
  rc=$?
  need_rc "$rc" 0 "broadcast #1" || return 0
  n4=$(journal_entry_count "$fx")
  need_eq "$((n4 - n3))" 1 "journal lines added by broadcast #1 (one invocation = one line)" || return 0
  l3=$(journal_since "$fx" "$n3")

  run_brain "$fx" alpha dm @all "$b2"
  rc=$?
  need_rc "$rc" 0 "broadcast #2" || return 0
  n5=$(journal_entry_count "$fx")
  need_eq "$((n5 - n4))" 1 "journal lines added by broadcast #2" || return 0
  l4=$(journal_since "$fx" "$n4")

  s3=$(journal_shape "$l3"); s4=$(journal_shape "$l4")
  [ -n "$s3" ] || fail "instrument check: the normalised broadcast journal line is empty"
  need_eq "$s3" "$s4" "BROADCAST call-log line is not body-independent (UR-10)"

  # positive control: both bodies really were transported, so a clean journal means something
  need_tree_has "$fx/.brain/dm" "$b1" "body #1 reached the queue (positive control)"
  need_tree_has "$fx/.brain/dm" "$b2" "body #2 reached the queue (positive control)"
  need_tree_lacks "$fx/.brain/journal" "$b1" "body #1 anywhere under journal/"
  need_tree_lacks "$fx/.brain/journal" "$b2" "body #2 anywhere under journal/"
}

# V.S/9 — a secret-shaped body leaves no trace under journal/. The secret LEADS the body and
# repeats, so a prefix-truncating leak cannot hide it: any leaked fragment of >= 4 chars contains
# 'AWS_', and of >= 21 the whole key name.
sc_dm_secret_body_never_journalled() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  secret_body="AWS_SECRET_ACCESS_KEY=abc123 AWS_SECRET_ACCESS_KEY=abc123 abc123"
  pd=$(q_dir "$fx" bravo pending)
  before_entries=$(journal_entry_count "$fx")

  run_brain "$fx" alpha dm @bravo "$secret_body"
  rc=$?
  need_rc "$rc" 0 "brain dm @bravo (secret probe)" || return 0

  # positive controls: the probe really was transported AND the send really journalled, so a
  # clean grep is a result rather than an absence of anything to find.
  need_count "$pd" 1 "bravo pending/ after the secret probe" || return 0
  need_tree_has "$pd" "abc123" "probe string reached the queue (positive control)" || return 0
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 1 \
    "journal entry lines added by the secret-probe send (positive control)" || return 0

  need_tree_lacks "$fx/.brain/journal" "abc123" "secret value under journal/"
  need_tree_lacks "$fx/.brain/journal" "AWS_SECRET_ACCESS_KEY" "secret key name under journal/"
  need_tree_lacks "$fx/.brain/journal" "AWS_" "any leading fragment of the secret under journal/"
}

# V.S/10 — @all lands in every registered lane's pending/ and never the sender's; one invocation
# still writes ONE journal line. The fan-out is NOT gated on who looks live.
sc_dm_all_broadcasts_not_to_self() {
  fx=$(make_vault alpha bravo charlie delta) || fatal "fixture build failed"
  body="resync-before-your-gates-9c1"
  write_presence "$fx" charlie active "" "2026-06-01T00:00:00Z" \
    || fatal "fixture: could not write the stale lane"
  write_presence "$fx" delta "done" || fatal "fixture: could not write the done lane"
  before_entries=$(journal_entry_count "$fx")

  run_brain "$fx" alpha dm @all "$body"
  rc=$?
  need_rc "$rc" 0 "brain dm @all" || return 0

  for lane in bravo charlie delta; do
    case "$lane" in
      charlie) why="$lane (STALE updated: — must NOT be skipped)" ;;
      delta)   why="$lane (status: done — must NOT be skipped)" ;;
      *)       why="$lane" ;;
    esac
    pd=$(q_dir "$fx" "$lane" pending)
    need_count "$pd" 1 "$why pending/ after broadcast" || continue
    f=$(first_file "$pd")
    if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
      fail "$lane broadcast file is not a JSON object: $(head -c 120 "$f")"
      continue
    fi
    need_eq "$(jq -r '.from    // ""' "$f")" "alpha" "$why broadcast .from"
    need_eq "$(jq -r '.to      // ""' "$f")" "$lane" "$why broadcast .to"
    need_eq "$(jq -r '.content // ""' "$f")" "$body" "$why broadcast .content"
  done

  need_count "$(q_dir "$fx" alpha pending)" 0 "the sender's OWN pending/ after a broadcast"
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 1 \
    "journal entry lines added by one broadcast (ONE invocation = ONE line)"
}

# V.S/11 — an unknown recipient fails cleanly: no lane tree, no journal line, and no temp residue
# anywhere (a half-written .tmp-* would be the atomic-placement helper leaking).
# Verified discriminating against a mutant that journals a rejected send.
sc_dm_unknown_recipient_fails_clean() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha dm @bravo "probe-known-recipient"
  rc=$?
  need_rc "$rc" 0 "prerequisite: dm to a known recipient" || return 0

  before_entries=$(journal_entry_count "$fx")
  run_brain "$fx" alpha dm @nope "x"
  rc=$?
  need_rc_nonzero "$rc" "brain dm @nope"
  [ -s "$ERR" ] || fail "brain dm @nope wrote nothing to stderr"
  need_file_has "$ERR" "nope" "error message must name the unknown recipient"
  need_dir_absent "$fx/.brain/dm/nope" "unknown recipient lane directory"
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 0 \
    "journal entry lines added by a REJECTED send"
  need_eq "$(count_dotfiles "$(q_dir "$fx" bravo pending)")" 0 \
    "temp residue in a bystander lane's pending/ after a rejected send"
}

# V.S/12 — a self-send is refused, writes nothing, journals nothing, leaves no temp.
# Verified discriminating against a mutant that journals a rejected send.
sc_dm_self_send_refused() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  body="self-send-body-4b2"

  run_brain "$fx" alpha dm @bravo "probe-known-recipient"
  rc=$?
  need_rc "$rc" 0 "prerequisite: dm to a known recipient" || return 0

  pd_self=$(q_dir "$fx" alpha pending)
  before_self=$(count_files "$pd_self")
  before_entries=$(journal_entry_count "$fx")

  run_brain "$fx" alpha dm @alpha "$body"
  rc=$?
  need_rc_nonzero "$rc" "brain dm @alpha (self-send)"
  [ -s "$ERR" ] || fail "self-send wrote nothing to stderr"
  need_eq "$(count_files "$pd_self")" "$before_self" "the sender's own pending/ count after a self-send"
  if [ -d "$pd_self" ]; then
    need_tree_lacks "$pd_self" "$body" "the sender's own pending/"
    need_eq "$(count_dotfiles "$pd_self")" 0 "temp residue after a refused self-send"
  fi
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 0 \
    "journal entry lines added by a REFUSED self-send"
}

# V.S/13 — must-survive #6 (dm/ gitignore self-heal). The `dm/` ignore rule is PREFIX-scoped, so
# every state directory is covered; this guard is what would catch a regression that narrowed the
# rule to one path. Verified discriminating against a mutant whose fresh init omits the dm/ rule.
sc_init_gitignores_dm_queue() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  # positive control on the instrument: check-ignore must NOT match a tracked vault path
  if git -C "$fx" check-ignore -q .brain/presence/alpha.md 2>/dev/null; then
    fail "instrument broken: git check-ignore matches .brain/presence/alpha.md"
    return 0
  fi
  for p in .brain/dm/bravo/pending/20260101T000000Z-1 \
           .brain/dm/bravo/read/20260101T000000Z-1 \
           .brain/dm/bravo/failed/20260101T000000Z-1; do
    git -C "$fx" check-ignore -q "$p" 2>/dev/null \
      || fail "a fresh init does not gitignore $p (git check-ignore did not match)"
  done
}

# V.S/14 — a real send leaves nothing in `git status`.
sc_queue_files_stay_out_of_git_status() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  git -C "$fx" add -A >/dev/null 2>&1 || { fail "fixture: git add failed"; return 0; }
  git -C "$fx" commit -q -m "vault baseline" >/dev/null 2>&1 \
    || { fail "fixture: baseline vault commit failed"; return 0; }

  # positive control: git status is not blind to untracked files in this fixture
  printf 'probe\n' > "$fx/probe-untracked.txt"
  st=$(git -C "$fx" status --porcelain 2>/dev/null)
  need_str_has "$st" "probe-untracked.txt" "instrument check: git status sees untracked files" || return 0

  run_brain "$fx" alpha dm @bravo "gitignore-probe-1a"
  rc=$?
  need_rc "$rc" 0 "brain dm @bravo" || return 0
  need_count "$(q_dir "$fx" bravo pending)" 1 "the send actually wrote under .brain/dm/" || return 0

  st=$(git -C "$fx" status --porcelain 2>/dev/null)
  need_str_lacks "$st" ".brain/dm" "git status after a send"
}

# V.S/15 — structural witness: the queue path takes NO lock, under ANY name. Seam altitude
# decision: "No lock anywhere on the queue path"; v1.2 removes machinery, never adds a lock.
#   INSTRUMENT making .brain/.locks read-only is NAME-agnostic: _lock_acquire creates
#              $BRAIN/.locks/<k>.lock whatever <k> is, so any lock protocol fails here while a
#              lock-free send is unaffected. A stale per-lane dm/<to>/.lock is pre-created too,
#              since a bespoke lock need not live under .brain/.locks at all.
#   POSITIVE   the same send must SUCCEED — this is not "everything is broken" passing as
#   CONTROL    "no lock", and the elapsed-time bound catches a lock that spins then gives up.
sc_dm_takes_no_lock() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  locks="$fx/.brain/.locks"
  mkdir -p "$fx/.brain/dm/bravo/.lock" \
    || { fail "fixture: could not pre-create dm/bravo/.lock"; return 0; }

  make_readonly_dir "$locks"
  mrc=$?
  case "$mrc" in
    0) ;;
    2) fail "instrument blind: a lock dir is still creatable under a read-only .locks (running as root?)"; return 0 ;;
    *) fail "fixture: could not make .brain/.locks read-only (rc=$mrc)"; return 0 ;;
  esac

  # ALL THREE queue paths must be lock-free, not just the send.
  run_brain "$fx" alpha dm @bravo "no-lock-probe-3c"
  rc=$?
  # Sample the post-SEND queue state HERE: the take below empties pending/, so asserting it
  # afterwards would make this unsatisfiable. Captured into variables rather than asserted
  # inline, because an early return would skip the chmod restore below. [R2-1]
  pend_after_send=$(count_files "$(q_dir "$fx" bravo pending)")
  pend_has_body=no
  grep -rqF -- "no-lock-probe-3c" "$(q_dir "$fx" bravo pending)" 2>/dev/null && pend_has_body=yes
  run_brain "$fx" bravo dm take
  trc=$?
  run_brain "$fx" bravo hook session-start
  hrc=$?
  chmod 755 "$locks" 2>/dev/null || true       # restore BEFORE any early return

  need_rc "$rc" 0 "brain dm with .brain/.locks read-only and a stale dm/bravo/.lock (the SEND path takes no lock)" || return 0
  need_rc "$trc" 0 "brain dm take under a read-only .brain/.locks (the CONSUME path takes no lock)"
  need_rc "$hrc" 0 "hook session-start under a read-only .brain/.locks (the BOOT path takes no lock)"
  # NB a wall-clock limb ("<= 4s, since one _lock_acquire spin costs ~5s") was DELETED here on the
  # watchdog's recommendation: it was a timing heuristic on a loaded machine, and the structural
  # witness above already rejects every lock protocol by making the lock DIRECTORY unwritable.
  # A lock that spins and gives up still fails the read-only .locks gate, so the timer bought
  # nothing but flake surface. [L7]
  need_eq "$pend_after_send" 1 "message files in pending/ immediately after the lock-free send"
  need_eq "$pend_has_body" yes "the sent body reached pending/ (positive control)"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the take (the consume path completed without a lock)"
  need_tree_has "$(q_dir "$fx" bravo read)" "no-lock-probe-3c" "the archived transcript carries the delivered content"
}

# V.S/16 — seam decision 2 (UNCHANGED): the send temp is a DOT-file inside pending/, so `sh` globs
# skip it and "a torn temp is invisible to every reader with zero code". A temp must therefore
# never be counted as a message, never be emitted, and never be consumed.
#   NOT ASSERTED: the 300s stale-temp PURGE. It was specified inside seam decision 6, which v1.2
#   supersedes, and its only caller was the deleted `_dm_recover_stale`. Unresolved, non-blocking
#   — see [F14] in the header.
sc_dot_temp_invisible_to_readers() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  run_brain "$fx" alpha dm @bravo "real-message-2p6"
  rc=$?
  need_rc "$rc" 0 "prerequisite: a real send" || return 0

  printf '{"from":"alpha","to":"bravo","ts":"x","content":"torn-temp-must-not-deliver"}\n' \
    > "$pd/.tmp-inflight-9x1" || { fail "fixture: could not plant the in-flight temp"; return 0; }

  need_count "$pd" 1 "a reader glob must see ONE message and never the dot-temp" || return 0
  need_eq "$(count_dotfiles "$pd")" 1 "instrument check: the planted temp really is there" || return 0

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take alongside an in-flight temp" || return 0
  need_file_has "$OUT" "real-message-2p6" "the real message must be delivered (positive control)"
  need_file_lacks "$OUT" "torn-temp-must-not-deliver" \
    "a dot-prefixed in-flight temp must NEVER be emitted as a message (seam decision 2)"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the take — only the real message is archived"
  need_tree_lacks "$(q_dir "$fx" bravo read)" "torn-temp-must-not-deliver" \
    "an in-flight temp must never be promoted into the archive"
}

# ══════════════════════════ V.C — consume: take + boot (all guards) ══════════════════════
# The "keep" half of the map's Suite-consequences list: offline delivery, no replay after a
# successful ack, arming, path robustness, absolute-engine deployment resolution. Nothing here
# asserts anything about `claimed/` — the deleted state is V.N/46's business.

# V.C/17 — `brain dm take` emits every queued message and archives it into read/.
#   PROVES     every delivered message reaches the archive carrying its ORIGINAL id, and a second
#              take consumes nothing (no replay after a SUCCESSFUL archive).
#   REJECTS    a take that prints without archiving (pending/ would still hold the files), one
#              that archives without printing, and one that re-consumes an archived message.
sc_take_emits_and_archives() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "take-one-8a2"
  rc=$?
  need_rc "$rc" 0 "prerequisite: first send" || return 0
  run_brain "$fx" alpha dm @bravo "take-two-9b3"
  rc=$?
  need_rc "$rc" 0 "prerequisite: second send" || return 0
  need_count "$pd" 2 "prerequisite: both messages queued" || return 0
  id1=$(id_of_body "$pd" "take-one-8a2") || { fail "no queued file carries body #1 — the send did not land as a per-message file in pending/"; return 0; }
  id2=$(id_of_body "$pd" "take-two-9b3") || { fail "no queued file carries body #2 — the send did not land as a per-message file in pending/"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take" || return 0
  need_file_has "$OUT" "take-one-8a2" "take must print the first message"
  need_file_has "$OUT" "take-two-9b3" "take must print the second message"

  need_count "$pd" 0 "pending/ after take (a successfully emitted message leaves it)"
  need_count "$rd" 2 "read/ after take"
  need_dir_has_id "$rd" "$id1" "the archive must preserve message id #1"
  need_dir_has_id "$rd" "$id2" "the archive must preserve message id #2"

  # sequential no-double-consume: a second take sees nothing and changes nothing.
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "second brain dm take (empty queue)"
  need_eq "$(line_count "$OUT")" 0 "stdout lines from a take on an empty queue"
  need_count "$rd" 2 "read/ after the second take (nothing re-consumed, nothing duplicated)"
}

# V.C/18 — UR-3. A live-observed message must really be consumed, not merely seen: after
# `dm take`, the next SessionStart must not replay it.
#   NEGATIVE   a message sent AFTER the take must still be reported at that same boot —
#   CONTROL    otherwise "boot did not replay" would be satisfied by a boot that reports nothing.
sc_take_then_boot_no_replay() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha dm @bravo "live-read-a7k"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send before the live read" || return 0

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take (the live read)" || return 0
  need_file_has "$OUT" "live-read-a7k" "take must actually deliver the message (positive control)" || return 0
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the live read (the message was archived)" || return 0

  run_brain "$fx" alpha dm @bravo "after-take-b8m"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send AFTER the live read" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "hook session-start as bravo" || return 0
  need_str_has  "$ctx" "after-take-b8m" "the boot must still deliver a message sent after the take (negative control)"
  need_str_lacks "$ctx" "live-read-a7k"  "a message already consumed by 'dm take' must NOT be replayed at the next boot (UR-3)"
}

# V.C/19 — an empty queue is a silent success. A watcher runs this on every inbox flutter, so
# noise or a non-zero exit is a defect.
sc_take_empty_is_silent_zero() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take on an empty queue" || return 0
  need_eq "$(line_count "$OUT")" 0 "stdout lines from an empty take"
  need_eq "$(byte_size "$OUT")" 0 "stdout bytes from an empty take"
}

# V.C/20 — offline delivery. THREE queued messages from TWO senders: a dormant lane wakes to a
# QUEUE, so one-message coverage would let a `tail -1`-shaped delivery pass while dropping
# everything older.
#   PROVES     per-message archiving (read/ holds three separate entries carrying the original
#              ids), sender attribution survives delivery, and — the structural half — that the
#              BATCH ROTATION IS GONE: no `<ts>-<pid>.jsonl` archive and no inbox.jsonl.
sc_boot_delivers_offline_backlog() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  q1="q1a4"; q2="q2b5"; q3="q3c6"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)
  # charlie sends while status: done — cmd_dm only requires the presence note to exist. Being
  # done keeps charlie out of cmd_status's active list, so its name cannot reach the injected
  # context that way.
  write_presence "$fx" charlie "done" || fatal "fixture: could not set charlie done"

  run_brain "$fx" alpha   dm @bravo "queued-$q1"; rc=$?
  need_rc "$rc" 0 "prerequisite: first dm to the (not running) lane" || return 0
  run_brain "$fx" charlie dm @bravo "queued-$q2"; rc=$?
  need_rc "$rc" 0 "prerequisite: second dm (different sender)" || return 0
  run_brain "$fx" alpha   dm @bravo "queued-$q3"; rc=$?
  need_rc "$rc" 0 "prerequisite: third dm" || return 0
  need_count "$pd" 3 "prerequisite: all three messages queued" || return 0
  id1=$(id_of_body "$pd" "queued-$q1") || { fail "no queued file carries $q1"; return 0; }
  id2=$(id_of_body "$pd" "queued-$q2") || { fail "no queued file carries $q2"; return 0; }
  id3=$(id_of_body "$pd" "queued-$q3") || { fail "no queued file carries $q3"; return 0; }

  # Close the OTHER path by which a sender's name reaches the context: cmd_status echoes recent
  # journal lines mentioning this lane, and the call-log line names the sender. Stripping
  # journal ENTRY lines leaves the delivered message as the only possible source.
  for jf in "$fx"/.brain/journal/*.md; do
    [ -e "$jf" ] || continue
    grep -v '^- ' "$jf" > "$jf.tmp"
    mv "$jf.tmp" "$jf"
  done
  need_tree_lacks "$fx/.brain/journal" "charlie" "instrument check: no journal line still names the sender" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "brain hook session-start as bravo (JSON with additionalContext)" || return 0

  need_str_has "$ctx" "$q1" "startup context must report the OLDEST queued message"
  need_str_has "$ctx" "$q2" "startup context must report the middle queued message"
  need_str_has "$ctx" "$q3" "startup context must report the newest queued message"
  # ATTRIBUTION: who sent it must survive delivery. A queue of contradictory instructions with
  # no sender is unactionable. The NAME is the contract; any rendering carrying it satisfies it.
  need_str_has "$ctx" "charlie" "startup context must identify the SENDER of a delivered message"

  need_count "$pd" 0 "pending/ after a delivered boot"
  need_count "$rd" 3 "read/ after a delivered boot — one entry per message, not one blob"
  need_dir_has_id "$rd" "$id1" "archive preserves id #1"
  need_dir_has_id "$rd" "$id2" "archive preserves id #2"
  need_dir_has_id "$rd" "$id3" "archive preserves id #3"

  # the deleted-not-extended half: _inbox_rotate and its <ts>-<pid>.jsonl archive naming die.
  for f in "$rd"/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
      *.jsonl) fail "read/ holds a batch archive '${f##*/}' — the batch-rotation naming is DELETED, not extended" ;;
    esac
  done
  need_file_absent "$fx/.brain/dm/bravo/inbox.jsonl" "the retired single-shared inbox file"
}

# V.C/21 — no replay across boots. TWO messages across THREE boots: one message's lifecycle is
# not enough, because "deliver only if read/ does not already exist" delivers correctly exactly
# once per lane FOREVER and would satisfy a single-message test.
#   ALSO       an empty-queue boot must not destroy an existing archive (the v1.0 unconditional
#              rotation did exactly that).
sc_boot_no_replay_across_boots() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  m1="m1x7"; m2="m2y9"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "$m1-$m1-$m1"; rc=$?
  need_rc "$rc" 0 "prerequisite: first dm to bravo" || return 0
  id1=$(id_of_body "$pd" "$m1") || { fail "no queued file carries $m1"; return 0; }

  ctx1=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot 1" || return 0
  need_str_has "$ctx1" "$m1" "boot 1 must report the first message" || return 0
  need_dir_has_id "$rd" "$id1" "boot 1 must archive the first message into read/" || return 0

  ctx2=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot 2" || return 0
  need_str_lacks "$ctx2" "$m1" "boot 2 must NOT re-report the first message"
  need_dir_has_id "$rd" "$id1" "an empty-queue boot destroyed the archived first message"

  run_brain "$fx" alpha dm @bravo "$m2-$m2-$m2"; rc=$?
  need_rc "$rc" 0 "prerequisite: second dm (after a delivery already happened)" || return 0
  id2=$(id_of_body "$pd" "$m2") || { fail "no queued file carries $m2"; return 0; }

  ctx3=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot 3" || return 0
  need_str_has  "$ctx3" "$m2" "boot 3 must report the SECOND message (delivery is per-message, not per-lane)"
  need_str_lacks "$ctx3" "$m1" "boot 3 must still NOT re-report the first message"

  need_count "$pd" 0 "pending/ after the final boot"
  need_dir_has_id "$rd" "$id1" "the first message must remain retrievable after boot 3"
  need_dir_has_id "$rd" "$id2" "the second message must be retrievable after boot 3"
  need_count "$rd" 2 "read/ after three boots (2 deliveries, 1 empty-queue no-op)"
}

# V.C/22 — every boot arms the lane on the pending/ directory and names the consume command,
# whether or not mail arrived. The retired inbox.jsonl watch target must be gone from the
# context, or lanes keep arming a file that no longer exists.
sc_boot_arms_pending_and_take() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  ctx=$(hook_context "$fx" bravo)   # no pending DM — arming happens on EVERY boot
  hrc=$?
  need_rc "$hrc" 0 "brain hook session-start as bravo" || return 0

  need_str_has "$ctx" "navigation-standards" "the existing protocol nudge must survive"
  need_str_has "$ctx" "dm/bravo/pending" "startup context must carry this lane's concrete pending/ path to arm on"
  need_str_has "$ctx" "dm take" "startup context must name the command that CONSUMES a live-observed message (UR-3)"
  need_str_lacks "$ctx" "inbox.jsonl" "startup context must stop pointing lanes at the retired shared inbox file"
}

# V.C/23 — message identifiers must survive a vault path containing whitespace. Drives the
# complete public lifecycle: send → SessionStart delivery → archive.
sc_space_path_round_trip() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  spaced="$base/repo with space"
  mv "$fx" "$spaced" || { fail "fixture: could not move the vault under a spaced path"; return 0; }
  fx=$spaced

  run_brain "$fx" alpha dm @bravo "space-path-round-trip-h1"
  rc=$?
  need_rc "$rc" 0 "send from a vault path containing a space" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "SessionStart from a vault path containing a space" || return 0
  need_str_has "$ctx" "space-path-round-trip-h1" \
    "the real boot must deliver a DM when the vault path contains a space"
  need_count "$(q_dir "$fx" bravo pending)" 0 "pending/ after the spaced-path boot"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the spaced-path delivery"
}

# V.C/24 — must-survive #7 (absolute engine resolution). Deployment is one main-worktree engine,
# even when the receiving lane is a sibling whose tracked .brain/bin/brain predates `dm take`.
# This reproduces the live failure shape: SessionStart resolves the shared vault correctly, then
# its emitted command is executed from the stale sibling. Only an absolute main-engine
# instruction can consume the queued marker.
sc_deploy_instruction_uses_main_worktree_engine() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx"); sibling="$base/sibling-worktree"

  cp "$BRAIN_BIN" "$fx/.brain/bin/brain" \
    || { fail "fixture: could not deploy the new engine into the main worktree"; return 0; }
  chmod +x "$fx/.brain/bin/brain" \
    || { fail "fixture: could not make the deployed main engine executable"; return 0; }
  git -C "$fx" add -f -- .brain/bin/brain >/dev/null 2>&1 \
    || { fail "fixture: could not stage the tracked engine"; return 0; }
  git -C "$fx" commit -q -m "fixture tracked engine" >/dev/null 2>&1 \
    || { fail "fixture: could not commit the tracked engine"; return 0; }
  git -C "$fx" worktree add -q -b stale-engine-lane "$sibling" HEAD >/dev/null 2>&1 \
    || { fail "fixture: could not create the sibling worktree"; return 0; }

  {
    printf '#!/bin/sh\n'
    printf 'printf "OLD SIBLING ENGINE: dm take unavailable\\n" >&2\n'
    printf 'exit 64\n'
  } > "$sibling/.brain/bin/brain"
  chmod +x "$sibling/.brain/bin/brain" \
    || { fail "fixture: could not install the old sibling engine stub"; return 0; }

  ctx=$(hook_context "$sibling" bravo)
  hrc=$?
  need_rc "$hrc" 0 "SessionStart from the sibling carrying an old tracked engine" || return 0

  # ⚠ THE PROSE IS NOT PINNED — dispatcher ruling, 2026-08-04. The v1.1 engine emits
  # "On activity, claim and consume it with: <cmd>", and an honest v1.2 GREEN drops the word
  # "claim" with the layer it names. GREEN may not touch this frozen suite, so a guard matching
  # that sentence would wedge the arc. Exactly three things are pinned, all load-bearing:
  #   (a) the instruction names the MAIN worktree's ABSOLUTE engine — never the sibling's tracked
  #       copy and never a relative `.brain/bin/brain` (must-survive #7);
  #   (b) the command NAME is `dm take` — ruled v1.2 contract; it survives with no-claim semantics;
  #   (c) the line is an INSTRUCTION to act on activity, not a bare path with no directive.
  # The command is extracted by stripping any leading prose up to the first quote or absolute
  # path, so ANY sentence wrapping the command works. If a future wording puts a '/' inside the
  # prose itself, the extraction breaks LOUDLY (the command below will not execute), never silently.
  instr_line=$(printf '%s\n' "$ctx" | grep -F -- 'dm take' | grep -F -- "$fx/.brain/bin/brain" | head -1)
  [ -n "$instr_line" ] \
    || { fail "Part 1: SessionStart emitted no line carrying BOTH the 'dm take' command name and the main worktree's absolute engine path ($fx/.brain/bin/brain)"; return 0; }
  need_str_lacks "$instr_line" "$sibling/.brain/bin/brain" \
    "Part 1: the consume instruction must never name the sibling's tracked engine"
  printf '%s' "$instr_line" | grep -qiE 'consume|run|execute|invoke' \
    || fail "Part 1: the emitted line carries a command but no directive verb — a lane watching its pending/ dir is told a path, not an action to take on activity"
  instruction=$(printf '%s' "$instr_line" | sed -n 's|^[^"/]*\(["/].*\)$|\1|p')
  [ -n "$instruction" ] \
    || { fail "Part 1: could not extract an executable command from the emitted line: $instr_line"; return 0; }
  need_str_has "$instruction" "$fx/.brain/bin/brain" \
    "Part 1: the extracted command must name the main worktree's deployed engine" || return 0

  run_brain "$fx" alpha dm @bravo "main-engine-deploy-p1"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue a message after the sibling was armed" || return 0

  OUT="$base/instructed-take.out"; ERR="$base/instructed-take.err"
  (
    cd "$sibling" || exit 127
    exec env HOME="$base/home" BRAIN_FEATURE=bravo BRAIN_TEST_BRANCH="$FIXTURE_BRANCH" \
      BRAIN_MAIN_REF="$FIXTURE_MAIN_REF" BRAIN_SKILLS_DIR="$base/home/.claude/skills" \
      BRAIN_GLOBAL_SETTINGS="$base/home/.claude/settings.json" BRAIN_PRETOOL_MODE=allow \
      sh -c "$instruction"
  ) > "$OUT" 2> "$ERR"
  rc=$?
  need_rc "$rc" 0 "the SessionStart consume instruction executed from the stale sibling" || return 0
  need_file_has "$OUT" "main-engine-deploy-p1" \
    "the emitted instruction must execute the new main engine and deliver the queued message"
  need_file_lacks "$ERR" "OLD SIBLING ENGINE" \
    "the stale sibling engine must never execute"

  need_file_has "$NAV_SKILL" "absolute engine path printed in SessionStart" \
    "the always-read navigation template must direct lanes to the emitted absolute engine"
  need_file_has "$DM_PROTOCOL" "absolute engine path printed in SessionStart" \
    "the DM protocol must direct lanes to the emitted absolute engine"
}

# ══════════════════════ V.W — wire contract + bounds at the consumer (guards) ═════════════
# Must-survive #6: "exactly one JSON object per file, four bounded fields, byte-based
# (utf8bytelength) line and aggregate caps". Every fixture here gets its filename from a real
# send (plant_message) and only its BYTES are overwritten, so nothing depends on the queue
# filename grammar v1.2 changes.
#
# ⚠ RENDERING IS NOT PINNED. The v1.1 suite asserted `keys == ["content","from","to","ts"]` on
# the emitted record. Must-survive #8 requires the message ID to be EXPOSED in the digest, and
# the map does not say how — an `id` key is the obvious rendering, and an exact-keys equality
# would forbid it. These guards therefore assert the four contract values and the byte caps and
# say nothing about extra structure. See the hand-off report: authority/authority tension,
# resolved by NARROWING an assertion the map never mandated rather than by adding apparatus.

# V.W/25 — a file is the consumer-boundary unit. Multiple JSON values in one file are malformed:
# nothing may be emitted from it, it must never reach the archive, and it must not be destroyed.
#   (WHERE it goes is v1.2's change — V.N/49 pins quarantine. This guard pins only that the
#   malformed file is refused, silent, and not lost, all of which hold today.)
sc_multi_object_file_refused() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  rd=$(q_dir "$fx" bravo read)

  planted=$(plant_message "$fx" bravo "multi-object-seed-h2") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"multi-first-h2"}' > "$planted" \
    || { fail "fixture: could not write the first planted object"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:01Z",content:"multi-second-h2"}' >> "$planted" \
    || { fail "fixture: could not write the second planted object"; return 0; }

  run_brain "$fx" bravo dm take
  # ⚠ NARROWED from the v1.1 suite, deliberately. F.H2/43 asserted `exit non-zero` here. The
  # v1.2 ruling is SILENT on the exit status of a consume that quarantined one file and
  # delivered its peers, and V.N/49 requires exactly that outcome to be normal — so a non-zero
  # requirement would reject a permitted implementation. The anti-silence property is what
  # matters, and it is asserted directly instead: the engine must SAY something. Its own
  # diagnostics are prefixed "brain: " (_warn/_die), so a bare jq/mv error on stderr is a leak,
  # not a report, and does not satisfy this.
  if [ -s "$ERR" ]; then
    need_file_has "$ERR" "brain:" "a refused multi-object file must be reported BY THE ENGINE (stderr carried output, but no 'brain: ' diagnostic — an unsuppressed tool error is a leak, not a report)"
  else
    fail "a file refused at the consumer boundary must be reported, never silently swallowed (stderr was empty)"
  fi
  need_file_lacks "$OUT" "multi-first-h2" "a multi-object file must emit NOTHING (first object)"
  need_file_lacks "$OUT" "multi-second-h2" "a multi-object file must emit NOTHING (second object)"
  need_count "$rd" 0 "read/ after a malformed multi-object file — it must never be archived"
  need_not_lost "$fx" bravo "multi-first-h2" "the refused multi-object file"
}

# V.W/26 — unknown fields are not part of the wire contract and must not cross the consumer
# boundary. The contract values survive; the planted field does not.
sc_extra_field_stripped() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  planted=$(plant_message "$fx" bravo "extra-field-seed-h2") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"extra-field-h2",extra:"must-not-cross"}' \
    > "$planted" || { fail "fixture: could not write the extra-field message"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take of a valid message carrying an unknown field" || return 0
  need_file_has "$OUT" "extra-field-h2" "the sanitized message content"
  need_file_has "$OUT" "alpha" "the .from contract field must survive sanitisation"
  need_file_lacks "$OUT" "must-not-cross" "the planted unknown field must not cross the consumer boundary"
  # STRUCTURAL half: a literal-fragment check alone would accept a record that dropped `ts`, or
  # emitted prose, or carried the unknown field under a renamed key. This is where the rebuilt
  # record's shape is actually pinned.
  need_digest_records_wellformed "$OUT" "the sanitized record emitted for a message with an unknown field"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the sanitized message is delivered"
}

# V.W/27 — every contract value is bounded, not only content. An oversized producer-controlled
# `from` must be shortened before output, and the emitted line must stay within the per-line
# BYTE cap.
sc_oversized_from_bounded() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  huge_from=$(awk 'BEGIN { for (i = 0; i < 6000; i++) printf "f" }')

  planted=$(plant_message "$fx" bravo "oversized-from-seed-h2") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  jq -cn --arg f "$huge_from" \
    '{from:$f,to:"bravo",ts:"2026-08-04T12:00:00Z",content:"oversized-from-h2"}' \
    > "$planted" || { fail "fixture: could not write the oversized-from message"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take of a message carrying an oversized from value" || return 0
  need_file_has "$OUT" "oversized-from-h2" "content alongside the bounded from value"
  need_file_lacks "$OUT" "$huge_from" "the full 6,000-byte from value must never be emitted"
  need_digest_records_wellformed "$OUT" "the record emitted for a message with an oversized from value"
  widest=$(max_line_bytes "$OUT")
  [ "$widest" -le "$DM_INJECT_MAX_COLS" ] \
    || fail "the widest emitted line is $widest bytes, above the $DM_INJECT_MAX_COLS-byte per-line cap"
}

# V.W/28 — jq's `length` counts CODE POINTS. Four multibyte fields can therefore serialize above
# the 2,000-BYTE line cap even after a conservative per-field slice. The map's caps are byte caps
# (`utf8bytelength`), and `max_line_bytes` measures under LC_ALL=C so it really counts bytes.
sc_multibyte_digest_respects_byte_caps() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  multi=$(awk 'BEGIN { for (i = 0; i < 300; i++) printf "🙂" }')

  planted=$(plant_message "$fx" bravo "multibyte-seed-m1") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  jq -cn --arg v "$multi" '{from:"alpha",to:$v,ts:$v,content:$v}' \
    > "$planted" || { fail "fixture: could not write the multibyte message"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take of a multibyte boundary message" || return 0
  [ "$(byte_size "$OUT")" -gt 0 ] || fail "the multibyte message was not emitted at all"
  # The byte cap must be met by SHRINKING the fields, never by emitting a truncated/invalid record.
  need_digest_records_wellformed "$OUT" "the record emitted for a multibyte boundary message"
  widest=$(max_line_bytes "$OUT")
  [ "$widest" -le "$DM_INJECT_MAX_COLS" ] \
    || fail "the widest emitted line is $widest BYTES, above the $DM_INJECT_MAX_COLS-byte line cap — a code-point slice is not a byte cap"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the bounded multibyte delivery"
}

# V.W/29 — seam defect 5: `cut -c1-2000` truncated mid-JSON and injected a syntactically broken
# object into a session's startup context. The fix truncates the CONTENT FIELD, not the
# serialized object.
#   VACUITY    if the digest renders prose rather than serialized objects, the JSON limb is
#   NOTE       vacuously true — a PERMITTED alternative (the map does not pin the rendering) —
#              and the HEAD/TAIL bound still holds. Do not "fix" the engine to produce JSON just
#              to make this limb bite.
sc_digest_truncates_content_not_json() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pad=$(awk 'BEGIN{ s=""; for (i = 0; i < 2900; i++) s = s "x"; printf "%s", s }')
  body="HEADMARK-$pad-TAILMARK"

  run_brain "$fx" alpha dm @bravo "$body"
  rc=$?
  need_rc "$rc" 0 "brain dm with a 2.9 KB body (under DM_MAX_BODY)" || return 0
  need_count "$(q_dir "$fx" bravo pending)" 1 "the long message was queued" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot with a long message queued" || return 0

  need_str_has  "$ctx" "HEADMARK" "the long message must be delivered at all (positive control)"
  need_str_lacks "$ctx" "TAILMARK" \
    "the injected block carried the FULL 2.9 KB body — the $DM_INJECT_MAX_COLS-byte line cap is not bounding it"

  printf '%s\n' "$ctx" > "$base/ctx.txt"
  bad=0
  while IFS= read -r ln; do
    case "$ln" in
      '{'*) printf '%s\n' "$ln" | jq -e . >/dev/null 2>&1 || bad=$((bad + 1)) ;;
    esac
  done < "$base/ctx.txt"
  need_eq "$bad" 0 \
    "seam defect 5: $bad line(s) of the injected block start with '{' but are not valid JSON — truncation must bound the CONTENT FIELD, never the serialized object"
}

# V.W/30 — must-survive #3 (per-message isolation): a malformed file must never suppress a valid
# peer. The corrupted entry is whichever one the consumer reaches FIRST, so this also covers
# head-of-line blocking.
#   REJECTS    a consumer that abandons the batch on the first bad file (both peers would be
#              missing), and one that discards healthy peers alongside the poison.
#   NOT PINNED where the poison goes, nor the exit status — v1.2 moves it to failed/ (V.N/49),
#              v1.1 leaves it parked; both satisfy "not lost, not archived".
sc_malformed_peer_does_not_suppress_valid() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  for m in peer-a-h2 peer-b-h2 peer-c-h2; do
    run_brain "$fx" alpha dm @bravo "$m"
    rc=$?
    need_rc "$rc" 0 "prerequisite: send $m" || return 0
  done
  need_count "$pd" 3 "prerequisite: three peers queued" || return 0

  # corrupt whichever entry the consumer's glob reaches first — the head-of-line position
  victim=$(first_file "$pd") || { fail "pending/ is empty after three sends"; return 0; }
  lost=""
  for m in peer-a-h2 peer-b-h2 peer-c-h2; do
    grep -qF -- "$m" "$victim" 2>/dev/null && lost=$m
  done
  [ -n "$lost" ] || { fail "fixture: could not identify which peer sits at the head of the queue"; return 0; }
  printf '%s\n' '{not-valid-json-h2' > "$victim" \
    || { fail "fixture: could not corrupt the head entry"; return 0; }

  run_brain "$fx" bravo dm take

  shown=0
  for m in peer-a-h2 peer-b-h2 peer-c-h2; do
    [ "$m" = "$lost" ] && continue
    if grep -qF -- "$m" "$OUT" 2>/dev/null; then
      shown=$((shown + 1))
    else
      fail "healthy peer '$m' was suppressed by a malformed entry at the head of the queue (must-survive #3)"
    fi
  done
  need_eq "$shown" 2 "healthy peers delivered alongside a malformed head entry"
  need_count "$rd" 2 "read/ — exactly the two healthy peers are archived"
  need_tree_lacks "$rd" "not-valid-json-h2" "a malformed file must never reach the archive"
  need_not_lost "$fx" bravo "not-valid-json-h2" "the malformed entry"
}

# V.W/31 — a quarantined message is SURFACED, never silent. `failed/` is planted directly (its
# contents are forensic records, not queue entries, so no filename grammar applies).
#   CONTROL    status is sampled BEFORE and AFTER: a hardcoded banner fails the before-sample.
#   ⚠ AUTHORITY NOTE: the "surfaced in brain status, never auto-deleted" wording came from seam
#   decision 6b (the poison cap), which the v1.2 ruling supersedes. v1.2 keeps a quarantine but
#   does not restate the surfacing requirement. Retained here as a regression guard on live
#   behaviour, flagged NON-BLOCKING in the hand-off report — drop it if the dispatcher rules that
#   quarantine visibility is not part of the v1.2 contract.
sc_status_surfaces_quarantined_dms() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: brain inbox ensures the queue tree" || return 0

  run_brain "$fx" bravo status
  rc=$?
  need_rc "$rc" 0 "brain status (before any quarantine)" || return 0
  if status_has_failed "$OUT"; then
    fail "control: brain status reports a failure with an EMPTY failed/ — the surfacing is hardcoded, not derived"
    return 0
  fi

  mkdir -p "$fd" || { fail "fixture: could not create failed/"; return 0; }
  printf '%s\n' '{quarantined-forensic-record' > "$fd/quarantined-probe" \
    || { fail "fixture: could not plant the quarantined record"; return 0; }

  run_brain "$fx" bravo status
  rc=$?
  need_rc "$rc" 0 "brain status (after quarantine)" || return 0
  status_has_failed "$OUT" \
    || fail "a quarantined DM must be SURFACED in 'brain status' (never auto-deleted, never silent). NB this ignores status's echoed journal lines, so the banner must come from status's OWN rendering"
  need_file "$fd/quarantined-probe" "the quarantined record must never be auto-deleted"
}

# ══════════════════════════ V.X — symlink / path-component refusal (guards) ══════════════
#
# Must-survive #6: "path/symlink component checks". UR-2: the `dm` ROOT was never validated, and
# the boot-time rotate that ran FIRST validated nothing at all. `_dm_dir_ok` must reject a
# symlink or non-directory at EVERY level walked, on EVERY queue touch. Every target below lives
# inside the disposable scratch root; nothing points at a real path.
#
# ⚠ SCOPE HONESTY (seam Flags): POSIX sh has no openat/O_NOFOLLOW, so these scenarios pin
# COMPONENT REFUSAL, not race-freedom. The same-user TOCTOU residual is a documented limit and
# no assertion here claims otherwise.

# V.X/32 — the `dm` ROOT itself: the component the v1.0 engine never validated at all.
sc_send_refuses_symlinked_dm_root() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  ext=$(dirname "$fx")/outside-dmroot
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }
  printf 'XCANARY-dmroot\n' > "$ext/canary.txt"

  # positive control: this exact send WORKS before the root becomes a symlink
  run_brain "$fx" alpha dm @bravo "presym-probe"
  rc=$?
  need_rc "$rc" 0 "positive control: the send works before .brain/dm is a symlink" || return 0

  mv "$fx/.brain/dm" "$fx/.brain/dm.real" || { fail "fixture: could not move the real dm root"; return 0; }
  ln -s "$ext" "$fx/.brain/dm" || { fail "fixture: could not symlink the dm root"; return 0; }

  run_brain "$fx" alpha dm @bravo "postsym-XSYM1"
  rc=$?
  need_rc_nonzero "$rc" "brain dm with .brain/dm a SYMLINK (UR-2: the dm root was never validated)"
  [ -s "$ERR" ] || fail "a refused send wrote nothing to stderr"
  need_tree_lacks "$ext" "postsym-XSYM1" "message content written THROUGH the symlinked dm root"
  need_file_has "$ext/canary.txt" "XCANARY-dmroot" "external canary intact (positive control that the target is readable)"
}

# V.X/33 — the lane directory. Refusal must be SPECIFIC to the poisoned lane: a send to a
# healthy sibling in the same vault still has to work, or "refused" just means "broken".
sc_send_refuses_symlinked_lane_dir() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  ext=$(dirname "$fx")/outside-lane
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }

  mkdir -p "$fx/.brain/dm" || { fail "fixture: could not create the dm root"; return 0; }
  ln -s "$ext" "$fx/.brain/dm/bravo" || { fail "fixture: could not symlink the lane dir"; return 0; }

  run_brain "$fx" alpha dm @bravo "lanelink-XSYM2"
  rc=$?
  need_rc_nonzero "$rc" "brain dm to a lane whose directory is a SYMLINK"
  [ -s "$ERR" ] || fail "a refused send wrote nothing to stderr"
  need_tree_lacks "$ext" "lanelink-XSYM2" "message content written through the symlinked lane dir"

  # specificity: a healthy lane in the same vault is unaffected
  run_brain "$fx" alpha dm @charlie "healthy-lane-probe"
  rc=$?
  need_rc "$rc" 0 "positive control: a healthy sibling lane still receives mail" || return 0
  need_count "$(q_dir "$fx" charlie pending)" 1 "the healthy lane's pending/"
}

# V.X/34 — the pending/ STATE directory.
sc_send_refuses_symlinked_pending_dir() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  ext=$(dirname "$fx")/outside-pending
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }

  mkdir -p "$fx/.brain/dm/bravo" || { fail "fixture: could not create the lane dir"; return 0; }
  ln -s "$ext" "$fx/.brain/dm/bravo/pending" || { fail "fixture: could not symlink pending/"; return 0; }

  run_brain "$fx" alpha dm @bravo "pendinglink-XSYM3"
  rc=$?
  need_rc_nonzero "$rc" "brain dm to a lane whose pending/ is a SYMLINK"
  [ -s "$ERR" ] || fail "a refused send wrote nothing to stderr"
  need_tree_lacks "$ext" "pendinglink-XSYM3" "message content written through the symlinked pending/"

  run_brain "$fx" alpha dm @charlie "healthy-lane-probe"
  rc=$?
  need_rc "$rc" 0 "positive control: a healthy sibling lane still receives mail"
}

# V.X/35 — the read/ ARCHIVE directory, reached on the BOOT path. This is the exact gap UR-2
# names: the boot-time move ran first and validated neither source nor destination, so a
# symlinked archive could route message bodies into a tracked canonical directory.
#   PROVES     the boot path validates read/ before moving anything through it, warns, and
#              LOSES NOTHING.
sc_boot_refuses_symlinked_read_dir() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  ext=$(dirname "$fx")/outside-read
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }
  hooklog="$fx/.brain/.hook-errors.log"
  pd=$(q_dir "$fx" bravo pending)

  run_brain "$fx" alpha dm @bravo "readlink-XSYM4"; rc=$?
  need_rc "$rc" 0 "prerequisite: send with a healthy tree" || return 0
  need_count "$pd" 1 "prerequisite: message queued" || return 0

  assert_disposable "$fx"
  [ -d "$fx/.brain/dm/bravo/read" ] && rm -rf "$fx/.brain/dm/bravo/read"
  ln -s "$ext" "$fx/.brain/dm/bravo/read" || { fail "fixture: could not symlink read/"; return 0; }
  before_log=$(byte_size "$hooklog")

  hook_context "$fx" bravo >/dev/null
  hrc=$?
  need_rc "$hrc" 0 "the boot must still succeed (a hook never blocks a session)" || return 0

  need_tree_lacks "$ext" "readlink-XSYM4" \
    "UR-2: a message body was moved THROUGH a symlinked read/ — the archive destination must be validated before every move"
  [ "$(byte_size "$hooklog")" -gt "$before_log" ] \
    || fail "a refused symlinked read/ must be reported to .brain/.hook-errors.log"
  need_not_lost "$fx" bravo "readlink-XSYM4" "the message whose archive destination was refused"
}

# V.X/36 — the MESSAGE FILE. Seam `_dm_dir_ok`: "message files additionally -L-checked and
# required regular (-f)", and the iteration guard is `[ -e ] || [ -L ] || continue` precisely so
# "a broken symlink must be SEEN and refused, not silently skipped".
#   PROVES     no dereference (external content never reaches the injected context), no promotion
#              of the link into read/, and that BOTH a resolvable and a BROKEN symlink are
#              reported rather than skipped.
#   FIXTURE    these two entries are the ONLY hand-named queue files in the suite. Both names are
#              given in the v1.2 grammar (no `.a<k>`), which makes the provenance of a GREEN
#              result DIFFERENT before and after the rewrite — state it rather than paper over it:
#                · Against the v1.1 engine this scenario passes for a WEAKER reason than it
#                  claims. An earlier draft of this comment asserted that `_dm_dir_ok` refuses a
#                  non-regular entry before any name parsing, so the spelling could not matter.
#                  That is measurably FALSE here (watchdog m3): under v1.1 these names have no
#                  `.a<k>`, so the NAME-GRAMMAR check rejects them and SHADOWS the symlink gate.
#                  The entries are refused — just not by the limb this scenario is about.
#                · At GREEN the names become valid, the grammar check stops firing, and the
#                  symlink/non-regular gate is the only thing left that can refuse them. The
#                  assertions below are load-bearing from that point on.
#              Naming a v1.1-valid spelling instead would invert the problem (load-bearing now,
#              shadowed after GREEN), and the suite is frozen for GREEN — so the v1.2 spelling is
#              the right choice and this note is the honest accounting of what it costs today.
sc_boot_refuses_symlinked_message_file() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  ext=$(dirname "$fx")/outside-msg
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }
  printf '{"from":"mallory","to":"bravo","ts":"x","content":"XSYMBODY-injected"}\n' > "$ext/secret.txt"
  before_secret=$(byte_size "$ext/secret.txt")
  hooklog="$fx/.brain/.hook-errors.log"

  run_brain "$fx" alpha dm @bravo "healthy-alongside"; rc=$?
  need_rc "$rc" 0 "prerequisite: one healthy message" || return 0
  pd=$(q_dir "$fx" bravo pending)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }
  ln -s "$ext/secret.txt" "$pd/20260803T101500Z-424242" \
    || { fail "fixture: could not plant the symlinked message"; return 0; }
  ln -s "$ext/no-such-target" "$pd/20260803T101501Z-424243" \
    || { fail "fixture: could not plant the broken symlink"; return 0; }
  before_log=$(byte_size "$hooklog"); before_loglines=$(line_count "$hooklog")

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "the boot must still succeed (a hook never blocks a session)" || return 0

  need_str_lacks "$ctx" "XSYMBODY-injected" \
    "UR-2: a symlinked message file was DEREFERENCED into the startup context — arbitrary external content reached the session"
  need_dir_lacks_id "$(q_dir "$fx" bravo read)" "20260803T101500Z-424242" \
    "a symlinked message must not be promoted into read/"
  need_dir_lacks_id "$(q_dir "$fx" bravo read)" "20260803T101501Z-424243" \
    "a BROKEN symlinked message must not be promoted into read/"
  # BOTH planted entries must be reported, not just one. NAMES ARE THE PRIMARY GATE: it accepts a
  # compliant CONSOLIDATED one-line warning that names both, and rejects a two-line warning about
  # only one of them. A line-count floor does neither, so it is used ONLY as the fallback when
  # the warnings name nothing.
  # ⚠ DECLARED: in that unnamed fallback case, "one refusal that happens to span two lines" cannot
  # be distinguished from "two refusals" by any observation available here. Naming the offending
  # filename in the warning is what would close it. [F10a / R2-2]
  added=$(( $(line_count "$hooklog") - before_loglines ))
  [ "$(byte_size "$hooklog")" -gt "$before_log" ] \
    || fail "the symlinked and BROKEN-symlinked entries must be SEEN and refused, not silently skipped — .brain/.hook-errors.log did not grow"
  if grep -q '424242' "$hooklog" 2>/dev/null || grep -q '424243' "$hooklog" 2>/dev/null; then
    need_file_has "$hooklog" "424242" "the symlinked entry must be named among the refusals"
    need_file_has "$hooklog" "424243" "the BROKEN-symlinked entry must be named among the refusals"
  else
    [ "$added" -ge 2 ] \
      || fail "the refusals name neither planted entry, so only the line count can be checked here: $added line(s) added, want >= 2 (one per refused entry). Naming the offending filename in the warning would make this exact"
  fi
  need_eq "$(byte_size "$ext/secret.txt")" "$before_secret" "the external target must be untouched"
}

# ══════════════════════════ V.T — presence + templates (guards, carried) ═════════════════

# V.T/37 — a presence note with dialog_with: shows the open dialog in brain status.
# Verified discriminating against a mutant that stops rendering dialog_with (V.T/38 correctly did
# NOT flip against that same mutant — the pair is a control).
# charlie is done → cmd_status never lists it, so any mention of 'charlie' in the output can
# only come from alpha's dialog_with field.
sc_status_surfaces_open_dialog() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  write_presence "$fx" charlie "done" || fatal "fixture: could not rewrite charlie"
  write_presence "$fx" alpha active charlie || fatal "fixture: could not rewrite alpha"

  run_brain "$fx" alpha status
  rc=$?
  need_rc "$rc" 0 "brain status" || return 0

  out=$(cat "$OUT")
  need_str_has "$out" "charlie" "status must surface the dialog partner"
  if ! printf '%s' "$out" | grep -qi 'dialog'; then
    fail "status output never says 'dialog' — the open dialog is not surfaced as one"
  fi
}

# V.T/38 — a note WITHOUT dialog_with renders unchanged (the field is genuinely optional).
sc_status_unchanged_without_dialog() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  write_presence "$fx" charlie "done" || fatal "fixture: could not rewrite charlie"

  run_brain "$fx" alpha status
  rc=$?
  need_rc "$rc" 0 "brain status" || return 0

  out=$(cat "$OUT")
  need_str_has "$out" "alpha" "active lanes still listed"
  need_str_has "$out" "bravo" "active lanes still listed"
  need_str_lacks "$out" "charlie" "a done lane must stay unlisted"
  if printf '%s' "$out" | grep -qi 'dialog'; then
    fail "status invented dialog output for a vault with no dialog_with field"
  fi
}

# V.T/39 — reconcile does not flag dialog_with as stealth-structural.
sc_reconcile_accepts_dialog_field() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  write_presence "$fx" alpha active charlie || fatal "fixture: could not rewrite alpha"
  need_file_has "$fx/.brain/presence/alpha.md" "dialog_with: charlie" "fixture carries the field" || return 0

  run_brain "$fx" alpha reconcile --check
  rc=$?
  need_rc "$rc" 0 "brain reconcile --check with dialog_with present" || return 0
  need_file_lacks "$ERR" "stealth" "reconcile warnings"
  need_file_lacks "$ERR" "invalid" "reconcile warnings"
}

nav_matches() { grep -qiE -- "$1" "$NAV_SKILL" 2>/dev/null; }

# Same, but newline-flattened so a match may span a wrapped sentence. Callers MUST bound the
# gap (.{0,N}) — an unbounded .* over the flattened file degenerates into "both words appear
# somewhere", which the pre-rewrite template already satisfies.
nav_matches_near() { tr '\n' ' ' < "$NAV_SKILL" 2>/dev/null | grep -qiE -- "$1"; }
file_matches_near() { tr '\n' ' ' < "$1" 2>/dev/null | grep -qiE -- "$2"; }

# V.T/40 — the always-read skill must teach the mechanic lanes actually operate.
#   ⚠ the negative limb targets the v1.0 sentence ("watch it for new JSON lines"). It is a
#   WORDING check, not a contract: if a rewritten instruction legitimately trips it, challenge
#   this assertion rather than contorting the template.
sc_nav_skill_names_the_take_mechanic() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  nav_matches 'brain dm|dm @' || fail "the always-read skill never mentions 'brain dm' — the fast tier is untaught"
  nav_matches 'dm take' \
    || fail "the always-read skill never mentions 'brain dm take' — lanes cannot consume a live-observed message, so UR-3 reopens at the protocol layer"
  nav_matches 'pending' \
    || fail "the always-read skill never mentions the pending/ queue — lanes have nothing concrete to arm on"
  if nav_matches_near 'watch.{0,60}(new JSON|JSON line|jsonl)'; then
    fail "the always-read skill still tells lanes to watch the inbox FILE for JSON lines — that storage contract is deleted (cmd_inbox prints the pending/ dir; activity means 'run brain dm take')"
  fi
}

# V.T/41 — a fresh reader can state the three tiers and which one is the record.
sc_nav_skill_states_tiers_and_record() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  nav_matches 'brain dm|dm @|inbox' || fail "tier 1 (fast: dm → queue) is not named in the always-read skill"
  nav_matches 'announce' || fail "tier 2 (everyone-eventually: announce → journal) is not named"
  nav_matches 'connection' || fail "tier 3 (permanent: connections/ note) is not named"
  # PHRASE-anchored, not proximity. A proximity check is demonstrably hollow here: the template
  # ALSO contains "record it in the waiting-on connection note" and "a connections note recording
  # what was contested", so 'connection' and 'record' sit within 10 characters of each other even
  # when the load-bearing sentence has been gutted — measured against a mutant that rewrote
  # "record is a connection note" to "home is a connection note", which every window from 80 down
  # to 10 chars, and a same-physical-line variant, all failed to catch. [F2]
  # Accepted phrasings (case-insensitive, wrap-tolerant): "[the] record is a|the connection[s]
  # note" · "connection[s] note is a|the [durable] record". Widen this alternation if you reword
  # it — do NOT loosen it back into a proximity match.
  nav_matches_near '(the[[:space:]]+)?record[[:space:]]+is[[:space:]]+(a|the)[[:space:]]+connections?[[:space:]]+note|connections?[[:space:]]+note[[:space:]]+is[[:space:]]+(a|the)[[:space:]]+(durable[[:space:]]+)?record' \
    || fail "nothing STATES that the connection note is the record — a reader cannot tell which tier is durable. Accepted phrasings: '[the] record is a|the connection[s] note' or 'connection[s] note is a|the [durable] record'. Merely mentioning both words near each other does NOT satisfy this (the template already does that twice while saying something else entirely)"
}

# V.T/42 — triage rules an agent must ACT on live in the always-read part.
sc_nav_skill_carries_triage_rules() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  # word-boundary the short form: a bare 'ack' substring also matches "track", so an
  # unrelated "keep track of what lands" would green this gate with the ack rule missing
  nav_matches '\back\b|acknowledg' || fail "the 'ack everything even when deferring' rule is absent"
  nav_matches 'defer' || fail "the write-it-down-when-you-defer rule is absent"
}

# V.T/43 — UR-8. Both templates promised `announce` reaches every lane at its next boot;
# _recent_journal surfaces only TODAY's last five lines naming the lane as author or explicit
# @recipient, so a generic announcement is invisible to every other lane and nothing crossing a
# date boundary matches at all. A doc-lie is worse than a missing feature, because lanes act on it.
sc_no_false_announce_promise() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  need_file "$DM_PROTOCOL" "DM-PROTOCOL template" || return 0
  # instrument control: the flattener is looking at real content
  file_matches_near "$DM_PROTOCOL" 'announce' \
    || { fail "instrument check: DM-PROTOCOL.md does not mention announce at all"; return 0; }

  # NB `next[[:space:]]+boot`, not a literal single space: both templates WRAP this sentence, so
  # after flattening the words are separated by a newline-plus-indent run. A literal 'next boot'
  # silently missed the live false promise in the nav skill — measured, not assumed.
  if file_matches_near "$NAV_SKILL" '(everyone|every lane|all lanes).{0,40}next[[:space:]]+boot'; then
    fail "UR-8: the nav skill still promises announce reaches everyone at their next boot — _recent_journal filters to today + explicit mentions, so that promise is false"
  fi
  if file_matches_near "$DM_PROTOCOL" '(everyone|every lane|all lanes).{0,40}(its[[:space:]]+)?next[[:space:]]+boot'; then
    fail "UR-8: DM-PROTOCOL.md still promises announce reaches every lane at its next boot — narrow it to explicit mentions, today's journal"
  fi
}

# V.T/44 — the always-read skill stays <= 80 lines (measure, don't estimate).
sc_nav_skill_line_budget() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  n=$(wc -l < "$NAV_SKILL" | tr -d ' \n')
  [ "$n" -le 80 ] || fail "templates/navigation-standards.SKILL.md is $n lines (budget: 80)"
}

# V.T/45 — zero project-specific referents in the generic template.
sc_nav_skill_no_erd_referents() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  n=$(grep -cE 'AUTONOMOUS_WORK|\.brain/research' "$NAV_SKILL" 2>/dev/null || true)
  [ -n "$n" ] || n=0
  need_eq "$n" 0 "project-specific referents in the generic template"
}

# ══════════════════════════ V.N — NEW v1.2 behaviour (RED) ═══════════════════════════════
#
# Every scenario below pins something the v1.2 ruling introduces or changes. Authority is the
# map's `# v1.2` section: the Delete list, the 8-item Must-survive checklist, "Poison, without a
# counter", and the Suite-consequences Add list.
#
# All but ONE are RED against the v1.1 engine. The exception is V.N/51 (occupied archive
# destination), which is labelled `guard` and says why in its own comment: must-survive #5 is a
# PRESERVATION requirement the current engine already satisfies, so once it is narrowed to what
# the map actually claims there is nothing left for v1.1 to fail. It stays in this section
# because it is a v1.2 must-survive, not because it is red.

# V.N/46 — the claim layer is GONE. Consume is `pending/ → validate → emit → read/`, with no
# intermediate state and no name-embedded bookkeeping.
#   PROVES     (a) a freshly sent file's name is a bare `<ts>-<pid>[-<n>]` — the `.a<k>` counter
#              is deleted; (b) the archived name is the same id, still bare; (c) `claimed/` does
#              not exist ANYWHERE in the lane after a full send→consume cycle.
#   REJECTS    the whole v1.1 chain in one assertion set: an engine that keeps `claimed/` "just
#              for safety", one that keeps the attempt counter as a cheap poison defence, and one
#              that carries a claim stamp into the archive name.
#   NOTE       (c) is checked against the LANE, not just after the take: `_dm_ensure_tree`
#              creates every state directory up front, so a v1.1 engine fails here even if it
#              never claims anything.
sc_consume_has_no_claim_layer() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "no-claim-layer-v12"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: message queued" || return 0

  queued=$(first_file "$pd")
  need_v12_queue_name "$queued" "the name a fresh send mints in pending/"
  id=$(msg_id_of "$queued")

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take" || return 0
  need_file_has "$OUT" "no-claim-layer-v12" "the message must be delivered (positive control)" || return 0

  need_count "$pd" 0 "pending/ after a successful consume"
  need_count "$rd" 1 "read/ after a successful consume" || return 0
  archived=$(first_file "$rd")
  need_v12_queue_name "$archived" "the name the consume path writes into read/"
  need_eq "$(msg_id_of "$archived")" "$id" "the archived entry must carry the SAME id the send minted"

  need_file_absent "$fx/.brain/dm/bravo/claimed" \
    "the claimed/ state is DELETED by v1.2 — no lane directory may contain it (the ruling's head-of-chain: claim → hidden crash state → lease → invisible expiry → background sweeper → transition budget)"
}

# V.N/47 — must-survive #2, first limb: CRASH BEFORE EMIT. Stdout is closed, so emitting the
# message cannot succeed. The message must still be in pending/ — not archived, not quarantined,
# not parked in a hidden state — and the next boot must deliver it.
#   REJECTS    any consume that moves a file out of pending/ before it has been emitted (v1.0's
#              loss bug, and v1.1's claim-first ordering), and any that terminalises a message
#              because its OUTPUT failed.
sc_crash_before_emit_leaves_pending() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "crash-before-emit-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: message queued" || return 0

  _brain_env_run - "$base/closed.err" "$fx" bravo dm take

  need_count "$pd" 1 \
    "pending/ after a take whose OUTPUT could not be written — must-survive #2: nothing leaves pending/ until it has been emitted"
  need_tree_has "$pd" "crash-before-emit-v12" "the un-emitted message must still be the one sitting in pending/"
  need_count "$rd" 0 "read/ after a failed emit — a message archived without being delivered is exactly UR-1's silent loss"
  need_count "$fd" 0 "failed/ after a failed emit — an emit failure is not evidence that the message is structurally invalid"
  need_file_absent "$fx/.brain/dm/bravo/claimed" "no hidden intermediate state may hold the un-emitted message"

  # ...and it is delivered on the next boot, with no ageing, no sweeper and no lease to wait for.
  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot after the emit failure" || return 0
  need_str_has "$ctx" "crash-before-emit-v12" \
    "a message whose emit failed must be delivered by the very next boot (v1.2 has no lease to expire first)"
  need_count "$pd" 0 "pending/ after the recovery boot"
  need_count "$rd" 1 "read/ after the recovery boot"
}

# V.N/48 — must-survive #2, second limb: CRASH AFTER EMIT, BEFORE THE MOVE. read/ is made
# read-only, so the archive rename gets EACCES after the digest has already been printed.
#   PROVES     the emit really happened FIRST (the marker is on stdout), the message is NOT lost,
#              it stays in pending/, and it therefore REPLAYS on the next consume.
#   THE POINT  at-least-once is now a public contract: "duplicates acceptable". This scenario is
#              where the suite says so — a second delivery of the same message is CORRECT here,
#              not a double-consume defect. The v1.1 suite's Q.T/15 asserted the opposite and is
#              retired.
sc_crash_after_emit_before_move_replays() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "crash-after-emit-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0

  make_readonly_dir "$rd"
  mrc=$?
  case "$mrc" in
    0) ;;
    2) fail "instrument blind: a rename into a 0500 directory still succeeds (running as root?)"; return 0 ;;
    *) fail "fixture: could not make read/ read-only (rc=$mrc)"; return 0 ;;
  esac
  run_brain "$fx" bravo dm take
  chmod 755 "$rd" 2>/dev/null || true       # restore BEFORE any early return

  need_file_has "$OUT" "crash-after-emit-v12" \
    "must-survive #2 is EMIT-before-move: the digest must reach stdout before the archive rename is attempted"
  need_count "$rd" 0 "read/ after an archive rename that could not land"
  need_count "$pd" 1 \
    "pending/ after a failed archive rename — must-survive #2: 'rename failure leaves the source pending'"
  need_tree_has "$pd" "crash-after-emit-v12" "the retained message must be the one whose move failed"
  need_file_absent "$fx/.brain/dm/bravo/claimed" "no hidden intermediate state may hold the message"
  # the engine's own diagnostics are prefixed "brain: " (_warn/_die); a bare mv error on stderr
  # is a LEAK, not a report, and must not satisfy this. [F10b]
  if [ -s "$ERR" ]; then
    need_file_has "$ERR" "brain:" "a failed archive rename must be reported BY THE ENGINE (stderr carried output, but none of it was a 'brain: ' diagnostic — an unsuppressed mv error is a leak, not a report)"
  else
    fail "a failed archive rename must be reported (stderr was empty)"
  fi

  # AT-LEAST-ONCE: the same message is delivered AGAIN once the fault clears. That duplicate is
  # the contract, not a defect.
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "second take after the fault cleared" || return 0
  need_file_has "$OUT" "crash-after-emit-v12" \
    "at-least-once: a message emitted but not archived must REPLAY on the next consume (duplicates are explicitly acceptable)"
  need_count "$rd" 1 "read/ after the replay"
  need_count "$pd" 0 "pending/ after the replay"
}

# V.N/49 — "Poison, without a counter". A file PROVEN structurally invalid against the wire
# contract is quarantined; the valid peer beside it delivers in the SAME invocation.
#   FIXTURE    the corrupted entry is whichever the consumer reaches FIRST (head of line).
#   PROVES     quarantine happens (failed/ gains exactly the poison), it carries the poison's
#              bytes, pending/ is drained, the healthy peer is archived, and NO attempt counter
#              or retry bookkeeping appears in the quarantined name.
#   DISPATCHER the quarantine directory is `failed/` — v1.1's name, kept as a minimal grammar
#   DECISION   change. Ruled by the dispatcher for this pass.
#   REJECTS    a consumer that leaves a structurally-invalid file cycling in pending/ forever
#              (the redelivery loop the deleted poison cap existed to bound), one that discards
#              it silently, and one that drops the healthy peer with it.
sc_invalid_file_quarantined_valid_peer_delivers() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "quarantine-peer-a-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send #1" || return 0
  run_brain "$fx" alpha dm @bravo "quarantine-peer-b-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send #2" || return 0
  need_count "$pd" 2 "prerequisite: two peers queued" || return 0

  victim=$(first_file "$pd") || { fail "pending/ is empty after two sends"; return 0; }
  survivor="quarantine-peer-b-v12"
  grep -qF -- "quarantine-peer-b-v12" "$victim" 2>/dev/null && survivor="quarantine-peer-a-v12"
  printf '%s\n' '{structurally-invalid-v12' > "$victim" \
    || { fail "fixture: could not corrupt the head entry"; return 0; }

  run_brain "$fx" bravo dm take

  need_file_has "$OUT" "$survivor" \
    "the valid peer must deliver in the same invocation as the quarantined one (must-survive #3)"
  need_count "$fd" 1 \
    "failed/ after the consume — a file PROVEN structurally invalid against the wire contract must be quarantined, not left to redeliver forever"
  need_tree_has "$fd" "structurally-invalid-v12" "the quarantined file must carry the offending bytes"
  need_count "$rd" 1 "read/ — exactly the one valid peer is archived"
  need_count "$pd" 0 "pending/ after the consume — neither entry may be left cycling"
  q=$(first_file "$fd") || { fail "failed/ is empty"; return 0; }
  case "${q##*/}" in
    *.a[0-9]*) fail "the quarantined name '${q##*/}' carries a .a<k> attempt counter — v1.2 quarantines on proof, never on a retry count" ;;
  esac
}

# V.N/50 — must-survive #4: "one 'process at most K entries' cap plus aggregate output caps. If
# entries remain, the emitted context must explicitly instruct continuation — do not rely on a
# new directory event firing."
#   BOUND      45 entries are queued and at most DM_INJECT_MAX_LINES (40) may be delivered in one
#              boot. K itself is NOT pinned — the map does not name it — only that a bound exists
#              and does not exceed the surviving injection cap.
#   LOSSLESS   every entry is accounted for across pending/ + read/ + failed/ afterwards.
#   RESUMES    successive takes drain the remainder, so a bound is not starvation.
#   CONTINUATION is checked with a NEGATIVE CONTROL: a second vault whose 3-entry backlog fits in
#              one batch must NOT carry the phrase. Without that control the alternation could be
#              satisfied by boilerplate every boot prints.
sc_bounded_backlog_instructs_continuation() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  seed=$(plant_message "$fx" bravo "backlog-seed-v12") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  clone_queued "$seed" 44 "backlog-" || { fail "fixture: could not mint the backlog"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"backlog-00-marker"}' > "$seed" \
    || { fail "fixture: could not rewrite the seed body"; return 0; }
  need_count "$pd" 45 "prerequisite: 45 entries queued" || return 0

  ctx=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot with a 45-entry backlog" || return 0

  shown=0; i=0
  while [ "$i" -le 44 ]; do
    m=$(printf 'backlog-%02d-marker' "$i")
    str_has "$ctx" "$m" && shown=$((shown + 1))
    i=$((i + 1))
  done
  [ "$shown" -gt 0 ] || { fail "the boot injected NONE of the 45 queued entries"; return 0; }
  [ "$shown" -le "$DM_INJECT_MAX_LINES" ] \
    || fail "the boot delivered $shown of 45 entries — DM_INJECT_MAX_LINES ($DM_INJECT_MAX_LINES) is the surviving aggregate bound, so anything above it means no batch cap is applied"
  [ "$(count_files "$pd")" -gt 0 ] \
    || fail "instrument check: nothing remained pending after the bounded boot, so the continuation limb below would be vacuous — raise the fixture backlog above the engine's batch cap"

  total=$(( $(count_files "$pd") + $(count_files "$rd") + $(count_files "$fd") ))
  need_eq "$total" 45 "entries accounted for across pending/ + read/ + failed/ — bounding the BATCH must never destroy a MESSAGE"

  continuation_signal "$ctx" \
    || fail "must-survive #4: $(count_files "$pd") entr(y|ies) are still queued, and the emitted context does not instruct the lane to continue — the design explicitly forbids relying on a new directory event firing"

  continuation_has_absolute_engine=0
  while IFS= read -r continuation_line; do
    if continuation_signal "$continuation_line" &&
       str_has "$continuation_line" "\"$fx/.brain/bin/brain\" dm take"; then
      continuation_has_absolute_engine=1
      break
    fi
  done <<EOF
$ctx
EOF
  [ "$continuation_has_absolute_engine" = 1 ] \
    || fail "must-survive #7: the continuation instruction does not carry the exact receiving-vault engine invocation (\"$fx/.brain/bin/brain\" dm take)"

  # NEGATIVE CONTROL: a backlog that fits in one batch must NOT carry the continuation phrase.
  fx2=$(make_vault alpha bravo) || fatal "control fixture build failed"
  seed2=$(plant_message "$fx2" bravo "control-seed-v12") \
    || { fail "control: could not queue the seed message"; return 0; }
  clone_queued "$seed2" 2 "control-" || { fail "control: could not mint the small backlog"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"control-00-marker"}' > "$seed2" \
    || { fail "control: could not rewrite the seed body"; return 0; }
  ctx2=$(hook_context "$fx2" bravo); hrc=$?
  need_rc "$hrc" 0 "control boot with a 3-entry backlog" || return 0
  need_str_has "$ctx2" "control-00-marker" "control: the small backlog really was delivered"
  need_count "$(q_dir "$fx2" bravo pending)" 0 "control: a 3-entry backlog must drain in one boot" || return 0
  if continuation_signal "$ctx2"; then
    fail "instrument check: the continuation phrase is present when NOTHING remains queued — it is matching boot boilerplate, so the positive limb above proves nothing. Tighten continuation_signal()"
  fi

  # RESUMES: a bound must not starve the tail. The invocation budget is 50, not "45 / expected K":
  # K is not pinned by the map, and the loop exits as soon as pending/ empties, so a generous
  # budget costs nothing on a correct engine while refusing to false-reject a small batch cap.
  used=$(drain_takes "$fx" bravo 50)
  need_count "$pd" 0 "pending/ after $used follow-up take(s) — a bounded batch must resume, not starve"
  need_count "$rd" 45 "read/ after the backlog drains — every entry delivered and archived"
  need_count "$fd" 0 "failed/ after the backlog drains — no valid entry may be quarantined"
}

# V.N/51 — must-survive #5: "never a blind `mv -f` into read/; an occupied archive destination
# must not overwrite an earlier transcript."
#
#   ⚠ THIS IS A GUARD, NOT A RED — and that is the honest disposition, not a concession.
#   Must-survive #5 is a PRESERVATION requirement: the map lists it under "do not lose these in
#   the simplification", and `_dm_ack` already refuses an occupied destination today. Once the
#   claim is narrowed to what #5 actually says (below), there is nothing left for the v1.1 engine
#   to fail. Its at-GREEN provenance: the archive NAME changes with the grammar, so this is what
#   catches a rewrite that reaches for a blind `command mv -f` while re-plumbing the move.
#
#   NARROWED per dispatcher ruling. The first draft also asserted `read/ == 1` and `pending/ == 1`,
#   which pinned ONE of two legal outcomes: the map permits a bumped-name archive (the house
#   `_dm_failed_dest` idiom) just as much as retain-in-pending, and a count assertion silently
#   outlawed the former. Only #5's two real claims are asserted now.
#
#   FIXTURE    no hand-built sentinel and no assumption about how an id maps to an archive name:
#              a real send is really consumed, so the ENGINE mints the archive entry, and the
#              second message is then queued under that exact basename. That is a genuine
#              destination collision under v1.1's `<id>.a<k>` and v1.2's bare `<id>` alike.
#   PROVES     the earlier transcript survives BYTE-INTACT, and the colliding arrival is not lost.
#   REJECTS    `command mv -f` into read/ (the earlier transcript's bytes would be gone).
sc_occupied_read_destination_preserved() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  # 1. a real send, really consumed — the archive entry is a genuine earlier transcript whose
  #    name the ENGINE chose, so nothing here encodes a filename grammar.
  run_brain "$fx" alpha dm @bravo "earlier-transcript-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: first send" || return 0
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "prerequisite: first consume" || return 0
  need_count "$rd" 1 "prerequisite: the first transcript is archived" || return 0
  archived=$(first_file "$rd") || { fail "read/ is empty after the first consume"; return 0; }
  before_bytes=$(byte_size "$archived")

  # 2. queue a SECOND message under the name the archive already holds.
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"colliding-arrival-v12"}' \
    > "$pd/${archived##*/}" \
    || { fail "fixture: could not queue the colliding arrival"; return 0; }
  need_count "$pd" 1 "prerequisite: the colliding arrival is queued" || return 0

  run_brain "$fx" bravo dm take

  need_file_has "$archived" "earlier-transcript-v12" \
    "must-survive #5: the earlier transcript at the occupied archive destination was OVERWRITTEN — never a blind mv -f into read/"
  need_eq "$(byte_size "$archived")" "$before_bytes" \
    "the earlier transcript must be BYTE-INTACT, not merely still present"
  need_not_lost "$fx" bravo "colliding-arrival-v12" \
    "the arrival whose archive destination was occupied (retained pending or archived under a bumped name are BOTH legal)"
}

# V.N/52 — must-survive #8: "Expose the message id in the digest — if duplicates are a public
# contract, the receiving agent needs to recognise a replay. Currently only from/to/ts/content
# are rendered."
#   ASSERTION  the id appears in the emitted output. The RENDERING is deliberately not pinned —
#              a fifth JSON key, a prefix, a trailing comment all satisfy it (which is why the
#              V.W guards no longer assert an exact key set).
#   NOT A      the id (`<ts>-<pid>`) shares no substring with the ISO-8601 `ts` field, so this
#   COINCIDENCE cannot pass by accident on today's four-field record.
#   ALSO       the id the receiver sees must be the id the sender minted AND the one the archive
#              keeps — otherwise "recognise a replay" is unusable across the duplicate.
sc_message_id_exposed_in_digest() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "id-in-digest-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  queued=$(first_file "$pd") || { fail "pending/ is empty after the send"; return 0; }
  id=$(msg_id_of "$queued")
  [ -n "$id" ] || { fail "could not read the minted message id from ${queued##*/}"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take" || return 0
  need_file_has "$OUT" "id-in-digest-v12" "the message must be delivered (positive control)" || return 0

  need_file_has "$OUT" "$id" \
    "must-survive #8: the emitted digest does not carry the message id '$id' — with at-least-once delivery a public contract, the receiving agent has no way to recognise a replay"
  need_dir_has_id "$rd" "$id" "the archived entry must keep the same id the digest exposed"
}

# V.N/53 — "Poison, without a counter", the global-failure limb: "preflight global dependencies
# once — a global failure leaves everything pending; quarantine only a file proven structurally
# invalid; leave valid messages retryable indefinitely."
#   INSTRUMENT a PATH shim that makes `jq` fail for every invocation. jq is the engine's wire
#              validator, so without a preflight EVERY healthy message looks structurally invalid
#              and gets terminalised wholesale — the exact fault the ruling names ("a GLOBAL
#              failure (e.g. an incompatible jq) would terminalise healthy messages wholesale").
#   PATH is saved and restored around the run, and restored BEFORE any early return: a leaked
#   broken-jq PATH would silently break every later scenario in this file.
#   PROVES     nothing is quarantined, nothing is archived, everything stays in pending/, and the
#              messages are still deliverable once the dependency is healthy again (retryable
#              indefinitely).
sc_global_dependency_failure_leaves_everything_pending() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "global-dep-a-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send #1" || return 0
  run_brain "$fx" alpha dm @bravo "global-dep-b-v12"; rc=$?
  need_rc "$rc" 0 "prerequisite: send #2" || return 0
  need_count "$pd" 2 "prerequisite: two healthy messages queued" || return 0

  shim_dir="$base/broken-jq-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'printf "jq: simulated global dependency failure\\n" >&2\n'
    printf 'exit 3\n'
  } > "$shim_dir/jq"
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the broken jq shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo dm take
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  # Instrument controls, both directions:
  #   · the shim ENGAGED — proven by `read/ == 0` below: with a working jq the engine would have
  #     digested and archived both messages, so a blind shim would fail that assertion, not pass it.
  #   · the shim is GONE — checked here, because a leaked broken-jq PATH would silently poison
  #     every scenario that runs after this one.
  jq -e -n '1' >/dev/null 2>&1 \
    || { fail "instrument leak: the broken-jq shim is STILL on PATH after the restore — every later scenario in this file would be poisoned by it"; return 0; }

  need_count "$fd" 0 \
    "failed/ after a GLOBAL dependency failure — a broken jq is not proof that any individual message is structurally invalid, and quarantining on it terminalises healthy mail wholesale"
  need_count "$rd" 0 "read/ after a global dependency failure — nothing was validly emitted, so nothing may be archived"
  need_count "$pd" 2 \
    "pending/ after a global dependency failure — the ruling requires a global failure to leave EVERYTHING pending"
  need_tree_has "$pd" "global-dep-a-v12" "message #1 must still be queued"
  need_tree_has "$pd" "global-dep-b-v12" "message #2 must still be queued"
  need_file_absent "$fx/.brain/dm/bravo/claimed" "no hidden intermediate state may hold the messages"

  # retryable indefinitely: once the dependency is healthy, the same take delivers both.
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take after the dependency is healthy again" || return 0
  need_file_has "$OUT" "global-dep-a-v12" "message #1 must deliver once jq works again (valid messages are retryable indefinitely)"
  need_file_has "$OUT" "global-dep-b-v12" "message #2 must deliver once jq works again"
  need_count "$rd" 2 "read/ after the retry"
  need_count "$pd" 0 "pending/ after the retry"
}

# V.N/54 — the quarantine destination gets the same collision protection as the archive. Two
# structurally-invalid arrivals can map to the same `failed/` name (v1.1's `_dm_route_failed`
# already reserves a bumped `.collision-<ts>-<pid>` spelling for exactly this), and an earlier
# forensic record is the ONLY evidence of a message that was already thrown away once.
#   FIXTURE    the quarantine destination is pre-occupied under the name the ENGINE minted for the
#              pending entry, so the collision is real under either filename grammar.
#   PROVES     the earlier forensic record survives BYTE-INTACT, and the new arrival still reaches
#              failed/ — i.e. the collision is resolved by BUMPING, not by clobbering and not by
#              refusing forever (a structurally-invalid file left cycling in pending/ is the
#              redelivery loop the deleted poison cap existed to bound).
#   RED        against v1.1 for one reason: v1.1 never quarantines a structurally-invalid file at
#              all, so nothing arrives to collide. The earlier-record limb passes trivially today
#              and becomes load-bearing the moment V.N/49's quarantine lands.
#   DECLARED GAP: only the REGULAR-FILE collision kind is covered. The v1.1 suite also drove
#              directory- and symlink-occupied destinations (retired U.H4/53); those need a
#              non-regular entry planted inside a queue state directory, which the consumer-
#              boundary scenarios (V.X/36) already prove is refused wholesale. Not claimed here.
sc_failed_dest_collision_preserves_record() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); fd=$(q_dir "$fx" bravo failed)

  planted=$(plant_message "$fx" bravo "quarantine-collision-seed-v12") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  name=${planted##*/}
  printf '%s\n' '{invalid-colliding-quarantine-v12' > "$planted" \
    || { fail "fixture: could not corrupt the queued entry"; return 0; }

  mkdir -p "$fd" || { fail "fixture: could not create failed/"; return 0; }
  printf 'EARLIER-FORENSIC-RECORD-v12\n' > "$fd/$name" \
    || { fail "fixture: could not pre-occupy the quarantine destination"; return 0; }
  before_bytes=$(byte_size "$fd/$name")

  run_brain "$fx" bravo dm take

  need_file_has "$fd/$name" "EARLIER-FORENSIC-RECORD-v12" \
    "an occupied quarantine destination was OVERWRITTEN — the earlier forensic record is the only evidence of a message already discarded once"
  need_eq "$(byte_size "$fd/$name")" "$before_bytes" \
    "the earlier forensic record must be BYTE-INTACT, not merely still present"
  need_tree_has "$fd" "invalid-colliding-quarantine-v12" \
    "the newly quarantined arrival must still reach failed/ under a bumped name — a collision must not leave a structurally-invalid file cycling in pending/ forever"
  need_not_lost "$fx" bravo "invalid-colliding-quarantine-v12" "the colliding quarantine arrival"
}

# ═════════════════════ V.Q — v1.2.1 contract addendum (RED) ══════════════════════════════
#
# Authority: the seam map's `# v1.2.1 — CONTRACT ADDENDUM` section, rulings 1-6. Each scenario
# names the ruling it pins. The pre-PR review's transcripts supply fixture SHAPES only.
#
# SHIM DISCIPLINE (rulings 2, 4, 6 and 9 all need one): every PATH shim below follows V.N/53's
# rules exactly — PATH saved in the parent shell, restored BEFORE any assertion can return
# early, and a post-restore leak check that the shim directory is no longer what `command -v`
# resolves. A leaked shim would silently poison every later scenario in this file.

# V.Q/55 — ruling 1: "a non-regular direct child of `pending/` is quarantinable on the same
# footing as invalid content ... renamed — as a directory entry, NEVER dereferenced — into
# `failed/`", because "such an entry consumed a batch slot but was classified transient, [so] it
# was retried forever and 40 of them permanently starved every message behind them".
#   FIXTURE    40 symlinks + one directory, all lexically AHEAD of one valid message. Their names
#              are given in the v1.2 grammar ON PURPOSE: a grammar-invalid spelling would let the
#              NAME check shadow the limb under test — the same trap V.X/36 documents.
#   ⚠ NO FIFO, and the reason is measured, not squeamish. A FIFO was planted first and then
#              REMOVED: against a mutant that quarantines by DEREFERENCING (`cp -L` instead of
#              renaming the directory entry) the symlink limbs fail cleanly, but `cp` opens the
#              FIFO for reading and BLOCKS FOREVER — turning a detected defect into a wedged
#              suite with no output. A fixture that converts a FAIL into a hang is worse than no
#              fixture. Ruling 1's predicate is "not a regular file", one decision for the whole
#              class, and the two members kept exercise both hazards it names: a symlink (the
#              dereference door) and a directory (the not-a-file door). FIFO/socket/device-node
#              handling is therefore NOT claimed by this suite. Declared gap. [Q4]
#   PROVES     the valid message behind the wall is delivered, ONE invocation makes progress,
#              every unusable entry reaches failed/ AS A DIRECTORY ENTRY (still a symlink, still
#              a directory, still a FIFO — a dereferencing copy would be a regular file), the
#              symlink target's bytes are untouched, and its content never reaches read/.
#   REJECTS    today's engine exactly: `_dm_dir_ok` refuses the entry and `_dm_pending_digest`
#              calls that TRANSIENT, so the entry keeps its batch slot forever (measured by the
#              orchestrator: 0 emitted, still 0 on the second run).
sc_nonregular_entries_quarantined_not_starving() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  ext="$base/outside-nonregular"
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }
  printf '{"from":"mallory","to":"bravo","ts":"x","content":"XDEREF-nonregular-v121"}\n' \
    > "$ext/target.json" || { fail "fixture: could not write the external target"; return 0; }
  before_target=$(byte_size "$ext/target.json")

  # the valid message goes in FIRST: nothing may grep pending/ once the FIFO exists.
  run_brain "$fx" alpha dm @bravo "nonregular-survivor-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: the one valid message" || return 0
  need_count "$pd" 1 "prerequisite: exactly the valid message is queued" || return 0

  i=1
  while [ "$i" -le 40 ]; do
    ln -s "$ext/target.json" "$pd/$(printf '00000000T0000%02dZ-%s' "$i" "$i")" \
      || { fail "fixture: could not plant symlink #$i"; return 0; }
    i=$((i + 1))
  done
  mkdir "$pd/00000000T000090Z-90" \
    || { fail "fixture: could not plant the directory entry"; return 0; }
  unusable=41
  need_count "$pd" "$((unusable + 1))" "prerequisite: the wall plus one valid message" || return 0

  # ONE invocation must make progress. This is H1's exact measurement.
  before_pending=$(count_files "$pd")
  run_brain "$fx" bravo dm take
  after_pending=$(count_files "$pd")
  need_file_lacks "$OUT" "XDEREF-nonregular-v121" \
    "a symlinked queue entry was DEREFERENCED and its target's content emitted as a message"
  [ "$after_pending" -lt "$before_pending" ] \
    || fail "ruling 1: one 'dm take' over $before_pending queued entries moved NOTHING out of pending/ — a non-regular entry consumes a batch slot and is classified transient, so it is retried forever and starves every message behind it"

  used=$(drain_takes "$fx" bravo 12)
  need_count "$pd" 0 \
    "pending/ after $used follow-up take(s) — the wall must DRAIN, not be re-examined on every invocation"
  need_count "$rd" 1 "read/ after the drain — the one valid message is delivered and archived"
  need_tree_has "$rd" "nonregular-survivor-v121" \
    "the valid message behind the wall must actually be delivered (H1: measured 0 emitted)"
  need_count "$fd" "$unusable" \
    "failed/ after the drain — every structurally unusable queue entry is quarantined on the same footing as invalid content"

  # NEVER DEREFERENCED: quarantine renames the DIRECTORY ENTRY. A follow-and-copy would land
  # regular-file bytes in failed/ and would have opened the target.
  qlinks=0; qdirs=0; qother=0
  for qf in "$fd"/*; do
    [ -e "$qf" ] || [ -L "$qf" ] || continue
    if [ -L "$qf" ]; then qlinks=$((qlinks + 1))
    elif [ -d "$qf" ]; then qdirs=$((qdirs + 1))
    else qother=$((qother + 1)); fi
  done
  need_eq "$qlinks" 40 \
    "symlinks quarantined AS symlinks — ruling 1 renames the directory entry and never dereferences it, so a regular file here means the target was followed and its bytes copied into the queue"
  need_eq "$qdirs" 1 "the directory entry quarantined as a directory"
  need_eq "$qother" 0 "failed/ must hold no entry that was materialised as a regular file"

  need_eq "$(byte_size "$ext/target.json")" "$before_target" \
    "the symlink target's bytes must be untouched — the entry is never opened"
  need_file_has "$ext/target.json" "XDEREF-nonregular-v121" \
    "the external target must survive intact (positive control that it was readable at all)"
  need_tree_lacks "$rd" "XDEREF-nonregular-v121" \
    "the symlink target's CONTENT must never reach read/ — a dereferenced link is arbitrary external content entering the transcript archive"
}

# V.Q/56 — ruling 2: "the engine may not hard-code a dependency's incidental exit code ...
# `_dm_jq_preflight` ... must PROBE every contract the consume path relies on — including the
# parse-error code and the `error()` code". Measured in the review: jq 1.6 (Debian bookworm,
# Ubuntu 22.04) exits 4 for a parse error; jq 1.7.1 exits 5.
#   INSTRUMENT a jq-1.6-emulating PATH shim: the REAL jq runs, and only a PARSE error's exit
#              code is remapped 5 → 4 (discriminated on jq's own "parse error" stderr line).
#              `error()` still exits 5, so this fixture is neutral between the two spellings the
#              ruling permits — "recording" the probed codes and "verifying" them both classify
#              this jq correctly, and neither is forced.
#   CONTROLS   engagement is measured directly (a parse error must exit 4 while the shim is on
#              PATH), and the restore is checked by resolving `jq` again afterwards.
#   REJECTS    today's engine: `_dm_digest` exits 4, `_dm_pending_digest`'s `case` sends anything
#              but 5 to the TRANSIENT branch, so a corrupt message is never quarantined and
#              retries on every boot forever.
sc_probed_parse_error_code_still_quarantines() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  planted=$(plant_message "$fx" bravo "jq16-victim-seed-v121") \
    || { fail "prerequisite: could not queue the victim"; return 0; }
  run_brain "$fx" alpha dm @bravo "jq16-peer-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: the healthy peer" || return 0
  printf '%s\n' '{jq16-structurally-invalid-v121' > "$planted" \
    || { fail "fixture: could not corrupt the victim"; return 0; }
  need_count "$pd" 2 "prerequisite: one corrupt entry and one healthy peer" || return 0

  shim_dir="$base/jq16-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  # SC2016 is the POINT here: these single-quoted formats are the shim's SOURCE TEXT, and $@ /
  # $? / $$ must reach the generated script unexpanded. Only "$real_jq" and "$base" interpolate.
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '# jq 1.6 emulation: a PARSE error exits 4; error() still exits 5; everything else\n'
    printf '# is the real jq, byte for byte.\n'
    printf '_e="%s/jq16-err.$$"\n' "$base"
    printf '"%s" "$@" 2>"$_e"\n' "$real_jq"
    printf '_rc=$?\n'
    printf 'cat "$_e" >&2 2>/dev/null\n'
    printf 'if [ "$_rc" = 5 ] && grep -q "parse error" "$_e" 2>/dev/null; then _rc=4; fi\n'
    printf 'rm -f "$_e" 2>/dev/null\n'
    printf 'exit "$_rc"\n'
  } > "$shim_dir/jq" || { fail "fixture: could not write the jq shim"; return 0; }
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  jq -e . "$planted" >/dev/null 2>&1
  probe_rc=$?
  run_brain "$fx" bravo dm take
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac

  need_eq "$probe_rc" 4 \
    "instrument check: with the shim on PATH a JSON parse error must exit 4 (the jq 1.6 code) — otherwise this scenario proves nothing about a version-dependent exit code" || return 0

  need_count "$fd" 1 \
    "ruling 2: a jq that reports a parse error with a code OTHER than 5 must still quarantine — deriving invalidity from a hard-coded 5 leaves a corrupt message retrying forever on current stable distros"
  need_tree_has "$fd" "jq16-structurally-invalid-v121" \
    "the quarantined file must carry the offending bytes"
  need_file_has "$OUT" "jq16-peer-v121" "the healthy peer must deliver in the same invocation"
  need_count "$rd" 1 "read/ — exactly the healthy peer is archived"
  need_count "$pd" 0 "pending/ — neither entry may be left cycling"
}

# V.Q/57 — ruling 2's fail-safe half: "A jq whose behavior cannot be established fails safe to
# *everything stays pending* ... Fail-safe is leave-pending; it is never quarantine."
#   INSTRUMENT a shim whose parse-error exit code COLLIDES WITH SUCCESS (0, with jq's own empty
#              stdout). Invalidity is then genuinely undecidable from the exit code, so no
#              engine may claim proof — while `utf8bytelength`/`tojson` still work, which is
#              exactly what distinguishes this from V.N/53's wholly-broken jq: the OLD preflight
#              passes here, so only a preflight that PROBES the parse-error code can notice.
#   PROVES     nothing is quarantined, nothing is archived, BOTH messages (the corrupt one and
#              its healthy peer) stay pending, and everything is deliverable once the dependency
#              is trustworthy again.
#   REJECTS    today's engine: the digest returns 0 with empty output, so a blank line is emitted
#              as a message and the corrupt file is archived into read/ — worse than quarantine.
sc_unestablishable_jq_leaves_everything_pending() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  planted=$(plant_message "$fx" bravo "jqamb-victim-seed-v121") \
    || { fail "prerequisite: could not queue the victim"; return 0; }
  run_brain "$fx" alpha dm @bravo "jqamb-peer-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: the healthy peer" || return 0
  printf '%s\n' '{jqamb-structurally-invalid-v121' > "$planted" \
    || { fail "fixture: could not corrupt the victim"; return 0; }
  need_count "$pd" 2 "prerequisite: one corrupt entry and one healthy peer" || return 0

  shim_dir="$base/jqamb-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  # SC2016 is the POINT here — see V.Q/56's identical note.
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '# A jq whose PARSE-error exit code is indistinguishable from success. Invalidity\n'
    printf '# cannot be established from an exit code on this build.\n'
    printf '_e="%s/jqamb-err.$$"\n' "$base"
    printf '"%s" "$@" 2>"$_e"\n' "$real_jq"
    printf '_rc=$?\n'
    printf 'cat "$_e" >&2 2>/dev/null\n'
    printf 'if [ "$_rc" = 5 ] && grep -q "parse error" "$_e" 2>/dev/null; then _rc=0; fi\n'
    printf 'rm -f "$_e" 2>/dev/null\n'
    printf 'exit "$_rc"\n'
  } > "$shim_dir/jq" || { fail "fixture: could not write the jq shim"; return 0; }
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  jq -e . "$planted" >/dev/null 2>&1
  probe_rc=$?
  jq -e -n '"x" | (utf8bytelength == 1 and ((tojson | type) == "string"))' >/dev/null 2>&1
  preflight_rc=$?
  run_brain "$fx" bravo dm take
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac

  need_eq "$probe_rc" 0 \
    "instrument check: with the shim on PATH a parse error must exit 0, colliding with success" || return 0
  need_eq "$preflight_rc" 0 \
    "instrument check: the OLD utf8bytelength/tojson preflight must still PASS on this jq — otherwise this scenario is just V.N/53 again and says nothing about probing the exit-code contract" || return 0

  need_count "$fd" 0 \
    "ruling 2: fail-safe is LEAVE-PENDING, never quarantine — a jq whose parse-error verdict cannot be established is not proof that any message is structurally invalid"
  need_count "$rd" 0 \
    "read/ after an unestablishable jq — nothing was validly digested, so nothing may be archived (an empty digest emitted as a message is not a delivery)"
  need_count "$pd" 2 \
    "pending/ after an unestablishable jq — the ruling requires EVERYTHING to stay pending, the healthy peer included"
  need_tree_has "$pd" "jqamb-structurally-invalid-v121" "the corrupt entry must still be queued"
  need_tree_has "$pd" "jqamb-peer-v121" "the healthy peer must still be queued"

  # retryable: once the dependency is trustworthy, the ordinary verdicts apply.
  run_brain "$fx" bravo dm take
  need_file_has "$OUT" "jqamb-peer-v121" "the healthy peer must deliver once jq is trustworthy again"
  need_count "$rd" 1 "read/ after the retry"
  need_count "$fd" 1 "failed/ after the retry — NOW the corrupt file is proven invalid"
  need_count "$pd" 0 "pending/ after the retry"
}

# V.Q/58 — ruling 3(a): "the producer grammar is enforced with explicit digit-only checks".
# `_dm_id_ok`'s `[0-9]*` is a shell GLOB, not a regex, so it admits whitespace inside the PID
# field. The crafted name is the review's own reproduction.
#   REJECTS    an engine that accepts a whitespace-bearing queue filename, digests it and
#              archives it under that name — which is what happens today.
#   NOTE       glob metacharacters in the same position are already refused (`…Z-1*` fails
#              `_dm_id_ok`'s `[1-9][0-9]*` case), so whitespace is the live hole, not a class.
#   NAME       the review's literal spelling is kept here because nothing in this scenario
#              depends on where the crafted entry sorts. V.Q/59's shape DOES depend on that, and
#              says why it uses different tokens.
sc_whitespace_queue_name_rejected() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "whitespace-peer-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: the healthy peer" || return 0

  crafted='20260803T000000Z-12 20260805T000000Z-123'
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"whitespace-name-body-v121"}' \
    > "$pd/$crafted" || { fail "fixture: could not plant the whitespace-named entry"; return 0; }
  need_count "$pd" 2 "prerequisite: the crafted entry plus one healthy peer" || return 0

  run_brain "$fx" bravo dm take

  need_file_lacks "$OUT" "whitespace-name-body-v121" \
    "ruling 3(a): a queue filename carrying embedded WHITESPACE must be rejected by the producer grammar — a [0-9]* case-glob is not a digit-only check, and it admits a space"
  need_file_has "$OUT" "whitespace-peer-v121" \
    "the healthy peer must still deliver (must-survive #3)"
  need_tree_lacks "$rd" "whitespace-name-body-v121" \
    "a grammar-rejected entry must never reach the transcript archive"
  need_count "$rd" 1 "read/ — exactly the healthy peer is archived"
  need_count "$fd" 1 \
    "failed/ — a name the grammar rejects is a proven-unusable queue entry and is quarantined (ruling 1's footing), not left cycling"
  need_tree_has "$fd" "whitespace-name-body-v121" "the quarantined entry must carry the offending bytes"
  need_count "$pd" 0 "pending/ after the consume"
}

# V.Q/59 — ruling 3(b): "collected filenames are NEVER joined into a delimited string. A filename
# crosses any boundary as exactly one element (quoted positional parameters)."
#   FIXTURE    the review's shape — crafted whitespace name FIRST, ordinary entries, and a real
#              file named exactly the crafted name's SECOND token LAST — but with MARGIN.
#              ⚠ MARGIN IS LOAD-BEARING [F2]. The review's literal 41-entry count leaves ZERO
#              slack against the 40-entry cap, and the map deliberately does not pin whether a
#              REJECTED entry consumes a batch slot ([L9]). Both policies are permitted, and at
#              41 entries they disagree about whether the trailing file is inside the batch:
#                · rejected entry CONSUMES a slot → batch = crafted + 39 ordinary, trailing is
#                  #41, outside. Fixture reproduces.
#                · rejected entry does NOT consume a slot (exactly what ruling 1's fix does) →
#                  batch = 39 ordinary + trailing = 40, trailing is INSIDE, nothing stays
#                  pending, and this scenario fails its own instrument check against a COMPLIANT
#                  engine. A false red is worse than a missing test: it sends the implementer
#                  to fix code that is already right.
#              So: 50 ordinary valid entries, not 39. Under the tighter policy the 40-entry cap
#              is exceeded by 10 valid entries before the trailing file is even reached, and the
#              cap can only be ≤ DM_INJECT_MAX_LINES (V.N/50 pins delivery at or under it), so
#              the trailing file is outside the batch under BOTH policies with margin to spare.
#              ⚠ The review's literal spelling (`20260803T000000Z-12 20260805T000000Z-123`) is
#              CLOCK-DEPENDENT — engine-minted names carry today's date, so which side of the
#              ordinary entries those tokens land on changes with the wall clock, and the shape
#              silently stops reproducing. Measured: at 2026-08-05T00:42Z the trailing entry
#              sorted SECOND, not last, and this scenario went green for the wrong reason. The
#              tokens below are the lexical extremes of the 8-digit date field, so the ordering
#              is fixed for the suite's lifetime. Only the spelling changed; the shape is the
#              review's.
#   PROVES     the invariant ruling 3 exists to protect — no message is archived that was not
#              emitted (must-survive #2 / UR-1). Today `set -- $_valid_names` re-splits the
#              crafted name and promotes the LAST file, never digested, straight into read/.
#   ASSERTION  stated as a UNIVERSAL over read/ — every archived entry's body must appear in the
#              emitted context — so it depends on NO batch arithmetic, no cap value, and no
#              slot-accounting policy. It also catches an archived-but-unemitted entry of ANY
#              name, not just the trailing one this fixture happens to construct. [F2]
#   ⚠ VACUITY, DECLARED [Q3]: the premise "a whitespace-bearing name reaches the collected set"
#              becomes unreachable once ruling 3(a) lands — `_valid_names` is built only from
#              names that already passed `_dm_id_ok`. So AFTER (a), ruling 3(b) is DEFENCE IN
#              DEPTH against a future name-shaped value, NOT a currently-reachable second bug,
#              and this scenario stops discriminating the round trip on its own. It is written
#              as an invariant (guarded on whether the body was actually emitted) so it can
#              never FALSELY fail a compliant engine.
#              Dispatcher ruling 2026-08-04: behavioural only, NO structural witness here. The
#              discrimination is pinned at gate time by a TEMPORARY mutant in
#              test/mutation-probe.sh (grammar relaxed to accept whitespace ⇒ this scenario must
#              fire, and only it), owed by the probe rewrite the dispatcher owns. See [Q3].
sc_no_message_archived_that_was_not_emitted() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  seed=$(plant_message "$fx" bravo "h4b-seed-v121") \
    || { fail "prerequisite: could not queue the seed"; return 0; }
  clone_queued "$seed" 49 "h4b-" || { fail "fixture: could not mint the ordinary entries"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"h4b-00-marker"}' > "$seed" \
    || { fail "fixture: could not rewrite the seed body"; return 0; }

  crafted='00000001T000000Z-12 99991231T235959Z-123'
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"h4b-crafted-body-v121"}' \
    > "$pd/$crafted" || { fail "fixture: could not plant the crafted entry"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"h4b-last-body-v121"}' \
    > "$pd/99991231T235959Z-123" || { fail "fixture: could not plant the trailing entry"; return 0; }
  need_count "$pd" 52 "prerequisite: 1 crafted + 50 ordinary + 1 trailing entry are queued" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "SessionStart with the crafted-name backlog" || return 0

  # non-vacuity: something really was delivered AND something really was archived, so the
  # universal below is quantified over a non-empty set rather than satisfied by an empty read/.
  need_str_has "$ctx" "h4b-00-marker" \
    "instrument check: the boot delivered none of the ordinary entries, so the invariant below would be vacuous"
  [ "$(count_files "$rd")" -gt 0 ] \
    || { fail "instrument check: read/ is empty after the boot, so 'nothing was archived without being emitted' is vacuously true and proves nothing"; return 0; }

  # THE INVARIANT — universal over read/, independent of the cap and of slot accounting.
  unemitted=0; unemitted_name=""
  for af in "$rd"/*; do
    [ -e "$af" ] || [ -L "$af" ] || continue
    abody=$(jq -r 'if type == "object" and (.content | type) == "string" then .content else empty end' \
      "$af" 2>/dev/null)
    if [ -z "$abody" ]; then
      fail "instrument check: archived entry ${af##*/} carries no readable .content, so this scenario cannot judge whether it was emitted"
      continue
    fi
    if ! str_has "$ctx" "$abody"; then
      unemitted=$((unemitted + 1)); unemitted_name=${af##*/}
    fi
  done
  need_eq "$unemitted" 0 \
    "ruling 3(b): $unemitted archived entr(y|ies) — e.g. '$unemitted_name' — carry a body that NEVER appeared in the emitted context. The collected names round-tripped through a delimited string that an unquoted re-split tore apart, promoting an un-digested file into the archive list. That is an emit-before-move violation: UR-1's silent loss through a new door"
  need_str_lacks "$ctx" "h4b-crafted-body-v121" \
    "ruling 3(a) on the boot path: the crafted whitespace name must not be digested"
}

# V.Q/60 — ruling 4: "minted identity is derived, never inherited — the engine clears/ignores an
# inherited `_DM_ID_TS` ... validates the final id against the grammar BEFORE composing any path,
# and asserts the destination's literal parent is the intended `pending/` directory."
#   INSTRUMENT the environment itself. `_brain_exec` runs `env` WITHOUT `-i`, so an exported
#              variable in this shell reaches the engine — no helper change needed. It is unset
#              in the parent immediately after each run, before any assertion can return early.
#   LIMB 1     `../read/<ts>` places a "sent" message straight into terminal read/, which no
#              consumer ever emits — `brain dm` reports success and the message is simply gone.
#   LIMB 2     more `../` escapes `.brain/dm` entirely.
#   PROVES     both destinations are refused AND the send still lands normally in pending/ under
#              a grammar-valid name — "ignores" means the send proceeds with a DERIVED id, so
#              refusing the send outright would not satisfy the ruling either.
sc_inherited_id_ts_cannot_escape_pending() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  _DM_ID_TS='../read/20260804T000000Z'; export _DM_ID_TS
  run_brain "$fx" alpha dm @bravo "id-ts-into-read-v121"
  rc1=$?
  unset _DM_ID_TS

  _DM_ID_TS='../../../../escapeprobe'; export _DM_ID_TS
  run_brain "$fx" alpha dm @bravo "id-ts-escape-v121"
  rc2=$?
  unset _DM_ID_TS

  need_rc "$rc1" 0 "a send with an inherited _DM_ID_TS must still succeed — the ruling says the value is CLEARED/IGNORED, not that the send fails"
  need_rc "$rc2" 0 "a send with a path-bearing inherited _DM_ID_TS must still succeed"
  need_count "$rd" 0 \
    "ruling 4: an inherited _DM_ID_TS placed a 'sent' message directly into TERMINAL read/ — no consumer ever emits it, so cmd_dm reports success over a message that is silently gone"

  escaped=0
  for ef in "$fx"/escapeprobe* "$fx/.brain"/escapeprobe* "$base"/escapeprobe*; do
    [ -e "$ef" ] || [ -L "$ef" ] || continue
    escaped=$((escaped + 1))
  done
  need_eq "$escaped" 0 \
    "ruling 4: an inherited _DM_ID_TS composed a destination OUTSIDE .brain/dm — the minted id must be validated against the grammar BEFORE any path is composed, and the destination's literal parent asserted to be pending/"

  need_count "$pd" 2 \
    "pending/ after two sends with a hostile inherited _DM_ID_TS — identity is DERIVED, so both messages belong in the recipient's pending/ under engine-minted ids"
  for qf in "$pd"/*; do
    [ -e "$qf" ] || [ -L "$qf" ] || continue
    need_v12_queue_name "$qf" "the id minted while _DM_ID_TS was inherited"
  done
}

# V.Q/61 — ruling 4, second half: the engine "requires its clock helper to actually succeed (a
# masked failure must not yield a malformed id)". `_dm_new_id` takes `$(_now_compact)` without
# checking it, so a failing `date` yields the id `-<pid>` — which `_dm_send` then uses, and which
# every consumer must later reject.
#   INSTRUMENT a `date` PATH shim that always fails. Same save/restore/leak discipline as V.N/53.
#   POSITIVE   a send made BEFORE the shim is installed proves the vault and the grammar checker
#   CONTROL    are both live, so "no malformed name found" is a result rather than an empty queue.
#   NOT PINNED the exit status of the failed send: the ruling requires that no malformed id is
#              PRODUCED, and both "refuse the send" and "fail before writing" satisfy that.
sc_failed_clock_mints_no_malformed_id() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "clock-ok-control-v121"
  rc=$?
  need_rc "$rc" 0 "positive control: a send with a working clock" || return 0
  need_count "$pd" 1 "positive control: the control message is queued" || return 0

  shim_dir="$base/broken-date-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'printf "date: simulated clock failure\\n" >&2\n'
    printf 'exit 1\n'
  } > "$shim_dir/date" || { fail "fixture: could not write the date shim"; return 0; }
  chmod +x "$shim_dir/date" || { fail "fixture: could not make the date shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" alpha dm @bravo "clock-failure-v121"
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v date)" in
    "$shim_dir"/*) fail "instrument leak: the date shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  date -u +%Y%m%dT%H%M%SZ >/dev/null 2>&1 \
    || { fail "instrument leak: date is still broken after the restore — every later scenario would be poisoned"; return 0; }

  for st in pending read failed; do
    for qf in "$(q_dir "$fx" bravo "$st")"/*; do
      [ -e "$qf" ] || [ -L "$qf" ] || continue
      need_v12_queue_name "$qf" \
        "a queue entry minted while the clock helper FAILED (ruling 4: a masked _now_compact failure must not yield a malformed id)"
    done
  done
  need_count "$rd" 0 "read/ after a failed-clock send — nothing terminal may be produced"
  need_count "$fd" 0 "failed/ after a failed-clock send — no message may need quarantining because the SENDER minted a bad name"
  # [F6] The name-grammar limbs above are satisfied by an engine that SILENTLY SUBSTITUTES a
  # synthetic timestamp when the clock fails: it mints a grammar-valid id and queues the message.
  # Ruling 4 requires the clock helper to ACTUALLY SUCCEED, so a failed clock must queue nothing —
  # only the positive control may be here.
  need_count "$pd" 1 \
    "pending/ after a failed-clock send — ruling 4 requires the clock helper to actually succeed, so no message may be queued at all; a synthetic-timestamp fallback mints a valid-LOOKING id and passes every grammar check while violating the ruling"
}

# V.Q/62 — ruling 6: "every path that absorbs an anomaly (bump taken, bump-construction failure)
# emits a `brain: `-prefixed diagnostic". v1.1 refused an occupied archive destination LOUDLY;
# v1.2 bumps silently, and `_dm_collision_dest`'s internal failures return without a word.
#   FIXTURE A  a real send really consumed, then a second message queued under the archive's own
#              basename — the same genuine collision V.N/51 builds, so no filename grammar is
#              encoded here either.
#   FIXTURE B  the same collision with a failing `date`, so `_dm_collision_dest` cannot mint the
#              `.collision-<epoch>-<pid>` suffix and returns 1. Today that failure is completely
#              invisible: `_dm_archive` returns without a warn and `cmd_dm_take` only sets rc.
#   ANCHOR     both limbs assert the colliding message was EMITTED first — proof the run actually
#              reached the archive step, so silence is silence and not a short circuit.
#   NOT PINNED the wording, and not the outcome: V.N/51 already rules that bumping and retaining
#              are both legal. Only the `brain: ` diagnostic is asserted, and only in limb A.
#
#   ⚠ LIMB B ASSERTS NO DIAGNOSTIC, and the reason is measured, not assumed [F1 / Q5].
#              An earlier draft asserted a `brain: ` line here too. That was a FALSE GREEN:
#              `_dm_collision_dest` is reachable ONLY through an already-occupied destination, so
#              an engine that warns about the OCCUPANCY before attempting the bump emits an
#              indistinguishable `brain: ` line in both limbs while leaving the construction
#              failure completely traceless. Measured against exactly that engine (one `_warn`
#              added ahead of the `_dm_collision_dest` call, nothing else): the whole scenario
#              PASSED. Separating the two diagnostics needs the WORDING pinned, which this suite
#              refuses to do everywhere else (V.C/24 is the standing precedent). Reachability was
#              never the problem — this limb reaches the path today and is red on it; the problem
#              is that no wording-free observation can tell the two anomalies apart.
#              Dispatcher ruling 2026-08-04: an honest gap over a hollow assertion. Limb B is
#              retained for what it DOES prove cheaply and uniquely — that a post-emit archive
#              abandonment under a failing clock does not destroy the message (must-survive #2,
#              under a fault no other scenario drives). Ruling 6's bump-CONSTRUCTION-failure
#              diagnostic is UNCOVERED; see [Q5].
sc_collision_anomalies_are_diagnosed() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  # ── A: the bump is taken ──
  run_brain "$fx" alpha dm @bravo "m3a-earlier-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: first send" || return 0
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "prerequisite: first consume" || return 0
  need_count "$rd" 1 "prerequisite: the earlier transcript is archived" || return 0
  archived=$(first_file "$rd") || { fail "read/ is empty after the first consume"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"m3a-colliding-v121"}' \
    > "$pd/${archived##*/}" || { fail "fixture: could not queue the colliding arrival"; return 0; }

  run_brain "$fx" bravo dm take
  need_file_has "$OUT" "m3a-colliding-v121" \
    "anchor: the colliding message must be emitted, so the run really reached the archive step" || return 0
  if [ -s "$ERR" ]; then
    need_file_has "$ERR" "brain:" \
      "ruling 6: an occupied archive destination that is silently BUMPED must emit a 'brain: '-prefixed diagnostic (stderr carried output, but none of it was an engine diagnostic — a bare tool error is a leak, not a report)"
  else
    fail "ruling 6: an occupied archive destination was bumped with NO diagnostic at all — v1.1 refused it loudly, and an anomaly absorbed in silence is exactly what the ruling forbids"
  fi

  # ── B: the bump cannot be constructed ──
  fx2=$(make_vault alpha bravo) || fatal "second fixture build failed"
  base2=$(dirname "$fx2")
  pd2=$(q_dir "$fx2" bravo pending); rd2=$(q_dir "$fx2" bravo read)

  run_brain "$fx2" alpha dm @bravo "m3b-earlier-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: second-fixture send" || return 0
  run_brain "$fx2" bravo dm take
  rc=$?
  need_rc "$rc" 0 "prerequisite: second-fixture consume" || return 0
  archived2=$(first_file "$rd2") || { fail "read/ is empty in the second fixture"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"m3b-colliding-v121"}' \
    > "$pd2/${archived2##*/}" || { fail "fixture: could not queue the second colliding arrival"; return 0; }

  shim_dir="$base2/nodate-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'printf "date: simulated clock failure\\n" >&2\n'
    printf 'exit 1\n'
  } > "$shim_dir/date" || { fail "fixture: could not write the date shim"; return 0; }
  chmod +x "$shim_dir/date" || { fail "fixture: could not make the date shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx2" bravo dm take
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v date)" in
    "$shim_dir"/*) fail "instrument leak: the date shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac

  need_file_has "$OUT" "m3b-colliding-v121" \
    "anchor: the colliding message must be emitted, so the run really reached the collision-bump step" || return 0
  # NO diagnostic assertion here — see the LIMB B note above [F1 / Q5]. What IS asserted is
  # must-survive #2 under a fault nothing else in this suite drives: the archive could not even
  # construct a destination name, and the message must survive that intact and replayable.
  need_not_lost "$fx2" bravo "m3b-colliding-v121" \
    "the message whose archive bump could not be constructed"
  need_count "$pd2" 1 \
    "pending/ after an archive that could not construct a collision name — an emitted-but-unarchived message stays pending and replays (must-survive #2)"
  need_count "$rd2" 1 \
    "read/ is unchanged — the earlier transcript is still there and the colliding arrival did not overwrite it"
}

# V.Q/63 — ruling 6, final clause: "The batch cap on the `dm take` path warns when entries remain
# — as OPERATOR VISIBILITY, and explicitly NOT as must-survive #4's continuation contract, which
# stays scoped to the SessionStart emitted context."
#   SO         this asserts a stderr diagnostic on the TAKE path only. Nothing here says anything
#              about the emitted context; V.N/50 owns that and is untouched.
#   CONTROL    a second vault whose backlog drains in one invocation must NOT carry the warn —
#              without it the alternation could be satisfied by something the take always prints.
#   REJECTS    today's `cmd_dm_take`, which breaks out of the loop at DM_INJECT_MAX_LINES and
#              says nothing, so an operator cannot distinguish "drained" from "capped, N left".
sc_take_batch_cap_warns_when_entries_remain() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  seed=$(plant_message "$fx" bravo "capwarn-seed-v121") \
    || { fail "prerequisite: could not queue the seed"; return 0; }
  clone_queued "$seed" 44 "capwarn-" || { fail "fixture: could not mint the backlog"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"capwarn-00-marker"}' > "$seed" \
    || { fail "fixture: could not rewrite the seed body"; return 0; }
  need_count "$pd" 45 "prerequisite: 45 entries queued" || return 0

  run_brain "$fx" bravo dm take
  [ "$(count_files "$pd")" -gt 0 ] \
    || fail "instrument check: the whole 45-entry backlog drained in one take, so there is nothing for the cap to warn about — raise the fixture above the engine's batch cap" || return 0
  if grep -E '^brain: ' "$ERR" 2>/dev/null | grep -qiE 'remain|more|still'; then
    : # operator can tell the batch was capped
  else
    fail "ruling 6: 'dm take' capped the batch with $(count_files "$pd") entr(y|ies) still queued and emitted no 'brain: ' diagnostic saying so — an operator cannot distinguish 'drained' from 'capped, N left'"
  fi

  # NEGATIVE CONTROL: a take that drains everything must NOT claim entries remain.
  fx2=$(make_vault alpha bravo) || fatal "control fixture build failed"
  seed2=$(plant_message "$fx2" bravo "capctl-seed-v121") \
    || { fail "control: could not queue the seed"; return 0; }
  clone_queued "$seed2" 2 "capctl-" || { fail "control: could not mint the small backlog"; return 0; }
  run_brain "$fx2" bravo dm take
  rc=$?
  need_rc "$rc" 0 "control: a 3-entry take" || return 0
  need_count "$(q_dir "$fx2" bravo pending)" 0 "control: a 3-entry backlog drains in one take" || return 0
  if grep -E '^brain: ' "$ERR" 2>/dev/null | grep -qiE 'remain|more|still'; then
    fail "instrument check: the 'entries remain' warn fired on a take that drained EVERYTHING — it is matching something the take always prints, so the positive limb above proves nothing"
  fi
}

# V.Q/66 — ruling 2, the SECOND undeclared jq dependency (review H3): the preflight "must probe
# every contract the consume path relies on — including the parse-error code AND the `error()`
# code". V.Q/56 covers the parse-error code; without this one, an engine that probes only that
# and hard-codes `error()==5` passes the whole suite while carrying the same class of defect.
#   INSTRUMENT a shim that remaps ONLY `error()`'s exit code 5 → 7, discriminated on jq's own
#              stderr (a parse error says "parse error"; `error()` says "error (at …)"), so the
#              parse-error code stays 5 and this scenario is orthogonal to V.Q/56's.
#   FIXTURE    a file that is VALID JSON but violates the wire contract (no `content`), so
#              `_dm_digest`'s own `error("invalid dm object")` fires — the exact call whose exit
#              convention the classifier depends on — plus a healthy peer.
#   ⚠ BOTH SPELLINGS ARE PERMITTED, so the OUTCOME is asserted as a disjunction rather than
#              pinned. The map says "recording OR verifying", and the two diverge here:
#                · RECORD the probed error() code (7) and classify against it ⇒ the contract
#                  violator is quarantined and the peer delivers: failed/=1 read/=1 pending/=0.
#                · VERIFY error()==5, fail to establish it, and fail safe ⇒ EVERYTHING stays
#                  pending, nothing quarantined: failed/=0 read/=0 pending/=2.
#              Asserting either one alone would reject an implementation the map allows.
#   REJECTS    today's third outcome, which is neither: the engine proceeds as if nothing were
#              wrong — delivers the peer and leaves the contract violator cycling in pending/ as
#              a TRANSIENT failure, forever, exactly the H2/H3 shape one exit code over.
sc_probed_error_code_classifies_or_fails_safe() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  planted=$(plant_message "$fx" bravo "errcode-victim-seed-v121") \
    || { fail "prerequisite: could not queue the victim"; return 0; }
  run_brain "$fx" alpha dm @bravo "errcode-peer-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: the healthy peer" || return 0
  # valid JSON, invalid wire object — this is what makes _dm_digest call error(), not parse-fail.
  jq -cn '{from:"alpha",to:"bravo",ts:"errcode-victim-v121"}' > "$planted" \
    || { fail "fixture: could not write the contract-violating entry"; return 0; }
  need_count "$pd" 2 "prerequisite: one contract violator and one healthy peer" || return 0

  shim_dir="$base/jqerr-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  # SC2016 is the POINT here — see V.Q/56's identical note.
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '# A jq whose error() exits 7 while a PARSE error still exits 5. Orthogonal to the\n'
    printf '# V.Q/56 shim, which moves the parse code and leaves error() alone.\n'
    printf '_e="%s/jqerr-err.$$"\n' "$base"
    printf '"%s" "$@" 2>"$_e"\n' "$real_jq"
    printf '_rc=$?\n'
    printf 'cat "$_e" >&2 2>/dev/null\n'
    printf 'if [ "$_rc" = 5 ] && ! grep -q "parse error" "$_e" 2>/dev/null; then _rc=7; fi\n'
    printf 'rm -f "$_e" 2>/dev/null\n'
    printf 'exit "$_rc"\n'
  } > "$shim_dir/jq" || { fail "fixture: could not write the jq shim"; return 0; }
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  jq -n 'error("probe")' >/dev/null 2>&1
  err_rc=$?
  printf '{' > "$base/parse-probe.json" 2>/dev/null
  jq -e . "$base/parse-probe.json" >/dev/null 2>&1
  parse_rc=$?
  run_brain "$fx" bravo dm take
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac

  need_eq "$err_rc" 7 \
    "instrument check: with the shim on PATH jq's error() must exit 7 — otherwise this scenario says nothing about the error() contract" || return 0
  need_eq "$parse_rc" 5 \
    "instrument check: the PARSE-error code must be untouched at 5 — otherwise this is V.Q/56 again, not an independent error()-code scenario" || return 0

  q=$(count_files "$fd"); a=$(count_files "$rd"); p=$(count_files "$pd")
  if [ "$q" = 1 ] && [ "$a" = 1 ] && [ "$p" = 0 ]; then
    # RECORDED the probed error() code and classified against it.
    need_tree_has "$fd" "errcode-victim-v121" "the quarantined file must carry the offending bytes"
    need_file_has "$OUT" "errcode-peer-v121" "the healthy peer must deliver in the same invocation"
  elif [ "$q" = 0 ] && [ "$a" = 0 ] && [ "$p" = 2 ]; then
    # VERIFIED error()==5, could not establish it, failed safe to leave-everything-pending.
    need_tree_has "$pd" "errcode-victim-v121" "the contract violator must still be queued"
    need_tree_has "$pd" "errcode-peer-v121" "the healthy peer must still be queued"
  else
    fail "ruling 2: with a jq whose error() exits 7, the consume ended at failed/=$q read/=$a pending/=$p, which is NEITHER permitted outcome. The engine proceeded as if nothing were wrong — it delivered the healthy peer and left the contract-violating file cycling in pending/ as a TRANSIENT failure, forever. The map permits RECORDING the probed error() code (quarantine the violator, deliver the peer: failed/=1 read/=1 pending/=0) or VERIFYING it and failing safe (leave everything pending: failed/=0 read/=0 pending/=2) — never silently retrying a verdict it never established"
  fi
}

# V.Q/64 — the review's routed coverage gap: `_dm_pending_digest`'s rc 3 — structurally invalid
# AND the quarantine itself failed. Authority: ruling 1's invariant that quarantine requires
# PROOF plus v1.2's "leave valid messages retryable indefinitely"; a message that cannot be
# quarantined must stay in pending/, be diagnosed, and quarantine later once failed/ is writable.
#   INSTRUMENT `make_readonly_dir` — the existing helper, which carries its own root/blind control.
#              The mode is restored BEFORE any assertion can return early.
#   ⚠ BASELINE this is a GUARD, not a RED: today's engine already routes rc 3 correctly. It is
#              added because the pre-PR review routed the limb as UNCOVERED, and the v1.2.1
#              quarantine widening (ruling 1) sends far more traffic down it.
sc_unwritable_failed_leaves_invalid_pending() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  planted=$(plant_message "$fx" bravo "rc3-victim-seed-v121") \
    || { fail "prerequisite: could not queue the victim"; return 0; }
  run_brain "$fx" alpha dm @bravo "rc3-peer-v121"
  rc=$?
  need_rc "$rc" 0 "prerequisite: the healthy peer" || return 0
  printf '%s\n' '{rc3-structurally-invalid-v121' > "$planted" \
    || { fail "fixture: could not corrupt the victim"; return 0; }
  need_count "$pd" 2 "prerequisite: one corrupt entry and one healthy peer" || return 0

  make_readonly_dir "$fd"
  mrc=$?
  case "$mrc" in
    0) ;;
    2) fail "instrument blind: a rename into a 0500 failed/ still succeeds (running as root?)"; return 0 ;;
    *) fail "fixture: could not make failed/ read-only (rc=$mrc)"; return 0 ;;
  esac
  run_brain "$fx" bravo dm take
  chmod 755 "$fd" 2>/dev/null || true       # restore BEFORE any early return
  # The unwritable run's stderr must be kept: the retry below overwrites $ERR. [F5]
  blocked_err="$(dirname "$fx")/rc3-blocked.err"
  cp "$ERR" "$blocked_err" 2>/dev/null || : > "$blocked_err"
  blocked_diags=$(grep -E '^brain: ' "$blocked_err" 2>/dev/null | sort -u | wc -l | tr -d ' \n')

  need_tree_has "$pd" "rc3-structurally-invalid-v121" \
    "a message that could not be quarantined must stay in pending/ — an unwritable failed/ is a system fault, not a licence to destroy the evidence"
  need_count "$fd" 0 "failed/ while it was unwritable — nothing can have been routed there"
  need_file_has "$OUT" "rc3-peer-v121" \
    "the healthy peer must still deliver alongside a message that could not be quarantined (must-survive #3)"
  # [F5] A bare `stderr contains "brain: "` assertion does NOT pin the quarantine-FAILURE
  # diagnostic: `_dm_pending_digest` already warns "invalid dm object in <file>" BEFORE any
  # quarantine is attempted, so deleting the routing failure's own warn would still satisfy it.
  # Counting DISTINCT `^brain: ` lines separates them without pinning any wording — the
  # pre-quarantine warn is one line, and the failure must add at least one more.
  #   LIMITATION, declared: an engine that MERGES both reports into a single line would be
  #   rejected here. Every existing diagnostic in the engine is a one-line `_warn` per event, so
  #   that shape is not the house style — but if a GREEN legitimately merges them, challenge this
  #   assertion rather than contorting the engine.
  [ "$blocked_diags" -ge 2 ] \
    || fail "ruling 1's quarantine-requires-proof invariant is unreported: the run that could NOT quarantine emitted $blocked_diags distinct 'brain: ' diagnostic(s), which is only the pre-quarantine 'invalid dm object' warn. The routing FAILURE itself must be reported too, or a message sits in pending/ forever with nothing saying why"

  # retryable: once failed/ is writable the ordinary quarantine happens.
  run_brain "$fx" bravo dm take
  # CONTROL for the counter above: a run where quarantine SUCCEEDS still emits at least one
  # diagnostic, so ">= 2 on the blocked run" is "the failure added a report", not "the engine is
  # noisy". A zero here would mean the counter is measuring nothing.
  ok_diags=$(grep -E '^brain: ' "$ERR" 2>/dev/null | sort -u | wc -l | tr -d ' \n')
  [ "$ok_diags" -ge 1 ] \
    || fail "instrument check: a run whose quarantine SUCCEEDED emitted no 'brain: ' diagnostic at all, so the distinct-line counter above is not measuring the engine's reporting"
  need_count "$fd" 1 "failed/ after failed/ became writable again — the quarantine must be retried, not abandoned"
  need_tree_has "$fd" "rc3-structurally-invalid-v121" "the retried quarantine must carry the offending bytes"
  need_count "$pd" 0 "pending/ after the retry"
  need_count "$rd" 1 "read/ — exactly the one healthy peer, archived on the first pass"
}

# V.Q/65 — M1 (the fork-free empty-queue path). v1.1 paid ZERO DM jq forks on an empty-queue boot
# (`[ -n "$_dt_claims" ] || return 0` at 503519b); v1.2 runs `_dm_jq_preflight` BEFORE any
# emptiness check, so with a broken jq the warn fires on every boot with nothing to digest —
# permanently polluting .hook-errors.log and tripping cmd_status's banner — and `dm take` on an
# empty queue returns 1 where v1.1 returned 0.
#   INSTRUMENT the same wholly-broken jq shim shape as V.N/53. It is OBSERVABLE evidence of the
#              fork: if the empty path never consults jq, a broken jq cannot be noticed.
#   PRECISION  the engine has exactly TWO warnings mentioning jq (bin/brain:528 and :1189), both
#              of them this preflight, so "no jq in the diagnostics" is an exact test.
#   COVERS     both consume paths: `dm take` (stderr + rc contract) and SessionStart (the hook's
#              stderr lands in .brain/.hook-errors.log, which is what cmd_status's banner reads).
sc_empty_queue_does_not_consult_jq() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  hooklog="$fx/.brain/.hook-errors.log"

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: brain inbox ensures the queue tree" || return 0
  need_count "$(q_dir "$fx" bravo pending)" 0 "prerequisite: the queue is empty" || return 0
  before_loglines=$(line_count "$hooklog")

  shim_dir="$base/absent-jq-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'printf "jq: simulated incompatible build\\n" >&2\n'
    printf 'exit 3\n'
  } > "$shim_dir/jq" || { fail "fixture: could not write the jq shim"; return 0; }
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo dm take
  take_rc=$?
  take_err="$base/m1-take.err"
  cp "$ERR" "$take_err" 2>/dev/null || : > "$take_err"
  take_out_bytes=$(byte_size "$OUT")
  run_brain "$fx" bravo hook session-start
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  jq -e -n '1' >/dev/null 2>&1 \
    || { fail "instrument leak: the broken-jq shim survived the restore — every later scenario would be poisoned"; return 0; }

  need_rc "$take_rc" 0 \
    "M1: 'dm take' on an EMPTY queue must return 0 as it did in v1.1 — the rc contract of a no-op must not change with a dependency the no-op never needs"
  need_eq "$take_out_bytes" 0 "stdout bytes from an empty take"
  need_file_lacks "$take_err" "jq" \
    "M1: an empty queue must not consult jq at all — the preflight runs BEFORE any emptiness check, so a broken jq warns on every no-op"
  added=$(( $(line_count "$hooklog") - before_loglines ))
  if [ "$added" -gt 0 ]; then
    need_file_lacks "$hooklog" "jq" \
      "M1 on the boot path: an empty-queue SessionStart logged a jq diagnostic into .brain/.hook-errors.log — that pollutes the log permanently and trips cmd_status's banner on a lane with no mail"
  fi
}

# ═════════════════════ V.R — v1.2.2/v1.2.3 contract addenda (RED) ═════════════════════════

# V.R/67 — v1.2.2 ruling 7: enumeration failure is operation-fatal, never "empty" or "free".
# A 0300 state directory is searchable by exact path but cannot be enumerated. Each state is
# exercised against all three queue operations: mint, live take, and SessionStart consumption.
# The helper's positive control proves this is the ruling's exact permission shape, not a generic
# access failure. Permissions are restored before any assertion can return early.
sc_unreadable_state_is_operation_fatal() {
  for state in pending read failed; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    state_dir=$(q_dir "$fx" bravo "$state")
    hooklog="$fx/.brain/.hook-errors.log"
    marker="unreadable-$state-survivor-v122"

    run_brain "$fx" alpha dm @bravo "$marker"
    rc=$?
    need_rc "$rc" 0 "prerequisite: queue the $state-state survivor" || return 0
    need_count "$pd" 1 "prerequisite: exactly one survivor is pending" || return 0
    before_hook=$(line_count "$hooklog")

    make_unreadable_dir "$state_dir"
    mrc=$?
    case "$mrc" in
      0) ;;
      2) fail "instrument blind: a 0300 $state/ directory is still enumerable (running as root?)"; return 0 ;;
      *) fail "fixture: could not make $state/ unreadable-but-searchable (rc=$mrc)"; return 0 ;;
    esac

    run_brain "$fx" alpha dm @bravo "must-not-mint-through-unreadable-$state-v122"
    send_rc=$?
    send_err="$base/unreadable-$state-send.err"
    cp "$ERR" "$send_err" 2>/dev/null || : > "$send_err"

    run_brain "$fx" bravo dm take
    take_rc=$?
    take_err="$base/unreadable-$state-take.err"
    cp "$ERR" "$take_err" 2>/dev/null || : > "$take_err"

    run_brain "$fx" bravo hook session-start
    hook_out="$base/unreadable-$state-hook.out"
    cp "$OUT" "$hook_out" 2>/dev/null || : > "$hook_out"

    chmod 755 "$state_dir" 2>/dev/null || true  # restore BEFORE any early return
    hook_added="$base/unreadable-$state-hook-added.err"
    tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

    need_rc_nonzero "$send_rc" \
      "ruling 7 mint with unreadable $state/ — an unenumerable id state must never be reported free"
    need_file_has "$send_err" "brain:" \
      "ruling 7 mint with unreadable $state/ must diagnose the unestablishable queue state"
    need_rc_nonzero "$take_rc" \
      "ruling 7 dm take with unreadable $state/ — the operation must abort, not report success or empty"
    need_file_has "$take_err" "brain:" \
      "ruling 7 dm take with unreadable $state/ must emit a diagnostic"
    need_file_has "$hook_added" "brain:" \
      "ruling 7 SessionStart with unreadable $state/ must log a diagnostic instead of treating the queue as empty"
    need_file_lacks "$hook_out" "$marker" \
      "SessionStart must not consume while any queue state is unestablishable"
    need_count "$pd" 1 \
      "pending/ after mint, take, and SessionStart encountered unreadable $state/ — only the original survivor may remain"
    need_tree_has "$pd" "$marker" \
      "the original message must stay pending while $state/ cannot be enumerated"
    need_tree_lacks "$pd" "must-not-mint-through-unreadable-$state-v122" \
      "the mint attempted through unreadable $state/ must not create a queue entry"
    need_count "$rd" 0 "read/ while $state/ was unestablishable"
    need_count "$fd" 0 "failed/ while $state/ was unestablishable"
  done
}

# V.R/68 — v1.2.2 ruling 8: a path is an opaque byte string and never crosses `$( )`.
# The non-regular pending basename ends in a literal newline while failed/ contains its truncated
# twin. Command substitution strips that newline, making today's caller re-check the wrong,
# occupied path and retain the unusable entry forever. The compliant destination is the exact
# newline-bearing name, which is free and must arrive as the same directory entry.
sc_trailing_newline_path_reaches_quarantine() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "newline-path-peer-v122"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the healthy peer" || return 0

  truncated_name='00000001T000000Z-68'
  newline_name="$truncated_name
"
  mkdir "$pd/$newline_name" \
    || { fail "fixture: could not plant the trailing-newline directory entry"; return 0; }
  printf 'EARLIER-TRUNCATED-TWIN-v122\n' > "$fd/$truncated_name" \
    || { fail "fixture: could not occupy the truncated failed/ twin"; return 0; }
  before_twin=$(byte_size "$fd/$truncated_name")

  run_brain "$fx" bravo dm take
  rc=$?

  need_rc "$rc" 0 \
    "ruling 8 take — quarantining a trailing-newline pathname must not fail on its occupied truncated twin"
  need_file_has "$OUT" "newline-path-peer-v122" \
    "the healthy peer behind the non-regular entry must deliver in the same invocation"
  need_file "$fd/$truncated_name" "the occupied truncated failed/ twin"
  need_file_has "$fd/$truncated_name" "EARLIER-TRUNCATED-TWIN-v122" \
    "the occupied truncated twin must remain byte-intact"
  need_eq "$(byte_size "$fd/$truncated_name")" "$before_twin" \
    "the occupied truncated twin's byte size"
  need_real_dir "$fd/$newline_name" \
    "the quarantined directory entry under its byte-exact trailing-newline basename"
  need_file_absent "$pd/$newline_name" \
    "the trailing-newline entry must not remain pending forever"
  need_count "$fd" 2 "failed/ — the old twin plus the byte-distinct quarantined entry"
  need_count "$pd" 0 "pending/ after the peer and unusable entry are processed"
  need_count "$rd" 1 "read/ — exactly the healthy peer is archived"
}

# V.R/69 — v1.2.2 ruling 9: resolve jq once per consume operation and invoke that exact path
# throughout. The first PATH entry passes every probe, then removes itself during the final
# preflight call; an unpinned engine re-resolves the next PATH entry, whose digest failure copies
# the measured parse-error status and falsely quarantines a healthy message. No counter or
# cross-process coordination is used: the preflight's own distinctive argument triggers the swap.
sc_jq_identity_is_pinned_for_operation() {
  for mode in take hook; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    marker="jq-swap-$mode-healthy-v122"
    hooklog="$fx/.brain/.hook-errors.log"

    run_brain "$fx" alpha dm @bravo "$marker"
    rc=$?
    need_rc "$rc" 0 "prerequisite: queue the $mode jq-swap victim" || return 0
    need_count "$pd" 1 "prerequisite: one healthy jq-swap victim" || return 0

    real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
    printf '{' | "$real_jq" -e . >/dev/null 2>&1
    measured_parse_rc=$?
    [ "$measured_parse_rc" != 0 ] \
      || { fail "instrument: real jq parse failure unexpectedly returned success"; return 0; }

    first_dir="$base/jq-first-$mode-bin"
    next_dir="$base/jq-next-$mode-bin"
    mkdir -p "$first_dir" "$next_dir" \
      || { fail "fixture: could not create jq swap directories"; return 0; }
    # shellcheck disable=SC2016
    {
      printf '#!/usr/bin/env sh\n'
      printf 'case "$*" in *"dm preflight"*) rm -f -- "$0" || exit 97 ;; esac\n'
      printf 'exec "%s" "$@"\n' "$real_jq"
    } > "$first_dir/jq" || { fail "fixture: could not write the probed jq shim"; return 0; }
    {
      printf '#!/usr/bin/env sh\n'
      printf 'printf "jq: simulated post-preflight replacement\\n" >&2\n'
      printf 'exit %s\n' "$measured_parse_rc"
    } > "$next_dir/jq" || { fail "fixture: could not write the replacement jq shim"; return 0; }
    chmod +x "$first_dir/jq" "$next_dir/jq" \
      || { fail "fixture: could not make jq swap shims executable"; return 0; }

    before_hook=$(line_count "$hooklog")
    saved_path=$PATH
    PATH="$first_dir:$next_dir:$PATH"; export PATH
    if [ "$mode" = take ]; then
      run_brain "$fx" bravo dm take
      op_rc=$?
      op_err="$base/jq-swap-take.err"
      cp "$ERR" "$op_err" 2>/dev/null || : > "$op_err"
    else
      run_brain "$fx" bravo hook session-start
      op_rc=$?
      op_err="$base/jq-swap-hook.err"
      tail -n "+$((before_hook + 1))" "$hooklog" > "$op_err" 2>/dev/null || : > "$op_err"
    fi
    resolved_after=$(command -v jq)
    jq -e -n '1' >/dev/null 2>&1
    replacement_rc=$?
    PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
    case "$(command -v jq)" in
      "$first_dir"/*|"$next_dir"/*)
        fail "instrument leak: a jq swap shim is STILL what PATH resolves after the restore"; return 0 ;;
    esac

    need_file_absent "$first_dir/jq" \
      "instrument: the probed jq must remove itself on the final preflight call" || return 0
    need_eq "$resolved_after" "$next_dir/jq" \
      "instrument: an unpinned post-preflight jq lookup must resolve the hostile replacement" || return 0
    need_eq "$replacement_rc" "$measured_parse_rc" \
      "instrument: the replacement must return the probed parse-error status" || return 0

    if [ "$mode" = take ]; then
      need_rc_nonzero "$op_rc" \
        "ruling 9 dm take must fail safe when its pinned jq disappears after preflight"
    else
      need_rc "$op_rc" 0 "SessionStart hook wrapper status contract"
    fi
    need_file_has "$op_err" "brain:" \
      "ruling 9 $mode path must diagnose the post-preflight dependency mismatch"
    need_count "$fd" 0 \
      "failed/ after the PATH-resolved jq changed — a mismatch is never proof that this healthy message is invalid"
    need_count "$rd" 0 \
      "read/ after the pinned jq disappeared before digest"
    need_count "$pd" 1 \
      "pending/ after the jq identity changed — fail-safe is leave-pending"
    need_tree_has "$pd" "$marker" "the healthy message must remain retryable after the jq swap"

    run_brain "$fx" bravo dm take
    retry_rc=$?
    need_rc "$retry_rc" 0 "retry with the ordinary jq restored" || return 0
    need_file_has "$OUT" "$marker" "the healthy message must deliver once jq is stable again"
    need_count "$pd" 0 "pending/ after the stable-jq retry"
    need_count "$rd" 1 "read/ after the stable-jq retry"
    need_count "$fd" 0 "failed/ after the stable-jq retry"
  done
}

# V.R/70 — ruling 8's DM-surface sweep: lane identities and recipient slugs become path
# components, so they also must not cross command substitution. A trailing newline in inherited
# BRAIN_FEATURE must remain invalid instead of truncating to another lane; likewise a hostile
# presence basename must not truncate into a valid broadcast destination. Literal multiline
# assignments preserve the byte under test without using `$( )` in the fixture itself.
sc_lane_components_never_cross_command_substitution() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)
  hooklog="$fx/.brain/.hook-errors.log"

  run_brain "$fx" alpha dm @bravo "identity-newline-survivor-v122"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the identity victim" || return 0
  before_hook=$(line_count "$hooklog")

  bad_identity="bravo
"
  run_brain "$fx" "$bad_identity" dm take
  take_rc=$?
  take_err="$base/newline-identity-take.err"
  cp "$ERR" "$take_err" 2>/dev/null || : > "$take_err"
  run_brain "$fx" "$bad_identity" hook session-start
  hook_out="$base/newline-identity-hook.out"
  cp "$OUT" "$hook_out" 2>/dev/null || : > "$hook_out"
  hook_added="$base/newline-identity-hook.err"
  tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

  need_rc_nonzero "$take_rc" \
    "ruling 8: a trailing-newline BRAIN_FEATURE must remain invalid, not truncate to @bravo"
  need_file_has "$take_err" "brain:" \
    "the invalid trailing-newline take identity must be diagnosed"
  need_file_has "$hook_added" "brain:" \
    "the invalid trailing-newline SessionStart identity must be diagnosed"
  need_file_lacks "$hook_out" "identity-newline-survivor-v122" \
    "SessionStart under a byte-distinct identity must not consume @bravo's message"
  need_count "$pd" 1 \
    "@bravo pending/ after take and SessionStart under the byte-distinct identity"
  need_tree_has "$pd" "identity-newline-survivor-v122" \
    "@bravo's message must remain pending after the invalid identity attempts"
  need_count "$rd" 0 "@bravo read/ after the invalid identity attempts"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "retry under the byte-exact @bravo identity" || return 0
  need_file_has "$OUT" "identity-newline-survivor-v122" \
    "the intended recipient must still be able to consume the retained message"

  bad_recipient="charlie
"
  write_presence "$fx" "$bad_recipient" active \
    || { fail "fixture: could not plant the trailing-newline presence basename"; return 0; }
  run_brain "$fx" alpha dm @all "broadcast-newline-recipient-v122"
  broadcast_rc=$?

  need_rc_nonzero "$broadcast_rc" \
    "ruling 8: broadcast must report the byte-invalid presence recipient instead of truncating it to @charlie"
  need_file_absent "$fx/.brain/dm/charlie" \
    "a trailing-newline presence basename must not create the truncated @charlie queue"
  need_file_absent "$fx/.brain/dm/$bad_recipient" \
    "the invalid trailing-newline recipient must not create a queue either"
  need_count "$pd" 1 "the one valid broadcast recipient must still receive the message"
  need_tree_has "$pd" "broadcast-newline-recipient-v122" \
    "the valid peer must receive the partial broadcast"
}

# V.R/71 — v1.2.2 ruling 9's same-executable RE-PROBE and operation-wide abort. The shim
# overwrites its own bytes (without changing its resolvable path) on the final preflight probe.
# Digestion then returns the RECORDED parse status, forcing `_dm_jq_contract_holds`; the hostile
# replacement fails the capability probe, so neither entry is evidence for quarantine. One
# systemic failure aborts the batch and emits one diagnostic naming the pinned executable.
sc_jq_contract_reprobe_aborts_batch() {
  for mode in take hook; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    hooklog="$fx/.brain/.hook-errors.log"
    marker1="jq-reprobe-$mode-one-v122"
    marker2="jq-reprobe-$mode-two-v122"

    run_brain "$fx" alpha dm @bravo "$marker1"
    rc=$?
    need_rc "$rc" 0 "prerequisite: queue the first $mode contract-reprobe victim" || return 0
    run_brain "$fx" alpha dm @bravo "$marker2"
    rc=$?
    need_rc "$rc" 0 "prerequisite: queue the second $mode contract-reprobe victim" || return 0
    need_count "$pd" 2 "prerequisite: two healthy contract-reprobe victims" || return 0

    real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
    printf '{' | "$real_jq" -e . >/dev/null 2>&1
    measured_parse_rc=$?
    [ "$measured_parse_rc" != 0 ] \
      || { fail "instrument: real jq parse failure unexpectedly returned success"; return 0; }

    shim_dir="$base/jq-reprobe-$mode-bin"
    mkdir -p "$shim_dir" || { fail "fixture: could not create the jq re-probe shim directory"; return 0; }
    {
      printf '#!/usr/bin/env sh\n'
      printf 'exit %s\n' "$measured_parse_rc"
    } > "$shim_dir/hostile" || { fail "fixture: could not write the hostile jq replacement"; return 0; }
    # One physical line makes the overwrite + current real-jq exec indivisible from the shell
    # parser's perspective; the next invocation reads the hostile bytes from the same path.
    # shellcheck disable=SC2016
    {
      printf '#!/usr/bin/env sh\n'
      printf 'case "$*" in *"dm preflight"*) cp "%s" "$0" || exit 97; chmod +x "$0" || exit 97; exec "%s" "$@" ;; esac\n' \
        "$shim_dir/hostile" "$real_jq"
      printf 'exec "%s" "$@"\n' "$real_jq"
    } > "$shim_dir/jq" || { fail "fixture: could not write the jq re-probe shim"; return 0; }
    chmod +x "$shim_dir/jq" "$shim_dir/hostile" \
      || { fail "fixture: could not make the jq re-probe shim executable"; return 0; }

    before_hook=$(line_count "$hooklog")
    saved_path=$PATH
    PATH="$shim_dir:$PATH"; export PATH
    if [ "$mode" = take ]; then
      run_brain "$fx" bravo dm take
      op_rc=$?
      op_err="$base/jq-reprobe-take.err"
      cp "$ERR" "$op_err" 2>/dev/null || : > "$op_err"
    else
      run_brain "$fx" bravo hook session-start
      op_rc=$?
      op_err="$base/jq-reprobe-hook.err"
      tail -n "+$((before_hook + 1))" "$hooklog" > "$op_err" 2>/dev/null || : > "$op_err"
    fi
    resolved_after=$(command -v jq)
    jq -e -n '1' >/dev/null 2>&1
    hostile_rc=$?
    PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
    case "$(command -v jq)" in
      "$shim_dir"/*)
        fail "instrument leak: the self-overwriting jq shim is STILL what PATH resolves after the restore"; return 0 ;;
    esac

    need_eq "$resolved_after" "$shim_dir/jq" \
      "instrument: the overwritten jq must remain resolvable at the exact pinned path" || return 0
    need_eq "$hostile_rc" "$measured_parse_rc" \
      "instrument: the overwritten jq must return the recorded parse-error status" || return 0
    if [ "$mode" = take ]; then
      need_rc_nonzero "$op_rc" "ruling 9 take must fail safe on a changed jq contract"
    else
      need_rc "$op_rc" 0 "SessionStart hook wrapper status contract"
    fi
    contract_warns=$(grep -cF 'jq contract changed during dm consume' "$op_err" 2>/dev/null)
    need_eq "$contract_warns" 1 \
      "ruling 9 $mode path must emit exactly one contract-changed warning for the whole batch"
    need_file_has "$op_err" "$shim_dir/jq" \
      "the contract-changed warning must name the pinned jq executable"
    need_count "$pd" 2 "pending/ after the systemic jq mismatch — the whole batch stays retryable"
    need_count "$rd" 0 "read/ after the systemic jq mismatch"
    need_count "$fd" 0 "failed/ after the systemic jq mismatch — a changed contract proves no message invalid"

    run_brain "$fx" bravo dm take
    retry_rc=$?
    need_rc "$retry_rc" 0 "retry after restoring a stable jq" || return 0
    need_file_has "$OUT" "$marker1" "the first retained message must deliver on retry"
    need_file_has "$OUT" "$marker2" "the second retained message must deliver on retry"
    need_count "$pd" 0 "pending/ after the stable-jq retry"
    need_count "$rd" 2 "read/ after the stable-jq retry"
    need_count "$fd" 0 "failed/ after the stable-jq retry"
  done
}

# V.R/75 — ruling 10's operation-wide half: a systemic jq failure invalidates every digest
# staged by this SessionStart batch, including entries digested successfully before the failure.
# The pinned shim digests the first entry normally, returns the recorded parse status for the
# second, fails the same-executable contract re-probe, then reports serialization success with
# `{}`. It captures the serializer's actual context argument so an unfixed hook cannot hide the
# staged first digest behind that empty-looking output while still archiving its message.
sc_hook_discards_staged_batch_on_systemic_jq_failure() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  hooklog="$fx/.brain/.hook-errors.log"
  marker1="jq-systemic-hook-one-v123"
  marker2="jq-systemic-hook-two-v123"

  run_brain "$fx" alpha dm @bravo "$marker1"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the first staged-batch victim" || return 0
  run_brain "$fx" alpha dm @bravo "$marker2"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the second staged-batch victim" || return 0
  need_count "$pd" 2 "prerequisite: two healthy staged-batch victims" || return 0

  first_pending=$(first_file "$pd") \
    || { fail "fixture: could not resolve the first pending entry"; return 0; }
  if grep -qF -- "$marker1" "$first_pending" 2>/dev/null; then
    first_marker=$marker1
  elif grep -qF -- "$marker2" "$first_pending" 2>/dev/null; then
    first_marker=$marker2
  else
    fail "fixture: the first pending entry carries neither staged-batch marker"
    return 0
  fi

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  printf '{' | "$real_jq" -e . >/dev/null 2>&1
  measured_parse_rc=$?
  [ "$measured_parse_rc" != 0 ] \
    || { fail "instrument: real jq parse failure unexpectedly returned success"; return 0; }

  shim_dir="$base/jq-systemic-hook-bin"
  shim_state="$base/jq-systemic-hook.state"
  payload_log="$base/jq-systemic-hook.payload"
  mkdir -p "$shim_dir" \
    || { fail "fixture: could not create the staged-batch jq shim directory"; return 0; }
  # The shim is stable at one path for the whole operation. It captures `--arg c` byte-for-byte,
  # counts only `--arg id` digest calls, and fails every post-second-digest capability probe.
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf '_state="%s"\n' "$shim_state"
    printf '_payload="%s"\n' "$payload_log"
    printf '_n=0; [ ! -f "$_state" ] || _n=$(sed -n "1p" "$_state" 2>/dev/null)\n'
    printf 'case "$_n" in ""|*[!0-9]*) _n=0 ;; esac\n'
    printf '_prev=""; _capture=0; _digest=0\n'
    printf 'for _arg in "$@"; do\n'
    printf '  if [ "$_capture" = 1 ]; then printf "%%s" "$_arg" > "$_payload" || exit 96; printf "{}\\n"; exit 0; fi\n'
    printf '  if [ "$_prev" = "--arg" ] && [ "$_arg" = "c" ]; then _capture=1; fi\n'
    printf '  if [ "$_prev" = "--arg" ] && [ "$_arg" = "id" ]; then _digest=1; fi\n'
    printf '  _prev=$_arg\n'
    printf 'done\n'
    printf 'if [ "$_digest" = 1 ]; then _n=$((_n + 1)); printf "%%s\\n" "$_n" > "$_state" || exit 95; [ "$_n" = 1 ] || exit %s; fi\n' "$measured_parse_rc"
    printf '[ "$_n" -lt 2 ] || exit 97\n'
    printf 'exec "%s" "$@"\n' "$real_jq"
  } > "$shim_dir/jq" || { fail "fixture: could not write the staged-batch jq shim"; return 0; }
  chmod +x "$shim_dir/jq" \
    || { fail "fixture: could not make the staged-batch jq shim executable"; return 0; }

  before_hook=$(line_count "$hooklog")
  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo hook session-start
  hook_rc=$?
  jq -e -n '1' >/dev/null 2>&1
  hostile_rc=$?
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*)
      fail "instrument leak: the staged-batch jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  hook_added="$base/jq-systemic-hook.err"
  tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

  need_eq "$(sed -n '1p' "$shim_state" 2>/dev/null)" 2 \
    "instrument: exactly two digest invocations must precede the systemic re-probe failure" || return 0
  need_eq "$hostile_rc" 97 \
    "instrument: the pinned jq must remain systemically unsafe after the second digest" || return 0
  need_file "$payload_log" \
    "instrument: the jq shim must capture the SessionStart serializer's context argument" || return 0
  need_rc "$hook_rc" 0 "SessionStart hook wrapper status contract"
  contract_warns=$(grep -cF 'jq contract changed during dm consume' "$hook_added" 2>/dev/null)
  need_eq "$contract_warns" 1 \
    "ruling 10: the systemic hook failure must warn exactly once for the whole batch"
  need_file_has "$hook_added" "$shim_dir/jq" \
    "the systemic warning must name the pinned jq executable"
  need_file_lacks "$payload_log" "$first_marker" \
    "the SessionStart serializer must not receive a digest staged before the operation became unsafe"
  need_count "$pd" 2 "pending/ after the systemic hook failure — the entire staged batch stays retryable"
  need_count "$rd" 0 "read/ after the systemic hook failure — no archive may rest on the unsafe operation"
  need_count "$fd" 0 "failed/ after the systemic hook failure"

  run_brain "$fx" bravo hook session-start
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq SessionStart retry" || return 0
  need_file_has "$OUT" "$marker1" "the first retained message must deliver on stable-jq retry"
  need_file_has "$OUT" "$marker2" "the second retained message must deliver on stable-jq retry"
  need_count "$pd" 0 "pending/ after the stable-jq retry"
  need_count "$rd" 2 "read/ after the stable-jq retry"
  need_count "$fd" 0 "failed/ after the stable-jq retry"
}

# V.R/72 — v1.2.3 ruling 10: SessionStart's serializer is part of the pinned operation. The
# preflight executable removes itself only AFTER producing the final digest; the next PATH jq
# exits 0 with zero bytes. Re-resolving that replacement would make an empty emit look successful
# and archive the undelivered message. Pinned/verified emit leaves it pending and warns once.
sc_session_emit_is_pinned_and_nonempty() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  hooklog="$fx/.brain/.hook-errors.log"
  marker="empty-emit-swap-survivor-v123"

  run_brain "$fx" alpha dm @bravo "$marker"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the empty-emit swap victim" || return 0

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  first_dir="$base/jq-emit-first-bin"
  next_dir="$base/jq-emit-next-bin"
  mkdir -p "$first_dir" "$next_dir" \
    || { fail "fixture: could not create the emit-swap shim directories"; return 0; }
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf 'case "$*" in *"--arg id"*) rm -f "$0" || exit 97 ;; esac; exec "%s" "$@"\n' "$real_jq"
  } > "$first_dir/jq" || { fail "fixture: could not write the digest jq shim"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'exit 0\n'
  } > "$next_dir/jq" || { fail "fixture: could not write the empty jq replacement"; return 0; }
  chmod +x "$first_dir/jq" "$next_dir/jq" \
    || { fail "fixture: could not make the emit-swap shims executable"; return 0; }

  before_hook=$(line_count "$hooklog")
  saved_path=$PATH
  PATH="$first_dir:$next_dir:$PATH"; export PATH
  run_brain "$fx" bravo hook session-start
  hook_rc=$?
  resolved_after=$(command -v jq)
  jq -n '1' > "$base/empty-jq.out" 2>/dev/null
  empty_rc=$?
  empty_bytes=$(byte_size "$base/empty-jq.out")
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$first_dir"/*|"$next_dir"/*)
      fail "instrument leak: an emit-swap jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  hook_added="$base/empty-emit-hook.err"
  tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

  need_file_absent "$first_dir/jq" \
    "instrument: the probed jq must remove itself only after the digest invocation" || return 0
  need_eq "$resolved_after" "$next_dir/jq" \
    "instrument: a post-digest bare jq lookup must resolve the empty replacement" || return 0
  need_eq "$empty_rc" 0 "instrument: the replacement jq must report success" || return 0
  need_eq "$empty_bytes" 0 "instrument: the replacement jq must emit zero bytes" || return 0
  need_rc "$hook_rc" 0 "SessionStart hook wrapper status contract"
  emit_warns=$(grep -c '^brain:' "$hook_added" 2>/dev/null)
  need_eq "$emit_warns" 1 "ruling 10: a failed/zero-byte SessionStart emit must warn exactly once"
  need_file_has "$hook_added" "emit" "the one warning must diagnose the failed SessionStart emit"
  need_count "$pd" 1 "pending/ after the post-digest emit swap"
  need_tree_has "$pd" "$marker" "the un-emitted message must remain retryable"
  need_count "$rd" 0 "read/ after a zero-byte SessionStart emit"
  need_count "$fd" 0 "failed/ after a zero-byte SessionStart emit"

  run_brain "$fx" bravo hook session-start
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq SessionStart retry" || return 0
  need_file_has "$OUT" "$marker" "the retained message must deliver once jq is stable"
  need_count "$pd" 0 "pending/ after the stable-jq emit retry"
  need_count "$rd" 1 "read/ after the stable-jq emit retry"
  need_count "$fd" 0 "failed/ after the stable-jq emit retry"
}

# V.R/73 — v1.2.3 ruling 11: every collision suffix is byte-checked. An operation-local wrapper
# exports its pid before execing the engine; the date shim uses it to choose a stamp making the FIRST
# collision candidate exactly NAME_MAX bytes, then occupies it. Appending `-1` would be overlong;
# the engine must switch to the compact checksum form and quarantine the non-regular entry there.
sc_collision_suffix_rechecks_name_max() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); fd=$(q_dir "$fx" bravo failed)
  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the collision fixture tree" || return 0

  near_name=$(printf '%220s' '' | tr ' ' n)
  near_bytes=$(LC_ALL=C printf '%s' "$near_name" | wc -c | tr -d ' \n')
  need_eq "$near_bytes" 220 "instrument: near-cap hostile basename size" || return 0
  mkdir "$pd/$near_name" \
    || { fail "fixture: could not plant the near-cap non-regular pending entry"; return 0; }
  printf 'EXACT-TWIN-MUST-SURVIVE-v123\n' > "$fd/$near_name" \
    || { fail "fixture: could not occupy the exact failed/ twin"; return 0; }

  real_date=$(command -v date) || { fail "fixture: cannot locate the real date"; return 0; }
  shim_dir="$base/name-max-date-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the NAME_MAX date shim directory"; return 0; }
  source_brain=$BRAIN_BIN
  wrapper_brain="$base/name-max-brain"
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf 'T6_BRAIN_PID=$$; export T6_BRAIN_PID\n'
    printf 'exec "%s" "$@"\n' "$source_brain"
  } > "$wrapper_brain" || { fail "fixture: could not write the NAME_MAX engine wrapper"; return 0; }
  chmod +x "$wrapper_brain" \
    || { fail "fixture: could not make the NAME_MAX engine wrapper executable"; return 0; }
  T6_FAILED_DIR=$fd
  T6_NAME=$near_name
  T6_LOG="$base/name-max-candidate.log"
  export T6_FAILED_DIR T6_NAME T6_LOG
  # shellcheck disable=SC2016
  {
    printf '#!/usr/bin/env sh\n'
    printf 'case "$*" in\n'
    printf '  *"+%%s"*)\n'
    printf '    brain_pid=${T6_BRAIN_PID:-}\n'
    printf '    case "$brain_pid" in ""|*[!0-9]*) exit 96 ;; esac\n'
    printf '    stamp_len=$((255 - ${#T6_NAME} - 12 - ${#brain_pid}))\n'
    printf '    [ "$stamp_len" -gt 0 ] || exit 95\n'
    printf '    stamp=""; i=0; while [ "$i" -lt "$stamp_len" ]; do stamp="${stamp}7"; i=$((i + 1)); done\n'
    printf '    candidate="$T6_FAILED_DIR/$T6_NAME.collision-$stamp-$brain_pid"\n'
    printf '    printf "FIRST-CANDIDATE-MUST-SURVIVE-v123\\n" > "$candidate" || exit 94\n'
    printf '    printf "%%s\\n" "$candidate" > "$T6_LOG" || exit 93\n'
    printf '    printf "%%s\\n" "$stamp"; exit 0 ;;\n'
    printf 'esac\n'
    printf 'exec "%s" "$@"\n' "$real_date"
  } > "$shim_dir/date" || { fail "fixture: could not write the NAME_MAX date shim"; return 0; }
  chmod +x "$shim_dir/date" \
    || { fail "fixture: could not make the NAME_MAX date shim executable"; return 0; }

  saved_path=$PATH
  saved_brain_bin=$BRAIN_BIN
  BRAIN_BIN=$wrapper_brain
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo dm take
  take_rc=$?
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  BRAIN_BIN=$saved_brain_bin
  unset T6_FAILED_DIR T6_NAME T6_LOG
  case "$(command -v date)" in
    "$shim_dir"/*)
      fail "instrument leak: the NAME_MAX date shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  need_eq "$BRAIN_BIN" "$source_brain" \
    "instrument leak: the NAME_MAX engine wrapper survived the restore" || return 0

  need_file "$base/name-max-candidate.log" \
    "instrument: the date shim must record the occupied first collision candidate" || return 0
  first_candidate=$(sed -n '1p' "$base/name-max-candidate.log")
  first_base=${first_candidate##*/}
  first_bytes=$(LC_ALL=C printf '%s' "$first_base" | wc -c | tr -d ' \n')
  need_eq "$first_bytes" 255 \
    "instrument: the occupied first collision candidate must be exactly NAME_MAX bytes" || return 0
  need_real_file "$first_candidate" "the occupied first collision candidate" || return 0
  need_file_has "$first_candidate" "FIRST-CANDIDATE-MUST-SURVIVE-v123" \
    "the occupied first collision candidate must remain byte-intact"
  need_file_has "$fd/$near_name" "EXACT-TWIN-MUST-SURVIVE-v123" \
    "the occupied exact failed/ twin must remain byte-intact"
  need_rc "$take_rc" 0 \
    "ruling 11: quarantine must recover from an overlong next suffix via the compact form"
  need_file_absent "$pd/$near_name" \
    "the proven-invalid near-cap entry must not remain pending after its suffix exceeds NAME_MAX"

  compact_dir=""
  for candidate in "$fd"/collision-*; do
    [ -d "$candidate" ] && [ ! -L "$candidate" ] || continue
    compact_dir=$candidate
    break
  done
  [ -n "$compact_dir" ] \
    || { fail "ruling 11: no compact checksum-form quarantine destination was created"; return 0; }
  compact_base=${compact_dir##*/}
  compact_bytes=$(LC_ALL=C printf '%s' "$compact_base" | wc -c | tr -d ' \n')
  [ "$compact_bytes" -le 255 ] \
    || fail "ruling 11: compact quarantine basename is $compact_bytes bytes, exceeds NAME_MAX"
  need_count "$pd" 0 "pending/ after compact collision quarantine"
  need_count "$fd" 3 "failed/ — exact twin, occupied first candidate, and compact quarantine"
}

# V.R/74 — v1.2.3 ruling 12: every hidden child except the atomic-send `.tmp-*` namespace is a
# queue entry. Exercise both consume loops with a healthy peer, then a hidden-only queue to pin
# `_dm_dir_has_entries`; `.poison` is quarantined by the existing invalid-name classification,
# while `.tmp-*` remains untouched and does not keep the queue logically non-empty.
sc_hidden_pending_entries_are_classified() {
  for mode in take hook; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    marker="hidden-peer-$mode-v123"
    poison="hidden-poison-$mode-v123"
    temp="hidden-temp-$mode-v123"

    run_brain "$fx" alpha dm @bravo "$marker"
    rc=$?
    need_rc "$rc" 0 "prerequisite: queue the healthy $mode hidden-entry peer" || return 0
    printf '{"from":"mallory","to":"bravo","ts":"x","content":"%s"}\n' "$poison" \
      > "$pd/.poison" || { fail "fixture: could not plant pending/.poison"; return 0; }
    printf '%s\n' "$temp" > "$pd/.tmp-inflight-v123" \
      || { fail "fixture: could not plant the protected .tmp-* entry"; return 0; }
    temp_bytes=$(byte_size "$pd/.tmp-inflight-v123")

    if [ "$mode" = take ]; then
      run_brain "$fx" bravo dm take
      op_rc=$?
    else
      run_brain "$fx" bravo hook session-start
      op_rc=$?
    fi

    need_rc "$op_rc" 0 "$mode consume with a foreign dot entry and healthy peer"
    need_file_has "$OUT" "$marker" "the healthy peer must deliver through the $mode loop"
    need_file_absent "$pd/.poison" "the foreign dot entry must leave pending/"
    need_real_file "$fd/.poison" "the foreign dot entry quarantined under its exact basename"
    need_file_has "$fd/.poison" "$poison" "the quarantined foreign dot entry must retain its bytes"
    need_file "$pd/.tmp-inflight-v123" "the protected atomic-send staging entry"
    need_file_has "$pd/.tmp-inflight-v123" "$temp" "the .tmp-* staging entry must remain untouched"
    need_eq "$(byte_size "$pd/.tmp-inflight-v123")" "$temp_bytes" \
      "the .tmp-* staging entry's byte size"
    need_count "$pd" 0 "visible pending queue after hidden classification and peer delivery"
    need_eq "$(count_dotfiles "$pd")" 1 \
      "only the sanctioned .tmp-* hidden entry may remain in pending/"
    need_count "$rd" 1 "read/ after the healthy hidden-entry peer delivers"
    need_count "$fd" 0 "visible failed/ entries after pending/.poison is classified"
    need_eq "$(count_dotfiles "$fd")" 1 "failed/ must contain exactly the quarantined .poison"

    run_brain "$fx" bravo status
    status_rc=$?
    need_rc "$status_rc" 0 "brain status after the $mode path quarantines a dot-named entry"
    need_file_has "$OUT" '⚠ 1 DM message(s) failed structural validation' \
      "the failed-DM banner must count the quarantined dot-named entry"

    run_brain "$fx" bravo dm take
    empty_rc=$?
    need_rc "$empty_rc" 0 "queue with only .tmp-* remaining must read empty"
    need_eq "$(byte_size "$OUT")" 0 "stdout from a queue containing only .tmp-*"
    need_file "$pd/.tmp-inflight-v123" ".tmp-* must survive the empty-queue probe"
  done

  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); fd=$(q_dir "$fx" bravo failed)
  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the hidden-only queue tree" || return 0
  printf '{"from":"mallory","to":"bravo","ts":"x","content":"hidden-only-poison-v123"}\n' \
    > "$pd/.poison" || { fail "fixture: could not plant the hidden-only poison"; return 0; }
  printf 'hidden-only-temp-v123\n' > "$pd/.tmp-hidden-only-v123" \
    || { fail "fixture: could not plant the hidden-only temp"; return 0; }

  run_brain "$fx" bravo dm take
  hidden_only_rc=$?
  need_rc "$hidden_only_rc" 0 \
    "_dm_dir_has_entries must report a foreign dot child as work, not established-empty"
  need_file_absent "$pd/.poison" "the hidden-only foreign entry must be classified"
  need_real_file "$fd/.poison" "the hidden-only foreign entry quarantined into failed/"
  need_file "$pd/.tmp-hidden-only-v123" "the hidden-only .tmp-* entry must remain untouched"
  need_count "$pd" 0 "visible pending queue after hidden-only classification"
  need_eq "$(count_dotfiles "$pd")" 1 "only .tmp-* may remain after the hidden-only scan"
}

# ═══════════════════ V.U — v1.2.4 structural payload witnesses (RED) ════════════════════

# V.U/76 — ruling 13, W1: an rc-0 digest is provisional. This same-path shim passes every jq
# capability probe and answers only the `--arg id` payload call with `{}`. The cheap witness must
# classify that as systemic, leave the message pending, emit exactly one warning naming the
# pinned binary, and allow an ordinary-jq retry to deliver.
sc_rc0_empty_digest_is_systemic() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  marker="rc0-empty-digest-survivor-v124"

  run_brain "$fx" alpha dm @bravo "$marker"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the rc-0 empty-digest victim" || return 0
  need_count "$pd" 1 "prerequisite: one empty-digest victim is pending" || return 0

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  shim_dir="$base/jq-empty-digest-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the digest shim directory"; return 0; }
  write_rc0_empty_payload_jq "$shim_dir/jq" "$real_jq" id \
    || { fail "fixture: could not write the rc-0 empty-digest jq shim"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo dm take
  take_rc=$?
  take_out="$base/rc0-empty-digest.out"; take_err="$base/rc0-empty-digest.err"
  cp "$OUT" "$take_out" 2>/dev/null || : > "$take_out"
  cp "$ERR" "$take_err" 2>/dev/null || : > "$take_err"
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the digest jq shim is STILL resolved after restore"; return 0 ;;
  esac

  need_rc_nonzero "$take_rc" "ruling 13 take must fail on an rc-0 digest lacking its id"
  need_eq "$(byte_size "$take_out")" 0 "stdout from the rejected rc-0 digest"
  digest_warns=$(grep -c '^brain:' "$take_err" 2>/dev/null)
  need_eq "$digest_warns" 1 "ruling 13 digest witness must warn exactly once"
  need_file_has "$take_err" "$shim_dir/jq" "the digest witness warning must name the pinned jq binary"
  need_count "$pd" 1 "pending/ after the rc-0 digest witness fails"
  need_tree_has "$pd" "$marker" "the rejected digest must remain retryable"
  need_count "$rd" 0 "read/ after the rc-0 digest witness fails"
  need_count "$fd" 0 "failed/ after the systemic rc-0 digest failure"

  run_brain "$fx" bravo dm take
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq retry after the rc-0 digest failure" || return 0
  need_file_has "$OUT" "$marker" "the retained digest victim must deliver on stable-jq retry"
  need_count "$pd" 0 "pending/ after the stable-jq digest retry"
  need_count "$rd" 1 "read/ after the stable-jq digest retry"
  need_count "$fd" 0 "failed/ after the stable-jq digest retry"
}

# V.U/77 — ruling 13, W2: the pinned SessionStart envelope must contain the first staged id.
# Digestion remains real; only the `--arg c` envelope call returns `{}` rc 0. No byte may be
# emitted or archived on that provisional success, and the stable-jq retry must deliver.
sc_rc0_empty_session_envelope_is_rejected() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  hooklog="$fx/.brain/.hook-errors.log"
  marker="rc0-empty-envelope-survivor-v124"

  run_brain "$fx" alpha dm @bravo "$marker"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the rc-0 empty-envelope victim" || return 0
  pending_file=$(first_file "$pd") \
    || { fail "fixture: could not resolve the empty-envelope victim"; return 0; }
  pending_id=${pending_file##*/}

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  shim_dir="$base/jq-empty-envelope-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the envelope shim directory"; return 0; }
  write_rc0_empty_payload_jq "$shim_dir/jq" "$real_jq" c \
    || { fail "fixture: could not write the rc-0 empty-envelope jq shim"; return 0; }

  before_hook=$(line_count "$hooklog")
  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo hook session-start
  hook_rc=$?
  hook_out="$base/rc0-empty-envelope.out"
  cp "$OUT" "$hook_out" 2>/dev/null || : > "$hook_out"
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the envelope jq shim is STILL resolved after restore"; return 0 ;;
  esac
  hook_added="$base/rc0-empty-envelope.err"
  tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

  need_rc "$hook_rc" 0 "SessionStart hook wrapper status contract"
  need_eq "$(byte_size "$hook_out")" 0 "stdout from the rejected rc-0 SessionStart envelope"
  envelope_warns=$(grep -c '^brain:' "$hook_added" 2>/dev/null)
  need_eq "$envelope_warns" 1 "ruling 13 envelope witness must warn exactly once"
  need_file_has "$hook_added" "$shim_dir/jq" "the envelope witness warning must name the pinned jq binary"
  need_file_lacks "$hook_out" "$pending_id" "the rejected envelope must not claim emission of the first staged id"
  need_count "$pd" 1 "pending/ after the rc-0 envelope witness fails"
  need_tree_has "$pd" "$marker" "the un-emitted envelope victim must remain retryable"
  need_count "$rd" 0 "read/ after the rc-0 envelope witness fails"
  need_count "$fd" 0 "failed/ after the rc-0 envelope witness fails"

  run_brain "$fx" bravo hook session-start
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq SessionStart retry after the envelope failure" || return 0
  need_file_has "$OUT" "$marker" "the retained envelope victim must deliver on stable-jq retry"
  need_count "$pd" 0 "pending/ after the stable-jq envelope retry"
  need_count "$rd" 1 "read/ after the stable-jq envelope retry"
  need_count "$fd" 0 "failed/ after the stable-jq envelope retry"
}

# V.U/78 — ruling 13, W3: direct and @all sends must reject an rc-0 `{}` encoder result before
# publication and before their journal announce. Each fixture has one recipient, so one failed
# send means exactly one witness warning naming the stable shim path.
sc_rc0_empty_send_payload_is_rejected() {
  for mode in direct broadcast; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    marker="rc0-empty-send-$mode-v124"
    before_journal=$(journal_entry_count "$fx")

    real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
    shim_dir="$base/jq-empty-send-$mode-bin"
    mkdir -p "$shim_dir" || { fail "fixture: could not create the $mode send shim directory"; return 0; }
    write_rc0_empty_payload_jq "$shim_dir/jq" "$real_jq" f \
      || { fail "fixture: could not write the rc-0 $mode send jq shim"; return 0; }

    saved_path=$PATH
    PATH="$shim_dir:$PATH"; export PATH
    if [ "$mode" = direct ]; then
      run_brain "$fx" alpha dm @bravo "$marker"
    else
      run_brain "$fx" alpha dm @all "$marker"
    fi
    send_rc=$?
    send_out="$base/rc0-empty-send-$mode.out"; send_err="$base/rc0-empty-send-$mode.err"
    cp "$OUT" "$send_out" 2>/dev/null || : > "$send_out"
    cp "$ERR" "$send_err" 2>/dev/null || : > "$send_err"
    PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
    case "$(command -v jq)" in
      "$shim_dir"/*) fail "instrument leak: the $mode send jq shim is STILL resolved after restore"; return 0 ;;
    esac

    need_rc_nonzero "$send_rc" "ruling 13 $mode send must fail on an rc-0 payload lacking wire keys"
    send_witness_warns=$(grep -cF "$shim_dir/jq" "$send_err" 2>/dev/null)
    need_eq "$send_witness_warns" 1 "ruling 13 $mode send witness warning count naming the jq binary"
    need_file_lacks "$send_out" 'dm →' "the failed $mode send must not claim delivery on stdout"
    need_count "$pd" 0 "pending/ after the rejected rc-0 $mode send"
    need_eq "$(count_dotfiles "$pd")" 0 "dot-temp residue after the rejected rc-0 $mode send"
    need_count "$rd" 0 "read/ after the rejected rc-0 $mode send"
    need_count "$fd" 0 "failed/ after the rejected rc-0 $mode send"
    need_eq "$(journal_entry_count "$fx")" "$before_journal" \
      "journal entry count after the rejected rc-0 $mode send — no dm call-log line may be written"
    journal_since "$fx" "$before_journal" > "$base/rc0-empty-send-$mode.journal"
    need_file_lacks "$base/rc0-empty-send-$mode.journal" 'dm →' \
      "journal delta after the rejected rc-0 $mode send"

    if [ "$mode" = direct ]; then
      run_brain "$fx" alpha dm @bravo "$marker"
    else
      run_brain "$fx" alpha dm @all "$marker"
    fi
    retry_rc=$?
    need_rc "$retry_rc" 0 "stable-jq retry of the $mode send" || return 0
    need_count "$pd" 1 "pending/ after the stable-jq $mode send retry"
    need_tree_has "$pd" "$marker" "the stable-jq $mode send retry must publish the message"
    need_eq "$(journal_entry_count "$fx")" "$((before_journal + 1))" \
      "journal entry count after the stable-jq $mode send retry"
  done
}

# V.U/79 — ruling 14, W4: failed/ enumeration failure is visible status, never a silently
# substituted zero. The established status contract remains rc 0; restoring permissions proves
# the same entry renders as the ordinary positive-count banner.
sc_status_surfaces_uninspectable_failed_state() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the failed-state tree" || return 0
  printf 'uninspectable-failed-entry-v124\n' > "$fd/failed-entry-v124" \
    || { fail "fixture: could not plant the failed-state entry"; return 0; }

  make_unreadable_dir "$fd"
  unreadable_rc=$?
  case "$unreadable_rc" in
    0) ;;
    2) fail "instrument blind: the 0300 failed/ directory is still enumerable (running as root?)"; return 0 ;;
    *) fail "fixture: could not make failed/ unreadable-but-searchable (rc=$unreadable_rc)"; return 0 ;;
  esac

  run_brain "$fx" bravo status
  status_rc=$?
  status_out="$base/uninspectable-failed-status.out"
  cp "$OUT" "$status_out" 2>/dev/null || : > "$status_out"
  chmod 755 "$fd" 2>/dev/null || true  # restore BEFORE any assertion can return early

  need_rc "$status_rc" 0 "brain status with an uninspectable failed/ state"
  need_file_has "$status_out" 'DM failed/ state cannot be inspected for @bravo' \
    "ruling 14 explicit uninspectable-failed banner"
  need_file_lacks "$status_out" '⚠ 0 DM message(s)' \
    "an uninspectable failed/ state must never render as proven-empty"

  run_brain "$fx" bravo status
  restored_rc=$?
  need_rc "$restored_rc" 0 "brain status after failed/ readability is restored" || return 0
  need_file_has "$OUT" '⚠ 1 DM message(s) failed structural validation' \
    "restored failed/ state must render its proven positive count"
}

# ═════════════════ V.V — v1.2.4 ruling 13a witness tightening (RED) ═════════════════

# V.V/80 — X1 digest framing: an rc-0 digest missing its final byte is systemic. The file stays
# pending, nothing is emitted or archived, one binary-naming warning fires, and retry delivers.
sc_rc0_truncated_digest_is_systemic() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  marker="rc0-truncated-digest-survivor-v124"

  run_brain "$fx" alpha dm @bravo "$marker"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the truncated-digest victim" || return 0

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  shim_dir="$base/jq-truncated-digest-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the digest shim directory"; return 0; }
  write_rc0_truncated_payload_jq "$shim_dir/jq" "$real_jq" id \
    || { fail "fixture: could not write the truncated-digest jq shim"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo dm take
  take_rc=$?
  take_out="$base/rc0-truncated-digest.out"; take_err="$base/rc0-truncated-digest.err"
  cp "$OUT" "$take_out" 2>/dev/null || : > "$take_out"
  cp "$ERR" "$take_err" 2>/dev/null || : > "$take_err"
  PATH=$saved_path; export PATH
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the digest jq shim is STILL resolved after restore"; return 0 ;;
  esac

  need_rc_nonzero "$take_rc" "ruling 13a take must fail on a digest lacking its closing delimiter"
  need_eq "$(byte_size "$take_out")" 0 "stdout from the rejected truncated digest"
  need_eq "$(grep -c '^brain:' "$take_err" 2>/dev/null)" 1 \
    "ruling 13a digest framing witness warning count"
  need_file_has "$take_err" "$shim_dir/jq" "the digest framing warning must name the pinned jq binary"
  need_count "$pd" 1 "pending/ after the digest framing witness fails"
  need_tree_has "$pd" "$marker" "the truncated digest victim must remain retryable"
  need_count "$rd" 0 "read/ after the digest framing witness fails"
  need_count "$fd" 0 "failed/ after the systemic digest framing failure"

  run_brain "$fx" bravo dm take
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq retry after the truncated digest" || return 0
  need_file_has "$OUT" "$marker" "the retained digest victim must deliver on stable-jq retry"
  need_count "$pd" 0 "pending/ after the stable-jq digest retry"
  need_count "$rd" 1 "read/ after the stable-jq digest retry"
}

# V.V/81 — X1 envelope framing: removing the serializer's final byte cannot authorize emission
# or archive. The hook stays rc 0, warns once through the hook log, and stable retry delivers.
sc_rc0_truncated_session_envelope_is_rejected() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  hooklog="$fx/.brain/.hook-errors.log"
  marker="rc0-truncated-envelope-survivor-v124"

  run_brain "$fx" alpha dm @bravo "$marker"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the truncated-envelope victim" || return 0

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  shim_dir="$base/jq-truncated-envelope-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the envelope shim directory"; return 0; }
  write_rc0_truncated_payload_jq "$shim_dir/jq" "$real_jq" c \
    || { fail "fixture: could not write the truncated-envelope jq shim"; return 0; }

  before_hook=$(line_count "$hooklog")
  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo hook session-start
  hook_rc=$?
  hook_out="$base/rc0-truncated-envelope.out"
  cp "$OUT" "$hook_out" 2>/dev/null || : > "$hook_out"
  PATH=$saved_path; export PATH
  case "$(command -v jq)" in
    "$shim_dir"/*) fail "instrument leak: the envelope jq shim is STILL resolved after restore"; return 0 ;;
  esac
  hook_added="$base/rc0-truncated-envelope.err"
  tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

  need_rc "$hook_rc" 0 "SessionStart hook wrapper status with a truncated envelope"
  need_eq "$(byte_size "$hook_out")" 0 "stdout from the rejected truncated SessionStart envelope"
  need_eq "$(grep -c '^brain:' "$hook_added" 2>/dev/null)" 1 \
    "ruling 13a envelope framing witness warning count"
  need_file_has "$hook_added" "$shim_dir/jq" "the envelope framing warning must name the pinned jq binary"
  need_count "$pd" 1 "pending/ after the envelope framing witness fails"
  need_tree_has "$pd" "$marker" "the truncated envelope victim must remain retryable"
  need_count "$rd" 0 "read/ after the envelope framing witness fails"
  need_count "$fd" 0 "failed/ after the systemic envelope framing failure"

  run_brain "$fx" bravo hook session-start
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq SessionStart retry after the truncated envelope" || return 0
  need_file_has "$OUT" "$marker" "the retained envelope victim must deliver on stable-jq retry"
  need_count "$pd" 0 "pending/ after the stable-jq envelope retry"
  need_count "$rd" 1 "read/ after the stable-jq envelope retry"
}

# V.V/82 — X1 send framing: direct and @all sends reject a real encoder result with its final
# byte removed. No queue or journal publication occurs; one warning fires and retry publishes.
sc_rc0_truncated_send_payload_is_rejected() {
  for mode in direct broadcast; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    marker="rc0-truncated-send-$mode-v124"
    before_journal=$(journal_entry_count "$fx")

    real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
    shim_dir="$base/jq-truncated-send-$mode-bin"
    mkdir -p "$shim_dir" || { fail "fixture: could not create the $mode send shim directory"; return 0; }
    write_rc0_truncated_payload_jq "$shim_dir/jq" "$real_jq" f \
      || { fail "fixture: could not write the truncated $mode send jq shim"; return 0; }

    saved_path=$PATH
    PATH="$shim_dir:$PATH"; export PATH
    if [ "$mode" = direct ]; then
      run_brain "$fx" alpha dm @bravo "$marker"
    else
      run_brain "$fx" alpha dm @all "$marker"
    fi
    send_rc=$?
    send_out="$base/rc0-truncated-send-$mode.out"; send_err="$base/rc0-truncated-send-$mode.err"
    cp "$OUT" "$send_out" 2>/dev/null || : > "$send_out"
    cp "$ERR" "$send_err" 2>/dev/null || : > "$send_err"
    PATH=$saved_path; export PATH
    case "$(command -v jq)" in
      "$shim_dir"/*) fail "instrument leak: the $mode send jq shim is STILL resolved after restore"; return 0 ;;
    esac

    need_rc_nonzero "$send_rc" "ruling 13a $mode send must fail without its closing delimiter"
    need_eq "$(grep -cF "$shim_dir/jq" "$send_err" 2>/dev/null)" 1 \
      "ruling 13a $mode send framing warning count naming the jq binary"
    need_file_lacks "$send_out" 'dm →' "the failed $mode send must not claim delivery"
    need_count "$pd" 0 "pending/ after the rejected truncated $mode send"
    need_eq "$(count_dotfiles "$pd")" 0 "dot-temp residue after the rejected truncated $mode send"
    need_count "$rd" 0 "read/ after the rejected truncated $mode send"
    need_count "$fd" 0 "failed/ after the rejected truncated $mode send"
    need_eq "$(journal_entry_count "$fx")" "$before_journal" \
      "journal entry count after the rejected truncated $mode send"

    if [ "$mode" = direct ]; then
      run_brain "$fx" alpha dm @bravo "$marker"
    else
      run_brain "$fx" alpha dm @all "$marker"
    fi
    retry_rc=$?
    need_rc "$retry_rc" 0 "stable-jq retry of the truncated $mode send" || return 0
    need_count "$pd" 1 "pending/ after the stable-jq $mode send retry"
    need_tree_has "$pd" "$marker" "the stable-jq $mode send retry must publish the message"
    need_eq "$(journal_entry_count "$fx")" "$((before_journal + 1))" \
      "journal entry count after the stable-jq $mode send retry"
  done
}

# V.V/83 — X2 key syntax: quoted values are not object keys. Direct and @all both fail before
# publication and before a delivery journal line when jq returns the framed wrong object.
sc_send_witness_requires_key_syntax() {
  for mode in direct broadcast; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    base=$(dirname "$fx")
    pd=$(q_dir "$fx" bravo pending)
    marker="wrong-object-send-$mode-v124"
    before_journal=$(journal_entry_count "$fx")

    real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
    shim_dir="$base/jq-wrong-object-send-$mode-bin"
    mkdir -p "$shim_dir" || { fail "fixture: could not create the $mode wrong-object shim directory"; return 0; }
    write_rc0_wrong_send_payload_jq "$shim_dir/jq" "$real_jq" \
      || { fail "fixture: could not write the $mode wrong-object jq shim"; return 0; }

    saved_path=$PATH
    PATH="$shim_dir:$PATH"; export PATH
    if [ "$mode" = direct ]; then
      run_brain "$fx" alpha dm @bravo "$marker"
    else
      run_brain "$fx" alpha dm @all "$marker"
    fi
    send_rc=$?
    send_out="$base/wrong-object-send-$mode.out"; send_err="$base/wrong-object-send-$mode.err"
    cp "$OUT" "$send_out" 2>/dev/null || : > "$send_out"
    cp "$ERR" "$send_err" 2>/dev/null || : > "$send_err"
    PATH=$saved_path; export PATH

    need_rc_nonzero "$send_rc" "ruling 13a $mode send must reject quoted values without key syntax"
    need_eq "$(grep -cF "$shim_dir/jq" "$send_err" 2>/dev/null)" 1 \
      "ruling 13a $mode key-syntax warning count naming the jq binary"
    need_file_lacks "$send_out" 'dm →' "the wrong-object $mode send must not claim delivery"
    need_count "$pd" 0 "pending/ after the wrong-object $mode send"
    need_eq "$(count_dotfiles "$pd")" 0 "dot-temp residue after the wrong-object $mode send"
    need_eq "$(journal_entry_count "$fx")" "$before_journal" \
      "journal entry count after the wrong-object $mode send"
  done
}

# V.V/84 — X3 escaped digest fragment: current_ticket supplies the same bare id in status, but
# a serializer that drops the DM block must still fail, leave pending intact, and retry cleanly.
sc_envelope_witness_requires_escaped_digest_id() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  hooklog="$fx/.brain/.hook-errors.log"
  marker="status-only-envelope-survivor-v124"

  run_brain "$fx" alpha dm @bravo "$marker"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the status-only envelope victim" || return 0
  pending_file=$(first_file "$pd") \
    || { fail "fixture: could not resolve the status-only envelope victim"; return 0; }
  pending_id=${pending_file##*/}
  presence="$fx/.brain/presence/bravo.md"
  presence_tmp="$base/bravo-presence.tmp"
  sed "s/^current_ticket: .*/current_ticket: $pending_id/" "$presence" > "$presence_tmp" \
    && mv "$presence_tmp" "$presence" \
    || { fail "fixture: could not set receiver current_ticket to the pending id"; return 0; }
  run_brain "$fx" bravo status
  need_file_has "$OUT" "$pending_id" "prerequisite: status text must carry the bare pending id" || return 0

  real_jq=$(command -v jq) || { fail "fixture: cannot locate the real jq"; return 0; }
  shim_dir="$base/jq-status-only-envelope-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the status-only shim directory"; return 0; }
  write_status_only_envelope_jq "$shim_dir/jq" "$real_jq" \
    || { fail "fixture: could not write the status-only envelope jq shim"; return 0; }

  before_hook=$(line_count "$hooklog")
  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_brain "$fx" bravo hook session-start
  hook_rc=$?
  hook_out="$base/status-only-envelope.out"
  cp "$OUT" "$hook_out" 2>/dev/null || : > "$hook_out"
  PATH=$saved_path; export PATH
  hook_added="$base/status-only-envelope.err"
  tail -n "+$((before_hook + 1))" "$hooklog" > "$hook_added" 2>/dev/null || : > "$hook_added"

  need_rc "$hook_rc" 0 "SessionStart hook wrapper status with the DM block removed"
  need_eq "$(byte_size "$hook_out")" 0 "stdout from the rejected status-only envelope"
  need_eq "$(grep -c '^brain:' "$hook_added" 2>/dev/null)" 1 \
    "ruling 13a escaped-fragment envelope warning count"
  need_file_has "$hook_added" "$shim_dir/jq" "the escaped-fragment warning must name the pinned jq binary"
  need_count "$pd" 1 "pending/ after the status-only envelope is rejected"
  need_tree_has "$pd" "$marker" "the status-only envelope victim must remain retryable"
  need_count "$rd" 0 "read/ after the status-only envelope is rejected"
  need_count "$fd" 0 "failed/ after the systemic status-only envelope failure"

  run_brain "$fx" bravo hook session-start
  retry_rc=$?
  need_rc "$retry_rc" 0 "stable-jq SessionStart retry after the status-only envelope" || return 0
  need_file_has "$OUT" "$marker" "the retained status-only envelope victim must deliver on retry"
  need_count "$pd" 0 "pending/ after the stable-jq status-only retry"
  need_count "$rd" 1 "read/ after the stable-jq status-only retry"
}

# V.V/85 — X4 absence-only fast path: an existing failed/ regular file is uninspectable state,
# not absence, so status must render the explicit cannot-inspect banner.
sc_status_surfaces_regular_file_failed_state() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the failed-state tree" || return 0
  rmdir "$fd" || { fail "fixture: could not replace failed/ directory"; return 0; }
  printf 'not-a-directory\n' > "$fd" || { fail "fixture: could not plant failed/ regular file"; return 0; }

  run_brain "$fx" bravo status
  status_rc=$?
  need_rc "$status_rc" 0 "brain status with failed/ as a regular file"
  need_file_has "$OUT" 'DM failed/ state cannot be inspected for @bravo' \
    "ruling 14 absence-only fast path for an existing failed/ regular file"
}

# ════════════════ V.Y — v1.2.4 ruling 14 ancestor validation (RED) ════════════════
# V.Y/86 — Y1: a regular-file lane makes failed/ uninspectable, not absent. The leaf itself is
# missing, so this discriminates the ancestor walk from ruling 13a's existing-leaf coverage.
sc_status_surfaces_regular_file_lane_ancestor() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  lane="$fx/.brain/dm/bravo"

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the failed-state tree" || return 0
  mv "$lane" "$lane.real" \
    || { fail "fixture: could not move the healthy lane directory"; return 0; }
  printf 'not-a-directory\n' > "$lane" \
    || { fail "fixture: could not plant the regular-file lane"; return 0; }

  run_brain "$fx" bravo status
  status_rc=$?
  need_rc "$status_rc" 0 "brain status with the lane ancestor as a regular file"
  need_file_has "$OUT" 'DM failed/ state cannot be inspected for @bravo' \
    "ruling 14 must reject a regular-file lane ancestor before treating failed/ as absent"
  need_file_lacks "$OUT" '⚠ 0 DM message(s)' \
    "a malformed lane ancestor must never render as proven-empty"
}

# V.Y/87 — Y1: a symlinked dm root that resolves to a regular file cannot be searched for the
# lane or failed/ leaf. The root's existence is enough to require validation before absence.
sc_status_surfaces_symlinked_file_dm_root_ancestor() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  dm_root="$fx/.brain/dm"
  target="$(dirname "$fx")/dm-root-file-target"

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the failed-state tree" || return 0
  mv "$dm_root" "$dm_root.real" \
    || { fail "fixture: could not move the healthy dm root"; return 0; }
  printf 'not-a-directory\n' > "$target" \
    || { fail "fixture: could not plant the dm-root symlink target"; return 0; }
  ln -s "$target" "$dm_root" \
    || { fail "fixture: could not symlink the dm root to a regular file"; return 0; }

  run_brain "$fx" bravo status
  status_rc=$?
  need_rc "$status_rc" 0 "brain status with dm/ symlinked to a regular file"
  need_file_has "$OUT" 'DM failed/ state cannot be inspected for @bravo' \
    "ruling 14 must reject a symlinked dm-root ancestor before treating failed/ as absent"
  need_file_lacks "$OUT" '⚠ 0 DM message(s)' \
    "a malformed dm-root ancestor must never render as proven-empty"
}

# V.Y/88 — Y1: an empty 0300 lane is searchable but not enumerable. Its missing failed/ child
# is not proven absent because the lane itself fails ruling 7's read+search validation.
sc_status_surfaces_unreadable_lane_ancestor() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  lane="$fx/.brain/dm/bravo"

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the failed-state tree" || return 0
  mv "$lane" "$lane.real" \
    || { fail "fixture: could not move the healthy lane directory"; return 0; }
  mkdir "$lane" || { fail "fixture: could not create the empty lane directory"; return 0; }
  make_unreadable_dir "$lane"
  unreadable_rc=$?
  case "$unreadable_rc" in
    0) ;;
    2) fail "instrument blind: the 0300 lane directory is still enumerable (running as root?)"; return 0 ;;
    *) fail "fixture: could not make the lane unreadable-but-searchable (rc=$unreadable_rc)"; return 0 ;;
  esac

  run_brain "$fx" bravo status
  status_rc=$?
  status_out="$(dirname "$fx")/unreadable-lane-status.out"
  cp "$OUT" "$status_out" 2>/dev/null || : > "$status_out"
  chmod 755 "$lane" 2>/dev/null || true  # restore BEFORE any assertion can return early

  need_rc "$status_rc" 0 "brain status with an unreadable lane ancestor"
  need_file_has "$status_out" 'DM failed/ state cannot be inspected for @bravo' \
    "ruling 14 must reject an unreadable lane ancestor before treating failed/ as absent"
  need_file_lacks "$status_out" '⚠ 0 DM message(s)' \
    "an unreadable lane ancestor must never render as proven-empty"
}

# V.Y/89 — control: failed/ genuinely does not exist beneath a healthy real dm root and lane.
# This is the fork-free common path ruling 14 preserves; absence produces no failed-DM banner.
sc_status_keeps_proven_absent_failed_state_silent() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: ensure the failed-state tree" || return 0
  rmdir "$fd" || { fail "fixture: could not remove the empty failed/ directory"; return 0; }

  run_brain "$fx" bravo status
  status_rc=$?
  need_rc "$status_rc" 0 "brain status with failed/ proven absent under healthy ancestors"
  need_file_lacks "$OUT" 'DM failed/ state cannot be inspected for @bravo' \
    "proven absence under healthy ancestors must remain banner-free"
  need_file_lacks "$OUT" 'DM message(s) failed structural validation' \
    "proven-empty failed/ state must not render a spurious zero or positive banner"
}

# ═══════════════ V.Z — round-7 failed-count status controls (guards) ═══════════════

# V.Z/90 — Z1 ordinary state: inbox/tree setup leaves a REAL, EXISTING, EMPTY failed/ directory.
# This is deliberately not V.Y/89's rmdir-manufactured absent leaf. Status must establish zero
# without inventing either a positive-count banner or a cannot-inspect banner.
sc_status_keeps_existing_empty_failed_state_silent() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" bravo inbox
  inbox_rc=$?
  need_rc "$inbox_rc" 0 "prerequisite: ensure the ordinary failed-state tree" || return 0
  need_real_dir "$fd" "ordinary failed/ state" || return 0
  need_count "$fd" 0 "ordinary failed/ state before status" || return 0

  run_brain "$fx" bravo status
  status_rc=$?
  need_rc "$status_rc" 0 "brain status with an existing empty failed/ state"
  need_file_lacks "$OUT" 'DM failed/ state cannot be inspected for @bravo' \
    "an inspectable empty failed/ state must remain banner-free"
  need_file_lacks "$OUT" 'DM message(s) failed structural validation' \
    "proven-empty failed/ must not render a zero or positive failed-message banner"
}

# V.Z/91 — Z1 positive path: the same authoritative call that proves emptiness must surface a
# real count after an artifact appears, without falling through to the cannot-inspect banner.
sc_status_counts_existing_failed_entries() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" bravo inbox
  inbox_rc=$?
  need_rc "$inbox_rc" 0 "prerequisite: ensure the positive failed-state tree" || return 0
  printf 'positive-failed-count-round7\n' > "$fd/failed-entry-round7" \
    || { fail "fixture: could not plant the positive failed-state entry"; return 0; }

  run_brain "$fx" bravo status
  status_rc=$?
  need_rc "$status_rc" 0 "brain status with one failed/ artifact"
  need_file_has "$OUT" '⚠ 1 DM message(s) failed structural validation' \
    "the positive failed/ count path"
  need_file_lacks "$OUT" 'DM failed/ state cannot be inspected for @bravo' \
    "an inspectable positive failed/ state must not render cannot-inspect"
}

# ═══════════ V.P — task 5.7: automatic delivery via the PreToolUse injector ═══════════
#
# AUTHORITY: AGENT_BRAIN_DM_GSD_PLAN.md task 5.7 (header item 5). THE GAP it names: delivery
# today has exactly two paths — `_hook_session_start` (at boot) and `cmd_dm_take` (explicit) —
# so a RUNNING lane hears a DM only if it remembers to ask. `_hook_pre_tool` does collision
# detection only. THE MECHANISM: `_emit_pretool`'s allow branch is already a verified
# `additionalContext` injector, so delivering DMs through it needs no new primitive.
#
# ⚠ STOP-AND-ESCALATE CONDITION carried from the task, restated so it is not lost: the
# DM-mechanisms eval recorded hook-injected DMs being REFUSED as prompt injection 3/3, which the
# task argues was a fixture artifact (bare scratch lanes with no vault). Nothing in a shell suite
# can measure an agent's acceptance — that is Phase 6's job. If a real armed lane refuses a
# pre-tool-delivered DM, the approach is invalidated and `Monitor` becomes the answer; no
# scenario here should be read as evidence against that.
#
# BASELINE, said out loud: V.P/98, V.P/100's first limb and V.P/101 are GUARDS, not REDs, and
# each says why in its own comment. They pin "unchanged" and "do not add a cost" requirements
# (6 and 9) that the current engine satisfies trivially BECAUSE it does no DM work on this path
# at all. Manufacturing a failure for them would be dishonest; their value is at GREEN.
#
# DECLARED GAPS for this section (absence is a decision, not an oversight):
#   · The seam decision itself — "the consume→emit→archive loop gets ONE home; do not write a
#     second copy" — has NO structural witness here. It is a source-shape claim about a shell
#     script, and the only instruments available are a source-text grep (which prescribes a
#     spelling, and whose negative control needs a `bin/brain` mutation this agent may not make)
#     or a bespoke duplicate-detector. What IS pinned is the OBSERVABLE consequence the task
#     names as the reason for the rule — divergence turning at-least-once into at-most-once on
#     one path — by holding the PreToolUse path to the SAME discipline SessionStart is held to,
#     assertion for assertion: V.P/93 mirrors V.N/47, V.P/94 mirrors V.N/48, V.P/97 mirrors
#     V.N/50's cap limb. A duplicated loop that has already diverged fails those. A duplicated
#     loop that has NOT yet diverged passes, and is a review concern, not a test concern.
#     NON-BLOCKING. [P1]
#   · Requirement 5 pins only that DM_INJECT_MAX_LINES bounds this path and that bounding
#     destroys nothing. The CONTINUATION instruction V.N/50 requires of SessionStart
#     (must-survive #4) is NOT required here: task 5.7 names the cap and does not name
#     continuation, and PreToolUse fires again on the next tool call, so the "do not rely on a
#     new directory event firing" hazard that motivated it does not obviously transfer. Pinning
#     it would invent a ruling. NON-BLOCKING open question for the dispatcher. [P2]
#   · V.P/92 and V.P/96 pin `permissionDecision: "allow"`; V.P/95's four early-exit rows do not.
#     The task names the ALLOW BRANCH as the mechanism ("_emit_pretool's allow branch already
#     ships a verified additionalContext injector … that same courier"), so `allow` is
#     authority-backed and not this suite's invention — but pinning it once per shape (DM-only,
#     and DM-plus-collision) is enough to reject an ask/deny emission, and repeating it on every
#     row would buy nothing. [P3]
#   · Whether a pre-tool delivery should write a journal line of its own is unresolved and
#     deliberately unasserted. V.P/96 requires the COLLISION announce to survive (an existing
#     guarantee) and asserts nothing about DM-delivery announces in either direction, so a GREEN
#     may add one or not. [P4]
#   · ⚠ THE ASK-BRANCH COMBINATION IS NOT COVERED. V.P/96 drives the ALLOW branch only. The two
#     branches use DIFFERENT carriers — `allow` ships `additionalContext`, `ask` ships
#     `permissionDecisionReason` — so a GREEN that fixes requirement 4 by concatenating both
#     texts into ONE `_emit_pretool ask` call would satisfy "one JSON object" while delivering
#     the DM through a field requirement 1 never authorized. V.P/96 cannot see that.
#     WHY IT IS NOT DRIVEN, and why no harness was built for it: the ask branch is gated on
#     `[ "${BRAIN_PRETOOL_MODE:-allow}" = "ask" ] && [ -t 1 ]` (fix K). The env half is settable;
#     the `[ -t 1 ]` half needs a real terminal, so reaching it costs a pty harness (`script(1)`,
#     whose flags differ between macOS and Linux and which is not portable across sh/dash) — an
#     instrument that would need its own tests, which is the standing signal to escalate rather
#     than build. MEASURED 2026-08-06 against the current engine: `BRAIN_PRETOOL_MODE=ask` with
#     stdout redirected to a file emits `permissionDecision: "allow"` + `additionalContext`, and
#     no `permissionDecisionReason` key at all. The dispatcher runs hooks with stdout on a PIPE,
#     so the ask branch is unreachable in production as currently gated — the trap is real in
#     SOURCE and dead in DEPLOYMENT.
#     ⚠ BLOCKING IF THE GATE MOVES: this gap is safe only while `[ -t 1 ]` stands. A GREEN that
#     relaxes it, or a spec that rules "one object must carry BOTH fields", reopens it — and
#     "both fields" is a RULING this suite has no authority to invent, so it is returned rather
#     than guessed. Non-blocking as the plan stands today. [P5]

# ── V.P plumbing: the PreToolUse hook is STDIN-driven ────────────────────────────────────
# `_hook_pre_tool` opens with `_input=$(cat)`, so every existing runner in this file would HANG
# on it — none of them attach stdin. These are `run_brain` / `_brain_env_run` with a pipe in
# front and nothing else changed: same environment, same OUT/ERR capture, and the same
# `assert_disposable` interlock in the PARENT shell (inside the subshell a `fatal` would kill
# only the subshell and the breach would render as PASS).

# pretool_stdin <tool_name> [<key> <value>] — the PreToolUse envelope the dispatcher feeds the
# hook. An omitted key/value pair yields `tool_input: {}`, which is the empty-`_paths` early exit.
pretool_stdin() {
  if [ "$#" -lt 3 ]; then
    jq -cn --arg t "$1" '{tool_name:$t,tool_input:{}}'
  else
    # shellcheck disable=SC2016  # jq source; $t/$k/$v are jq variables
    jq -cn --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name:$t,tool_input:{($k):$v}}'
  fi
}

# run_pretool <repo> <identity> <stdin-json> — sets $OUT/$ERR; the caller reads $?.
run_pretool() {
  _rp_repo=$1; _rp_id=$2; _rp_json=$3
  _rp_base=$(dirname "$_rp_repo")
  OUT="$_rp_base/last.out"
  ERR="$_rp_base/last.err"
  assert_disposable "$_rp_repo"
  printf '%s\n' "$_rp_json" | ( _brain_exec "$_rp_repo" "$_rp_id" hook pre-tool ) >"$OUT" 2>"$ERR"
}

# run_pretool_closed_stdout <repo> <identity> <stdin-json> <errfile> — the emit-failure limb,
# the PreToolUse twin of `_brain_env_run`'s `-` outfile (V.N/47's instrument).
run_pretool_closed_stdout() {
  _rc_repo=$1; _rc_id=$2; _rc_json=$3; _rc_err=$4
  assert_disposable "$_rc_repo"
  printf '%s\n' "$_rc_json" | ( _brain_exec "$_rc_repo" "$_rc_id" hook pre-tool ) >&- 2>"$_rc_err"
}

# The additionalContext of the LAST captured PreToolUse emission. `-s` + `.[0]` on purpose: if
# the engine put TWO objects on stdout it is `pretool_object_count` that must fail and say so,
# not this reader failing to parse.
pretool_context() {
  jq -e -r -s '.[0].hookSpecificOutput.additionalContext // empty' "$OUT" 2>/dev/null
}

# JSON values on the LAST captured stdout. `0` covers both "emitted nothing" and "emitted
# something that does not parse", so a raw-text degradation is never mistaken for one object.
pretool_object_count() { jq -s 'length' "$OUT" 2>/dev/null || printf '0'; }

# The lines cmd_hook appended to .brain/.hook-errors.log since <baseline>. BOTH hooks run under
# `2>>"$BRAIN/.hook-errors.log"`, so a pre-tool WARN lands there and never on $ERR.
hooklog_since() { # <repo> <baseline-line-count> <dest>
  tail -n "+$(($2 + 1))" "$1/.brain/.hook-errors.log" > "$3" 2>/dev/null || : > "$3"
}

# set_presence_touches <repo> <slug> <path-or-zone> — turn a fixture lane into a live collision
# peer. `write_presence` hardcodes `touches: []`; rewriting that one line is cheaper than a
# second presence writer that could drift from the first.
set_presence_touches() {
  _sp_file="$1/.brain/presence/$2.md"
  [ -f "$_sp_file" ] || return 1
  awk -v t="$3" '
    /^touches: \[\]$/ && !done { printf "touches: [\"%s\"]\n", t; done = 1; next }
    { print }
  ' "$_sp_file" > "$_sp_file.rewrite" || return 1
  mv "$_sp_file.rewrite" "$_sp_file"
}

# V.P/92 — requirement 1: a pending DM is emitted ON PreToolUse, through `additionalContext`,
# for the RESOLVED lane. This is the feature itself; everything after it pins a way of getting
# it wrong.
#   FIXTURE    an ordinary matching tool (Edit) with NO collision — what a running lane actually
#              does all day, and the case where the hook is silent today.
#   PROVES     stdout is ONE well-formed PreToolUse object, its additionalContext carries the
#              body, and the file really left pending/ for read/.
#   LANE       a message queued for charlie must NOT reach bravo. Without it, "deliver everything
#   CONTROL    under dm/" would pass.
#   REJECTS    a hook that delivers nothing (today); one that ships the DM in
#              `permissionDecisionReason`, which the task's own mechanism note records as
#              silently dropped on an allow; one that ignores the resolved lane.
sc_pretool_delivers_pending_dm() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "pretool-inject-marker-57a"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send to bravo" || return 0
  run_brain "$fx" alpha dm @charlie "pretool-other-lane-57a"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send to the uninvolved lane" || return 0
  need_count "$pd" 1 "prerequisite: exactly one message queued for bravo" || return 0

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "the PreToolUse hook wrapper status contract" || return 0

  need_eq "$(pretool_object_count)" 1 \
    "requirement 1: the hook must put exactly ONE JSON value on stdout (0 = it emitted nothing, or text that does not parse; >1 = more than one _emit_pretool call)" || return 0
  need_eq "$(jq -r -s '.[0].hookSpecificOutput.hookEventName // ""' "$OUT" 2>/dev/null)" "PreToolUse" \
    "the emitted object must be a PreToolUse hook payload"
  need_eq "$(jq -r -s '.[0].hookSpecificOutput.permissionDecision // ""' "$OUT" 2>/dev/null)" "allow" \
    "requirement 1 names the ALLOW branch as the courier ('_emit_pretool's allow branch already ships a verified additionalContext injector … that same courier'). additionalContext renders only on allow, so a DM shipped under an ask/deny decision is present in the JSON and invisible to the agent — which is precisely the failure a payload-only assertion cannot see"

  ctx=$(pretool_context)
  need_str_has "$ctx" "pretool-inject-marker-57a" \
    "requirement 1: the pending DM must arrive in .hookSpecificOutput.additionalContext — permissionDecisionReason renders only on ask/deny and is silently dropped on an allow, which is exactly why the task names additionalContext as the courier"
  need_str_lacks "$ctx" "pretool-other-lane-57a" \
    "lane control: a message queued for a DIFFERENT lane must not be delivered to bravo"

  need_count "$pd" 0 "bravo's pending/ after the injection"
  need_count "$rd" 1 "bravo's read/ after the injection"
  need_count "$fd" 0 "bravo's failed/ after the injection"
  need_count "$(q_dir "$fx" charlie pending)" 1 \
    "charlie's pending/ — an uninvolved lane's queue must be untouched by bravo's tool call"
}

# V.P/93 — requirement 2, first two limbs: at-least-once, on ABSOLUTE counts.
#   LIMB A     CRASH BEFORE EMIT. Stdout is closed, so the emission cannot succeed. Nothing may
#              leave pending/. Identical instrument and identical claim to V.N/47 on the
#              SessionStart path — which is how this suite holds the two paths to one discipline.
#   LIMB B     the ordinary path, asserted on absolute counts BEFORE and AFTER. "It moved" is
#              blind to a half-fix in which the new consumer delivers while an older producer
#              still leaves a copy behind, or in which one message is archived twice; `pending/
#              == 0` and `read/ == 1` are not.
#   REJECTS    any consume that moves a file out of pending/ before it has been emitted, any
#              that terminalises a message because its OUTPUT failed, and a redelivery of an
#              already-archived message on the next tool call.
sc_pretool_at_least_once_absolute_counts() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "pretool-atleastonce-57b"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "BEFORE: pending/ holds exactly one message" || return 0
  need_count "$rd" 0 "BEFORE: read/ is empty" || return 0
  need_count "$fd" 0 "BEFORE: failed/ is empty" || return 0

  run_pretool_closed_stdout "$fx" bravo \
    "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")" "$base/pretool-closed.err"

  need_count "$pd" 1 \
    "pending/ after a PreToolUse whose OUTPUT could not be written — requirement 2: nothing leaves pending/ until it has been emitted"
  need_count "$rd" 0 \
    "read/ after a failed PreToolUse emit — archiving a message that was never delivered is UR-1's silent loss reappearing on a new path"
  need_count "$fd" 0 \
    "failed/ after a failed PreToolUse emit — an emit failure is not evidence that the message is structurally invalid"
  need_tree_has "$pd" "pretool-atleastonce-57b" \
    "the un-emitted message must still be the one sitting in pending/"

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "PreToolUse after the emit failure clears" || return 0
  ctx=$(pretool_context)
  need_str_has "$ctx" "pretool-atleastonce-57b" \
    "a message whose emit failed must be delivered by the very next tool call — there is no lease to expire first"
  need_count "$pd" 0 "AFTER: pending/ is exactly zero, not merely smaller"
  need_count "$rd" 1 \
    "AFTER: read/ holds exactly one entry, not merely a non-zero number — two would mean the message was archived twice"
  need_count "$fd" 0 "AFTER: failed/ is still empty"

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "a follow-up PreToolUse on a drained queue" || return 0
  need_file_lacks "$OUT" "pretool-atleastonce-57b" \
    "an archived message must not be redelivered on the next tool call — PreToolUse fires constantly, so a redelivering hook repeats every DM forever"
  need_count "$rd" 1 "read/ after the follow-up tool call"
  need_count "$pd" 0 "pending/ after the follow-up tool call"
}

# V.P/94 — requirement 2, third limb: CRASH AFTER EMIT, BEFORE THE MOVE. read/ is made read-only,
# so the archive rename gets EACCES after the digest has already been printed. The SessionStart
# twin is V.N/48.
#   PROVES     the emit really happened FIRST (the marker is on stdout), the message is not lost,
#              it stays pending, the failure is REPORTED, and it therefore replays.
#   WHERE THE  `cmd_hook` runs both hooks under `2>>"$BRAIN/.hook-errors.log"`, so the warn lands
#   WARN GOES  in the hook log, never on $ERR. A scenario that grepped $ERR would pass vacuously.
#   REJECTS    a pre-tool path that archives before emitting, one that swallows the rename
#              failure (leaving a message pending forever with nothing saying why), and one that
#              treats a rename failure as terminal.
sc_pretool_archive_failure_warns_and_replays() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
  hooklog="$fx/.brain/.hook-errors.log"

  run_brain "$fx" alpha dm @bravo "pretool-archivefail-57c"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0

  before_log=$(line_count "$hooklog")
  make_readonly_dir "$rd"
  mrc=$?
  case "$mrc" in
    0) ;;
    2) fail "instrument blind: a rename into a 0500 read/ still succeeds (running as root?)"; return 0 ;;
    *) fail "fixture: could not make read/ read-only (rc=$mrc)"; return 0 ;;
  esac
  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  chmod 755 "$rd" 2>/dev/null || true       # restore BEFORE any early return
  blocked_out="$base/pretool-archivefail.out"
  cp "$OUT" "$blocked_out" 2>/dev/null || : > "$blocked_out"
  hooklog_since "$fx" "$before_log" "$base/pretool-archivefail.log"

  need_file_has "$blocked_out" "pretool-archivefail-57c" \
    "requirement 2 is EMIT-before-archive: the digest must reach stdout before the archive rename is attempted"
  need_count "$rd" 0 "read/ after an archive rename that could not land"
  need_count "$pd" 1 \
    "pending/ after a failed archive rename — requirement 2: the message stays pending and replayable"
  need_count "$fd" 0 "failed/ after a failed archive rename"
  need_tree_has "$pd" "pretool-archivefail-57c" "the retained message must be the one whose move failed"
  need_file_has "$base/pretool-archivefail.log" "brain:" \
    "requirement 2: an archive failure on the PreToolUse path must WARN, in .brain/.hook-errors.log — identical discipline to SessionStart, whose 'emitted but could not be archived' warn is the only thing that makes a silent replay loop diagnosable"

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "PreToolUse after the archive fault cleared" || return 0
  need_file_has "$OUT" "pretool-archivefail-57c" \
    "at-least-once: a message emitted but not archived must REPLAY on the next tool call (duplicates are explicitly acceptable)"
  need_count "$rd" 1 "read/ after the replay"
  need_count "$pd" 0 "pending/ after the replay"
}

# V.P/95 — requirement 3: delivery is NOT gated behind collision detection. The task names three
# early exits in `_hook_pre_tool` (non-matching tool, empty `_paths`, empty `_collisions`); a DM
# must still be delivered on all three.
#   ROWS       the three the task names, plus `Bash` with an ordinary command. That fourth row is
#              the same non-matching-tool class reached through a DIFFERENT `exit 0` in the
#              source (the inner case under Bash), so it is exercised rather than assumed
#              equivalent — one extra loop iteration, no extra machinery.
#   REJECTS    the single most likely wrong implementation: appending the DM emission to the
#              BOTTOM of the existing function, where all four early exits jump past it. That
#              engine passes V.P/96 (which has a collision) and fails every row here.
sc_pretool_delivery_not_gated_by_collision() {
  for probe in nonmatching-tool bash-nonmatching empty-paths empty-collisions; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    marker="pretool-earlyexit-$probe-57d"

    run_brain "$fx" alpha dm @bravo "$marker"
    rc=$?
    need_rc "$rc" 0 "prerequisite ($probe): send" || return 0
    need_count "$pd" 1 "prerequisite ($probe): one message queued" || return 0

    case "$probe" in
      nonmatching-tool) probe_stdin=$(pretool_stdin Read file_path "$fx/notes/scratch.md") ;;
      bash-nonmatching) probe_stdin=$(pretool_stdin Bash command "ls -la") ;;
      empty-paths)      probe_stdin=$(pretool_stdin Edit) ;;
      *)                probe_stdin=$(pretool_stdin Edit file_path "$fx/notes/scratch.md") ;;
    esac

    run_pretool "$fx" bravo "$probe_stdin"
    ptrc=$?
    need_rc "$ptrc" 0 "$probe: the PreToolUse hook wrapper status contract"
    need_eq "$(pretool_object_count)" 1 \
      "$probe: requirement 3 — delivery must NOT be gated behind collision detection, and this early exit emitted no JSON payload at all"
    ctx=$(pretool_context)
    need_str_has "$ctx" "$marker" \
      "$probe: the pending DM must be delivered through this early-exit path too"
    need_count "$pd" 0 "$probe: pending/ after delivery"
    need_count "$rd" 1 "$probe: read/ after delivery"
    need_count "$fd" 0 "$probe: failed/ after delivery"
  done
}

# V.P/96 — requirement 4, THE TRAP. A collision AND a pending DM together must reach the agent as
# ONE well-formed JSON object. Two `_emit_pretool` calls put two objects on stdout and the
# payload is malformed — the agent gets neither.
#   PRIMARY    exactly one JSON value on stdout, asserted BEFORE the content limbs so that the
#   ASSERTION  diagnosis is not buried under three "not found" reports.
#   BOTH WAYS  the collision text must not clobber the DM, nor the DM the collision. Asserted on
#              the collided PATH and the peer LANE — the data, not any particular wording — so a
#              GREEN may reword the warning freely.
#   ALSO       the collision path's durable journal record survives the merge (the announce is
#              the guarantee the warning rests on).
#   REJECTS    two emissions; an emission that carries only the collision (today's engine, once
#              the DM path exists but is skipped when `_collisions` is non-empty); one that
#              carries only the DM (the collision warning quietly dropped while merging).
sc_pretool_collision_and_dm_in_one_object() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)
  shared="shared/collide-target-57e.txt"

  set_presence_touches "$fx" charlie "$shared" \
    || { fail "fixture: could not give charlie a touches[] entry"; return 0; }
  run_brain "$fx" alpha dm @bravo "pretool-combination-marker-57e"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: one message queued" || return 0

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/$shared")"
  ptrc=$?
  need_rc "$ptrc" 0 "the PreToolUse hook wrapper status contract" || return 0

  need_eq "$(pretool_object_count)" 1 \
    "requirement 4: a collision AND a pending DM must reach the agent as ONE well-formed JSON object — 2 means two _emit_pretool calls and a malformed payload, 0 means nothing parseable was emitted" || return 0

  ctx=$(pretool_context)
  need_str_has "$ctx" "pretool-combination-marker-57e" \
    "requirement 4: the DM must survive the combination — the collision warning must not clobber it"
  need_str_has "$ctx" "$shared" \
    "requirement 4: the collision warning must survive the combination — the DM must not clobber it (asserted on the collided PATH, not on any wording)"
  need_str_has "$ctx" "charlie" \
    "requirement 4: the surviving collision warning must still name the colliding LANE"
  need_eq "$(jq -r -s '.[0].hookSpecificOutput.permissionDecision // ""' "$OUT" 2>/dev/null)" "allow" \
    "carrying a DM must not change the collision DECISION: non-blocking allow (fix K forbids ask without an attached human, and stdout here is not a tty, so allow is the only legal value — this is existing pinned behaviour, not a new ruling)"

  need_tree_has "$fx/.brain/journal" "$shared" \
    "the collision announce is the durable record the warning rests on — it must not be dropped while the two emissions are merged"

  need_count "$pd" 0 "pending/ after the combined emission"
  need_count "$rd" 1 "read/ after the combined emission — the DM is archived exactly once"
}

# V.P/97 — requirement 5: DM_INJECT_MAX_LINES is honored on this path too. Same fixture shape and
# same bound as V.N/50 on the SessionStart path.
#   BOUND      45 entries are queued; at most DM_INJECT_MAX_LINES (40) may be delivered in one
#              tool call. K itself is not pinned — the map never names it — only that a bound
#              exists and does not exceed the surviving injection cap.
#   LOSSLESS   every entry is still accounted for across pending/ + read/ + failed/.
#   NOT PINNED the continuation instruction. See gap [P2]; task 5.7 names the cap and not
#              continuation, and inventing it here would be a ruling this suite has no authority
#              to make.
#   REJECTS    an unbounded injector that dumps a 45-message backlog into a single tool call, and
#              a bound that destroys the remainder instead of leaving it queued.
sc_pretool_honors_inject_max_lines() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  seed=$(plant_message "$fx" bravo "pretool-backlog-seed-57f") \
    || { fail "prerequisite: could not queue the seed message"; return 0; }
  clone_queued "$seed" 44 "pretool-backlog-" \
    || { fail "fixture: could not mint the backlog"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"pretool-backlog-00-marker"}' \
    > "$seed" || { fail "fixture: could not rewrite the seed body"; return 0; }
  need_count "$pd" 45 "prerequisite: 45 entries queued" || return 0

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "PreToolUse with a 45-entry backlog" || return 0
  need_eq "$(pretool_object_count)" 1 \
    "a backlogged PreToolUse must still emit exactly one JSON object" || return 0
  ctx=$(pretool_context)

  shown=0; i=0
  while [ "$i" -le 44 ]; do
    m=$(printf 'pretool-backlog-%02d-marker' "$i")
    str_has "$ctx" "$m" && shown=$((shown + 1))
    i=$((i + 1))
  done
  [ "$shown" -gt 0 ] \
    || { fail "requirements 1 and 5: the tool call injected NONE of the 45 queued entries"; return 0; }
  [ "$shown" -le "$DM_INJECT_MAX_LINES" ] \
    || fail "requirement 5: the tool call delivered $shown of 45 entries — DM_INJECT_MAX_LINES ($DM_INJECT_MAX_LINES) is the surviving aggregate bound and must be honored on the PreToolUse path too"

  total=$(( $(count_files "$pd") + $(count_files "$rd") + $(count_files "$fd") ))
  need_eq "$total" 45 \
    "entries accounted for across pending/ + read/ + failed/ — bounding the BATCH must never destroy a MESSAGE"
  [ "$(count_files "$pd")" -gt 0 ] \
    || fail "instrument check: nothing remained pending after a 45-entry injection, so the cap limb above is vacuous — raise the fixture backlog above the engine's batch cap"
}

# V.P/98 — requirement 6: an unresolvable whoami exits 0 SILENTLY, and a repo with no brain stays
# silent. The task marks this one "unchanged".
#
#   ⚠ THIS IS A GUARD, NOT A RED — the honest disposition, not a concession. There is nothing
#   here for the current engine to fail: `_hook_pre_tool` already exits at `[ -z "$_feat" ]` and
#   `cmd_hook` already exits on a missing `.brain`. Its at-GREEN value is precise: it is what
#   catches a GREEN that hoists DM delivery ABOVE the whoami guard, which would make every tool
#   call in every unrelated repo on the machine emit a payload — the exact hazard the deploy
#   notes call "machine-wide and instant".
#
#   FIXTURE    identity "" leaves BRAIN_FEATURE empty, so whoami falls through to the branch
#              scan, and the fixture branch (main) is owned by no presence note. The second limb
#              needs the one fixture `make_vault` cannot produce — a repo that was never inited.
sc_pretool_unresolvable_whoami_is_silent() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  run_brain "$fx" alpha dm @bravo "pretool-unresolvable-57g"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: one message queued" || return 0

  run_pretool "$fx" "" "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "requirement 6: an unresolvable whoami must exit 0"
  need_eq "$(byte_size "$OUT")" 0 \
    "requirement 6: an unresolvable whoami must be SILENT — a hook that starts emitting payloads when it cannot tell who it is turns every tool call everywhere into an injection"
  need_eq "$(line_count "$fx/.brain/.hook-errors.log")" 0 \
    "an unresolvable whoami must log no hook diagnostics either"
  need_count "$pd" 1 \
    "no lane resolved, so no queue may be consumed — a message must never be delivered to nobody"

  plain_base=$(mktemp -d "$SUITE_TMP/plain.XXXXXX") \
    || { fail "fixture: mktemp failed for the brainless repo"; return 0; }
  plain_base=$(cd "$plain_base" && pwd -P) \
    || { fail "fixture: cannot resolve the brainless repo root"; return 0; }
  assert_disposable "$plain_base"
  plain_repo="$plain_base/repo"
  mkdir -p "$plain_repo" "$plain_base/home/.claude" \
    || { fail "fixture: could not scaffold the brainless repo"; return 0; }
  git init -q -b "$FIXTURE_BRANCH" "$plain_repo" >/dev/null 2>&1 \
    || { fail "fixture: git init failed for the brainless repo"; return 0; }
  need_dir_absent "$plain_repo/.brain" "fixture: the brainless repo must have no brain" || return 0

  run_pretool "$plain_repo" "" "$(pretool_stdin Edit file_path "$plain_repo/anything.txt")"
  plain_rc=$?
  need_rc "$plain_rc" 0 "requirement 6: a repo with no .brain must exit 0"
  need_eq "$(byte_size "$OUT")" 0 "requirement 6: a repo with no .brain must emit nothing"
  need_eq "$(byte_size "$ERR")" 0 "requirement 6: a repo with no .brain must warn nothing"
}

# V.P/99 — requirement 7: jq-missing degradation neither SWALLOWS nor DUPLICATES a message.
#   INSTRUMENT the V.Q/65 broken-jq PATH shim, unchanged, with the same restore-and-prove-the-
#              restore discipline (a leaked shim would poison every later scenario).
#   OUTCOME-   the task does not say WHICH degradation is correct, so this does not pin one. Both
#   NEUTRAL    legal shapes are permitted — leave the message pending and replay it, or emit the
#              body and archive it — and the invariant asserted across BOTH runs is the one the
#              task actually states: the body is delivered EXACTLY once. 0 is a swallow, 2 is a
#              duplicate, and both are named failures.
#   REJECTS    a degraded run that quarantines the message (a missing dependency is not proof of
#              a malformed message), one that archives without emitting, and one that emits
#              without archiving and then replays.
sc_pretool_jq_missing_neither_swallows_nor_duplicates() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "pretool-jqgone-marker-57h"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: one message queued" || return 0

  # Built while jq still works — the shim must break the ENGINE's jq, not the fixture's.
  jqgone_stdin=$(pretool_stdin Edit file_path "$fx/notes/scratch.md")

  shim_dir="$base/pretool-broken-jq-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'printf "jq: simulated incompatible build\\n" >&2\n'
    printf 'exit 3\n'
  } > "$shim_dir/jq" || { fail "fixture: could not write the jq shim"; return 0; }
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_pretool "$fx" bravo "$jqgone_stdin"
  broken_rc=$?
  broken_out="$base/pretool-jqgone.out"
  cp "$OUT" "$broken_out" 2>/dev/null || : > "$broken_out"
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*)
      fail "instrument leak: the jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  jq -e -n '1' >/dev/null 2>&1 \
    || { fail "instrument leak: the broken-jq shim survived the restore — every later scenario would be poisoned"; return 0; }

  broken_delivered=0
  grep -qF -- "pretool-jqgone-marker-57h" "$broken_out" 2>/dev/null && broken_delivered=1

  need_rc "$broken_rc" 0 "requirement 7: a degraded PreToolUse must not fail the tool call"
  need_count "$fd" 0 \
    "requirement 7: a missing or incompatible jq is not evidence that a message is structurally invalid — nothing may be quarantined"
  need_eq "$(( $(count_files "$pd") + $(count_files "$rd") ))" 1 \
    "requirement 7 must not SWALLOW: after the degraded run the message must still be exactly one entry across pending/ + read/"
  if [ "$broken_delivered" = 1 ]; then
    need_count "$pd" 0 \
      "a degraded run that DID emit the body must archive it — leaving it pending as well makes the next tool call a duplicate, which requirement 7 forbids"
  else
    need_count "$pd" 1 \
      "a degraded run that emitted nothing must leave the message pending and replayable"
    need_count "$rd" 0 \
      "a degraded run that emitted nothing must not archive — that is a swallow"
  fi

  run_pretool "$fx" bravo "$jqgone_stdin"
  ptrc=$?
  need_rc "$ptrc" 0 "PreToolUse once jq is healthy again" || return 0
  healthy_delivered=0
  grep -qF -- "pretool-jqgone-marker-57h" "$OUT" 2>/dev/null && healthy_delivered=1
  need_eq "$(( broken_delivered + healthy_delivered ))" 1 \
    "requirement 7: neither swallowed nor duplicated — across the degraded run and the healthy one the body must be delivered EXACTLY once (0 = swallowed, 2 = duplicated)"
  need_count "$pd" 0 "pending/ once jq is healthy again"
  need_count "$rd" 1 "read/ once jq is healthy again"
  need_count "$fd" 0 "failed/ once jq is healthy again"
}

# V.P/100 — requirement 8: no double delivery with SessionStart. Both paths consume the same
# `pending/`, so whichever runs first must leave nothing for the other.
#
#   ⚠ SCOPE — read this before restating requirement 8. Taken absolutely, "no double-delivery"
#   contradicts the at-least-once contract, which explicitly permits a crash replay ("duplicates
#   acceptable"). This scenario pins the NON-CONTRADICTORY reading and only that: no duplicate
#   under a CLEAN, NON-CRASHING handoff. That is enforced by construction, not by wording — the
#   first consumer is asserted to have fully completed (`pending/ == 0`) BEFORE the second is
#   invoked, and neither consumer is faulted. V.P/94 is the deliberate companion in the other
#   direction: it REQUIRES a replay after an archive failure. The two cannot collide, because
#   V.P/94's message is still pending when it replays and this one's is not. If the plan's
#   requirement 8 is restated, it should be restated to this reading; no assertion here needs
#   to change for that.
#   ORDER      the sessionstart-first limb runs FIRST on purpose: it is BASELINE-GREEN today (the
#              boot consumes, the pre-tool hook does nothing) and would go on passing after a
#              wrong GREEN, so it is the regression guard for that direction. The pretool-first
#              limb is the RED one. Running the green limb first means its result is reported
#              even though the red limb short-circuits the loop.
#   REJECTS    a pre-tool path that reads pending/ without consuming it, which would redeliver
#              every message on every tool call until the next boot; and a boot that replays what
#              a tool call already delivered.
sc_pretool_and_session_start_do_not_double_deliver() {
  for order in sessionstart-first pretool-first; do
    fx=$(make_vault alpha bravo) || fatal "fixture build failed"
    pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)
    marker="pretool-nodouble-$order-57i"

    run_brain "$fx" alpha dm @bravo "$marker"
    rc=$?
    need_rc "$rc" 0 "prerequisite ($order): send" || return 0
    need_count "$pd" 1 "prerequisite ($order): one message queued" || return 0

    if [ "$order" = sessionstart-first ]; then
      first_ctx=$(hook_context "$fx" bravo)
      firstrc=$?
      need_rc "$firstrc" 0 "$order: the first (SessionStart) consumer" || return 0
      need_str_has "$first_ctx" "$marker" "$order: the first consumer must deliver the message"
      need_count "$pd" 0 "$order: pending/ after the first consumer" || return 0
      run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
      secondrc=$?
      need_rc "$secondrc" 0 "$order: the second (PreToolUse) consumer" || return 0
      second_ctx=$(pretool_context)
    else
      run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
      firstrc=$?
      need_rc "$firstrc" 0 "$order: the first (PreToolUse) consumer" || return 0
      first_ctx=$(pretool_context)
      need_str_has "$first_ctx" "$marker" "$order: the first consumer must deliver the message"
      need_count "$pd" 0 "$order: pending/ after the first consumer" || return 0
      second_ctx=$(hook_context "$fx" bravo)
      secondrc=$?
      need_rc "$secondrc" 0 "$order: the second (SessionStart) consumer" || return 0
    fi

    need_str_lacks "$second_ctx" "$marker" \
      "$order: requirement 8 — a message already consumed by one path must NOT be redelivered by the other; both read the same pending/"
    need_count "$pd" 0 "$order: pending/ after both consumers"
    need_count "$rd" 1 "$order: read/ after both consumers — exactly one archive entry, not two"
    need_count "$fd" 0 "$order: failed/ after both consumers"
  done
}

# V.P/101 — requirement 9: the hot path. PreToolUse fires constantly, so an empty `pending/` must
# short-circuit cheaply.
#
#   ⚠ THIS IS A GUARD, NOT A RED. Requirement 9 is a "do not add a cost" requirement, and today's
#   hook satisfies it trivially by doing no DM work at all. Manufacturing a failure would be
#   dishonest. Its at-GREEN value is what it rejects: a GREEN that hangs an unconditional
#   `_dm_jq_preflight` off the hot path — which would warn on EVERY tool call, permanently
#   polluting .brain/.hook-errors.log and tripping cmd_status's banner on a lane with no mail —
#   or one that injects an empty DM block into every tool use.
#
#   INSTRUMENT the V.Q/65 broken-jq shim, unchanged. It is OBSERVABLE evidence of the fork: if
#              the empty path never consults jq, a broken jq cannot be noticed.
#   LIVENESS   the SAME shim, the same vault, on the SessionStart consumer WITH a message queued
#   CONTROL    for a third lane, must produce a jq diagnostic. Without it, "no jq diagnostic on
#              the empty pre-tool path" is indistinguishable from "the shim never engaged". The
#              control lane is charlie so that bravo's queue stays genuinely empty, and its
#              message is sent BEFORE the shim goes on PATH (the send itself needs jq).
sc_pretool_empty_queue_short_circuits() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  base=$(dirname "$fx")
  hooklog="$fx/.brain/.hook-errors.log"

  run_brain "$fx" bravo inbox
  rc=$?
  need_rc "$rc" 0 "prerequisite: brain inbox ensures bravo's queue tree" || return 0
  need_count "$(q_dir "$fx" bravo pending)" 0 "prerequisite: bravo's queue is empty" || return 0
  run_brain "$fx" alpha dm @charlie "pretool-hotpath-liveness-57j"
  rc=$?
  need_rc "$rc" 0 "prerequisite: queue the liveness-control message for charlie" || return 0

  hotpath_stdin=$(pretool_stdin Edit file_path "$fx/notes/scratch.md")

  run_pretool "$fx" bravo "$hotpath_stdin"
  ptrc=$?
  need_rc "$ptrc" 0 "PreToolUse on an empty queue"
  need_eq "$(byte_size "$OUT")" 0 \
    "requirement 9: with nothing pending and no collision, a tool call must produce NO payload at all — an empty DM block on every tool call is exactly the hot-path cost this requirement forbids"

  shim_dir="$base/hotpath-broken-jq-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the shim directory"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'printf "jq: simulated incompatible build\\n" >&2\n'
    printf 'exit 3\n'
  } > "$shim_dir/jq" || { fail "fixture: could not write the jq shim"; return 0; }
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  before_log=$(line_count "$hooklog")
  saved_path=$PATH
  PATH="$shim_dir:$PATH"; export PATH
  run_pretool "$fx" bravo "$hotpath_stdin"
  hot_rc=$?
  hooklog_since "$fx" "$before_log" "$base/hotpath-empty.log"
  before_ctl=$(line_count "$hooklog")
  run_brain "$fx" charlie hook session-start
  hooklog_since "$fx" "$before_ctl" "$base/hotpath-control.log"
  PATH=$saved_path; export PATH        # restore BEFORE any assertion can return early
  case "$(command -v jq)" in
    "$shim_dir"/*)
      fail "instrument leak: the jq shim is STILL what PATH resolves after the restore"; return 0 ;;
  esac
  jq -e -n '1' >/dev/null 2>&1 \
    || { fail "instrument leak: the broken-jq shim survived the restore — every later scenario would be poisoned"; return 0; }

  need_file_has "$base/hotpath-control.log" "jq" \
    "instrument liveness: the SAME broken jq, with a message actually queued, must be NOTICED by the SessionStart consumer — otherwise 'the empty PreToolUse path never consulted jq' proves nothing" || return 0
  need_rc "$hot_rc" 0 "PreToolUse on an empty queue with a broken jq"
  need_file_lacks "$base/hotpath-empty.log" "jq" \
    "requirement 9: an empty pending/ must short-circuit BEFORE any jq consult — a preflight on the hot path warns on every tool call, permanently polluting .brain/.hook-errors.log and tripping cmd_status's failed-DM banner"
}

# V.P/102 — the hot-path payload budget. Authority is the phase seam map
# `.context/seams/5.7-pretool-dm-delivery.md` §2, which is later than task 5.7 and rules:
# "PreToolUse must NOT carry `cmd_status` — it fires on every Bash/Edit/Write and that payload
# is ~13.6KB." That is a requirement 9 sibling: requirement 9 bounds what the hot path COSTS to
# compute, this bounds what it SHIPS.
#   REJECTS    the single most tempting way to implement 5.7 — reusing `_hook_session_start`'s
#              context builder wholesale, which appends `cmd_status` — turning every Edit, Write
#              and Bash call into a multi-kilobyte injection.
#   NEEDLE     `Active features:` is `cmd_status`'s own section header (bin/brain:897) and is
#              printed by nothing else. The SessionStart limb below is a POSITIVE CONTROL run in
#              the same fixture: it proves the needle really is present when status IS carried,
#              so the pre-tool absence assertion cannot pass by the needle being wrong.
#   NOT PINNED any byte threshold. The seam map cites ~13.6KB as evidence, not as a limit, and
#              inventing a number would be a ruling this suite has no authority to make.
sc_pretool_payload_excludes_status() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  run_brain "$fx" alpha dm @bravo "pretool-nostatus-marker-57k"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: one message queued" || return 0

  run_pretool "$fx" bravo "$(pretool_stdin Edit file_path "$fx/notes/scratch.md")"
  ptrc=$?
  need_rc "$ptrc" 0 "the PreToolUse hook wrapper status contract" || return 0
  pretool_ctx=$(pretool_context)
  need_str_has "$pretool_ctx" "pretool-nostatus-marker-57k" \
    "the DM must be delivered (without this the absence assertion below is vacuous — an empty payload trivially lacks the status block)"
  need_str_lacks "$pretool_ctx" "Active features:" \
    "seam map §2: the PreToolUse payload must NOT carry cmd_status. PreToolUse fires on every Bash/Edit/Write, so reusing SessionStart's context builder wholesale ships a multi-kilobyte status dump on every single tool call"

  # POSITIVE CONTROL — the same needle, in the same fixture, on the path that IS meant to carry
  # status. If this limb ever goes quiet the assertion above is measuring nothing.
  run_brain "$fx" alpha dm @bravo "pretool-nostatus-control-57k"
  rc=$?
  need_rc "$rc" 0 "control: queue a message for the SessionStart limb" || return 0
  boot_ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "control: the SessionStart consumer" || return 0
  need_str_has "$boot_ctx" "Active features:" \
    "instrument control: SessionStart IS meant to carry cmd_status, so 'Active features:' must appear there — otherwise the needle is wrong and the pre-tool absence assertion above proves nothing"
}

# ═════════════════════════════════════ run ═══════════════════════════════════════════════
printf 'brain lane-DM v1.2 RED suite (claim layer deleted) + v1.2.1-v1.2.4 contract addenda\n'
printf '  engine : %s\n' "$BRAIN_BIN"
printf '  scratch: %s\n\n' "$SUITE_TMP"

scenario guard "V.S/1   inbox-prints-pending-dir"            sc_inbox_prints_pending_dir
scenario guard "V.S/2   usage-lists-dm-and-take"             sc_usage_lists_dm_and_take
scenario guard "V.S/3   send-writes-one-message-file"        sc_send_writes_one_message_file
scenario guard "V.S/4   rapid-sends-stay-distinct"           sc_rapid_sends_stay_distinct
scenario guard "V.S/5   over-cap-body-refused"               sc_over_cap_body_refused
scenario guard "V.S/6   json-special-body-round-trip"        sc_json_special_body_round_trip
scenario guard "V.S/7   dm-journals-pointer-not-body"        sc_dm_journals_pointer_not_body
scenario guard "V.S/8   journal-body-independent"            sc_journal_body_independent
scenario guard "V.S/9   secret-body-never-journalled"        sc_dm_secret_body_never_journalled
scenario guard "V.S/10  dm-all-broadcasts-not-to-self"       sc_dm_all_broadcasts_not_to_self
scenario guard "V.S/11  unknown-recipient-fails-clean"       sc_dm_unknown_recipient_fails_clean
scenario guard "V.S/12  self-send-refused"                   sc_dm_self_send_refused
scenario guard "V.S/13  init-gitignores-dm-queue"            sc_init_gitignores_dm_queue
scenario guard "V.S/14  queue-files-stay-out-of-git-status"  sc_queue_files_stay_out_of_git_status
scenario guard "V.S/15  dm-takes-no-lock"                    sc_dm_takes_no_lock
scenario guard "V.S/16  dot-temp-invisible-to-readers"       sc_dot_temp_invisible_to_readers

scenario guard "V.C/17  take-emits-and-archives"             sc_take_emits_and_archives
scenario guard "V.C/18  take-then-boot-no-replay"            sc_take_then_boot_no_replay
scenario guard "V.C/19  take-empty-is-silent-zero"           sc_take_empty_is_silent_zero
scenario guard "V.C/20  boot-delivers-offline-backlog"       sc_boot_delivers_offline_backlog
scenario guard "V.C/21  boot-no-replay-across-boots"         sc_boot_no_replay_across_boots
scenario guard "V.C/22  boot-arms-pending-and-take"          sc_boot_arms_pending_and_take
scenario guard "V.C/23  space-path-round-trip"               sc_space_path_round_trip
scenario guard "V.C/24  main-worktree-engine-from-sibling"   sc_deploy_instruction_uses_main_worktree_engine

scenario guard "V.W/25  multi-object-file-refused"           sc_multi_object_file_refused
scenario guard "V.W/26  extra-field-stripped"                sc_extra_field_stripped
scenario guard "V.W/27  oversized-from-bounded"              sc_oversized_from_bounded
scenario guard "V.W/28  multibyte-digest-byte-caps"          sc_multibyte_digest_respects_byte_caps
scenario guard "V.W/29  digest-truncates-content-not-json"   sc_digest_truncates_content_not_json
scenario guard "V.W/30  malformed-peer-does-not-suppress"    sc_malformed_peer_does_not_suppress_valid
scenario guard "V.W/31  status-surfaces-quarantined-dms"     sc_status_surfaces_quarantined_dms

scenario guard "V.X/32  send-refuses-symlinked-dm-root"      sc_send_refuses_symlinked_dm_root
scenario guard "V.X/33  send-refuses-symlinked-lane-dir"     sc_send_refuses_symlinked_lane_dir
scenario guard "V.X/34  send-refuses-symlinked-pending"      sc_send_refuses_symlinked_pending_dir
scenario guard "V.X/35  boot-refuses-symlinked-read-dir"     sc_boot_refuses_symlinked_read_dir
scenario guard "V.X/36  boot-refuses-symlinked-message"      sc_boot_refuses_symlinked_message_file

scenario guard "V.T/37  status-surfaces-open-dialog"         sc_status_surfaces_open_dialog
scenario guard "V.T/38  status-unchanged-without-dialog"     sc_status_unchanged_without_dialog
scenario guard "V.T/39  reconcile-accepts-dialog-field"      sc_reconcile_accepts_dialog_field
scenario guard "V.T/40  nav-skill-names-the-take-mechanic"   sc_nav_skill_names_the_take_mechanic
scenario guard "V.T/41  nav-skill-states-tiers-and-record"   sc_nav_skill_states_tiers_and_record
scenario guard "V.T/42  nav-skill-carries-triage-rules"      sc_nav_skill_carries_triage_rules
scenario guard "V.T/43  no-false-announce-promise"           sc_no_false_announce_promise
scenario guard "V.T/44  nav-skill-line-budget"               sc_nav_skill_line_budget
scenario guard "V.T/45  nav-skill-no-erd-referents"          sc_nav_skill_no_erd_referents

scenario red   "V.N/46  consume-has-no-claim-layer"          sc_consume_has_no_claim_layer
scenario red   "V.N/47  crash-before-emit-leaves-pending"    sc_crash_before_emit_leaves_pending
scenario red   "V.N/48  crash-after-emit-before-move"        sc_crash_after_emit_before_move_replays
scenario red   "V.N/49  invalid-file-quarantined"            sc_invalid_file_quarantined_valid_peer_delivers
scenario red   "V.N/50  bounded-backlog-continuation"        sc_bounded_backlog_instructs_continuation
scenario guard "V.N/51  occupied-read-dest-preserved"        sc_occupied_read_destination_preserved
scenario red   "V.N/52  message-id-exposed-in-digest"        sc_message_id_exposed_in_digest
scenario red   "V.N/53  global-dep-failure-leaves-pending"   sc_global_dependency_failure_leaves_everything_pending
scenario red   "V.N/54  failed-dest-collision-preserves"     sc_failed_dest_collision_preserves_record

scenario red   "V.Q/55  nonregular-entries-quarantined"      sc_nonregular_entries_quarantined_not_starving
scenario red   "V.Q/56  probed-parse-error-quarantines"      sc_probed_parse_error_code_still_quarantines
scenario red   "V.Q/57  unestablishable-jq-leaves-pending"   sc_unestablishable_jq_leaves_everything_pending
scenario red   "V.Q/58  whitespace-queue-name-rejected"      sc_whitespace_queue_name_rejected
scenario red   "V.Q/59  no-archive-without-emit"             sc_no_message_archived_that_was_not_emitted
scenario red   "V.Q/60  inherited-id-ts-cannot-escape"       sc_inherited_id_ts_cannot_escape_pending
scenario red   "V.Q/61  failed-clock-mints-no-bad-id"        sc_failed_clock_mints_no_malformed_id
scenario red   "V.Q/62  collision-anomalies-diagnosed"       sc_collision_anomalies_are_diagnosed
scenario red   "V.Q/63  take-batch-cap-warns"                sc_take_batch_cap_warns_when_entries_remain
scenario guard "V.Q/64  unwritable-failed-leaves-pending"    sc_unwritable_failed_leaves_invalid_pending
scenario red   "V.Q/65  empty-queue-does-not-consult-jq"     sc_empty_queue_does_not_consult_jq
scenario red   "V.Q/66  probed-error-code-or-fail-safe"      sc_probed_error_code_classifies_or_fails_safe
scenario red   "V.R/67  unreadable-state-operation-fatal"    sc_unreadable_state_is_operation_fatal
scenario red   "V.R/68  trailing-newline-path-quarantined"   sc_trailing_newline_path_reaches_quarantine
scenario red   "V.R/69  jq-identity-pinned-per-operation"    sc_jq_identity_is_pinned_for_operation
scenario red   "V.R/70  lane-components-byte-opaque"         sc_lane_components_never_cross_command_substitution
scenario red   "V.R/71  jq-contract-reprobe-aborts-batch"    sc_jq_contract_reprobe_aborts_batch
scenario red   "V.R/72  pinned-nonempty-session-emit"        sc_session_emit_is_pinned_and_nonempty
scenario red   "V.R/73  collision-rechecks-name-max"         sc_collision_suffix_rechecks_name_max
scenario red   "V.R/74  hidden-pending-entries-classified"   sc_hidden_pending_entries_are_classified
scenario red   "V.R/75  systemic-hook-discards-staged-batch" sc_hook_discards_staged_batch_on_systemic_jq_failure
scenario red   "V.U/76  rc0-empty-digest-is-systemic"        sc_rc0_empty_digest_is_systemic
scenario red   "V.U/77  rc0-empty-envelope-is-rejected"      sc_rc0_empty_session_envelope_is_rejected
scenario red   "V.U/78  rc0-empty-send-is-rejected"          sc_rc0_empty_send_payload_is_rejected
scenario red   "V.U/79  uninspectable-failed-status-banner"  sc_status_surfaces_uninspectable_failed_state
scenario red   "V.V/80  rc0-truncated-digest-is-systemic"    sc_rc0_truncated_digest_is_systemic
scenario red   "V.V/81  rc0-truncated-envelope-is-rejected" sc_rc0_truncated_session_envelope_is_rejected
scenario red   "V.V/82  rc0-truncated-send-is-rejected"     sc_rc0_truncated_send_payload_is_rejected
scenario red   "V.V/83  send-witness-requires-key-syntax"   sc_send_witness_requires_key_syntax
scenario red   "V.V/84  envelope-needs-escaped-digest-id"   sc_envelope_witness_requires_escaped_digest_id
scenario red   "V.V/85  regular-file-failed-status-banner"  sc_status_surfaces_regular_file_failed_state
scenario red   "V.Y/86  regular-file-lane-status-banner"    sc_status_surfaces_regular_file_lane_ancestor
scenario red   "V.Y/87  symlinked-file-root-status-banner"  sc_status_surfaces_symlinked_file_dm_root_ancestor
scenario red   "V.Y/88  unreadable-lane-status-banner"      sc_status_surfaces_unreadable_lane_ancestor
scenario guard "V.Y/89  proven-absent-failed-is-silent"     sc_status_keeps_proven_absent_failed_state_silent
scenario guard "V.Z/90  existing-empty-failed-is-silent"    sc_status_keeps_existing_empty_failed_state_silent
scenario guard "V.Z/91  positive-failed-count-is-visible"  sc_status_counts_existing_failed_entries

scenario red   "V.P/92  pretool-delivers-pending-dm"       sc_pretool_delivers_pending_dm
scenario red   "V.P/93  pretool-at-least-once-abs-counts"  sc_pretool_at_least_once_absolute_counts
scenario red   "V.P/94  pretool-archive-failure-replays"   sc_pretool_archive_failure_warns_and_replays
scenario red   "V.P/95  pretool-not-gated-by-collision"    sc_pretool_delivery_not_gated_by_collision
scenario red   "V.P/96  collision-and-dm-one-object"       sc_pretool_collision_and_dm_in_one_object
scenario red   "V.P/97  pretool-honors-inject-max-lines"   sc_pretool_honors_inject_max_lines
scenario guard "V.P/98  pretool-unresolvable-is-silent"    sc_pretool_unresolvable_whoami_is_silent
scenario red   "V.P/99  pretool-jq-gone-exactly-once"      sc_pretool_jq_missing_neither_swallows_nor_duplicates
scenario red   "V.P/100 pretool-ss-no-double-delivery"     sc_pretool_and_session_start_do_not_double_deliver
scenario guard "V.P/101 pretool-empty-queue-short-circuit" sc_pretool_empty_queue_short_circuits
scenario red   "V.P/102 pretool-payload-excludes-status"   sc_pretool_payload_excludes_status

NON_GUARD_FAILED=$((FAILED - GUARD_FAILED))
printf '\n── summary ──\n'
printf 'scenarios: %s   passed: %s   failed: %s\n' "$TOTAL" "$PASSED" "$FAILED"
printf 'non-guard failures: %s   guard failures: %s\n' "$NON_GUARD_FAILED" "$GUARD_FAILED"

# A guard regression means a behaviour that WORKS TODAY was broken — during the GREEN loop that
# is categorically different from "a RED scenario is still red", so it gets its own exit code
# instead of being averaged into the generic failure count. [F9]
[ "$GUARD_FAILED" -eq 0 ] || exit 3
[ "$FAILED" -eq 0 ] || exit 1
exit 0
