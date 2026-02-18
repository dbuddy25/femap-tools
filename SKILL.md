---
name: femap-api
description: >
  Deep reference for Femap API custom tools — writing .BAS scripts in WinWrap Basic
  for the Femap finite element pre/post-processor. Use when writing Femap API code,
  creating custom tools, automating meshing, post-processing results, creating loads,
  manipulating geometry, or working with Femap entities programmatically.
  Trigger phrases: Femap, Femap API, WinWrap Basic, .BAS, feFemap, feNode, feElem,
  feSet, feResults, Results Browsing, meshing, post-processing, CBUSH, RBE2, RBE3,
  PSHELL, CQUAD4, CTRIA3, output vectors, DataTable, custom tool, feGroup, feOutput,
  OutputSet, feLoadMesh, feBCNode, feProperty, feMaterial, feCSys, Selector, CopyTool.
---

# Femap API Custom Tools Skill

## Overview

The Femap API is an OLE/COM programming interface to Siemens Femap (finite element
pre/post-processor). It provides hundreds of functions callable from the built-in
WinWrap Basic editor (API Programming window), VB.NET, Excel VBA, C++, or Python.

**Architecture:** Application Object (`femap.model`) → Entity Objects (Node, Elem,
Prop, Matl, etc.) → Properties + Methods (Get/Put/Next pattern). Tool Objects
(Set, DataTable, Results Browsing, Selector, CopyTool) provide utilities.

**This skill covers:** Writing `.BAS` scripts in WinWrap Basic for Femap's API
Programming window. All entity types, App Object methods, results, loads, geometry,
meshing, groups, dialogs, and constants.

## Scope

**In scope:** All Femap API domains — entity CRUD, bulk operations, meshing, geometry
creation, load/constraint application, results extraction and creation, groups,
views, Data Table, dialogs, and automation via WinWrap Basic `.BAS` scripts.

**Out of scope:** Python/Pyfemap setup, VB.NET project configuration, C++ integration,
Femap GUI-only workflows (no API), solver-specific (Nastran) card syntax.

## Quick Start

### Boilerplate — Connect to Femap

```vb
Sub Main
    Dim App As femap.model
    Set App = feFemap()       ' Always use inside Femap API Programming window
    Dim rc As Long

    ' --- Your code here ---

    App.feViewRegenerate(0)   ' Refresh graphics
End Sub
```

> **Outside Femap** (Excel VBA, VB.NET): use `Set App = GetObject(,"femap.model")`
> to attach to a running session, or `CreateObject("femap.model")` to start a new one.

### Create Entity Objects from the App Object

```vb
Dim nd As femap.Node      : Set nd = App.feNode
Dim el As femap.Elem      : Set el = App.feElem
Dim pr As femap.Prop      : Set pr = App.feProp       ' Also: App.feProperty
Dim mt As femap.Matl      : Set mt = App.feMatl        ' Also: App.feMaterial
Dim os As femap.OutputSet  : Set os = App.feOutputSet
Dim gp As femap.Group     : Set gp = App.feGroup
Dim cs As femap.CSys      : Set cs = App.feCSys
Dim st As femap.Set       : Set st = App.feSet
Dim rbo As femap.Results  : Set rbo = App.feResults
Dim ld As femap.LoadMesh  : Set ld = App.feLoadMesh
Dim bc As femap.BCNode    : Set bc = App.feBCNode
Dim dt As femap.DataTable : Set dt = App.feDataTable
Dim ly As femap.Layup     : Set ly = App.feLayup
```

> **Factory method aliases:** `feProp`/`feProperty` and `feMatl`/`feMaterial` both work.
> The short forms (`feProp`, `feMatl`) are tested and match the API PDF examples.

### The Get/Put Pattern (Every Entity)

```vb
rc = nd.Get(42)          ' Load node 42 from database into object
nd.x = nd.x + 10.0      ' Modify property
rc = nd.Put(42)          ' Save back to database

' Create new entity:
Dim newID As Long
newID = nd.NextEmptyID   ' Find next available ID
nd.x = 0.0 : nd.y = 1.0 : nd.z = 2.0
rc = nd.Put(newID)       ' Store new node
```

### Set Object — Selection & Iteration

```vb
Dim mySet As femap.Set
Set mySet = App.feSet
rc = mySet.Select(FT_ELEM, True, "Select Elements")  ' Interactive selection

' Iterate:
Dim id As Long
id = mySet.First()
Do While id > 0
    rc = el.Get(id)
    ' ... process element ...
    id = mySet.Next()
Loop
```

### Messages

```vb
App.feAppMessage(FCM_NORMAL, "Info message")
App.feAppMessage(FCM_ERROR, "Error: something failed")
App.feAppMessage(FCM_WARNING, "Warning: check input")
```

## Core Patterns

### Entity CRUD Lifecycle

1. **Create object:** `Set nd = App.feNode`
2. **Set properties:** `nd.x = 1.0`, `nd.y = 2.0`, `nd.z = 3.0`
3. **Store:** `rc = nd.Put(id)` — returns `FE_OK` (-1) on success, `FE_FAIL` (0) on failure
4. **Retrieve:** `rc = nd.Get(id)` — loads from database
5. **Traverse:** `nd.First()`, `nd.Next()`, `nd.Prev()`, `nd.Last()`
6. **Delete:** `App.feDelete(FT_NODE, id)`

### Bulk Operations (Performance)

Use `GetAllArray` / `PutAllArray` for batch reads/writes instead of looping Get/Put:

```vb
Dim count As Long, vID As Variant, vXYZ As Variant
Dim vLayer As Variant, vColor As Variant, vType As Variant
Dim vDefCS As Variant, vOutCS As Variant, vPermBC As Variant
rc = nd.GetAllArray(0, count, vID, vXYZ, vLayer, vColor, _
                    vType, vDefCS, vOutCS, vPermBC)
```

### Set Object Rules (Add Entities by Criteria)

```vb
mySet.AddRule(propID, FGD_ELEM_BYPROP)       ' Elements by property
mySet.AddRule(surfID, FGD_NODE_ATSURFACE)     ' Nodes on surface
mySet.AddSetRule(elemSetID, FGD_NODE_ONELEM) ' Nodes on elements in set
mySet.AddAll(FT_ELEM)                         ' All elements
```

### Data Types (WinWrap Basic ↔ Femap API)

| API Doc Type | WinWrap Basic | Description |
|---|---|---|
| BOOL | `Boolean` | True/False |
| INT4 | `Long` | 4-byte integer |
| REAL8 | `Double` | 8-byte real |
| STRING | `String` | Text |
| Array | `Variant` | Arrays passed as Variant |

### Return Codes

| Constant | Value | Meaning |
|---|---|---|
| `FE_OK` | -1 | Success |
| `FE_FAIL` | 0 | Failure |
| `FE_NOT_EXIST` | 3 | Entity not found |
| `FE_CANCEL` | -2 | User cancelled |

### Locking for Performance

```vb
App.feAppLock()        ' Lock UI — prevents redraws during bulk operations
' ... bulk operations ...
App.feAppUnlock()      ' Unlock (must pair every Lock with Unlock)
App.feViewRegenerate(0)
```

## App Object Quick Reference

### File Methods
`feFileOpen`, `feFileSave`, `feFileSaveAs`, `feFileNew`, `feFileExit`,
`feFileAttach`, `feFileImport*`, `feFileExport*`, `feFileNeutralRead/Write`

### Geometry Methods
`feLineDir`, `feLineArc`, `feLineCircle`, `feLineSpline`, `feSurfaceRuled`,
`feSurfaceRevolve`, `feSurfaceExtrude`, `feSurfaceLoft`, `feSolidExtrude`,
`feSolidRevolve`, `feSolidBoolean`, `feSolidSlice`, `feBoundaryFromSurfaces`

### Meshing Methods
`feMeshSurface`, `feMeshTetSolid`, `feMeshHexSolid`, `feMeshSize*`,
`feMeshSizeSurface`, `feMeshSizeCurve`, `feCheckElemDistortion`,
`feMeshClosestLink`, `feMergeNodes`, `feMeshCopy`, `feMeshRadialCopy`

### Model Methods
`feLoadSet`, `feConstraintSet`, `feOutputCreate*V2`, `feOutputCombine*V2`,
`feOutputEnvelope*V2`, `feDeleteOutputV2`, `feDeleteLoads`, `feDeleteConstraints`

### View/Window Methods
`feViewRegenerate`, `feViewRedraw`, `feViewAutoscaleAll`, `feViewShow`,
`feViewVisible`, `feViewTile`, `feViewCascade`, `feAppGetActiveView`

### Group Methods
`feGroupGenerate`, `feGroupGenerate2`, `feGroupGenProp`, `feGroupGenMatl`,
`feGroupGenElemType`, `feGroupBoolean`, `feGroupCombine`, `feGroupEvaluate`

### Selection / Dialog Methods
`feSelectEntity`, `feSelectOutput`, `feCoordPick`, `feVectorPick`,
`fePlanePick`, `feAppMessageBox`, `feAppMessage`

### Utility Methods
`feMeasureDistance`, `feMeasureAngle`, `feMeasureMeshMassProp`,
`feAppLock`/`feAppUnlock`, `feAppVisible`,
`feRunCommand`, `feFileProgramRun`, `feFileExecute`, `feAppEventCallback`

## Entity Objects Quick Reference

| Object | App Method | Key Properties | Key Methods |
|---|---|---|---|
| Node | `feNode` | x, y, z, defCSys, outCSys | Get/Put/GetAllArray/PutAllArray |
| Elem | `feElem` | type, topology, propID, node() | Get/Put/GetNodeList/PutNodeList |
| Prop | `feProp` | type, matlID, pval(), title | Get/Put |
| Matl | `feMatl` | type, title, mval() | Get/Put |
| CSys | `feCSys` | type, origin, dirz, dirx | Get/Put |
| OutputSet | `feOutputSet` | title, value, analysis | Get/Put |
| Group | `feGroup` | title, layer | Get/Put/AddRule |
| View | `feView` | OutputSet, Deformed, Mode | Get/Put |
| LoadSet | `feLoadSet` | title | Get/Put |
| BCSet | `feBCSet` | title | Get/Put |
| LoadMesh | `feLoadMesh` | type, setID, nodeID, dof() | Get/Put/PutArray |
| BCNode | `feBCNode` | setID, nodeID, dof() | Get/Put |
| BCGeom | `feBCGeom` | setID, geomID, dof() | Get/Put |
| Curve | `feCurve` | type, startPt, endPt | Get/Put/Tangent |
| Surface | `feSurface` | type, solidID | Get/Put/Normal |
| Solid | `feSolid` | title, color | Get/Put |
| Text | `feText` | x, y, z, text, color | Get/Put |
| Function | `feFunction` | title, type | Get/Put |
| Layup | `feLayup` | NumberOfPlys, matlID(ply), thickness(ply) | Get/Put |
| ConnProp | `feConnProp` | type | Get/Put |
| ConnRegion | `feConnectionRegion` | type, masterID, MassNSM | Get/Put |

## Results Browsing (Modern Post-Processing)

The Results Browsing Object (`App.feResults`) is the **preferred** way to read and
create output in Femap v2020.1+. The old `feOutput` object is deprecated.

### Read Results Workflow

```vb
Dim rbo As femap.Results : Set rbo = App.feResults
Dim col As Long, vCol As Variant
rc = rbo.AddColumnV2(setID, vectorID, False, col, vCol)
rc = rbo.Populate
Dim vIDs As Variant, vVals As Variant
rc = rbo.GetColumn(0, vIDs, vVals)  ' Column 0 = first added
```

### Create Nodal Output

```vb
rbo.AddVectorAtNodeColumnsV2(oSetID, 24000000, 24000001, 24000002, _
    24000003, "My Vector", FOT_DISP, True, cIndex)
rbo.SetVectorAtNodeColumnsV2(cIndex, count, vNodeIDs, vX, vY, vZ)
rbo.Save
```

### Create Elemental Output

```vb
rbo.AddScalarAtElemColumnV2(oSetID, 24000000, "Stress", FOT_STRESS, _
    False, cIndex)
rbo.SetColumn(cIndex, count, vElemIDs, vVals)
rbo.Save
```

### V2 Migration Note

All methods using output vector IDs now have `V2` variants. Use the new vector IDs
(v2020.1+). Use `ResultsIDQuery` object to look up vector IDs programmatically:

```vb
Dim q As femap.ResultsIDQuery : Set q = App.feResultsIDQuery
Dim vecID As Long
vecID = q.Plate(VPV_STRESS, VPT_VON_MISES, VPP_TOP, VPL_CENTROID)
```

## Custom Dialogs

WinWrap Basic supports `Begin Dialog` / `End Dialog` for custom input forms:

```vb
Begin Dialog MyDialog 300, 200, "My Tool"
    Text 10, 10, 100, 14, "Enter value:"
    TextBox 120, 8, 80, 14, .valueBox
    CheckBox 10, 30, 200, 14, "Include nodes", .chkNodes
    DropListBox 10, 50, 200, 14, items$(), .listChoice
    OKButton 60, 170, 80, 20
    CancelButton 160, 170, 80, 20
End Dialog
Dim dlg As MyDialog
If Dialog(dlg) = -1 Then   ' OK pressed
    val = CDbl(dlg.valueBox)
End If
```

> For complex dialogs with event handling, use `DialogFunc` callback.
> See `references/ui-and-dialogs.md` and `examples/custom_dialog.bas`.

## Reference Files

Read these when you need deeper detail beyond what's in this skill file:

| File | When to Read |
|---|---|
| `references/common-pitfalls.md` | **Always check first** — 14 common mistakes with fixes |
| `references/sets-and-selection.md` | Working with Set objects, selection, iteration, rules |
| `references/entity-objects.md` | Full entity types, properties, creation patterns |
| `references/app-object-methods.md` | App-level methods organized by domain |
| `references/constants-and-enums.md` | Looking up FT_*, FET_*, FCM_*, FGD_*, FOC_* values |
| `references/results-and-output.md` | Results Browsing, OutputSet, V2 migration, creation |
| `references/loads-and-constraints.md` | LoadMesh, LoadGeom, BCNode, BCGeom, load sets |
| `references/geometry-and-meshing.md` | Geometry creation, mesh control, mesh editing |
| `references/tool-objects.md` | DataTable, Selector, CopyTool, ReadFile, UserData |
| `references/ui-and-dialogs.md` | Dialogs, messages, events, toolbars, embedding |

## Example Scripts

| File | Description |
|---|---|
| `examples/create_nodes_and_elements.bas` | Create nodes, material, property, CQUAD4 |
| `examples/select_and_iterate.bas` | Set selection and iteration patterns |
| `examples/modify_element_properties.bas` | Change element properties and colors |
| `examples/create_loads.bas` | Apply forces, pressures, temperatures |
| `examples/extract_results.bas` | Results Browsing read workflow |
| `examples/create_output.bas` | Create user-defined output vectors |
| `examples/geometry_operations.bas` | Lines, arcs, surfaces, meshing |
| `examples/group_management.bas` | Create/modify groups, add rules |
| `examples/custom_dialog.bas` | WinWrap Basic dialog with inputs |
| `examples/mesh_and_connect.bas` | Mesh surfaces, connections, quality |

## Searching the API PDF

When reference files don't have enough detail, search the source PDF:

```bash
pdftotext api.pdf - | grep -i -A 5 "methodName"
pdftotext api.pdf - | grep -i -B 2 -A 10 "feNodeGetAll"
pdftotext api.pdf - | grep -n "FGD_" | head -50
```

**Common search patterns:**
- Method signature: `grep -A 10 "^methodName$"`
- Entity object section: `grep -B 2 -A 20 "Node Object Properties"`
- Constants: `grep "FT_\|FET_\|FGD_\|FCM_\|FOT_"`
- Code examples: `grep -B 5 -A 20 "Sub Main"`
