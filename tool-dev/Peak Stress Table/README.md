# Peak Stress Table

Peak stress per bucket — **group, property, material or element type** — across any number of
output sets, written to Excel as one flat table. Read-only on the model.

*(file: `Peak Stress Table.bas`)*

**Status:** Built 2026-09-01, corner-data rework same day. Untested since the rework.

## The table

One row per bucket. Each output set contributes its own block of three measures, in the order you
picked them, with an envelope block last:

| Bucket | Elements | *set 1* Von Mises | Max Prin | Min Prin | *set 2* Von Mises | Max Prin | Min Prin | **ENV** Von Mises | Max Prin | Min Prin |
|---|---|---|---|---|---|---|---|---|---|---|

The header is **one row**, with the set name and the measure stacked inside a single cell by a
line break. Merging the set name across its three columns would look tidier and would break both
sorting and AutoFilter.

**The envelope is across output sets only, never across buckets.** Von Mises and Max Principal
take the largest value; Min Principal takes the most **negative**, because the governing
compressive value is the most negative, not the largest. It is omitted for a single output set,
where it would only repeat it. The von Mises cell of the governing set is tinted on each row.

## Where the stress is read — the setting that decides whether it agrees with Femap

`Stress read at:` in the dialog, three choices:

| Choice | |
|---|---|
| **Corner, unaveraged** | default; the worst of the element's corners |
| Centroid | one value per element |
| Both | worst of the two |

**Centroidal stress is materially lower than corner stress on the same element.** A table built
on the centroid does not disagree with Femap's own group max by a rounding error — it disagrees
by a visible margin, and it is the tool that is wrong, because the number an analyst quotes comes
off a corner-data plot. The first version queried `VPL_CENTROID` only, and read low for exactly
this reason.

The dialog is **seeded from the active view's Contour Options** (`View.ContourCornerData`), so the
default matches what is on screen, and the README sheet records which it used. No active view
falls back to corner.

Corner values are read **raw** from the corner vectors, so they are unaveraged by construction.
The tool does no nodal averaging at all; matching an *averaged* contour would mean averaging
across the elements meeting at each node, which is a different number and is not offered.

## API notes

- `PlateWithCorners(result, type, ply, VectorIDs)` → **five** IDs: `0` centroid, `1..4` corners.
- `SolidWithCorners(result, type, VectorIDs)` → **nine** IDs: `0` centroid, `1..8` corners.
  The guide's Output line says `VectorIDs[0..4]` and then lists nine. The nine is right. Indices
  are taken from `LBound` and clamped to `UBound` so it cannot overrun either way.
- Every selected location becomes its own column and they all feed the same running peak, so
  "corner" means the worst corner of that element.
- `DataNeeded(8, setID)` narrows `Populate` to the elements actually being reported. With corner
  data that is dozens of columns, and the row loop is the whole cost of the tool. Optional by
  design — if it is refused the result is only slower, never wrong.

## The two measured facts underneath it

Both from `Check Stress Vectors` and `List Output Vectors` against a real model. Neither is
guessable, and either one wrong produces a report that is wrong while looking right.

**1. `VPP_BOT` is 2. The API guide says 3, and the guide is wrong.**
`ply=3` returns `FE_FAIL`; `ply=2` returns 9033, which Femap's own contour list titles *"Plate Bot
VonMises Stress"* (top is 7033). The guide prints these constants in two-column tables whose
right-hand values are shifted a row — the same block claims `VPL_2 = 3`, which is impossible.

This matters more than a normal off-by-one: bottom-surface plate stress usually **governs in
bending**, and `FE_FAIL` reads as "the solver never wrote it" rather than as a bug, so the wrong
constant silently drops the governing fibre.

**2. Columns are padded with exactly `0.0` on the wrong element class.**
`Populate` returns one row per element that has *any* requested result, not one row per element
the vector applies to. Measured: the plate columns carried 187,881 rows of exactly `0.0` —
precisely the solid count — and the solid columns carried 134,771, precisely the plate count.

So **every row is filtered by element class** before it can move a peak. Without it an all-solid
bucket asked for a plate column reports a confident `0.0`, and Min Principal reports `0.0` for any
wholly compressive bucket, because `0.0` beats every negative number.

## Blank is not zero

A blank cell means no element carrying that result was found in that bucket for that output set.
Zero is written only where an element really reported zero. The reader has to be able to tell
those apart, so the tool never fills an empty cell with 0.

## Design notes

- **One code path, four dimensions.** Every bucket dimension collapses to *a name plus an element
  set*: group → `Group.List(FGR_ELEM)`, property → `AddRule(id, FGD_ELEM_BYPROP)`, material →
  `AddRule(id, FGD_ELEM_BYMATL)` (which resolves the property indirection itself — no loop),
  element type → `AddRule(FET_*, FGD_ELEM_BYTYPE)`.
- **Both `FET_L_*` and `FET_P_*`.** The `L` means *linear*. Listing only that half silently drops
  every parabolic element, which in a real model is most of them.
- **Array lookups, not `IsAdded`.** Element class and bucket membership are resolved through
  arrays indexed by element ID, built once; `Set.IsAdded` is a COM call and the row loop runs
  rows × columns × output sets times.
- **Overlapping buckets are counted, not blocked.** An element lands in the last bucket that
  claims it. Peaks are maxima rather than sums, so overlap cannot double-count — but it can hide
  a peak, so the count is reported on the README sheet.
- **`iSet`, not `iS`.** WinWrap identifiers are case-insensitive, so `iS` *is* the `Is` operator
  and will not compile.

## Usage

Run it, choose the bucket dimension and where to read the stress, pick the output sets, then pick
the buckets. Excel opens on the README sheet, which records every setting and caveat that applies
to the numbers.
