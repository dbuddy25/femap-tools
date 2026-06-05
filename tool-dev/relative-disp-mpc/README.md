# relative-disp-mpc

**Status:** Spec only — not yet built (designed 2026-06-02, to try next week).

Custom tool to instrument **relative displacement** between two grid points by
generating MPC constraint equations. After solve, the relative displacement is
read directly as output — works in statics, modal, and frequency response (no
hand-subtracting result vectors).

## How it works

Pick node **A** and node **B**. For each chosen translational DOF, create a
**scalar point (SPOINT)** `S` and one constraint equation:

```
1.0·u_S  −  1.0·u_A(dof)  +  1.0·u_B(dof)  =  0     →     u_S = u_A − u_B
```

- The SPOINT is the **dependent** term (first term, coef +1, dof 1). It has no
  elements/SPCs, so it's free to be eliminated — exactly what an MPC needs.
- After solve, the SPOINT's displacement **is** the relative displacement of A
  w.r.t. B in that direction. Sign convention: **A minus B**.

### Why SPOINT instead of a new grid node?
For per-DOF relative displacement (no magnitude needed), SPOINTs win:
- Scalar points have only DOF 1 → **no free rotational DOFs**, so nothing extra
  to SPC. A real grid node would leave R1/R2/R3 floating (singular unless SPC'd).
- No geometry → no clutter, no accidental coincident-node merge.

A single grid node would only have been preferable if we wanted the **resultant
magnitude** for free (its total translation). We don't — per-DOF only.

## Workflow

1. Pick node **A**, pick node **B** (guard A ≠ B).
2. **Gate:** `outCSys(A) == outCSys(B)` **and** that CSys is **rectangular**.
   Else abort, naming the offending node/CSys.
   - Rectangular only for now — cylindrical/spherical is unusual here and adds a
     real trap (radial/θ directions are position-dependent, so "u_A(T1) − u_B(T1)"
     mixes directions even when both nodes share the CSys ID). Punted.
3. Draw **temporary color-coded axis arrows** (X=red, Y=green, Z=blue) labeled
   T1/T2/T3 at both A and B, so the directions are painfully clear. Hold during a
   confirm dialog; delete on close.
4. Dialog: **checkboxes T1/T2/T3** (labeled X/Y/Z), default all on; abort if none.
   Lets the user instrument only the directions they care about.
5. For each checked DOF: create SPOINT (`feNode`, `type=1`), then
   `feBCEqn.PutAll` with `[(S,1,+1), (A,dof,−1), (B,dof,+1)]`.
6. Clean up the temporary arrows.
7. **Bookkeeping:** group `RelDisp A<idA>-B<idB>` holding the SPOINTs + printed
   SPOINT→DOF map + sign convention. Warn if that group already exists (re-run guard).

## ID handling (the fiddly part)

Two independent ID spaces:

| Level | Femap | Nastran | Shared? |
|---|---|---|---|
| **Constraint set** = `feBCSet.Active` | the BC set the equations live in | the **MPC SID** the subcase selects (`MPC = n`) | **Shared** — all rel-disp equations ride one SID |
| **Equation ID** (`nID` in `PutAll`) | per-set slot, 1…N | (no equivalent — internal) | Unique per equation |

- All equations go in the **active constraint set** → they share one MPC SID, so
  the subcase's existing `MPC = n` selects them all (no extra case control). This
  matches the usual "one MPC ID for all relative displacement" expectation.
- Each measurement is its **own** equation (one dependent DOF per MPC). 3 DOFs on
  one pair = 3 equations/SPOINTs; they all share the set's SID.
- **Next equation ID:** set `bcEqn.SetID = activeSetID`, then `CountSet()` (counts
  only within that set). IDs run 1…N, so next free = `CountSet()+1`, incrementing.
  - Do **not** trust `NextEmptyID` (not documented as set-scoped).
  - Do **not** use `Set.AddAll(FT_BEQ)` (silently defaults to constraint Set 1).
- `PutAll` lists no duplicate-ID error → almost certainly **overwrites**; always
  feed a fresh `CountSet()+1`, never a guessed ID.

## Key API (verified against api.pdf)

- **Constraint equation:** `App.feBCEqn` →
  `PutAll(nID, nSetID, nDefID, nCount, vNode, vDof, vCoeff, eColor, nLayer)`.
  ≥2 terms required. `dof` is 1–6. Entity type constant: `FT_BEQ` (=20).
- **SPOINT:** ordinary `App.feNode` with `type = 1` (0=Node, 1=Scalar, 2=Extra).
- **Active constraint set:** `App.feBCSet.Active` (read/set). There is no
  `feConstraintGetActive`.
- **Count in set:** `bcEqn.SetID = n : bcEqn.CountSet()` — set-scoped.

## Open / to decide when building

- Active constraint set (default, rides existing `MPC = n`) vs a dedicated
  "RelDisp" set (cleaner to bulk-delete, but needs `MPCADD` or MPC re-selection).
  Leaning active-set for lower friction.
- Exact temporary-draw API for the arrows: dynamic-draw call if Femap exposes one,
  else temporary curves/text created then deleted (guaranteed fallback).
- Rotational DOFs (R1–R3) deliberately out of scope for v1.
