# Application Object Methods

The Femap Application Object (`femap.model`) contains all global methods organized
by domain. These correspond to Femap menu commands accessible via the API.

## File Methods

### Open / Save / Exit

| Method | Description |
|---|---|
| `feFileOpen(clear, filename)` | Open a Femap model file |
| `feFileNew()` | Create a new empty model |
| `feFileSave(filename)` | Save model to file |
| `feFileSaveAs(filename)` | Save model with new name |
| `feFileClose()` | Close current model |
| `feFileExit()` | Exit Femap |

### Import Geometry

| Method | Description |
|---|---|
| `feFileReadCatia(file)` | Import CATIA geometry |
| `feFileReadIGES(file)` | Import IGES geometry |
| `feFileReadParasolid(file)` | Import Parasolid geometry |
| `feFileReadSTEP(file)` | Import STEP geometry |
| `feFileReadSTL(file)` | Import STL geometry |
| `feFileReadSolidEdge(file)` | Import Solid Edge geometry |
| `feFileReadNX(file)` | Import NX geometry |

### Import Analysis Model

| Method | Description |
|---|---|
| `feFileReadNastran(file)` | Import Nastran bulk data |
| `feFileReadAnsys(file)` | Import ANSYS model |
| `feFileReadAbaqus(file)` | Import Abaqus model |

### Import Results

| Method | Description |
|---|---|
| `feFileReadNastranOP2(file)` | Import Nastran OP2 results |
| `feFileReadNastranXDB(file)` | Import Nastran XDB results |
| `feFileReadNeutral(file)` | Import Femap neutral file |
| `feFileAttach(type, file)` | Attach results file for on-demand reading |

### Export

| Method | Description |
|---|---|
| `feFileWriteNastran(file, opt)` | Export Nastran input file |
| `feFileWriteIGES(file)` | Export IGES geometry |
| `feFileWriteSTL(file)` | Export STL geometry |
| `feFileWriteParasolid(file)` | Export Parasolid geometry |
| `feNeutralWrite(file, opt)` | Export Femap neutral file |
| `feNeutralWriteSet(file, set, opt)` | Export neutral file for set of entities |

### Print / Copy

| Method | Description |
|---|---|
| `feFilePrint()` | Print current view |
| `feFileCopyToClipboard(opt)` | Copy graphics to clipboard |
| `feFileSavePicture(file, type, w, h)` | Save view as image |

---

## Tool Methods

### Units

| Method | Description |
|---|---|
| `feToolsUnitsSet(sys)` | Set unit system |
| `feToolsUnitsGet(sys)` | Get current unit system |
| `feToolsUnitsConvert(from, to, val)` | Convert between units |

### Variables

| Method | Description |
|---|---|
| `feToolsVarGet(name, val)` | Get a Femap variable value |
| `feToolsVarSet(name, val)` | Set a Femap variable value |

### Layers

| Method | Description |
|---|---|
| `feToolsLayerCreate(title, id)` | Create a layer |
| `feToolsActiveLayer(id)` | Set active layer |

### Text / Labels

| Method | Description |
|---|---|
| `feTextPut(...)` | Create text annotation |
| `feTextPut2(...)` | Create text annotation (extended) |
| `feTextMultiPut(...)` | Create multiple text annotations |
| `feTextMultiPut2(...)` | Create multiple text annotations (extended) |
| `feTextGet(...)` | Get text annotation data |

### Measure

| Method | Description |
|---|---|
| `feMeasureDistance(n1, n2, dist)` | Measure distance between nodes |
| `feMeasureDistanceBetweenXYZ(...)` | Distance between coordinates |
| `feMeasureAngle(...)` | Measure angle |
| `feMeasureLength(curveID, length)` | Measure curve length |
| `feMeasureArea(surfID, area)` | Measure surface area |
| `feMeasureMeshMassProp(...)` | Mass properties from mesh elements (see below) |

#### `feMeasureMeshMassProp` — Mesh Mass Properties

Computes mass properties (structural, non-structural, total) for a set of elements.
Returns mass, CG, and inertia broken down by category. Connection Region NSM **is**
included in the measurement.

```vb
rc = App.feMeasureMeshMassProp(setID, csysID, includeRigid, useLumpedMass, _
    length, area, volume, structMass, nonstructMass, totalMass, _
    structCG, nonstructCG, totalCG, inertia, inertiaCG)
```

| Parameter | Type | Direction | Description |
|---|---|---|---|
| `setID` | Long | In | Set ID containing element IDs (use `elemSet.ID`) |
| `csysID` | Long | In | Coordinate system for CG/inertia (0=global) |
| `includeRigid` | Boolean | In | Include rigid element contributions |
| `useLumpedMass` | Boolean | In | Use lumped (vs consistent) mass |
| `length` | Double | Out | Total length (line elements) |
| `area` | Double | Out | Total area (surface elements) |
| `volume` | Double | Out | Total volume (solid elements) |
| `structMass` | Double | Out | Structural mass (from material density) |
| `nonstructMass` | Double | Out | Non-structural mass (NSM, CONM2) |
| `totalMass` | Double | Out | Total mass (structural + non-structural) |
| `structCG` | Variant | Out | Structural CG [x, y, z] |
| `nonstructCG` | Variant | Out | Non-structural CG [x, y, z] |
| `totalCG` | Variant | Out | Total CG [x, y, z] |
| `inertia` | Variant | Out | Inertia tensor (about origin) |
| `inertiaCG` | Variant | Out | Inertia tensor (about CG) |

**Example:**
```vb
Dim len0 As Double, area0 As Double, volume0 As Double
Dim structMass0 As Double, nonstructMass0 As Double, totalMass0 As Double
Dim structCG0 As Variant, nonstructCG0 As Variant, totalCG0 As Variant
Dim inertia0 As Variant, inertiaCG0 As Variant

rc = App.feMeasureMeshMassProp(elemSet.ID, 0, False, False, _
    len0, area0, volume0, structMass0, nonstructMass0, totalMass0, _
    structCG0, nonstructCG0, totalCG0, inertia0, inertiaCG0)

If rc = FE_OK Then
    App.feAppMessage(FCM_NORMAL, "Total Mass: " + Format$(totalMass0, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Structural: " + Format$(structMass0, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Non-structural: " + Format$(nonstructMass0, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "CG: (" + Format$(totalCG0(0), "0.000") + ", " + _
        Format$(totalCG0(1), "0.000") + ", " + Format$(totalCG0(2), "0.000") + ")")
End If
```

> CG arrays are 0-based: `totalCG0(0)` = X, `totalCG0(1)` = Y, `totalCG0(2)` = Z.

### Checks

| Method | Description |
|---|---|
| `feCheckElemDistortion(set, type, limit, count)` | Check element quality |
| `feCheckCoincidentNodes(tol, set)` | Find coincident nodes |
| `feCheckFreeEdge(set)` | Find free edges |
| `feCheckDuplicateElements(set)` | Find duplicate elements |
| `feCheckNormals(set)` | Check element normals |
| `feCheckJacobians(set, limit)` | Check Jacobian quality |

---

## Geometry Methods

### Lines and Curves

| Method | Description |
|---|---|
| `feLineDir(x1,y1,z1, x2,y2,z2, id)` | Line between two points |
| `feLineArc(xc,yc,zc, x1,y1,z1, angle, nx,ny,nz, id)` | Arc |
| `feLineCircle(xc,yc,zc, r, nx,ny,nz, id)` | Full circle |
| `feLineSpline(nPt, xyz, id)` | Spline through points |
| `feLineFillet(c1, c2, r, id)` | Fillet between curves |
| `feLineChamfer(c1, c2, d, id)` | Chamfer between curves |
| `feLineMidline(c1, c2, id)` | Midline between curves |
| `feLineBreak(curveID, param)` | Break curve at parameter |

### Curve Modification

| Method | Description |
|---|---|
| `feCurveExtend(id, dist, end)` | Extend curve |
| `feCurveReverse(id)` | Reverse curve direction |
| `feCurveProject(id, surf)` | Project curve onto surface |
| `feCurveJoin(set, id)` | Join curves |

### Surfaces

| Method | Description |
|---|---|
| `feSurfaceRuled(c1, c2, id)` | Ruled surface between curves |
| `feSurfaceRevolve(curve, axis, angle, id)` | Surface of revolution |
| `feSurfaceExtrude(curve, dx,dy,dz, id)` | Extruded surface |
| `feSurfaceLoft(curves, id)` | Lofted surface |
| `feSurfacePad(curve, id)` | Pad (fill) surface from closed curve |
| `feSurfaceFromMesh(set, id)` | Create surface from mesh |

### Midsurfaces

| Method | Description |
|---|---|
| `feMidsurface(solidID, id)` | Generate midsurface |
| `feMidsurfaceGenerate(set)` | Generate midsurfaces for set of solids |

### Solids

| Method | Description |
|---|---|
| `feSolidExtrude(surfSet, dx,dy,dz, id)` | Extrude surfaces into solid |
| `feSolidRevolve(surfSet, axis, angle, id)` | Revolve surfaces into solid |
| `feSolidBoolean(op, s1, s2, id)` | Boolean operation on solids |
| `feSolidSlice(id, plane)` | Slice solid with plane |
| `feSolidStitch(set, tol, id)` | Stitch surfaces into solid |

### Boundaries

| Method | Description |
|---|---|
| `feBoundaryFromSurfaces(surfSet, id)` | Create boundary from surfaces |
| `feBoundarySplit(id, curve)` | Split boundary at curve |

---

## Meshing Methods

### Mesh Control

| Method | Description |
|---|---|
| `feMeshSize(size)` | Set default mesh size |
| `feMeshSizeSurface(surfSet, size, type)` | Set mesh size on surfaces |
| `feMeshSizeCurve(curveSet, nElem, bias)` | Set mesh size on curves |
| `feMeshSizePoint(ptSet, size)` | Set mesh size at points |
| `feMeshApproach(surfSet, type)` | Set mesh approach (mapped/free) |

### Meshing Geometry

| Method | Description |
|---|---|
| `feMeshSurface(surfSet, elemType)` | Mesh surfaces |
| `feMeshCurve(curveSet, elemType)` | Mesh curves |
| `feMeshTetSolid(solidSet, elemType)` | Tet mesh solids |
| `feMeshHexSolid(solidSet, elemType)` | Hex mesh solids |

### Mesh Editing

| Method | Description |
|---|---|
| `feMergeNodes(tol, set)` | Merge coincident nodes |
| `feMeshSmooth(set, iter)` | Smooth mesh |
| `feMeshRefine(set, level)` | Refine mesh |

### Mesh Copy / Transform

| Method | Description |
|---|---|
| `feMeshCopy(set, dx,dy,dz, n, merge)` | Copy mesh with translation |
| `feMeshRadialCopy(set, axis, angle, n, merge)` | Copy mesh with rotation |
| `feMeshScale(set, sx,sy,sz, cx,cy,cz)` | Scale mesh |
| `feMeshReflect(set, plane)` | Reflect mesh |

---

## Connection Methods

| Method | Description |
|---|---|
| `feConnectionAutomatic(set, tol)` | Automatic mesh connections |
| `feMeshClosestLink(n1set, n2set, type, prop)` | Create closest-link connections |

---

## Model Load/Constraint Methods

| Method | Description |
|---|---|
| `feLoadSet(id)` | Access load set |
| `feConstraintSet(id)` | Access constraint set |
| `feDeleteLoads(setID, type)` | Delete loads of type in set |
| `feDeleteConstraints(setID, type)` | Delete constraints of type in set |

---

## Model Output Methods (V2)

| Method | Description |
|---|---|
| `feOutputCreateV2(...)` | Create output vectors |
| `feOutputCombineV2(...)` | Combine output sets |
| `feOutputEnvelopeV2(...)` | Create output envelope |
| `feDeleteOutputV2(setID, vecID)` | Delete output vector |
| `feDeleteOutput2V2(setID, vecSet)` | Delete multiple vectors |

---

## View, Window, and Visibility

| Method | Description |
|---|---|
| `feViewRegenerate(viewID)` | Regenerate view (0=active) |
| `feViewRedraw(viewID)` | Redraw view |
| `feViewAutoscaleAll(viewID)` | Autoscale view |
| `feViewAutoscaleVisible(viewID)` | Autoscale to visible |
| `feViewShow(type, set, show)` | Show/hide entities |
| `feViewShow2(type, set, show, redraw)` | Show/hide with redraw control |
| `feViewVisible(viewID, vis)` | Set view visibility |
| `feViewTile()` | Tile all views |
| `feViewCascade()` | Cascade all views |
| `feAppGetActiveView(viewID)` | Get active view ID |

---

## Group Methods (Application-Level)

| Method | Description |
|---|---|
| `feGroupGenerate(groupID, genOpt)` | Generate group from options |
| `feGroupGenerate2(groupID, title, genOpt)` | Generate with title |
| `feGroupGenProp(groupID, propID)` | Generate group from property |
| `feGroupGenMatl(groupID, matlID)` | Generate group from material |
| `feGroupGenElemType(groupID, elemType)` | Generate group from elem type |
| `feGroupGenElemShape(groupID, shape)` | Generate group from elem shape |
| `feGroupBoolean(result, op, g1, g2)` | Boolean operation on groups |
| `feGroupCombine(result, gSet)` | Combine groups |
| `feGroupEvaluate(groupID)` | Evaluate group rules |
| `feGroupPeel(groupID, layers)` | Peel layers from group |
| `feGroupCondense(groupID)` | Remove unreferenced entities |
| `feGroupMoveToLayer(groupID, layer)` | Move group to layer |
| `feGroupsContaining(type, id, gSet)` | Find groups containing entity |

---

## Standard Dialog Methods

### Coordinate / Vector / Plane Dialogs

| Method | Description |
|---|---|
| `feCoordPick(prompt, x,y,z)` | Pick coordinate interactively |
| `feVectorPick(prompt, baseXYZ, dirXYZ)` | Pick vector interactively |
| `fePlanePick(prompt, baseXYZ, normXYZ)` | Pick plane interactively |
| `feCoordOnCurve(prompt, curveID, x,y,z)` | Pick point on curve |
| `feCoordOnSurface(prompt, surfID, x,y,z)` | Pick point on surface |

### Entity Selection

| Method | Description |
|---|---|
| `feSelectEntity(type, prompt, id)` | Select single entity |
| `feSelectOutput(setID, vecID)` | Select output set and vector |

---

## User Interface Methods

| Method | Description |
|---|---|
| `feAppMessage(color, text)` | Write message to message pane |
| `feAppMessageBox(type, text)` | Display message box |
| `feAppLock()` / `feAppUnlock()` | Lock/unlock UI for performance |
| `feAppVisible(vis)` | Show/hide Femap |
| `feRunCommand(cmdID)` | Run Femap command by ID |
| `feFileProgramRun(wait, echo, file)` | Run program file |
| `feFileExecute(file, args)` | Execute external program |
| `feAppEventCallback(event, param)` | Trigger event callback |

---

## Utility Methods

| Method | Description |
|---|---|
| `feSetFree(setID)` | Free/release a Set object |
| `feSetFreeNotInSet(setID, excludeSet)` | Free with exclusion |
| `feFileGetName(prompt, filter, file)` | File selection dialog |
| `feFileCurrentDirectory(dir)` | Get/set current directory |
