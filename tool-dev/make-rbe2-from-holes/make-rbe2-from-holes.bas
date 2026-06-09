' make-rbe2-from-holes.bas
' -----------------------------------------------------------------------------
' Select clearance-hole (bolt-hole) geometry and let Femap build one RBE2 spider
' per hole automatically. Works on either:
'   - SURFACES  (solid models: a bore is 2+ cylindrical surfaces), or
'   - CURVES    (shell/plate models: a hole edge is 2+ half-circle curves)
' chosen via an up-front mode prompt (Femap's selector is entity-type specific).
'
' A single hole is usually modeled as 2+ pieces that SHARE the seam points of the
' bore/edge. This tool groups the selected geometry into holes by shared geometric
' points (union-find), then for each hole:
'   - gathers every mesh node on the hole's surface(s)/curve(s)
'     (FGD_NODE_ATSURFACE / FGD_NODE_ATCURVE)
'   - creates a new independent node at the centroid of those nodes (on the axis,
'     or the in-plane circle center for a shell hole)
'   - creates an RBE2 (rigid): independent = center node, dependent = bore/edge
'     nodes. Dependent DOF follows the mode: 123 for surfaces (solid nodes have no
'     rotational stiffness), 123456 for curves (shell nodes carry rotations).
'
' Options (single confirm dialog before anything is written to the model):
'   - apply a thermal expansion coefficient (CTE) to the created RBE2s: either pick
'     a model material (uses its thermal-expansion coeff) or enter a value.
'   - project the new center nodes onto a user-picked plane (fePlanePick) after
'     creation. Each node moves ALONG ITS HOLE AXIS to the plane so it stays centered
'     on the hole for any plane tilt (axis from ArcCircleInfo / feVectorAxisOfSurface;
'     orthogonal projection is used as a fallback if a hole's axis can't be read).
'
' Assumptions / limits (v1):
'   - Select ONLY hole surfaces (or curves) of one geometry type per run. Entities
'     are grouped into one hole iff they share a geometric point, so distinct holes
'     (separated by the plate) stay separate.
'   - Center node is the simple node centroid -> lands on the bore axis (solid) or
'     the hole center in the shell plane (curves).
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long, k As Long, d As Long, h As Long

    ' ============================================================
    ' Section 0: Choose geometry type (surfaces vs curves)
    ' ============================================================
    Begin Dialog ModeDlg 250, 120, "RBE2 from Holes - Geometry Type"
        GroupBox 12, 10, 226, 64, "Hole Geometry"
        OptionGroup .geomType
            OptionButton 22, 28, 200, 12, "Surfaces (Solid Mesh)"
            OptionButton 22, 48, 200, 12, "Curves (Plate Mesh)"
        OKButton     40, 90, 70, 20
        CancelButton 140, 90, 70, 20
    End Dialog

    Dim mdlg As ModeDlg
    mdlg.geomType = 0
    If Dialog(mdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim geomEnt As Long, ptRule As Long, nodeRule As Long, geomWord As String
    If mdlg.geomType = 1 Then
        geomEnt = FT_CURVE   : ptRule = FGD_POINT_ONCURVE   : nodeRule = FGD_NODE_ATCURVE   : geomWord = "curve"
    Else
        geomEnt = FT_SURFACE : ptRule = FGD_POINT_ONSURFACE : nodeRule = FGD_NODE_ATSURFACE : geomWord = "surface"
    End If

    ' Dependent-node DOF by mode: solid (surface) nodes have no rotational
    ' stiffness -> couple 123 only; shell (curve) nodes carry rotations -> 123456.
    Dim depDOF(5) As Long, dofStr As String
    For d = 0 To 5
        depDOF(d) = 0
    Next d
    depDOF(0) = 1 : depDOF(1) = 1 : depDOF(2) = 1
    If mdlg.geomType = 1 Then
        depDOF(3) = 1 : depDOF(4) = 1 : depDOF(5) = 1
        dofStr = "123456"
    Else
        dofStr = "123"
    End If

    ' ============================================================
    ' Section 1: Select hole geometry
    ' ============================================================
    Dim geomSet As femap.Set
    Set geomSet = App.feSet

    rc = geomSet.Select(geomEnt, True, "Select clearance-hole " + geomWord + "s")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No " + geomWord + "s selected - exiting")
        Exit Sub
    End If

    Dim nGeom As Long
    nGeom = geomSet.Count
    If nGeom = 0 Then
        App.feAppMessage(FCM_ERROR, "No " + geomWord + "s selected - exiting")
        Exit Sub
    End If

    Dim geomIDs() As Long
    ReDim geomIDs(nGeom - 1)
    Dim sID As Long
    i = 0
    sID = geomSet.First()
    Do While sID > 0
        geomIDs(i) = sID
        i = i + 1
        sID = geomSet.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(nGeom) + " " + geomWord + "(s)")

    ' ============================================================
    ' Section 2: Get the bounding points of each surface
    ' ============================================================
    Dim ptSet As femap.Set
    Set ptSet = App.feSet

    Dim ptCnt() As Long
    ReDim ptCnt(nGeom - 1)
    Dim maxPts As Long
    maxPts = 0

    For i = 0 To nGeom - 1
        ptSet.Clear()
        ptSet.AddRule(geomIDs(i), ptRule)
        ptCnt(i) = ptSet.Count
        If ptCnt(i) > maxPts Then maxPts = ptCnt(i)
    Next i

    If maxPts = 0 Then
        App.feAppMessage(FCM_ERROR, "Selected " + geomWord + "s have no geometric points - cannot group into holes")
        Exit Sub
    End If

    Dim ptArr() As Long
    ReDim ptArr(nGeom - 1, maxPts - 1)
    Dim pID As Long, pIdx As Long
    For i = 0 To nGeom - 1
        ptSet.Clear()
        ptSet.AddRule(geomIDs(i), ptRule)
        pIdx = 0
        pID = ptSet.First()
        Do While pID > 0
            ptArr(i, pIdx) = pID
            pIdx = pIdx + 1
            pID = ptSet.Next()
        Loop
    Next i

    ' ============================================================
    ' Section 3: Group surfaces into holes by shared points (union-find)
    ' ============================================================
    Dim parent() As Long
    ReDim parent(nGeom - 1)
    For i = 0 To nGeom - 1
        parent(i) = i
    Next i

    For i = 0 To nGeom - 2
        For j = i + 1 To nGeom - 1
            If FindRoot(parent, i) <> FindRoot(parent, j) Then
                If SharePoint(ptArr, ptCnt, i, j) Then
                    parent(FindRoot(parent, j)) = FindRoot(parent, i)
                End If
            End If
        Next j
    Next i

    ' Distinct roots = distinct holes
    Dim holeRoot() As Long
    ReDim holeRoot(nGeom - 1)
    Dim nHoles As Long
    nHoles = 0
    Dim r As Long, seen As Boolean
    For i = 0 To nGeom - 1
        r = FindRoot(parent, i)
        seen = False
        For j = 0 To nHoles - 1
            If holeRoot(j) = r Then seen = True
        Next j
        If Not seen Then
            holeRoot(nHoles) = r
            nHoles = nHoles + 1
        End If
    Next i

    ' ============================================================
    ' Section 4: Count bore nodes per hole (for the summary)
    ' ============================================================
    Dim nodeSet As femap.Set
    Set nodeSet = App.feSet

    Dim holeNodeCnt() As Long
    ReDim holeNodeCnt(nHoles - 1)
    Dim totalDep As Long
    totalDep = 0
    Dim emptyHoles As Long
    emptyHoles = 0

    For h = 0 To nHoles - 1
        nodeSet.Clear()
        For i = 0 To nGeom - 1
            If FindRoot(parent, i) = holeRoot(h) Then
                nodeSet.AddRule(geomIDs(i), nodeRule)
            End If
        Next i
        holeNodeCnt(h) = nodeSet.Count
        totalDep = totalDep + holeNodeCnt(h)
        If holeNodeCnt(h) = 0 Then emptyHoles = emptyHoles + 1
    Next h

    ' ============================================================
    ' Section 5: Confirm + options dialog (nothing written before OK)
    ' ============================================================
    Dim line1 As String, line2 As String, line3 As String, line4 As String
    line1 = "Geometry selected:  " + Trim$(Str$(nGeom)) + "  " + geomWord + "(s)"
    line2 = "Holes identified:   " + Trim$(Str$(nHoles)) + "  (grouped by shared points)"
    line3 = "Total nodes:        " + Trim$(Str$(totalDep))
    If emptyHoles > 0 Then
        line4 = "WARNING: " + Trim$(Str$(emptyHoles)) + " hole(s) have no mesh nodes - will be skipped."
    Else
        line4 = ""
    End If

    Dim dofLine As String
    dofLine = "RBE2 dependent DOF: " + dofStr + "   (" + geomWord + " mode)"

    ' Build the material list for the CTE dropdown
    Dim mtl As femap.Matl
    Set mtl = App.feMatl
    Dim matCount As Long
    matCount = 0
    mtl.Reset
    Do While mtl.Next()
        matCount = matCount + 1
    Loop

    Dim matIDs() As Long
    Dim matNames() As String
    If matCount > 0 Then
        ReDim matIDs(matCount - 1)
        ReDim matNames(matCount - 1)
        Dim mi As Long
        mi = 0
        mtl.Reset
        Do While mtl.Next()
            matIDs(mi)   = mtl.ID
            matNames(mi) = Trim$(Str$(mtl.ID)) + " - " + mtl.title
            mi = mi + 1
        Loop
    Else
        ReDim matIDs(0)
        ReDim matNames(0)
        matIDs(0)   = 0
        matNames(0) = "(no materials in model)"
    End If

    Begin Dialog HoleDlg 330, 268, "Create RBE2 Spiders from Holes"
        Text       12, 8,  306, 12, line1
        Text       12, 22, 306, 12, line2
        Text       12, 36, 306, 12, line3
        Text       12, 50, 306, 12, line4
        Text       12, 64, 306, 12, dofLine
        GroupBox   12, 82, 306, 96, "Thermal expansion (optional)"
        CheckBox   22, 98, 290, 12, "Apply CTE to RBE2s", .chkCTE
        OptionGroup .cteSource
            OptionButton 22, 118, 96, 12, "From material:"
            OptionButton 22, 146, 96, 12, "Enter value:"
        DropListBox 120, 116, 188, 60, matNames(), .matPick
        TextBox     120, 144, 90, 12, .cteVal
        CheckBox   12, 184, 306, 12, "Project center nodes onto a plane (after creation)", .chkProject
        Text       12, 206, 306, 12, "Click OK to create the spiders, Cancel to abort."
        OKButton   76, 238, 80, 20
        CancelButton 176, 238, 80, 20
    End Dialog

    Dim dlg As HoleDlg
    dlg.cteVal     = "0.0"
    dlg.chkCTE     = 0
    dlg.cteSource  = 0          ' 0 = from material, 1 = enter value
    dlg.matPick    = 0
    dlg.chkProject = 0
    If matCount = 0 Then dlg.cteSource = 1

    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim doProject As Boolean
    doProject = (dlg.chkProject <> 0)

    Dim applyCTE As Boolean
    Dim cteValue As Double
    Dim cteNote As String
    applyCTE = (dlg.chkCTE <> 0)
    cteValue = 0.0
    cteNote  = ""
    If applyCTE Then
        If dlg.cteSource = 0 Then
            ' From material
            If matCount > 0 Then
                rc = mtl.Get(matIDs(dlg.matPick))
                If rc = FE_OK Then
                    cteValue = mtl.mval(36)
                    cteNote  = " (material " + matNames(dlg.matPick) + ")"
                Else
                    App.feAppMessage(FCM_WARNING, "Could not read selected material - CTE not applied")
                    applyCTE = False
                End If
            Else
                App.feAppMessage(FCM_WARNING, "No materials in model - CTE not applied")
                applyCTE = False
            End If
        Else
            ' Manual value
            cteValue = CDbl(dlg.cteVal)
            cteNote  = " (entered)"
        End If
    End If

    ' ============================================================
    ' Section 6: Create one RBE2 spider per hole
    ' ============================================================
    Dim nd As femap.Node
    Set nd = App.feNode

    Dim spiderCount As Long
    spiderCount = 0

    ' Parallel arrays of created center nodes + a representative hole geometry ID
    ' (any piece of a hole is coaxial) for optional plane projection later.
    Dim projCenterID() As Long, projGeomID() As Long, projN As Long
    ReDim projCenterID(nHoles - 1)
    ReDim projGeomID(nHoles - 1)
    projN = 0

    App.feAppLock

    For h = 0 To nHoles - 1
        ' Gather this hole's bore nodes
        Dim repGeom As Long
        repGeom = -1
        nodeSet.Clear()
        For i = 0 To nGeom - 1
            If FindRoot(parent, i) = holeRoot(h) Then
                nodeSet.AddRule(geomIDs(i), nodeRule)
                If repGeom < 0 Then repGeom = geomIDs(i)
            End If
        Next i

        Dim nDep As Long
        nDep = nodeSet.Count
        If nDep > 0 Then
            Dim vNodes As Variant
            nodeSet.GetArray(nDep, vNodes)

            ' Centroid (node coords are always global rectangular in the API)
            Dim cx As Double, cy As Double, cz As Double
            cx = 0.0 : cy = 0.0 : cz = 0.0
            For k = 0 To nDep - 1
                rc = nd.Get(CLng(vNodes(k)))
                cx = cx + nd.x
                cy = cy + nd.y
                cz = cz + nd.z
            Next k
            cx = cx / nDep : cy = cy / nDep : cz = cz / nDep

            ' Create the independent (center) node
            Dim ndNew As femap.Node
            Set ndNew = App.feNode
            Dim centerID As Long
            centerID = ndNew.NextEmptyID
            ndNew.x = cx : ndNew.y = cy : ndNew.z = cz
            rc = ndNew.Put(centerID)

            If rc <> FE_OK Then
                App.feAppMessage(FCM_ERROR, "Hole " + Trim$(Str$(h + 1)) + ": failed to create center node")
            Else
                ' Dependent-node arrays (DOF per mode: 123 solid / 123456 shell)
                Dim vFaces As Variant, vWeights As Variant, vDOF As Variant
                ReDim vFaces(nDep - 1)
                ReDim vWeights(nDep - 1)
                ReDim vDOF(nDep * 6 - 1)
                For k = 0 To nDep - 1
                    vFaces(k)   = CLng(0)
                    vWeights(k) = CDbl(0)
                    For d = 0 To 5
                        vDOF(k * 6 + d) = CLng(depDOF(d))
                    Next d
                Next k

                ' Build the RBE2 (fresh Elem object each hole to avoid stale state)
                Dim el As femap.Elem
                Set el = App.feElem
                Dim elemID As Long
                elemID = el.NextEmptyID
                el.type     = FET_L_RIGID
                el.topology = FTO_RIGIDLIST
                el.node(0)  = centerID            ' independent node
                For d = 0 To 5                    ' independent-node DOF flags
                    el.Release(0, d) = 1
                Next d
                If applyCTE Then el.RigidThermalExpansion = cteValue

                rc = el.PutNodeList(0, nDep, vNodes, vFaces, vWeights, vDOF)
                If rc <> FE_OK Then
                    App.feAppMessage(FCM_ERROR, "Hole " + Trim$(Str$(h + 1)) + ": PutNodeList failed")
                Else
                    rc = el.Put(elemID)
                    If rc <> FE_OK Then
                        App.feAppMessage(FCM_ERROR, "Hole " + Trim$(Str$(h + 1)) + ": failed to save RBE2")
                    Else
                        spiderCount = spiderCount + 1
                        projCenterID(projN) = centerID
                        projGeomID(projN)   = repGeom
                        projN = projN + 1
                        App.feAppMessage(FCM_NORMAL, "Hole " + Trim$(Str$(h + 1)) _
                            + ": RBE2 " + Trim$(Str$(elemID)) _
                            + ", center node " + Trim$(Str$(centerID)) _
                            + ", " + Trim$(Str$(nDep)) + " dependent nodes")
                    End If
                End If
            End If
        End If
    Next h

    App.feAppUnlock

    ' ============================================================
    ' Section 7: Project center nodes onto a user-selected plane
    ' Each node moves ALONG ITS HOLE AXIS to the plane (stays centered).
    ' Falls back to orthogonal projection if a hole's axis can't be read.
    ' ============================================================
    Dim projDone As Long, alongCnt As Long, orthoCnt As Long
    projDone = 0 : alongCnt = 0 : orthoCnt = 0
    If doProject And projN > 0 Then
        Dim plBase(2) As Double, plNormal(2) As Double, plAxis(2) As Double
        rc = App.fePlanePick("Select plane to project center nodes onto", plBase, plNormal, plAxis)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Plane selection cancelled - center nodes not projected")
        Else
            Dim nLen2 As Double
            nLen2 = plNormal(0) * plNormal(0) + plNormal(1) * plNormal(1) + plNormal(2) * plNormal(2)
            If nLen2 <= 0.0 Then nLen2 = 1.0     ' guard against a degenerate normal

            Dim cv As femap.Curve
            Set cv = App.feCurve

            Dim p As Long
            Dim pcx As Double, pcy As Double, pcz As Double
            Dim ax As Double, ay As Double, az As Double, axisOK As Boolean
            Dim aCtr As Variant, aNrm As Variant, aSp As Variant, aEp As Variant, aAng As Double, aRad As Double
            Dim sBase As Variant, sDir As Variant
            Dim denom As Double, tnum As Double, tt As Double, dphi As Double
            Dim Nx As Double, Ny As Double, Nz As Double

            Nx = plNormal(0) : Ny = plNormal(1) : Nz = plNormal(2)

            App.feAppLock
            For p = 0 To projN - 1
                If nd.Get(projCenterID(p)) = FE_OK Then
                    pcx = nd.x : pcy = nd.y : pcz = nd.z

                    ' --- hole axis a for this node's geometry ---
                    axisOK = False
                    ax = 0.0 : ay = 0.0 : az = 0.0
                    If mdlg.geomType = 1 Then
                        ' curve / arc: normal from ArcCircleInfo is the axis
                        If cv.Get(projGeomID(p)) = FE_OK Then
                            If cv.ArcCircleInfo(aCtr, aNrm, aSp, aEp, aAng, aRad) = FE_OK Then
                                ax = CDbl(aNrm(0)) : ay = CDbl(aNrm(1)) : az = CDbl(aNrm(2))
                                axisOK = True
                            End If
                        End If
                    Else
                        ' surface / cylinder: revolution vector is the axis
                        If App.feVectorAxisOfSurface(projGeomID(p), sBase, sDir) = FE_OK Then
                            ax = CDbl(sDir(0)) : ay = CDbl(sDir(1)) : az = CDbl(sDir(2))
                            axisOK = True
                        End If
                    End If

                    denom = ax * Nx + ay * Ny + az * Nz
                    If axisOK And Abs(denom) > 0.00000001 Then
                        ' along-axis: intersect the hole centerline with the plane
                        tnum = (plBase(0) - pcx) * Nx + (plBase(1) - pcy) * Ny + (plBase(2) - pcz) * Nz
                        tt = tnum / denom
                        nd.x = pcx + tt * ax
                        nd.y = pcy + tt * ay
                        nd.z = pcz + tt * az
                        alongCnt = alongCnt + 1
                    Else
                        ' orthogonal fallback: drop perpendicular onto the plane
                        dphi = ((pcx - plBase(0)) * Nx + (pcy - plBase(1)) * Ny + (pcz - plBase(2)) * Nz) / nLen2
                        nd.x = pcx - dphi * Nx
                        nd.y = pcy - dphi * Ny
                        nd.z = pcz - dphi * Nz
                        orthoCnt = orthoCnt + 1
                    End If
                    nd.Put(projCenterID(p))
                    projDone = projDone + 1
                End If
            Next p
            App.feAppUnlock
        End If
    End If

    ' ============================================================
    ' Section 8: Report
    ' ============================================================
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Make RBE2 from Holes - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Geometry selected:     " + Str$(nGeom) + " " + geomWord + "(s)")
    App.feAppMessage(FCM_NORMAL, "  Holes identified:      " + Str$(nHoles))
    App.feAppMessage(FCM_NORMAL, "  RBE2 spiders created:  " + Str$(spiderCount))
    App.feAppMessage(FCM_NORMAL, "  Dependent DOF:         " + dofStr)
    If emptyHoles > 0 Then
        App.feAppMessage(FCM_WARNING, "  Holes skipped (no nodes): " + Str$(emptyHoles))
    End If
    If applyCTE Then
        App.feAppMessage(FCM_NORMAL, "  CTE applied to RBE2s:  " + Str$(cteValue) + cteNote)
    End If
    If doProject Then
        App.feAppMessage(FCM_NORMAL, "  Center nodes projected:" + Str$(projDone) _
            + "  (along-axis " + Trim$(Str$(alongCnt)) + ", orthogonal " + Trim$(Str$(orthoCnt)) + ")")
        If orthoCnt > 0 Then
            App.feAppMessage(FCM_WARNING, "  " + Trim$(Str$(orthoCnt)) _
                + " node(s) used orthogonal projection (hole axis unreadable or parallel to plane)")
        End If
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub

' -----------------------------------------------------------------------------
' Union-find root with path compression. parent() is modified in place.
' -----------------------------------------------------------------------------
Function FindRoot(parent() As Long, x As Long) As Long
    Dim r As Long, c As Long, nxt As Long
    r = x
    Do While parent(r) <> r
        r = parent(r)
    Loop
    c = x
    Do While parent(c) <> r
        nxt = parent(c)
        parent(c) = r
        c = nxt
    Loop
    FindRoot = r
End Function

' -----------------------------------------------------------------------------
' True if surfaces a and b share at least one geometric point.
' -----------------------------------------------------------------------------
Function SharePoint(ptArr() As Long, ptCnt() As Long, a As Long, b As Long) As Boolean
    Dim ia As Long, ib As Long
    SharePoint = False
    For ia = 0 To ptCnt(a) - 1
        For ib = 0 To ptCnt(b) - 1
            If ptArr(a, ia) = ptArr(b, ib) Then
                SharePoint = True
                Exit Function
            End If
        Next ib
    Next ia
End Function
