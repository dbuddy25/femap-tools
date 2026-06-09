# Ground Interface by CBUSH

*(file: `Ground Interface by CBUSH.bas`)*

**Status:** Built — pending in-Femap testing.

A grounding variant of [Connect Groups by CBUSH](../Connect%20Groups%20by%20CBUSH/README.md).
Ties one part's RBE2 bolt-hole spiders to a **single ground interface node** through
fasteners — e.g. to apply a boundary condition or attach the part to the rest of a
model at one point.

## How it works

1. **One settings window:** source **Group** (dropdown), **near-plane tolerance**,
   orientation **CSys**, **PBUSH Type 1 (fasteners)** and **Type 2 (shear pins**, with
   a "(none)" option**)**, two output-group pickers (**CBUSH group** and **Ground RBE2
   group**, each "(create new)" + a name box, or an existing group), and an optional
   **CTE block** for the ground RBE2 (apply on/off, from a material's `mval(36)` or a
   typed value).
2. **Pick a plane** (`fePlanePick`).
3. **Find participants:** RBE2s in the group (`type = FET_L_RIGID`,
   `topology = FTO_RIGIDLIST`) whose center node `Ci = el.node(0)` is within the
   tolerance perpendicular distance of the plane. The found RBE2s are **isolated** in
   the view (no zoom) as a visual check.
4. **Assign:** single PBUSH → all participants are fasteners; two PBUSH → one graphical
   pick of the shear-pin RBE2s (the rest are fasteners).
5. **Build** (per participant): a new node `Gi` coincident with `Ci`, and a
   **zero-length CBUSH** `Ci–Gi` (PBUSH + CSys orientation). All `Gi` become the
   dependents of a **new ground RBE2** whose independent node `G0` is the centroid of
   the participating centers **projected onto the plane**. Ground RBE2 DOF = **123456**,
   optional CTE on `RigidThermalExpansion`.
6. **Two output groups:**
   - **CBUSH group** — the CBUSH elements + PBUSH(es) used + orientation CSys, **no
     nodes**.
   - **Ground RBE2 group** — the ground RBE2 element + its nodes (`G0` + all `Gi`).

## Topology / why a new node `Gi`

`Ci` is already the independent node of its hole spider, so it can't also be an RBE2
dependent. The CBUSH (`Ci–Gi`) carries the fastener compliance; the ground RBE2 rigidly
ties each `Gi` to `G0`. Load path: BC/load at `G0` → rigid → `Gi` → CBUSH (fastener
stiffness) → `Ci` → hole spider.

```
Ci (model center) --CBUSH(zero-length, PBUSH)--> Gi --\
                                                       >-- RBE2(123456) --> G0 (ground interface)
... one per participating RBE2 ...                  --/
```

## Key API

| Need | Call |
|---|---|
| Pick plane | `fePlanePick(title, plBase, plNormal, plAxis)` (Variant out-args) |
| Distance to plane | `d = abs((Ci - plBase) . n_hat)` |
| CBUSH | `FET_L_SPRING`/`FTO_LINE2`, `node(0)/node(1)`, `propID`, `SetSpringOrient(3, csys, 0,0,0)` |
| Ground RBE2 | `FET_L_RIGID`/`FTO_RIGIDLIST`, `node(0)=G0`, `Release(0,0..5)=1`, `PutNodeList(0, n, vGi, vFaces, vWeights, vDOF=all 1)`; optional `RigidThermalExpansion` |
| Material CTE | `mtl.Get(id)` → `mval(36)` |
| Groups | `SetAdd(FT_ELEM / FT_PROP / FT_CSYS / FT_NODE, setID)` **before** `Put`, then `feGroupEvaluate(-id, True)`. CBUSH group omits `FT_NODE` → no nodes. |

## Notes

- "Near the plane" = perpendicular distance ≤ the entered tolerance (model units).
- Attaching a CBUSH to an RBE2-dependent node (`Gi`) is intentional and valid; confirm
  no solver complaint on your specific deck.
- Same WinWrap/Femap gotchas as the other tools: `SetAdd` before `Put`; case-insensitive
  identifiers; no `Dim`/`ReDim` joined by colon; `fePlanePick` out-args are `Variant`.
