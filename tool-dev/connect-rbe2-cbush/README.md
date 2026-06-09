# connect-rbe2-cbush

**Status:** Built — pending in-Femap testing.

Custom tool to create **CBUSH fastener elements between two parts**. Each part is a
group containing RBE2 bolt-hole spiders (e.g. from `make-rbe2-from-holes`). The tool
matches RBE2s whose independent (center) nodes are near each other across the two
groups, lets the user **visually verify** the proposed connections, then builds one
CBUSH per chosen location between the two center nodes.

## How it works

1. **Pick two groups** (Part A, Part B). Each group's elements are scanned for RBE2s
   (`type = FET_L_RIGID`, `topology = FTO_RIGIDLIST`); the independent node
   (`el.node(0)`) and its global coordinates are recorded.
2. **Match** — enter a max-gap tolerance. Each group-1 RBE2 is matched to the nearest
   *unused* group-2 RBE2 within tolerance (greedy, 1-to-1). Each match is a candidate
   connection with a gap = center-node distance.
3. **Visual check with numbers** — a numbered list of candidate pairs (with RBE2 IDs
   and gap distances) is printed to the messages window, and the view is **isolated to
   the matched RBE2s** (`feViewShow2`) so the user can see exactly which spiders will
   be connected. (Connection lines aren't used: bolt center nodes are typically
   coincident, so a line would be zero-length/invisible.) Full element visibility is
   restored at the end.
4. **Pick one orientation coordinate system** applied to every CBUSH.
5. **Per-type rounds** — for each connection type the user picks a **PBUSH property**
   then graphically selects which group-1 RBE2s get it; a CBUSH is created for each.
   Repeat for the next type (fasteners, then shear pins, …) until done. This is how
   two PBUSH types live in one joint.
6. **Output group** — a new named group, or append to an existing group. It receives
   the CBUSH elements, the PBUSH property/properties used, and the orientation CSys.

### CBUSH creation

```
cb.type     = FET_L_SPRING      ' 6
cb.topology = FTO_LINE2         ' 0 (2-node line)
cb.node(0)  = group1 center node
cb.node(1)  = group2 center node
cb.propID   = chosen PBUSH
cb.SetSpringOrient(3, csysID, 0,0,0)   ' 3 = FESO_ELCID: orient by CSys on element
cb.Put(NextEmptyID)
```

Orientation by coordinate system is what makes a **zero-length** CBUSH valid (the two
center nodes may be coincident at the joint interface). The CSys is applied to every
created element.

## Key API (verified against api.pdf)

| Need | Call |
|---|---|
| Pick a group / property / CSys / elements | `Set.Select(FT_GROUP / FT_PROP / FT_CSYS / FT_ELEM, True, title)` → selected ID via `Set.First()` |
| Elements in a group | `gp.Get(id)` → `gp.List(8)` (copy into a private Set immediately — it is volatile) |
| Detect RBE2 | `el.type = FET_L_RIGID And el.topology = FTO_RIGIDLIST`; center = `el.node(0)` |
| Node coords | `nd.Get(id)` → `nd.x/y/z` (always global rectangular) |
| CBUSH | `FET_L_SPRING` (6) / `FTO_LINE2` (0), `node(0)/node(1)`, `propID` |
| CBUSH orientation | `el.SetSpringOrient(3, csysID, 0,0,0)` (alt: `SpringNoOrient=False : SpringUseCID=True : SpringCID=csysID`) |
| PBUSH identify | Prop `type = 6` with `cbush = 1` |
| Verify visually | `feViewShow2(FT_ELEM, setID, autoscale)` isolates the matched RBE2s; restore with `feViewShow2(FT_ELEM, allElemsSet, False)` (a Set `AddAll(FT_ELEM)`) |
| Group contents | `gp.SetAdd(FT_ELEM / FT_PROP / FT_CSYS, setID)` **before** `gp.Put(id)` (SetAdd builds rules; Put commits), then `feGroupEvaluate(-id, True)` to materialize. A group can hold all three types. |

## Notes / assumptions

- Each part's fastener points must be **RBE2s**; their independent nodes are the
  connection points.
- Matching is **1-to-1** within the tolerance; the visual check + manual per-type
  selection are the real filter, so a generous tolerance is fine.
- The two center nodes are connected directly (no new nodes); coincident nodes give a
  zero-length CBUSH oriented by the chosen CSys.
- A **new** output group will contain only the CBUSHes + PBUSH(es) + orientation CSys.
