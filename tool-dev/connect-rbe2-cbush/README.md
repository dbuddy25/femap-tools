# connect-rbe2-cbush

**Status:** Built — pending in-Femap testing.

Custom tool to create **CBUSH fastener elements between two parts**. Each part is a
group containing RBE2 bolt-hole spiders (e.g. from `make-rbe2-from-holes`). The tool
matches RBE2s whose independent (center) nodes are near each other across the two
groups, lets the user **visually verify** the proposed connections, then builds one
CBUSH per chosen location between the two center nodes.

## How it works

1. **One settings window** — every global choice is on a single dialog: **Group 1**,
   **Group 2**, **max-gap tolerance**, **orientation CSys**, **PBUSH Type 1
   (fasteners)**, **PBUSH Type 2 (shear pins**, with a "(none)" option for a
   single-type joint**)**, and the **output group** ("(create new)" + a name box, or an
   existing group). All lists are enumerated up front (groups, CSys incl. global 0,
   PBUSH = property `type = 6`).
2. **Match** — each group's elements are scanned for RBE2s (`type = FET_L_RIGID`,
   `topology = FTO_RIGIDLIST`; center = `el.node(0)`). Each group-1 RBE2 is matched to
   the nearest *unused* group-2 RBE2 within tolerance (greedy, 1-to-1). A numbered list
   (RBE2 IDs + gap) prints to the messages window.
3. **Visual check + assignment** — the matched RBE2s are **isolated in the view**
   (`feViewShow2`) so the user sees the locations. Then:
   - **Single PBUSH:** confirm → **all** matches connect with Type 1. No model picking.
   - **Two PBUSH:** **one graphical pick** of the shear-pin locations (group-1 RBE2s);
     those get Type 2, the rest get Type 1. Cancelling the picker = all fasteners.
4. **Create + group** — one CBUSH per match (zero-length lines for coincident nodes),
   the single orientation CSys applied to every element via `SetSpringOrient`. Full
   element visibility is restored, and the output group is populated with the CBUSHes
   + the PBUSH property/properties used + the orientation CSys.

Net interactions: **one settings window + one confirm** (single type), plus **one
model selection** only when a second property type is used.

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
