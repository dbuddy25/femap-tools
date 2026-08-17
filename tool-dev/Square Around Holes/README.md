# Square Around Holes

Pick any number of **circles or arcs** and drop a **square** around each one, lying in that circle's own plane, centered on its center, with its four edges **tangent** to the circle. The square is created as four curves.

**Last updated:** 2026-08-17
**Status:** Written, **not yet run in Femap** — needs a live check.

## Usage

- Run in Femap's API Programming window
- Select the circles / arcs to square
- Set the **size rule** and **orientation source** in the options dialog
- If orienting from a picked vector, pick it when prompted
- Review the tally dialog and click OK

## What It Does

Per selected curve it needs three things, and gets each with a call that works on **both** native arc/circle curves and **solid** (imported CAD) curves:

| Need | Call |
|---|---|
| Center | `feCoordCurveCenter` |
| Plane normal + a reference in-plane X axis | `fePlaneCurveNormal` |
| Radius | `Curve.ParamToXYZ(0.5)`, then distance from the center |

Then the four corners are `center ± h·X̂ ± h·Ŷ` (with `Ŷ = normal × X̂`) walked in loop order, and four `feLinePoints` calls close the square.

## Options

- **Size** — tangent (`side = 2R`), `2R × factor`, or an explicit side length. A washer or doubler footprint is usually a spec dimension rather than a function of the hole, which is why the last two exist.
- **Orientation** — a circumscribing square has infinitely many valid rotations about the hole axis, so the rotation has to come from somewhere:
  - **Pick a direction vector** — the picked vector is projected into *each* hole's plane, so one pick orients a whole bolt pattern even when the holes are not coplanar.
  - **Hole plane's own X axis** — whatever `fePlaneCurveNormal` reports. No extra pick, but the rotation is arbitrary per hole.

## Output

- Four curves per hole
- Summary report: curves selected, squares created, size rule, hole radius range, orientation source, and counts for anything skipped or fallen back

## Notes

- **`feCoordCurveCenter` does no checking on solid curves.** The API guide is explicit that it assumes whatever it is handed is an arc, so a planar spline would return a plausible-looking center and a meaningless radius. The tool guards this by sampling two more parametric locations on the curve and requiring them to sit the same distance from the center (0.1% relative tolerance). Curves that fail are counted as skipped.
- **`feLineRectangle` looks perfect for this and is unusable.** It creates four lines forming a rectangle from two diagonal corners — but it *projects them onto the workplane*, and there is **no API function to set the workplane**. It can only ever produce a square in whatever plane the workplane happens to be in, so it cannot be aimed at a tilted hole. Hence four explicit `feLinePoints(False, ...)` calls.
- **A vector nearly parallel to a hole axis is a degenerate pick.** Its projection into that hole's plane collapses to noise. Below ~3° (projected length < 0.05, since `feVectorPick` returns a unit vector) the tool falls back to that hole's plane X axis and reports the count separately in the confirm dialog — the tally is shown before anything is written, so a bad pick can be cancelled.
- **Group → Automatic Add is handled if you use it** (evaluates the target group before regenerating); no-op if it's off.
- Coordinates from the API are global rectangular throughout.
- Nothing is done about duplicate or overlapping squares if the same hole is picked twice, or if two concentric arcs are both selected.
- Arcs work as well as full circles — a partial arc still defines the underlying circle.

## Possible extensions

- **Make the square a surface**, or a surface with the hole cut out, rather than four loose curves. `feSurfaceCorners(True, c1..c4)` takes the four corners directly; `feBoundaryFromPoints(0, 4, corners, bID)` would give points + lines + boundary in one call.
- **Rectangles, not just squares** — separate width/height, same math.
- **Screen concentric duplicates** so selecting both edges of a countersink doesn't produce two stacked squares.
