#!/bin/sh
# Mutation probe for the DM queue review fixes.
#
# Every mutant breaks one load-bearing production line and declares the scenario IDs that must
# fail. A result counts only when the suite reaches its complete summary and exits with an
# expected failing-suite status; an early death can never masquerade as a clean baseline or kill.
set -u
cd "$(dirname "$0")/.." || exit 1

EXPECTED_SCENARIOS=$(grep -c '^scenario ' test/dm.sh 2>/dev/null)
case "$EXPECTED_SCENARIOS" in ''|*[!0-9]*|0) echo "ABORT: could not count dm scenarios"; exit 1 ;; esac

PROBE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/brain-mutation-probe.XXXXXX") || exit 1
ENGINE_BACKUP="$PROBE_TMP/brain.original"
cp -p bin/brain "$ENGINE_BACKUP" || exit 1

cleanup() {
  [ -f "$ENGINE_BACKUP" ] && cp -p "$ENGINE_BACKUP" bin/brain 2>/dev/null || true
  case "$PROBE_TMP" in */brain-mutation-probe.*) rm -rf "$PROBE_TMP" ;; esac
}
trap 'cleanup' 0
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

restore_engine() { cp -p "$ENGINE_BACKUP" bin/brain; }
norm() { printf '%s\n' "$1" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '; }

# run_suite [command] — status and failures are globals because command substitution would hide
# them in a subshell. Return 0 means COMPLETE, not green; RUN_EXIT carries the suite's real status.
run_suite() {
  _suite=${1:-./test/dm.sh}; _suite_out="$PROBE_TMP/suite.out"
  RUN_EXIT=0; RUN_FAILURES=""; RUN_FAILED=""; RUN_TOTAL=""
  if "$_suite" >"$_suite_out" 2>&1; then RUN_EXIT=0; else RUN_EXIT=$?; fi
  RUN_FAILURES=$(grep '^FAIL' "$_suite_out" 2>/dev/null \
    | sed 's/^FAIL  *//;s/ .*//' | tr '\n' ' ')

  [ "$(grep -c '^scenarios:' "$_suite_out" 2>/dev/null)" = 1 ] || return 2
  [ "$(grep -c '^non-guard failures:' "$_suite_out" 2>/dev/null)" = 1 ] || return 2
  _summary=$(grep '^scenarios:' "$_suite_out")
  # Expected shape: scenarios: N passed: P failed: F
  # shellcheck disable=SC2086
  set -- $_summary
  [ "$#" = 6 ] && [ "$1" = "scenarios:" ] && [ "$3" = "passed:" ] && [ "$5" = "failed:" ] \
    || return 2
  RUN_TOTAL=$2; _run_passed=$4; RUN_FAILED=$6
  case "$RUN_TOTAL:$_run_passed:$RUN_FAILED" in *[!0-9:]*) return 2 ;; esac
  [ "$RUN_TOTAL" = "$EXPECTED_SCENARIOS" ] || return 2
  [ "$((_run_passed + RUN_FAILED))" = "$EXPECTED_SCENARIOS" ] || return 2
  # One FAIL header per reported failed scenario.
  # shellcheck disable=SC2086
  set -- $RUN_FAILURES
  [ "$#" = "$RUN_FAILED" ] || return 2
  return 0
}

baseline_ok() {
  run_suite "$1" || return 1
  [ "$RUN_EXIT" = 0 ] && [ "$RUN_FAILED" = 0 ] && [ -z "$RUN_FAILURES" ]
}

rc=0
instrument_selfcheck() {
  _early="$PROBE_TMP/early-exit.sh"; _false_clean="$PROBE_TMP/false-clean.sh"
  {
    printf '#!/bin/sh\n'
    printf 'printf "FAIL  D.P1/50 synthetic-early-kill\\n"\n'
    printf 'exit 2\n'
  } >"$_early"
  {
    printf '#!/bin/sh\n'
    printf 'printf "scenarios: %s   passed: %s   failed: 0\\n"\n' "$EXPECTED_SCENARIOS" "$EXPECTED_SCENARIOS"
    printf 'printf "non-guard failures: 0   guard failures: 0\\n"\n'
    printf 'exit 2\n'
  } >"$_false_clean"
  chmod +x "$_early" "$_false_clean" || return 1

  if run_suite "$_early"; then
    echo "instrument early-exit summary check: ACCEPTED incomplete suite ❌"; return 1
  fi
  echo "instrument early-exit summary check: rejected ✅"
  if baseline_ok "$_false_clean"; then
    echo "instrument baseline-status check: ACCEPTED exit 2 baseline ❌"; return 1
  fi
  echo "instrument baseline-status check: rejected ✅"
}

probe() { # <label> <declared-failing-ids> <sed-program>
  _label=$1; _declared=$2; _sed=$3
  restore_engine || { echo "$_label: RESTORE FAILED ❌"; rc=1; return; }
  sed -i '' "$_sed" bin/brain || { echo "$_label: SED FAILED ❌"; rc=1; return; }
  if cmp -s "$ENGINE_BACKUP" bin/brain; then
    echo "$_label: mutant did not apply (pattern drifted) ❌"; rc=1; return
  fi
  if ! sh -n bin/brain 2>/dev/null || ! dash -n bin/brain 2>/dev/null; then
    echo "$_label: mutant broke syntax — INVALID ❌"; restore_engine; rc=1; return
  fi
  if ! run_suite; then
    echo "$_label: suite did not complete its $EXPECTED_SCENARIOS-scenario summary ❌"
    restore_engine; rc=1; return
  fi
  _got=$RUN_FAILURES; _suite_exit=$RUN_EXIT
  restore_engine || { echo "$_label: RESTORE FAILED ❌"; rc=1; return; }

  case "$_suite_exit" in 1|3) ;; *)
    echo "$_label: suite exit $_suite_exit is not a completed failing-suite status ❌"; rc=1; return ;;
  esac
  if [ -z "$_got" ]; then
    echo "$_label: NO SCENARIO FAILED → the test does NOT pin this fix ❌"; rc=1
  elif [ "$(norm "$_got")" = "$(norm "$_declared")" ]; then
    echo "$_label: killed exactly [$_got] ✅"
  else
    echo "$_label: killed [$_got], declared [$_declared] → not evidence ⚠"; rc=1
  fi
}

echo "=== instrument self-check ==="
instrument_selfcheck || { echo "mutation instrument self-check failed ❌"; exit 1; }

echo "=== baseline (no mutation) ==="
if baseline_ok ./test/dm.sh; then
  echo "baseline complete and clean ($EXPECTED_SCENARIOS/$EXPECTED_SCENARIOS) ✅"
else
  echo "BASELINE INVALID: exit=$RUN_EXIT failures=$RUN_FAILURES ❌"; exit 1
fi

# Pre-PR H1–H5 fixes retained from the prior probe.
probe "M1 H1 space-path    " "F.H1/42" \
  's#cd "$_dg_dir" || exit 1#cd $_dg_dir || exit 1#'
probe "M2 H3 leading-zero  " "F.H3/46" \
  's|^  case "$_dc_value" in .*$|  case "$_dc_value" in ""\|*[!0-9]*) return 1 ;; esac|'
probe "M3 H4 ack-soft-path " "F.H4/48" \
  's|if \[ ! -e "$_ak_claim" \] && \[ ! -L "$_ak_claim" \]; then|if false; then|'
probe "M4 total-work-cap   " "F.H5/49 Q.D/31 U.H6/55" \
  's|^DM_TRANSITION_MAX=40$|DM_TRANSITION_MAX=100000|'
probe "M5 H2 multi-object  " "F.H2/43" \
  's#      length == 1#      length >= 1#'
probe "M6 H2 field-bound   " "F.H2/45" \
  's#            from: $message.from\[0:$limit\],#            from: $message.from,#'

# Final-ultrareview fixes.
probe "M7 deploy engine    " "D.P1/50" \
  's|\$BRAIN/bin/brain|.brain/bin/brain|g'
probe "M8 poison isolation " "U.H2/51" \
  's|^      _dt_rc=1$|      return 1|'
probe "M9 lease scheduler  " "U.H3/52" \
  's@^  _dm_arm_lease_sweep "$_feat" || true$@  : # mutant disables lease scheduler@'
probe "M10 collision guard " "U.H4/53" \
  's|^_dm_dest_occupied() {.*$|_dm_dest_occupied() { return 1; }|'
probe "M11 id byte reserve " "U.H5/54" \
  's|^DM_ID_MAX_BYTES=.*$|DM_ID_MAX_BYTES=255|'
probe "M12 utf8 byte caps  " "U.M1/56" \
  's|utf8bytelength|length|g'

echo "=== final tree check ==="
if cmp -s "$ENGINE_BACKUP" bin/brain; then
  echo "bin/brain restored byte-for-byte ✅"
else
  echo "DIRTY — RESTORE FAILED ❌"; rc=1
fi
exit "$rc"
