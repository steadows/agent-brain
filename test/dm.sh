#!/usr/bin/env sh
# test/dm.sh — RED-phase suite for the Agent-Brain lane-DM feature.
#
# AUTHORITY: AGENT_BRAIN_DM_GSD_PLAN.md — gates 1.G / 2.G / 3.G / 4.G, tasks 1.1-1.6 and
# 2.1-2.2, plus the 0.3 seam decisions: (a) ONE journal line per command invocation, even
# for the @all fan-out; (b) rotation archives to dm/<feat>/read/<ts>.jsonl and is a no-op
# on an empty inbox; (c) one make_vault fixture helper, identity via BRAIN_FEATURE.
#
# SAFETY: every scenario runs inside a throwaway git repo under a single mktemp -d root.
# The engine is never invoked with a real repository as CWD, and HOME is redirected into
# the fixture so no machine-global file can be touched. The gate 1.G secret probe string
# exists only in this file and inside those throwaway repos.
#
# Scenario ids carry the gate they encode. Scenarios labelled "guard:" are regression
# guards that may legitimately pass against the pre-implementation engine.
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

# Fixed fixture environment. origin/main deliberately does NOT exist in a fixture, so
# reconcile's touches[] auto-fix stays a no-op and scenarios never mutate each other.
FIXTURE_BRANCH="main"
FIXTURE_MAIN_REF="origin/main"

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

# ── fixture helpers (seam decision c) ────────────────────────────────────────────────────

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

# run_brain <repo> <identity> [args...] — invokes the SOURCE engine with CWD inside the
# fixture. Sets $OUT / $ERR to the captured streams; the caller reads $? for the status.
run_brain() {
  _rb_repo=$1; _rb_id=$2; shift 2
  assert_disposable "$_rb_repo"
  _rb_base=$(dirname "$_rb_repo")
  OUT="$_rb_base/last.out"
  ERR="$_rb_base/last.err"
  (
    cd "$_rb_repo" || exit 127
    exec env \
      HOME="$_rb_base/home" \
      BRAIN_FEATURE="$_rb_id" \
      BRAIN_TEST_BRANCH="$FIXTURE_BRANCH" \
      BRAIN_MAIN_REF="$FIXTURE_MAIN_REF" \
      BRAIN_SKILLS_DIR="$_rb_base/home/.claude/skills" \
      BRAIN_GLOBAL_SETTINGS="$_rb_base/home/.claude/settings.json" \
      BRAIN_PRETOOL_MODE=allow \
      "$BRAIN_BIN" "$@"
  ) >"$OUT" 2>"$ERR"
}

inbox_of() { printf '%s\n' "$1/.brain/dm/$2/inbox.jsonl"; }

# journal entry lines ("- <ts> <feat> — <msg>") across every journal file in the vault
journal_entries() { grep -h '^- ' "$1"/.brain/journal/*.md 2>/dev/null || true; }
journal_entry_count() { journal_entries "$1" | wc -l | tr -d ' \n'; }
journal_raw_count() { cat "$1"/.brain/journal/*.md 2>/dev/null | wc -l | tr -d ' \n'; }
journal_since() { journal_entries "$1" | tail -n +"$(($2 + 1))"; }

line_count() { [ -f "$1" ] || { printf '0'; return 0; }; wc -l < "$1" | tr -d ' \n'; }

count_files() {
  _cf=0
  for _cf_f in "$1"/*; do [ -e "$_cf_f" ] || continue; _cf=$((_cf + 1)); done
  printf '%s' "$_cf"
}

first_file() {
  for _ff in "$1"/*; do [ -e "$_ff" ] || continue; printf '%s' "$_ff"; return 0; done
  return 1
}

str_has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

# trailing "-<component>" of an archive basename, minus .jsonl — the per-boot discriminator
# in task 2.1's ratified <ts>-<pid>.jsonl. Empty when the name carries no "-" at all.
suffix_of() {
  _sb=$(basename "$1"); _sb=${_sb%.jsonl}
  case "$_sb" in
    *-*) printf '%s' "${_sb##*-}" ;;
    *)   printf '' ;;
  esac
}

err_tail() { tr '\n' ' ' < "$ERR" 2>/dev/null | cut -c1-160; }

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
need_dir_absent() { [ ! -d "$1" ] && return 0; fail "$2: directory should not exist: $1"; }
need_empty() { [ -f "$1" ] && [ ! -s "$1" ] && return 0; fail "$2: expected an existing EMPTY file: $1"; }

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
  if [ ! -d "$1" ]; then
    fail "$3: expected directory does not exist: $1"
    return 1
  fi
  grep -rqF -- "$2" "$1" 2>/dev/null && return 0
  fail "$3: '$2' not found anywhere under $1"
}

need_tree_lacks() { # <dir> <needle> <label>
  # a missing directory is a FAILURE, not a clean grep — otherwise "nothing leaked"
  # would be satisfied by there being nothing to leak into.
  if [ ! -d "$1" ]; then
    fail "$3: expected directory does not exist: $1"
    return 1
  fi
  if grep -rqF -- "$2" "$1" 2>/dev/null; then
    fail "$3: '$2' found somewhere under $1"
    return 1
  fi
  return 0
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

# ═════════════════════════════════════ GATE 1.G — transport ══════════════════════════════

# 1.G "brain inbox prints+creates" (task 1.1 registers it; cmd_inbox owns mkdir+touch+print)
sc_inbox_prints_and_creates() {
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
    */dm/alpha/inbox.jsonl) ;;
    *) fail "printed path does not end in dm/alpha/inbox.jsonl: $path" ;;
  esac

  [ -d "$(dirname "$path")" ] || fail "inbox directory was not created: $(dirname "$path")"
  need_empty "$path" "inbox file after 'brain inbox'"
}

# 1.G / task 1.1 second half — "register dm) and inbox) in the dispatch case AND in usage()"
sc_usage_lists_dm_and_inbox() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  run_brain "$fx" alpha help
  rc=$?
  need_rc "$rc" 0 "brain help" || return 0
  need_file_has "$OUT" "brain announce" "usage() baseline (an existing command is listed)" || return 0
  need_file_has "$OUT" "brain dm" "usage() must list the dm subcommand"
  need_file_has "$OUT" "brain inbox" "usage() must list the inbox subcommand"
}

# 1.G "brain dm @graph \"x\" writes one valid JSON line to the inbox"
sc_dm_writes_one_json_line() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  ib=$(inbox_of "$fx" bravo)
  ib_charlie=$(inbox_of "$fx" charlie)
  ib_self=$(inbox_of "$fx" alpha)
  before_self=$(line_count "$ib_self")
  need_eq "$(line_count "$ib")" 0 "bravo inbox starts empty" || return 0

  run_brain "$fx" alpha dm @bravo "hello"
  rc=$?
  need_rc "$rc" 0 "brain dm @bravo" || return 0

  need_file "$ib" "bravo inbox" || return 0
  need_eq "$(line_count "$ib")" 1 "lines appended to bravo's inbox" || return 0

  if ! jq -e . "$ib" >/dev/null 2>&1; then
    fail "inbox line is not valid JSON: $(head -1 "$ib")"
    return 0
  fi
  need_eq "$(jq -r '.from    // ""' "$ib")" "alpha" "inbox line .from"
  need_eq "$(jq -r '.to      // ""' "$ib")" "bravo" "inbox line .to"
  need_eq "$(jq -r '.content // ""' "$ib")" "hello" "inbox line .content"
  need_eq "$(jq -r 'has("ts")' "$ib")" "true" "inbox line has a ts field"
  ts=$(jq -r '.ts // ""' "$ib")
  [ -n "$ts" ] || fail "inbox line .ts is empty"

  # point-to-point: an uninvolved lane must not receive it
  if [ -f "$ib_charlie" ]; then
    need_file_lacks "$ib_charlie" "hello" "charlie (uninvolved lane) inbox"
  fi
  # ...and neither must the SENDER. A self-copy would be re-delivered to alpha by the
  # session-start rotation, so a lane would read back its own outbound traffic.
  need_eq "$(line_count "$ib_self")" "$before_self" "sender's own inbox line count after a p2p send"
  if [ -f "$ib_self" ]; then
    need_file_lacks "$ib_self" "hello" "sender's own inbox after a p2p send"
  fi
}

# 1.G "one journal line containing the inbox path and NOT the body" (task 1.2, seam a)
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
  need_eq "$(line_count "$(inbox_of "$fx" bravo)")" 1 "the send actually delivered" || return 0

  after_entries=$(journal_entry_count "$fx")
  after_raw=$(journal_raw_count "$fx")
  need_eq "$((after_entries - before_entries))" 1 "journal entry lines added by one dm" || return 0
  need_eq "$((after_raw - before_raw))" 1 "raw journal lines added by one dm"

  new=$(journal_since "$fx" "$before_entries")
  need_str_has "$new" "dm/bravo/inbox.jsonl" "journal line must carry the transcript pointer"
  need_str_has "$new" "@bravo" "journal line must name the recipient"
  need_str_lacks "$new" "$marker" "journal line must NOT carry the message body (not even a fragment)"
  need_tree_lacks "$fx/.brain/journal" "$marker" "message-body fragment anywhere under journal/"
  # positive control: the body really did travel, so a clean journal is a real result
  need_file_has "$(inbox_of "$fx" bravo)" "$body" "the body reached the inbox (positive control)"
}

# 1.G "a DM body containing AWS_SECRET_ACCESS_KEY=abc123 leaves no trace under journal/"
sc_dm_secret_body_never_journalled() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  # The secret LEADS the body and repeats, so a prefix-truncating leak cannot hide it:
  # any leaked fragment of >= 4 chars contains 'AWS_', and of >= 21 the whole key name.
  secret_body="AWS_SECRET_ACCESS_KEY=abc123 AWS_SECRET_ACCESS_KEY=abc123 abc123"
  ib=$(inbox_of "$fx" bravo)
  before_entries=$(journal_entry_count "$fx")

  run_brain "$fx" alpha dm @bravo "$secret_body"
  rc=$?
  need_rc "$rc" 0 "brain dm @bravo (secret probe)" || return 0

  # positive control: the probe string must actually have been transported, otherwise a
  # clean journal grep proves nothing.
  need_file "$ib" "bravo inbox" || return 0
  need_file_has "$ib" "abc123" "probe string reached the inbox (positive control)" || return 0
  # second positive control: the send DID journal, so there is a real line to leak into.
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 1 \
    "journal entry lines added by the secret-probe send (positive control)" || return 0

  need_tree_lacks "$fx/.brain/journal" "abc123" "secret value under journal/"
  need_tree_lacks "$fx/.brain/journal" "AWS_SECRET_ACCESS_KEY" "secret key name under journal/"
  need_tree_lacks "$fx/.brain/journal" "AWS_" "any leading fragment of the secret under journal/"
}

# 1.G "brain dm @all lands in every registered inbox and NOT the sender's" (task 1.6, seam a)
sc_dm_all_broadcasts_not_to_self() {
  fx=$(make_vault alpha bravo charlie delta) || fatal "fixture build failed"
  body="resync-before-your-gates-9c1"
  # task 1.6: "do NOT gate the fan-out on who looks live" — presence updated: is unreliable.
  # charlie LOOKS dormant (two-month-old updated:), delta is explicitly done. Both are
  # registered presence notes, so both must still receive the broadcast.
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
    ib=$(inbox_of "$fx" "$lane")
    need_file "$ib" "$why inbox after broadcast" || continue
    need_eq "$(line_count "$ib")" 1 "$why inbox lines after broadcast" || continue
    if ! jq -e . "$ib" >/dev/null 2>&1; then
      fail "$lane broadcast line is not valid JSON: $(head -1 "$ib")"
      continue
    fi
    need_eq "$(jq -r '.from    // ""' "$ib")" "alpha" "$why broadcast line .from"
    need_eq "$(jq -r '.content // ""' "$ib")" "$body" "$why broadcast line .content"
  done

  ib_self=$(inbox_of "$fx" alpha)
  if [ -f "$ib_self" ]; then
    need_file_lacks "$ib_self" "$body" "sender's own inbox after broadcast"
  fi

  # seam (a): ONE invocation = ONE journal line, not one per recipient
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 1 \
    "journal entry lines added by one broadcast"
}

# 1.G "unknown recipient fails cleanly"
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
  need_dir_absent "$fx/.brain/dm/nope" "unknown recipient inbox dir"
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 0 \
    "journal entry lines added by a REJECTED send"
}

# 1.G "self-send refused"
sc_dm_self_send_refused() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  body="self-send-body-4b2"

  run_brain "$fx" alpha dm @bravo "probe-known-recipient"
  rc=$?
  need_rc "$rc" 0 "prerequisite: dm to a known recipient" || return 0

  ib_self=$(inbox_of "$fx" alpha)
  before_self=$(line_count "$ib_self")
  before_entries=$(journal_entry_count "$fx")

  run_brain "$fx" alpha dm @alpha "$body"
  rc=$?
  need_rc_nonzero "$rc" "brain dm @alpha (self-send)"
  [ -s "$ERR" ] || fail "self-send wrote nothing to stderr"
  need_eq "$(line_count "$ib_self")" "$before_self" "sender's own inbox line count after a self-send"
  if [ -f "$ib_self" ]; then
    need_file_lacks "$ib_self" "$body" "sender's own inbox"
  fi
  need_eq "$(($(journal_entry_count "$fx") - before_entries))" 0 \
    "journal entry lines added by a REFUSED self-send"
}

# 1.G / task 1.3 "dm/ is gitignored by a fresh init"
sc_init_gitignores_dm() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  # positive control on the instrument: check-ignore must NOT match a tracked vault path
  if git -C "$fx" check-ignore -q .brain/presence/alpha.md 2>/dev/null; then
    fail "instrument broken: git check-ignore matches .brain/presence/alpha.md"
    return 0
  fi
  if ! git -C "$fx" check-ignore -q .brain/dm/bravo/inbox.jsonl 2>/dev/null; then
    fail "fresh init does not gitignore .brain/dm/ (git check-ignore did not match an inbox path)"
  fi
}

# 1.G "git status shows no .brain/dm/ after a send"
sc_dm_files_stay_out_of_git_status() {
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
  need_eq "$(line_count "$(inbox_of "$fx" bravo)")" 1 "the send actually wrote under .brain/dm/" || return 0

  st=$(git -C "$fx" status --porcelain 2>/dev/null)
  need_str_lacks "$st" ".brain/dm" "git status after a send"
}

# 1.G / task 1.4 "a pre-existing stale dm lock must not wedge the send"
sc_dm_immune_to_stale_lock() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  mkdir -p "$fx/.brain/.locks/dm-bravo.lock" || { fail "fixture: could not pre-create the lock"; return 0; }

  t0=$(date +%s)
  run_brain "$fx" alpha dm @bravo "stale-lock-probe-2b"
  rc=$?
  t1=$(date +%s)
  need_rc "$rc" 0 "brain dm @bravo with a stale dm-bravo.lock present" || return 0

  need_eq "$(line_count "$(inbox_of "$fx" bravo)")" 1 "lines delivered despite the stale lock"
  need_file_has "$(inbox_of "$fx" bravo)" "stale-lock-probe-2b" "delivered content"
  elapsed=$((t1 - t0))
  [ "$elapsed" -le 3 ] || fail "send took ${elapsed}s — it waited on the stale lock (want <= 3s)"
}

# 1.G / task 1.4 structural witness: the dm path runs NO mkdir-lock at all, under ANY name.
# Making .brain/.locks read-only is name-agnostic: _lock_acquire creates $BRAIN/.locks/<k>.lock
# (bin/brain:115) whatever <k> is, so any lock protocol fails here while a lock-free send —
# which never touches .locks — is unaffected. A witness keyed on the literal name "dm-bravo"
# would miss a lock taken under a global key.
sc_dm_takes_no_lock() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  locks="$fx/.brain/.locks"
  mkdir -p "$locks" || { fail "fixture: could not create .locks"; return 0; }
  # A bespoke lock need not live under .brain/.locks. Pre-create a STALE per-lane lock at
  # dm/<to>/.lock too: a lock protocol rooted there wedges exactly as task 1.4 describes,
  # and the read-only .locks probe alone would never see it.
  mkdir -p "$fx/.brain/dm/bravo/.lock" \
    || { fail "fixture: could not pre-create dm/bravo/.lock"; return 0; }
  chmod 500 "$locks" || { fail "fixture: chmod 500 .locks failed"; return 0; }

  # instrument positive control: with .locks read-only, creating a lock dir MUST fail.
  if mkdir "$locks/_instrument_probe" 2>/dev/null; then
    rmdir "$locks/_instrument_probe" 2>/dev/null || true
    chmod 755 "$locks" 2>/dev/null || true
    fail "instrument blind: a lock dir is still creatable under a read-only .locks (running as root?)"
    return 0
  fi

  t0=$(date +%s)
  run_brain "$fx" alpha dm @bravo "no-lock-probe-3c"
  rc=$?
  t1=$(date +%s)
  # restore BEFORE any early return — the EXIT-trap rm -rf needs to descend here
  chmod 755 "$locks" 2>/dev/null || true

  need_rc "$rc" 0 "brain dm with .brain/.locks read-only and a stale dm/bravo/.lock (task 1.4: the dm path takes no lock)" || return 0
  elapsed=$((t1 - t0))
  [ "$elapsed" -le 3 ] || fail "send took ${elapsed}s — it spun on a lock somewhere (want <= 3s)"
  need_eq "$(line_count "$(inbox_of "$fx" bravo)")" 1 "the send actually delivered" || return 0
  need_file_has "$(inbox_of "$fx" bravo)" "no-lock-probe-3c" "delivered content"
}

# ═════════════════════════════════════ GATE 2.G — hook ═══════════════════════════════════

hook_context() { # <repo> <identity> → prints additionalContext, non-zero if it can't
  run_brain "$1" "$2" hook session-start
  _hc_rc=$?
  [ "$_hc_rc" = "0" ] || return 1
  jq -e -r '.hookSpecificOutput.additionalContext // empty' "$OUT" 2>/dev/null
}

# 2.G "offline delivery: send to a lane that is not running, then boot it" (task 2.1, seam b)
sc_session_start_delivers_and_rotates() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  # THREE queued messages, two senders. A dormant lane normally wakes to a QUEUE, not to a
  # single message (that is the whole broadcast tier), so one-message coverage would let an
  # injection of just `tail -1` of the archive pass while silently dropping everything older.
  q1="q1a4"; q2="q2b5"; q3="q3c6"
  ib=$(inbox_of "$fx" bravo)
  # charlie sends while status: done — cmd_dm only requires the presence note to exist.
  # Being done keeps charlie out of cmd_status's active-lanes list, so its name cannot
  # reach the injected context that way (same trick as 4.G/13a).
  write_presence "$fx" charlie "done" || fatal "fixture: could not set charlie done"

  run_brain "$fx" alpha dm @bravo "queued-$q1"
  rc=$?
  need_rc "$rc" 0 "prerequisite: first dm to the (not running) lane" || return 0
  run_brain "$fx" charlie dm @bravo "queued-$q2"
  rc=$?
  need_rc "$rc" 0 "prerequisite: second dm (different sender)" || return 0
  run_brain "$fx" alpha dm @bravo "queued-$q3"
  rc=$?
  need_rc "$rc" 0 "prerequisite: third dm" || return 0
  need_eq "$(line_count "$ib")" 3 "prerequisite: all three messages are queued in bravo's inbox" || return 0

  # Close the OTHER path by which a sender's name reaches the context: cmd_status echoes
  # recent journal lines mentioning this lane, and task 1.2's call-log line is "<ts> <sender>
  # — dm → @bravo (transcript: …)". That echo carries "charlie" on its own, so without this
  # the attribution assertion below would pass against a delivery that injects only .content
  # (verified: it does). Stripping journal ENTRY lines leaves the delivered message as the
  # only possible source.
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
  # ATTRIBUTION: who sent it must survive delivery. A queue of contradictory instructions
  # with no sender is unactionable — task 3.2's ack rule and 3.3's merge handshake both
  # require knowing who to answer. The NAME is the contract; any rendering carrying it
  # (raw JSON, "From @charlie: …", a table) satisfies this.
  need_str_has "$ctx" "charlie" "startup context must identify the SENDER of a delivered message"
  need_empty "$ib" "inbox after the boot (rotated, then re-created empty)"

  rd="$fx/.brain/dm/bravo/read"
  if [ ! -d "$rd" ]; then
    fail "no read archive at $rd — task 2.1 requires mv to dm/<feat>/read/<ts>-<pid>.jsonl"
    return 0
  fi
  need_eq "$(count_files "$rd")" 1 "files in the read archive after one delivered boot" || return 0
  arc=$(first_file "$rd")
  # task 2.1 ratifies `<ts>-<pid>.jsonl`. Only the `-<pid>` half is pinned here — the
  # timestamp format is the implementer's choice — so the shape check is a trailing
  # "-<digits>.jsonl". This is a SHAPE check only: a constant suffix such as "-0" satisfies
  # it while still colliding. 2.G/10b is what rejects constant suffixes — it requires the
  # trailing discriminator to DIFFER between two boots. Read its comment before relying on
  # either: it does NOT force two rotations into one clock second (that instrument is
  # unbuildable here) and it declares a clock-derived-suffix residual it cannot catch.
  # (2.G/11 pins neither shape nor uniqueness — it pins no-op-on-empty and per-message
  # delivery.)
  case "$arc" in
    *.jsonl) ;;
    *) fail "read archive file is not a .jsonl: $arc" ;;
  esac
  if ! printf '%s' "$(basename "$arc")" | grep -qE -- '-[0-9][0-9]*\.jsonl$'; then
    fail "read archive name lacks the ratified -<pid> suffix (task 2.1: <ts>-<pid>.jsonl): $(basename "$arc")"
  fi
  # the archive is the transcript the journal pointer promises — ALL of it, not just the tail
  need_file_has "$arc" "$q1" "read archive must contain the oldest queued message"
  need_file_has "$arc" "$q2" "read archive must contain the middle queued message"
  need_file_has "$arc" "$q3" "read archive must contain the newest queued message"
}

# 2.G / task 2.1 — the ratified `-<pid>` suffix must make archive names UNIQUE, not merely
# well-shaped. A constant suffix ("-0") passes 2.G/10's shape check, 2.G/11's durability and
# 2.G/11's count, while reintroducing exactly the same-second collision the ruling exists to
# prevent.
#
# Forcing two rotations into one clock second is NOT a usable instrument: a single send+boot
# cycle takes about a second by itself (the hook runs reconcile + status across the whole
# vault), so the collision case cannot be constructed on demand — measured, not assumed.
# This checks the DISCRIMINATOR instead: the trailing component of the archive name must
# differ between two boots. It holds wherever the second boundaries happen to fall, so the
# check is deterministic — but be precise about what it does and does not establish:
#
#   PROVES     — a CONSTANT suffix (e.g. "-0"), shaped like <ts>-<pid> but not a
#                discriminator at all, is rejected. No timing luck required.
#   DOES NOT   — a CLOCK-DERIVED suffix (e.g. <ts> as %Y%m%d and the suffix as %H%M%S) also
#   PROVE        differs across two boots in different seconds, so it passes here while
#                still colliding within one second. "Differs across boots" does not imply
#                "unique within a second".
#
# That residual is ACCEPTED and DECLARED, not closed: tightening this to reject 6-digit
# suffixes would false-red a legitimate 6-digit pid. The ratified `-<pid>` itself is enforced
# by review — /simplify (7.1) verifies the finished diff against seam decision (b).
sc_rotation_archive_names_collision_free() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  rd="$fx/.brain/dm/bravo/read"

  run_brain "$fx" alpha dm @bravo "collide-one"
  rc=$?
  need_rc "$rc" 0 "prerequisite: first dm to bravo" || return 0
  hook_context "$fx" bravo >/dev/null
  hrc=$?
  need_rc "$hrc" 0 "prerequisite: first boot of bravo" || return 0

  run_brain "$fx" alpha dm @bravo "collide-two"
  rc=$?
  need_rc "$rc" 0 "prerequisite: second dm to bravo" || return 0
  hook_context "$fx" bravo >/dev/null
  hrc=$?
  need_rc "$hrc" 0 "prerequisite: second boot of bravo" || return 0

  need_eq "$(count_files "$rd")" 2 "archives after two delivered boots" || return 0

  arc_a=""; arc_b=""
  for f in "$rd"/*; do
    [ -e "$f" ] || continue
    if [ -z "$arc_a" ]; then arc_a=$f; elif [ -z "$arc_b" ]; then arc_b=$f; fi
  done
  sfx_a=$(suffix_of "$arc_a")
  sfx_b=$(suffix_of "$arc_b")
  [ -n "$sfx_a" ] || fail "archive name carries no trailing -<discriminator>: $(basename "$arc_a")"
  [ -n "$sfx_b" ] || fail "archive name carries no trailing -<discriminator>: $(basename "$arc_b")"
  if [ -n "$sfx_a" ] && [ -n "$sfx_b" ] && [ "$sfx_a" = "$sfx_b" ]; then
    fail "both boots used the SAME trailing discriminator '$sfx_a' — a constant suffix is not collision-free; task 2.1 ratifies -<pid>, which differs per boot"
  fi

  need_tree_has "$rd" "collide-one" "the first transcript must be retrievable"
  need_tree_has "$rd" "collide-two" "the second transcript must be retrievable"
}

# 2.G "exactly-once" — TWO messages across THREE boots. One message's lifecycle is not
# enough: "rotate only if read/ does not already exist" delivers correctly exactly once per
# lane FOREVER and would satisfy a single-message test.
sc_session_start_delivers_exactly_once() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"
  m1="m1x7"; body1="m1x7-m1x7-m1x7-m1x7"
  m2="m2y9"; body2="m2y9-m2y9-m2y9-m2y9"
  rd="$fx/.brain/dm/bravo/read"

  run_brain "$fx" alpha dm @bravo "$body1"
  rc=$?
  need_rc "$rc" 0 "prerequisite: first dm to bravo" || return 0

  ctx1=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot 1: hook session-start as bravo" || return 0
  need_str_has "$ctx1" "$m1" "prerequisite: boot 1 reports the first message" || return 0

  need_tree_has "$rd" "$m1" "prerequisite: boot 1 archived the first message under read/" || return 0

  ctx2=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot 2: hook session-start as bravo" || return 0
  need_str_lacks "$ctx2" "$m1" "boot 2 must NOT re-report the first message"

  # seam (b): rotation must NO-OP on an empty inbox. An unconditional every-boot rotation
  # mv's the empty inbox over the existing <ts>.jsonl and destroys a delivered transcript —
  # a file COUNT cannot see that (the count stays 1), content can.
  need_tree_has "$rd" "$m1" \
    "an empty-inbox boot destroyed the archived first message (rotation must no-op on empty)"

  # the lane has now already received one delivery — a second message must still arrive
  run_brain "$fx" alpha dm @bravo "$body2"
  rc=$?
  need_rc "$rc" 0 "prerequisite: second dm to bravo (after a delivery already happened)" || return 0

  ctx3=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "boot 3: hook session-start as bravo" || return 0
  need_str_has "$ctx3" "$m2" "boot 3 must report the SECOND message (delivery is per-message, not per-lane)"
  need_str_lacks "$ctx3" "$m1" "boot 3 must still NOT re-report the first message"

  need_empty "$(inbox_of "$fx" bravo)" "inbox after the final boot"
  need_tree_has "$rd" "$m2" "the second message must be retrievable under read/ after boot 3"

  # Archive durability across a REAL rotation. Task 2.1 ratifies `<ts>-<pid>.jsonl`
  # precisely so boot 3's archive cannot land on boot 1's filename: `<ts>` alone collides
  # within one clock second and the mv destroys the first transcript, which would make
  # task 1.2's "retrievable pointer" a lie. Both boots run in their own process, so this
  # is deterministic under the ratified name and fails under a bare `<ts>`.
  need_tree_has "$rd" "$m1" \
    "boot 3's rotation destroyed boot 1's archive — archive names must be collision-free (task 2.1: <ts>-<pid>.jsonl)"
  # boot 1 archived, boot 2 no-opped on an empty inbox, boot 3 archived → exactly two
  need_eq "$(count_files "$rd")" 2 "archives after three boots (2 deliveries, 1 empty-inbox no-op)"
}

# 2.G / task 2.2 "the injected block carries the concrete inbox path to arm"
sc_session_start_arms_inbox_path() {
  fx=$(make_vault alpha bravo) || fatal "fixture build failed"

  # no pending DM — the watcher must be armed on every boot, not only on delivery
  ctx=$(hook_context "$fx" bravo)
  hrc=$?
  need_rc "$hrc" 0 "brain hook session-start as bravo" || return 0

  need_str_has "$ctx" "navigation-standards" "the existing protocol nudge must survive"
  need_str_has "$ctx" "dm/bravo/inbox.jsonl" "startup context must carry this lane's concrete inbox path"
}

# ═════════════════════════════════════ GATE 4.G — presence ═══════════════════════════════

# 4.G "a presence note with dialog_with: shows the open dialog in brain status"
sc_status_surfaces_open_dialog() {
  fx=$(make_vault alpha bravo charlie) || fatal "fixture build failed"
  # charlie is done → cmd_status never lists it, so any mention of 'charlie' in the output
  # can only come from alpha's dialog_with field.
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

# 4.G guard "a note WITHOUT dialog_with renders unchanged" (the field is genuinely optional)
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

# 4.G guard "reconcile does not flag dialog_with as stealth-structural"
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

# ═════════════════════════════════════ GATE 3.G — template ═══════════════════════════════

nav_matches() { grep -qiE -- "$1" "$NAV_SKILL" 2>/dev/null; }

# Same, but newline-flattened so a match may span a wrapped sentence. Callers MUST bound the
# gap (.{0,N}) — an unbounded .* over the flattened file degenerates into "both words appear
# somewhere", which the pre-Phase-3 template already satisfies.
nav_matches_near() { tr '\n' ' ' < "$NAV_SKILL" 2>/dev/null | grep -qiE -- "$1"; }

# 3.G POSITIVE "every rule an agent is expected to act on appears in the always-read part".
# The two guards below are negative only; without this, a Phase 3 that writes NOTHING
# clears gate 3.G. The DM mechanic is the thing Phase 3 exists to teach.
sc_nav_skill_names_the_dm_mechanic() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  nav_matches 'inbox' || fail "the always-read skill never mentions the inbox — lanes will not know to arm it (task 2.2 / Phase 3 preamble)"
  nav_matches 'brain dm|dm @' || fail "the always-read skill never mentions 'brain dm' — the fast tier is untaught"
}

# 3.G "a fresh reader can state the three tiers and which one is the record"
# (Context tier table + task 3.3: "DM = signal; the connection note = record")
sc_nav_skill_states_tiers_and_record() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  nav_matches 'brain dm|dm @|inbox' || fail "tier 1 (fast: dm → inbox) is not named in the always-read skill"
  nav_matches 'announce' || fail "tier 2 (everyone-eventually: announce → journal) is not named"
  nav_matches 'connection' || fail "tier 3 (permanent: connections/ note) is not named"
  nav_matches_near 'connection.{0,80}record|record.{0,80}connection' \
    || fail "nothing states that the connections note is THE RECORD — a reader cannot tell which tier is durable. NB this matches 'connection' and 'record' WITHIN 80 CHARACTERS OF EACH OTHER (newlines count as one space): if your sentence says both but with a long aside between them, tighten the sentence rather than assuming the gate is broken"
}

# 3.G "triage rules an agent must ACT on live in the always-read part" (task 3.2)
sc_nav_skill_carries_triage_rules() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  # word-boundary the short form: a bare 'ack' substring also matches "track", so an
  # unrelated "keep track of what lands" would green this gate with the ack rule missing
  nav_matches '\back\b|acknowledg' || fail "task 3.2's 'ack everything even when deferring' rule is absent"
  nav_matches 'defer' || fail "task 3.2's write-it-down-when-you-defer rule is absent"
}

# 3.G guard "the always-read skill stays <= 80 lines" (M5 — measure, don't estimate)
sc_nav_skill_line_budget() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  n=$(wc -l < "$NAV_SKILL" | tr -d ' \n')
  [ "$n" -le 80 ] || fail "templates/navigation-standards.SKILL.md is $n lines (budget: 80)"
}

# 3.G guard "zero ERD-specific referents in the generic template" (M3)
sc_nav_skill_no_erd_referents() {
  need_file "$NAV_SKILL" "generic nav-standards template" || return 0
  n=$(grep -cE 'AUTONOMOUS_WORK|\.brain/research' "$NAV_SKILL" 2>/dev/null || true)
  [ -n "$n" ] || n=0
  need_eq "$n" 0 "ERD-specific referents in the generic template"
}

# ═════════════════════════════════════ run ═══════════════════════════════════════════════
printf 'brain lane-DM RED suite\n'
printf '  engine : %s\n' "$BRAIN_BIN"
printf '  scratch: %s\n\n' "$SUITE_TMP"

scenario red   "1.G/1  inbox-prints-and-creates"          sc_inbox_prints_and_creates
scenario red   "1.G/1b usage-lists-dm-and-inbox"          sc_usage_lists_dm_and_inbox
scenario red   "1.G/2  dm-writes-one-valid-json-line"     sc_dm_writes_one_json_line
scenario red   "1.G/3  dm-journals-pointer-not-body"      sc_dm_journals_pointer_not_body
scenario red   "1.G/4  dm-secret-body-never-journalled"   sc_dm_secret_body_never_journalled
scenario red   "1.G/5  dm-all-broadcasts-not-to-self"     sc_dm_all_broadcasts_not_to_self
scenario red   "1.G/6  dm-unknown-recipient-fails-clean"  sc_dm_unknown_recipient_fails_clean
scenario red   "1.G/7  dm-self-send-refused"              sc_dm_self_send_refused
scenario red   "1.G/8a init-gitignores-dm"                sc_init_gitignores_dm
scenario red   "1.G/8b dm-files-stay-out-of-git-status"   sc_dm_files_stay_out_of_git_status
scenario red   "1.G/9  dm-immune-to-stale-lock"           sc_dm_immune_to_stale_lock
scenario red   "1.G/9b dm-takes-no-lock"                  sc_dm_takes_no_lock
scenario red   "2.G/10 session-start-delivers-and-rotates" sc_session_start_delivers_and_rotates
scenario red   "2.G/10b archive-names-collision-free"     sc_rotation_archive_names_collision_free
scenario red   "2.G/11 session-start-delivers-exactly-once" sc_session_start_delivers_exactly_once
scenario red   "2.G/12 session-start-arms-inbox-path"     sc_session_start_arms_inbox_path
scenario red   "4.G/13a status-surfaces-open-dialog"      sc_status_surfaces_open_dialog
scenario guard "4.G/13b status-unchanged-without-dialog"  sc_status_unchanged_without_dialog
scenario guard "4.G/13c reconcile-accepts-dialog-field"   sc_reconcile_accepts_dialog_field
scenario red   "3.G/16  nav-skill-names-the-dm-mechanic"  sc_nav_skill_names_the_dm_mechanic
scenario red   "3.G/17  nav-skill-states-tiers-and-record" sc_nav_skill_states_tiers_and_record
scenario red   "3.G/18  nav-skill-carries-triage-rules"   sc_nav_skill_carries_triage_rules
scenario guard "3.G/14  nav-skill-line-budget"            sc_nav_skill_line_budget
scenario guard "3.G/15  nav-skill-no-erd-referents"       sc_nav_skill_no_erd_referents

NON_GUARD_FAILED=$((FAILED - GUARD_FAILED))
printf '\n── summary ──\n'
printf 'scenarios: %s   passed: %s   failed: %s\n' "$TOTAL" "$PASSED" "$FAILED"
printf 'non-guard failures: %s   guard failures: %s\n' "$NON_GUARD_FAILED" "$GUARD_FAILED"

[ "$FAILED" -eq 0 ] || exit 1
exit 0
