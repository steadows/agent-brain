# Dispatch brief — DM v1.2.2 fix round 2: /simplify clusters + pre-PR review findings

**Mode: FULL CYCLE where tests are named — same per-arc override as `dm-v122-full-round.md`
(Steve, 2026-08-05): you own both test and engine edits this round. Do NOT commit; the
orchestrator verifies and commits.**

## Required reading, in order

1. `.context/seams/dm-v1.1-queue.md` — the seam map, ALL of § v1.2.2 + rulings 1–6.
   Every fix below implements a triaged finding; none licenses a new design direction.
2. `docs/prompts/dm-v122-full-round.md` §3 — every hard fence there still applies
   (frozen 66 + V.R additions now also frozen EXCEPT where a fix below names them;
   commit-install.sh byte-frozen; no cmd_install/_write_project_settings/templates/.brain;
   probe kill declarations may strengthen, never weaken).
3. This file, fully, before any edit.

## Engine fixes (bin/brain)

E1. **Extract the jq probe triple.** One `_dm_jq_measure` that runs the three probes
    against `"$_DM_JQ_BIN"` and sets `_JM_PARSE_RC`/`_JM_ERROR_RC` (variable-return, rc 1
    on capability failure). `_dm_jq_preflight` = resolve + measure + reject-zero + record;
    `_dm_jq_contract_holds` = measure + compare against the recorded pair. It must NOT
    re-resolve PATH. (3 independent review angles converged on this.)
E2. **Delete the redundant middle-layer validations**: `_dm_dir_ok "$_dt_pending"` in
    `cmd_dm_take` (pre-scan), the `&amp;&amp; _dm_dir_ok "$_ib"` in `_hook_session_start`, and
    `_dm_dir_ok "$_ds_pending"` in `_dm_send`. The scanners self-validate both sides
    (ruled); `_dm_ensure_tree`'s gate stays. Behavior (rc + diagnostics) must be unchanged
    — the suite is the referee.
E3. **Merge `_dm_ensure_tree`'s two loops** into one create-then-validate pass per state.
E4. **`_slug_of()` variable-twin** beside `_agent_slug` (`_SLUG=${1##*/}; _SLUG=${_SLUG%.md}`),
    used at the two new inline sites (`_resolve_whoami` match loop, broadcast loop). Mark
    `_agent_slug` display-only in its comment. Do NOT migrate its other callers.
E5. **Exact-path witness** in `_dm_id_in_use` uses `_dm_dest_occupied "$_iu_exact"`.
E6. **Validate inherited identity at the resolver**: in `_resolve_whoami`, `_feat_ok` the
    non-empty `BRAIN_FEATURE`; invalid → one `_warn` diagnostic + `_WHOAMI` stays empty
    (return 0). Keep V.R/70 green — its assertions are behavioral (nonzero rc, `brain:`
    diagnostic, no consumption) and must hold with the rejection moving earlier. If any
    V.R/70 line must change, justify it line-by-line in the report.
E7. **Post-exhaustion revalidation** in both consuming loops: after the `for` over
    pending/* exits by exhaustion, `_dm_dir_ok` the dir once; on failure `cmd_dm_take`
    sets rc 1, the hook warns (hook wrapper stays rc 0). Closes the probe→loop-expansion
    TOCTOU window at the third enumeration site (ruling 7's letter: "before trusting any
    scan" — the loop glob IS a scan).
E8. **Pin the send-path jq**: `_dm_write_json` resolves via `_dm_resolve_jq` per send
    operation and invokes `"$_DM_JQ_BIN"`. No contract probes on the send path.
E9. **Batch-abort on systemic jq failure + name the binary**: when
    `_dm_jq_contract_holds` fails, set a module flag; both consume loops check it after
    the digest dispatch and `break` (mirroring the top-of-batch preflight-failure shape) —
    one warn per operation, not one per entry (live-reproduced at 3×/invocation; 40 cap).
    The warn includes `${_DM_JQ_BIN:-&lt;unresolved&gt;}`.
E10. **Bump `VERSION="1.2.2"`.**
E11. **Nesting**: with E2's deletion, restore the flat
    `if _dm_ensure_tree ... &amp;&amp; _dm_dir_has_entries ...; then` shape in the hook IF
    truth-table-identical (rc 1/2 both skip consume; add the one-line comment saying the
    convergence is deliberate — the hook must exit 0 and rc-2 diagnostics come from
    `_dm_dir_ok`'s warn). Otherwise keep the case and add the comment.

## Test fixes (test/dm.sh) — you own these under the override

T1. **Drive `_dm_jq_contract_holds` for real** (deletion-verified as currently uncalled
    across all 70 scenarios): extend V.R/69 (or add a sibling limb) with a shim that
    OVERWRITES ITSELF IN PLACE on the "dm preflight" trigger — same path stays resolvable,
    content becomes hostile returning the recorded parse rc — so `_dm_digest` reaches a
    hostile binary whose rc matches, entering the re-probe branch; the re-probe must fail
    the capability check → leave-pending. Assert: pending intact, failed/ empty, ONE
    contract-changed warn naming the binary (pins E9's batch-abort too — queue ≥2 messages
    in this limb and assert the warn count is exactly 1). Follow V.N/53 shim discipline
    (save/restore/leak-check). After the fix, stub-`return 0`-ing `_dm_jq_contract_holds`
    must flip this limb red — state in your report that you verified exactly that.
T2. **Declared gap** for the scanner-internal `_dm_dir_ok` checks in
    `_dm_id_in_use`/`_dm_dir_has_entries` (deletion-verified: not independently exercised;
    a mid-process permission flip is not drivable from a single CLI invocation). Add [Q6]
    to the header's declared-gaps list naming the mechanism and why it is undrivable, per
    the Q1–Q5 style. Also add the one-line note that read/-side `_dm_collision_dest` is
    unreachable for hostile names (grammar gate precedes `_dm_archive`) — same
    declare-don't-omit convention.
T3. **Prose reconciliation in test files**: AUTHORITY header gains v1.2.2 as item 0
    (naming rulings 7/8/9 → section V.R); run banner mentions the v1.2.2 addendum; V.R
    block gets its ═══ divider; SHIM DISCIPLINE enumeration includes ruling 9;
    mutation-probe header prose updated (v1.2.2, "four times"). ⚠ `templates/…SKILL.md`
    is pinned to the byte by V.T/43–45 — do not touch templates for any of this.
T4. **Restore-idiom alignment**: V.R/67's `chmod 755 … || fatal` → the suite's
    `|| true  # restore BEFORE any early return` idiom.

## Probe (test/mutation-probe.sh)

P1. Re-anchor whatever E1–E11 move (each sed must match exactly once — the manifest
    self-check is the referee). Kill declarations may strengthen, never weaken; M7's
    count will change again with E1 (expect 2: measure + digest) — verify empirically,
    don't hand-wave the number. If T1's new limb changes M-kill sets, update declarations
    with one-line justifications.

## Adversarial-sweep findings (verified by the orchestrator; map rulings 10–12 in
## `.context/seams/dm-v1.1-queue.md` § v1.2.3 are the authority — read them first)

E12. **Pinned + verified emit before archive (ruling 10, HIGH).** SessionStart serialization
     uses the operation-pinned `"$_DM_JQ_BIN"`; stage the payload, require it NON-EMPTY, one
     checked write, and only then archive the collected messages. Zero-byte/failed emit →
     everything stays pending + one warn. The raw-text fallback survives only on the no-DM
     nudge path (nothing archived on its strength). Note: on the entries path the preflight
     has already pinned `_DM_JQ_BIN`; do not re-resolve.
E13. **Per-suffix byte-cap recheck in `_dm_collision_dest` (ruling 11).** Validate every
     `-<n>` variant against `DM_FILENAME_MAX_BYTES`; when the next suffix would exceed the
     cap, switch to the compact checksum form with counter headroom reserved. Final basename
     within the cap by construction.
E14. **Hidden-entry classification (ruling 12).** Enumerate dot children other than
     `.`/`..`/`.tmp-*` in the pending scans (`_dm_dir_has_entries`, both consume loops,
     `_dm_id_in_use`'s occupancy scan) and route them through ruling 1's existing
     classification (they fail the id grammar → quarantine as structurally invalid).
     ⚠ `.tmp-*` stays excluded EVERYWHERE by name — it is the atomic-send staging namespace;
     classifying a mid-write temp would break send atomicity. POSIX sh note: `.*` globs match
     `.` and `..` on some shells — filter them explicitly, and keep the scan fork-free.

T5. **Emit-swap scenario (pins E12):** post-digest PATH swap where the replacement jq exits 0
    with EMPTY output — assert messages remain pending, nothing archived, one warn; then a
    stable-jq retry delivers. V.N/53 shim discipline.
T6. **NAME_MAX collision scenario (pins E13):** plant a near-cap non-regular pending name
    whose exact failed/ twin AND first collision candidate are occupied; assert quarantine
    succeeds under a within-cap name (checksum form) and pending drains.
T7. **Hidden-entry scenario (pins E14):** plant `pending/.poison` (plus a healthy peer);
    assert the dot entry quarantines as structurally invalid, the peer delivers, the queue
    reads empty afterward, and a planted `.tmp-`prefixed file is NOT touched.

## Gates — run ALL on the FINAL tree, paste real output

Same battery as `dm-v122-full-round.md` §5 (sh + real dash × both suites, sh -n/dash -n,
shellcheck count vs 11 baseline + code set, mutation probe). Plus: the A/B discrimination
re-check for T1 (stub `_dm_jq_contract_holds` → limb goes red → unstub). Re-run everything
LAST, on the tree you deliver.

## Report shape

Verdict first (READY/NOT READY); per-fix table (id → done/blocked → files touched);
T1's stub-flip evidence; gate outputs; fence self-declarations.
