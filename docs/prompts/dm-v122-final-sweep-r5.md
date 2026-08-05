# Final adversarial sweep, round 5 — lane-DM branch at d30c736 (pre-PR convergence gate)

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
witnesses while being structurally invalid or incomplete (nested/data `}` framing confusion,
serializer-specific terminal witnesses, escaped-fragment uniqueness, round-tripping the
payload through jq). That entire class is answered by rulings 13 + 13b: it requires a
deliberately defective binary on PATH, i.e. an attacker with code execution as this user,
and the residual exposure (a message archived without delivery, recoverable from `read/`) is
accepted on the record.

If you believe the ceiling itself is wrong, say so in ONE short paragraph at the end under
"Boundary objection" — with a concrete accidental (non-adversarial) failure mode it lets
through. Do not spend the review on it.

## Scope

`git diff main...HEAD`. Newest code is `d30c736` (r6): `_dm_failed_state`'s tri-state
ancestor walk and its two consumers (`_dm_failed_count`, `cmd_status`), plus scenarios
V.Y/86-89. Weight attention there. Then the whole branch with fresh eyes, INSIDE the
boundary. Read the map rulings 1-14 + errata 13a/13b.

## Skip list

All prior rounds' skip lists (briefs `dm-v122-final-sweep*.md`), plus everything covered by
the ceiling above, plus: the CHANGELOG/plan drift fixed in the r5/r6 doc commits.

## Fresh angles (in-boundary only)

1. r6's ancestor walk: rc conflation at either consumer; the fork-free claim on the common
   absent path; behavior when `dm/` root is absent entirely vs lane absent vs failed absent;
   interaction with `_dm_ensure_tree` creating those dirs moments earlier in the same run.
2. Queue-state and lifecycle bugs anywhere on the branch that do NOT depend on a lying jq:
   permissions, symlinks, renames, ordering, rc propagation, the batch cap, `cmd_commit`'s
   DM purge/secret-scan interplay, hook wrapper contracts.
3. Test-suite validity: any scenario that would pass with its defense deleted (name the
   exact deletion); probe anchors matching more than once by luck.
4. Doc drift from the r5/r6 commits.

## Report

Verdict line FIRST: READY or NOT READY. Findings: File / Line / Category / Severity /
Finding / Evidence / Fix. Optional final "Boundary objection" paragraph as described above.
