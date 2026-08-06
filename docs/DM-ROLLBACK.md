# DM engine rollback runbook — DRAIN BEFORE DOWNGRADING

Plan task 5.6 (ultrareview UR-5). Read this **before** reverting `<main>/.brain/bin/brain` to any
pre-v1.2.2 build. Rolling back without draining loses messages; rolling back to the wrong build
quarantines them.

## Why a bare rollback loses data

The v1.2 engine is the **only** consumer of `dm/<lane>/pending`. A pre-DM engine has no queue
reader at all, so every queued message is stranded permanently — and a broadcast's call-log line
names only `@all`, which matches no recipient's journal filter, so the loss is also invisible.

## ⚠ Rolling back to a v1.1-era engine is WORSE than stranding — it QUARANTINES

v1.2 mints **bare `<id>`** pending filenames. v1.1's `_dm_claim_all` requires an `.a<k>` attempt
suffix, so it rejects every v1.2 name as `invalid pending dm name` on first contact and routes it
to `failed/`.

**Therefore: a non-zero `failed/` count immediately after a v1.1 rollback is most likely
false-positive grammar rejection, NOT genuine poison.** Check that before treating those messages
as bad — they are recoverable by moving them back under a v1.2+ engine.

Collision-bumped names already sitting in `read/` or `failed/` are **not** a hazard: both engines
mint identical suffix grammar, and neither engine's consume glob scans those directories.

## Before any engine rollback

**(a) Confirm every lane's `pending/` is empty.**

```sh
MAIN=~/research-dashboard/enterprise_research_dashboard
find "$MAIN/.brain/dm" -type d -name pending -exec sh -c \
  'n=$(ls -1 "$1" 2>/dev/null | wc -l | tr -d " "); [ "$n" -gt 0 ] && echo "NOT DRAINED: $1 ($n queued)"' _ {} \;
```

Silence means drained. Any output means **STOP** — either drain it (`brain dm take` as each named
lane, which requires that lane to boot) or explicitly accept and document the loss.

**Also check for a `claimed/` directory:**

```sh
find "$MAIN/.brain/dm" -type d -name claimed
```

`claimed/` **no longer exists** — v1.2 deleted the claim layer. If one appears, an engine older
than v1.2 has already run since deploy. **Stop and reconcile** before doing anything else.

**(b) Keep `dm/` in `.brain/.gitignore` PERMANENTLY.**

This is a forward-compatible invariant, not a v1.2 detail. Restoring an older `.gitignore`
alongside an older engine re-opens the path where DM bodies get staged — and the commit-time
secret scan is **line-anchored**, so it cannot see a jsonl body (the line starts with `{`). The
ignore rule is the only control that stands there. Never revert it.

**(c) `read/` and `failed/` archives are inert** under the old engine. Safe to leave in place.

## Rolling forward again

The engine is tracked in the ERD repo, so the swap is a git operation plus the same atomic
rename used at deploy — never a bare `cp`, which truncates the destination while 13 lanes are
executing it:

```sh
cp <new-engine> "$MAIN/.brain/bin/.brain.new"
chmod +x "$MAIN/.brain/bin/.brain.new"
sh -n "$MAIN/.brain/bin/.brain.new"          # syntax gate — must pass
mv "$MAIN/.brain/bin/.brain.new" "$MAIN/.brain/bin/brain"   # atomic within one directory
```

After any engine change, every active lane must **restart** — inbox arming happens only at
SessionStart (plan task 5.5).
