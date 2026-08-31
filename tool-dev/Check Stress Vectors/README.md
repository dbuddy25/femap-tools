# Check Stress Vectors

Diagnostic. Answers one question: **what do the stress output vectors in this model actually
contain, per element type?**

*(file: `Check Stress Vectors.bas`)*

**Status:** Built 2026-08-31, untested. Read-only — nothing in the model is modified.

## Why

This is the groundwork for a *peak stress by group / property / material* table. That table is
one `max()` away from trivial. The part that is not trivial is knowing which output vector to
take the max **of**.

Every element type stores stress in a different vector — plate von Mises top is not solid von
Mises, and neither is beam stress. A wrong vector ID does not raise an error. It returns
numbers, and plausible ones. A stress summary built on the wrong vector is worse than no
summary at all, because it looks right.

So the vectors get read before the table gets written.

## What it measures

1. **Do the IDs resolve?** `ResultsIDQuery.Plate()` and `.Solid()` return a vector ID or
   `FE_FAIL`. `FE_FAIL` means the model has no such vector — usually the solver was never asked
   for that output. Printed per vector.

2. **What is in the rows?** `Populate` loads columns for the whole model, not just the elements
   a vector applies to. So a plate-von-Mises column may return rows for solid elements too. The
   probe counts, per column, how many *nonzero* rows belong to plates, to solids, and to
   neither.

3. **Is the padding zero or garbage?** If a plate column pads its solid rows with `0.0`, a
   `max()` over von Mises is still correct — stress is positive. A **min principal** `max()` is
   not, because a padded `0.0` beats every real compressive value. Min and max are printed per
   column so the padding value is visible rather than assumed.

4. **Is `VPP_BOT` really 3?** The plate ply enum runs `TOP=0, MID=1, BOT=3` — it skips 2. The
   probe also queries ply 2 and prints all three IDs side by side, so the skip is confirmed
   rather than trusted. Separately, the `Solid()` location argument is documented under two
   different names (`VSL_CENTROID` in the method description, `VPL_CENTROID` in the constants
   table); locations and plies are passed as integer literals so a wrong enum name cannot
   silently select the wrong one.

## How to read the output

| You see | It means |
|---|---|
| A vector ID of `FAIL` | The solver did not write that result. Exclude the column from the table, or re-run the solve asking for it. |
| Nonzero rows on the wrong element class | The column is padded across the whole model. The table must filter rows **by element class**, not just by bucket membership. |
| A min-principal column whose max is exactly `0.0` | The padding is zero and it is winning. Min-principal columns must skip padded rows or they will report 0. |
| `ply=2` returns an ID equal to neither `ply=0` nor `ply=3` | MID is a real third vector, and `BOT=3` is correct. |

Warnings are printed inline next to the column that triggered them.

## Usage

Run it, pick one output set. Everything else is automatic. Output goes to the Messages window.

## Next

The findings here decide three things in the peak-stress table: which columns it can offer,
whether it filters rows by element class, and how it handles min-principal padding.
