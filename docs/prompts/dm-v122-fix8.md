# Dispatch brief — DM v1.2.2 fix round 8: sweep-r6's composed drift gap (W1 suite + W2 manifest)

Same per-arc override (Steve, 2026-08-05). Engine + test edits yours; do NOT commit. All
standing fences apply — DOC fence unchanged: you own `test/dm.sh` prose and
`test/mutation-probe.sh`; orchestrator owns CHANGELOG / plan / docs/reviews. Required
reading: `.context/seams/dm-v1.1-queue.md` must-survive #4 and #7, ruling 13b (no witness
code this round — a witness finding is answered by that paragraph).

## The finding (sweep 6, orchestrator-CONFIRMED by measurement)

The r7 address-cardinality check bounds the two `g`-flag mutants (M7 `utf8bytelength` ×2,
M10 `$BRAIN/bin/brain` ×5) by COUNT only — they are deliberately excluded from the
exact-line anchor manifest (documented at `test/mutation-probe.sh` ~line 128). A selector
can therefore drift to a DIFFERENT set of N lines and every integrity check stays green.

Confirmed counterexample (reproduce it yourself as your RED): copy `bin/brain`; change the
line-~1515 backlog continuation `Continue by running: \"$BRAIN/bin/brain\" dm take` to the
relative `.brain/bin/brain dm take` (a REAL regression of must-survive #7); plant
`# engine lives at $BRAIN/bin/brain` as a comment. Measured on that copy: M10 cardinality
still 5, changed-line count still 5, no anchor breaks (the continuation line is in no
manifest), M11's anchor intact, and `continuation_signal()` (`test/dm.sh` ~445) still
matches because it greps broad wording (`remain|more …|again`), never the path. The probe
would report `M10 killed exactly [V.C/24]` against an engine whose continuation path is
already broken.

## W1 — suite, the cheapest instrument (assertion on observable behavior)

In V.N/50 (or a sibling assertion within that scenario), assert the emitted continuation
instruction carries the ABSOLUTE receiving-lane engine invocation — the fixture knows the
vault path, so assert the exact expanded string (`"<vault>/bin/brain" dm take` form), not a
looser pattern. This is must-survive #7's deployment-resolution property, NOT wording-
pinning (the broad `continuation_signal` alternation stays as-is for #4). The drifted
engine above must now FAIL this scenario; the negative-control fixture must stay green.

## W2 — probe manifest: exact line sets for the multi-count selectors

Add M7's 2 lines and M10's 5 lines to the exact-line anchor manifest (they are load-bearing
shapes now, same as every other entry) and rewrite the ~line-128 exclusion comment to say
the opposite: multi-count selectors are bounded by count AND exact lines. Any of those 7
lines changing shape must fail the manifest loud. Keep the declared counts in the
address-cardinality table unchanged.

## DECLINED, on the record — do not build

The sweep's suggested ">40-message sibling-worktree test that extracts and executes the
continuation command" is NEW harness machinery (command extraction + execution + a second
worktree fixture). A review finding is evidence, not authorization; W1+W2 discriminate the
named fault at strictly lower cost. If you believe W1+W2 leave a named fault
undiscriminated, SAY SO as a declared gap — do not build the executor.

**Instrument budget: ZERO new mutants, zero new helpers.** W1 is an assertion in an
existing scenario; W2 is manifest entries + a corrected comment.

## Gates — full battery on the FINAL tree, paste real output

Both suites × sh AND real dash; sh -n/dash -n; shellcheck vs 11 baseline + code set;
`sh test/mutation-probe.sh`. Your sandbox may deny `mktemp` — if so, say so explicitly and
do the RED structurally (show the drifted-copy measurements before/after); the orchestrator
re-runs everything regardless. Report: verdict first, the W1/W2 table, the counterexample
A/B (drifted engine must fail V.N/50 and/or the manifest check after the fix; the real
engine must pass everything), fence self-declarations.
