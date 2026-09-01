# Peak Stress Table

Peak stress per bucket — **group, property, material or element type** — with **one column per
output set**, written to Excel. Read-only on the model.

*(file: `Peak Stress Table.bas`)*

**Status:** Built 2026-09-01, untested.

## What it reports

Three measures per bucket per output set:

| Measure | Envelope direction |
|---|---|
| Max von Mises | up |
| Max Principal (peak tension) | up |
| Min Principal (peak compression) | **down** — the governing value is the most negative |

Each is enveloped over the **plate TOP fibre, plate BOTTOM fibre and solid centroid**, so a bucket
holding both plates and solids reports one governing number rather than three partial ones.

## Sheets

| Sheet | Contents |
|---|---|
| `Von Mises` / `Max Principal` / `Min Principal` | Buckets down, output sets across. The governing cell in each row is tinted and bolded. |
| `Governing` | Per bucket, the envelope across *all* sets for each measure, plus **which set** and **which element** produced it. |
| `README` | Model, options, and every caveat that applies to the numbers. |

## The two measured facts it is built on

Both came from `Check Stress Vectors` and `List Output Vectors` run against a real model. Neither
is guessable, and either one wrong produces a report that is wrong while looking right.

**1. `VPP_BOT` is 2. The API guide says 3, and the guide is wrong.**
`Plate(VPV_STRESS, VPT_VON_MISES, 3, 0)` returns `FE_FAIL`. `ply=2` returns **9033**, which
Femap's own contour list titles *"Plate Bot VonMises Stress"* (top is 7033). The guide prints
these constants in two-column tables whose right-hand values are shifted a row — the same block
claims `VPL_2 = 3`, which is impossible.

This matters more than a normal off-by-one: bottom-surface plate stress usually **governs in
bending**, and `FE_FAIL` reads as "the solver never wrote it" rather than as a bug, so the wrong
constant silently drops the governing fibre.

**2. Columns are padded with exactly `0.0` on the wrong element class.**
`Populate` returns one row per element that has *any* requested result, not one row per element
the vector applies to. In the measured model the plate columns carried 187,881 rows of exactly
`0.0` — precisely the solid count — and the solid columns carried 134,771, precisely the plate
count.

So **every row is filtered by element class** before it can move a peak. Bucket membership alone
is not enough. Without the filter an all-solid bucket asked for a plate column reports a confident
`0.0`, and a Min Principal column reports `0.0` for any bucket whose real values are all
compressive — because `0.0` beats every negative number.

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
- **Array lookups, not `IsAdded`.** The row loop runs rows × 9 columns × output sets times;
  `Set.IsAdded` is a COM call. Element class and bucket membership are both resolved through
  arrays indexed by element ID, built once.
- **Overlapping buckets are counted, not blocked.** An element lands in the last bucket that
  claims it. Peaks are maxima rather than sums, so overlap cannot double-count — but it can hide
  a peak, so the count is reported on the README sheet.

## Usage

Run it, choose the bucket dimension, pick the output sets, then pick the buckets. Excel opens on
the `README` sheet.
