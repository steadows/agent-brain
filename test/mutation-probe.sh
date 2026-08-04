#!/bin/sh
# Mutation probe for the H1–H5 fix round (pre-PR review findings).
#
# WHY THIS EXISTS: a passing suite proves nothing about whether a test would CATCH the
# regression it claims to guard. Each mutant below breaks exactly one shipped fix and
# DECLARES which scenario(s) must die as a result. A mutant that kills nothing means the
# test is decorative; a mutant that kills more than it declared is over-broad and its
# result is not evidence. Both are reported as failures of the probe, not of the engine.
#
# Usage:  sh test/mutation-probe.sh          (from the repo root, clean bin/brain)
# Runtime: ~6 full suite runs. bin/brain is restored from git after every mutant.
#
# Recorded result 2026-08-04 @ 583235f — all six landed exactly as declared:
#   M1 → F.H1/42 · M2 → F.H3/46 · M3 → F.H4/48
#   M4 → F.H5/49 + Q.D/31 (declared: removing the claim cap lets a >40 batch reach the
#        digest, which then correctly refuses it — the cap is load-bearing for the
#        pre-existing bound too, so Q.D/31 dying is CORRECT, not over-broad)
#   M5 → F.H2/43 · M6 → F.H2/45
set -u
cd "$(dirname "$0")/.." || exit 1

git diff --quiet -- bin/brain || { echo "ABORT: bin/brain has uncommitted changes"; exit 1; }

run_suite() { ./test/dm.sh 2>/dev/null | grep '^FAIL' | sed 's/^FAIL  *//;s/ .*//' | tr '\n' ' '; }
norm() { printf '%s\n' $1 | sort | tr '\n' ' '; }

rc=0
probe() { # <label> <declared-failing-ids> <sed-expr>
  _label=$1; _declared=$2; _sed=$3
  sed -i '' "$_sed" bin/brain || { echo "$_label: SED FAILED ❌"; rc=1; return; }
  if git diff --quiet -- bin/brain; then
    echo "$_label: mutant did not apply (pattern drifted) ❌"; rc=1; return
  fi
  if ! sh -n bin/brain 2>/dev/null; then
    echo "$_label: mutant broke syntax — INVALID ❌"; git checkout -- bin/brain; rc=1; return
  fi
  _got=$(run_suite)
  git checkout -- bin/brain
  if [ -z "$_got" ]; then
    echo "$_label: NO SCENARIO FAILED → the test does NOT pin this fix ❌"; rc=1
  elif [ "$(norm "$_got")" = "$(norm "$_declared")" ]; then
    echo "$_label: killed exactly [$_got] ✅"
  else
    echo "$_label: killed [$_got], declared [$_declared] → not evidence ⚠"; rc=1
  fi
}

echo "=== baseline (no mutation) ==="
B=$(run_suite)
[ -z "$B" ] && echo "baseline clean ✅" || { echo "BASELINE DIRTY: $B ❌"; exit 1; }

# H1 — space-safety rests on names crossing the split and paths being rebuilt quoted.
# Unquoting the digest's cd reintroduces exactly the space-path failure class.
probe "M1 H1 space-path    " "F.H1/42" 's#cd "$_dg_dir" || exit 1#cd $_dg_dir || exit 1#'

# H3 — accept leading-zero decimals again (the fatal-arithmetic class that wedged boots).
probe "M2 H3 leading-zero  " "F.H3/46" 's|^  case "$_dc_value" in .*$|  case "$_dc_value" in ""\|*[!0-9]*) return 1 ;; esac|'

# H4 — disable the vanished-claim soft landing so _dm_dir_ok intercepts it again.
probe "M3 H4 ack-soft-path " "F.H4/48" 's|if \[ ! -e "$_ak_claim" \] && \[ ! -L "$_ak_claim" \]; then|if false; then|'

# H5 — remove the per-invocation claim bound.
probe "M4 H5 claim-cap     " "F.H5/49 Q.D/31" 's|^DM_CLAIM_MAX_MESSAGES=40$|DM_CLAIM_MAX_MESSAGES=100000|'

# H2 — allow more than one JSON object per message file.
probe "M5 H2 multi-object  " "F.H2/43" 's#      length == 1#      length >= 1#'

# H2 — stop bounding a non-content contract field.
probe "M6 H2 field-bound   " "F.H2/45" 's#            from: $message.from\[0:$limit\],#            from: $message.from,#'

echo "=== final tree check ==="
git diff --quiet -- bin/brain && echo "bin/brain restored ✅" || { echo "DIRTY — RESTORE FAILED ❌"; rc=1; }
exit "$rc"
