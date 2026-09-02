# Interpolate Temp Between Sets

Two node sets that already carry nodal temperatures, plus the nodes between them, and a linear
gradient is written across the middle.

*(file: `Interpolate Temp Between Sets.bas`)*

**Status:** Built 2026-09-02, untested. **Modifies the model** — it creates nodal temperature loads.

## Not the same as Extrapolate Temp Gradient

| | |
|---|---|
| `Extrapolate Temp Gradient` | Fits a line through **one** seeded region and projects it outward |
| **This tool** | **Bounded** — both ends are known, so nothing is predicted beyond the data |

That difference is the point. Extrapolation can run to physically absurd temperatures far from the
seed, which is why that tool has an R² gate and a clamp. Interpolation between two measured faces
cannot.

## Usage

1. Pick the load set holding the existing temperatures
2. Select **end set A**, then **end set B**, then the **nodes between them**
3. Review the two end temperatures reported in the Messages window
4. Choose destination load set and whether to clamp

## How a node's position is measured

The axis runs from the **centroid of A to the centroid of B**. A middle node's fraction is its
projection onto that axis, so the field is constant on every plane perpendicular to it — the
textbook linear gradient through a wall, a flange, a standoff.

`T = Ta + f · (Tb − Ta)`, with `f` clamped to 0…1 by default.

**This is the wrong model when the path between A and B curves**, because the projection measures
straight-line distance rather than distance through material. The tool cannot detect that from
node positions alone, so it is stated rather than guarded against.

## What it checks before writing

- **Uniformity of each end set.** The tool was asked for on the understanding that each end is all
  one temperature. It reports the spread of each set, and if either is non-uniform it says so and
  asks before using the average — averaging silently would produce a gradient that looks right and
  isn't.
- **End nodes with no temperature** in the chosen load set are counted and excluded from the
  average rather than being treated as zero.
- **Coincident centroids** stop the run. Concentric sets — inner and outer face of a cylinder —
  are genuinely nested rather than opposed, and a projected gradient cannot describe them.
- **Middle nodes outside the A…B span** are counted and reported. That is a selection problem, not
  a maths one: it means the middle set reaches past one of the ends.

## Output

One nodal temperature per middle node, plus a summary: source set, both end temperatures with node
counts, middle node count, destination set, result range, and any nodes outside the span.

## Notes

- Node coordinates from the API are global rectangular, so the axis is interpreted in global
  rectangular coordinates.
- Temperature-dependent functions (`LoadNTemp.function`) are not carried over — created
  temperatures are constant values.
- Handles **Group → Automatic Add** by re-evaluating the target group; no-op when it's off.
- `GetAllArray` returns coordinates packed three per node, so node `k` sits at `3k, 3k+1, 3k+2`.

## Possible extensions

- **Nearest-node distance ratio** instead of axis projection, for curved or irregular paths where
  a single straight axis misrepresents the distance through material.
- **Per-node end temperatures** rather than one value per set, preserving a varying face
  temperature instead of flattening it to an average.
