# List Output Vectors

Diagnostic. Prints every **stress** output vector that actually exists in a chosen output set,
by ID and title.

*(file: `List Output Vectors.bas`)*

**Status:** Built 2026-09-01, untested. Read-only — nothing in the model is modified.

## Why

`Check Stress Vectors` asked `ResultsIDQuery` for nine plate/solid stress vectors in a real
model. Six resolved. All three **plate BOTTOM** vectors came back `FE_FAIL` — using `ply=3`,
which the API guide confirms is `VPP_BOT` (`zVecPlatePly`: TOP=0, MID=1, BOT=3).

`FE_FAIL` means "no such vector in this model". It does not say why, and two very different
causes produce it:

| Cause | Fix |
|---|---|
| The solver never wrote bottom-surface plate stress | Re-run the solve asking for it; the table cannot offer those columns today |
| The vectors exist but `ResultsIDQuery` isn't finding them under that enum combination | Address them by ID |

Bottom-surface stress usually **governs in bending**. A table that silently reports top-surface
only isn't a conservative simplification — it's a wrong answer that looks right. So the set gets
listed rather than guessed at.

## How to read the output

| You see | It means |
|---|---|
| A `Plate Bot ...` line | The vector exists. Note its ID — the table addresses it directly instead of via `ResultsIDQuery`. |
| No `Plate Bot ...` line anywhere | The solve didn't write it. The table offers top-surface only, and says so on the sheet. |

The probe states this verdict itself at the end rather than leaving it to be inferred from the list.

## Usage

Run it, pick one output set. Output goes to the Messages window. Filtered to titles containing
"STRESS" — an unfiltered dump of a real model runs to hundreds of displacement, force and strain
lines that have no bearing on the question.

## API note

`Results.VectorTitlesV2(nSetID, bIncludeID, minID, maxID, Count, listID, listTITLE)` — the last
three are out-params. `minID = maxID = 0` retrieves every vector in the set. `bIncludeID = False`
keeps the title clean; the ID is printed separately.
