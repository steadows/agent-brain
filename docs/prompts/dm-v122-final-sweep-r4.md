# Final adversarial sweep, round 4 — lane-DM branch at c879468 (pre-PR convergence gate)

Same contract as rounds 1–3 (briefs `dm-v122-final-sweep*.md`): ALONE, findings only, no
code edits, no fan-out. If you cannot find material issues say READY explicitly — a clean
verdict from you closes this gate; do not invent findings, do not go easy.

## Scope

`git diff main...HEAD`. Newest code is `c879468` (r5): the ruling-13a witness corrections —
`{...}` framing on all three payload witnesses, key-syntax matching on the send witness,
the escaped `\"id\":\"<staged-id>\"` envelope fragment, the absence-only status fast path —
plus scenarios V.V/80–85 and minimal probe re-anchors. Read the map end-to-end (rulings
1–14 + erratum 13a), especially the trust-boundary paragraph.

## Skip list

Everything in rounds 1–3's skip lists, PLUS: truncated rc-0 payloads (→ framing witnesses);
quoted-word key matching (→ key syntax); bare-id envelope false positive (→ escaped
fragment); non-directory failed/ banner bypass (→ absence-only gate); CHANGELOG/probe-header
drift (fixed).

**Boundary reminder:** ruling 13's declared trust boundary stands — a PATH binary that
passes the full probed contract AND forges structurally well-formed payloads (correct
framing, correct escaped id fragment, correct key syntax) is out of the threat model; do
not file findings that require it. In-boundary findings (cheaper bypasses, composition
bugs, accidental-shape gaps) are exactly what this round is for.

## Fresh angles

1. The 13a corrections themselves: `case` framing patterns vs payloads containing `}` mid-
   string; the escaped-fragment pattern vs jq's actual escaping of the digest block inside
   `additionalContext`; the absence-only gate's fork cost claim.
2. Composition: witnesses × systemic flag × discard/abort machinery × the batch cap, on
   both consume paths and the send/broadcast path.
3. Doc drift from `04a98f4`.
4. Anything else in-boundary the ladder predicts.

## Report

Verdict line FIRST: READY or NOT READY. Findings: File / Line / Category / Severity /
Finding / Evidence / Fix.
