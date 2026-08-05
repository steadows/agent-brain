# Final adversarial sweep, round 6 — lane-DM branch at `1249b99` (r7) + docs `2cb0021`

ALONE (no sub-agents, no fan-out), findings only, no code edits. Say READY explicitly if you
find nothing material — do not invent findings, do not go easy.

## ⚠ READ FIRST — ruling 13b, the WITNESS CEILING (signed by the human owner, 2026-08-05)

`.context/seams/dm-v1.1-queue.md` § 13b is a **signed product decision**, not an oversight.
Shell-side output validation of jq's payloads STOPS at the r5 witnesses. POSIX shell cannot
parse JSON and message content may contain any byte, so no `case` pattern can distinguish an
outer delimiter from a data one — rounds 3 and 4 each demonstrated this, which is why the
ceiling was drawn.

**Therefore, OUT OF SCOPE this round — do not file, do not restate as a new severity:**
any finding whose trigger is a jq that exits 0 and emits output that satisfies the shipped
witnesses while being structurally invalid or incomplete. That entire class is answered by
rulings 13 + 13b: it requires a deliberately defective binary on PATH, i.e. an attacker with
code execution as this user, and the residual exposure (a message archived without delivery,
recoverable from `read/`) is accepted on the record.

If you believe the ceiling itself is wrong, say so in ONE short paragraph at the end under
"Boundary objection" — with a concrete accidental (non-adversarial) failure mode it lets
through. Do not spend the review on it.

## Scope

`git diff main...HEAD`. Newest code is `1249b99` (r7): `_dm_failed_count` became the ONE
authoritative tri-state+count call (runs the `_dm_failed_state` ancestor walk itself,
revalidates the directory AFTER glob expansion, returns via `_DM_FAILED_COUNT` — no `$( )`
on either status path), `cmd_status` gates on its rc; the mutation probe gained an
address-cardinality self-check (all 21 sed selectors across 16 mutants asserted against
declared engine match counts; M6 re-addressed 3→1); scenarios V.Z/90-91. Weight attention
there. Then the whole branch with fresh eyes, INSIDE the boundary. Read the map rulings
1-14 + errata 13a/13b.

## Skip list

All prior rounds' skip lists (briefs `dm-v122-final-sweep*.md`), everything covered by the
ceiling above, the doc reconciliation landed in `2cb0021`, and the DECLARED suite gaps
[Q1]-[Q7] (`test/dm.sh` header) plus the probe header's declared limits — re-filing a
declared gap is a finding only if you demonstrate its stated premise is false (e.g. you
exhibit a one-CLI-invocation reproduction for something declared non-drivable).

## Fresh angles (in-boundary only)

1. r7's collapse: rc conflation between `_dm_failed_count`'s tri-state (0 counted /
   1 proven-absent / 2 cannot-establish) and `cmd_status`'s `-le 1` gate; `_DM_FAILED_COUNT`
   scalar lifetime (stale reads after a non-zero rc, any second consumer); interaction with
   `_dm_ensure_tree` having just created `failed/` in the same run; behavior when `dm/` root
   is absent entirely vs lane absent vs leaf absent.
2. The address-cardinality self-check ITSELF: `\%…%` BRE delimiter semantics; the `~`
   field-separator exclusion; multi-count addresses (M7 declares 2, M10 declares 5) — an
   address drifting to a DIFFERENT set of N lines still counts N; does the exact-line
   replacement manifest close that composed gap or is there a reachable false-pass?
3. Queue-state and lifecycle bugs anywhere on the branch that do NOT depend on a lying jq:
   permissions, symlinks, renames, ordering, rc propagation, the batch cap, `cmd_commit`'s
   DM purge/secret-scan interplay, hook wrapper contracts.
4. Test-suite validity beyond what [Q7] declares: any scenario that would pass with its
   defense deleted (name the exact deletion); probe anchors or addresses surviving by luck.
5. Doc drift from the r7 fix and `2cb0021` reconciliation.
