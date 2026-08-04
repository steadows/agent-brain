#!/usr/bin/env sh
# test/dm.sh — RED-phase suite for the Agent-Brain lane-DM feature, v1.1 per-message queue.
#
# AUTHORITY (in precedence order):
#   1. .context/seams/dm-v1.1-queue.md — THE design authority. Storage layout (decision 1),
#      send = temp+atomic-rename (2), message-ID/filename grammar (3), claim (4), ack (5),
#      lease-based stale-claim recovery (6), poison cap → failed/ (6b), claim-loss vs real
#      error (6c), durability boundary (6d), wire format (7), and the New seams section
#      (_atomic_place, _dm_dir_ok, _dm_new_id, _dm_claim_all/_dm_recover_stale/_dm_ack,
#      cmd_dm_take, the _dm_digest signature change, and what is DELETED not extended).
#   2. docs/lane-dm-ultrareview-findings.md — UR-1..UR-10. This suite makes UR-1, UR-2, UR-3,
#      UR-9 and UR-10 falsifiable.
#   3. ROADMAP.md "v1.1 — DM per-message queue" — the added acceptance criteria.
#   4. AGENT_BRAIN_DM_GSD_PLAN.md §7.5 — disposition of all 10 findings.
# Implementation code is EVIDENCE, never authority. Where this suite pins something the seam
# map leaves open, the scenario comment says so out loud and names the choice that was forced.
#
# WHAT REPLACED WHAT: the v1 suite pinned the single shared dm/<lane>/inbox.jsonl and its
# boot-time rotate→deliver ordering. Both are deleted by the redesign, so every transport and
# hook scenario here is new or re-pinned. Scenarios whose OBSERVABLE behaviour survives the
# rewrite (journal pointer-not-body, secret-body-never-journalled, self-send, unknown
# recipient, broadcast-not-to-self, gitignore, no-lock, dialog_with presence, nav-skill
# template) are carried forward, re-pinned to the new storage layout where they touch storage.
#
# SAFETY: every scenario runs inside a throwaway git repo under a single mktemp -d root.
# The engine is never invoked with a real repository as CWD, and HOME is redirected into
# the fixture so no machine-global file can be touched. The secret probe string and every
# symlink target exist only in this file and inside those throwaway repos. Scenarios that
# chmod a directory read-only restore the mode BEFORE any early return, so the EXIT trap can
# still descend and remove the scratch root.
#
# DECLARED GAPS (absence here is a decision, not an oversight):
#   · UR-4a / UR-4b (`brain commit`) and UR-7 (`cmd_install`) have NO scenario in this file. The
#     seam map sequences them "with the rewrite, not inside it" (§"UR fixes riding along — small,
#     self-contained — sequenced with the rewrite, not inside it"), so they need their own RED
#     pass against the commit/install paths, not a DM-transport scenario. [F13]
#   · `_atomic_place`'s "temp cleaned up on FAILURE" limb is only partially covered. Q.S/2, Q.S/8
#     and Q.S/9 assert no `.tmp-*` residue after a completed send and after both refusal paths,
#     and Q.R/25 covers the stale-temp sweep — but a temp abandoned by a crash BETWEEN create and
#     rename is not drivable from the CLI (there is no injectable failure point inside the
#     helper), so no scenario claims it. Cover it in a unit harness if the helper grows one. [F12]
#
# RED DISCIPLINE: scenarios pinning v1.1 behaviour MUST fail against the current engine —
# the commands and directories do not exist yet. Scenarios labelled "guard:" are regression
# guards that legitimately pass today and must keep passing. Every guard was mutation-probed
# against a deliberately non-compliant copy of bin/brain and shown to REJECT it, so a green
# guard means the behaviour is present, not that the assertion is toothless.
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

# Constants the seam map ratifies. Restated here so a scenario reads against a NAME, and so a
# change to either constant surfaces as one edit rather than scattered magic numbers.
DM_CLAIM_MAX_AGE=600      # seam decision 6  — stale-claim lease, seconds (dirq maxlock)
DM_MAX_ATTEMPTS=3         # seam decision 6b — deliveries before a message routes to failed/
DM_TEMP_MAX_AGE=300       # seam decision 6  — stale .tmp-* purge, seconds (dirq maxtemp)
DM_MAX_BODY=4096          # seam decision 8  — body cap KEPT (rationale rewritten, value unchanged)
DM_INJECT_MAX_LINES=40    # seam "injection bounds" — USE as-is

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
# is used whether the caller wants captured streams, tag-scoped streams (concurrency), or a
# CLOSED stdout (the emit-failure instrument). Always run inside ( ) — it cd's and exec's.
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
# '-' as the outfile CLOSES stdout instead of redirecting it — that is how Q.R/24 drives the
# "emit failed, so the message must NOT be retired" limb of UR-1.
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

# run_brain_tagged <tag> <repo> <identity> [args...] — tag-scoped stream files so two
# invocations can run CONCURRENTLY without clobbering each other's captures. Does NOT touch
# $OUT/$ERR. Safe to background:  run_brain_tagged a "$fx" bravo dm take &
run_brain_tagged() {
  _rt_tag=$1; shift
  _rt_base=$(dirname "$1")
  _brain_env_run "$_rt_base/last.$_rt_tag.out" "$_rt_base/last.$_rt_tag.err" "$@"
}
tagged_out() { printf '%s' "$(dirname "$1")/last.$2.out"; }
tagged_err() { printf '%s' "$(dirname "$1")/last.$2.err"; }

# ── queue-layout helpers (seam decision 1) ───────────────────────────────────────────────
# q_dir <repo> <lane> <state>  where state ∈ pending | claimed | read | failed
q_dir() { printf '%s' "$1/.brain/dm/$2/$3"; }

# journal entry lines ("- <ts> <feat> — <msg>") across every journal file in the vault
journal_entries() { grep -h '^- ' "$1"/.brain/journal/*.md 2>/dev/null || true; }
journal_entry_count() { journal_entries "$1" | wc -l | tr -d ' \n'; }
journal_raw_count() { cat "$1"/.brain/journal/*.md 2>/dev/null | wc -l | tr -d ' \n'; }
journal_since() { journal_entries "$1" | tail -n +"$(($2 + 1))"; }

line_count() { [ -f "$1" ] || { printf '0'; return 0; }; wc -l < "$1" | tr -d ' \n'; }
byte_size()  { [ -f "$1" ] || { printf '0'; return 0; }; wc -c < "$1" | tr -d ' \n'; }

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

# Dot-prefixed entries — the temp names (seam decision 2: temp = `.tmp-<id>` inside pending/).
# A plain `for f in dir/*` never sees them, which is exactly the property the design relies on;
# this helper is how the suite checks the invariant the reader glob cannot.
count_dotfiles() {
  _cd=0
  for _cd_f in "$1"/.*; do
    case "${_cd_f##*/}" in .|..) continue ;; esac
    [ -e "$_cd_f" ] || [ -L "$_cd_f" ] || continue
    _cd=$((_cd + 1))
  done
  printf '%s' "$_cd"
}

# <id> is the IMMUTABLE substring the seam requires be preserved across every transition
# (decision 6b, Bernstein's "preserve the uniq string" rule): strip the `.a<k>[...]` tail.
msg_id_of() { _mi=${1##*/}; printf '%s' "${_mi%.a*}"; }

# delivery-attempt counter k from `<id>.a<k>` / `<id>.a<k>.c<ts>-<pid>`; non-zero if absent.
attempt_of() {
  _ao=${1##*/}
  case "$_ao" in *.a[0-9]*) ;; *) return 1 ;; esac
  _ao=${_ao#*.a}; _ao=${_ao%%.*}
  case "$_ao" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$_ao"
}

# <claim-ts> from `.c<claim-ts>-<claimer-pid>`; non-zero if the name carries no claim stamp.
claim_ts_of() {
  _ct=${1##*/}
  case "$_ct" in *.c*) ;; *) return 1 ;; esac
  _ct=${_ct##*.c}
  case "$_ct" in *-*) ;; *) return 1 ;; esac
  printf '%s' "${_ct%-*}"
}

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

# `brain status` ECHOES recent journal lines verbatim. The DM call-log pointer wording is GREEN's
# to rewrite and may legitimately contain the word "failed", so a control that grepped ALL of
# status would fire on the echo rather than on the failed-queue banner. Q.R/22's controls
# therefore look ONLY at status's own rendering.
# The filter is anchored to the REAL journal entry format written by _announce_as —
# `- <ISO-8601-ts> <feat> — <msg>` — not to a bare "- " prefix: a failed-queue banner rendered as
# a column-0 markdown bullet would be eaten by the looser filter and falsely red Q.R/22. [F3/R2-3]
status_has_failed() { grep -vE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$1" 2>/dev/null | grep -qi 'failed'; }

# Journal-line SHAPE: the line with every digit removed. Timestamps, pids and message ids are
# all digit-bearing, so two sends of two different bodies must produce the SAME shape — while a
# base64/hex/encoded body leaves differing letters behind and breaks the equality. This is
# UR-10's "compare journal payloads for two different bodies and require body-independence"
# branch, chosen because the seam map does not pin the call-log grammar itself.
journal_shape() { printf '%s' "$1" | tr -d '0-9'; }

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

# grammar gate for a queued message name (seam decisions 3 + 6b):
#   <_now_compact>-<pid>[-<n>]  .a<k>        where _now_compact is %Y%m%dT%H%M%SZ
need_queue_name() { # <path> <label>
  _nq=${1##*/}
  printf '%s' "$_nq" | grep -qE '^[0-9]{8}T[0-9]{6}Z-[0-9][0-9]*(-[0-9][0-9]*)?\.a[0-9][0-9]*$' \
    && return 0
  fail "$2: '$_nq' does not match the ratified name grammar <ts>-<pid>[-<n>].a<k> (seam decisions 3 + 6b; <ts> is _now_compact's %Y%m%dT%H%M%SZ)"
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

# mint_stuck_claim <repo> <lane> — leave ONE genuinely engine-minted claim stuck in claimed/:
# claimed but never acked. That is precisely UR-1's kill-after-claim state.
#
# HOW: pre-create read/ read-only, so the claim (pending/ → claimed/) succeeds while the ack
# rename (claimed/<name> → read/<id>.a<k>) gets EACCES. The mode is restored before returning.
#
# ENGINE-MINTED IS PRIMARY; hand-minted is the fallback. The seam map has since RULED the
# encoding — "<claim-ts> encoding — RULED: Unix epoch seconds (gap (a) closed 2026-08-04)" — so a
# hand-minted claim name is now authority-grounded rather than an invented ruling. The fallback
# exists because a fail-CLOSED engine (one that refuses to claim while read/ is unwritable — a
# shape the seam does not forbid) would otherwise silently kill Q.R/20/21/22 instead of testing
# them. `age_claim` still detects either encoding, so the ruling forces no test change. [F5]
#
# ⚠ WHEN THE FALLBACK FIRES the claim NAME was written by this fixture, so Q.R/20's name-shape
# assertions are then checking the fixture, not the engine. The engine's own claim and ack naming
# is pinned independently by Q.T/12 and Q.B/16, neither of which uses this instrument.
#
# prints the claimed file path; rc 1 = fixture error, 2 = instrument blind, 4 = nothing in
# pending/ to claim (i.e. the SEND seam is what is missing, not the claim seam).
mint_stuck_claim() {
  _ms_fx=$1; _ms_lane=$2
  make_readonly_dir "$(q_dir "$_ms_fx" "$_ms_lane" read)"
  _ms_rc=$?
  [ "$_ms_rc" = 0 ] || return "$_ms_rc"

  run_brain "$_ms_fx" "$_ms_lane" dm take
  chmod 755 "$(q_dir "$_ms_fx" "$_ms_lane" read)" 2>/dev/null || true

  if _ms_c=$(first_file "$(q_dir "$_ms_fx" "$_ms_lane" claimed)"); then
    printf '%s' "$_ms_c"; return 0
  fi
  # fallback: the engine declined to claim — hand-mint the same state. Authority for the epoch
  # encoding: seam map, "<claim-ts> encoding — RULED: Unix epoch seconds".
  _ms_p=$(first_file "$(q_dir "$_ms_fx" "$_ms_lane" pending)") || return 4
  mkdir -p "$(q_dir "$_ms_fx" "$_ms_lane" claimed)" || return 1
  _ms_hand="$(q_dir "$_ms_fx" "$_ms_lane" claimed)/${_ms_p##*/}.c$(date -u +%s)-1"
  mv "$_ms_p" "$_ms_hand" || return 1
  printf '%s' "$_ms_hand"
}

# Turn a mint_stuck_claim rc into ONE precise scenario failure. Called by every consumer so the
# same diagnosis is reported identically wherever the instrument could not be built.
mint_failed() { # <rc>
  case "$1" in
    2) fail "instrument blind: a rename into a 0500 directory still succeeds (running as root?) — the stuck-claim instrument cannot be built on this machine" ;;
    4) fail "no message in pending/ to claim — the send did not land as a per-message file, so the claim/recovery seam cannot be reached yet (fix the send path first)" ;;
    *) fail "stuck-claim fixture failed (rc=$1) — neither 'brain dm take' nor the hand-minted fallback could leave a claim in claimed/" ;;
  esac
}

# age_claim <claimed-file> <seconds-back> — rewrite the claim's <claim-ts> to <seconds-back>
# in the past, preserving <id>, .a<k> and the claimer-pid component. Detects the encoding
# rather than assuming it: all-digits ⇒ epoch seconds, `<digits>T<digits>Z` ⇒ _now_compact.
# Anything else is an unrecognised encoding and returns non-zero (an actionable RED, never a
# silent skip). Prints the new path.
age_claim() {
  _ac_f=$1; _ac_back=$2
  _ac_b=${_ac_f##*/}; _ac_d=${_ac_f%/*}
  _ac_ts=$(claim_ts_of "$_ac_f") || return 1
  case "$_ac_ts" in
    ''|*[!0-9TZ]*) return 1 ;;
  esac
  case "$_ac_ts" in
    *T*Z) _ac_min=$(( (_ac_back + 59) / 60 ))   # round UP: never land ON the lease boundary
          _ac_new=$(date -u -v-"$_ac_min"M +%Y%m%dT%H%M%SZ 2>/dev/null \
                 || date -u -d "$_ac_min minutes ago" +%Y%m%dT%H%M%SZ 2>/dev/null) ;;
    *)    _ac_new=$(( _ac_ts - _ac_back )) ;;
  esac
  [ -n "$_ac_new" ] || return 1
  _ac_pre=${_ac_b%.c*}
  _ac_pid=${_ac_b##*-}
  mv "$_ac_f" "$_ac_d/$_ac_pre.c$_ac_new-$_ac_pid" || return 1
  printf '%s' "$_ac_d/$_ac_pre.c$_ac_new-$_ac_pid"
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

# ══════════════════════════ Q.S — send / storage layout ══════════════════════════════════

# Q.S/1 — `brain inbox` prints the pending/ DIRECTORY to arm on, and the retired single-inbox
# file is never created.
#   PROVES     the arming target moved from a FILE to a DIRECTORY (seam, "Deleted, not
#              extended": _inbox_ensure's append-creation semantics die; cmd_inbox "now ensures
#              the directory tree and prints the pending/ dir to arm on").
#   DOES NOT   pin which of claimed/ read/ failed/ are created eagerly — the seam says "the
#   PROVE      directory tree" without enumerating, so only pending/ is required here. An
#              engine that also pre-creates the others passes.
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
    *) fail "brain inbox must print the pending/ DIRECTORY (seam: cmd_inbox ensures the tree and prints pending/), got: $path" ;;
  esac
  need_real_dir "$path" "the printed arming target"
  need_file_absent "$fx/.brain/dm/alpha/inbox.jsonl" \
    "the retired single-shared-inbox file (v1.1 deletes it; nothing may re-create it)"
}

# Q.S/1b — the dispatcher and usage() must both know the live-consumption command. Without
# `dm take` in usage(), UR-3's fix is undiscoverable by the agent that has to run it.
sc_usage_lists_dm_inbox_and_take() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha help
  rc=$?
  need_rc "$rc" 0 "brain help" || return 0
  need_file_has "$OUT" "brain announce" "usage() baseline (an existing command is listed)" || return 0
  need_file_has "$OUT" "brain dm" "usage() must list the dm subcommand"
  need_file_has "$OUT" "brain inbox" "usage() must list the inbox subcommand"
  need_file_has "$OUT" "dm take" "usage() must list the live-consumption command (seam: cmd_dm_take — UR-3's fix)"
}

# Q.S/2 — ONE message is ONE file: name grammar, single JSON object, no temp residue, and no
# copy anywhere but the recipient's pending/.
#   REJECTS    an append-based encoder (jq -s length would be > 1), a shared-inbox regression
#              (count in pending/ would be 0), a temp left behind by a completed send, and a
#              self-copy that boot delivery would read back to the sender.
#   INITIAL ATTEMPT COUNTER — RATIFIED. The map was silent when this scenario was written; the
#   RED pass surfaced the gap and the map then closed it: "_dm_new_id … A fresh send mints
#   attempt counter ZERO: `<id>.a0` (gap (b) closed 2026-08-04 — the map was silent; the RED
#   suite pins `.a0` at Q.S/2 and this ruling ratifies it)". Authority-backed, not a guess. [F11]
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
  need_queue_name "$f" "queued message name"
  need_eq "$(attempt_of "$f")" 0 \
    "delivery-attempt counter on a FRESHLY SENT message (seam map, _dm_new_id: 'A fresh send mints attempt counter ZERO')"

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

# Q.S/2b — three sends land as three DISTINCT files. Sends from separate processes in the same
# clock second differ only by <pid>, which is exactly what seam decision 3 relies on; a
# timestamp-only id would collapse them and lose messages silently.
#   DOES NOT   exercise the `-<n>` collision bump: that fires only on same-second PID REUSE,
#   PROVE      which cannot be forced here (measured, not assumed). The grammar gate accepts it.
sc_rapid_sends_stay_distinct() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  for m in rapid-a1 rapid-b2 rapid-c3; do
    run_brain "$fx" alpha dm @bravo "$m"
    rc=$?
    need_rc "$rc" 0 "brain dm @bravo ($m)" || return 0
  done

  need_count "$pd" 3 "message files after three sends (a colliding id would show fewer)" || return 0
  for f in "$pd"/*; do
    [ -e "$f" ] || continue
    need_queue_name "$f" "queued message name"
  done
  for m in rapid-a1 rapid-b2 rapid-c3; do
    need_tree_has "$pd" "$m" "every sent body must still be in pending/ ($m)"
  done
}

# Q.S/2c — the body cap survives the redesign. Seam decision 8: "DM_MAX_BODY kept, rationale
# rewritten" — the PIPE_BUF justification evaporates under one-file-per-message, but the constant
# and its refusal behaviour stay (it now bounds storage and digest cost, not atomicity). An
# over-cap send is REFUSED outright: nothing queued, nothing journalled, no temp residue.
# BASELINE-GREEN: v1 already enforces the cap. This guards against the rewrite quietly DROPPING
# the cap while rewriting the comment that justifies it — the seam map changes the rationale and
# an implementer reading only "that rationale evaporates" could reasonably delete the check. [F7]
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

# Q.S/3 — UR-9. A body carrying `"`, `\`, a tab and an INTERNAL NEWLINE must round-trip byte
# for byte. This is the finding's whole point: every v1 test body was JSON-safe ASCII, so a
# naïvely interpolated encoder passed them all while corrupting exactly these four characters.
#   REJECTS    string-interpolated JSON (invalid object, or the newline splitting the file into
#              two JSON values), and any lossy escape/unescape round trip.
sc_ur9_json_special_body_round_trip() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx")
  pd=$(q_dir "$fx" bravo pending)
  # all four hazards, plus an ASCII marker so delivery can be checked without newline games
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

  # ...and it must survive DELIVERY too, not just storage.
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take (JSON-special body)" || return 0
  need_file_has "$OUT" "ur9mark" "the JSON-special message must actually be delivered by take"
}

# Q.S/4 — carried from v1, re-pinned. The journal keeps a POINTER, never the body.
#   The pointer's exact path form is deliberately NOT pinned: the seam map replaces the storage
#   layout but never restates the call-log grammar, so this asserts only what v1 ratified and
#   the redesign preserves — the line names the recipient and points into that lane's dm tree.
#   Q.S/5 is what closes UR-10's encoded-body hole; this scenario is the literal-leak half.
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

# Q.S/5 — UR-10. The v1 scenarios rejected only LITERAL fragments, so a call-log line carrying
# `base64(content)` passed every assertion while committing a reversible credential.
#   INSTRUMENT the journal line with every DIGIT removed. Timestamps, pids and message ids are
#              digit-bearing, so two sends of two DIFFERENT bodies must normalise to the SAME
#              string. Any body-derived component — base64, hex, a length, a hash, a prefix —
#              leaves differing letters behind and breaks the equality.
#   FIXTURE    the two bodies are the same LENGTH and contain no digits, so a length field or a
#              digit-only encoding cannot smuggle a difference past the normaliser either.
#   COVERS     the direct path AND the @all broadcast path (the finding requires both).
#   BASELINE-GREEN: the current jq-based writer is already body-independent — UR-10 is a SUITE
#   hole, not an engine bug — so this passes today and must keep passing. Verified DISCRIMINATING
#   against a mutant engine that appends [b64:<body>] to the call-log line: that mutant satisfies
#   every literal-fragment assertion (v1's whole test) and is rejected by the shape comparison.
sc_ur10_journal_body_independent() {
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
  need_eq "$s3" "$s4" \
    "BROADCAST call-log line is not body-independent (UR-10)"

  # positive control: both bodies really were transported, so a clean journal means something
  need_tree_has "$fx/.brain/dm" "$b1" "body #1 reached the queue (positive control)"
  need_tree_has "$fx/.brain/dm" "$b2" "body #2 reached the queue (positive control)"
  need_tree_lacks "$fx/.brain/journal" "$b1" "body #1 anywhere under journal/"
  need_tree_lacks "$fx/.brain/journal" "$b2" "body #2 anywhere under journal/"
}

# Q.S/6 — carried. A secret-shaped body leaves no trace under journal/. The secret LEADS the
# body and repeats, so a prefix-truncating leak cannot hide it: any leaked fragment of >= 4
# chars contains 'AWS_', and of >= 21 the whole key name.
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

# Q.S/7 — carried, re-pinned to per-message files. @all lands in every registered lane's
# pending/ and never the sender's; one invocation still writes ONE journal line.
sc_dm_all_broadcasts_not_to_self() {
  fx=$(make_vault alpha bravo charlie delta) || fatal "fixture build failed"
  body="resync-before-your-gates-9c1"
  # the fan-out is NOT gated on who looks live: charlie LOOKS dormant (two-month-old updated:),
  # delta is explicitly done. Both are registered, so both must still receive it.
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
    need_queue_name "$f" "$why broadcast message name"
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

# Q.S/8 — carried. An unknown recipient fails cleanly: no lane tree, no journal line, and no
# temp residue anywhere (a half-written .tmp-* would be the atomic-placement helper leaking).
# BASELINE-GREEN; verified discriminating against a mutant that journals a rejected send.
sc_dm_unknown_recipient_fails_clean() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  # prerequisite: the dm path works at all, so a non-zero exit below means "rejected",
  # not "subcommand missing".
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

# Q.S/9 — carried. A self-send is refused, writes nothing, journals nothing, leaves no temp.
# BASELINE-GREEN; verified discriminating against a mutant that journals a rejected send.
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

# Q.S/10a — guard. The existing `dm/` ignore rule is PREFIX-scoped, so the new subtree is
# already covered (Stage-2 seam finding: "no new-layout work needed here"). This guard is what
# would catch a regression that narrowed the rule to the old inbox.jsonl path.
# BASELINE-GREEN; verified discriminating against a mutant whose fresh init omits the dm/ rule.
sc_init_gitignores_dm_queue() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  # positive control on the instrument: check-ignore must NOT match a tracked vault path
  if git -C "$fx" check-ignore -q .brain/presence/alpha.md 2>/dev/null; then
    fail "instrument broken: git check-ignore matches .brain/presence/alpha.md"
    return 0
  fi
  for p in .brain/dm/bravo/pending/20260101T000000Z-1.a0 \
           .brain/dm/bravo/claimed/20260101T000000Z-1.a0.c1-1 \
           .brain/dm/bravo/read/20260101T000000Z-1.a0 \
           .brain/dm/bravo/failed/20260101T000000Z-1.a3; do
    git -C "$fx" check-ignore -q "$p" 2>/dev/null \
      || fail "a fresh init does not gitignore $p (git check-ignore did not match)"
  done
}

# Q.S/10b — a real send leaves nothing in `git status`. RED today only because the precondition
# (one file in pending/) does not hold yet; the ignore half is already true.
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

# Q.S/11 — structural witness, carried: the queue path takes NO lock, under ANY name.
# Seam altitude decision: "No lock anywhere on the queue path — rename arbitration IS the
# concurrency control; reusing _lock_acquire (no staleness break) would reintroduce the wedge
# the design exists to remove."
#   INSTRUMENT making .brain/.locks read-only is NAME-agnostic: _lock_acquire creates
#              $BRAIN/.locks/<k>.lock whatever <k> is, so any lock protocol fails here while a
#              lock-free send is unaffected. A witness keyed on a literal lock name would miss
#              a lock taken under a global key. A stale per-lane dm/<to>/.lock is pre-created
#              too, since a bespoke lock need not live under .brain/.locks at all.
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

  # ALL THREE queue paths must be lock-free, not just the send: the seam's altitude decision is
  # "No lock ANYWHERE on the queue path". A consume or boot that locked would wedge exactly the
  # way the design exists to prevent. [F8]
  t0=$(date +%s)
  run_brain "$fx" alpha dm @bravo "no-lock-probe-3c"
  rc=$?
  # Sample the post-SEND queue state HERE: the take below must EMPTY pending/ (Q.T/12), so
  # asserting pending/ after it would make this scenario unsatisfiable under GREEN. Captured
  # into variables rather than asserted inline, because an assertion that returns early would
  # skip the chmod restore below and leave .brain/.locks read-only for the EXIT trap. [R2-1]
  pend_after_send=$(count_files "$(q_dir "$fx" bravo pending)")
  pend_has_body=no
  grep -rqF -- "no-lock-probe-3c" "$(q_dir "$fx" bravo pending)" 2>/dev/null && pend_has_body=yes
  run_brain "$fx" bravo dm take
  trc=$?
  run_brain "$fx" bravo hook session-start
  hrc=$?
  t1=$(date +%s)
  # restore BEFORE any early return — the EXIT-trap rm -rf needs to descend here
  chmod 755 "$locks" 2>/dev/null || true

  need_rc "$rc" 0 "brain dm with .brain/.locks read-only and a stale dm/bravo/.lock (the SEND path takes no lock)" || return 0
  need_rc "$trc" 0 "brain dm take under a read-only .brain/.locks (the CONSUME path takes no lock)"
  need_rc "$hrc" 0 "hook session-start under a read-only .brain/.locks (the BOOT path takes no lock)"
  # Bound covers all three invocations: baseline is ~1.5s, and ONE _lock_acquire spin adds ~5s
  # (50 x 0.1s), so 4s separates them without courting flake. Measured non-flaky across repeat
  # runs at a 55s whole-suite load on this machine.
  elapsed=$((t1 - t0))
  [ "$elapsed" -le 4 ] || fail "send+take+boot took ${elapsed}s — something spun on a lock (want <= 4s; one lock spin costs ~5s)"
  # positive control, sampled BETWEEN the send and the take — the send really did deliver
  need_eq "$pend_after_send" 1 "message files in pending/ immediately after the lock-free send"
  need_eq "$pend_has_body" yes "the sent body reached pending/ (positive control)"
  # ...and the lock-free CONSUME path then carried it through to the acked archive
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the take (the consume path completed without a lock)"
  need_tree_has "$(q_dir "$fx" bravo read)" "no-lock-probe-3c" "the acked archive carries the delivered content"
}

# ══════════════════════════ Q.T — take (the live path, UR-3) ═════════════════════════════

# Q.T/12 — `brain dm take` claims, prints, acks. Seam: cmd_dm_take = recover → claim all →
# print each → ack each, and ack is `claimed/<full-name>` → `read/<id>.a<k>`.
#   PROVES     every claimed message reaches a TERMINAL acked state (claimed/ empty afterwards),
#              the immutable <id> substring survives both transitions (decision 6b), and a
#              second take consumes nothing — the SEQUENTIAL half of accepted finding #11.
#   REJECTS    a take that prints without claiming (pending/ would still hold the files), one
#              that claims without acking (claimed/ non-empty), and one that re-consumes.
sc_take_claims_prints_acks() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)

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

  need_count "$pd"  0 "pending/ after take (a claim empties it)"
  need_count "$cd_" 0 "claimed/ after take (every claim must be acked once delivery succeeded)"
  need_count "$rd"  2 "read/ after take"
  need_dir_has_id "$rd" "$id1" "the acked archive must preserve message id #1 (seam 6b)"
  need_dir_has_id "$rd" "$id2" "the acked archive must preserve message id #2 (seam 6b)"

  # sequential no-double-consume: a second take sees nothing and changes nothing.
  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "second brain dm take (empty queue)"
  need_eq "$(line_count "$OUT")" 0 "stdout lines from a take on an empty queue"
  need_count "$rd" 2 "read/ after the second take (nothing re-consumed, nothing duplicated)"
}

# Q.T/13 — UR-3. A live-observed message must be CLAIMED, not merely seen: after `dm take`,
# the next SessionStart must not replay it.
#   NEGATIVE   a message sent AFTER the take must still be reported at that same boot —
#   CONTROL    otherwise "boot did not replay" would be satisfied by a boot that reports
#              nothing at all.
sc_ur3_take_then_boot_no_replay() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha dm @bravo "live-read-a7k"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send before the live read" || return 0

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take (the live read)" || return 0
  need_file_has "$OUT" "live-read-a7k" "take must actually deliver the message (positive control)" || return 0
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the live read (the message was acked)" || return 0

  run_brain "$fx" alpha dm @bravo "after-take-b8m"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send AFTER the live read" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "hook session-start as bravo" || return 0
  need_str_has  "$ctx" "after-take-b8m" "the boot must still deliver a message sent after the take (negative control)"
  need_str_lacks "$ctx" "live-read-a7k"  "a message already consumed by 'dm take' must NOT be replayed at the next boot (UR-3)"
}

# Q.T/14 — an empty queue is a silent success. Seam: cmd_dm_take "exits 0 with no output when
# empty". A watcher runs this on every inbox flutter, so noise or a non-zero exit is a defect.
sc_take_empty_is_silent_zero() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "brain dm take on an empty queue" || return 0
  need_eq "$(line_count "$OUT")" 0 "stdout lines from an empty take"
  need_eq "$(byte_size "$OUT")" 0 "stdout bytes from an empty take"
}

# Q.T/15 — two CONCURRENT consumers of one lane get DISJOINT messages. This is accepted finding
# #11's structural fix: rename(2) arbitration means each of two sessions wins a distinct set,
# with no lock (seam decision 4).
#   ASSERTION  every marker appears in EXACTLY ONE of the two captures (disjoint AND complete),
#              which is deterministic under a correct implementation regardless of how the race
#              actually falls. A double-consume shows as a marker in both; a lost message shows
#              as a marker in neither.
#   6c LIMB    both takes must exit 0. Decision 6c says the loser of a claim race "continues
#              silently" — a non-zero exit or a hard failure there is conflating a lost race
#              with a real error. This only bites when the race actually fires, so treat it as
#              opportunistic evidence, not a proof of the silent path.
sc_two_consumers_disjoint() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)

  for m in c1 c2 c3 c4 c5 c6; do
    run_brain "$fx" alpha dm @bravo "concurrent-$m-marker"
    rc=$?
    need_rc "$rc" 0 "prerequisite: send concurrent-$m" || return 0
  done
  need_count "$pd" 6 "prerequisite: six messages queued" || return 0

  run_brain_tagged conA "$fx" bravo dm take &
  pa=$!
  run_brain_tagged conB "$fx" bravo dm take &
  pb=$!
  wait "$pa"; rca=$?
  wait "$pb"; rcb=$?
  oa=$(tagged_out "$fx" conA); ob=$(tagged_out "$fx" conB)

  need_rc "$rca" 0 "concurrent take A (decision 6c: losing a claim race is SILENT, not an error)"
  need_rc "$rcb" 0 "concurrent take B (decision 6c: losing a claim race is SILENT, not an error)"

  for m in c1 c2 c3 c4 c5 c6; do
    seen=0
    grep -qF -- "concurrent-$m-marker" "$oa" 2>/dev/null && seen=$((seen + 1))
    grep -qF -- "concurrent-$m-marker" "$ob" 2>/dev/null && seen=$((seen + 1))
    case "$seen" in
      1) ;;
      0) fail "concurrent-$m was delivered to NEITHER consumer — a message was lost" ;;
      *) fail "concurrent-$m was delivered to BOTH consumers — double-consume (accepted finding #11 is not closed)" ;;
    esac
  done

  need_count "$pd" 0 "pending/ after two concurrent takes"
  need_count "$(q_dir "$fx" bravo claimed)" 0 "claimed/ after two concurrent takes"
  need_count "$(q_dir "$fx" bravo read)" 6 "read/ after two concurrent takes (all six acked exactly once)"
}

# ══════════════════════════ Q.B — boot delivery (UR-1 ordering) ══════════════════════════

hook_context() { # <repo> <identity> → prints additionalContext, non-zero if it can't
  run_brain "$1" "$2" hook session-start
  _hc_rc=$?
  [ "$_hc_rc" = "0" ] || return 1
  jq -e -r '.hookSpecificOutput.additionalContext // empty' "$OUT" 2>/dev/null
}

# Q.B/16 — offline delivery under the NEW order (recover → claim → digest → emit → ack).
# THREE queued messages from TWO senders: a dormant lane wakes to a QUEUE, so one-message
# coverage would let a `tail -1`-shaped delivery pass while dropping everything older.
#   PROVES     per-message claim+ack (read/ holds three separate entries carrying the original
#              ids), sender attribution survives delivery, and — the structural half — that
#              the BATCH ROTATION IS GONE: no `<ts>-<pid>.jsonl` archive and no inbox.jsonl.
#   REJECTS    the v1 rotate-then-deliver shape wholesale, and any delivery that collapses N
#              messages into one archive blob.
sc_boot_delivers_and_acks_per_message() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  q1="q1a4"; q2="q2b5"; q3="q3c6"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)
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
  id1=$(id_of_body "$pd" "queued-$q1") || { fail "no queued file carries $q1 — the send did not land as a per-message file in pending/"; return 0; }
  id2=$(id_of_body "$pd" "queued-$q2") || { fail "no queued file carries $q2 — the send did not land as a per-message file in pending/"; return 0; }
  id3=$(id_of_body "$pd" "queued-$q3") || { fail "no queued file carries $q3 — the send did not land as a per-message file in pending/"; return 0; }

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

  need_count "$pd"  0 "pending/ after a delivered boot (emptied by successful claims)"
  need_count "$cd_" 0 "claimed/ after a delivered boot (every claim acked AFTER emission)"
  need_count "$rd"  3 "read/ after a delivered boot — one entry per message, not one blob"
  need_dir_has_id "$rd" "$id1" "acked archive preserves id #1"
  need_dir_has_id "$rd" "$id2" "acked archive preserves id #2"
  need_dir_has_id "$rd" "$id3" "acked archive preserves id #3"

  # the deleted-not-extended half: _inbox_rotate and its <ts>-<pid>.jsonl archive naming die.
  for f in "$rd"/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
      *.jsonl) fail "read/ holds a batch archive '${f##*/}' — _inbox_rotate's <ts>-<pid>.jsonl naming is DELETED by the redesign, not extended" ;;
    esac
  done
  need_file_absent "$fx/.brain/dm/bravo/inbox.jsonl" "the retired single-shared inbox file"
}

# Q.B/17 — exactly-once across boots. TWO messages across THREE boots: one message's lifecycle
# is not enough, because "deliver only if read/ does not already exist" delivers correctly
# exactly once per lane FOREVER and would satisfy a single-message test.
#   ALSO       an empty-queue boot must not destroy an existing archive (the v1 unconditional
#              rotation did exactly that; the per-message layout must not regress into it).
sc_boot_delivers_exactly_once() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  m1="m1x7"; m2="m2y9"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "$m1-$m1-$m1"; rc=$?
  need_rc "$rc" 0 "prerequisite: first dm to bravo" || return 0
  id1=$(id_of_body "$pd" "$m1") || { fail "no queued file carries $m1 — the send did not land as a per-message file in pending/"; return 0; }

  ctx1=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot 1" || return 0
  need_str_has "$ctx1" "$m1" "boot 1 must report the first message" || return 0
  need_dir_has_id "$rd" "$id1" "boot 1 must ack the first message into read/" || return 0

  ctx2=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot 2" || return 0
  need_str_lacks "$ctx2" "$m1" "boot 2 must NOT re-report the first message"
  need_dir_has_id "$rd" "$id1" "an empty-queue boot destroyed the archived first message"

  run_brain "$fx" alpha dm @bravo "$m2-$m2-$m2"; rc=$?
  need_rc "$rc" 0 "prerequisite: second dm (after a delivery already happened)" || return 0
  id2=$(id_of_body "$pd" "$m2") || { fail "no queued file carries $m2 — the send did not land as a per-message file in pending/"; return 0; }

  ctx3=$(hook_context "$fx" bravo); hrc=$?
  need_rc "$hrc" 0 "boot 3" || return 0
  need_str_has  "$ctx3" "$m2" "boot 3 must report the SECOND message (delivery is per-message, not per-lane)"
  need_str_lacks "$ctx3" "$m1" "boot 3 must still NOT re-report the first message"

  need_count "$pd" 0 "pending/ after the final boot"
  need_dir_has_id "$rd" "$id1" "the first message must remain retrievable after boot 3"
  need_dir_has_id "$rd" "$id2" "the second message must be retrievable after boot 3"
  need_count "$rd" 2 "read/ after three boots (2 deliveries, 1 empty-queue no-op)"
}

# Q.B/18 — every boot arms the lane on the NEW mechanism, whether or not mail arrived.
# Seam: cmd_inbox prints the pending/ dir; the protocol tells the agent to run `brain dm take`
# on inbox activity. The retired inbox.jsonl watch target must be gone from the context, or
# lanes keep arming a file that no longer exists.
sc_boot_arms_pending_and_take() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  ctx=$(hook_context "$fx" bravo)   # no pending DM — arming happens on EVERY boot
  hrc=$?
  need_rc "$hrc" 0 "brain hook session-start as bravo" || return 0

  need_str_has "$ctx" "navigation-standards" "the existing protocol nudge must survive"
  need_str_has "$ctx" "dm/bravo/pending" "startup context must carry this lane's concrete pending/ path to arm on"
  need_str_has "$ctx" "dm take" "startup context must name the command that CLAIMS a live-observed message (UR-3)"
  need_str_lacks "$ctx" "inbox.jsonl" "startup context must stop pointing lanes at the retired shared inbox file"
}

# Q.B/19 — pending/ is emptied ONLY by a successful claim, and decision 6c's LOUD limb: when
# the claim `mv` fails while the source is STILL THERE, that is a real error (ENOSPC/EACCES),
# not a lost race — warn loudly and stop claiming.
#   INSTRUMENT claimed/ made read-only, with the rename-into-0500 positive control.
#   CHANNEL    the hook redirects its stderr into .brain/.hook-errors.log (cmd_hook), which is
#              the "warn loudly" channel decision 6c names; growth of that file is the witness.
#   PROVES     a failed claim loses NOTHING — the message is still in pending/ and is delivered
#              by the next boot once the fault clears.
#   DOES NOT   pin whether the failing boot still emits a digest; the seam is silent on that.
#   PROVE
sc_pending_emptied_only_by_successful_claims() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)
  hooklog="$fx/.brain/.hook-errors.log"

  run_brain "$fx" alpha dm @bravo "claim-blocked-5e2"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  need_count "$pd" 1 "prerequisite: message queued" || return 0

  make_readonly_dir "$cd_"
  mrc=$?
  case "$mrc" in
    0) ;;
    2) fail "instrument blind: a rename into a 0500 directory still succeeds (running as root?)"; return 0 ;;
    *) fail "fixture: could not make claimed/ read-only (rc=$mrc)"; return 0 ;;
  esac
  before_log=$(byte_size "$hooklog")

  hook_context "$fx" bravo >/dev/null
  hrc=$?
  chmod 755 "$cd_" 2>/dev/null || true       # restore BEFORE any early return
  need_rc "$hrc" 0 "the boot must still succeed (a hook never blocks a session)" || return 0

  need_count "$pd" 1 "pending/ after a FAILED claim — the message must NOT be consumed"
  need_count "$rd" 0 "read/ after a FAILED claim — nothing may reach the terminal state"
  [ "$(byte_size "$hooklog")" -gt "$before_log" ] \
    || fail "decision 6c: a claim that failed while the source was STILL PRESENT is a real error and must warn loudly — .brain/.hook-errors.log did not grow"

  # nothing was lost: once the fault clears, the very next boot delivers it.
  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "recovery boot" || return 0
  need_str_has "$ctx" "claim-blocked-5e2" "after the fault clears the message must still be delivered (prefer duplicate delivery over silent loss)"
  need_count "$pd" 0 "pending/ after the recovery boot"
  need_count "$rd" 1 "read/ after the recovery boot"
}

# ══════════════════════════ Q.R — recovery, lease, poison cap ════════════════════════════

# Q.R/20 — UR-1's headline: a message CLAIMED but never ACKED (the interrupted boot) must come
# back. Seam decision 6: recovery parses <claim-ts> from the claim name, and past
# DM_CLAIM_MAX_AGE renames it back to pending/<id>.a<k+1>.
#   PROVES     recovery happens (the message is redelivered), the attempt counter is BUMPED
#              (k+1 — without which the poison cap in 6b can never trigger), and the immutable
#              <id> survives the whole pending→claimed→pending→claimed→read round trip.
#   REJECTS    a boot that only reads pending/ (the v1 shape — nothing ever scans a
#              non-terminal state, which is exactly UR-1), and a recovery that resets k.
#   PAIRS WITH Q.R/21, which is the same fixture with only the AGE changed.
sc_ur1_stale_claim_recovered() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "stale-claim-6h1"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0

  c=$(mint_stuck_claim "$fx" bravo); mrc=$?
  [ "$mrc" = 0 ] || { mint_failed "$mrc"; return 0; }
  need_count "$cd_" 1 "prerequisite: exactly one stuck claim" || return 0
  id=$(msg_id_of "$c")
  k=$(attempt_of "$c") || { fail "the claim name carries no .a<k> attempt counter: ${c##*/}"; return 0; }
  claim_ts_of "$c" >/dev/null \
    || { fail "the claim name carries no .c<claim-ts>-<pid> stamp (seam decision 6): ${c##*/}"; return 0; }

  aged=$(age_claim "$c" $(( DM_CLAIM_MAX_AGE + 300 )))
  [ -n "$aged" ] || { fail "could not age the claim: unrecognised <claim-ts> encoding in ${c##*/} (expected epoch seconds or _now_compact %Y%m%dT%H%M%SZ)"; return 0; }

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot after the claim went stale" || return 0

  need_str_has "$ctx" "stale-claim-6h1" \
    "UR-1: a claim older than DM_CLAIM_MAX_AGE (${DM_CLAIM_MAX_AGE}s) must be recovered and REDELIVERED — prefer duplicate delivery over silent loss"
  need_count "$pd"  0 "pending/ after the recovering boot"
  need_count "$cd_" 0 "claimed/ after the recovering boot"
  need_dir_has_id "$rd" "$id" "the recovered message must reach read/ carrying its ORIGINAL id (seam 6b: preserve the uniq string)"

  got=$(first_file "$rd")
  gk=$(attempt_of "$got") || { fail "the acked name carries no .a<k>: ${got##*/}"; return 0; }
  need_eq "$gk" "$((k + 1))" \
    "recovery must BUMP the delivery-attempt counter (seam 6b: recovery renames with k+1) — without the bump the poison cap can never fire"
}

# Q.R/21 — the lease's other side: a claim YOUNGER than DM_CLAIM_MAX_AGE belongs to a live
# consumer and must NOT be stolen. Identical fixture to Q.R/20 with only the AGE changed, so
# the pair isolates the lease decision itself rather than the recovery machinery.
#   REJECTS    "recover everything in claimed/ on every boot", which would deliver every
#              message twice to a lane that is simply still working through its queue.
sc_fresh_claim_not_stolen() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)

  run_brain "$fx" alpha dm @bravo "fresh-claim-7j2"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0

  c=$(mint_stuck_claim "$fx" bravo); mrc=$?
  [ "$mrc" = 0 ] || { mint_failed "$mrc"; return 0; }
  need_count "$cd_" 1 "prerequisite: exactly one fresh claim" || return 0
  id=$(msg_id_of "$c")

  ctx=$(hook_context "$fx" bravo)     # claim-ts is NOW — well inside the lease
  hrc=$?
  need_rc "$hrc" 0 "boot while the claim is still fresh" || return 0

  need_str_lacks "$ctx" "fresh-claim-7j2" \
    "a claim younger than DM_CLAIM_MAX_AGE (${DM_CLAIM_MAX_AGE}s) must NOT be stolen from its claimer"
  need_count "$pd" 0 "pending/ must stay empty — a fresh claim is not recovered"
  need_count "$rd" 0 "read/ must stay empty — the boot never owned this message"
  need_count "$cd_" 1 "the fresh claim must still be sitting in claimed/"
  need_dir_has_id "$cd_" "$id" "the untouched claim must still carry its original id"
}

# Q.R/22 — the poison cap (seam 6b / ROADMAP "a poison message must not loop forever").
# At-least-once delivery plus automatic stale-claim recovery is an INFINITE redelivery loop for
# any message whose processing kills its consumer; SQS's answer is a dead-letter queue after N
# receives, and the seam adopts it: recovery at k+1 > DM_MAX_ATTEMPTS routes to failed/.
#   FIXTURE    the attempt counter is set to DM_MAX_ATTEMPTS BY THE TEST (renaming the pending
#              file), so this scenario is independent of the unresolved initial-k question
#              flagged at Q.S/2 — only the k+1 > 3 arithmetic is under test.
#   PROVES     routing to failed/, id preservation, NO delivery on the routing boot, NO
#              redelivery on any later boot, and surfacing in `brain status`.
#   CONTROL    status is sampled BEFORE and AFTER: a hardcoded banner fails the before-sample.
sc_poison_cap_routes_to_failed() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed)
  rd=$(q_dir "$fx" bravo read);    fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "poison-8k3"; rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  p=$(first_file "$pd") || { fail "nothing queued in pending/ — the send did not land as a per-message file"; return 0; }
  id=$(msg_id_of "$p")
  mv "$p" "$pd/$id.a$DM_MAX_ATTEMPTS" \
    || { fail "fixture: could not set the attempt counter to $DM_MAX_ATTEMPTS"; return 0; }

  # negative control on the status banner, taken while nothing has failed yet
  run_brain "$fx" bravo status
  rc=$?
  need_rc "$rc" 0 "brain status (before any failure)" || return 0
  if status_has_failed "$OUT"; then
    fail "control: brain status says 'failed' with an EMPTY failed/ — the surfacing is hardcoded, not derived"
  fi

  c=$(mint_stuck_claim "$fx" bravo); mrc=$?
  [ "$mrc" = 0 ] || { mint_failed "$mrc"; return 0; }
  need_eq "$(attempt_of "$c")" "$DM_MAX_ATTEMPTS" "prerequisite: the claim carries the capped attempt counter" || return 0
  aged=$(age_claim "$c" $(( DM_CLAIM_MAX_AGE + 300 )))
  [ -n "$aged" ] || { fail "could not age the claim: unrecognised <claim-ts> encoding in ${c##*/}"; return 0; }

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot that must route the poisoned message" || return 0

  need_count "$fd" 1 "failed/ after the routing boot (k+1 > $DM_MAX_ATTEMPTS)" || return 0
  need_dir_has_id "$fd" "$id" "the poisoned message must keep its id in failed/"
  need_count "$pd"  0 "pending/ after routing — a poisoned message is NOT re-queued"
  need_count "$cd_" 0 "claimed/ after routing"
  need_count "$rd"  0 "read/ after routing — failed/ is terminal, not an ack"
  need_str_lacks "$ctx" "poison-8k3" "the routing boot must not ALSO deliver the poisoned message"

  ctx2=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "a later boot" || return 0
  need_str_lacks "$ctx2" "poison-8k3" "a message in failed/ must NEVER be redelivered"
  need_count "$fd" 1 "failed/ is terminal and never auto-deleted"

  run_brain "$fx" bravo status
  rc=$?
  need_rc "$rc" 0 "brain status (after the failure)" || return 0
  status_has_failed "$OUT" \
    || fail "seam 6b: a message routed to failed/ must be SURFACED in 'brain status' (never auto-deleted, never silent). NB this ignores status's echoed journal lines, so the banner must come from status's OWN rendering"
}

# Q.R/22b — the poison cap's BOUNDARY, and the reason Q.R/22 alone is not enough. Seam 6b routes
# to failed/ when `k+1 > DM_MAX_ATTEMPTS`, so k = DM_MAX_ATTEMPTS-1 is the LAST attempt that must
# still be DELIVERED: recovery bumps it to .a3 and 3 > 3 is false. Q.R/22 pins the first FAILING
# k; this pins the last DELIVERING one.
#   REJECTS    an off-by-one that implements `>=` instead of `>` — which Q.R/22 cannot see, since
#              a `>=` engine routes k=3 to failed/ exactly like a correct one. Without this
#              sibling the cap could fire one delivery early on every poisoned message. [F4]
sc_poison_cap_boundary_delivers() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read); fd=$(q_dir "$fx" bravo failed)

  run_brain "$fx" alpha dm @bravo "boundary-3q7"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0
  pf=$(first_file "$pd") || { fail "nothing queued in pending/ — the send did not land as a per-message file"; return 0; }
  id=$(msg_id_of "$pf")
  k=$(( DM_MAX_ATTEMPTS - 1 ))
  mv "$pf" "$pd/$id.a$k" || { fail "fixture: could not set the attempt counter to $k"; return 0; }

  c=$(mint_stuck_claim "$fx" bravo); mrc=$?
  [ "$mrc" = 0 ] || { mint_failed "$mrc"; return 0; }
  need_eq "$(attempt_of "$c")" "$k" "prerequisite: the claim carries the boundary attempt counter" || return 0
  aged=$(age_claim "$c" "$(( DM_CLAIM_MAX_AGE + 300 ))")
  [ -n "$aged" ] || { fail "could not age the claim: unrecognised <claim-ts> encoding in ${c##*/}"; return 0; }

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot at the poison-cap boundary" || return 0

  need_count "$fd" 0 \
    "failed/ must stay EMPTY at k=$k: recovery bumps to $DM_MAX_ATTEMPTS, and $DM_MAX_ATTEMPTS > $DM_MAX_ATTEMPTS is FALSE — routing here is an off-by-one (>= instead of >)"
  need_str_has "$ctx" "boundary-3q7" "the last permitted delivery attempt must still be DELIVERED"
  need_count "$pd" 0 "pending/ after the boundary boot"
  need_dir_has_id "$rd" "$id" "the boundary message must be acked into read/"
  got=$(first_file "$rd") || { fail "read/ is empty after the boundary boot"; return 0; }
  gk=$(attempt_of "$got") || { fail "the acked name carries no .a<k>: ${got##*/}"; return 0; }
  need_eq "$gk" "$DM_MAX_ATTEMPTS" "recovery must bump k=$k to $DM_MAX_ATTEMPTS and DELIVER, not route to failed/"
}

# (Q.R/23 is intentionally absent: it was a standalone "status stays silent with an empty
# failed/" scenario, folded into Q.R/22 as its before/after negative control so the pair shares
# one vault. The id is left unused rather than renumbered, so review references stay stable.)

# Q.R/24 — delivery failure must never retire a message. This is UR-1's fix text verbatim
# ("test kill-after-claim plus digest/output failure") and ROADMAP's "a message stays replayable
# until handoff to the session actually succeeded".
#   LIMB (a)   ACK failure — read/ read-only, so the claimed→read rename gets EACCES. The
#              message must not vanish, must not be in read/, and the failure must be reported.
#   LIMB (b)   EMIT failure — stdout is CLOSED, so printing the message cannot succeed. Whatever
#              the engine does about it, the message must NOT end up in read/: acking a message
#              whose delivery failed is exactly the loss UR-1 describes.
#   NOT PINNED the exit status of either limb; the seam fixes the WARN-don't-die behaviour for
#              the ENOENT case only and says nothing about the process's exit code, so asserting
#              one would be stricter than the authority.
#   NOT COVERED the true ENOENT limb ("the claim was recovered out from under us — warn, never
#              die") needs a real concurrent interleaving between recovery and ack; there is no
#              CLI surface for acking a named claim, so it is not drivable here. Declared, not
#              silently skipped.
sc_delivery_failure_never_retires() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)

  # ── limb (a): the ack cannot land ──
  run_brain "$fx" alpha dm @bravo "ack-fails-9m4"; rc=$?
  need_rc "$rc" 0 "prerequisite: send #1" || return 0

  make_readonly_dir "$rd"
  mrc=$?
  case "$mrc" in
    0) ;;
    2) fail "instrument blind: a rename into a 0500 directory still succeeds (running as root?)"; return 0 ;;
    *) fail "fixture: could not make read/ read-only (rc=$mrc)"; return 0 ;;
  esac
  run_brain "$fx" bravo dm take
  chmod 755 "$rd" 2>/dev/null || true       # restore BEFORE any early return

  need_count "$rd" 0 "read/ after an ack that could not land — nothing may reach the terminal state"
  [ "$(count_files "$pd")" != 0 ] || [ "$(count_files "$cd_")" != 0 ] \
    || fail "after a failed ack the message is in NEITHER pending/ nor claimed/ — it must stay replayable in one of them, never be dropped"
  # the engine's own diagnostics are prefixed "brain: " (_warn/_die); a bare mv/rename error on
  # stderr is a LEAK, not a report, and must not satisfy this. [F10b]
  if [ -s "$ERR" ]; then
    need_file_has "$ERR" "brain:" "a failed ack must be reported BY THE ENGINE (stderr carried output, but none of it was a 'brain: ' diagnostic — an unsuppressed mv error is a leak, not a report)"
  else
    fail "a failed ack must be reported (stderr was empty)"
  fi

  # ── limb (b): the emit cannot land ──
  fx2=$(make_vault alpha bravo) || fatal "fixture build failed"
  base2=$(dirname "$fx2")
  pd2=$(q_dir "$fx2" bravo pending); cd2=$(q_dir "$fx2" bravo claimed); rd2=$(q_dir "$fx2" bravo read)

  run_brain "$fx2" alpha dm @bravo "emit-fails-1n5"; rc=$?
  need_rc "$rc" 0 "prerequisite: send #2" || return 0

  _brain_env_run - "$base2/closed.err" "$fx2" bravo dm take

  need_count "$rd2" 0 \
    "read/ after a take whose OUTPUT could not be written — a message acked without being delivered is exactly UR-1's silent loss"
  [ "$(count_files "$pd2")" != 0 ] || [ "$(count_files "$cd2")" != 0 ] \
    || fail "after a failed emit the message is in NEITHER pending/ nor claimed/ — it must stay replayable in one of them"
  # ...and it must still be deliverable once the fault clears. AGE any surviving claim first:
  # a correct engine may legitimately leave the emit-failed message as a FRESH claim in claimed/,
  # and Q.R/21 forbids the next boot from stealing a claim younger than DM_CLAIM_MAX_AGE. Without
  # this step the two scenarios contradict each other and this one falsely rejects the seam's own
  # take shape. Ageing converges BOTH permitted shapes (returned to pending/, or left claimed) on
  # "delivered at the next boot", and still proves the message was never silently lost. [F1]
  if c2=$(first_file "$cd2"); then
    age_claim "$c2" "$(( DM_CLAIM_MAX_AGE + 300 ))" >/dev/null \
      || { fail "could not age the surviving claim: unrecognised <claim-ts> encoding in ${c2##*/}"; return 0; }
  fi
  ctx=$(hook_context "$fx2" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot after the emit failure" || return 0
  need_str_has "$ctx" "emit-fails-1n5" \
    "a message whose emit failed must still be delivered later (prefer duplicate delivery over silent loss)"
}

# Q.R/25 — stale temps are purged, in-flight temps are not. Seam decision 6: "Stale .tmp-*
# purged after 300s (dirq maxtemp)". A fresh .tmp-* is another process's send MID-FLIGHT;
# deleting it would destroy a message that is about to be renamed into place.
#   INSTRUMENT mtime, which is the CORRECT judge for a temp (it is created fresh) even though
#              it is the wrong judge for a claim (rename preserves the send-time mtime — the
#              bug the seam map records its research catching).
#   PATHS      both `dm take` and a boot are driven before asserting, because the seam pins the
#              300s rule without naming which command owns the sweep.
#   ALSO       neither temp is ever visible to a reader glob (count_files skips dotfiles).
sc_stale_temp_purged_fresh_kept() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }

  printf '{"from":"alpha","to":"bravo","ts":"x","content":"torn-stale"}\n' > "$pd/.tmp-stale-9x1"
  printf '{"from":"alpha","to":"bravo","ts":"x","content":"torn-fresh"}\n' > "$pd/.tmp-fresh-9x2"
  touch -t 202601020304.05 "$pd/.tmp-stale-9x1" \
    || { fail "fixture: touch -t is unavailable, cannot age a temp"; return 0; }

  run_brain "$fx" alpha dm @bravo "temp-sweep-2p6"; rc=$?
  need_rc "$rc" 0 "prerequisite: a real send alongside the temps" || return 0
  need_count "$pd" 1 "a reader glob must see ONE message and neither temp (dotfiles are invisible by design)"

  run_brain "$fx" bravo dm take
  hook_context "$fx" bravo >/dev/null

  need_file_absent "$pd/.tmp-stale-9x1" \
    "a .tmp-* older than DM_TEMP_MAX_AGE (${DM_TEMP_MAX_AGE}s) must be purged (seam decision 6, dirq maxtemp)"
  need_file "$pd/.tmp-fresh-9x2" \
    "a FRESH .tmp-* is another sender's in-flight message and must NOT be purged"
  # positive control: the sweep did not eat the real message
  need_count "$(q_dir "$fx" bravo read)" 1 "the real message must still have been delivered while the temps were swept"
}

# ══════════════════════════ Q.X — symlink refusal (UR-2) ═════════════════════════════════
#
# UR-2: _inbox_ensure checked only the lane dir and the inbox; the `dm` ROOT was never checked,
# and _inbox_rotate — which ran FIRST at SessionStart — validated nothing at all. The seam's
# _dm_dir_ok must reject a symlink or non-directory at EVERY level walked, on EVERY queue touch.
# Every target below lives inside the disposable scratch root; nothing points at a real path.
#
# ⚠ SCOPE HONESTY (seam Flags): POSIX sh has no openat/O_NOFOLLOW, so these scenarios pin
# COMPONENT REFUSAL, not race-freedom. The same-user TOCTOU residual is a documented limit and
# no assertion here claims otherwise.

# Q.X/26 — the `dm` ROOT itself. The component the v1 engine never validated at all.
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

# Q.X/27 — the lane directory. Refusal must be SPECIFIC to the poisoned lane: a send to a
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

# Q.X/28 — the pending/ STATE directory. A component the v1 layout did not even have, so
# nothing in the old engine could have validated it.
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

# Q.X/29 — the read/ ARCHIVE directory, reached on the BOOT path. This is the exact gap UR-2
# names: _inbox_rotate ran first at SessionStart and validated neither the inbox nor read/, so
# a symlinked archive could route message bodies into a tracked canonical directory.
#   PROVES     the boot path validates read/ before moving anything through it, warns, and
#              LOSES NOTHING (the message stays in pending/ or claimed/, still deliverable).
sc_boot_refuses_symlinked_read_dir() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  ext=$(dirname "$fx")/outside-read
  mkdir -p "$ext" || { fail "fixture: could not create the external target"; return 0; }
  hooklog="$fx/.brain/.hook-errors.log"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed)

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
  [ "$(count_files "$pd")" != 0 ] || [ "$(count_files "$cd_")" != 0 ] \
    || fail "the message was lost when read/ was refused — it must stay in pending/ or claimed/"
}

# Q.X/30 — the MESSAGE FILE. Seam _dm_dir_ok: "message files additionally -L-checked and
# required regular (-f)", and the iteration guard is `[ -e ] || [ -L ] || continue` precisely so
# "a broken symlink must be SEEN and refused, not silently skipped".
#   PROVES     no dereference (external content never reaches the injected context), no
#              promotion of the link into read/, and that BOTH a resolvable and a BROKEN
#              symlink are reported rather than skipped.
#   DOES NOT   pin whether refusing one entry halts the rest of the lane — the seam is silent on
#   PROVE      that, so no assertion is made about the healthy message alongside it.
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
  # names chosen to satisfy the grammar, so a refusal cannot be blamed on an unparsable name
  ln -s "$ext/secret.txt" "$pd/20260803T101500Z-424242.a0" \
    || { fail "fixture: could not plant the symlinked message"; return 0; }
  ln -s "$ext/no-such-target" "$pd/20260803T101501Z-424243.a0" \
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
  # only one of them. A line-count floor does neither — it gets both directions wrong — so it is
  # used ONLY as the fallback when the warnings name nothing.
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

# ══════════════════════════ Q.D — digest ═════════════════════════════════════════════════

# Q.D/31 — a large backlog is BOUNDED at injection and LOSSLESS in storage. _dm_digest's
# signature changes from one file to N files; DM_INJECT_MAX_LINES (40) still bounds it.
#   PROVES     the injected block does not carry all 45 messages (an unbounded digest would
#              blow the receiving lane's context window — the reason the caps exist), while
#              every one of the 45 is still accounted for in exactly one queue state.
#   DOES NOT   pin WHICH messages are shown, nor whether the omitted ones are claimed-and-
#   PROVE      pointed-at or left in pending/. The seam map does not resolve that, so the
#              lossless invariant is asserted instead of a particular policy. Flagged in the
#              hand-off report as an open, non-blocking choice.
#   FIXTURE    messages are written directly (not sent) so 45 of them cost no engine calls; the
#              names follow the ratified grammar with an explicit `-<n>` discriminator.
sc_digest_bounded_and_lossless() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }

  i=1
  while [ "$i" -le 45 ]; do
    m=$(printf 'dg%02d' "$i")
    jq -cn --arg f alpha --arg t bravo --arg ts "2026-08-03T00:00:00Z" --arg c "bulk-$m-marker" \
      '{from:$f,to:$t,ts:$ts,content:$c}' > "$pd/20260803T000000Z-999999-$i.a0" \
      || { fail "fixture: could not write bulk message $i"; return 0; }
    i=$((i + 1))
  done
  need_count "$pd" 45 "prerequisite: 45 messages queued" || return 0

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot with a 45-message backlog" || return 0

  shown=0
  i=1
  while [ "$i" -le 45 ]; do
    m=$(printf 'dg%02d' "$i")
    str_has "$ctx" "bulk-$m-marker" && shown=$((shown + 1))
    i=$((i + 1))
  done
  [ "$shown" -gt 0 ] || fail "the boot injected NONE of the 45 queued messages"
  [ "$shown" -le "$DM_INJECT_MAX_LINES" ] \
    || fail "the injected block carried $shown of the 45 queued messages — DM_INJECT_MAX_LINES ($DM_INJECT_MAX_LINES) IS the bound, so anything above it means the cap is not applied. (A '< 45' check would have passed at 44 and let a near-unbounded digest through — that was the original hole.) [F6]"

  # lossless: every message is in exactly one of the four states, none destroyed
  total=$(( $(count_files "$pd") \
          + $(count_files "$(q_dir "$fx" bravo claimed)") \
          + $(count_files "$(q_dir "$fx" bravo read)") \
          + $(count_files "$(q_dir "$fx" bravo failed)") ))
  need_eq "$total" 45 "messages accounted for across pending/claimed/read/failed after the boot — bounding the DIGEST must never destroy a MESSAGE"
}

# Q.D/32 — seam defect 5: `cut -c1-2000` truncated mid-JSON and injected a syntactically broken
# object into a session's startup context. The fix truncates the CONTENT FIELD, not the
# serialized object.
#   PROVES     the injected block is bounded (a marker at the far end of a 2.9 KB body does not
#              survive) AND that every JSON-looking line it does carry actually parses.
#   VACUITY    if the digest renders prose rather than serialized objects, the JSON limb is
#   NOTE       vacuously true — that is a PERMITTED alternative (the seam does not pin the
#              rendering), and the HEAD/TAIL bound still holds. Do not "fix" the engine to
#              produce JSON just to make this limb bite.
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
    "the injected block carried the FULL 2.9 KB body — DM_INJECT_MAX_COLS (2000) is not bounding it"

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

# ══════════════════════════ 4.G — presence (carried unchanged) ═══════════════════════════

# 4.G/33 — a presence note with dialog_with: shows the open dialog in brain status.
# BASELINE-GREEN; verified discriminating against a mutant that stops rendering dialog_with
# (4.G/34 correctly did NOT flip against that same mutant — the pair is a control).
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

# 4.G/34 — a note WITHOUT dialog_with renders unchanged (the field is genuinely optional).
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

# 4.G/35 — reconcile does not flag dialog_with as stealth-structural.
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

# ══════════════════════════ 3.G — templates ══════════════════════════════════════════════

nav_matches() { grep -qiE -- "$1" "$NAV_SKILL" 2>/dev/null; }

# Same, but newline-flattened so a match may span a wrapped sentence. Callers MUST bound the
# gap (.{0,N}) — an unbounded .* over the flattened file degenerates into "both words appear
# somewhere", which the pre-rewrite template already satisfies.
nav_matches_near() { tr '\n' ' ' < "$NAV_SKILL" 2>/dev/null | grep -qiE -- "$1"; }
file_matches_near() { tr '\n' ' ' < "$1" 2>/dev/null | grep -qiE -- "$2"; }

# 3.G/36 — the always-read skill must teach the mechanic lanes actually operate. Seam Flags:
# the templates "must describe the take command and drop the inbox-file watch instructions".
#   ⚠ the negative limb targets the v1 sentence ("watch it for new JSON lines"). It is a
#   WORDING check, not a contract: if a rewritten instruction legitimately trips it, challenge
#   this assertion rather than contorting the template.
sc_nav_skill_names_the_take_mechanic() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  nav_matches 'brain dm|dm @' || fail "the always-read skill never mentions 'brain dm' — the fast tier is untaught"
  nav_matches 'dm take' \
    || fail "the always-read skill never mentions 'brain dm take' — lanes cannot CLAIM a live-observed message, so UR-3 reopens at the protocol layer"
  nav_matches 'pending' \
    || fail "the always-read skill never mentions the pending/ queue — lanes have nothing concrete to arm on"
  if nav_matches_near 'watch.{0,60}(new JSON|JSON line|jsonl)'; then
    fail "the always-read skill still tells lanes to watch the inbox FILE for JSON lines — that storage contract is deleted (seam: cmd_inbox now prints the pending/ dir; activity means 'run brain dm take')"
  fi
}

# 3.G/37 — a fresh reader can state the three tiers and which one is the record.
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

# 3.G/38 — triage rules an agent must ACT on live in the always-read part.
sc_nav_skill_carries_triage_rules() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  # word-boundary the short form: a bare 'ack' substring also matches "track", so an
  # unrelated "keep track of what lands" would green this gate with the ack rule missing
  nav_matches '\back\b|acknowledg' || fail "the 'ack everything even when deferring' rule is absent"
  nav_matches 'defer' || fail "the write-it-down-when-you-defer rule is absent"
}

# 3.G/39 — UR-8. Both templates promise `announce` reaches every lane at its next boot;
# _recent_journal surfaces only TODAY's last five lines naming the lane as author or explicit
# @recipient, so a generic announcement is invisible to every other lane and nothing crossing a
# date boundary matches at all. §7.5 bucket C: narrow the doc to what the code does — a
# doc-lie is worse than a missing feature, because lanes act on it.
sc_ur8_no_false_announce_promise() {
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

# 3.G/40 — the always-read skill stays <= 80 lines (measure, don't estimate).
sc_nav_skill_line_budget() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  n=$(wc -l < "$NAV_SKILL" | tr -d ' \n')
  [ "$n" -le 80 ] || fail "templates/navigation-standards.SKILL.md is $n lines (budget: 80)"
}

# 3.G/41 — zero project-specific referents in the generic template.
sc_nav_skill_no_erd_referents() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  n=$(grep -cE 'AUTONOMOUS_WORK|\.brain/research' "$NAV_SKILL" 2>/dev/null || true)
  [ -n "$n" ] || n=0
  need_eq "$n" 0 "project-specific referents in the generic template"
}

# ══════════════════════════ pre-PR H1–H5 review fixes ════════════════════════════════════

# The implementation names this bound beside the other DM_* constants. Restating the ruled
# value here makes the H5 boundary falsifiable without sourcing the engine under test.
DM_CLAIM_MAX_MESSAGES=40
DM_INJECT_MAX_COLS=2000

# H1 — claimed message identifiers must survive a vault path containing whitespace. This drives
# the complete public lifecycle: send → SessionStart claim/delivery → ack.
sc_h1_space_path_round_trip() {
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
    "H1: the real boot must deliver a DM when the vault path contains a space"
  need_count "$(q_dir "$fx" bravo pending)" 0 "pending/ after the spaced-path boot"
  need_count "$(q_dir "$fx" bravo claimed)" 0 "claimed/ after the spaced-path ack"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the spaced-path delivery"
}

# H2(a) — a file is the consumer-boundary unit. Multiple JSON values in one file are malformed,
# must emit nothing, and must remain replayable rather than being acked as several records.
sc_h2_multi_object_file_refused() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }
  planted="$pd/20260804T120000Z-9201.a0"
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"multi-first-h2"}' > "$planted" \
    || { fail "fixture: could not write the first planted object"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:01Z",content:"multi-second-h2"}' >> "$planted" \
    || { fail "fixture: could not write the second planted object"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc_nonzero "$rc" "H2: taking a file that contains more than one JSON object"
  need_eq "$(byte_size "$OUT")" 0 "multi-object file output — malformed input must emit nothing"
  need_count "$(q_dir "$fx" bravo read)" 0 "read/ after a malformed multi-object file"
  need_count "$cd_" 1 "claimed/ after a malformed multi-object file — it must remain replayable"
}

# H2(b) — unknown fields are not part of the wire contract and must not cross the consumer
# boundary. The four contract fields remain intact and the message is acked normally.
sc_h2_extra_field_stripped() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"extra-field-h2",extra:"must-not-cross"}' \
    > "$pd/20260804T120000Z-9202.a0" \
    || { fail "fixture: could not write the extra-field message"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take of a valid message carrying an unknown field" || return 0
  if ! jq -s -e 'length == 1 and (.[0] | keys == ["content","from","to","ts"])' "$OUT" >/dev/null 2>&1; then
    fail "H2: digest output must reconstruct exactly from/to/ts/content and strip every unknown field"
  fi
  need_file_has "$OUT" "extra-field-h2" "the sanitized message content"
  need_file_lacks "$OUT" "must-not-cross" "the planted unknown field"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the sanitized message is delivered"
}

# H2(c) — every contract value is bounded, not only content. An oversized producer-controlled
# `from` must be shortened before output and the serialized record must remain within the
# existing per-line injection cap.
sc_h2_oversized_from_bounded() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }
  huge_from=$(awk 'BEGIN { for (i = 0; i < 6000; i++) printf "f" }')
  jq -cn --arg f "$huge_from" \
    '{from:$f,to:"bravo",ts:"2026-08-04T12:00:00Z",content:"oversized-from-h2"}' \
    > "$pd/20260804T120000Z-9203.a0" \
    || { fail "fixture: could not write the oversized-from message"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take of a message carrying an oversized from value" || return 0
  size=$(byte_size "$OUT")
  [ "$size" -le "$((DM_INJECT_MAX_COLS + 1))" ] \
    || fail "H2: one sanitized digest record is $size bytes, above the $DM_INJECT_MAX_COLS-column bound"
  if ! jq -s -e --arg original "$huge_from" \
    'length == 1 and (.[0] | keys == ["content","from","to","ts"]) and (.[0].from | length) < ($original | length)' \
    "$OUT" >/dev/null 2>&1; then
    fail "H2: the oversized from value was not bounded while reconstructing the four-field record"
  fi
  need_file_has "$OUT" "oversized-from-h2" "content alongside the bounded from value"
}

# H3(a) — leading-zero decimals are non-canonical and must never reach shell arithmetic. The
# malformed claim moves visibly to failed/ while an unrelated valid message still delivers.
sc_h3_leading_zero_claim_survives_boot() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed)
  mkdir -p "$pd" "$cd_" "$(q_dir "$fx" bravo read)" "$(q_dir "$fx" bravo failed)" \
    || { fail "fixture: could not create the queue tree"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"bad-leading-zero-h3"}' \
    > "$cd_/20260804T120000Z-9301.a0.c08-123"
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:01Z",content:"good-after-bad-h3"}' \
    > "$pd/20260804T120001Z-9302.a0"

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "SessionStart with a leading-zero claim epoch" || return 0
  need_str_has "$ctx" "good-after-bad-h3" \
    "H3: a malformed claim must not prevent other messages from being delivered"
  need_str_lacks "$ctx" "bad-leading-zero-h3" "the malformed claim must not be delivered"
  need_count "$(q_dir "$fx" bravo failed)" 1 "failed/ after rejecting the leading-zero claim"
  need_count "$cd_" 0 "claimed/ after routing the malformed claim to failed/"
  need_file_has "$fx/.brain/.hook-errors.log" "20260804T120000Z-9301.a0.c08-123" \
    "the malformed-claim warning must name the offending file"
}

# H3(b) — an attempt outside the state-machine range is terminal input, never an operand. It
# must land in failed/ without wrapping into a negative, permanently unclaimable pending name.
sc_h3_overrange_attempt_routes_failed() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  cd_=$(q_dir "$fx" bravo claimed); fd=$(q_dir "$fx" bravo failed)
  mkdir -p "$(q_dir "$fx" bravo pending)" "$cd_" "$(q_dir "$fx" bravo read)" "$fd" \
    || { fail "fixture: could not create the queue tree"; return 0; }
  bad_name="20260804T120000Z-9303.a9223372036854775807.c0-123"
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:"overrange-attempt-h3"}' \
    > "$cd_/$bad_name"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take with an over-range claim attempt" || return 0
  need_count "$fd" 1 "failed/ after rejecting the over-range attempt"
  need_file "$fd/$bad_name" "the over-range claim's visible terminal file"
  need_count "$(q_dir "$fx" bravo pending)" 0 \
    "pending/ after the over-range attempt — no wrapped negative name may be created"
  need_file_has "$ERR" "$bad_name" "the over-range warning must name the offending file"

  run_brain "$fx" bravo status
  rc=$?
  need_rc "$rc" 0 "status after routing the over-range claim" || return 0
  status_has_failed "$OUT" || fail "H3: the terminal failed/ state must be visible in brain status"
}

# H4 — a jq shim simulates another session recovering the claim after digest but before ack.
# The digest is delivered, ack warns about ENOENT, and the public command still exits zero.
sc_h4_disappeared_claim_ack_is_soft() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx"); cd_=$(q_dir "$fx" bravo claimed)
  run_brain "$fx" alpha dm @bravo "claim-disappeared-h4"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send" || return 0

  shim_dir="$base/ack-race-bin"
  mkdir -p "$shim_dir" || { fail "fixture: could not create the ack-race shim directory"; return 0; }
  real_jq=$(command -v jq) || { fail "fixture: jq vanished after preflight"; return 0; }
  real_rm=$(command -v rm) || { fail "fixture: rm is unavailable"; return 0; }
  {
    printf '#!/usr/bin/env sh\n'
    printf 'validation=0\n'
    printf 'for arg do [ "$arg" = "-e" ] && validation=1; done\n'
    printf '"%s" "$@"\n' "$real_jq"
    printf 'rc=$?\n'
    printf 'if [ "$rc" -eq 0 ] && [ "$validation" -eq 0 ]; then\n'
    printf '  for file in "$DM_ACK_RACE_CLAIM_DIR"/*; do\n'
    printf '    [ -e "$file" ] || [ -L "$file" ] || continue\n'
    printf '    "%s" -f -- "$file"\n' "$real_rm"
    printf '  done\n'
    printf 'fi\n'
    printf 'exit "$rc"\n'
  } > "$shim_dir/jq"
  chmod +x "$shim_dir/jq" || { fail "fixture: could not make the jq shim executable"; return 0; }

  DM_ACK_RACE_CLAIM_DIR=$cd_
  export DM_ACK_RACE_CLAIM_DIR
  PATH="$shim_dir:$PATH" run_brain "$fx" bravo dm take
  rc=$?
  unset DM_ACK_RACE_CLAIM_DIR

  need_rc "$rc" 0 "H4: take after another session recovered the claim before ack"
  need_file_has "$OUT" "claim-disappeared-h4" "the digest emitted before the simulated recovery"
  need_file_has "$ERR" "claim disappeared before ack" \
    "the dedicated ENOENT soft-landing warning"
  need_file_lacks "$ERR" "refusing non-regular dm message" \
    "the generic file validator must not intercept the absent-claim soft path"
}

# H5 — claiming is bounded work. The first invocation owns exactly the fixed batch, leaves the
# remainder pending, and the next invocation drains every leftover without loss or starvation.
sc_h5_claim_batch_bounded_and_fair() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx"); pd=$(q_dir "$fx" bravo pending); rd=$(q_dir "$fx" bravo read)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }
  backlog=$((DM_CLAIM_MAX_MESSAGES + 3))
  i=1
  while [ "$i" -le "$backlog" ]; do
    seq=$(printf '%03d' "$i")
    jq -cn --arg content "bounded-batch-$seq-h5" \
      '{from:"alpha",to:"bravo",ts:"2026-08-04T12:00:00Z",content:$content}' \
      > "$pd/20260804T120000Z-9401-$seq.a0" \
      || { fail "fixture: could not plant backlog message $i"; return 0; }
    i=$((i + 1))
  done

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "first bounded take" || return 0
  first_out="$base/first-bounded-take.out"
  cp "$OUT" "$first_out" || { fail "fixture: could not preserve first take output"; return 0; }
  need_eq "$(line_count "$first_out")" "$DM_CLAIM_MAX_MESSAGES" \
    "H5: messages delivered by the first claim invocation"
  need_count "$rd" "$DM_CLAIM_MAX_MESSAGES" \
    "read/ after the first invocation — exactly one bounded batch must have been claimed"
  need_count "$pd" 3 "pending/ after the first invocation — the remainder stays claimable"
  need_count "$(q_dir "$fx" bravo claimed)" 0 "claimed/ after the first batch is acked"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "second take of the leftover batch" || return 0
  second_out="$OUT"
  need_eq "$(line_count "$second_out")" 3 "messages delivered by the second claim invocation"
  need_count "$rd" "$backlog" "read/ after successive invocations drain the full backlog"
  need_count "$pd" 0 "pending/ after the second invocation"

  i=1
  while [ "$i" -le "$backlog" ]; do
    seq=$(printf '%03d' "$i")
    seen=$(grep -h -cF -- "bounded-batch-$seq-h5" "$first_out" "$second_out" 2>/dev/null \
      | awk '{ total += $1 } END { print total + 0 }')
    need_eq "$seen" 1 "backlog marker $seq across successive bounded takes" || return 0
    i=$((i + 1))
  done
}

# D.P1/50 — deployment is one main-worktree engine, even when the receiving lane is a sibling
# whose tracked .brain/bin/brain predates `dm take`. This reproduces the live failure shape:
# SessionStart itself resolves the shared vault correctly, then its emitted command is executed
# from the stale sibling. Only an absolute main-engine instruction can consume the queued marker.
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
  instruction=$(printf '%s\n' "$ctx" | sed -n 's/^On activity, claim and consume it with: //p' | head -1)
  [ -n "$instruction" ] \
    || { fail "Part 1: SessionStart emitted no executable consume instruction"; return 0; }
  need_str_has "$instruction" "$fx/.brain/bin/brain" \
    "Part 1: the consume instruction must name the main worktree's deployed engine" || return 0
  need_str_lacks "$instruction" "$sibling/.brain/bin/brain" \
    "Part 1: the consume instruction must never name the sibling's tracked engine"

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

# U.H2/51 — one malformed file is isolated from healthy peers in the same claimed batch. The
# poison stays replayable (the frozen H2 single-poison contract), while both valid peers emit and
# ack at attempt zero; they must never inherit the poison file's retry count.
sc_poison_file_does_not_discard_healthy_batchmates() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed); rd=$(q_dir "$fx" bravo read)
  mkdir -p "$pd" || { fail "fixture: could not create pending/"; return 0; }
  printf '%s\n' '{not-valid-json' > "$pd/20260804T130000Z-9500.a0"
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T13:00:01Z",content:"healthy-peer-one-h2"}' \
    > "$pd/20260804T130001Z-9501.a0"
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T13:00:02Z",content:"healthy-peer-two-h2"}' \
    > "$pd/20260804T130002Z-9502.a0"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc_nonzero "$rc" "mixed healthy/poison take must report the retained poison file"
  need_file_has "$OUT" "healthy-peer-one-h2" "the first healthy batchmate"
  need_file_has "$OUT" "healthy-peer-two-h2" "the second healthy batchmate"
  need_count "$rd" 2 "read/ after healthy peers are emitted and acked independently"
  need_count "$cd_" 1 "claimed/ after only the poison file remains replayable"
  need_count "$pd" 0 "pending/ after all three files were claimed"
  for f in "$rd"/*; do
    [ -e "$f" ] || continue
    need_eq "$(attempt_of "$f")" 0 \
      "healthy peer attempt counter — poison retries must never propagate to a batchmate" || return 0
  done
}

# U.H3/52 — crash → immediate restart preserves the fresh claim, then an armed lease sweep moves
# it back to pending when wall-clock expiry arrives. The lane's existing pending-dir watcher can
# then run `dm take`; no unrelated DM or later reboot is needed to create the wake-up event.
sc_fresh_claim_arms_recovery_at_lease_expiry() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  run_brain "$fx" alpha dm @bravo "lease-expiry-wakeup-h3"
  rc=$?
  need_rc "$rc" 0 "prerequisite: send the crash-window message" || return 0
  claim=$(mint_stuck_claim "$fx" bravo); mrc=$?
  [ "$mrc" = 0 ] || { mint_failed "$mrc"; return 0; }
  claim=$(age_claim "$claim" "$((DM_CLAIM_MAX_AGE - 2))") \
    || { fail "fixture: could not place the claim just inside its lease"; return 0; }

  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "immediate restart while the claim is still fresh" || return 0
  need_str_lacks "$ctx" "lease-expiry-wakeup-h3" \
    "the immediate restart must not steal a still-fresh claim"
  need_count "$(q_dir "$fx" bravo claimed)" 1 "claimed/ immediately after restart"
  need_count "$(q_dir "$fx" bravo pending)" 0 "pending/ immediately after restart"

  waited=0
  while [ "$(count_files "$(q_dir "$fx" bravo pending)")" = 0 ] && [ "$waited" -lt 7 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  need_count "$(q_dir "$fx" bravo pending)" 1 \
    "pending/ after idling past the lease — the scheduled sweep must create watcher activity" \
    || return 0

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "watcher-triggered take after scheduled lease recovery" || return 0
  need_file_has "$OUT" "lease-expiry-wakeup-h3" \
    "the crash-window message delivered after idle lease expiry"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the recovered delivery"
}

# U.H4/53 — every pre-existing transition destination is preserved. Recovery must not clobber a
# regular pending message, nest into a directory, or follow a symlink out of the queue; failed/
# collisions get distinct forensic names instead of overwriting, nesting, or refusing forever.
sc_queue_destination_collisions_preserve_every_message() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  base=$(dirname "$fx"); pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed)
  fd=$(q_dir "$fx" bravo failed); ejected="$base/ejected"; ejected_failed="$base/ejected-failed"
  mkdir -p "$pd" "$cd_" "$fd" "$ejected" "$ejected_failed" \
    || { fail "fixture: could not create collision queue directories"; return 0; }

  jq -cn '{from:"prior",to:"bravo",ts:"2026-08-04T13:10:00Z",content:"occupied-regular-h4"}' \
    > "$pd/20260804T131000Z-9601.a1"
  mkdir "$pd/20260804T131001Z-9602.a1" \
    || { fail "fixture: could not plant the occupied directory"; return 0; }
  printf 'occupied-directory-sentinel-h4\n' > "$pd/20260804T131001Z-9602.a1/sentinel"
  ln -s "$ejected" "$pd/20260804T131002Z-9603.a1" \
    || { fail "fixture: could not plant the occupied symlink"; return 0; }

  i=1
  for id in 20260804T131000Z-9601 20260804T131001Z-9602 20260804T131002Z-9603; do
    jq -cn --arg content "stale-source-$i-h4" \
      '{from:"alpha",to:"bravo",ts:"2026-08-04T13:00:00Z",content:$content}' \
      > "$cd_/$id.a0.c0-1"
    i=$((i + 1))
  done

  printf 'old-failed-regular-h4\n' > "$fd/bad-regular"
  printf '%s\n' '{bad-new-regular-h4' > "$pd/bad-regular"
  mkdir "$fd/bad-directory" || { fail "fixture: could not plant failed/ directory collision"; return 0; }
  printf 'old-failed-directory-h4\n' > "$fd/bad-directory/sentinel"
  printf '%s\n' '{bad-new-directory-h4' > "$pd/bad-directory"
  ln -s "$ejected_failed" "$fd/bad-symlink" \
    || { fail "fixture: could not plant failed/ symlink collision"; return 0; }
  printf '%s\n' '{bad-new-symlink-h4' > "$pd/bad-symlink"

  run_brain "$fx" bravo dm take
  rc=$?
  need_file_has "$OUT" "occupied-regular-h4" \
    "the pre-existing regular pending message must survive and deliver"
  need_tree_has "$fd" "stale-source-1-h4" "the stale source blocked by a regular destination"
  need_tree_has "$fd" "stale-source-2-h4" "the stale source blocked by a directory destination"
  need_tree_has "$fd" "stale-source-3-h4" "the stale source blocked by a symlink destination"
  need_file_has "$pd/20260804T131001Z-9602.a1/sentinel" "occupied-directory-sentinel-h4" \
    "the occupied pending directory sentinel"
  need_eq "$(count_files "$ejected")" 0 \
    "symlink recovery target — no message may be ejected outside the queue"

  need_file_has "$fd/bad-regular" "old-failed-regular-h4" \
    "the pre-existing failed/ regular forensic record"
  need_tree_has "$fd" "bad-new-regular-h4" \
    "the newly rejected message beside a regular failed/ collision"
  need_file_has "$fd/bad-directory/sentinel" "old-failed-directory-h4" \
    "the pre-existing failed/ directory sentinel"
  need_tree_has "$fd" "bad-new-directory-h4" \
    "the newly rejected message beside a directory failed/ collision"
  need_tree_has "$fd" "bad-new-symlink-h4" \
    "the newly rejected message beside a symlink failed/ collision"
  need_eq "$(count_files "$ejected_failed")" 0 \
    "failed/ symlink target — no forensic message may be ejected"
  need_count "$pd" 2 \
    "pending/ after collisions — only the deliberately occupied directory and symlink remain"
  [ "$rc" = 0 ] || [ "$rc" = 1 ] \
    || fail "collision handling returned unexpected exit $rc"
}

# U.H5/54 — a 252-byte producer-alphabet ID fits pending/<id>.a0 but cannot fit the maximum
# claim suffix. It must be quarantined, allowing the later healthy entry to deliver in the same
# invocation; an early overlong name can never permanently head-of-line block the queue.
sc_overlong_id_routes_failed_without_blocking_later_message() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); fd=$(q_dir "$fx" bravo failed)
  mkdir -p "$pd" "$fd" || { fail "fixture: could not create overlong-id queue"; return 0; }
  long_id=$(awk 'BEGIN { printf "20260804T132000Z-1"; for (i = 0; i < 234; i++) printf "0" }')
  need_eq "$(printf '%s' "$long_id" | wc -c | tr -d ' \n')" 252 \
    "fixture: overlong ID byte length" || return 0
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T13:20:00Z",content:"overlong-id-h5"}' \
    > "$pd/$long_id.a0" \
    || { fail "fixture: filesystem did not accept the intended NAME_MAX boundary file"; return 0; }
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T13:20:01Z",content:"healthy-after-overlong-h5"}' \
    > "$pd/99999999T999999Z-9999.a0"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take with an early-sorting overlong ID" || return 0
  need_file_has "$OUT" "healthy-after-overlong-h5" \
    "the healthy message after the overlong ID"
  need_count "$fd" 1 "failed/ after quarantining the overlong ID"
  need_tree_has "$fd" "overlong-id-h5" "the quarantined overlong-ID message"
  need_count "$pd" 0 "pending/ after the overlong ID is removed and the healthy peer delivers"
}

# U.H6/55 — one 40-transition budget spans stale recovery, invalid-name routing, and claiming.
# Twenty stale recoveries plus twenty early invalid pending routes exhaust invocation one; the
# twenty recovered messages and one healthy tail remain and all progress on invocation two.
sc_one_transition_budget_spans_recovery_routing_and_claiming() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending); cd_=$(q_dir "$fx" bravo claimed)
  fd=$(q_dir "$fx" bravo failed); rd=$(q_dir "$fx" bravo read)
  mkdir -p "$pd" "$cd_" "$fd" "$rd" \
    || { fail "fixture: could not create transition-budget queue"; return 0; }

  i=1
  while [ "$i" -le 20 ]; do
    seq=$(printf '%03d' "$i")
    jq -cn --arg content "recovered-budget-$seq-h6" \
      '{from:"alpha",to:"bravo",ts:"2026-08-04T13:30:00Z",content:$content}' \
      > "$cd_/10000000T000000Z-9701-$seq.a0.c0-1"
    printf '%s\n' '{invalid-budget-h6' > "$pd/000-invalid-$seq"
    i=$((i + 1))
  done
  jq -cn '{from:"alpha",to:"bravo",ts:"2026-08-04T13:30:01Z",content:"healthy-tail-budget-h6"}' \
    > "$pd/99999999T999999Z-9702.a0"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "first transition-bounded take" || return 0
  need_eq "$(byte_size "$OUT")" 0 \
    "first take output — recovery plus routing must consume the whole shared budget"
  need_count "$fd" 20 "failed/ after the first take routes exactly twenty invalid names"
  need_count "$pd" 21 \
    "pending/ after the first take leaves twenty recovered messages plus the healthy tail"
  need_count "$cd_" 0 "claimed/ after exactly twenty stale recoveries"
  need_count "$rd" 0 "read/ after no claim budget remained"

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "second take resumes after the exhausted transition budget" || return 0
  need_eq "$(line_count "$OUT")" 21 "messages delivered by the resumed invocation"
  need_file_has "$OUT" "healthy-tail-budget-h6" \
    "fair resumption must eventually reach the healthy tail"
  need_count "$pd" 0 "pending/ after the resumed invocation"
  need_count "$rd" 21 "read/ after every valid message progresses"
}

# U.M1/56 — jq `length` counts code points. Four multibyte fields can therefore serialize above
# the 2,000-byte line cap even after the conservative per-field slice. The wire caps are bytes:
# the emitted line stays valid JSON and is at most DM_INJECT_MAX_COLS bytes plus its newline.
sc_multibyte_digest_respects_byte_caps() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  pd=$(q_dir "$fx" bravo pending)
  mkdir -p "$pd" || { fail "fixture: could not create multibyte queue"; return 0; }
  multi=$(awk 'BEGIN { for (i = 0; i < 300; i++) printf "🙂" }')
  jq -cn --arg v "$multi" '{from:"alpha",to:$v,ts:$v,content:$v}' \
    > "$pd/20260804T134000Z-9801.a0" \
    || { fail "fixture: could not write the multibyte message"; return 0; }

  run_brain "$fx" bravo dm take
  rc=$?
  need_rc "$rc" 0 "take of a multibyte boundary message" || return 0
  jq -e -s 'length == 1 and (.[0] | type) == "object"' "$OUT" >/dev/null 2>&1 \
    || fail "multibyte digest output is not one valid JSON object"
  size=$(byte_size "$OUT")
  [ "$size" -le "$((DM_INJECT_MAX_COLS + 1))" ] \
    || fail "multibyte digest record is $size bytes, above the $DM_INJECT_MAX_COLS-byte line cap"
  need_count "$(q_dir "$fx" bravo read)" 1 "read/ after the bounded multibyte delivery"
}

# ═════════════════════════════════════ run ═══════════════════════════════════════════════
printf 'brain lane-DM v1.1 queue RED suite\n'
printf '  engine : %s\n' "$BRAIN_BIN"
printf '  scratch: %s\n\n' "$SUITE_TMP"

scenario red   "Q.S/1   inbox-prints-pending-dir"           sc_inbox_prints_pending_dir
scenario red   "Q.S/1b  usage-lists-dm-inbox-and-take"      sc_usage_lists_dm_inbox_and_take
scenario red   "Q.S/2   send-writes-one-message-file"       sc_send_writes_one_message_file
scenario red   "Q.S/2b  rapid-sends-stay-distinct"          sc_rapid_sends_stay_distinct
scenario guard "Q.S/2c  over-cap-body-refused"               sc_over_cap_body_refused
scenario red   "Q.S/3   UR9-json-special-round-trip"        sc_ur9_json_special_body_round_trip
scenario red   "Q.S/4   dm-journals-pointer-not-body"       sc_dm_journals_pointer_not_body
scenario guard "Q.S/5   UR10-journal-body-independent"      sc_ur10_journal_body_independent
scenario red   "Q.S/6   dm-secret-body-never-journalled"    sc_dm_secret_body_never_journalled
scenario red   "Q.S/7   dm-all-broadcasts-not-to-self"      sc_dm_all_broadcasts_not_to_self
scenario guard "Q.S/8   dm-unknown-recipient-fails-clean"   sc_dm_unknown_recipient_fails_clean
scenario guard "Q.S/9   dm-self-send-refused"               sc_dm_self_send_refused
scenario guard "Q.S/10a init-gitignores-dm-queue"           sc_init_gitignores_dm_queue
scenario red   "Q.S/10b queue-files-stay-out-of-git-status" sc_queue_files_stay_out_of_git_status
scenario red   "Q.S/11  dm-takes-no-lock"                   sc_dm_takes_no_lock

scenario red   "Q.T/12  take-claims-prints-acks"            sc_take_claims_prints_acks
scenario red   "Q.T/13  UR3-take-then-boot-no-replay"       sc_ur3_take_then_boot_no_replay
scenario red   "Q.T/14  take-empty-is-silent-zero"          sc_take_empty_is_silent_zero
scenario red   "Q.T/15  two-consumers-disjoint"             sc_two_consumers_disjoint

scenario red   "Q.B/16  boot-delivers-and-acks-per-message" sc_boot_delivers_and_acks_per_message
scenario red   "Q.B/17  boot-delivers-exactly-once"         sc_boot_delivers_exactly_once
scenario red   "Q.B/18  boot-arms-pending-and-take"         sc_boot_arms_pending_and_take
scenario red   "Q.B/19  pending-emptied-only-by-claims"     sc_pending_emptied_only_by_successful_claims

scenario red   "Q.R/20  UR1-stale-claim-recovered"          sc_ur1_stale_claim_recovered
scenario red   "Q.R/21  fresh-claim-not-stolen"             sc_fresh_claim_not_stolen
scenario red   "Q.R/22  poison-cap-routes-to-failed"        sc_poison_cap_routes_to_failed
scenario red   "Q.R/22b poison-cap-boundary-delivers"       sc_poison_cap_boundary_delivers
scenario red   "Q.R/24  delivery-failure-never-retires"     sc_delivery_failure_never_retires
scenario red   "Q.R/25  stale-temp-purged-fresh-kept"       sc_stale_temp_purged_fresh_kept

scenario red   "Q.X/26  send-refuses-symlinked-dm-root"     sc_send_refuses_symlinked_dm_root
scenario red   "Q.X/27  send-refuses-symlinked-lane-dir"    sc_send_refuses_symlinked_lane_dir
scenario red   "Q.X/28  send-refuses-symlinked-pending"     sc_send_refuses_symlinked_pending_dir
scenario red   "Q.X/29  boot-refuses-symlinked-read-dir"    sc_boot_refuses_symlinked_read_dir
scenario red   "Q.X/30  boot-refuses-symlinked-message"     sc_boot_refuses_symlinked_message_file

scenario red   "Q.D/31  digest-bounded-and-lossless"        sc_digest_bounded_and_lossless
scenario red   "Q.D/32  digest-truncates-content-not-json"  sc_digest_truncates_content_not_json

scenario guard "4.G/33  status-surfaces-open-dialog"        sc_status_surfaces_open_dialog
scenario guard "4.G/34  status-unchanged-without-dialog"    sc_status_unchanged_without_dialog
scenario guard "4.G/35  reconcile-accepts-dialog-field"     sc_reconcile_accepts_dialog_field

scenario red   "3.G/36  nav-skill-names-the-take-mechanic"  sc_nav_skill_names_the_take_mechanic
scenario guard "3.G/37  nav-skill-states-tiers-and-record"  sc_nav_skill_states_tiers_and_record
scenario guard "3.G/38  nav-skill-carries-triage-rules"     sc_nav_skill_carries_triage_rules
scenario red   "3.G/39  UR8-no-false-announce-promise"      sc_ur8_no_false_announce_promise
scenario guard "3.G/40  nav-skill-line-budget"              sc_nav_skill_line_budget
scenario guard "3.G/41  nav-skill-no-erd-referents"         sc_nav_skill_no_erd_referents

scenario red   "F.H1/42 space-path-round-trip"              sc_h1_space_path_round_trip
scenario red   "F.H2/43 multi-object-file-refused"          sc_h2_multi_object_file_refused
scenario red   "F.H2/44 extra-field-stripped"               sc_h2_extra_field_stripped
scenario red   "F.H2/45 oversized-from-bounded"             sc_h2_oversized_from_bounded
scenario red   "F.H3/46 leading-zero-claim-survives-boot"   sc_h3_leading_zero_claim_survives_boot
scenario red   "F.H3/47 overrange-attempt-routes-failed"    sc_h3_overrange_attempt_routes_failed
scenario red   "F.H4/48 disappeared-claim-ack-is-soft"      sc_h4_disappeared_claim_ack_is_soft
scenario red   "F.H5/49 claim-batch-bounded-and-fair"       sc_h5_claim_batch_bounded_and_fair
scenario red   "D.P1/50 main-worktree-engine-from-sibling"  sc_deploy_instruction_uses_main_worktree_engine
scenario red   "U.H2/51 poison-isolated-from-healthy-peers"  sc_poison_file_does_not_discard_healthy_batchmates
scenario red   "U.H3/52 lease-expiry-arms-recovery"          sc_fresh_claim_arms_recovery_at_lease_expiry
scenario red   "U.H4/53 queue-destination-collisions"       sc_queue_destination_collisions_preserve_every_message
scenario red   "U.H5/54 overlong-id-does-not-head-block"    sc_overlong_id_routes_failed_without_blocking_later_message
scenario red   "U.H6/55 one-total-transition-budget"        sc_one_transition_budget_spans_recovery_routing_and_claiming
scenario red   "U.M1/56 multibyte-digest-byte-caps"         sc_multibyte_digest_respects_byte_caps

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
