# Geometry and Meshing

## Geometry Creation

### Points

Points are the foundation of geometry. They're often created implicitly when
creating curves, but can be created explicitly:

```vb
Dim pt As femap.Point : Set pt = App.fePoint
pt.x = 10.0 : pt.y = 20.0 : pt.z = 0.0
rc = pt.Put(pt.NextEmptyID)
```

### Lines (Straight)

```vb
Dim lineID As Long
rc = App.feLineDir(0, 0, 0, 10, 0, 0, lineID)
' Creates line from (0,0,0) to (10,0,0), returns curve ID
```

### Arcs

```vb
Dim arcID As Long
' Arc: center, start point, angle (degrees), normal vector
rc = App.feLineArc(0, 0, 0, 5, 0, 0, 90.0, 0, 0, 1, arcID)
```

### Circles

```vb
Dim circID As Long
' Circle: center, radius, normal vector
rc = App.feLineCircle(0, 0, 0, 5.0, 0, 0, 1, circID)
```

### Splines

```vb
Dim nPts As Long : nPts = 4
Dim xyz(11) As Double
xyz(0) = 0 : xyz(1) = 0 : xyz(2) = 0    ' Point 1
xyz(3) = 5 : xyz(4) = 3 : xyz(5) = 0    ' Point 2
xyz(6) = 10 : xyz(7) = 3 : xyz(8) = 0   ' Point 3
xyz(9) = 15 : xyz(10) = 0 : xyz(11) = 0 ' Point 4
Dim splineID As Long
rc = App.feLineSpline(nPts, xyz, splineID)
```

### Curve Modification

```vb
' Break curve at midpoint parameter
rc = App.feLineBreak(curveID, 0.5)

' Reverse curve direction
Dim crv As femap.Curve : Set crv = App.feCurve
rc = crv.Get(curveID)
' Use curve methods for tangent, normal, etc.
```

---

## Surface Creation

### Ruled Surface (Between Two Curves)

```vb
Dim surfID As Long
rc = App.feSurfaceRuled(curve1ID, curve2ID, surfID)
```

### Extruded Surface

```vb
Dim surfID As Long
' Extrude curve along vector (dx, dy, dz)
rc = App.feSurfaceExtrude(curveID, 0, 0, 10, surfID)
```

### Revolved Surface

```vb
Dim surfID As Long
' Revolve curve around axis, angle in degrees
rc = App.feSurfaceRevolve(curveID, axisID, 360.0, surfID)
```

### Lofted Surface

```vb
Dim curveSet As femap.Set : Set curveSet = App.feSet
curveSet.Add(curve1ID)
curveSet.Add(curve2ID)
curveSet.Add(curve3ID)
Dim surfID As Long
rc = App.feSurfaceLoft(curveSet.ID, surfID)
```

### Pad Surface (Fill Closed Curve Loop)

```vb
Dim surfID As Long
rc = App.feSurfacePad(closedCurveID, surfID)
```

### Boundary Surface (Combine Multiple Surfaces)

```vb
Dim surfSet As femap.Set : Set surfSet = App.feSet
surfSet.Add(surf1)
surfSet.Add(surf2)
Dim bndID As Long
rc = App.feBoundaryFromSurfaces(surfSet.ID, bndID)
```

---

## Solid Creation

### Extrude Surfaces to Solid

```vb
Dim surfSet As femap.Set : Set surfSet = App.feSet
surfSet.Add(surfID)
Dim solidID As Long
rc = App.feSolidExtrude(surfSet.ID, 0, 0, 10, solidID)
```

### Revolve Surfaces to Solid

```vb
rc = App.feSolidRevolve(surfSet.ID, axisID, 360.0, solidID)
```

### Boolean Operations

```vb
' op: 0=Intersect, 1=Union, 2=Subtract(s1-s2)
rc = App.feSolidBoolean(1, solid1ID, solid2ID, resultID)  ' Union
rc = App.feSolidBoolean(2, solid1ID, solid2ID, resultID)  ' Subtract
```

### Slice Solid with Plane

```vb
rc = App.feSolidSlice(solidID, planeBase, planeNormal)
```

### Stitch Surfaces into Solid

```vb
Dim surfSet As femap.Set : Set surfSet = App.feSet
' Add all surfaces to stitch
surfSet.AddAll(FT_SURFACE)
Dim solidID As Long
rc = App.feSolidStitch(surfSet.ID, 0.001, solidID)
```

---

## Mesh Control

### Set Default Mesh Size

```vb
rc = App.feMeshSize(2.5)   ' Default element size = 2.5
```

### Surface Mesh Size

```vb
Dim surfSet As femap.Set : Set surfSet = App.feSet
surfSet.Add(surfID)
' type: 0=on surface, 1=on curves
rc = App.feMeshSizeSurface(surfSet.ID, 1.5, 0)
```

### Curve Mesh Size (Number of Elements)

```vb
Dim curveSet As femap.Set : Set curveSet = App.feSet
curveSet.Add(curveID)
' nElem=10 elements along curve, bias=1.0 (uniform)
rc = App.feMeshSizeCurve(curveSet.ID, 10, 1.0)
```

### Mesh Approach (Mapped vs Free)

```vb
Dim surfSet As femap.Set : Set surfSet = App.feSet
surfSet.Add(surfID)
' type: 0=Free, 1=Mapped
rc = App.feMeshApproach(surfSet.ID, 1)   ' Mapped mesh
```

---

## Meshing Geometry

### Mesh Surfaces (2D)

```vb
Dim surfSet As femap.Set : Set surfSet = App.feSet
surfSet.Select(FT_SURFACE, True, "Select Surfaces to Mesh")
' elemType: 0=Default, use FET_L_PLATE for CQUAD4/CTRIA3
rc = App.feMeshSurface(surfSet.ID, 0)
```

### Mesh Curves (1D — Beams/Bars)

```vb
Dim curveSet As femap.Set : Set curveSet = App.feSet
curveSet.Select(FT_CURVE, True, "Select Curves to Mesh")
rc = App.feMeshCurve(curveSet.ID, FET_L_BEAM)
```

### Tet Mesh Solids (3D)

```vb
Dim solidSet As femap.Set : Set solidSet = App.feSet
solidSet.Select(FT_SOLID, True, "Select Solids to Mesh")
' elemType: 0=linear tet, 1=parabolic tet
rc = App.feMeshTetSolid(solidSet.ID, 1)  ' Parabolic tets
```

### Hex Mesh Solids (3D)

```vb
rc = App.feMeshHexSolid(solidSet.ID, 0)
```

---

## Mesh Editing

### Merge Coincident Nodes

```vb
Dim nodeSet As femap.Set : Set nodeSet = App.feSet
nodeSet.AddAll(FT_NODE)
rc = App.feMergeNodes(0.001, nodeSet.ID)  ' Tolerance = 0.001
```

### Smooth Mesh

```vb
Dim elemSet As femap.Set : Set elemSet = App.feSet
elemSet.Select(FT_ELEM, True, "Select Elements to Smooth")
rc = App.feMeshSmooth(elemSet.ID, 5)  ' 5 iterations
```

### Refine Mesh

```vb
rc = App.feMeshRefine(elemSet.ID, 2)  ' Refine level 2
```

---

## Mesh Copy and Transform

### Translational Copy

```vb
Dim elemSet As femap.Set : Set elemSet = App.feSet
elemSet.Select(FT_ELEM, True, "Select Elements to Copy")
' Copy 3 times along (10, 0, 0), merge coincident nodes
rc = App.feMeshCopy(elemSet.ID, 10, 0, 0, 3, True)
```

### Rotational (Radial) Copy

```vb
' axisType: defines rotation axis
' angle: rotation per copy
' n: number of copies
rc = App.feMeshRadialCopy(elemSet.ID, axisType, 30.0, 11, True)
```

### Reflect Mesh

```vb
rc = App.feMeshReflect(elemSet.ID, planeType)
```

---

## Quality Checks

### Element Distortion Check

```vb
Dim badSet As femap.Set : Set badSet = App.feSet
Dim distCount As Long
rc = App.feCheckElemDistortion(elemSet.ID, 0, 0.7, distCount)
' Elements exceeding Jacobian limit are flagged
```

### Coincident Node Check

```vb
rc = App.feCheckCoincidentNodes(0.001, nodeSet.ID)
```

### Free Edge Check

```vb
rc = App.feCheckFreeEdge(elemSet.ID)
```

### Normal Consistency Check

```vb
rc = App.feCheckNormals(elemSet.ID)
```

---

## Connection Methods

### Automatic Connections

```vb
Dim connSet As femap.Set : Set connSet = App.feSet
connSet.AddAll(FT_SURFACE)
rc = App.feConnectionAutomatic(connSet.ID, 0.01)  ' Tolerance
```

### Closest Link (Spider/RBE)

```vb
' Create closest links between two node sets
Dim n1Set As femap.Set : Set n1Set = App.feSet
Dim n2Set As femap.Set : Set n2Set = App.feSet
n1Set.AddRule(surf1ID, FGD_NODE_ATSURFACE)
n2Set.AddRule(surf2ID, FGD_NODE_ATSURFACE)
rc = App.feMeshClosestLink(n1Set.ID, n2Set.ID, FET_L_RIGID, propID)
```

---

## BodyMesher Object

For advanced solid meshing control:

```vb
Dim bm As femap.BodyMesher : Set bm = App.feBodyMesher

' Set options
bm.ElemSize = 2.0
bm.ElemOrder = 1        ' 0=Linear, 1=Parabolic
bm.MeshType = 0         ' 0=Tet

' Mesh a solid
rc = bm.MeshSolid(solidID)
```

### BodyMesher Properties

| Property | Type | Description |
|---|---|---|
| `ElemSize` | Double | Default element size |
| `ElemOrder` | Long | 0=Linear, 1=Parabolic |
| `MeshType` | Long | 0=Tet, 1=Hex |
| `SurfaceMeshSize` | Double | Surface-specific size |
| `GrowthRate` | Double | Mesh growth rate |
| `MinJacobian` | Double | Minimum Jacobian threshold |
