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
'     nodes, all 6 DOF (123456) coupled.
'
' Options (single confirm dialog before anything is written to the model):
'   - apply a thermal expansion coefficient (CTE) to the created RBE2s
'   - collect the new center nodes + RBE2 elements into a group
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
        GroupBox 12, 10, 226, 64, "Hole geometry"
        OptionGroup .geomType
            OptionButton 22, 28, 200, 12, "Surfaces (solid bore)"
            OptionButton 22, 48, 200, 12, "Curves (shell / plate hole edge)"
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
    line3 = "Total bore nodes:   " + Trim$(Str$(totalDep))
    If emptyHoles > 0 Then
        line4 = "WARNING: " + Trim$(Str$(emptyHoles)) + " hole(s) have no mesh nodes - will be skipped."
    Else
        line4 = ""
    End If

    Begin Dialog HoleDlg 330, 222, "Create RBE2 Spiders from Holes"
        Text       12, 8,  306, 12, line1
        Text       12, 22, 306, 12, line2
        Text       12, 36, 306, 12, line3
        Text       12, 50, 306, 12, line4
        GroupBox   12, 70, 306, 56, "Thermal expansion"
        CheckBox   22, 86, 250, 12, "Apply CTE (thermal expansion coeff) to RBE2s", .chkCTE
        Text       22, 104, 60, 12, "CTE value:"
        TextBox    86, 102, 90, 12, .cteVal
        CheckBox   12, 136, 306, 12, "Put new center nodes + RBE2s in a group", .chkGroup
        Text       12, 156, 306, 12, "Click OK to create the spiders, Cancel to abort."
        OKButton   76, 192, 80, 20
        CancelButton 176, 192, 80, 20
    End Dialog

    Dim dlg As HoleDlg
    dlg.cteVal  = "0.0"
    dlg.chkCTE  = 0
    dlg.chkGroup = 0

    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim applyCTE As Boolean
    Dim cteValue As Double
    applyCTE = (dlg.chkCTE <> 0)
    cteValue = 0.0
    If applyCTE Then cteValue = CDbl(dlg.cteVal)

    Dim doGroup As Boolean
    doGroup = (dlg.chkGroup <> 0)

    ' ============================================================
    ' Section 6: Create one RBE2 spider per hole
    ' ============================================================
    Dim nd As femap.Node
    Set nd = App.feNode

    Dim createdNodeSet As femap.Set
    Set createdNodeSet = App.feSet
    Dim createdElemSet As femap.Set
    Set createdElemSet = App.feSet

    Dim spiderCount As Long
    spiderCount = 0

    App.feAppLock

    For h = 0 To nHoles - 1
        ' Gather this hole's bore nodes
        nodeSet.Clear()
        For i = 0 To nGeom - 1
            If FindRoot(parent, i) = holeRoot(h) Then
                nodeSet.AddRule(geomIDs(i), nodeRule)
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
                createdNodeSet.Add(centerID)

                ' Dependent-node arrays (all 6 DOF coupled)
                Dim vFaces As Variant, vWeights As Variant, vDOF As Variant
                ReDim vFaces(nDep - 1)
                ReDim vWeights(nDep - 1)
                ReDim vDOF(nDep * 6 - 1)
                For k = 0 To nDep - 1
                    vFaces(k)   = CLng(0)
                    vWeights(k) = CDbl(0)
                    For d = 0 To 5
                        vDOF(k * 6 + d) = CLng(1)
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
                        createdElemSet.Add(elemID)
                        spiderCount = spiderCount + 1
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
    ' Section 7: Optional group of created entities
    ' ============================================================
    If doGroup And spiderCount > 0 Then
        Dim gp As femap.Group
        Set gp = App.feGroup
        Dim grpID As Long
        grpID = gp.NextEmptyID
        gp.title = "RBE2 Hole Spiders"
        rc = gp.Put(grpID)
        If rc = FE_OK Then
            gp.SetAdd(FT_NODE, createdNodeSet.ID)
            gp.SetAdd(FT_ELEM, createdElemSet.ID)
            App.feAppMessage(FCM_NORMAL, "Created group " + Trim$(Str$(grpID)) + " 'RBE2 Hole Spiders'")
        Else
            App.feAppMessage(FCM_WARNING, "Could not create the results group")
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
    If emptyHoles > 0 Then
        App.feAppMessage(FCM_WARNING, "  Holes skipped (no nodes): " + Str$(emptyHoles))
    End If
    If applyCTE Then
        App.feAppMessage(FCM_NORMAL, "  CTE applied to RBE2s:  " + Str$(cteValue))
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
