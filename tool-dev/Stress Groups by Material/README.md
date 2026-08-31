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

## The optional all-elements group

Tick **"ALSO make an all-elements group"** and each material gets a second group named
`<material title> - All` holding *every* element of that material — no free-face restriction,
no rigid exclusion — **plus the rigid elements tied to that material**. In combined mode you
get one `<name> - All` instead.

Rigids need adding back explicitly because they carry no material of their own, so
`FGD_ELEM_BYMATL` never returns them; without this the display group would show the mesh with
all its connections missing. They are found by growing a copy of the material's elements one
layer with `AddConnectedElements()` and keeping only what is rigid. The count is reported.

The point is display: show the full model from the all-group, then contour stress only on the
stress group. The geometry stays visible without the artefact elements colouring the plot.

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
| Also make an all-elements group | off | A second unfiltered group per material, suffixed `- All`, for display |

### Two `feElementFreeFace` flags are hardcoded, deliberately

Both are fixed rather than exposed, because one of them only ever does the wrong thing and the
other essentially never does anything.

**`bParabolicEdges` = `True`.** It decides only whether face matching compares midside nodes as
well as corners. On a linear mesh it is inert. On a parabolic mesh the two settings agree unless
a seam has merged corner nodes but *separate* midside nodes — which normal meshing and normal
node merging do not produce. `True` is the safe end of a choice that almost never matters: it
treats an unmerged seam as the free surface it is, instead of quietly folding those solids away
as interior.

### Plates sitting on solid faces: both are kept

`feElementFreeFace` takes a `bPlaneElem` flag that makes a solid face count as **not** free when
a plate element sits on it — which drops the covered solid out of the group. That is the
opposite of what is wanted here, so the flag is hardcoded `False` and is deliberately **not**
exposed as an option.

With it `False`, only solid-to-solid sharing decides freeness, and an exterior face with a plate
on it has no solid behind it — so the solid stays. The plates of that material are added
wholesale anyway. **Both the plate and the solid underneath it end up in the group**, which is
the intent. Setting it `True` would silently delete the covered solids.

## Output

Per material, the Messages window reports the plate / beam / free-face-solid counts and how many
solids that material has in total, so the free-face fraction is visible.

In per-material mode each material also reports how many elements the rigid exclusion removed
and the group that was written. In combined mode each material reports its contribution and the
running union, then a final block gives the union total, the rigid removal, and the one group.

## The linear/parabolic trap

The `L` in `FET_L_SOLID` means **Linear**, not "element type". Femap gives linear and parabolic
elements separate type codes:

| Class | Linear | Parabolic |
|---|---|---|
| Solid | `FET_L_SOLID` (25) | `FET_P_SOLID` (26) |
| Plate | `FET_L_PLATE` (17) | `FET_P_PLATE` (18) |
| Membrane | `FET_L_MEMBRANE` (13) | `FET_P_MEMBRANE` (14) |
| Laminate plate | `FET_L_LAMINATE_PLATE` (21) | `FET_P_LAMINATE_PLATE` (22) |
| Laminate solid | `FET_L_LAMINATE_SOLID` | `FET_P_LAMINATE_SOLID` |
| Beam | `FET_L_BEAM` (5) | `FET_P_BEAM` |

A rule on `FET_L_SOLID` alone matches tet4 / wedge6 / brick8 and **silently misses every tet10,
wedge15 and brick20** — which is most of a real tet mesh. Every class in this tool lists both
halves of the pair. If you add an element class, add both.

To make the next version of this visible rather than silent, each material also prints an
**other/unclassified** count — everything of that material matching none of the three classes.
Masses, springs and rigids legitimately land there, so a non-zero number is normal; a number
in the thousands means a whole element family is being missed.

## Notes

- Group population uses **SetAdd before Put**, then `feGroupEvaluate` — `SetAdd` builds
  selection *rules* on the in-memory object, so putting first yields an empty group.
- Every group is written through `MakeGroup`, which allocates a **fresh** `femap.Group` object
  per group. Those rules are never cleared after a `Put`, so a reused object carries each
  earlier group's rules into the next one and the second group silently comes out holding the
  first group's elements too. Do not hoist that allocation out to save it.
- The free-face array is read via `LBound` rather than assuming a 0-based COM array.
- No entities are created, so the Group Automatic Add cleanup that other tools in this repo
  need does not apply here.
