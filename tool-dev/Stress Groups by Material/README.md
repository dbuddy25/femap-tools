# Stress Groups by Material

Builds groups holding the elements whose stress is worth reporting — and, just as
importantly, leaving out the elements whose stress is an artefact.

*(file: `Stress Groups by Material.bas`)*

**Status:** Built 2026-08-31, untested. Creates groups; changes nothing else in the model.

## Two modes

| Mode | Result | Named |
|---|---|---|
| **One group per material** (default) | A group for each material you selected | the material title, with nothing added |
| **One combined group** (checkbox) | The union of every selected material — pick three, get one group | exactly the name you type |

In combined mode the rigid exclusion is applied **once to the union** rather than per material.
Removal is idempotent so the answer is the same either way, but doing it at the end means the
per-material lines printed along the way are pre-exclusion contributions — which is what makes
them add up to the union total.

## The recipe

For each material you select:

| | |
|---|---|
| **+** | All **plate** elements of that material (plate, laminate, membrane) |
| **+** | All **beam** elements of that material (beam, bar, rod) |
| **+** | Only the **free-face solids** of that material |
| **−** | Every element **directly attached to a rigid** |

## Why only free-face solids

In a solid, peak stress lives on the exterior surface — the free face — where there is no
through-thickness constraint. Interior solids are along for the ride. Reporting them dilutes
the summary and buries the number you actually want.

## The silent trap: free faces are computed over the whole solid mesh

If free faces were computed from only *one* material's solids, then every face where that
material is bonded to a **different** material's solid would look free — because from inside
that one material's subset, there is nothing on the other side. Those faces are interior. The
stress there is not free-surface stress.

So `feElementFreeFace` is called **once** against every solid in the model, and the result is
intersected with each material afterwards.

> Do not "optimise" this by moving the call inside the per-material loop. It would run faster
> and be wrong — and wrong specifically at material interfaces, which is exactly where someone
> reading this report is looking.

## Why elements at rigids come out

An RBE2/RBE3 imposes infinite stiffness on the nodes it touches. Elements sharing those nodes
report a stress concentration that is a modelling artefact, not a load path — and it is
routinely the model-wide maximum, so it hijacks every peak-stress summary it appears in.

**One** element layer is removed: the elements directly tied to a rigid. The **second** element
away is kept, being the first ring far enough out for the artefact to have decayed.

### Tuning the exclusion depth

`Set.AddConnectedElements()` grows a set by exactly one element layer — it adds every element
sharing at least one node with the set. Section 4 calls it **once**. Call it twice to remove two
layers. That single call is the whole knob.

## Options

| Option | Default | Effect |
|---|---|---|
| Group name | `Stress` | **Combined mode only.** Per-material groups are named for their material, with nothing added. |
| Combine into one group | off | Union of all selected materials into a single named group |
| Exclude elements attached to rigids | on | The exclusion above. Off leaves the artefact elements in. |
| Plate elements cover a solid face | off | `bPlaneElem` — a solid face with a plate on it is not free. Turn on if you skin solids with plates. |
| Consider midside nodes | on | `bParabolicEdges` — matters on parabolic (tet10 / brick20) meshes. |

When the plate-cover option is on, the plates are added to the set handed to
`feElementFreeFace`, because the flag only counts plane elements that are actually *in* that
set. Any plate that comes back owning a free face is then stripped, since only solids belong in
the result.

## Output

Per material, the Messages window reports the plate / beam / free-face-solid counts and how many
solids that material has in total, so the free-face fraction is visible.

In per-material mode each material also reports how many elements the rigid exclusion removed
and the group that was written. In combined mode each material reports its contribution and the
running union, then a final block gives the union total, the rigid removal, and the one group.

## Notes

- Group population uses **SetAdd before Put**, then `feGroupEvaluate` — `SetAdd` builds
  selection *rules* on the in-memory object, so putting first yields an empty group.
- The free-face array is read via `LBound` rather than assuming a 0-based COM array.
- No entities are created, so the Group Automatic Add cleanup that other tools in this repo
  need does not apply here.
