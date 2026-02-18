' geometry_operations.bas
' Creates geometry (lines, arcs, surfaces) and meshes them.
' Demonstrates: feLineDir, feLineArc, feSurfaceRuled, feMeshSurface.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Create a rectangular plate with a hole
    ' =============================================

    ' --- Outer rectangle: 4 lines ---
    Dim line1 As Long, line2 As Long, line3 As Long, line4 As Long

    rc = App.feLineDir(0, 0, 0, 100, 0, 0, line1)       ' Bottom edge
    rc = App.feLineDir(100, 0, 0, 100, 50, 0, line2)     ' Right edge
    rc = App.feLineDir(100, 50, 0, 0, 50, 0, line3)      ' Top edge
    rc = App.feLineDir(0, 50, 0, 0, 0, 0, line4)         ' Left edge

    App.feAppMessage(FCM_NORMAL, "Created rectangular boundary: lines " + _
        Str$(line1) + "-" + Str$(line4))

    ' --- Center hole: circle ---
    Dim circleID As Long
    ' Circle at center (50, 25, 0), radius 10, normal in Z
    rc = App.feLineCircle(50, 25, 0, 10.0, 0, 0, 1, circleID)

    App.feAppMessage(FCM_NORMAL, "Created hole: curve " + Str$(circleID))

    ' --- Create a pad surface from the outer boundary ---
    ' First create a boundary surface from the rectangle
    Dim surfID As Long
    rc = App.feSurfacePad(line1, surfID)

    If rc = FE_OK Then
        App.feAppMessage(FCM_NORMAL, "Created surface " + Str$(surfID))
    Else
        App.feAppMessage(FCM_WARNING, "Surface creation may need manual boundary setup")
    End If

    ' =============================================
    ' Create additional geometry: arc and spline
    ' =============================================

    ' Arc: center at (150, 25, 0), start at (160, 25, 0), 180 degrees
    Dim arcID As Long
    rc = App.feLineArc(150, 25, 0, 160, 25, 0, 180.0, 0, 0, 1, arcID)
    App.feAppMessage(FCM_NORMAL, "Created arc: curve " + Str$(arcID))

    ' Create a second line and ruled surface
    Dim topLine As Long
    rc = App.feLineDir(200, 0, 0, 200, 50, 0, topLine)

    Dim bottomLine As Long
    rc = App.feLineDir(250, 0, 0, 250, 50, 0, bottomLine)

    ' Ruled surface between two lines
    Dim ruledSurf As Long
    rc = App.feSurfaceRuled(topLine, bottomLine, ruledSurf)
    If rc = FE_OK Then
        App.feAppMessage(FCM_NORMAL, "Created ruled surface " + Str$(ruledSurf))
    End If

    ' =============================================
    ' Set mesh size and mesh surfaces
    ' =============================================

    ' Set default mesh size
    rc = App.feMeshSize(5.0)

    ' Create material and property for meshing
    Dim mt As femap.Matl
    Set mt = App.feMaterial
    mt.title = "Steel"
    mt.type = 0
    mt.mval(0) = 200000.0    ' E [MPa]
    mt.mval(1) = 76900.0     ' G [MPa]
    mt.mval(2) = 0.3          ' NU
    mt.mval(3) = 7.85E-09    ' RHO [tonne/mm^3]
    Dim matlID As Long
    matlID = mt.NextEmptyID
    rc = mt.Put(matlID)

    Dim pr As femap.Prop
    Set pr = App.feProperty
    pr.title = "Plate t=3.0"
    pr.type = FET_L_PLATE
    pr.matlID = matlID
    pr.pval(0) = 3.0
    Dim propID As Long
    propID = pr.NextEmptyID
    rc = pr.Put(propID)

    ' Select surfaces to mesh
    Dim surfSet As femap.Set
    Set surfSet = App.feSet
    surfSet.AddAll(FT_SURFACE)

    If surfSet.Count > 0 Then
        rc = App.feMeshSurface(surfSet.ID, 0)
        If rc = FE_OK Then
            App.feAppMessage(FCM_NORMAL, "Meshed " + Str$(surfSet.Count) + " surfaces")
        Else
            App.feAppMessage(FCM_WARNING, "Meshing may require manual mesh size setup")
        End If
    End If

    ' =============================================
    ' Merge coincident nodes
    ' =============================================
    Dim nodeSet As femap.Set
    Set nodeSet = App.feSet
    nodeSet.AddAll(FT_NODE)
    If nodeSet.Count > 0 Then
        rc = App.feMergeNodes(0.001, nodeSet.ID)
        App.feAppMessage(FCM_NORMAL, "Merged coincident nodes (tol=0.001)")
    End If

    App.feViewRegenerate(0)
    App.feViewAutoscaleAll(0)
    App.feAppMessage(FCM_HIGHLIGHT, "Geometry and meshing complete")
End Sub
