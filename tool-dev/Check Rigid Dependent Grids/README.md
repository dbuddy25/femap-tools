# Check Rigid Dependent Grids

Model QA: finds rigid elements that fight over the same **dependent grid + DOF**. Nastran rejects a deck where the same `(grid, DOF)` is dependent on more than one rigid — this catches it before the solver does.

Femap calls grids **nodes**, so API terms below (`node(0)`, `GetNodeList`, node lists) are the Femap spelling of the same thing. Output says grid.

**Last updated:** 2026-08-17
**Status:** Written, **not yet run in Femap**. Two API readings are unverified — see *Verify this first*.

## Usage

- Run in Femap's API Programming window
- Choose **all rigids in the model** or **select the elements**
- Optionally group the offenders, and optionally dump raw data for verification
- Read the Messages window

## What It Does

The check is at **grid + DOF** level, not grid level. A grid may legally be dependent on one RBE2 for `123` and another for `456`; a grid-level check would report that as an error every time.

Femap has **one** rigid element type (`FET_L_RIGID` = 29). RBE2 and RBE3 are told apart by the `Elem.RigidInterpolate` flag, not by type:

| | `node(0)` | Node list (`GetNodeList`) |
|---|---|---|
| **RBE2** (`RigidInterpolate` False) | Independent, DOF in `Release(0,0..5)` | **Dependent** — DOF in `dof(6i..6i+5)` ← checked |
| **RBE3** (`RigidInterpolate` True) | **Dependent** / reference ← checked | Independent, carries the weights |

Entries are collected, sorted by grid, and each run of equal grid IDs is compared pairwise; any pair whose DOF masks overlap is a conflict.

## Output

- A Messages line per conflict: grid, the specific overlapping DOFs, and the two element IDs
- Optional group of the conflicting elements
- Summary with per-type counts and coverage caveats

## Verify this first

**The RBE3 arrangement is inferred, not documented.** The API guide never states which end of an RBE3 is dependent. It follows from two things: `feMeshConnectRigid` describes its source node as *"the Independent (RBE2) or **Dependent (RBE3)** node"*, and `GetNodeList`'s `weight` array is documented as *"for interpolation elements"* — so the weighted list is the RBE3 independent side, matching the Nastran card. The Elem property table still labels node slot 0 "Independent" because that table is written per-topology and knows nothing about `RigidInterpolate`.

Getting this backwards would check the **wrong end of every RBE3** and produce a clean-looking report — worse than not checking them at all.

**Run once with "Dump raw rigid data" ticked** against an RBE3 you know, and confirm from the Messages output that `node(0)` is the reference node and its `Release(0,*)` flags are the dependent DOF.

The dump also settles the second unknown: the guide calls the node-list `dof` values *"degree of freedom flags"* and gives six per node, but never says whether the value is `0/1` or something else. The tool treats **nonzero = dependent**, which is right for flags; the dump prints them raw.

As a backstop, if a type is found but yields **zero** dependent DOF entries, the summary says `SUSPECT:` loudly rather than reporting a clean model — that's the signature of a bad read, not a good deck.

## Notes

- **Coverage is RBE2 + RBE3 only** (topology `FTO_RIGIDLIST` = 13). RBAR, RROD and RBE1 store dependent DOF completely differently — `vRigidBarDOFs`, `RigidRodDependentDof`, and (for RBE1) a second node list that `GetNodeList` explicitly does not expose. Those are **counted and reported as unchecked** rather than skipped silently, so a clean result is never mistaken for full coverage.
- **There is no bulk getter for rigid node lists.** `GetAllArray` states outright that elements referencing node lists "will not have the nodes from their node lists in this array". So this is one `Get` + `GetNodeList` per rigid — unavoidable, and the reason the element set is built with `AddRule(FET_L_RIGID, FGD_ELEM_BYTYPE)` rather than by walking the model.
- **Femap has no built-in API check for this.** The full `feCheck*` family was reviewed; `feCheckConstraints` looks at the active constraint set only and never touches rigid elements.
- **Sorting, not bucketing.** Bucketing by grid ID would need an array sized to the largest grid ID in the model — fine at 50k grids, ugly on a renumbered model with IDs in the millions.
- **Group populate order matters:** `SetAdd` builds selection *rules* on the in-memory object, so `Put` must come **after** the adds, then `feGroupEvaluate`. Put first and the group comes out empty.
- Bitwise AND is done arithmetically (`MaskAnd`) rather than with WinWrap's `And`, which is a logical operator in a Boolean context — relying on it to act bitwise on Longs is how you get a silently empty report.
- Nothing is written to the model except the optional group.

## Possible extensions

- **Dependent grid with an SPC** — a grid dependent on a rigid *and* constrained in a constraint set is the same class of Nastran fatal.
- **Dependent-and-independent** — a grid dependent on one rigid and independent on another is legal but a chained-rigid smell.
- **RBAR / RROD / RBE1 coverage**, once `vRigidBarDOFs` and `RigidRodDependentDof` are confirmed against live elements. `FTO_RIGIDRODLINE2` / `FTO_RIGIDBARLINE2` have no documented numeric values and would need reading from `feConstants` at runtime.
- **Feed this into *Point RBE2 Spiders*** to screen candidate legs before building, which is the extension already logged there.
