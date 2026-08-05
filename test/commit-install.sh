#!/usr/bin/env sh
# test/commit-install.sh — RED-phase suite for the three remaining ultrareview findings on the
# `brain commit` and `brain install` surfaces: UR-4a, UR-4b and UR-7.
#
# AUTHORITY (in precedence order):
#   1. docs/lane-dm-ultrareview-findings.md
#        · "[MEDIUM] The commit guard certifies a false ignore state and cannot finish
#          tracked-inbox cleanup" — UR-4a (cleanup wedge) and UR-4b (literal-line ignore check),
#          including its Fix paragraph and its Evidence paragraph (the pathspec trap).
#        · "[MEDIUM] Skill installation can falsely report success and expose a partial
#          protocol" — UR-7, including its Fix paragraph ("copy to a same-directory temporary
#          file … atomically rename it over SKILL.md").
#   2. .context/seams/dm-v1.1-queue.md
#        · §"UR fixes riding along" — the three intended fixes, in the words that bind them:
#          UR-4a "the final fail-closed check must distinguish staged additions (refuse) from
#          staged deletions of un-tracked-on-purpose paths (proceed)"; UR-4b "replace the
#          `grep -qxF 'dm/'` ignore check with `git check-ignore --no-index`"; UR-7 "check every
#          `mkdir`/`cp`, route the skill copy through `_atomic_place`".
#        · §"New seams" → `_atomic_place` — the 5-consumer contract, `cmd_install` among them,
#          "temp must move into the DESTINATION dir".
#        · §"Defects found during this pass" item 3 — the cross-device `mktemp`-in-$TMPDIR → `mv`
#          into `$HOME` non-atomicity, and the explicit warning that "naïvely 'checking the return
#          value' would not have fixed this".
# Implementation code is EVIDENCE, never authority. Every place this suite had to choose where
# authority is silent, the scenario comment says so and names the choice that was forced.
#
# RELATIONSHIP TO test/dm.sh: that suite is FROZEN and covers the DM transport (45 scenarios).
# It declares UR-4a/UR-4b/UR-7 as out-of-scope gaps ("they need their own RED pass against the
# commit/install paths, not a DM-transport scenario"). This file is that pass. Harness patterns
# (fixture builders, need_* assertions, the red|guard dispatcher, assert_disposable interlocks,
# exit-3-on-guard-regression) are DELIBERATELY duplicated from dm.sh rather than extracted: two
# files with one duplication is the right altitude, and dm.sh is frozen.
#
# SAFETY — this suite drives `brain install`, which writes MACHINE-GLOBAL files:
#   Every invocation runs with HOME, BRAIN_SKILLS_DIR and BRAIN_GLOBAL_SETTINGS redirected inside
#   the disposable scratch root. `run_brain` validates all three THROUGH `assert_install_env`
#   BEFORE forking — in the PARENT shell, deliberately: an earlier revision called it inside
#   `_brain_exec`'s subshell, where `fatal`'s exit 2 killed only the subshell, `need_rc_nonzero`
#   happily accepted status 2 and the diagnosis vanished into the scenario's captured stderr. A
#   safety interlock that fails silently-green is worse than none, so the check now runs where its
#   exit actually aborts the suite. The real ~/.claude is never a destination, never a source, and
#   never read. Scenarios that chmod a directory read-only restore the mode BEFORE any early
#   return so the EXIT trap can still descend.
#
# DECLARED GAPS (absence here is a decision, not an oversight):
#   · "No DM body in the committed HISTORY" is NOT asserted, and cannot be: the legacy fixture's
#     own baseline commit deliberately contains the body, and `brain commit` does not rewrite
#     history — `git log -p` would show it as a removed line under ANY correct fix. What IS
#     asserted is the stronger-where-it-matters and satisfiable form: no DM path and no DM body
#     in the TREE at the new HEAD (`git ls-tree` + `git grep <rev>`).
#   · The post-commit INDEX SHAPE stays unpinned — no authority fixes it, and the sanitized-index
#     fix is explicitly allowed to change it. WHICH PATHS LAND IN THE COMMIT is a different
#     question and is NOT a gap: it is pinned by UR4a/1 and UR4a/1b per the seam map's 2026-08-04
#     ruling (constraint 3, "still path-scoped IN EFFECT"). An earlier revision of this header
#     conflated the two and declared both non-blocking; that was wrong, and four candidate fixes
#     — including the ultrareview's own temp-index sketch — swept unrelated staged work into the
#     brain commit while scoring 12/12 against the suite that lacked those assertions.
#   · The truncation WINDOW (a concurrent reader observing a half-written SKILL.md) is not
#     directly observable without a race. UR7/8 and UR7/9 cover it indirectly — by outcome (a
#     failed install leaves the PREVIOUS skill byte-intact) and by structure (the destination is
#     produced by a same-directory rename). Neither proves the window's absence under concurrency.
#   · `mkdir` failure is pinned by OUTCOME, never by either check's existence — and this applies
#     to BOTH `mkdir` calls in `cmd_install`, not just the skills one. UR7/7 drives an uncreatable
#     skills directory and UR7/13 an uncreatable settings directory, but on a fixed engine:
#       · removing ONLY the skills `mkdir` check → still full marks (mutant m8); the placement
#         into a directory that could not be created fails one step later anyway;
#       · removing ONLY the settings `mkdir` check → still full marks (mutant n2); the settings
#         seed (`printf '{}' > "$_gs"`) fails one step later anyway.
#     Both checks' residual value is diagnostic precision, which no authority pins, and neither is
#     distinguishable from the CLI. Measured, not assumed. Stated so a reviewer can see the limit
#     rather than infer coverage that is not there.
#   · `_write_project_settings` (reached via `brain init`, not `brain install`) has the same
#     cross-device temp defect and the same `_atomic_place` mandate. Out of the assigned surface;
#     NON-BLOCKING, but it is the third consumer and should land in the same change.
#   · ⚠ UR-4a's cleanup STILL WEDGES PERMANENTLY for one class of legacy vault, and no scenario
#     here covers it. Not a scoping note — a live limitation, stated plainly because the earlier
#     wording ("the scan is a separate control…") read as "we aren't testing the scan" and hid it.
#     The class: `dm/` never ignored, the inbox TRACKED AND UNMODIFIED, and its body carrying a
#     line that matches the commit secret scan's `^[A-Z][A-Z0-9_]*=.+`. Mechanism: the pre-`git
#     add` purge stages a deletion, which pulls the still-present on-disk file into the scan's
#     input list (`git diff --cached --name-only -- .brain`, then `[ -f "$ROOT/$_f" ]`), the scan
#     matches, and `brain commit` aborts — on every rerun, because the staged deletion persists.
#     Measured on today's engine AND on a prototype satisfying all four UR-4a constraints: both
#     abort permanently with `secret-scan abort: …/inbox.jsonl (env-shaped secret)`, the vault
#     change never commits, and the secret stays in the tree. PRE-EXISTING — today's engine does
#     the same, so this is not repair-induced — and NOT closed by the UR-4a fix.
#     Exposure is bounded: a real `inbox.jsonl` line starts with `{` and cannot match the anchored
#     pattern, so the trigger needs a truncated write, a hand-edit, or a pre-v1 body format. This
#     suite's fixtures use JSON bodies deliberately (so the scan cannot abort a run for a reason
#     unrelated to the finding under test), which is exactly why no scenario here reaches it.
#     Tracked outside the suite; adding a scenario is a separate decision, not an oversight.
#
# RED DISCIPLINE: scenarios pinning the FIXED behaviour MUST fail against the current engine.
# Scenarios labelled "guard:" already pass today and must keep passing — they exist because the
# named fixes could plausibly break them (the ultrareview itself notes "deleting the whole guard
# leaves the suite unchanged"). A guard regression exits 3, not 1.
#
# Usage: ./test/commit-install.sh          BRAIN_BIN=<path> overrides the engine under test.

# Scenario bodies are dispatched by name from `scenario`, so shellcheck cannot see the call.
# shellcheck disable=SC2329

set -u

# ── locate the engine under test ─────────────────────────────────────────────────────────
SUITE_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
REPO_ROOT=$(dirname "$SUITE_DIR")
BRAIN_BIN=${BRAIN_BIN:-$REPO_ROOT/bin/brain}

FIXTURE_BRANCH="main"
FIXTURE_MAIN_REF="origin/main"   # deliberately absent from every fixture: fetch/rebase no-ops

# Resolved BEFORE any shim can enter PATH, so the recorders exec the genuine tools.
REAL_MV=$(command -v mv) || REAL_MV=/bin/mv
REAL_CP=$(command -v cp) || REAL_CP=/bin/cp

# ── counters / current-scenario state ────────────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0
GUARD_FAILED=0
SC_FAILED=0
SC_REASONS=""
OUT=""
ERR=""
SHIM_DIR=""
SHIM_LOG=""

fatal() {
  printf 'test/commit-install.sh: FATAL %s\n' "$*" >&2
  exit 2
}

# ── disposable scratch root (the ONLY thing cleanup ever removes) ────────────────────────
SUITE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/brain-ci-test.XXXXXX") || fatal "mktemp failed"
SUITE_TMP=$(cd "$SUITE_TMP" && pwd -P) || fatal "cannot resolve scratch root"

cleanup() {
  case "$SUITE_TMP" in
    */brain-ci-test.*) ;;
    *) printf 'test/commit-install.sh: refusing to remove unexpected scratch root %s\n' "$SUITE_TMP" >&2
       return 0 ;;
  esac
  case "$SUITE_TMP" in
    *research-dashboard*|*agent-brain*)
      printf 'test/commit-install.sh: refusing to remove a path under a real project: %s\n' "$SUITE_TMP" >&2
      return 0 ;;
  esac
  # a scenario may leave a 0500 directory behind on an unexpected early exit
  chmod -R u+rwX "$SUITE_TMP" 2>/dev/null || true
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
    *research-dashboard*|*agent-brain*) fatal "refusing to operate on a real project path: $1" ;;
  esac
}

# HARD SAFETY INTERLOCK. `brain install` writes machine-global files; if HOME, the skills dir or
# the global settings path ever pointed outside the scratch root, this suite would overwrite the
# developer's real ~/.claude/skills/navigation-standards/SKILL.md and ~/.claude/settings.json.
# Checked on EVERY invocation, not once at startup, so a fixture bug cannot open the hole later.
# ⚠ MUST be called from the PARENT shell (`run_brain`), never from inside `_brain_exec`'s
# subshell: `fatal`'s exit would otherwise terminate only the subshell, the scenario would read it
# as an ordinary non-zero engine exit, and the breach would be reported as a PASS.
assert_install_env() { # <home> <skills-dir> <global-settings>
  assert_disposable "$1"
  assert_disposable "$2"
  assert_disposable "$3"
  case "$1" in "$HOME"|"$HOME"/*) fatal "fixture HOME resolves into the real HOME: $1" ;; esac
  case "$2" in "$HOME"/*) fatal "fixture skills dir resolves into the real HOME: $2" ;; esac
  case "$3" in "$HOME"/*) fatal "fixture global settings resolves into the real HOME: $3" ;; esac
}

# ── preflight ────────────────────────────────────────────────────────────────────────────
[ -x "$BRAIN_BIN" ] || fatal "engine not executable: $BRAIN_BIN"
command -v jq  >/dev/null 2>&1 || fatal "jq is required (the engine itself depends on it)"
command -v git >/dev/null 2>&1 || fatal "git is required"
command -v awk >/dev/null 2>&1 || fatal "awk is required"

# ── fixture helpers ──────────────────────────────────────────────────────────────────────

# make_vault → prints the fixture REPO path (with a sibling fake HOME). No lanes are registered:
# neither `brain commit` nor `brain install` reads presence, and a smaller fixture is a smaller
# surface for an unrelated failure to enter through.
make_vault() {
  _mv_base=$(mktemp -d "$SUITE_TMP/vault.XXXXXX") || { printf 'make_vault: mktemp failed\n' >&2; return 1; }
  _mv_base=$(cd "$_mv_base" && pwd -P) || return 1
  assert_disposable "$_mv_base"
  _mv_repo="$_mv_base/repo"
  mkdir -p "$_mv_repo" "$_mv_base/home/.claude" || return 1

  git init -q -b "$FIXTURE_BRANCH" "$_mv_repo" >/dev/null 2>&1 \
    || { printf 'make_vault: git init failed\n' >&2; return 1; }
  git -C "$_mv_repo" config user.email "brain-ci-test@example.invalid" || return 1
  git -C "$_mv_repo" config user.name  "brain ci test" || return 1
  git -C "$_mv_repo" config commit.gpgsign false || return 1
  printf 'disposable fixture repo for test/commit-install.sh\n' > "$_mv_repo/README-fixture.txt"
  git -C "$_mv_repo" add -- README-fixture.txt >/dev/null 2>&1 || return 1
  git -C "$_mv_repo" commit -q -m "fixture base" >/dev/null 2>&1 \
    || { printf 'make_vault: base commit failed\n' >&2; return 1; }

  run_brain "$_mv_repo" init --no-install
  if [ ! -d "$_mv_repo/.brain" ]; then
    printf 'make_vault: brain init did not scaffold .brain (stderr below)\n' >&2
    cat "$ERR" >&2 2>/dev/null
    return 1
  fi

  # `brain init` copies templates out of the ENGINE's own tree ($(dirname $0)/../templates), so a
  # BRAIN_BIN pointed anywhere else — a mutation probe, a staged build — scaffolds a vault with no
  # nav-skill template, `cmd_install` then dies at its template check, and every install scenario
  # collapses for a FIXTURE reason (observed: it also made UR7/11 pass vacuously). The template is
  # fixture INPUT, not the thing under test, so seed it from the repo under test when it is absent.
  if [ ! -f "$_mv_repo/.brain/templates/navigation-standards.SKILL.md" ]; then
    mkdir -p "$_mv_repo/.brain/templates" || return 1
    cp "$REPO_ROOT/templates/navigation-standards.SKILL.md" "$_mv_repo/.brain/templates/" \
      || { printf 'make_vault: could not seed the nav-skill template\n' >&2; return 1; }
  fi

  printf '%s\n' "$_mv_repo"
}

# Per-scenario overrides for the two machine-global install destinations. Empty (the default,
# reset by `scenario`) means "derive from the fixture HOME". They exist so a scenario can make ONE
# of the two paths uncreatable while the other stays writable — otherwise every install failure is
# driven through the same directory and the settings-side `mkdir` can never fail, because the
# fixture always pre-creates its parent. Overrides are NOT an escape from the interlock:
# `run_brain` validates whatever they resolve to, exactly like the derived values.
OVERRIDE_SKILLS_DIR=""
OVERRIDE_GLOBAL_SETTINGS=""

# eff_skills_dir / eff_settings <repo> — the paths a run will actually use.
eff_skills_dir() { # <repo>
  if [ -n "$OVERRIDE_SKILLS_DIR" ]; then printf '%s' "$OVERRIDE_SKILLS_DIR"
  else printf '%s' "$(dirname "$1")/home/.claude/skills"; fi
}
eff_settings() { # <repo>
  if [ -n "$OVERRIDE_GLOBAL_SETTINGS" ]; then printf '%s' "$OVERRIDE_GLOBAL_SETTINGS"
  else printf '%s' "$(dirname "$1")/home/.claude/settings.json"; fi
}

# The engine invocation. SHIM_DIR, when a scenario has set it, goes AHEAD of PATH so the call
# recorders see the engine's own `mv`/`cp` (including `_atomic_place`'s `command mv`, which
# bypasses functions and aliases but still resolves through PATH).
# No interlock call here — see assert_install_env's warning; `run_brain` owns that, in the parent.
_brain_exec() {
  _be_repo=$1; shift
  _be_base=$(dirname "$_be_repo")
  cd "$_be_repo" || exit 127
  exec env \
    PATH="${SHIM_DIR:+$SHIM_DIR:}$PATH" \
    HOME="$_be_base/home" \
    BRAIN_TEST_BRANCH="$FIXTURE_BRANCH" \
    BRAIN_MAIN_REF="$FIXTURE_MAIN_REF" \
    BRAIN_SKILLS_DIR="$(eff_skills_dir "$_be_repo")" \
    BRAIN_GLOBAL_SETTINGS="$(eff_settings "$_be_repo")" \
    "$BRAIN_BIN" "$@"
}

# run_brain <repo> [args...] — sets $OUT / $ERR to the captured streams; caller reads $?.
# The safety interlock runs HERE, in the parent shell, so a breach aborts the whole suite.
run_brain() {
  assert_disposable "$1"
  _rb_base=$(dirname "$1")
  assert_install_env "$_rb_base/home" "$(eff_skills_dir "$1")" "$(eff_settings "$1")"
  OUT="$_rb_base/last.out"
  ERR="$_rb_base/last.err"
  ( _brain_exec "$@" ) >"$OUT" 2>"$ERR"
}

# fixture paths (override-aware, so a scenario's assertions follow its own redirection)
skills_dir_of()  { eff_skills_dir "$1"; }
skill_dest_of()  { printf '%s' "$(eff_skills_dir "$1")/navigation-standards/SKILL.md"; }
skill_dir_of()   { printf '%s' "$(eff_skills_dir "$1")/navigation-standards"; }
settings_of()    { eff_settings "$1"; }
skill_src_of()   { printf '%s' "$1/.brain/templates/navigation-standards.SKILL.md"; }

# plant_dm <repo> <lane> <marker> — a v1.1-shaped pending message AND a legacy inbox.jsonl,
# both carrying <marker>. Both shapes are planted because the wedge is about "anything under
# .brain/dm is tracked", and a legacy vault predates the per-message layout. Bodies are JSON
# objects, never `KEY=value` lines, so the engine's line-anchored secret scan cannot abort the
# run for a reason unrelated to the finding under test.
plant_dm() {
  mkdir -p "$1/.brain/dm/$2/pending" || return 1
  printf '{"from":"alpha","to":"%s","ts":"2026-01-01T00:00:00Z","content":"%s"}\n' "$2" "$3" \
    > "$1/.brain/dm/$2/pending/20260101T000000Z-1.a0" || return 1
  printf '{"from":"alpha","to":"%s","ts":"2026-01-01T00:00:00Z","content":"%s"}\n' "$2" "$3" \
    > "$1/.brain/dm/$2/inbox.jsonl" || return 1
}
dm_pending_file() { printf '%s' "$1/.brain/dm/$2/pending/20260101T000000Z-1.a0"; }
dm_legacy_file()  { printf '%s' "$1/.brain/dm/$2/inbox.jsonl"; }

MARKER_PATH=".brain/research/ur-commit-marker.md"
# mark_vault <repo> <unique-text> — a REAL vault change, so "the commit succeeded" can be
# distinguished from "the commit had nothing to do".
mark_vault() { printf 'vault marker %s\n' "$2" >> "$1/$MARKER_PATH"; }

# A developer's unrelated work, STAGED, outside .brain. Seam-map ruling 2026-08-04 (UR-4a
# constraint 3): it must not be swept into the brain commit. Staged rather than merely present,
# because that is the state every no-pathspec `git commit` sweeps up.
OUTSIDE_PATH="src/UNRELATED-STAGED.txt"
stage_outside_work() { # <repo>
  mkdir -p "$1/src" || return 1
  printf 'developer work in progress — must never enter a brain commit\n' > "$1/$OUTSIDE_PATH" || return 1
  git -C "$1" add -- "$OUTSIDE_PATH" >/dev/null 2>&1 || return 1
  git -C "$1" diff --cached --name-only -- "$OUTSIDE_PATH" 2>/dev/null | grep -q . || return 1
}

# strip_dm_ignore <repo> — a vault initialized BEFORE the DM feature: the `dm/` rule was never
# written, which is how a real inbox came to be tracked in the first place.
strip_dm_ignore() {
  grep -v '^dm/$' "$1/.brain/.gitignore" > "$1/.brain/.gitignore.tmp" 2>/dev/null || true
  mv "$1/.brain/.gitignore.tmp" "$1/.brain/.gitignore" || return 1
  grep -qxF 'dm/' "$1/.brain/.gitignore" 2>/dev/null && return 1   # must be gone
  return 0
}

git_commit_all() { # <repo> <subject>
  git -C "$1" add -A >/dev/null 2>&1 || return 1
  git -C "$1" commit -q -m "$2" >/dev/null 2>&1 || return 1
}
git_commit_path() { # <repo> <subject> <path>
  git -C "$1" add -- "$3" >/dev/null 2>&1 || return 1
  git -C "$1" commit -q -m "$2" -- "$3" >/dev/null 2>&1 || return 1
}

head_sha()       { git -C "$1" rev-parse HEAD 2>/dev/null; }
tracked_dm()     { git -C "$1" ls-files --cached -- .brain/dm 2>/dev/null; }
tree_paths_dm()  { git -C "$1" ls-tree -r --name-only HEAD -- .brain/dm 2>/dev/null; }
# searches the TREE at HEAD (not the diff, not history) — see the declared gap above.
tree_has_text()  { git -C "$1" grep -q -I -F -e "$2" HEAD 2>/dev/null; }
head_file_has()  { git -C "$1" show "HEAD:$2" 2>/dev/null | grep -qF -- "$3"; }
# git's REAL ignore decision for a path, tracked or not (the check UR-4b says must replace grep)
path_ignored()   { git -C "$1" check-ignore --no-index -q -- "$2" 2>/dev/null; }

# ── call-recording shim (structural instrument for UR7/9 + UR7/10) ───────────────────────
# Records "<tool>\t<second-to-last arg>\t<last arg>" for every mv/cp the engine execs, then
# execs the genuine tool. `mv [opts] [--] SRC DEST` and `cp [opts] SRC DEST` both put the pair
# last, which is what makes the two-field record sufficient.
make_shim() { # <base>
  _mk_base=$1
  assert_disposable "$_mk_base"
  SHIM_DIR="$_mk_base/shim"
  SHIM_LOG="$_mk_base/calls.log"
  mkdir -p "$SHIM_DIR" || return 1
  : > "$SHIM_LOG" || return 1
  for _mk_t in mv cp; do
    case "$_mk_t" in
      mv) _mk_real=$REAL_MV ;;
      cp) _mk_real=$REAL_CP ;;
    esac
    cat > "$SHIM_DIR/$_mk_t" <<EOF
#!/bin/sh
_n=\$#; _s=-; _d=-; _i=0
for _a in "\$@"; do
  _i=\$((_i + 1))
  [ "\$_i" = "\$((_n - 1))" ] && _s=\$_a
  [ "\$_i" = "\$_n" ] && _d=\$_a
done
printf '%s\t%s\t%s\n' '$_mk_t' "\$_s" "\$_d" >> '$SHIM_LOG'
exec '$_mk_real' "\$@"
EOF
    chmod +x "$SHIM_DIR/$_mk_t" || return 1
  done
  return 0
}

# Canonical key for a path's DIRECTORY, so /var/... and /private/var/... (macOS $TMPDIR) do not
# read as different directories, and so `dir/./x` cannot masquerade as a different location.
dir_key() {
  _dkp=${1%/*}
  [ "$_dkp" = "$1" ] && _dkp="."
  ( cd "$_dkp" 2>/dev/null && pwd -P ) 2>/dev/null || printf '%s' "$_dkp"
}

# rename_verdict <log> <dest> → ok | crossdir | tool:<name> | none
# Side-effect free, so the scenario's own negative and positive controls can assert on it.
# LAST writer wins: an implementation that writes a temp and then renames it is judged on the
# rename, and one that renames first and then copies over it is judged on the copy.
rename_verdict() {
  _rv_tool=$(awk -F'\t' -v d="$2" '$3 == d { t = $1 } END { if (t != "") print t }' "$1" 2>/dev/null)
  _rv_src=$(awk -F'\t' -v d="$2" '$3 == d { s = $2 } END { if (s != "") print s }' "$1" 2>/dev/null)
  [ -n "$_rv_tool" ] || { printf 'none'; return 0; }
  [ "$_rv_tool" = "mv" ] || { printf 'tool:%s' "$_rv_tool"; return 0; }
  if [ "$(dir_key "$_rv_src")" = "$(dir_key "$2")" ]; then printf 'ok'; else printf 'crossdir'; fi
}
rename_src() { awk -F'\t' -v d="$2" '$3 == d { s = $2 } END { print s }' "$1" 2>/dev/null; }

# ── instruments ──────────────────────────────────────────────────────────────────────────

# make_readonly_dir <dir> — chmod 0500 plus a POSITIVE CONTROL that creating an entry really
# fails here. Without the control, "the engine could not write" is indistinguishable from
# "the suite is running as root and the block never engaged".
# Returns 0 (blocked, instrument live), 1 (fixture error), 2 (instrument blind).
make_readonly_dir() {
  _mr_d=$1
  mkdir -p "$_mr_d" || return 1
  chmod 500 "$_mr_d" || return 1
  if ( : > "$_mr_d/.probe.$$" ) 2>/dev/null; then
    rm -f "$_mr_d/.probe.$$" 2>/dev/null
    chmod 755 "$_mr_d" 2>/dev/null
    return 2
  fi
  return 0
}
readonly_failed() { # <rc> <what>
  case "$1" in
    2) fail "instrument blind: a file can still be created inside a 0500 directory ($2) — running as root? the injected-failure instrument cannot be built on this machine" ;;
    *) fail "fixture error building the read-only directory instrument ($2), rc=$1" ;;
  esac
}

# ── assertion helpers — each records a reason and returns 1 so callers can short-circuit ─
fail() {
  SC_FAILED=1
  SC_REASONS="$SC_REASONS
      - $*"
  return 1
}

err_tail() { tr '\n' ' ' < "$ERR" 2>/dev/null | cut -c1-200; }

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
need_empty() { # <value> <label>
  [ -z "$1" ] && return 0
  fail "$2: expected nothing, got '$1'"
}
need_file() { [ -f "$1" ] && return 0; fail "$2: no such file: $1"; }
need_file_absent() { [ ! -e "$1" ] && [ ! -L "$1" ] && return 0; fail "$2: must not exist: $1"; }
need_file_has() {  # <file> <needle> <label>
  grep -qF -- "$2" "$1" 2>/dev/null && return 0
  fail "$3: '$2' not found in $1"
}
need_file_lacks() { # <file> <needle> <label>
  grep -qF -- "$2" "$1" 2>/dev/null || return 0
  fail "$3: '$2' WAS found in $1 and must not be"
}
need_same_bytes() { # <a> <b> <label>
  cmp -s "$1" "$2" && return 0
  fail "$3: $1 and $2 differ"
}
need_differs() { # <a> <b> <label>
  cmp -s "$1" "$2" || return 0
  fail "$3: $1 and $2 are identical and must not be"
}
need_tree_lacks_dm() { # <repo> <label>
  _ntd=$(tree_paths_dm "$1")
  [ -z "$_ntd" ] && return 0
  fail "$2: the tree at HEAD still carries DM path(s): $(printf '%s' "$_ntd" | tr '\n' ' ')"
}
need_index_reconciled() { # <repo> <label>
  git -C "$1" diff --cached --quiet HEAD -- .brain 2>/dev/null && return 0
  fail "$2: the REAL index disagrees with the new HEAD for .brain — $(git -C "$1" diff --cached --name-status HEAD -- .brain 2>/dev/null | tr '\n' ' '). A commit whose files read as staged deletions afterwards is reverted by the developer's very next 'git commit -a' (seam map ruling 2026-08-04 round 2, UR-4a constraint 4)"
}
need_still_staged() { # <repo> <path> <label>
  git -C "$1" diff --cached --name-status HEAD -- "$2" 2>/dev/null | grep -q . && return 0
  fail "$3: '$2' is no longer staged — reconciling the real index must not disturb any OTHER staged path (seam map UR-4a constraint 4). A blanket 'git read-tree HEAD' does exactly this damage"
}
need_tree_lacks_path() { # <repo> <path> <label>
  git -C "$1" ls-tree -r --name-only HEAD -- "$2" 2>/dev/null | grep -q . || return 0
  fail "$3: '$2' IS in the tree at HEAD. Only .brain paths may land in a brain commit (seam map ruling 2026-08-04, UR-4a constraint 3 'still path-scoped IN EFFECT'; the engine advertises 'path-scoped' at bin/brain:1232). Dropping the pathspec to unwedge sweeps a developer's unrelated staged work into 'chore(brain): sync coordination vault'"
}
need_tree_lacks_text() { # <repo> <needle> <label>
  tree_has_text "$1" "$2" || return 0
  fail "$3: the DM body '$2' is present in the tree at HEAD and must never be committed"
}
need_head_file_has() { # <repo> <path-in-tree> <needle> <label>
  head_file_has "$1" "$2" "$3" && return 0
  fail "$4: '$3' is not in $2 at HEAD — the real vault change did not get committed"
}
need_ignored() { # <repo> <path> <label>
  path_ignored "$1" "$2" && return 0
  fail "$3: git does NOT ignore $2 (git check-ignore --no-index) — the ignore invariant is not in force, whatever .gitignore says textually"
}
need_not_ignored() { # <repo> <path> <label>   (used only as a fixture/instrument control)
  path_ignored "$1" "$2" || return 0
  fail "$3: git DOES ignore $2 — the fixture's override did not take, so this scenario would be vacuous"
}
need_no_dotfiles() { # <dir> <label> — no `.tmp-*`-style residue left behind
  _nd=""
  for _nd_f in "$1"/.*; do
    case "${_nd_f##*/}" in .|..) continue ;; esac
    [ -e "$_nd_f" ] || [ -L "$_nd_f" ] || continue
    _nd="$_nd ${_nd_f##*/}"
  done
  [ -z "$_nd" ] && return 0
  fail "$2: temp/dot residue left in $1:$_nd"
}
need_verdict() { # <actual> <expected> <label>
  [ "$1" = "$2" ] && return 0
  fail "$3: instrument verdict '$1', want '$2'"
}
# A failed install must not be SILENT. Deliberately stream-agnostic: an earlier revision required
# the destination path to be absent from stdout, which would false-RED a GREEN that prints its
# failure diagnostics to stdout rather than stderr — nothing in authority fixes the stream, and a
# failure message legitimately names the path it could not write. "Did not report success" is
# carried by the non-zero exit plus the destination-state assertions in each scenario; this only
# adds "and said something about it somewhere".
need_not_silent() { # <label>
  if [ -s "$OUT" ] || [ -s "$ERR" ]; then return 0; fi
  fail "$1: the run failed without writing anything to stdout OR stderr — a silent failure is indistinguishable from a no-op"
}
need_writable_dir() { # <dir> <label>
  if ( : > "$1/.writable-probe" ) 2>/dev/null; then
    rm -f "$1/.writable-probe" 2>/dev/null
    return 0
  fi
  fail "$2: $1 is not writable"
}

# ── scenario runner ──────────────────────────────────────────────────────────────────────
scenario() { # <kind: red|guard> <name> <function>
  SC_FAILED=0
  SC_REASONS=""
  SHIM_DIR=""                 # never let one scenario's PATH shim leak into the next
  SHIM_LOG=""
  OVERRIDE_SKILLS_DIR=""      # …nor its install-destination redirection
  OVERRIDE_GLOBAL_SETTINGS=""
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

# ═════════════════════════ UR-4a — the tracked-inbox cleanup wedge ════════════════════════

# UR4a/1 — a legacy vault whose DM state is ALREADY TRACKED must be able to commit.
#   AUTHORITY  ultrareview UR-4a ("`git rm --cached` stages the intended deletion, but the final
#              `git diff --cached --name-only` treats that deletion as a failure and aborts
#              forever") + seam map §"UR fixes riding along": the final check "must distinguish
#              staged additions (refuse) from staged deletions of un-tracked-on-purpose paths
#              (proceed)". "Proceed" is mandated, so this scenario requires exit 0 — it does not
#              accept a polite refusal.
#   PROVES     the cleanup completes: the command succeeds, the real vault change lands, the DM
#              paths end up UNTRACKED, and neither the DM paths nor their bodies are in the tree
#              at the new HEAD.
#   REJECTS    (a) today's wedge — exit 1, nothing commits, ever;
#              (b) the naive repair "just allow staged deletions through the final check". That
#              fix keeps `git commit -- .brain`, and pathspec semantics read the still-present
#              WORKING-TREE inbox: measured in a scratch repo, the deleted-from-index DM file is
#              silently RE-COMMITTED into the tree and the untracked vault marker is not
#              committed at all. The ultrareview names this trap; the tree assertions below are
#              what catch it.
#              (c) — added 2026-08-04 — the repair that satisfies (a)+(b) by dropping the pathspec
#              from `git commit`, which makes it take the WHOLE index and sweep a developer's
#              unrelated staged work into the brain commit. Four candidate fixes did exactly this
#              and scored 12/12 before this limb existed. Authority: seam map UR-4a constraint 3.
#              The limb lives HERE as well as in UR4a/1b because this is the path on which the
#              fix rewrites the commit call; a guard on the ordinary path alone would leave the
#              rewritten call unpinned.
#   DOES NOT   pin HOW cleanup is achieved (sanitized temporary index, `git commit-tree`, an
#              index-restoring dance) — only its observable outcome; nor the post-commit INDEX
#              shape (unpinned by design — "which paths land in the commit" is the pinned
#              question, not "what is left staged"). It also does not assert anything about
#              history: the fixture's own baseline commit contains the body by construction (see
#              the declared gap in the header).
sc_ur4a_legacy_tracked_inbox_commits_clean() {
  fx=$(make_vault) || fatal "fixture build failed"
  body="URCOMMITBODYPROBE-1a"

  strip_dm_ignore "$fx" || { fail "fixture: could not remove the dm/ rule from .brain/.gitignore"; return 0; }
  plant_dm "$fx" bravo "$body" || { fail "fixture: could not plant DM state"; return 0; }
  mark_vault "$fx" "baseline"
  git_commit_all "$fx" "legacy vault with a tracked DM inbox" \
    || { fail "fixture: baseline commit failed"; return 0; }

  # fixture control: the legacy state really is TRACKED, else the wedge is never reached
  [ -n "$(tracked_dm "$fx")" ] || { fail "fixture: .brain/dm is not tracked at baseline — nothing to wedge on"; return 0; }
  tree_has_text "$fx" "$body" || { fail "fixture: the DM body is not in the baseline tree — the cleanup has nothing to clean"; return 0; }

  mark_vault "$fx" "change-one"
  stage_outside_work "$fx" || { fail "fixture: could not stage unrelated work outside .brain"; return 0; }
  run_brain "$fx" commit
  rc=$?

  need_rc "$rc" 0 "brain commit on a legacy vault with a tracked DM inbox"
  need_tree_lacks_path "$fx" "$OUTSIDE_PATH" "unrelated staged work after the unwedging commit"
  need_empty "$(tracked_dm "$fx")" "DM paths still tracked in the index after commit"
  # Constraint 4 on the path where the fix rewrites the commit call. Conditional on success
  # because index state after a REFUSED commit is not what this asserts — while the wedge stands
  # this limb is dormant, and UR4a/1c carries the durability property on a path that succeeds
  # today. It goes live the moment the wedge clears.
  if [ "$rc" = "0" ]; then
    need_index_reconciled "$fx" "the real index after the unwedging commit"
  fi
  need_tree_lacks_dm "$fx" "DM paths in the tree at HEAD after commit"
  need_tree_lacks_text "$fx" "$body" "DM body in the tree at HEAD after commit"
  need_head_file_has "$fx" "$MARKER_PATH" "vault marker change-one" "the real vault change"
  # un-tracking is an INDEX operation: the lane's queued message must survive on disk
  need_file "$(dm_pending_file "$fx" bravo)" "the queued message file after un-tracking"
  need_file "$(dm_legacy_file "$fx" bravo)" "the legacy inbox file after un-tracking"
  # and the invariant that made the cleanup necessary must now actually hold
  need_ignored "$fx" ".brain/dm/bravo/pending/20260101T000000Z-1.a0" "the DM path after cleanup"
}

# UR4a/1b — guard. A brain commit stays PATH-SCOPED: only .brain paths may land in it.
#   AUTHORITY  seam map §"UR fixes riding along" → UR-4a RULING 2026-08-04, constraint 3: "ONLY
#              `.brain` paths may land in the commit. The engine advertises 'path-scoped' in its
#              usage (`bin/brain:1232`) and the current call is pathspec-scoped (`:866`)."
#   PROVES     with a developer's unrelated file STAGED outside .brain, an ordinary `brain commit`
#              records the .brain change and leaves the unrelated path out of the tree.
#   REJECTS    every candidate repair that unwedges by dropping `-- .brain` from `git commit`,
#              which takes the whole index. Measured directly: a no-pathspec commit with
#              `src/UNRELATED.txt` staged puts it in the tree at HEAD. This is the ONE constraint
#              the audit found four independent fixes breaking while scoring 12/12 — including
#              the ultrareview's own temp-index sketch, and this suite's own prototype witness.
#   DOES NOT   pin what remains staged afterwards (the index shape is unpinned by design), and
#              does not distinguish "seeded the temp index from HEAD" from any other mechanism
#              that produces a .brain-only commit — only the tree is asserted.
#   BASELINE   green today: `git commit -- .brain` is already path-scoped. It is a guard precisely
#              because the fix is what endangers it.
sc_ur4a_commit_stays_path_scoped() {
  fx=$(make_vault) || fatal "fixture build failed"
  git_commit_all "$fx" "vault baseline" || { fail "fixture: baseline commit failed"; return 0; }

  mark_vault "$fx" "scoped-change"
  stage_outside_work "$fx" || { fail "fixture: could not stage unrelated work outside .brain"; return 0; }

  run_brain "$fx" commit
  rc=$?

  need_rc "$rc" 0 "brain commit with unrelated work staged outside .brain"
  need_head_file_has "$fx" "$MARKER_PATH" "vault marker scoped-change" "the real vault change"
  need_tree_lacks_path "$fx" "$OUTSIDE_PATH" "unrelated staged work after a brain commit"
  # the developer's work must also still BE there — swept-in is one failure, deleted is another
  need_file "$fx/$OUTSIDE_PATH" "the developer's unrelated file on disk after a brain commit"
}

# UR4a/1c — guard. The commit must SURVIVE the developer's next ordinary git command.
#   AUTHORITY  seam map §UR-4a RULING round 2 (2026-08-04), constraint 4: "The real index must
#              agree with the new HEAD for `.brain` afterward … A commit the next git command
#              undoes is not durability, which is `cmd_commit`'s whole contract. Pin: after a
#              successful commit, `git diff --cached --quiet HEAD -- .brain`." Plus the same
#              paragraph's "WITHOUT disturbing any other staged path".
#   WHY IT     this constraint was discovered BECAUSE the fix for constraint 3 broke it. A
#   EXISTS     temp-index shape that never touches the real index leaves the just-synced files
#              reading as staged DELETIONS against the new HEAD. Measured on prototype v2:
#              `brain commit` exits 0, the marker is in the tree, this suite scored it 14/14 —
#              and then `git commit -a` emptied the marker. Today's engine survives the same
#              sequence, so this is a real regression the previous suite would have certified.
#   PROVES     three limbs, in the order they matter: the index agrees with the new HEAD for
#              .brain; unrelated staged work is STILL staged afterwards; and the vault change is
#              still at HEAD after a subsequent `git commit -a`.
#   REJECTS    (a) the temp-index shape that leaves the real index stale (limb 1 + limb 3);
#              (b) reconciling with a blanket `git read-tree HEAD`, which fixes limb 1 by
#              destroying limb 2 — the developer's staged work silently leaves the index.
#   DOES NOT   pin the reconciliation mechanism. `git reset HEAD -- .brain` satisfies all three
#              limbs and so does the pathspec commit today; any other mechanism with the same
#              observable result passes.
#   BASELINE   green today — today's engine reconciles as a side effect of the pathspec form.
sc_ur4a_commit_survives_the_next_git_command() {
  fx=$(make_vault) || fatal "fixture build failed"
  git_commit_all "$fx" "vault baseline" || { fail "fixture: baseline commit failed"; return 0; }

  mark_vault "$fx" "durable-change"
  stage_outside_work "$fx" || { fail "fixture: could not stage unrelated work outside .brain"; return 0; }

  run_brain "$fx" commit
  rc=$?
  need_rc "$rc" 0 "brain commit before the durability checks" || return 0
  need_head_file_has "$fx" "$MARKER_PATH" "vault marker durable-change" "the vault change at HEAD"

  need_index_reconciled "$fx" "the real index after a successful commit"
  need_still_staged "$fx" "$OUTSIDE_PATH" "the developer's unrelated staged work after the commit"

  # The harm, end to end: whatever the index looks like, the sync must not evaporate on the
  # developer's next ordinary commit. rc is ignored — "nothing to commit" is a healthy outcome.
  git -C "$fx" commit -q -a -m "the developer's next ordinary commit" >/dev/null 2>&1
  need_head_file_has "$fx" "$MARKER_PATH" "vault marker durable-change" \
    "the vault change after the developer's next 'git commit -a'"
}

# UR4a/2 — the wedge is about PERMANENCE, so one-shot success proves nothing.
#   AUTHORITY  ultrareview UR-4a Evidence: "Retrying cannot recover: the deletion remains staged,
#              `git add -- .brain` does not re-add the ignored path, and every later final check
#              aborts again."
#   PROVES     a SECOND `brain commit` on the same vault also succeeds and also lands its change.
#   REJECTS    a fix that clears the wedge once (e.g. by unstaging on the way out) but leaves the
#              vault in a state that re-wedges on the next run — and, measured today, the engine
#              fails all three of three consecutive runs identically.
#   DOES NOT   test concurrency, and does not re-assert UR4a/1's tree invariants beyond the DM
#              paths (that scenario owns them); if UR4a/1 is red this is red too, by design —
#              its distinct claim is the SECOND run.
sc_ur4a_repeat_commit_after_cleanup() {
  fx=$(make_vault) || fatal "fixture build failed"
  body="URCOMMITBODYPROBE-2a"

  strip_dm_ignore "$fx" || { fail "fixture: could not remove the dm/ rule"; return 0; }
  plant_dm "$fx" bravo "$body" || { fail "fixture: could not plant DM state"; return 0; }
  mark_vault "$fx" "baseline"
  git_commit_all "$fx" "legacy vault with a tracked DM inbox" \
    || { fail "fixture: baseline commit failed"; return 0; }
  [ -n "$(tracked_dm "$fx")" ] || { fail "fixture: .brain/dm is not tracked at baseline"; return 0; }

  mark_vault "$fx" "change-one"
  run_brain "$fx" commit
  rc1=$?
  # `run_brain` reuses one $ERR path, so the second run overwrites the first. Snapshot each run's
  # diagnosis NOW; otherwise both failure messages below quote the SECOND run's stderr and a
  # first-run-only cause is invisible.
  err1=$(err_tail)
  sha1=$(head_sha "$fx")

  mark_vault "$fx" "change-two"
  run_brain "$fx" commit
  rc2=$?
  err2=$(err_tail)
  sha2=$(head_sha "$fx")

  [ "$rc1" = "0" ] || fail "first brain commit: exit $rc1, want 0 (run-1 stderr: $err1)"
  [ "$rc2" = "0" ] || fail "second brain commit (the wedge is permanent, so this is the load-bearing one): exit $rc2, want 0 (run-2 stderr: $err2)"
  [ "$sha1" = "$sha2" ] && fail "the second commit did not advance HEAD — the second real vault change was not recorded"
  need_head_file_has "$fx" "$MARKER_PATH" "vault marker change-two" "the second vault change"
  need_tree_lacks_dm "$fx" "DM paths in the tree at HEAD after two commits"
  need_tree_lacks_text "$fx" "$body" "DM body in the tree at HEAD after two commits"
}

# UR4a/3 — guard. A staged DM ADDITION must never reach the committed tree.
#   AUTHORITY  seam map §"UR fixes riding along": the final check must "distinguish staged
#              additions (REFUSE) from staged deletions … (proceed)"; ultrareview UR-4a Evidence,
#              "Simply allowing deletions is unsafe". Also the ultrareview's suite-coverage
#              remark: "deleting the whole guard leaves the suite unchanged" — this guard is the
#              reason that stops being true.
#   PROVES     with a DM file force-staged before the run, no DM path and no DM body is in the
#              tree at the new HEAD, and a reported success is a real success (the vault marker
#              landed). Exit 0 and a clean refusal are BOTH accepted: the seam map says "refuse"
#              of the final check, but the engine legitimately purges the addition earlier, and
#              the outcome — never in the tree — is what the finding protects.
#   REJECTS    the deletion of the whole guard (measured: mutant m1, which strips both purges AND
#              the final check, fails this scenario and only this one).
#              ⚠ ALSO ARCHITECTURE-DEPENDENT, so do not read this guard as the only thing standing
#              between the vault and a deleted guard block: on a sanitized-temp-index engine the
#              same deletion (mutant n4) does NOT flip this scenario, because staging with
#              `git add -A` into the temp index respects `.gitignore` and the block is largely
#              redundant there. Deletion is still caught — by UR4a/1, UR4a/2 and UR4b/5 — but by
#              those scenarios, not this one.
#   DOES NOT   discriminate WHICH mechanism kept the addition out — and NO claim about purge
#              redundancy holds without naming the architecture it was measured on. Two earlier
#              versions of this paragraph got that wrong in opposite directions. The measured
#              matrix (each mutant neuters exactly one purge; "caught by" means the suite fails):
#                · pre-`git add` real-index purge removed:
#                    – on a temp-index engine with NO index reconciliation → caught by UR4a/1
#                      ("DM paths still tracked in the index after commit");
#                    – on a temp-index engine that DOES reconcile (constraint 4) → caught by
#                      nothing IN THIS SUITE, because every fixture here uses a JSON body.
#                      ⚠ It is NOT dead code, and an earlier version of this comment said it was
#                      — retracted. On the input this suite deliberately avoids (a tracked,
#                      unmodified inbox whose body matches the secret scan's `^[A-Z][A-Z0-9_]*=.+`)
#                      the purge's staged deletion pulls that file into the scan's list and
#                      `brain commit` aborts permanently, secret still in the tree; with the purge
#                      neutered the same vault commits cleanly. Measured both ways. So its removal
#                      IS observable — just not through any fixture here.
#                · sanitized-index purge removed → caught by UR4a/1 AND UR4a/2 in BOTH shapes
#                  (DM path and body reach the committed tree). This purge is load-bearing
#                  everywhere it has been measured.
#              Either way the scenario that reads the purges is UR4a/1, not this one — and any
#              future "this purge is redundant" claim must name BOTH the architecture it was
#              measured on AND whether the secret-scan path was exercised. Two revisions of this
#              comment were wrong for want of exactly those two qualifiers.
#   ALSO       the FINAL fail-closed check (`bin/brain:859`) is not pinned here either: with any
#              purge intact the index is already clean when it runs. It is load-bearing in the
#              case this suite cannot drive — a DM file landing BETWEEN the purge and the check,
#              which needs a concurrent writer — and that is exactly why the engine's own post-add
#              re-purge is deliberately non-fatal (`|| true`, `bin/brain:858`): the check is what
#              stands if that purge silently fails. The seam map keeps it for that reason and
#              requires it to distinguish additions (refuse) from deletions (proceed).
#                · the FINAL fail-closed check (`bin/brain:859`) is not pinned by this scenario
#              either: with either purge intact the index is already clean when it runs, so
#              removing it changes nothing HERE. It is load-bearing in the case this suite cannot
#              drive — a DM file landing BETWEEN the purge and the check, which needs a concurrent
#              writer — and that is exactly why the engine's own post-add re-purge is deliberately
#              non-fatal (`|| true`, `bin/brain:858`): the check is what stands if that purge
#              silently fails. The seam map keeps it for that reason and requires it to
#              distinguish additions (refuse) from deletions (proceed).
#   BASELINE   green today.
sc_ur4a_staged_dm_addition_never_in_tree() {
  fx=$(make_vault) || fatal "fixture build failed"
  body="URCOMMITBODYPROBE-3a"

  plant_dm "$fx" bravo "$body" || { fail "fixture: could not plant DM state"; return 0; }
  mark_vault "$fx" "baseline"
  # force-stage the DM message: `-f` is required precisely because a healthy vault ignores it
  git -C "$fx" add -f -- ".brain/dm/bravo/pending/20260101T000000Z-1.a0" >/dev/null 2>&1 \
    || { fail "fixture: could not force-stage the DM message"; return 0; }
  git -C "$fx" diff --cached --name-only -- .brain/dm 2>/dev/null | grep -q . \
    || { fail "fixture control: the DM addition is not actually staged — the guard would be vacuous"; return 0; }

  before=$(head_sha "$fx")
  run_brain "$fx" commit
  rc=$?

  need_tree_lacks_dm "$fx" "DM paths in the tree at HEAD after a staged DM addition"
  need_tree_lacks_text "$fx" "$body" "DM body in the tree at HEAD after a staged DM addition"
  if [ "$rc" = "0" ]; then
    need_head_file_has "$fx" "$MARKER_PATH" "vault marker baseline" "the real vault change (commit reported success)"
  else
    need_eq "$(head_sha "$fx")" "$before" "HEAD after a REFUSED commit"
    [ -s "$ERR" ] || fail "the commit refused but said nothing on stderr"
  fi
}

# UR4a/4 — guard. A vault with no DM state at all still commits.
#   AUTHORITY  `cmd_commit`'s contract (usage: "durability: path-scoped, locked, secret-scanned,
#              ff-only"); the DM guard is gated on `[ -d "$BRAIN/dm" ]` and must stay a no-op
#              when there is nothing to guard.
#   PROVES     the ordinary path is unbroken — so UR4a/1's and UR4b/5's failures cannot be
#              explained away as "commit is just broken in this fixture".
#   DOES NOT   assert anything about the rebase/fetch tail (no origin exists in a fixture; the
#              engine warns and continues by design).
#   BASELINE   green today.
sc_ur4a_plain_vault_commit_still_works() {
  fx=$(make_vault) || fatal "fixture build failed"
  rm -rf "$fx/.brain/dm" || { fail "fixture: could not remove the empty dm/ tree"; return 0; }
  git_commit_all "$fx" "vault baseline" || { fail "fixture: baseline commit failed"; return 0; }

  mark_vault "$fx" "plain-change"
  run_brain "$fx" commit
  rc=$?

  need_rc "$rc" 0 "brain commit on a vault with no DM state"
  need_head_file_has "$fx" "$MARKER_PATH" "vault marker plain-change" "the real vault change"
}

# ═══════════════════ UR-4b — the ignore check is a string match, not a decision ════════════

# UR4b/5 — a `.gitignore` whose literal `dm/` line is present but EFFECTIVELY OVERRIDDEN.
#   AUTHORITY  ultrareview UR-4b: "Checking for a literal `dm/` line does not establish effective
#              Git ignore behavior; later negations can re-include the directory"; Fix: "Verify
#              effective ignore behavior with `git check-ignore --no-index`"; seam map: "replace
#              the `grep -qxF 'dm/'` ignore check with `git check-ignore --no-index`".
#   FIXTURE    `dm/` followed by a negation, PARAMETRIZED over three spellings: `!dm/`, `!/dm/`
#              and `!dm`. Not `!dm/keep.md` — measured in a scratch repo, a negation of a path
#              INSIDE an excluded directory does not re-include it (git never descends into an
#              excluded directory), so that shape would make the scenario vacuous. All three
#              spellings used here were measured to (i) re-include, (ii) still satisfy the literal
#              `grep -qxF 'dm/'`, and (iii) heal when a fresh `dm/` is appended (last match wins)
#              — so every case is both discriminating AND satisfiable.
#   WHY THREE   the audit demonstrated that a fixed-string grep special-casing ONE spelling
#              (`grep 'dm/' && ! grep '!dm/'`) scores full marks against a single-spelling
#              scenario. The negation spelling is the only discriminating axis available, so
#              covering all three raises any non-`check-ignore` implementation to "reimplement
#              gitignore matching" — which is the point of the finding. Authority: seam map
#              UR-4b audit note, 2026-08-04.
#   CONTROLS   per spelling, before the run: `grep -qxF 'dm/'` must succeed (so a string-matching
#              implementation genuinely believes the invariant holds), git's real decision must be
#              NOT-ignored (so the override genuinely bit), and the DM paths must be untracked (so
#              this cannot silently become a second UR-4a wedge test). Without all three, a case
#              could pass for the wrong reason.
#   PROVES     the engine either repairs the effective ignore state or refuses — it may not
#              silently certify a false one. Both shapes are accepted because authority mandates
#              the CHECK, not the remedy.
#   DOES NOT   pin the remedy, the warning text, or where a healed rule is written; and it does
#              not enumerate every conceivable re-include (a `.gitignore` in a parent directory,
#              `core.excludesFile`, `.git/info/exclude`) — three in-file spellings is the axis the
#              seam map names.
sc_ur4b_literal_rule_but_effectively_overridden() {
  msg=".brain/dm/bravo/pending/20260101T000000Z-1.a0"
  for neg in '!dm/' '!/dm/' '!dm'; do
    fx=$(make_vault) || fatal "fixture build failed"
    body="URCOMMITBODYPROBE-5b"

    plant_dm "$fx" bravo "$body" || { fail "[$neg] fixture: could not plant DM state"; continue; }
    mark_vault "$fx" "baseline"
    # ORDER MATTERS: the baseline is committed while the ignore rule is still EFFECTIVE, so the DM
    # files stay untracked; only then is the override written. Committing the baseline after the
    # override would track the DM bodies and turn this case into a second UR-4a wedge test
    # (observed, and the reason for this ordering).
    git_commit_all "$fx" "vault baseline" || { fail "[$neg] fixture: baseline commit failed"; continue; }
    printf 'dm/\n%s\n' "$neg" > "$fx/.brain/.gitignore" \
      || { fail "[$neg] fixture: could not write .gitignore"; continue; }
    git_commit_path "$fx" "override the dm ignore rule" ".brain/.gitignore" \
      || { fail "[$neg] fixture: could not commit the overridden .gitignore"; continue; }
    need_empty "$(tracked_dm "$fx")" "[$neg] fixture control: DM paths must be UNTRACKED here (this scenario is about the ignore CHECK, not the tracked-inbox wedge)" || continue

    grep -qxF 'dm/' "$fx/.brain/.gitignore" 2>/dev/null \
      || { fail "[$neg] fixture control: the literal 'dm/' line is absent — a string-matching engine would already refuse, so this case would not discriminate"; continue; }
    need_not_ignored "$fx" "$msg" "[$neg] fixture control: git's real ignore decision before the run" || continue

    before=$(head_sha "$fx")
    mark_vault "$fx" "change-one"
    run_brain "$fx" commit
    rc=$?

    if [ "$rc" = "0" ]; then
      need_ignored "$fx" "$msg" "[$neg] the DM path AFTER a commit that reported success"
      need_head_file_has "$fx" "$MARKER_PATH" "vault marker change-one" "[$neg] the real vault change"
    else
      need_eq "$(head_sha "$fx")" "$before" "[$neg] HEAD after a REFUSED commit"
      [ -s "$ERR" ] || fail "[$neg] the commit refused but said nothing on stderr"
    fi
    need_tree_lacks_dm "$fx" "[$neg] DM paths in the tree at HEAD"
    need_tree_lacks_text "$fx" "$body" "[$neg] DM body in the tree at HEAD"
  done
}

# UR4b/6 — guard. A HEALTHY ignore state is left alone.
#   AUTHORITY  the same fix, read for what it must NOT do: the check gates a self-heal, so a
#              check that mis-fires would rewrite `.brain/.gitignore` on every commit.
#   PROVES     with a fresh init (where `dm/` is present AND effective), a commit leaves
#              `.brain/.gitignore` byte-identical.
#   REJECTS    a repair that unconditionally appends `dm/`, or one whose new check is inverted.
#   DOES NOT   assert the file's contents beyond "unchanged", and says nothing about vaults
#              whose rule lives somewhere other than `.brain/.gitignore`.
#   BASELINE   green today.
sc_ur4b_healthy_ignore_not_rewritten() {
  fx=$(make_vault) || fatal "fixture build failed"
  plant_dm "$fx" bravo "URCOMMITBODYPROBE-6b" || { fail "fixture: could not plant DM state"; return 0; }
  git_commit_all "$fx" "vault baseline" || { fail "fixture: baseline commit failed"; return 0; }

  need_ignored "$fx" ".brain/dm/bravo/pending/20260101T000000Z-1.a0" "fixture control: a fresh init's ignore state" || return 0
  cp "$fx/.brain/.gitignore" "$(dirname "$fx")/gitignore.before" \
    || { fail "fixture: could not snapshot .gitignore"; return 0; }

  mark_vault "$fx" "healthy"
  run_brain "$fx" commit
  rc=$?

  need_rc "$rc" 0 "brain commit on a healthy vault"
  need_same_bytes "$fx/.brain/.gitignore" "$(dirname "$fx")/gitignore.before" \
    ".brain/.gitignore after a commit that needed no repair"
}

# ═══════════════════════ UR-7 — install can report success over a failure ═════════════════

# UR7/7 — an injected mkdir/copy failure must make `brain install` fail LOUDLY.
#   AUTHORITY  ultrareview UR-7: "`cmd_install` does not check `mkdir` or `cp` … It can continue
#              through settings installation, print success, and exit zero while leaving the old
#              or truncated navigation protocol"; seam map: "check every `mkdir`/`cp`".
#   INSTRUMENT the skills PARENT directory is made 0500, so creating the
#              `navigation-standards/` subdirectory fails. `make_readonly_dir` carries its own
#              positive control (a create inside really fails here) so a root-run cannot pass as
#              a success. The mode is restored before any assertion or early return.
#   PROVES     non-zero exit, a diagnosis on some stream, and no installed skill.
#   DOES NOT   pin the error wording OR the stream it goes to. "Did not report success" rests on
#              the non-zero exit plus the absent destination, not on scanning stdout for a path:
#              a GREEN that prints failures to stdout names the same path in a failure sentence,
#              and rejecting that would be stricter than any authority.
#   MEASURED   today: exit 0 with "brain: installed nav skill → …" on stdout while mkdir and cp
#              both failed and SKILL.md does not exist. That is the finding, live.
sc_ur7_failed_copy_must_not_report_success() {
  fx=$(make_vault) || fatal "fixture build failed"
  skills=$(skills_dir_of "$fx")
  dest=$(skill_dest_of "$fx")

  make_readonly_dir "$skills"
  mrc=$?
  [ "$mrc" = "0" ] || { readonly_failed "$mrc" "the skills parent directory"; chmod 755 "$skills" 2>/dev/null; return 0; }

  run_brain "$fx" install
  rc=$?
  chmod 755 "$skills" 2>/dev/null || true

  need_rc_nonzero "$rc" "brain install when the skills directory cannot be created"
  need_not_silent "brain install when the skills directory cannot be created"
  need_file_absent "$dest" "the skill destination after a failed install"
}

# UR7/8 — a FAILED install must leave the PREVIOUS skill intact, never a partial one.
#   AUTHORITY  ultrareview UR-7 Fix: "copy to a same-directory temporary file, validate or compare
#              it, and atomically rename it over `SKILL.md`. Test injected copy failure and
#              replacement of an existing installed skill"; seam map §"UR fixes riding along":
#              "route the skill copy through `_atomic_place`", whose contract is "write to
#              `<dest-dir>/.tmp-$$-<n>`, then `mv -- tmp dest`; non-zero + temp cleanup on any
#              failure".
#   INSTRUMENT the destination DIRECTORY is made 0500 with an older SKILL.md already inside.
#              This is the discriminating fixture: POSIX permits writing an EXISTING file in a
#              non-writable directory, so a bare `cp` succeeds and truncates-then-rewrites in
#              place, while a same-directory temp cannot be created at all and the placement
#              fails cleanly. Measured today: exit 0, success printed, and the old skill
#              destroyed in place.
#   PROVES     non-zero exit, a diagnosis on some stream, and the destination still byte-identical
#              to the PREVIOUS skill — the strongest observable form of "the reader never sees a
#              partial or truncated protocol". Stream-agnostic for the same reason as UR7/7.
#   DOES NOT   prove the absence of a truncation window under concurrency (not observable without
#              a race); and it is deliberately strict about one thing — an implementation that
#              keeps overwriting in place will fail here even though it "worked", because
#              in-place overwrite is exactly the non-atomic shape the finding rejects.
sc_ur7_failed_install_preserves_previous_skill() {
  fx=$(make_vault) || fatal "fixture build failed"
  dir=$(skill_dir_of "$fx")
  dest=$(skill_dest_of "$fx")
  prev="$(dirname "$fx")/previous-skill.md"

  mkdir -p "$dir" || { fail "fixture: could not create the skill directory"; return 0; }
  printf -- '---\nname: previous-navigation-standards\n---\nPREVIOUS SKILL CONTENT — must survive a failed install.\n' > "$dest" \
    || { fail "fixture: could not seed a previously installed skill"; return 0; }
  cp "$dest" "$prev" || { fail "fixture: could not snapshot the previous skill"; return 0; }
  need_differs "$prev" "$(skill_src_of "$fx")" "fixture control: the seeded skill must differ from the template" || {
    return 0
  }

  make_readonly_dir "$dir"
  mrc=$?
  [ "$mrc" = "0" ] || { readonly_failed "$mrc" "the skill destination directory"; chmod 755 "$dir" 2>/dev/null; return 0; }

  run_brain "$fx" install
  rc=$?
  chmod 755 "$dir" 2>/dev/null || true

  need_rc_nonzero "$rc" "brain install when the skill cannot be placed atomically"
  need_not_silent "brain install when the skill cannot be placed atomically"
  need_same_bytes "$dest" "$prev" "the installed skill after a FAILED install (previous content must survive)"
  need_no_dotfiles "$dir" "the skill directory after a failed install"
}

# UR7/9 — STRUCTURAL WITNESS: the skill is placed by a rename FROM THE SAME DIRECTORY.
#   AUTHORITY  seam map §"New seams" `_atomic_place` ("write to `<dest-dir>/.tmp-$$-<n>`, then
#              `mv -- tmp dest`", consumers include `cmd_install`) and §"Defects found during this
#              pass" item 3: `cmd_install` "mktemp into `$TMPDIR` and `mv` into `$HOME` — a
#              CROSS-DEVICE rename, which degrades to copy+unlink and is therefore NOT atomic.
#              UR-7 asks for an atomic install; naïvely 'checking the return value' would not have
#              fixed this. The temp file must be created in the destination directory."
#   CLAIM      the destination's last writer is `mv`, and that `mv`'s source directory is the
#              destination's own directory.
#   TARGET     the engine's own exec of `mv`/`cp`, recorded by a PATH shim that logs the last two
#              arguments and then execs the genuine tool. Provenance: `_atomic_place` uses
#              `command mv`, which bypasses functions and aliases but still resolves through
#              PATH — verified live, the shim records `mv -f -- <pending>/.tmp-<pid> <pending>/<id>`
#              during a `brain dm` send. The scenario asserts the log is non-empty after the run,
#              so a shim that failed to engage reports itself instead of passing.
#   NEGATIVE   two named bypasses are executed through the shim against a throwaway destination
#   CONTROLS   and the verdict function must reject BOTH: a bare `cp` onto the destination
#              (verdict `tool:cp`) and the cross-device shape — `mktemp` in $TMPDIR, then `mv`
#              into the destination directory (verdict `crossdir`). No implementation file is
#              touched to build them.
#   POSITIVE   a permitted alternative is executed too: a temp with a DIFFERENT name from
#   CONTROL    `_atomic_place`'s (`.some-other-temp`) in the destination directory, renamed into
#              place — verdict `ok`. The witness is therefore name-agnostic; it constrains the
#              rename's source DIRECTORY, never the temp's spelling.
#   DOES NOT   cover an implementation that renames by some mechanism other than `mv(1)` — POSIX
#              sh has no rename builtin and the seam contract names `mv`, but a perl/python
#              placement would be falsely rejected. Declared, non-blocking.
sc_ur7_skill_placed_by_same_dir_rename() {
  fx=$(make_vault) || fatal "fixture build failed"
  base=$(dirname "$fx")
  dest=$(skill_dest_of "$fx")
  src=$(skill_src_of "$fx")

  make_shim "$base" || { fail "fixture: could not build the call-recording shim"; return 0; }

  # ── instrument controls, all against a throwaway destination in the scratch root ──
  ctl="$base/ctl"; mkdir -p "$ctl" || { fail "fixture: could not create the control directory"; return 0; }
  # positive control: same-directory temp under a name this suite invented, then rename.
  # The controls call the shims by absolute path — their job is to exercise the VERDICT
  # function in both directions, not PATH resolution (which the engine run proves separately).
  "$SHIM_DIR/cp" "$src" "$ctl/.some-other-temp" >/dev/null 2>&1 \
    && "$SHIM_DIR/mv" "$ctl/.some-other-temp" "$ctl/POSITIVE.md" >/dev/null 2>&1 \
    || { fail "instrument: the positive-control placement itself failed"; return 0; }
  need_verdict "$(rename_verdict "$SHIM_LOG" "$ctl/POSITIVE.md")" "ok" \
    "positive control (a differently-named same-directory temp must be ACCEPTED)"
  # negative control 1: a bare copy over the destination
  "$SHIM_DIR/cp" "$src" "$ctl/NEG-CP.md" >/dev/null 2>&1 \
    || { fail "instrument: the bare-copy control itself failed"; return 0; }
  need_verdict "$(rename_verdict "$SHIM_LOG" "$ctl/NEG-CP.md")" "tool:cp" \
    "negative control (a bare cp onto the destination must be REJECTED)"
  # negative control 2: the cross-device shape — temp in $TMPDIR, renamed into the destination
  xdev=$(mktemp "$SUITE_TMP/xdev.XXXXXX") || { fail "instrument: mktemp for the cross-dir control failed"; return 0; }
  "$SHIM_DIR/cp" "$src" "$xdev" >/dev/null 2>&1 \
    && "$SHIM_DIR/mv" "$xdev" "$ctl/NEG-XDEV.md" >/dev/null 2>&1 \
    || { fail "instrument: the cross-directory control itself failed"; return 0; }
  need_verdict "$(rename_verdict "$SHIM_LOG" "$ctl/NEG-XDEV.md")" "crossdir" \
    "negative control (a temp from another directory must be REJECTED)"

  # ── the engine itself ──
  : > "$SHIM_LOG"
  run_brain "$fx" install
  rc=$?

  need_rc "$rc" 0 "brain install into a writable fixture HOME"
  [ -s "$SHIM_LOG" ] || { fail "instrument blind: the engine execed no mv/cp through the shim — PATH interception did not engage, so nothing about placement was actually observed"; return 0; }

  verdict=$(rename_verdict "$SHIM_LOG" "$dest")
  case "$verdict" in
    ok) ;;
    none)     fail "the skill destination was never written by mv or cp — placement could not be observed at all (dest: $dest)" ;;
    tool:cp)  fail "the skill was placed by a bare 'cp' onto $dest (source: $(rename_src "$SHIM_LOG" "$dest")) — an in-place copy truncates the live skill before rewriting it; the seam requires a same-directory temp plus 'mv -- tmp dest'" ;;
    crossdir) fail "the skill was renamed in from $(rename_src "$SHIM_LOG" "$dest"), which is NOT the destination directory — a cross-directory rename degrades to copy+unlink across devices and is not atomic (seam map, Stage-2 defect 3)" ;;
    *)        fail "unrecognised instrument verdict '$verdict'" ;;
  esac
  need_same_bytes "$dest" "$src" "the installed skill after a successful install"
}

# UR7/10 — the same structural claim for the GLOBAL SETTINGS write.
#   AUTHORITY  seam map §"New seams" `_atomic_place`: "consumers: … `cmd_install` +
#              `_write_project_settings` (UR-7 — temp must move into the DESTINATION dir, fixing
#              the cross-device non-atomicity found in Stage 2)".
#   ⚠ CORRECTION (2026-08-04, audit ruling — this comment previously said the OPPOSITE and it was
#     wrong). This is the BEST-attested instance of the cross-device defect in the file, not the
#     weakest. Seam-map Stage-2 defect 3 says "`cmd_install` and `_write_project_settings`
#     `mktemp` into `$TMPDIR` and `mv` into `$HOME`" — and inside `cmd_install` the only
#     `mktemp`→`mv` pair IS this settings write (`bin/brain:1139` → `:1151`). The skill path has
#     no `mktemp` and no `mv` at all, so defect 3's literal description maps onto THIS scenario
#     and reaches UR7/9 only by the `_atomic_place` consumer mandate. The earlier note invited a
#     reader to drop the strongest scenario in the pair; it is retracted, not softened.
#   MEASURED   today the shim records `mv /var/folders/…/tmp.XXXX <fixture-home>/.claude/settings.json`
#              — the exact cross-device shape the seam map calls out.
#   DOES NOT   assert anything about the merged JSON's contents (UR7/11 guards the failure path;
#              the merge semantics are not part of any finding here).
sc_ur7_settings_placed_by_same_dir_rename() {
  fx=$(make_vault) || fatal "fixture build failed"
  base=$(dirname "$fx")
  gs=$(settings_of "$fx")

  make_shim "$base" || { fail "fixture: could not build the call-recording shim"; return 0; }
  : > "$SHIM_LOG"
  run_brain "$fx" install
  rc=$?

  need_rc "$rc" 0 "brain install into a writable fixture HOME"
  [ -s "$SHIM_LOG" ] || { fail "instrument blind: the engine execed no mv/cp through the shim"; return 0; }

  verdict=$(rename_verdict "$SHIM_LOG" "$gs")
  case "$verdict" in
    ok) ;;
    none)     fail "the global settings file was never written by mv or cp (dest: $gs)" ;;
    tool:cp)  fail "the global settings file was placed by 'cp', not by a rename" ;;
    crossdir) fail "the global settings file was renamed in from $(rename_src "$SHIM_LOG" "$gs") — a different directory. Cross-device rename is not atomic; the temp must be created in the destination directory (seam map, _atomic_place consumers + Stage-2 defect 3)" ;;
    *)        fail "unrecognised instrument verdict '$verdict'" ;;
  esac
}

# UR7/11 — guard. A settings merge that cannot complete fails closed.
#   AUTHORITY  ultrareview UR-7 ("It can CONTINUE through settings installation, print success,
#              and exit zero") read as its converse: the settings failure path must not report
#              success either, and must not destroy the file it could not merge.
#   INSTRUMENT invalid JSON in the global settings file — root-proof (no permission games) and
#              deterministic: jq fails, so the merge cannot produce output.
#   PROVES     non-zero exit, no success claim naming the settings path on stdout, and the
#              pre-existing settings file left byte-identical.
#   DOES NOT   assert the skill line's absence: if the skill was genuinely installed before the
#              settings step failed, saying so is honest, and forbidding it would reject a
#              permitted implementation.
#   BASELINE   green today (jq fails → `_die "failed to merge global settings"`, exit 1).
sc_ur7_settings_merge_failure_fails_closed() {
  fx=$(make_vault) || fatal "fixture build failed"
  gs=$(settings_of "$fx")
  before="$(dirname "$fx")/settings.before"

  printf 'this is not json at all\n' > "$gs" || { fail "fixture: could not seed invalid settings"; return 0; }
  cp "$gs" "$before" || { fail "fixture: could not snapshot settings"; return 0; }

  run_brain "$fx" install
  rc=$?

  need_rc_nonzero "$rc" "brain install with unparseable global settings"
  need_file_lacks "$OUT" "$gs" "stdout after a failed settings merge"
  need_same_bytes "$gs" "$before" "the global settings file after a failed merge"
}

# UR7/13 — guard, and honestly an OUTCOME ANCHOR rather than a discriminator.
#   ⚠ SCOPE, corrected 2026-08-04 (round 2). This scenario was written to pin "check every
#     `mkdir`", and it does NOT: the audit's n2 mutant — the settings-`mkdir` check removed, the
#     very fault this was aimed at — PASSES it, because the failure is caught one step downstream
#     by the settings seed. No CLI-observable difference exists between "checked the mkdir" and
#     "failed at the next statement", so no discriminating limb is available and none is claimed.
#     What it does buy: it makes the settings-side failure path REACHABLE at all (every other
#     scenario drives failure through the skills directory, and the fixture always pre-created the
#     settings parent), and it anchors the outcome — a settings directory that cannot be created
#     must not produce a success report. Mutant m4 (settings abort downgraded) does flip it, so it
#     is not inert; it simply does not pin what its name suggests.
#   AUTHORITY  seam map §"UR fixes riding along" → UR-7: "check every `mkdir`/`cp`". `cmd_install`
#              runs two: `mkdir -p "$_skills"` and `mkdir -p "$(dirname "$_gs")"`. This scenario
#              reaches the second one; see the scope correction above for what that does and does
#              not establish.
#   INSTRUMENT `OVERRIDE_GLOBAL_SETTINGS` redirects the settings file under a 0500 directory, so
#              its parent cannot be created, while the skills destination stays fully writable —
#              the two install paths are independent for the first time. Both overridden paths are
#              still validated by `assert_install_env` in `run_brain`; a redirection cannot escape
#              the scratch root. `make_readonly_dir` carries the root-run positive control, and
#              the mode is restored before any assertion or early return.
#   PROVES     non-zero exit, a diagnosis on some stream, and no settings file conjured anywhere.
#   DOES NOT   pin WHICH check catches it — that is the scope correction above. Today nothing
#              checks the `mkdir` and the run still fails closed downstream (the `printf '{}'`
#              seed fails, jq then has no input); under a GREEN that checks the `mkdir` it fails
#              earlier and more precisely. Both satisfy this scenario and no authority prefers
#              one.
#   BASELINE   green today.
sc_ur7_settings_dir_uncreatable_fails_closed() {
  fx=$(make_vault) || fatal "fixture build failed"
  base=$(dirname "$fx")
  blocked="$base/blocked-settings-root"

  make_readonly_dir "$blocked"
  mrc=$?
  [ "$mrc" = "0" ] || { readonly_failed "$mrc" "the blocked settings root"; chmod 755 "$blocked" 2>/dev/null; return 0; }

  OVERRIDE_GLOBAL_SETTINGS="$blocked/nested/settings.json"
  run_brain "$fx" install
  rc=$?
  chmod 755 "$blocked" 2>/dev/null || true

  need_rc_nonzero "$rc" "brain install when the settings directory cannot be created"
  need_not_silent "brain install when the settings directory cannot be created"
  need_file_absent "$blocked/nested/settings.json" "the global settings file after an uncreatable settings directory"
  # The skills side was healthy throughout, so this cannot pass merely because everything failed.
  # Probed on the skills PARENT rather than on the skills dir itself: whether the engine created
  # the latter depends on the order it does its two jobs in, which no authority fixes.
  need_writable_dir "$base/home/.claude" "fixture control: the skills side of the install"
}

# UR7/12 — guard. A clean install replaces an EXISTING skill and leaves no residue.
#   AUTHORITY  ultrareview UR-7 Fix: "Test … replacement of an existing installed skill";
#              `_atomic_place` contract: temp cleanup on every path.
#   PROVES     exit 0, the destination byte-identical to the template, and no dot-temp residue in
#              the destination directory — the positive control for UR7/7 and UR7/8, so their
#              expected failures cannot be satisfied by an install that never works.
#   DOES NOT   freeze the stdout wording. It requires only that a successful install SAYS so —
#              satisfied by naming the destination path (today's shape, and the identification
#              UR7/7 uses in the negative) or by any sentence mentioning the skill. Nothing in
#              authority mandates printing the path, so requiring it would reject a permitted
#              rewording.
#   BASELINE   green today.
sc_ur7_clean_install_replaces_and_leaves_no_residue() {
  fx=$(make_vault) || fatal "fixture build failed"
  dir=$(skill_dir_of "$fx")
  dest=$(skill_dest_of "$fx")
  src=$(skill_src_of "$fx")

  mkdir -p "$dir" || { fail "fixture: could not create the skill directory"; return 0; }
  printf 'STALE SKILL CONTENT that must be replaced.\n' > "$dest" \
    || { fail "fixture: could not seed an existing skill"; return 0; }

  run_brain "$fx" install
  rc=$?

  need_rc "$rc" 0 "brain install over an existing skill"
  grep -qF -- "$dest" "$OUT" 2>/dev/null || grep -qi 'skill' "$OUT" 2>/dev/null \
    || fail "stdout after a successful install: neither the destination path nor any mention of the skill — a successful install must report itself"
  need_same_bytes "$dest" "$src" "the installed skill after replacing an existing one"
  need_no_dotfiles "$dir" "the skill directory after a successful install"
}

# ═════════════════════════════════════ run ═══════════════════════════════════════════════
printf 'brain commit/install RED suite — UR-4a, UR-4b, UR-7\n'
printf '  engine : %s\n' "$BRAIN_BIN"
printf '  scratch: %s\n\n' "$SUITE_TMP"

scenario red   "UR4a/1  legacy-tracked-inbox-commits-clean"   sc_ur4a_legacy_tracked_inbox_commits_clean
scenario guard "UR4a/1b commit-stays-path-scoped"             sc_ur4a_commit_stays_path_scoped
scenario guard "UR4a/1c commit-survives-next-git-command"     sc_ur4a_commit_survives_the_next_git_command
scenario red   "UR4a/2  repeat-commit-after-cleanup"          sc_ur4a_repeat_commit_after_cleanup
scenario guard "UR4a/3  staged-dm-addition-never-in-tree"     sc_ur4a_staged_dm_addition_never_in_tree
scenario guard "UR4a/4  plain-vault-commit-still-works"       sc_ur4a_plain_vault_commit_still_works

scenario red   "UR4b/5  literal-rule-but-effectively-overridden" sc_ur4b_literal_rule_but_effectively_overridden
scenario guard "UR4b/6  healthy-ignore-not-rewritten"         sc_ur4b_healthy_ignore_not_rewritten

scenario red   "UR7/7   failed-copy-must-not-report-success"  sc_ur7_failed_copy_must_not_report_success
scenario red   "UR7/8   failed-install-preserves-prev-skill"  sc_ur7_failed_install_preserves_previous_skill
scenario red   "UR7/9   skill-placed-by-same-dir-rename"      sc_ur7_skill_placed_by_same_dir_rename
scenario red   "UR7/10  settings-placed-by-same-dir-rename"   sc_ur7_settings_placed_by_same_dir_rename
scenario guard "UR7/11  settings-merge-failure-fails-closed"  sc_ur7_settings_merge_failure_fails_closed
scenario guard "UR7/13  settings-dir-uncreatable-fails-closed" sc_ur7_settings_dir_uncreatable_fails_closed
scenario guard "UR7/12  clean-install-replaces-no-residue"    sc_ur7_clean_install_replaces_and_leaves_no_residue

NON_GUARD_FAILED=$((FAILED - GUARD_FAILED))
printf '\n── summary ──\n'
printf 'scenarios: %s   passed: %s   failed: %s\n' "$TOTAL" "$PASSED" "$FAILED"
printf 'non-guard failures: %s   guard failures: %s\n' "$NON_GUARD_FAILED" "$GUARD_FAILED"

# A guard regression means a behaviour that WORKS TODAY was broken — during the GREEN loop that
# is categorically different from "a RED scenario is still red", so it gets its own exit code.
[ "$GUARD_FAILED" -eq 0 ] || exit 3
[ "$FAILED" -eq 0 ] || exit 1
exit 0
