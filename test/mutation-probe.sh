#!/bin/sh
# Mutation probe for the DM v1.2.2 queue engine (including the v1.2.4 contract addendum).
#
# Every mutant breaks ONE load-bearing production mechanism and declares the scenario IDs that
# must fail. Four properties are load-bearing in the harness itself and are not negotiable:
#
#   1. ISOLATED ENGINE COPIES. A mutant is written to a scratch copy and the suite is pointed at
#      it with BRAIN_BIN. bin/brain is never edited — the suite spawns the engine many times per
#      scenario, so mutating the shared file races the suite's own fixture construction and
#      produces failures in unrelated scenarios (measured during the v1.1 round-2 fix).
#   2. INSTRUMENT SELF-CHECK. Before any mutant runs, the harness proves it cannot be fooled by
#      a truncated suite (an early death that prints one FAIL and exits) or by a false-clean
#      baseline (a complete-looking summary with a non-zero status). A result counts only when
#      the suite reaches its full summary AND the arithmetic in that summary is self-consistent.
#   3. ANCHOR MANIFEST. Every line this probe mutates is declared once, up front, and checked
#      whole-line-exact against the engine BEFORE any mutant runs. The engine has been rewritten
#      four times since this probe was first written (v1.2 GREEN, /simplify, v1.2.1, v1.2.2) and two
#      anchors had silently died — a probe that cannot apply its mutant is a gate that lies.
#      Per-mutant, the CHANGED-LINE COUNT is also declared, so an over-broad pattern that happens
#      to still match is caught as surely as one that matches nothing.
#   4. ADDRESS CARDINALITY. Every sed address below is declared with its intended engine match
#      count and checked with sed's own BRE semantics. The exact-line manifest proves the intended
#      replacement exists; this complementary check proves a broad address cannot reach it merely
#      because the intended occurrence happens to be first.
#
# A mutant that kills NOTHING proves the suite does not pin the mechanism. A mutant that kills
# MORE than it declared is not evidence either — it is a blunt instrument, and the run says so.
#
# WHAT WAS RETIRED: nothing claim-era survives to retire. The v1.2 ruling deleted claimed/,
# leases, the .a<k> attempt counter, the poison cap and the sweeper, and the probe was rewritten
# against v1.2 at that time; this pass re-anchors it to v1.2.2 and adds the new mechanisms.
# Every sed program below is SOURCE TEXT for the engine under mutation: `$field_max`, `$id`,
# `$_to`, `$@` and friends must survive into the mutant unexpanded, so single quotes are load
# bearing rather than a mistake. Silenced file-wide because the alternative is one directive per
# mutant, which would have to be maintained as mutants come and go.
# shellcheck disable=SC2016
set -u
cd "$(dirname "$0")/.." || exit 1

EXPECTED_SCENARIOS=$(grep -c '^scenario ' test/dm.sh 2>/dev/null)
case "$EXPECTED_SCENARIOS" in ''|*[!0-9]*|0) echo "ABORT: could not count dm scenarios"; exit 1 ;; esac
ENGINE_SOURCE="$(pwd -P)/bin/brain"

PROBE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/brain-mutation-probe.XXXXXX") || exit 1
ENGINE_BACKUP="$PROBE_TMP/brain.original"
MUTANT_ENGINE="$PROBE_TMP/brain.mutant"
cp -p bin/brain "$ENGINE_BACKUP" || exit 1

cleanup() {
  case "$PROBE_TMP" in */brain-mutation-probe.*) rm -rf "$PROBE_TMP" ;; esac
}
trap 'cleanup' 0
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Set membership over a space-separated list. Replaces the old sorted-string equality, which
# could only express "these exactly" — see probe()'s REQUIRED/PERMITTED note.
in_set() { # <id> <space-separated list>
  for _is in $2; do [ "$_is" = "$1" ] && return 0; done
  return 1
}

# run_suite [command] [engine] — status and failures are globals because command substitution
# would hide them in a subshell. Return 0 means COMPLETE, not green; RUN_EXIT carries the real
# status.
run_suite() {
  _suite=${1:-./test/dm.sh}; _engine=${2:-$ENGINE_SOURCE}; _suite_out="$PROBE_TMP/suite.out"
  RUN_EXIT=0; RUN_FAILURES=""; RUN_FAILED=""; RUN_TOTAL=""
  if BRAIN_BIN="$_engine" "$_suite" >"$_suite_out" 2>&1; then RUN_EXIT=0; else RUN_EXIT=$?; fi
  RUN_FAILURES=$(grep '^FAIL' "$_suite_out" 2>/dev/null \
    | sed 's/^FAIL  *//;s/^guard: //;s/ .*//' | tr '\n' ' ')

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
  run_suite "$1" "${2:-$ENGINE_SOURCE}" || return 1
  [ "$RUN_EXIT" = 0 ] && [ "$RUN_FAILED" = 0 ] && [ -z "$RUN_FAILURES" ]
}

rc=0
instrument_selfcheck() {
  _early="$PROBE_TMP/early-exit.sh"; _false_clean="$PROBE_TMP/false-clean.sh"
  {
    printf '#!/bin/sh\n'
    printf 'printf "FAIL  V.C/24 synthetic-early-kill\\n"\n'
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

# ── anchor manifest ──────────────────────────────────────────────────────────────────────
# Every line any mutant below rewrites, checked WHOLE-LINE-EXACT (grep -xF). Substring or BRE
# matching is not good enough here: `  _dm_id_ok "$_ni_id" || return 1` also occurs at a deeper
# indent, and BSD grep treats a mid-pattern `$` as an anchor, so a BRE check silently reports 0
# for lines that are really present. Both traps were hit while writing this file.
# Format: one anchor per line. The two `g`-flag mutants (utf8bytelength, $BRAIN/bin/brain) are
# multi-line by design; every matched line is listed here, so those selectors are bounded by
# their declared counts AND their exact line sets.
#
# ⚠ ONE ENTRY IS WRITTEN AGAINST THE POST-FIX ENGINE, DELIBERATELY: the `$_esc_payload` case
# line. The V.B batch-integrity fix replaces `_emit_session_ctx_pinned`'s single first-id check
# with a loop over every staged id, so the shipped line dies the moment GREEN lands and this
# manifest is the RED-phase co-change for it. Two consequences, both intended:
#   · BEFORE GREEN this manifest reports STALE for that line. That is the probe correctly saying
#     it is anchored to an engine that does not exist yet — not drift. (The probe cannot run
#     meaningfully during RED anyway: its baseline requires a green dm.sh, and V.B/103 + V.B/106
#     are red by design until the fix lands.)
#   · The entry is whole-line-exact, so it PRESCRIBES a spelling — the loop variable `_ep_name`
#     and the six-space body indent. That is a real constraint on GREEN and is called out in the
#     hand-off rather than hidden here. Its purpose is the same as the non-target entry below:
#     if the shape changes, fail loud and make a human re-check the probe. The complementary
#     sed address is deliberately looser (indent- and variable-agnostic), so a GREEN that spells
#     the loop differently trips ONLY this line and nothing silently mis-mutates.
#
# ONE ENTRY IS NOT A MUTATION TARGET: `set -- "$@" "$_pending_name"` is ruling 3(b)'s quoted
# positional accumulation, and test/dm.sh declares at [Q3] that it CANNOT pin that mechanism —
# a mutant that reintroduces the delimited round trip kills nothing (measured: 66/66). Listing
# the line here is the cheapest compensating control available: if its shape ever changes, this
# manifest fails loud and a human looks at the one mechanism the suite is blind to.
anchors_ok() {
  _bad=0
  while IFS= read -r _a; do
    [ -n "$_a" ] || continue
    _n=$(grep -cxF -- "$_a" "$ENGINE_BACKUP" 2>/dev/null)
    if [ "$_n" != 1 ]; then
      printf 'anchor matches %s line(s), want 1: [%s]\n' "$_n" "$_a"
      _bad=1
    fi
  done <<'ANCHORS'
      2) continue ;;
  if ! { true >&1; } 2>/dev/null; then
      _warn "could not emit pending dm messages for @$_dt_lane; leaving them pending"
  _JM_PARSE_RC=$?
  _JM_ERROR_RC=$?
      bounded($field_max) | tojson
  "$_DM_JQ_BIN" -e -n '"x" | (utf8bytelength == 1 and ((tojson | type) == "string"))' \
        | if (($record | tojson | utf8bytelength) <= $line_max) or $limit <= 1
          id: $id
      \{*'"id":"'"$_pd_name"'"'*\})
      case "$_esc_payload" in *'\"id\":\"'"$_ep_name"'\"'*) ;; *) _DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac
_dm_dest_occupied() { [ -e "$1" ] || [ -L "$1" ]; }
    _dm_route_failed "$_pd_lane" "$_pd_file" "structurally unusable dm queue entry" || return 3
  _warn "dm $_cd_state destination is occupied for $_cd_name; using a collision-safe name"
  _ni_ts=$(_now_compact) || return 1
  _dm_id_ok "$_ni_id" || return 1
  case $? in 0) ;; 1) return 0 ;; *) return 1 ;; esac
  _dm_digits_ok "$_io_pid"
        set -- "$@" "$_pending_name"
  _announce_as "$_from" "dm → @$_to (transcripts: .brain/dm/$_to/)" \
        _emit_session_ctx "Agent Brain: branch '$_br' has no presence note. If this is a tracked feature, register it once: \"$BRAIN/bin/brain\" new-feature $_slug"
More DMs remain pending after this bounded batch. Continue by running: \"$BRAIN/bin/brain\" dm take
On activity, consume it by running: \"$BRAIN/bin/brain\" dm take
  jq --arg ss "$1" --arg pt "$2" --arg dir "$BRAIN" --arg allow "Bash($BRAIN/bin/brain:*)" '
  jq --arg dir "$BRAIN" --arg allow "Bash($BRAIN/bin/brain:*)" "$_JQ_PERMISSIONS_MERGE"
ANCHORS
  [ "$_bad" = 0 ]
}

# Every selector used by a mutant, including the deliberately multi-line `g` substitutions.
# Format: expected-count~mutant/selector label~sed BRE. `~` is excluded from every address.
addresses_ok() {
  _bad=0
  while IFS='~' read -r _want _label _address; do
    [ -n "$_address" ] || continue
    _n=$(sed -n "\\%${_address}%p" "$ENGINE_BACKUP" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$_n" != "$_want" ]; then
      printf '%s address matches %s line(s), want %s: [%s]\n' \
        "$_label" "$_n" "$_want" "$_address"
      _bad=1
    fi
  done <<'ADDRESSES'
1~M1 batch arm~^      2) continue ;;$
1~M2 stdout preflight~^  if ! { true >&1; } 2>/dev/null; then$
1~M2 emit-warn scope~could not emit pending dm messages
1~M3 parse status~^  _JM_PARSE_RC=\$?$
1~M3 digest-case scope~^    case "\$_pd_digest" in$
1~M4 error status~^  _JM_ERROR_RC=\$?$
1~M5 bounded serializer~^      bounded(\$field_max) | tojson$
1~M6 digest id field~^          id: \$id$
1~M6 digest-case scope~^    case "\$_pd_digest" in$
# The two envelope-witness rows are indent- and variable-agnostic (`^ *`, `.*`) so they survive
# the V.B fix turning the single first-id check into a loop, whichever way GREEN spells it. The
# leading `\*` is NOT decoration: without it the address also reaches the `\{*\}` brace check two
# lines above, which shares the whole `_DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac` tail. That
# ambiguity was introduced and then caught by this very table (measured: 2 matches, want 1).
1~M6 envelope witness~^ *case "\$_esc_payload" in \*.*_DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac$
1~M12 envelope witness~^ *case "\$_esc_payload" in \*.*_DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac$
2~M7 byte metric~utf8bytelength
1~M8 collision predicate~^_dm_dest_occupied() { \[ -e "\$1" \] || \[ -L "\$1" \]; }$
1~MQ1 nonregular route~^    _dm_route_failed "\$_pd_lane" "\$_pd_file" "structurally unusable dm queue entry" || return 3$
1~MQ2 derived stamp~^  _ni_ts=\$(_now_compact) || return 1$
1~MQ2 id validation~^  _dm_id_ok "\$_ni_id" || return 1$
1~MQ3 derived stamp~^  _ni_ts=\$(_now_compact) || return 1$
1~MQ4 empty gate~^  case \$? in 0) ;; 1) return 0 ;; \*) return 1 ;; esac$
1~MQ5 pid grammar~^  _dm_digits_ok "\$_io_pid"$
1~M9 journal line~dm → @\$_to (transcripts: .brain/dm/\$_to/)
5~M10 engine path~\$BRAIN/bin/brain
1~M11 directive~^On activity, consume it by running: \\"\$BRAIN/bin/brain\\" dm take$
ADDRESSES
  [ "$_bad" = 0 ]
}

# probe <label> <required-ids> <permitted-ids> <expected-changed-lines> <sed-program>
# The sed runs into a COPY (never -i, which is spelled differently on BSD and GNU). The changed
# line count is asserted so a drifted pattern (0 changed) and an over-broad one (too many) are
# both caught before the suite ever runs.
#
# REQUIRED vs PERMITTED (dispatcher-approved 2026-08-04). The old check was sorted-string
# equality — "these scenarios exactly" — which cannot express a kill that is real but contingent
# on something outside the mutant's control. M1 has three such kills (see its note), and equality
# forced a choice between two wrong declarations: list them and cry wolf wherever the contingency
# does not hold, or omit them and cry wolf wherever it does. The semantics now are:
#   · every id in REQUIRED must die, or the mutant is not evidence;
#   · every id in PERMITTED may die or survive — both are fine;
#   · anything dying OUTSIDE both sets is still a failure, exactly as before;
#   · killing nothing at all is still a failure, exactly as before.
# PERMITTED is empty for every mutant but M1, so their verdict lines are unchanged.
probe() {
  _label=$1; _required=$2; _permitted=$3; _want_changed=$4; _sed=$5
  sed "$_sed" "$ENGINE_BACKUP" >"$MUTANT_ENGINE" \
    || { echo "$_label: SED FAILED ❌"; rc=1; return; }
  # A redirect creates the file fresh, so the engine's mode does not come along — and the suite
  # aborts on a non-executable BRAIN_BIN, which reads as "the suite did not complete" for every
  # mutant at once. (`cp -p` + `sed -i` used to carry the mode; `-i` is spelled differently on
  # BSD and GNU, which is why the redirect form is the one kept.)
  chmod +x "$MUTANT_ENGINE" \
    || { echo "$_label: could not make the mutant executable ❌"; rc=1; return; }
  _changed=$(diff "$ENGINE_BACKUP" "$MUTANT_ENGINE" 2>/dev/null | grep -c '^> ')
  if [ "$_changed" != "$_want_changed" ]; then
    echo "$_label: mutated $_changed line(s), declared $_want_changed — PATTERN DRIFTED ❌"
    rc=1; return
  fi
  if ! sh -n "$MUTANT_ENGINE" 2>/dev/null || ! dash -n "$MUTANT_ENGINE" 2>/dev/null; then
    echo "$_label: mutant broke syntax — INVALID ❌"; rc=1; return
  fi
  if ! run_suite ./test/dm.sh "$MUTANT_ENGINE"; then
    echo "$_label: suite did not complete its $EXPECTED_SCENARIOS-scenario summary ❌"
    rc=1; return
  fi
  _got=$RUN_FAILURES; _suite_exit=$RUN_EXIT

  case "$_suite_exit" in 1|3) ;; *)
    echo "$_label: suite exit $_suite_exit is not a completed failing-suite status ❌"; rc=1; return ;;
  esac
  _missing=""; _undeclared=""
  for _id in $_required; do
    in_set "$_id" "$_got" || _missing="$_missing $_id"
  done
  for _id in $_got; do
    in_set "$_id" "$_required" || in_set "$_id" "$_permitted" \
      || _undeclared="$_undeclared $_id"
  done

  if [ -z "$_got" ]; then
    echo "$_label: NO SCENARIO FAILED → the suite does NOT pin this mechanism ❌"; rc=1
  elif [ -n "$_missing" ]; then
    echo "$_label: killed [$_got], but REQUIRED$_missing survived → not evidence ⚠"; rc=1
  elif [ -n "$_undeclared" ]; then
    echo "$_label: killed [$_got], undeclared collateral$_undeclared → not evidence ⚠"; rc=1
  elif [ -z "$_permitted" ]; then
    echo "$_label: killed exactly [$_got] ✅"
  else
    echo "$_label: killed [$_got] — all required dead, rest permitted ✅"
  fi
}

echo "=== instrument self-check ==="
instrument_selfcheck || { echo "mutation instrument self-check failed ❌"; exit 1; }

echo "=== sed address cardinality ==="
if addresses_ok; then
  echo "every mutant address has its declared engine cardinality ✅"
else
  echo "MUTANT ADDRESS AMBIGUOUS — re-address before trusting any result below ❌"; exit 1
fi

echo "=== anchor manifest ==="
if anchors_ok; then
  echo "every mutated line matches exactly once against bin/brain ✅"
else
  echo "ANCHOR MANIFEST STALE — re-anchor before trusting any result below ❌"; exit 1
fi

echo "=== baseline (no mutation) ==="
if baseline_ok ./test/dm.sh; then
  echo "baseline complete and clean ($EXPECTED_SCENARIOS/$EXPECTED_SCENARIOS) ✅"
else
  echo "BASELINE INVALID: exit=$RUN_EXIT failures=$RUN_FAILURES ❌"; exit 1
fi

# ── v1.2 consume path (re-anchored to v1.2.1) ────────────────────────────────────────────
# Must-survive #3: a malformed file must never suppress a valid peer. Abandoning the batch at the
# first quarantine is the classic head-of-line regression. The v1.2 anchor for this
# (`          || _dt_rc=1`) died in the /simplify pass; the quarantine arm of the take loop's
# case is the mechanism now.
#   NOT V.N/54: measured. Its fixture holds ONE entry, so there is no peer behind the quarantine
#   for the break to strand — the mutant is invisible there, and declaring it would be a guess.
#   ⚠ ORDER DEPENDENCE — the one soft spot in this probe, and it is NOT merely theoretical.
#   V.Q/56, V.Q/57 and V.Q/66 each queue an invalid entry and a healthy peer whose names are both
#   engine-minted, so which one the glob reaches first is decided by `<ts>-<pid>` compared
#   LEXICALLY. The victim is queued first and normally gets the lower pid, so it sorts first, the
#   break strands the peer, and the scenario dies. But a lexical compare of decimal pids is not
#   numeric order: if the pid counter crosses a digit-length boundary between the two sends
#   (9999 → 10001), then `...Z-10001` sorts BEFORE `...Z-9999`, the peer is emitted before the
#   break, and all three drop out of this set.
#   MEASURED BOTH WAYS: 4 consecutive runs here killed all 7; re-ordering V.Q/56's two sends so
#   the peer is queued first makes V.Q/56 survive while the other six still die. So these three
#   are genuine but CONDITIONAL kills.
#   RESOLVED by the REQUIRED/PERMITTED split (dispatcher-approved 2026-08-04). The five kills
#   that hold BY CONSTRUCTION are required; the three that hinge on pid layout are permitted:
#     · V.W/30 and V.N/49 corrupt whatever `first_file` returns, so the poison IS the head entry
#       whatever it is named;
#     · V.Q/55's wall, V.R/68's trailing-newline directory, and V.Q/58's crafted entry have fixed
#       names that sort ahead of any engine-minted `<today>T…` name for the life of this suite.
#   The three permitted ones instead corrupt a SPECIFIC planted entry and depend on it sorting
#   ahead of a peer minted moments later — true here, not guaranteed anywhere.
#   ⚠ NOTE FOR CI: the inversion is rare on macOS (5-digit pids, wrap at 99999) but much more
#   likely on Linux with a small pid_max (32768 default), where the counter crosses digit-length
#   boundaries and wraps often. Do not read a permitted-set survivor as a regression there.
probe "M1  batch-abort-on-bad   " "V.W/30 V.N/49 V.Q/55 V.Q/58 V.R/68" "V.Q/56 V.Q/57 V.Q/66" 1 \
  's@^      2) continue ;;$@      2) break ;;@'

# Must-survive #2 (emit before move). BOTH defences must fall: the closed-stdout preflight and
# the per-message emit check. The `return 1` is addressed via the unique warn ABOVE it — a bare
# `^      return 1$` also matches _dm_collision_dest's checksum-failure arm.
probe "M2  emit-before-move     " "V.N/47" "" 2 \
  's@^  if ! { true >&1; } 2>/dev/null; then$@  if false; then@
/could not emit pending dm messages/{n;s@^      return 1$@      _dt_rc=1@;}'

# v1.2.1 ruling 2: the parse-error exit code must be MEASURED on the deployed jq, never assumed.
# Hard-coding 5 is exactly the H2 defect (jq 1.6 exits 4). Ruling 13's digest witness now catches
# V.Q/57's empty rc-0 digest independently, so this mutant also admits ONLY an empty digest; `{}`
# still fails and V.U/76 remains the witness's own discrimination. Both defences must fall for the
# original unestablishable-jq failure to remain observable, just as M2 drops both emit defences.
probe "M3  jq-parse-rc-hardcoded" "V.Q/56 V.Q/57" "" 2 \
  's@^  _JM_PARSE_RC=\$?$@  _JM_PARSE_RC=5@
/^    case "\$_pd_digest" in$/{n;s@^      @      ""|@;}'

# v1.2.1 ruling 2, second contract (review H3): the error() code is a separate undeclared
# dependency. Hard-coding it leaves the parse-error probe intact, so this is orthogonal to M3.
probe "M4  jq-error-rc-hardcoded" "V.Q/66" "" 1 \
  's@^  _JM_ERROR_RC=\$?$@  _JM_ERROR_RC=5@'

# Must-survive #8 + the digest JSON pinning: retain a real object and exact id so ruling 13's
# cheap witness passes, but move the four wire fields under prose. Only the three structural
# digest scenarios should notice; the old bare-prose mutant now fails systemically everywhere.
probe "M5  prose-digest         " "V.W/26 V.W/27 V.W/28" "" 1 \
  's@^      bounded(\$field_max) | tojson$@      bounded($field_max) | {id: .id, text: "from=\\(.from) to=\\(.to) ts=\\(.ts) content=\\(.content)"} | tojson@'

# Must-survive #8: drop the stable ID from the rebuilt record. The digest and envelope witnesses
# are relaxed only to require some `id` text so `{}` still dies in V.U/76 and V.U/77; this keeps
# the legacy mutant focused on V.N/52 without weakening either new witness declaration.
#   ⚠ THE ENVELOPE RELAXATION IS NOT FOCUS-PRESERVING ANY MORE, and the declaration says so
#   rather than papering over it. Against the post-fix engine the third program relaxes a LOOP,
#   so every staged id is accepted on the strength of the bare text `id` while the digest carries
#   none of them — which is precisely what section V.B forbids, and V.B/103, V.B/105 and V.B/106
#   die on it. Those kills are GENUINE (the engine archives messages whose ids never reached the
#   envelope), not instrument damage, and they are deterministic, so they are REQUIRED rather
#   than permitted. Removing the relaxation does not help: an un-relaxed loop rejects every
#   batch wholesale and M6 becomes a blunt systemic mutant instead of a focused one.
probe "M6  digest-drops-id      " "V.N/52 V.B/103 V.B/105 V.B/106" "" 3 \
  's@^          id: \$id$@          id: ""@
/^    case "\$_pd_digest" in$/{n;s@^      .*@      \\{*id*\\})@;}
s@^ *case "\$_esc_payload" in \*.*_DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac$@      case "$_esc_payload" in *id*) ;; *) _DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac@'

# Must-survive #6: the wire caps are BYTE caps (utf8bytelength), not code-point counts. Both
# source sites move together — the shared measurement used by preflight/re-probe, plus digest —
# so this stays a digest-bound mutant rather than a dependency-contract one.
probe "M7  codepoint-not-byte   " "V.W/28" "" 2 \
  's@utf8bytelength@length@g'

# Must-survive #5: an occupied read/ or failed/ destination must never be clobbered. Reporting
# "never occupied" also silences v1.2.1 ruling 6's bump-taken diagnostic, so V.Q/62 rides along.
# V.R/73 now also requires both occupied witnesses to survive before the compact fallback lands.
probe "M8  collision-bump-gone  " "V.N/51 V.N/54 V.Q/62 V.R/73" "" 1 \
  's@^_dm_dest_occupied() { \[ -e "\$1" \] || \[ -L "\$1" \]; }$@_dm_dest_occupied() { return 1; }@'

# ── v1.2.1 mechanisms ────────────────────────────────────────────────────────────────────
# Ruling 1: a non-regular direct child of pending/ is quarantinable on the same footing as
# invalid content. Demoting it back to a TRANSIENT failure restores H1's starvation exactly: the
# entry keeps its batch slot forever and everything behind it is never reached.
# V.R/73's near-NAME_MAX directory is the same proven non-regular class and must also be routed.
probe "MQ1 nonregular-transient " "V.Q/55 V.R/68 V.R/73" "" 1 \
  's@^    _dm_route_failed "\$_pd_lane" "\$_pd_file" "structurally unusable dm queue entry" || return 3$@    return 1@'

# Ruling 4: minted identity is DERIVED, never inherited. Honouring _DM_ID_TS needs the grammar
# gate dropped too — the v1.2.1 engine validates the id before composing any path, which is the
# second half of the same ruling.
probe "MQ2 id-ts-from-env       " "V.Q/60" "" 2 \
  's@^  _ni_ts=\$(_now_compact) || return 1$@  _ni_ts=${_DM_ID_TS:-$(_now_compact)}@
s@^  _dm_id_ok "\$_ni_id" || return 1$@  :@'

# Ruling 4, second half: the clock helper must ACTUALLY succeed. A synthetic fallback mints a
# grammar-VALID id, so every name check still passes — only the "nothing may be queued" limb
# (F6) catches it.
probe "MQ3 clock-synthetic-stamp" "V.Q/61" "" 1 \
  's@^  _ni_ts=\$(_now_compact) || return 1$@  _ni_ts=$(_now_compact) || _ni_ts=20260101T000000Z@'

# M1 (review): v1.1 paid ZERO jq forks on an empty-queue boot. Removing the emptiness gate makes
# a broken jq observable on a no-op and flips `dm take`'s rc contract from 0 to 1.
probe "MQ4 preflight-on-empty   " "V.Q/65" "" 1 \
  's@^  case \$? in 0) ;; 1) return 0 ;; \*) return 1 ;; esac$@  :@'

# Ruling 3(a): the producer grammar admits whitespace again. THIS IS THE DISCRIMINATION PROOF
# V.Q/59 was allowed to freeze behavioural-only on, and it is meaningful only now that V.Q/59's
# margin fix has landed — before that its verdict depended on batch accounting.
#   WHY V.Q/59 DIES HERE, measured: not through its emit-before-move invariant (the collected
#   names still cross as quoted positional parameters, so nothing un-emitted is archived) but
#   through its second limb, "the crafted whitespace name must not be digested". Both limbs are
#   ruling 3; only 3(a) is reachable once 3(b) is implemented.
#   MEASURED AND DROPPED — two mutants that kill NOTHING, each CONFIRMING a declared gap in
#   test/dm.sh rather than exposing one. Neither is committed, because a probe entry that kills
#   nothing fails this harness by design:
#     - ROUND-TRIP ONLY (grammar intact, `for _emitted_name in $(printf "%s " "$@")`): 66/66.
#       No whitespace-bearing name can reach the collected set, so the re-split has nothing to
#       tear apart. Exactly what [Q3] declares — ruling 3(b) is defence in depth against a future
#       name-shaped value, not a currently-reachable second defect.
#     - GRAMMAR + ROUND-TRIP together: kills V.Q/58 and V.Q/59, the SAME set as the grammar
#       alone, because the verdict is scenario-level and 3(a)'s limb has already fired. It buys
#       no signal over this mutant, so it was dropped rather than kept for appearances.
probe "MQ5 grammar-admits-space " "V.Q/58 V.Q/59" "" 1 \
  's@^  _dm_digits_ok "\$_io_pid"$@  return 0@'

# ── journal secrecy (UR-10) ──────────────────────────────────────────────────────────────
# The call-log line must be body-INDEPENDENT, not merely free of the literal body. This mutant
# leaks a reversible base64 of the body and is its own control: V.S/8's digit-stripped shape
# comparison catches it, while V.S/7's and V.S/9's literal-fragment assertions do NOT — base64
# emits no '_' and no run of the probe markers. That asymmetry IS the hole UR-10 named, so a run
# in which V.S/7 or V.S/9 also fires means the mutant grew teeth it should not have.
probe "M9  journal-b64-leak     " "V.S/8" "" 1 \
  's#dm → @$_to (transcripts: .brain/dm/$_to/)#dm → @$_to (transcripts: .brain/dm/$_to/) [b64:$(printf %s "$_msg" | base64)]#'

# ── deployment resolution (must-survive #7) ──────────────────────────────────────────────
# A relative engine path resolves against the RECEIVING lane's worktree, which may carry a
# tracked engine predating `dm take` — the live failure this fix exists for. V.C/24 pins the
# always-emitted activity instruction; V.N/50 pins the bounded-backlog continuation instruction.
probe "M10 relative-engine-path " "V.C/24 V.N/50" "" 5 \
  's@\$BRAIN/bin/brain@.brain/bin/brain@g'

# The emitted line must be an INSTRUCTION, not a bare path: a lane watching its pending/ dir has
# to be told what to do on activity.
probe "M11 no-directive-verb    " "V.C/24" "" 1 \
  's@^On activity, consume it by running: @On activity: @'

# ── emit-time batch integrity (section V.B) ──────────────────────────────────────────────
# The defect this section exists for: `_emit_session_ctx_pinned` validated that the serialized
# envelope carried the FIRST staged id, while `_hook_session_start` archived EVERY staged name on
# its success — so an envelope that kept message 1 and dropped 2..N passed the guard and archived
# all N as delivered. Same class as the r8 `count-checks-admit-set-drift` lesson: an integrity
# check scoped narrower than the set it authorizes.
#
# This mutant reverts exactly that scope and nothing else. It rewrites the loop-BODY case line so
# that every iteration tests the FIRST staged name (`"$1"`) instead of the name the loop is
# currently on. The post-fix loop still runs once per staged message, still uses the real
# `\"id\":\"<name>\"` framing, and still rejects — it just checks the same id N times, so it never
# looks past message 1.
#   WHY THE CASE LINE AND NOT THE LOOP HEADER: the case line already has a declared address that
#   is indent- and variable-agnostic, so this mutant costs no new dependency on how GREEN spells
#   the loop. Rewriting the pattern to a bare `*"$1"*` was measured and REJECTED as the mutant:
#   it also drops the escaped-fragment framing, which kills V.V/84 on a second mechanism and
#   makes the verdict unattributable. The framing is preserved here byte-for-byte.
#   NOT V.B/104 or V.B/105: both survive BY CONSTRUCTION, and that is the mutant's own control.
#   /104's envelope carries every id, so first-only still accepts and the batch still archives;
#   /105's envelope drops the first id, which first-only is precisely the check that catches.
probe "M12 envelope-first-id-only" "V.B/103 V.B/106" "" 1 \
  's@^ *case "\$_esc_payload" in \*.*_DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac$@      case "$_esc_payload" in *'"'"'\\"id\\":\\"'"'"'"$1"'"'"'\\"'"'"'*) ;; *) _DM_JQ_SYSTEMIC_FAILURE=1; return 1 ;; esac@'

echo "=== final tree check ==="
if cmp -s "$ENGINE_BACKUP" "$ENGINE_SOURCE"; then
  echo "bin/brain remained byte-for-byte unchanged ✅"
else
  echo "DIRTY — bin/brain changed while isolated mutants ran ❌"; rc=1
fi
exit "$rc"
