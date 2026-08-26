# Group Mass Properties

Per-group mass, CG and inertia for a set of selected groups, written to one flat Excel table with a totals row.

**Status:** Built — pending in-Femap testing.

## Use case

Mass-properties reporting across an assembly: pick the groups that make up the parts, get one sortable, filterable table of what each weighs and where its CG sits, plus a combined rollup for the whole selection.

## Replaces

An in-house script last touched in 2016 (`group mass properties calculating and reporting`). It had stopped working and its output was hard to use. Both causes are worth recording.

**Why it broke.** It opened with an early-binding reference:

```
'#Reference {...}#C:\Program Files (x86)\Microsoft Office\Office14\EXCEL.EXE
```

A hard dependency on Excel 2010 at exactly that path. Every other Excel tool in this toolset is late-bound (`CreateObject`) specifically so an Office upgrade can't break it — that script was the outlier. This one is late-bound too.

**Why the output was hard to use.** Three tiers of merged header cells, which make a sheet impossible to sort or filter; a "Pt Mass Model Data" block with headers that were never written to in ten years; and one hardcoded `"0.000"` format applied to a fixed `D11:AH200` range — wrong for values spanning orders of magnitude, and silently truncating past row 200.

Also fixed along the way: `CID = 3` was hardcoded, baking one person's coordinate system into a tool shared with colleagues.

## What it does

1. Select groups, then choose the coordinate system from a dropdown built from the model.
2. Each group is measured with `feMeasureMeshMassProp`.
3. Overlap, empty and zero-mass groups are detected and flagged.
4. The sign convention for the off-diagonal inertia terms is determined at runtime (see below).
5. Results go to a `Mass by Group` sheet plus a `README` provenance sheet. The workbook is left open and unsaved.

## Columns

Single header row on row 2, AutoFilter, frozen panes. Column A and row 1 are a blank margin.

| Column | Format | Notes |
|---|---|---|
| Group ID, Group Name, Elements | `0`, text, `#,##0` | |
| Mass (total / structural / non-struct) | `0.0000E+00` | scientific — real models span many orders of magnitude |
| CG X / Y / Z | `0.0000` | total CG, in the chosen coordinate system |
| Ixx / Iyy / Izz / Ixy / Iyz / Izx (cg) | `0.0000E+00` | about **each group's own CG** |
| Flags | text | blank when clean |

Flagged rows are tinted amber. Dropped relative to the old sheet: length/area/volume, structural and non-structural CG, and inertia about the coordinate-system origin.

## Two things that look wrong and aren't

### The inertia index mapping

`feMeasureMeshMassProp` returns `inertia[0..5]` packed **lower-triangular**:

```
0 = I11 (Ixx)    1 = I21 (Ixy)    2 = I22 (Iyy)
3 = I31 (Izx)    4 = I32 (Iyz)    5 = I33 (Izz)
```

So reading Ixx, Iyy, Izz, Ixy, Iyz, Izx means indices **0, 2, 5, 1, 4, 3**. That reads like a typo and is not. The old script had it right; don't "fix" it.

### Per-group inertia is never summed

The API returns two arrays: `inertia` about the **origin** of the chosen coordinate system, and `inertiaCG` about **that group's own CG**.

Per-group `inertiaCG` values are each about a *different point*, so summing them is meaningless. The totals row instead sums the about-origin arrays — all about the same point, so that is valid — and applies the parallel-axis theorem once at the end to shift to the combined CG. This is why the about-origin values are still computed even though the sheet doesn't display them.

## The sign convention is measured, not assumed

The API guide never states whether `Ixy` is a **product of inertia** (`+∫xy dm`) or an **inertia tensor** term (`−∫xy dm`). The parallel-axis theorem needs the opposite sign in each case, so guessing would produce a silently wrong totals row — the worst failure mode a mass-properties report has.

Both arrays come from a single call, and they are related by exactly the shift being identified:

```
Ixy(origin) − Ixy(cg) = conv · M · cx · cy      conv = +1  products of inertia
                                                conv = −1  inertia tensor
```

The tool divides one by the other on the group with the strongest signal (a group whose CG sits near a coordinate plane makes the predicted shift tiny and proves nothing), then corroborates on the other two off-diagonal slots. Three independent votes; any disagreement and no convention is claimed.

**Validation gate.** Before any of that is trusted, a *diagonal* term is checked: `Ixx(origin) − Ixx(cg)` must equal `M·(cy² + cz²)` under **both** conventions. If that identity fails, the premise itself is wrong — the arrays are not what the guide says — and no convention is inferred.

The result is written to the README sheet and the Messages summary every run. If it can't be established, the totals inertia is left blank rather than guessed.

## The totals are checked against Femap's own answer

The convention self-check proves the *sign*. This proves the whole chain.

`seenSet` — the union of every selected group — is exactly the aggregate body the totals row describes, provided nothing overlaps. So the tool measures it directly with one extra `feMeasureMeshMassProp` call and compares Femap's answer against its own:

| Compared | Why it matters |
|---|---|
| Combined mass | validates the sums |
| Combined CG | validates the mass-weighted average |
| Inertia about the combined CG | validates the summation, the parallel-axis shift, **and the sign convention**, all at once |

That last row is the prize. Femap computes the union's inertia about the union's CG *internally*, with no parallel-axis step and no sign assumption from this tool. If the convention vote had picked the wrong sign, the three off-diagonal terms would disagree by `2·M·Rx·Ry` — a large, obvious number, not a rounding artefact.

The worst relative difference is reported as PASS/FAIL in the Messages window and on the README sheet. It does **not** require the groups to cover the whole model — only that they don't overlap each other.

## When the totals row goes blank

Mass sums are always shown — a sum of masses is a sum of masses. The **CG and inertia cells are left blank**, with the reason in the Flags cell, when:

- the selected groups **overlap** (mass double-counted, so a combined CG is meaningless, not merely imprecise),
- any group returned `FE_NEGATIVE_MASS_VOLUME`,
- total mass is zero,
- or the sign convention couldn't be established (inertia only).

A blank cell is recoverable. A plausible-looking wrong CG is not.

## Flags

| Flag | Meaning |
|---|---|
| `OVERLAP` | Shares elements with an earlier selected group — mass counted more than once |
| `EMPTY` | Group holds no elements. Written as a row rather than skipped, so a group that contributed nothing is visible |
| `ZERO MASS` | Has elements but no mass — geometry-only, or no density on the property |
| `NEG MASS-VOL` | Femap reported negative mass or volume; returned values may understate the total |

The Messages summary also reports coverage: how many model elements no selected group contains.

## Implementation notes

**Group Name and Flags are forced to Text format before anything is written.** Excel type-infers on write, so a group titled `3-4 Bracket` becomes a date and one titled `1E5` becomes `100000`. That is silent corruption of the one column the reader uses to identify the row, and it is unrecoverable — the original string is gone by the time anyone notices.

**Scientific number format costs no precision.** `NumberFormat` is display-only; the cell still holds the full double, so copy/paste and downstream formulas are unaffected. For values spanning ten decades it is also more readable than a fixed mask, and fixed-width so a column aligns.

**No live Set cursor across a Femap call.** Group IDs are harvested into arrays before any measuring begins, matching the discipline in `Remove From Groups`.

**One coordinate system for the whole run.** The summability of the about-origin inertias is a direct consequence of that single choice — it is why the old `CID = 3` had to become a user selection rather than simply being deleted.

## Known gaps

- No `On Error` around the Femap calls — only the Excel COM calls are fenced.
- The convention self-check needs at least one group with an off-axis CG. A model where every group's CG sits on a coordinate plane yields no determination, and the totals inertia is blanked.
- Coverage compares element counts only; it doesn't report *which* elements are uncovered.
- The workbook is never saved to disk, matching the rest of the toolset.
- Units are not reported — the sheet inherits whatever the model uses.
