# Loads and Constraints

## Load Creation Workflow

Creating loads requires three objects in order:

1. **LoadSet** — the container for loads (like a folder)
2. **LoadDefinition** — defines the load type within a set
3. **LoadMesh** (or LoadGeom, LoadNTemp, LoadETemp) — the actual load data

```
LoadSet (container)
  └── LoadDefinition (type definition)
       └── LoadMesh / LoadGeom entries (individual loads)
```

### Complete Example: Create a Force Load

```vb
Sub Main
    Dim App As femap.model : Set App = feFemap()

    ' 1. Create Load Set
    Dim ls As femap.LoadSet : Set ls = App.feLoadSet
    ls.title = "Applied Forces"
    rc = ls.Put(ls.NextEmptyID)
    Dim lsID As Long : lsID = ls.ID

    ' 2. Create Load Definition
    Dim ld As femap.LoadDefinition : Set ld = App.feLoadDefinition
    ld.setID = lsID
    ld.title = "Nodal Forces"
    ld.loadType = FLT_NFORCE
    rc = ld.Put(ld.NextEmptyID)
    Dim ldID As Long : ldID = ld.ID

    ' 3. Create individual loads
    Dim lm As femap.LoadMesh : Set lm = App.feLoadMesh
    lm.setID = lsID
    lm.LoadDefinitionID = ldID
    lm.type = FLT_NFORCE
    lm.nodeID = 42             ' Node to apply load
    lm.dof(0) = False          ' Tx - not loaded
    lm.dof(1) = False          ' Ty - not loaded
    lm.dof(2) = True           ' Tz - loaded
    lm.dof(3) = False          ' Rx
    lm.dof(4) = False          ' Ry
    lm.dof(5) = False          ' Rz
    lm.load(2) = -1000.0       ' Force value in Z direction
    rc = lm.Put(-1)            ' -1 for auto-ID
End Sub
```

---

## LoadMesh Object (`App.feLoadMesh`)

Mesh-based loads applied to nodes or elements.

### Key Properties

| Property | Type | Description |
|---|---|---|
| `setID` | Long | Parent load set ID |
| `LoadDefinitionID` | Long | Parent load definition ID |
| `type` | Long | Load type (`FLT_*` constant) |
| `nodeID` | Long | Node ID for nodal loads |
| `elemID` | Long | Element ID for element loads |
| `dof(0..5)` | Boolean | DOF flags (Tx, Ty, Tz, Rx, Ry, Rz) |
| `load(0..5)` | Double | Load values per DOF |
| `CSys` | Long | Coordinate system for load direction |
| `expanded` | Boolean | Whether geometrically expanded |

### Load Types (FLT_* Constants)

| Constant | Description |
|---|---|
| `FLT_NFORCE` | Nodal force |
| `FLT_NMOMENT` | Nodal moment |
| `FLT_NDISPLACEMENT` | Enforced displacement |
| `FLT_NVELOCITY` | Enforced velocity |
| `FLT_NACCELERATION` | Enforced acceleration |
| `FLT_NBODY` | Body load (gravity) |
| `FLT_NHEATGEN` | Nodal heat generation |
| `FLT_EPRESSURE` | Elemental pressure |
| `FLT_EHEATFLUX` | Elemental heat flux |
| `FLT_ECONVECTION` | Elemental convection |
| `FLT_ERADIATION` | Elemental radiation |

### Bulk Load Creation with PutArray / PutAllArray

For multiple loads at once (much faster than looping Put):

```vb
' PutArray — uses pre-set LoadDefinitionID
lm.setID = lsID
lm.LoadDefinitionID = ldID
rc = lm.PutArray(count, vNodeIDs, vTypes, vDOF, vLoads)

' PutAllArray — specifies LoadDefinitionID as parameter
rc = lm.PutAllArray(lsID, ldID, count, vNodeIDs, vTypes, vDOF, vLoads)
```

---

## LoadGeom Object (`App.feLoadGeom`)

Geometry-based loads applied to curves, surfaces, or solids. These get expanded
to mesh-based loads during analysis.

### Key Properties

| Property | Type | Description |
|---|---|---|
| `setID` | Long | Parent load set ID |
| `geomID` | Long | Geometry entity ID |
| `geomType` | Long | `FT_CURVE`, `FT_SURFACE`, `FT_SOLID` |
| `type` | Long | Load type |
| `dof(0..5)` | Boolean | DOF flags |
| `load(0..5)` | Double | Load values |
| `CSys` | Long | Coordinate system |

---

## Temperature Loads

### LoadNTemp (`App.feLoadNTemp`) — Nodal Temperatures

```vb
Dim nt As femap.LoadNTemp : Set nt = App.feLoadNTemp
nt.setID = lsID
nt.nodeID = 42
nt.temp = 100.0          ' Temperature value
rc = nt.Put(-1)
```

### LoadETemp (`App.feLoadETemp`) — Elemental Temperatures

```vb
Dim et As femap.LoadETemp : Set et = App.feLoadETemp
et.setID = lsID
et.elemID = 100
et.temp = 150.0
rc = et.Put(-1)
```

---

## Constraint Creation Workflow

Similar to loads: BCSet → BCNode (or BCGeom).

### BCSet Object (`App.feBCSet`)

```vb
Dim bs As femap.BCSet : Set bs = App.feBCSet
bs.title = "Fixed Supports"
rc = bs.Put(bs.NextEmptyID)
Dim bsID As Long : bsID = bs.ID
```

### BCNode Object (`App.feBCNode`) — Nodal Constraints

```vb
Dim bc As femap.BCNode : Set bc = App.feBCNode
bc.setID = bsID
bc.nodeID = 1
bc.dof(0) = True    ' Fix Tx
bc.dof(1) = True    ' Fix Ty
bc.dof(2) = True    ' Fix Tz
bc.dof(3) = True    ' Fix Rx
bc.dof(4) = True    ' Fix Ry
bc.dof(5) = True    ' Fix Rz
rc = bc.Put(-1)     ' Auto-ID
```

### BCGeom Object (`App.feBCGeom`) — Geometric Constraints

Applied to geometry (points, curves, surfaces). Expanded to nodal constraints
during analysis.

```vb
Dim bg As femap.BCGeom : Set bg = App.feBCGeom
bg.setID = bsID
bg.geomID = surfaceID
bg.geomType = FT_SURFACE
bg.dof(0) = True : bg.dof(1) = True : bg.dof(2) = True
bg.dof(3) = True : bg.dof(4) = True : bg.dof(5) = True
rc = bg.Put(-1)
```

### Constraint Equations (BCEqn)

```vb
Dim eq As femap.BCEqn : Set eq = App.feBCEqn
eq.setID = bsID
' Set equation terms...
rc = eq.Put(-1)
```

---

## Walking Through Existing Loads

Iterate through all loads in all load sets:

```vb
Dim LdSet As femap.LoadSet : Set LdSet = App.feLoadSet
Dim Ld As femap.LoadMesh : Set Ld = App.feLoadMesh

While (LdSet.Next())
    Ld.setID = LdSet.ID
    Ld.ID = -1                ' Start before first load
    While (Ld.Next())
        ' Process load: Ld.type, Ld.nodeID, Ld.load(), etc.
    Wend
Wend
```

## Walking Through Existing Constraints

```vb
Dim BCSet As femap.BCSet : Set BCSet = App.feBCSet
Dim BC As femap.BCNode : Set BC = App.feBCNode

While (BCSet.Next())
    BC.setID = BCSet.ID
    BC.ID = -1
    While (BC.Next())
        ' Process constraint: BC.nodeID, BC.dof(), etc.
    Wend
Wend
```

---

## Converting Expanded Loads to Permanent

Geometry-based loads expand to mesh loads. To make them permanent (prevent
re-compression):

```vb
Ld.setID = LdSet.ID
Ld.ID = -1
While (Ld.Next())
    If (Ld.expanded) Then
        Ld.expanded = False
        Ld.Put(Ld.ID)
    End If
Wend
```

---

## Deleting Loads and Constraints

```vb
' Delete all loads of a type in a set
rc = App.feDeleteLoads(setID, loadType)

' Delete all constraints of a type in a set
rc = App.feDeleteConstraints(setID, bcType)
```
