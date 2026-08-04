#!/usr/bin/env sh
# test/dm.sh — RED-phase suite for the Agent-Brain lane-DM feature, v1.2 (claim layer DELETED).
#
# AUTHORITY (in precedence order):
#   1. .context/seams/dm-v1.1-queue.md, the `# v1.2` section (lines 335-467) — THE design
#      authority, DECIDED by Steve 2026-08-04. It supersedes decisions 4, 6, 6b and 6c for the
#      consume path; send-side atomicity (decisions 2 + 3) is explicitly UNCHANGED. Its "Delete"
#      list, its 8-item "Must survive" checklist, its "Poison, without a counter" ruling and its
#      "Suite consequences" retire/keep/add lists are this file's spec.
#   2. The same map's surviving v1.1 sections — decision 2 (dot-temp + same-directory rename),
#      decision 3 (message ID = filename = <_now_compact>-<pid>[+ collision bump]), decision 7
#      (wire format from/to/ts/content), decision 8 (DM_MAX_BODY kept), the `_dm_dir_ok` and
#      `_dm_digest` seams, and the altitude decision "no lock anywhere on the queue path".
#   3. docs/lane-dm-ultrareview-findings.md — UR-1 (emit before the terminal move), UR-2 (symlink
#      component refusal), UR-3 (a live-observed message is really consumed), UR-8 (no false
#      announce promise), UR-9/UR-10 (round-trip + body-independent journal).
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
#   · The per-invocation batch size K is NOT pinned — only that a bound exists (V.N/50 caps
#     delivery at DM_INJECT_MAX_LINES over a 45-entry backlog), that bounding destroys nothing,
#     and that successive invocations drain the remainder without starvation. The map says "one
#     'process at most K entries' cap" and deliberately does not name K, so pinning a value here
#     would invent a ruling. A map decision, not an oversight. [L9]
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

# ═════════════════════════════════════ run ═══════════════════════════════════════════════
printf 'brain lane-DM v1.2 RED suite (claim layer deleted)\n'
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
