# Femap Entity Objects

All entity objects share Common Entity Properties and Methods (Get, Put, First, Next,
Prev, Last, NextEmptyID, Count, CountSet, Delete, etc.). This file covers each entity
type's unique properties and creation patterns.

## Common Entity Properties (All Objects)

| Property | Type | Description |
|---|---|---|
| `ID` | Long (read-only) | Entity ID in database |
| `SetID` | Long | Parent set ID (for load/BC sub-entities) |
| `title` | String | Entity title/name |
| `color` | Long | Entity color |
| `layer` | Long | Layer assignment |
| `Exist` | Boolean (read-only) | Whether entity exists in database |

## Common Entity Methods (All Objects)

| Method | Signature | Description |
|---|---|---|
| `Get` | `Get(id) → Long` | Load entity from database |
| `Put` | `Put(id) → Long` | Save entity to database |
| `First` | `First() → Long` | Move to first entity, return ID |
| `Next` | `Next() → Long` | Move to next entity, return ID |
| `Prev` | `Prev() → Long` | Move to previous entity |
| `Last` | `Last() → Long` | Move to last entity |
| `NextEmptyID` | `NextEmptyID() → Long` | Next available ID |
| `Count` | `Count() → Long` | Total count of this entity type |
| `CountSet` | `CountSet(setID) → Long` | Count within a set |
| `Delete` | `Delete(id) → Long` | Delete entity from database |
| `GetAllArray` | See below | Bulk read all entities |
| `PutAllArray` | See below | Bulk write multiple entities |
| `GetLibrary` | `GetLibrary(file, id)` | Read from library file |
| `PutLibrary` | `PutLibrary(file, id)` | Write to library file |
| `Enumerate` | `Enumerate(set, vID)` | Fill set with all entity IDs |
| `CopyTo` | `CopyTo(id, newID)` | Copy entity |
| `Reset` | `Reset()` | Reset traversal cursor |

---

## Node Object (`App.feNode`)

### Properties

| Property | Type | Description |
|---|---|---|
| `x`, `y`, `z` | Double | Coordinates in definition CSys |
| `defCSys` | Long | Definition coordinate system ID (0=global) |
| `outCSys` | Long | Output coordinate system ID |
| `color` | Long | Display color |
| `layer` | Long | Layer |
| `type` | Long | Node type |
| `permBC(0..5)` | Long | Permanent boundary condition DOFs |

### Bulk Methods

```vb
' Read all nodes at once:
rc = nd.GetAllArray(setID, count, vID, vXYZ, vLayer, vColor, _
                    vType, vDefCSys, vOutCSys, vPermBC)
' setID=0 for all nodes, or a Set ID to filter

' Write multiple nodes:
rc = nd.PutAllArray(count, vID, vXYZ, vLayer, vColor, _
                    vType, vDefCSys, vOutCSys, vPermBC)
```

> `vXYZ` is a flat array: `[x1,y1,z1, x2,y2,z2, ...]` (3 values per node).

---

## Element Object (`App.feElem`)

### Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | Element type (use `FET_*` constants) |
| `topology` | Long | Topology (use `FTO_*` constants) |
| `propID` | Long | Property ID |
| `node(i)` | Long | Node IDs (0-based, up to max nodes for topology) |
| `orient` | Long | Orientation node/vector |
| `Release(i,j)` | Long | DOF releases |
| `offset(i)` | Double | Offsets |
| `formulation` | Long | Element formulation |
| `color` | Long | Display color |
| `layer` | Long | Layer |

### Key Methods

```vb
' Get/set node list for variable-node elements (RBE2, RBE3, etc.):
rc = el.GetNodeList(face, count, vNodes, vFaces, vWeights, vDOF)
rc = el.PutNodeList(face, count, vNodes, vFaces, vWeights, vDOF)

' Bulk methods:
rc = el.GetAllArray(setID, count, vID, vPropID, vType, vTopology, _
                    vLayer, vColor, vFormulation, vOrient, _
                    vOffsetFlag, vSect, vGeomID, vNodes)
```

### Common Element Types and Topologies

| Element | Type Constant | Topology Constant | Nodes |
|---|---|---|---|
| Rod | `FET_L_ROD` (2) | `FTO_LINE2` (2) | 2 |
| Bar | `FET_L_BAR` (5) | `FTO_LINE2` (2) | 2 |
| Beam | `FET_L_BEAM` (6) | `FTO_LINE2` (2) | 2 |
| CTRIA3 | `FET_L_PLATE` (20) | `FTO_TRIA3` (4) | 3 |
| CQUAD4 | `FET_L_PLATE` (20) | `FTO_QUAD4` (6) | 4 |
| CTRIA6 | `FET_P_PLATE` (21) | `FTO_TRIA6` (5) | 6 |
| CQUAD8 | `FET_P_PLATE` (21) | `FTO_QUAD8` (7) | 8 |
| CTETRA4 | `FET_L_SOLID` (25) | `FTO_TETRA4` (8) | 4 |
| CTETRA10 | `FET_P_SOLID` (26) | `FTO_TETRA10` (9) | 10 |
| CHEXA8 | `FET_L_SOLID` (25) | `FTO_BRICK8` (12) | 8 |
| CHEXA20 | `FET_P_SOLID` (26) | `FTO_BRICK20` (13) | 20 |
| Spring | `FET_L_SPRING` (15) | `FTO_LINE2` (2) | 2 |
| CBUSH | `FET_L_SPRING` (15) | `FTO_LINE2` (2) | 2 |
| Mass | `FET_L_MASS` (17) | `FTO_POINT1` (1) | 1 |
| RBE2 (Rigid) | `FET_L_RIGID` (29) | `FTO_RIGIDLIST` (15) | variable |
| RBE3 | `FET_L_RIGID` (29) | `FTO_RIGIDLIST2` (16) | variable |

### Creating an Element

```vb
Dim el As femap.Elem
Set el = App.feElem

el.type = FET_L_PLATE      ' Linear plate
el.topology = FTO_QUAD4    ' CQUAD4
el.propID = 1
el.node(0) = 1
el.node(1) = 2
el.node(2) = 3
el.node(3) = 4
rc = el.Put(el.NextEmptyID)
```

---

## Property Object (`App.feProperty`)

### Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | Property type (matches element types) |
| `matlID` | Long | Material ID (0 for Laminate/PCOMP — ply materials live on Layup) |
| `layupID` | Long | Layup ID (Laminate properties type 21/22 only) |
| `title` | String | Property title |
| `color` | Long | Display color |
| `pval(i)` | Double | Property values array (meaning depends on type) |
| `flag(i)` | Long | Property flags |

### Common `pval` Indices for Shell Properties (PSHELL)

> **WARNING:** The pval layout below was originally derived from the API PDF and
> **has not been verified index-by-index** against Femap for PSHELL. Use the diagnostic
> dump pattern from common-pitfalls.md #16 to confirm before relying on specific indices.

| Index | Description |
|---|---|
| `pval(0)` | Thickness (T) |
| `pval(1)` | MID2 (bending material, 0=same as matlID) |
| `pval(2)` | I (12*I/T^3 ratio, default=1.0) |
| `pval(3)` | MID3 (transverse shear material) |
| `pval(4)` | TS/T (shear thickness ratio) |
| `pval(5)` | — (see note) |
| `pval(6)` | Z1 (fiber distance 1) |
| `pval(7)` | NSM (non-structural mass) — **verified via mass scaling tool** |

### NSM `pval` Indices by Property Type (Verified)

Non-structural mass location in the `pval` array depends on property type. These
indices were verified through the part-mass-scale tool (density and NSM scaling with
`feMeasureMeshMassProp` verification).

| Property Types | Type Numbers | NSM Index |
|---|---|---|
| Rod, Bar, Tube | 1, 2, 3 | `pval(7)` |
| Beam | 5 | `pval(7)` = NSM_A, `pval(27)` = NSM_B |
| Curved Beam | 8 | `pval(7)` |
| Shear | 11, 12 | `pval(7)` |
| Membrane | 13, 14 | `pval(7)` |
| Bending Only | 15, 16 | `pval(7)` |
| Plate (PSHELL) | 17, 18 | `pval(7)` |
| Plane Strain | 19, 20 | `pval(7)` |
| Laminate (PCOMP) | 21, 22 | `pval(1)` |

Types without NSM (Link, Spring, DOFSpring, Gap, Solid, Mass, MassMatrix) are skipped.

### `pval` Indices for Mass Element (CONM2, Type 27) — API PDF p.5-1036

> **WARNING:** The API PDF table headers for this section are mislabeled — the column
> marked "LINK" is actually the Mass (Type 27) property. Match by Type number, not header.

| Index | Field | Description |
|---|---|---|
| `pval(0)` | — | (unused) |
| `pval(1)` | I11 (Ixx) | Mass moment of inertia about X |
| `pval(2)` | I21 (Ixy) | Product of inertia XY |
| `pval(3)` | I22 (Iyy) | Mass moment of inertia about Y |
| `pval(4)` | I31 (Izx) | Product of inertia ZX |
| `pval(5)` | I32 (Iyz) | Product of inertia YZ |
| `pval(6)` | I33 (Izz) | Mass moment of inertia about Z |
| `pval(7)` | Mx | Mass in X direction |
| `pval(8)` | Xoff | X offset in reference CS |
| `pval(9)` | Yoff | Y offset in reference CS |
| `pval(10)` | Zoff | Z offset in reference CS |
| `pval(11)` | My | Mass in Y direction |
| `pval(12)` | Mz | Mass in Z direction |

> **Note:** To create a mass with equal values in all directions, Mx, My, AND Mz must
> all be set — setting only Mx (as the GUI allows) is not sufficient via the API.

---

## Material Object (`App.feMaterial`)

### Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | Material type (0=Isotropic, 1=Orthotropic, etc.) |
| `title` | String | Material title |
| `mval(i)` | Double | Material values array |
| `color` | Long | Display color |

### Common `mval` Indices for Isotropic Material (API PDF p.5-875)

> **WARNING:** The `mval` array is NOT a compact layout. Indices are sparse and
> non-obvious. The table below was verified against actual Femap data. When in
> doubt, dump `mval(0)` through `mval(55)` and compare against known values.

| Index | Description |
|---|---|
| `mval(0)` | E[1] (Young's modulus, direction 1) |
| `mval(1)` | E[2] |
| `mval(2)` | E[3] |
| `mval(3)` | G[1] (Shear modulus, direction 1) — **NOT density** |
| `mval(4)` | G[2] |
| `mval(5)` | G[3] |
| `mval(6)` | NU[1] (Poisson's ratio, direction 1) |
| `mval(7)` | NU[2] |
| `mval(8)` | NU[3] |
| `mval(49)` | **DENSITY (RHO)** — mass density |

For isotropic materials, only direction 1 values are populated (mval(0), mval(3), mval(6)).
Indices 9–48 and 50+ cover thermal expansion, TREF, damping, stress/strain limits, etc.

---

## Coordinate System Object (`App.feCSys`)

### Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | 0=Rectangular, 1=Cylindrical, 2=Spherical |
| `origin(0..2)` | Double | Origin x, y, z |
| `dirz(0..2)` | Double | Z-axis direction |
| `dirx(0..2)` | Double | X-axis direction |
| `title` | String | Title |

---

## OutputSet Object (`App.feOutputSet`)

### Properties

| Property | Type | Description |
|---|---|---|
| `title` | String | Output set title |
| `value` | Double | Associated value (time, frequency, etc.) |
| `analysis` | Long | Analysis type |
| `notes` | String | Notes |

---

## Group Object (`App.feGroup`)

### Properties

| Property | Type | Description |
|---|---|---|
| `title` | String | Group title |
| `layer` | Long | Default layer |
| `Active` | Boolean | Whether group is active |

### Methods (Unique to Group)

```vb
' Add entities by rule:
rc = gp.AddRule(entityID, ruleType)    ' Same FGD_ rules as Set

' Check if entity is in group:
inGroup = gp.IsEntityInGroup(entityType, entityID)

' Operations:
rc = gp.AddRelatedEntities()    ' Add related entities
rc = gp.Condense()              ' Remove unreferenced entities
```

---

## LoadSet Object (`App.feLoadSet`)

### Properties

| Property | Type | Description |
|---|---|---|
| `title` | String | Load set title |

---

## BCSet Object (`App.feBCSet`)

### Properties

| Property | Type | Description |
|---|---|---|
| `title` | String | Constraint set title |

---

## View Object (`App.feView`)

### Key Properties

| Property | Type | Description |
|---|---|---|
| `OutputSet` | Long | Active output set ID |
| `DeformDataV2` | Long | Deformation vector ID (V2) |
| `Deformed` | Long | 0=Off, 1=Deformed, 2=Animate |
| `Mode` | Long | Display mode |
| `ContourStyle` | Long | Contour display style |

---

## Curve Object (`App.feCurve`)

### Key Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | Curve type |
| `startPt` | Long | Start point ID |
| `endPt` | Long | End point ID |
| `solidID` | Long | Parent solid ID |

### Key Methods

```vb
rc = crv.Tangent(param, vTangent)   ' Get tangent at parameter
rc = crv.Normal(param, vNormal)     ' Get normal at parameter
rc = crv.XYZAtParam(param, x, y, z) ' Get point at parameter
length = crv.Length()                ' Get curve length
```

---

## Surface Object (`App.feSurface`)

### Key Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | Surface type |
| `solidID` | Long | Parent solid ID |

### Key Methods

```vb
rc = surf.Normal(u, v, vNormal)     ' Get normal at parameters
rc = surf.XYZAtParam(u, v, x, y, z) ' Get point at parameters
area = surf.Area()                    ' Get surface area
```

---

## Text Object (`App.feText`)

### Properties

| Property | Type | Description |
|---|---|---|
| `x`, `y`, `z` | Double | Position |
| `text` | String | Display text |
| `color` | Long | Text color |
| `size` | Double | Text size |

---

## GFXArrow, GFXLine, GFXPoint, GFXQuad4, GFXTria3

User-defined graphics objects for annotations and custom visualization.
Created via `App.feGFXArrow`, `App.feGFXLine`, etc.

Each has position/direction properties and standard Get/Put methods.

---

## AnalysisCase / AnalysisMgr Objects

### AnalysisCase (`App.feAnalysisCase` or via AnalysisMgr)

Controls individual analysis case settings (load sets, constraint sets,
output requests, solver options).

### AnalysisMgr (`App.feAnalysisMgr`)

Manages analysis studies and execution. Key methods:

```vb
rc = am.Analyze(caseID)         ' Run analysis
rc = am.AnalyzeAll()            ' Run all cases
```

---

## Layup Object (`App.feLayup`)

Stores ply stacking definitions for Laminate (PCOMP) properties. Each ply has its own
material, thickness, and orientation. Access via `pr.layupID` on Laminate properties
(type 21/22).

### Properties

| Property | Type | Description |
|---|---|---|
| `NumberOfPlys` | Long (read-only) | Number of plies in the layup |
| `matlID(ply)` | Long | Material ID for ply (0-based index) |
| `thickness(ply)` | Double | Ply thickness |
| `angle(ply)` | Double | Ply orientation angle |
| `title` | String | Layup title |

### Usage Pattern

```vb
Dim ly As femap.Layup
Set ly = App.feLayup

' Get layup from a laminate property
Dim pr As femap.Prop : Set pr = App.feProp
rc = pr.Get(propID)
If rc = FE_OK And pr.layupID > 0 Then
    rc = ly.Get(pr.layupID)
    If rc = FE_OK Then
        Dim ply As Long
        For ply = 0 To ly.NumberOfPlys - 1
            App.feAppMessage(FCM_NORMAL, "Ply " + Str$(ply) + _
                ": matlID=" + Str$(ly.matlID(ply)))
        Next ply
    End If
End If
```

> **Note:** For Laminate properties (type 21/22), `pr.matlID` is **not used** (API PDF
> p.5-1017 documents it as 0). Ply materials must be read from the Layup object via
> `pr.layupID`.

---

## Connection Objects

### ConnProp (`App.feConnProp`)
Connection property definitions (bolt, weld, fastener, glue, etc.).

### ConnectionRegion (`App.feConnectionRegion`)
Connection region definitions linking surfaces or elements.

> **Factory method status:** `App.feConnectionRegion` is believed correct based on the
> API PDF but **has not been verified** in Femap. The shorter form `App.feConnRegion`
> was tested and **FAILED** ("expecting a valid data type"). Use `feConnectionRegion`
> and test before relying on it in production scripts.

#### Key Properties

| Property | Type | Description |
|---|---|---|
| `type` | Long | Connection region type |
| `masterID` | Long | Master entity ID |
| `MassNSM` | Double | Non-structural mass on this connection region |

> **Note:** Connection Region NSM (`MassNSM`) **is included** in `feMeasureMeshMassProp`
> measurements. If scaling mass, Connection Region NSM may need manual adjustment since
> Connection Regions are model-level entities not tied to specific element selections.

### Connection (`App.feConnection`)
Individual connection instances.

---

## Function Object (`App.feFunction`)

Stores tabular data (x-y pairs) for load time histories, material curves, etc.

```vb
Dim fn As femap.Function
Set fn = App.feFunction
fn.title = "Time History"
fn.type = 0
' Add data points via methods
rc = fn.Put(fn.NextEmptyID)
```
