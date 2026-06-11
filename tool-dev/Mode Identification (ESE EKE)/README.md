# Mode Identification (ESE EKE)

*(file: `Mode Identification (ESE EKE).bas`)*

**Status:** Built — pending in-Femap testing.

Modal post-processing tool. For each selected **output set (mode)** and each selected
**element group**, it reports the group's **% Element Strain Energy (ESE)** and **%
Element Kinetic Energy (EKE)** — the classic "which parts carry the strain / kinetic
energy of this mode" view. Results go to one Excel sheet, ESE and EKE side by side,
each with a per-mode **Total** column to confirm ~100%.

Requires Element Strain Energy + Element Kinetic Energy output from the SOL 103 run,
with `PARAM,TINY,1.-20` so every element reports energy.

## How it works

1. **Select** output sets (modes) and element groups.
2. **Resolve the energy vectors at runtime** (no hardcoded IDs) via
   `ResultsIDQuery.Elemental(1)` = Strain-Energy-Percent and `.Elemental(30)` =
   Kinetic-Energy-Percent (fallback: `Find(setID, "...Percent")` by title). This is
   what makes it version-proof — no hand-editing an ID when results change.
3. **Coverage check** — compares the union of the selected groups to all model
   elements and warns if elements are **uncovered** (totals < 100%) or the groups
   **overlap** (totals > 100%).
4. **Build the matrix** — for each mode: `DataNeeded(8, 0)` (all elements),
   `AddColumnV2` for ESE% + EKE%, `Populate` once, then `GetColumnSum(col,
   groupElemSet, …)` per group (the set-limit restricts the sum to that group).
   Validated against Femap's Data Table — same numbers as a per-group populate, and
   faster.
5. **Excel** (late-bound, so it survives Office version changes): one `Energy by
   Group` sheet (ESE block + Total, gap, EKE block + Total; red/green data bars;
   vertical group-title headers) plus a `README` sheet logging the model, user, date,
   resolved vector IDs, and the coverage numbers.

## Layout

```
A            B       C          D ... (ESE groups) ...  Total   |  ... (EKE groups) ...  Total
OutSet #     Title   Freq[Hz]   <one column per group>          |  <one column per group>
```
One row per mode. Each `Total` is a live Excel `=SUM(...)` across that block's group
columns → should read ~100.00 when the groups partition the model.

## Key API (verified against api.pdf)

| Need | Call |
|---|---|
| ESE% / EKE% vector ID (runtime) | `App.feResultsIDQuery.Elemental(1)` / `.Elemental(30)`; fallback `.Find(setID, "...Percent")` |
| Results browser | `feResults`: `DataNeeded(8, 0)`, `AddColumnV2(setID, vecID, False, nAdded, vIdx)`, `Populate`, `GetColumnSum(col, limitSetID, nNumVal, sum, sumSq)`, `Clear` |
| Output set value | `OutputSet.value` = modal frequency (Hz) |
| Group elements | `Set.AddGroup(FT_ELEM, groupID)`; all elements `Set.AddAll(FT_ELEM)` |
| Excel | late-bound `CreateObject("Excel.Application")`; `appExcel.UserName` |

## Notes

- A clean rewrite of an inherited "Mode ID" tool. The old hardcoded vector IDs
  (`80001`/`80104`) are replaced by the runtime `ResultsIDQuery` lookup, so the IDs
  never need hand-editing when the results/version change. (Tested: the lookup
  resolves to `80001`/`80104` and per-mode totals come out ~100%, confirming both are
  the percent vectors.)
- **Validation:** the per-group %ESE/%EKE sums were checked against Femap's **Data
  Table** (its own GUI vectors) and match. They did **not** match an older inherited
  tool — because that tool uses the deprecated `AddColumn` (old vector-ID scheme),
  which reads a *different* vector for the same ID number than the v2020.1 `AddColumnV2`
  this tool uses. Femap's GUI (and Data Table) use the V2 scheme, same as this tool.
