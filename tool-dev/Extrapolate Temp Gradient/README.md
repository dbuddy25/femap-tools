# Extrapolate Temp Gradient

Reads the nodal temperatures that already exist on part of a model, fits a linear gradient along a chosen axis, and applies it to the rest of the model — extrapolating in both directions past the seeded region.

**Last updated:** 2026-08-14
**Status:** Built and run in Femap.

## Usage

- Run in Femap's API Programming window
- Pick the **source load set** — the one holding the existing temperatures
- Review the per-axis fit quality, then pick the axis (**global X/Y/Z** or a **custom vector**)
- Select the **target nodes** (the selector's Select All covers the whole model)
- Choose the destination load set and whether to clamp, then confirm

## What It Does

- Reads every nodal temperature in the source set (`LoadNTemp.GetAllArray`) and the matching node coordinates
- Least-squares fits `T = a + b·s` along global X, Y and Z, where `s` is the node's projection onto that direction, and reports the **R²** of each so you can see which axis the gradient actually runs along
- Applies the chosen fit to every target node and writes the result with `LoadNTemp.PutArray`

## Options

- **Axis** — global X, Y, Z, or a picked vector. The best-fitting global axis is preselected.
- **Destination** — write into the source load set, or a new set with a typed title
- **Clamp to the seeded temperature range** — caps values far outside the seeded region, where an unbounded line can run to physically absurd temperatures

## Output

- One nodal temperature per target node
- Summary report: source set, seeded node count, axis and unit vector, fitted intercept/slope, R², destination set, temperatures written, result range, clamp count

## Notes

- **R² is the gate, not a decoration.** If it is well below 1.0 the source field is not linear along that axis, and extrapolating it produces a plausible-looking but meaningless field. The confirm dialog warns below 0.99 — abort rather than proceed.
- **Every target node gets the fitted value**, including nodes that were part of the seed. With a genuinely linear source field those come back identical; if they don't, the field wasn't linear and the R² already said so.
- Node coordinates from the API are global rectangular, so the projection axis is interpreted in global rectangular coordinates.
- Temperature-dependent functions (`LoadNTemp.function`) are not carried over — created temperatures are constant values.
- Handles **Group → Automatic Add** if you use it (evaluates the target group before regenerating); no-op if it's off.

## Possible extensions

- **Bilinear fit** (`T = a + b·x + c·y`) for a field with a genuine two-axis gradient. The current fit is single-axis: it projects onto one direction and ignores the other two, producing a field that is constant on every plane perpendicular to that axis. A low R² over a seed region that spans more than one direction is the signal that this is needed.
