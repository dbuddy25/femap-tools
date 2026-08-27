# RBE2 CTE from Material

Set each RBE2's thermal expansion coefficient from the material it is actually attached to, across the whole model in one pass. Spiders that bridge two different CTEs are left alone and reported.

## Use case

A model full of bolt-hole spiders needs CTE on the rigids so thermal cases behave. Setting it by hand means checking what each spider lands on and typing a value per element — and getting it wrong on the ones that straddle a joint, which are exactly the ones that matter.

## What it does

1. Every RBE2 in the model by default, or a selection.
2. For each: dependent nodes → the non-rigid elements on those nodes → those elements' materials → `mval(36)` → `el.RigidThermalExpansion`.
3. One CTE found → written. More than one → skipped, reported, and grouped.

Nothing is written until the confirm dialog, and **Report only** skips the write entirely.

## Dependent nodes, not independent

On a hole spider or bolt pattern the dependent nodes are the legs sitting on the mesh; the independent centre node is usually free, or tied to a CBUSH, and carries no material. Reading the centre node would find nothing on most spiders and the wrong thing on the rest.

## RBE2 vs RBE3

Femap has one rigid element type (`FET_L_RIGID`). The two are told apart by `Elem.RigidInterpolate` — `False` = RBE2, `True` = RBE3 — not by type. Only RBE2 is touched. On an RBE3 the node roles are reversed (`node(0)` is the dependent one), so the same code would read the wrong end. RBE3s are counted and reported rather than silently passed over.

## Conflicts are by CTE value, not material ID

A spider landing on two different aluminium materials that happen to share a CTE is not ambiguous, and flagging it would bury the real conflicts under dozens of false ones. Materials are resolved to their CTE first, and only differing CTEs conflict.

The comparison is **relative**, with a tolerance you set on the dialog (default 0.1%). CTE values sit around `1e-5`, so any fixed epsilon is either meaningless on the large end or unmeetable on the small.

**Conflicted elements are skipped** — their existing CTE is not modified — and collected into a group. The tool never picks a winner: an RBE2 spanning a steel fitting and an aluminium skin is a real modelling decision, and quietly writing one of the two values would hide it. The competing values are printed per element:

```
  RBE2 4417 spans 2 CTEs:
      1.2600E-05   12 - A286 CRES
      2.3400E-05   4 - AL 7075-T7351
```

## The summary says what was applied, not just how many

A single "wrote 180 elements" total isn't checkable. The report breaks it down by the value actually applied, so it can be read against what you expect the model to contain:

```
  Elements examined:     214
  RBE2 resolved:         180
  CTE written:           180
  CTE applied:
    1.2600E-05     142 RBE2   (12 - A286 CRES)
    2.3400E-05      38 RBE2   (4 - AL 7075-T7351)
```

In **Report only** mode the same block appears as `CTE that WOULD be applied`, so a dry run tells you the whole outcome before anything is written.

## "No material found" is not a conflict

A spider attached only to other rigids, to mass elements, or to plot-only elements has nothing to read. That's reported on its own line, separately from conflicts — a spider with no material is a different problem from one with too many.

Rigids are stripped from each spider's attached-element list before materials are read, so a spider tied to another spider can't read a CTE *through* it.

## Implementation notes

- `Elem.GetGeomPropArray` returns `matlID` per element for a whole set in one call, so a whole-model run doesn't need a `Get` per attached element. It's called on a **separate** Elem object — calling it on the one holding the current RBE2 would overwrite it and the `Put` would write back the wrong element.
- `GetNodeList` takes **six** arguments (`listID, count, vNode, vFace, vWeight, vDof`). Writing it with five puts the weights in the DOF slot.
- Materials are read into an ID→CTE table once up front, so the per-element loop never touches a Material object.
- Group IDs and element IDs are pulled into arrays before the scan, so no Set cursor is live across a rule evaluation or a `Get`.

## Known gaps

- RBE3 is not handled at all.
- RBAR, RROD and RBE1 are not rigid-list topology and are counted as "not a rigid".
- Only isotropic `mval(36)` is read. An orthotropic material with direction-dependent CTE resolves to whatever sits in that slot.
- No `On Error` handler.
