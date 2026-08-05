# Dispatch brief — DM v1.2.2 FULL ROUND: rulings 7/8/9, RED + GREEN + converge to clean

**Round:** v1.2.2 (third fix round of the lane-DM arc)
**Mode:** FULL TDD CYCLE — you author the failing tests AND the implementation this round.
This is a **per-arc override authorized by Steve, 2026-08-05** ("we hand all fixes to Codex …
converge on a clean run"). It supersedes, for this dispatch only, the standing GREEN-only fence.
The orchestrator independently re-verifies everything after delivery; your report is not the
evidence, the tree is.

---

## 0. Required reading, in order (all paths repo-relative to `~/agent-brain`)

1. `.context/seams/dm-v1.1-queue.md` — **THE SEAM MAP, the design authority.** Read ALL of it;
   the work is § v1.2.2 (rulings 7, 8, 9). Rulings 1–6 + 1a bind you too — do not undo them.
2. `docs/prompts/dm-v121-adversarial-review.md` — where the three findings came from.
3. `test/dm.sh` — the whole header (SAFETY discipline, `assert_disposable` interlock, SHIM
   DISCIPLINE comment near line 2451, declared gaps [Q1]–[Q5]) plus enough of the suite to
   follow its conventions. 66 scenarios, currently all green.
4. `test/mutation-probe.sh` — header + the REQUIRED/PERMITTED note above `probe()`.

## 1. The three rulings (map § v1.2.2 is authoritative; anchors below are a courtesy)

- **Ruling 8 — paths never travel through `$( )`.** `_dm_collision_dest` (`bin/brain` ~437)
  returns its destination on stdout; both callers (`_dm_route_failed` ~467, `_dm_archive` ~573)
  capture with `$( )`, which strips trailing newlines. A non-regular `pending/<name>\n` entry
  with an occupied `failed/<name>` twin stays pending FOREVER (the caller's re-check sees the
  truncated twin occupied and refuses the move). Fix per the ruling: the helper sets a
  caller-visible variable or performs the rename itself, preserving every byte except NUL.
  Sweep for any OTHER path transported through `$( )` on the DM surface and fix or justify.
- **Ruling 7 — enumeration failure is operation-fatal, never "empty"/"free".** A 0300
  (write+search, no read) queue dir defeats every glob scan: `_dm_id_in_use` (~343) reports an
  occupied id as free, `_dm_dir_has_entries` (~420) reports a non-empty queue as empty, and
  `cmd_dm_take` (~586) returns success with messages sitting there. Fix per the ruling: verify
  state dirs are readable+searchable before trusting any scan; abort with a diagnostic and
  leave messages pending otherwise. Keep an exact-path test alongside the bumped-variant glob
  scan in `_dm_id_in_use`.
- **Ruling 9 — pin the dependency's identity for the operation.** `_dm_jq_preflight` (~482)
  probes whatever `jq` PATH resolves to; `_dm_digest` (~497) re-resolves per message. Fix per
  the ruling: resolve jq once per operation, invoke that resolved path throughout, and a
  nonzero digest result may authorize quarantine only if the probe still holds for that same
  executable. Any mismatch leaves the message pending. (Quarantine is the one irreversible
  transition — fail-safe direction is leave-pending.)

## 2. RED first — and prove it

Write behavioral scenarios in `test/dm.sh` covering all three rulings, run them against the
UNMODIFIED engine, and capture the failing output in your report. Then implement. A test that
never failed is not evidence.

Instruments that already exist — reuse, don't reinvent:
- `make_readonly_dir` (test/dm.sh ~566, 0500 + positive control). Ruling 7 needs 0300
  (write+search, no read) — if you add a `make_unreadable_dir`-style helper, give it the same
  positive-control shape.
- The V.N/53 PATH-shim discipline (save/restore/leak-check) for the ruling-9 jq-swap scenario.
- Plant hostile names directly in `pending/` (the trailing-newline entry must be NON-regular —
  ruling 1 quarantines non-regular entries before the grammar check; that is what makes the
  path reachable).

Scenario ids continue the suite's existing scheme. Cheapest instrument that discriminates —
assertions on observable behavior first; no new shared state, no cross-process coordination,
no persistent fixtures in test helpers.

## 3. Hard fences — violating any of these is an automatic rejection

- **`test/dm.sh`: the existing 66 scenarios are FROZEN.** Your diff on this file must be
  pure-addition (new scenario functions + new `scenario` registration lines + any new helper).
  The orchestrator asserts this mechanically with `git diff`. If you believe an existing
  scenario is WRONG, say so in the report — do not touch it.
- **`test/commit-install.sh` is byte-frozen.** Its 15 scenarios must pass unchanged.
- **Do NOT touch:** `cmd_install`, `_write_project_settings`, anything under `templates/`
  (V.T/43/44/45 pin them to the byte), `.brain/` anywhere, `~/.claude` anywhere, docs outside
  `docs/prompts/` scratch. The live vault is sacred.
- **`test/mutation-probe.sh`:** keep `sh test/mutation-probe.sh` green. If your engine
  refactor moves a sed anchor (each must match exactly once — the manifest self-check
  enforces it), update the anchor minimally. NEVER weaken a REQUIRED kill declaration and
  never move a kill from REQUIRED to PERMITTED. Adding cheap mutants for the new defences is
  welcome but optional.
- **Do NOT commit.** Leave everything in the working tree; the orchestrator verifies and
  commits. Do not create branches, do not reset HEAD, do not stage.
- **Map "Not adopted" section stands:** no retry/attempt counters, no poison cap, no
  age-based expiry. No `${#var}` for the digest byte-count (bash counts chars, dash counts
  bytes). Do not factor the five inline PATH shims into a shared helper.

## 4. Converge: your own adversarial pass, then loop

After GREEN + REFACTOR, run an adversarial review of the FULL branch-vs-main diff with the
same rigor as `docs/prompts/dm-v121-adversarial-review.md` (state-machine walk, hostile
filesystem states, POSIX sh semantics, dash differences, TOCTOU windows on every rename).
Fix any CRITICAL/HIGH you find, re-run the gates, and review again. Repeat until a pass
returns zero CRITICAL/HIGH. Report every round: findings, severity, product-code vs
test-infrastructure split, disposition.

**Falsification terms — you are NOT done while any of these holds:**
1. A non-regular pending entry whose basename ends in `\n`, with its truncated twin occupying
   `failed/`, fails to reach quarantine (or the queue behind it stays starved).
2. A 0300 pending/read/failed dir lets any mint, take, or SessionStart consume report
   success, "empty", or "free" instead of aborting with a diagnostic and leaving messages
   pending.
3. Swapping the PATH-resolved jq between preflight and digest can still quarantine a healthy
   message.
4. Any gate below is red, or was last run on a tree that you subsequently modified.

## 5. Gates — run ALL on the FINAL tree, paste real output

```sh
./test/dm.sh                                   # 66 + your additions, expect all pass
./test/commit-install.sh                       # 15/15
sed '1s|.*|#!/usr/bin/env dash|' bin/brain > /tmp/brain-dash && chmod +x /tmp/brain-dash
BRAIN_BIN=/tmp/brain-dash ./test/dm.sh         # REAL dash, not the harness fake
BRAIN_BIN=/tmp/brain-dash ./test/commit-install.sh
sh -n bin/brain && dash -n bin/brain
shellcheck bin/brain                            # count findings with grep -cE '^In .* line'
                                                # baseline is 11 — no new codes allowed
sh test/mutation-probe.sh                       # all mutants: required dead, tree restored
```

A gate number from an earlier tree is not a result. Last round's report cited pre-refactor
numbers; that pattern previously shipped a red state. Re-run everything last.

## 6. Report shape (verdict first)

1. `READY` or `NOT READY` + one sentence.
2. Rounds table: round → findings (id, severity, product|test-infra) → disposition.
3. RED evidence: the failing-run excerpt per new scenario, then the green run.
4. Gate outputs (final tree), including the dash invocations and the probe.
5. Every file touched, with a one-line why. Anything you touched outside §3's allowed set is
   a self-declared fence violation — name it rather than hoping it passes unnoticed.
6. New declared gaps, if any, in the suite header's [Q*] style.
