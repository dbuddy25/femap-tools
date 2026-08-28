# Check MPC Export

Diagnostic. Answers one question: **where** do constraint equations stop being written on their
way into a Nastran deck?

*(file: `Check MPC Export.bas`)*

**Status:** Built 2026-08-28, untested.

## Why

Constraint equations that plainly exist in the model can come out of an export as nothing at
all — no `MPC` cards, no warning, no empty section. There are at least three independent gates
between an equation and a deck, they fail identically, and nothing distinguishes them:

1. **The equations are not where you think.** They live in a constraint *set*, and the set that
   looks active in the UI is not necessarily the one they were written into.
2. **The analysis set does not select them.** An analysis set names its constraint equations in
   `BCSet[1]` — a *separate* slot from `BCSet[0]` constraints. Unset, which is what a fresh
   analysis set has, means no set is selected and nothing is written.
3. **The group filter drops them.** `NasBulkGroupID` limits a deck to the entities in that
   group, and that governs equations exactly as it governs elements: every node an equation
   references must be in the group.

Three plausible-sounding fixes were applied to this problem in sequence, on reasoning, and none
of them worked. This tool exists because that is the wrong way to find out.

## How it works

It does not reason about any of the above. It writes real decks and counts the `MPC` cards:

- **Probe A** — whole model, `BCSet[1]` set → do the equations export *at all*?
- **Probe B** — filtered to a group you pick → does the group filter drop them?

Before the probes it lists every constraint set with the number of equations actually in it,
and prints the node:dof terms of the equations in the set you select — which is the list you
check a group against when gate 3 is the culprit.

## Reading the result

| A | B | Meaning |
|---|---|---|
| 0 | 0 | The equations never export. Gate 1 or 2 — check the set table, and open probe A. |
| >0 | 0 | Export is fine; the **group** is the problem. It is missing a node the equations reference. |
| >0 | >0 | They export in both. Whatever is wrong is downstream — the consuming tool, or the master deck's case control not selecting the MPC set. |

## Known gaps

- Nothing in the model is modified: the probe analysis set is created and deleted again, and
  the two `.bdf` files are the only output.
- The card count is a signal, not an inventory. What matters is whether it is zero.
- No `On Error` around the Femap calls, consistent with the rest of the toolset.
