# Adversarial review — DM v1.2.1 fix round (`066d9f6`)

You are a senior adversarial code reviewer working ALONE — do NOT spawn sub-agents or fan out;
single-agent is a hard requirement (the multi-agent fleet belongs to the post-PR ultrareview gate).
Findings only — do not edit code. Your sandbox blocks the suites (`mktemp` rejected); do not chase
that. The orchestrator has them green: `test/dm.sh` **66/66** and `test/commit-install.sh` **15/15**
under `sh` AND real dash, `sh -n`/`dash -n` clean, shellcheck 11 = baseline.

## Scope — the fix diff ONLY

`git show 066d9f6 -- bin/brain` (+112/−54). Read the post-diff `bin/brain` DM region in full for
context, but **findings must be about code this commit introduced or changed.** The v1.2 arc that
precedes it was already reviewed (5 HIGH / 9 MEDIUM, all closed here) — do not re-review it.

## Authority

`.context/seams/dm-v1.1-queue.md` — the `# v1.2.1` section (rulings 1–6) plus **clarification 1a**
(the batch cap bounds entries EXAMINED, not lines emitted; a counter incrementing only on
successful digest is out of contract). The `# v1.2` section above is the base design.

## What this commit changed — verify each landed correctly AND introduced nothing

1. **Ruling 1** — a non-regular `pending/` entry (symlink/dir/FIFO/socket/device) is quarantined
   into `failed/` **as a directory entry, never dereferenced**. Previously it was classified
   transient and retried forever; 40 of them permanently starved every message behind them
   (reproduced). Check: is the rename genuinely non-dereferencing on every path? Can a symlinked
   `failed/` or a race turn the quarantine itself into a follow? Does the collision-safe helper
   behave when the *source* is a symlink?
2. **Ruling 2** — `_dm_jq_preflight` now PROBES the deployed jq's parse-error and `error()` exit
   codes and records them, instead of hard-coding `5`. Fail-safe is **leave-pending, never
   quarantine**. Check: are the probe results stored in a way a later message can't corrupt? Is
   there any path where an unestablished probe still reaches a quarantine decision? What happens if
   jq's behaviour differs *between* the probe and a later call (jq replaced mid-run, PATH change)?
3. **Ruling 3, both halves** — digit-only id grammar, AND filenames carried as quoted positional
   parameters instead of a space-joined string re-split by unquoted `set --`. Check: does ANY
   remaining path join or re-split names? Is `set --` used elsewhere in the hook where a name
   could reach it? Does the new grammar reject everything it should without rejecting a legitimate
   engine-minted id (including a collision-bumped one)?
4. **Ruling 4** — identity derived, never inherited: `_DM_ID_TS` ignored, clock failure fatal to
   the mint, id validated before path composition, destination's literal parent asserted as
   `pending/`. Check: is the parent assertion done on the *composed* path or a re-derived one? Any
   other environment variable the engine still trusts into a path? Is the clock-failure path
   reachable in a way that leaves partial state?
5. **Ruling 6** — bump-taken and both bump-construction-failure paths emit `brain: ` diagnostics.
6. **Empty-queue gate** — both consume paths probe emptiness before invoking jq. Check: is the
   probe genuinely fork-free? Does it change behaviour when `pending/` is unreadable vs empty?
7. **Two requirements no test enforces** (declared gaps, shipped deliberately): `_dm_id_in_use`
   widened to a `<id>*` glob; `_dm_collision_dest` diagnoses internal failures. Check the glob
   widening especially — it now matches `<id>*` across three states. Can that glob match something
   it shouldn't (an unrelated id sharing a prefix), and does over-matching cause a mint to spin,
   hang, or escalate the bump counter unboundedly?

## Blind-spot categories to hunt

- Subtle logic errors under specific input combinations (glob ordering, prefix collisions between
  ids, empty vs unset shell variables, `IFS` assumptions, filenames at the length cap)
- TOCTOU between validate and rename, symlink swaps mid-consume, races between two concurrent
  senders and one consumer (13 lanes share one consumer's `pending/`)
- Cascade failures where an error path leaves partial state or loses a message
- State-machine violations: pending→read/failed only, no hidden intermediate state, and
  **emit-before-move on every path including partial-batch failure** — v1.0's loss bug was
  archive-before-emit, and v1.2 reintroduced it through a filename-splitting door
- Backward compatibility: the emitted hook-context format is parsed by 13 live lanes; CLI rc
  contracts (`dm take`'s rc on empty queue, on partial failure)
- Anything the fix round made *worse* than the bug it closed

## Per finding

**File / Line / Category** (security | correctness | concurrency | compatibility | cascade-failure
| state-machine) / **Severity** (CRITICAL | HIGH | MEDIUM) / **Finding** / **Evidence** (cite the
exact code path — why it is real, not speculative) / **Fix**.

If the fix round is clean, say so explicitly. Do not invent findings to justify your existence — a
clean verdict on a diff this security-sensitive is a useful result.
