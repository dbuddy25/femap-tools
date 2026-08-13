' Point RBE2 Spiders.bas
' -----------------------------------------------------------------------------
' Build one RBE2 spider per picked POINT. Works on either:
'   - MESH POINTS (FT_MESH_POINT), or
'   - GEOMETRIC POINTS (FT_POINT)
' chosen via an up-front mode prompt (Femap's selector is entity-type specific).
'
' For each picked point:
'   - a new independent node is created AT the point location (coincident nodes
'     with existing mesh nodes are fine and expected - a mesh point normally
'     already forced a node there, and that node becomes a zero-length leg)
'   - the surrounding mesh nodes are gathered from a user-selected candidate
'     pool, either by RADIUS or by N NEAREST
'   - an RBE2 (rigid) is created: independent = new center node,
'     dependent = the gathered ring nodes
'
' There is no geometry to infer the leg set from (unlike the hole-based tool),
' so scoping is explicit: the user selects the candidate node pool up front
' (a group, a surface, a part - whatever) and the distance filter runs only
' against that pool. This is what keeps a spider from reaching through a plate
' thickness or grabbing an adjacent part.
'
' Options (single options dialog, then a confirm dialog with the tally; nothing
' is written to the model until the confirm dialog is OK'd):
'   - dependent DOF: 123 (solid mesh) or 123456 (shell mesh)
'   - apply a thermal expansion coefficient (CTE) to the created RBE2s: either
'     pick a model material (uses its thermal-expansion coeff) or enter a value
'   - project the new center nodes onto a user-picked plane (fePlanePick).
'     Projection is ORTHOGONAL (along the plane normal) - unlike the hole tool
'     there is no per-spider axis to travel along.
'
' Assumptions / limits (v1):
'   - Center node sits exactly at the point location (before optional projection).
'   - Mesh point location: the on-geometry location if the mesh point is
'     associated to geometry, otherwise the underlying geometric point's coords.
'   - Node coords from the API are always global rectangular, so the distance
'     filter is a plain global-rectangular sphere.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, k As Long, d As Long, p As Long

    ' ============================================================
    ' Section 0: Choose point source + dependent DOF
    ' ============================================================
    Begin Dialog ModeDlg 260, 190, "Point RBE2 Spiders - Setup"
        GroupBox 12, 8, 236, 64, "Spider Center From"
        OptionGroup .ptSource
            OptionButton 22, 26, 216, 12, "Mesh Points"
            OptionButton 22, 46, 216, 12, "Points (geometry)"
        GroupBox 12, 80, 236, 64, "RBE2 Dependent DOF"
        OptionGroup .dofMode
            OptionButton 22, 98, 216, 12, "123456  (shell / plate mesh)"
            OptionButton 22, 118, 216, 12, "123     (solid mesh)"
        OKButton     44, 158, 70, 20
        CancelButton 144, 158, 70, 20
    End Dialog

    Dim mdlg As ModeDlg
    mdlg.ptSource = 0
    mdlg.dofMode  = 0
    If Dialog(mdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim useMeshPts As Boolean
    Dim srcEnt As Long, srcWord As String
    useMeshPts = (mdlg.ptSource = 0)
    If useMeshPts Then
        srcEnt = FT_MESH_POINT : srcWord = "mesh point"
    Else
        srcEnt = FT_POINT      : srcWord = "point"
    End If

    Dim depDOF(5) As Long, dofStr As String
    For d = 0 To 5
        depDOF(d) = 0
    Next d
    depDOF(0) = 1 : depDOF(1) = 1 : depDOF(2) = 1
    If mdlg.dofMode = 0 Then
        depDOF(3) = 1 : depDOF(4) = 1 : depDOF(5) = 1
        dofStr = "123456"
    Else
        dofStr = "123"
    End If

    ' ============================================================
    ' Section 1: Select the points and resolve each to an XYZ
    ' ============================================================
    Dim srcSet As femap.Set
    Set srcSet = App.feSet

    rc = srcSet.Select(srcEnt, True, "Select " + srcWord + "s for spider centers")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No " + srcWord + "s selected - exiting")
        Exit Sub
    End If

    Dim nPts As Long
    nPts = srcSet.Count
    If nPts = 0 Then
        App.feAppMessage(FCM_ERROR, "No " + srcWord + "s selected - exiting")
        Exit Sub
    End If

    Dim srcID() As Long
    Dim ptX() As Double, ptY() As Double, ptZ() As Double
    Dim ptOK() As Boolean
    ReDim srcID(nPts - 1)
    ReDim ptX(nPts - 1)
    ReDim ptY(nPts - 1)
    ReDim ptZ(nPts - 1)
    ReDim ptOK(nPts - 1)

    Dim sID As Long
    i = 0
    sID = srcSet.First()
    Do While sID > 0
        srcID(i) = sID
        i = i + 1
        sID = srcSet.Next()
    Loop

    Dim gPt As femap.Point
    Set gPt = App.fePoint
    Dim mPt As Object
    Dim vLoc As Variant
    Dim underPt As Long
    Dim badPts As Long
    badPts = 0

    If useMeshPts Then Set mPt = App.feMeshHardPoint

    For i = 0 To nPts - 1
        ptOK(i) = False
        If useMeshPts Then
            If mPt.Get(srcID(i)) = FE_OK Then
                If mPt.OnGeometryType <> 0 Then
                    ' Snapped to geometry - this is where the mesh node lands
                    vLoc = mPt.vLocationOnGeometry
                    ptX(i) = CDbl(vLoc(0))
                    ptY(i) = CDbl(vLoc(1))
                    ptZ(i) = CDbl(vLoc(2))
                    ptOK(i) = True
                Else
                    ' Free mesh point - use its underlying geometric point
                    underPt = mPt.PointID
                    If underPt > 0 Then
                        If gPt.Get(underPt) = FE_OK Then
                            ptX(i) = gPt.x : ptY(i) = gPt.y : ptZ(i) = gPt.z
                            ptOK(i) = True
                        End If
                    End If
                End If
            End If
        Else
            If gPt.Get(srcID(i)) = FE_OK Then
                ptX(i) = gPt.x : ptY(i) = gPt.y : ptZ(i) = gPt.z
                ptOK(i) = True
            End If
        End If
        If Not ptOK(i) Then badPts = badPts + 1
    Next i

    If badPts = nPts Then
        App.feAppMessage(FCM_ERROR, "Could not read a location for any selected " + srcWord + " - exiting")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(nPts) + " " + srcWord + "(s)")

    ' ============================================================
    ' Section 2: Select the candidate node pool
    ' This is the scoping step - the distance filter never looks outside it.
    ' ============================================================
    Dim candSet As femap.Set
    Set candSet = App.feSet

    rc = candSet.Select(FT_NODE, True, "Select candidate nodes for the spider legs")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No candidate nodes selected - exiting")
        Exit Sub
    End If

    Dim nd As femap.Node
    Set nd = App.feNode

    Dim nCand As Long
    Dim vCandID As Variant, vXYZ As Variant
    Dim vLayer As Variant, vColor As Variant, vNType As Variant
    Dim vDefCS As Variant, vOutCS As Variant, vPermBC As Variant
    rc = nd.GetAllArray(candSet.ID, nCand, vCandID, vXYZ, vLayer, vColor, _
                        vNType, vDefCS, vOutCS, vPermBC)
    If rc <> FE_OK Or nCand = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read candidate node coordinates - exiting")
        Exit Sub
    End If

    ' Unpack into plain typed arrays (much faster to index in the inner loops)
    Dim candID() As Long
    Dim candX() As Double, candY() As Double, candZ() As Double
    ReDim candID(nCand - 1)
    ReDim candX(nCand - 1)
    ReDim candY(nCand - 1)
    ReDim candZ(nCand - 1)
    For k = 0 To nCand - 1
        candID(k) = CLng(vCandID(k))
        candX(k)  = CDbl(vXYZ(k * 3))
        candY(k)  = CDbl(vXYZ(k * 3 + 1))
        candZ(k)  = CDbl(vXYZ(k * 3 + 2))
    Next k

    App.feAppMessage(FCM_NORMAL, "Candidate node pool: " + Str$(nCand) + " node(s)")

    ' ============================================================
    ' Section 3: Options dialog (leg selection, CTE, projection)
    ' ============================================================
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
    Dim mi As Long
    If matCount > 0 Then
        ReDim matIDs(matCount - 1)
        ReDim matNames(matCount - 1)
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

    Dim hdrLine As String, poolLine As String, dofLine As String
    hdrLine  = Trim$(Str$(nPts)) + " " + srcWord + "(s) selected"
    poolLine = "Candidate node pool: " + Trim$(Str$(nCand)) + " node(s)"
    dofLine  = "RBE2 dependent DOF: " + dofStr

    Begin Dialog OptDlg 330, 320, "Point RBE2 Spiders - Options"
        Text       12, 8,  306, 12, hdrLine
        Text       12, 22, 306, 12, poolLine
        Text       12, 36, 306, 12, dofLine
        GroupBox   12, 54, 306, 76, "Leg Selection"
        OptionGroup .legMode
            OptionButton 22, 72, 96, 12, "Radius:"
            OptionButton 22, 98, 96, 12, "N nearest:"
        TextBox    124, 70, 90, 12, .radVal
        TextBox    124, 96, 90, 12, .nearVal
        GroupBox   12, 136, 306, 96, "CTE (optional)"
        CheckBox   22, 152, 290, 12, "Apply CTE to RBE2s", .chkCTE
        OptionGroup .cteSource
            OptionButton 22, 172, 96, 12, "From mat:"
            OptionButton 22, 200, 96, 12, "Enter value:"
        DropListBox 120, 170, 188, 60, matNames(), .matPick
        TextBox     120, 198, 90, 12, .cteVal
        CheckBox   12, 240, 306, 12, "Project center nodes onto a plane", .chkProject
        Text       12, 260, 306, 12, "Next dialog shows the leg tally before anything is written."
        OKButton   76, 288, 80, 20
        CancelButton 176, 288, 80, 20
    End Dialog

    Dim dlg As OptDlg
    dlg.legMode    = 0
    dlg.radVal     = "1.0"
    dlg.nearVal    = "8"
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

    Dim byRadius As Boolean
    Dim radius As Double, rad2 As Double, nNear As Long
    byRadius = (dlg.legMode = 0)
    radius = 0.0 : rad2 = 0.0 : nNear = 0
    If byRadius Then
        radius = CDbl(dlg.radVal)
        If radius <= 0.0 Then
            App.feAppMessage(FCM_ERROR, "Radius must be greater than zero - exiting")
            Exit Sub
        End If
        rad2 = radius * radius
    Else
        nNear = CLng(dlg.nearVal)
        If nNear < 1 Then
            App.feAppMessage(FCM_ERROR, "N nearest must be at least 1 - exiting")
            Exit Sub
        End If
        If nNear > nCand Then nNear = nCand
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
            cteValue = CDbl(dlg.cteVal)
            cteNote  = " (entered)"
        End If
    End If

    ' ============================================================
    ' Section 4: Tally pass - how many legs would each spider get?
    ' Nothing is written to the model here.
    ' ============================================================
    Dim legCnt() As Long
    ReDim legCnt(nPts - 1)

    Dim totalLegs As Long, emptyPts As Long, minLegs As Long, maxLegs As Long
    totalLegs = 0 : emptyPts = 0 : minLegs = -1 : maxLegs = 0

    Dim legID() As Long, legD2() As Double
    ReDim legID(nCand - 1)
    ReDim legD2(nCand - 1)

    For p = 0 To nPts - 1
        If ptOK(p) Then
            legCnt(p) = GatherLegs(nCand, candID, candX, candY, candZ, _
                                   ptX(p), ptY(p), ptZ(p), _
                                   byRadius, rad2, nNear, legID, legD2)
            totalLegs = totalLegs + legCnt(p)
            If legCnt(p) = 0 Then emptyPts = emptyPts + 1
            If minLegs < 0 Or legCnt(p) < minLegs Then minLegs = legCnt(p)
            If legCnt(p) > maxLegs Then maxLegs = legCnt(p)
        Else
            legCnt(p) = 0
        End If
    Next p
    If minLegs < 0 Then minLegs = 0

    Dim cLine1 As String, cLine2 As String, cLine3 As String, cLine4 As String, cLine5 As String
    cLine1 = "Spiders to create:  " + Trim$(Str$(nPts - badPts - emptyPts))
    If byRadius Then
        cLine2 = "Leg selection:      radius " + Trim$(Str$(radius))
    Else
        cLine2 = "Leg selection:      " + Trim$(Str$(nNear)) + " nearest"
    End If
    cLine3 = "Total legs:         " + Trim$(Str$(totalLegs)) _
           + "   (min " + Trim$(Str$(minLegs)) + " / max " + Trim$(Str$(maxLegs)) + " per spider)"
    cLine4 = "Dependent DOF:      " + dofStr
    cLine5 = ""
    If badPts > 0 Then
        cLine5 = "WARNING: " + Trim$(Str$(badPts)) + " " + srcWord + "(s) had no readable location - skipped."
    End If
    If emptyPts > 0 Then
        If cLine5 <> "" Then cLine5 = cLine5 + "  "
        cLine5 = cLine5 + "WARNING: " + Trim$(Str$(emptyPts)) + " " + srcWord + "(s) found no legs - skipped."
    End If

    Begin Dialog ConfirmDlg 340, 160, "Point RBE2 Spiders - Confirm"
        Text       12, 8,  316, 12, cLine1
        Text       12, 22, 316, 12, cLine2
        Text       12, 36, 316, 12, cLine3
        Text       12, 50, 316, 12, cLine4
        Text       12, 66, 316, 24, cLine5
        Text       12, 96, 316, 12, "Click OK to create the spiders, Cancel to abort."
        OKButton   80, 126, 80, 20
        CancelButton 180, 126, 80, 20
    End Dialog

    Dim cdlg As ConfirmDlg
    If Dialog(cdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    If totalLegs = 0 Then
        App.feAppMessage(FCM_ERROR, "No legs found for any " + srcWord + " - nothing created")
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: Create one RBE2 spider per point
    ' ============================================================
    Dim ndNew As femap.Node
    Set ndNew = App.feNode
    Dim el As femap.Elem

    Dim spiderCount As Long
    spiderCount = 0

    Dim centerIDs() As Long, centerN As Long
    ReDim centerIDs(nPts - 1)
    centerN = 0

    Dim nLeg As Long, centerID As Long, elemID As Long
    Dim vNodes As Variant, vFaces As Variant, vWeights As Variant, vDOF As Variant

    App.feAppLock

    For p = 0 To nPts - 1
        If ptOK(p) And legCnt(p) > 0 Then
            nLeg = GatherLegs(nCand, candID, candX, candY, candZ, _
                              ptX(p), ptY(p), ptZ(p), _
                              byRadius, rad2, nNear, legID, legD2)

            If nLeg > 0 Then
                ' Independent (center) node, at the point location
                centerID = ndNew.NextEmptyID
                ndNew.x = ptX(p) : ndNew.y = ptY(p) : ndNew.z = ptZ(p)
                rc = ndNew.Put(centerID)

                If rc <> FE_OK Then
                    App.feAppMessage(FCM_ERROR, srcWord + " " + Trim$(Str$(srcID(p))) _
                        + ": failed to create center node")
                Else
                    ReDim vNodes(nLeg - 1)
                    ReDim vFaces(nLeg - 1)
                    ReDim vWeights(nLeg - 1)
                    ReDim vDOF(nLeg * 6 - 1)
                    For k = 0 To nLeg - 1
                        vNodes(k)   = CLng(legID(k))
                        vFaces(k)   = CLng(0)
                        vWeights(k) = CDbl(0)
                        For d = 0 To 5
                            vDOF(k * 6 + d) = CLng(depDOF(d))
                        Next d
                    Next k

                    ' Fresh Elem object each spider to avoid stale state
                    Set el = App.feElem
                    elemID = el.NextEmptyID
                    el.type     = FET_L_RIGID
                    el.topology = FTO_RIGIDLIST
                    el.node(0)  = centerID            ' independent node
                    For d = 0 To 5                    ' independent-node DOF flags
                        el.Release(0, d) = 1
                    Next d
                    If applyCTE Then el.RigidThermalExpansion = cteValue

                    rc = el.PutNodeList(0, nLeg, vNodes, vFaces, vWeights, vDOF)
                    If rc <> FE_OK Then
                        App.feAppMessage(FCM_ERROR, srcWord + " " + Trim$(Str$(srcID(p))) _
                            + ": PutNodeList failed")
                    Else
                        rc = el.Put(elemID)
                        If rc <> FE_OK Then
                            App.feAppMessage(FCM_ERROR, srcWord + " " + Trim$(Str$(srcID(p))) _
                                + ": failed to save RBE2")
                        Else
                            spiderCount = spiderCount + 1
                            centerIDs(centerN) = centerID
                            centerN = centerN + 1
                            App.feAppMessage(FCM_NORMAL, srcWord + " " + Trim$(Str$(srcID(p))) _
                                + ": RBE2 " + Trim$(Str$(elemID)) _
                                + ", center node " + Trim$(Str$(centerID)) _
                                + ", " + Trim$(Str$(nLeg)) + " dependent nodes")
                        End If
                    End If
                End If
            End If
        End If
    Next p

    App.feAppUnlock

    ' ============================================================
    ' Section 6: Project center nodes onto a user-selected plane
    ' Orthogonal projection (along the plane normal) - there is no per-spider
    ' axis to travel along the way a bolt hole has one.
    ' ============================================================
    Dim projDone As Long
    projDone = 0
    If doProject And centerN > 0 Then
        Dim plBase As Variant, plNormal As Variant, plAxis As Variant
        rc = App.fePlanePick("Select plane to project center nodes onto", plBase, plNormal, plAxis)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Plane selection cancelled - center nodes not projected")
        Else
            Dim pnx As Double, pny As Double, pnz As Double, nLen2 As Double
            pnx = CDbl(plNormal(0)) : pny = CDbl(plNormal(1)) : pnz = CDbl(plNormal(2))
            nLen2 = pnx * pnx + pny * pny + pnz * pnz
            If nLen2 <= 0.0 Then
                App.feAppMessage(FCM_WARNING, "Degenerate plane normal - center nodes not projected")
            Else
                Dim pcx As Double, pcy As Double, pcz As Double, dphi As Double
                App.feAppLock
                For p = 0 To centerN - 1
                    If nd.Get(centerIDs(p)) = FE_OK Then
                        pcx = nd.x : pcy = nd.y : pcz = nd.z
                        dphi = ((pcx - CDbl(plBase(0))) * pnx _
                              + (pcy - CDbl(plBase(1))) * pny _
                              + (pcz - CDbl(plBase(2))) * pnz) / nLen2
                        nd.x = pcx - dphi * pnx
                        nd.y = pcy - dphi * pny
                        nd.z = pcz - dphi * pnz
                        nd.Put(centerIDs(p))
                        projDone = projDone + 1
                    End If
                Next p
                App.feAppUnlock
            End If
        End If
    End If

    ' ============================================================
    ' Section 7: Report
    ' ============================================================
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Point RBE2 Spiders - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  " + srcWord + "s selected:      " + Str$(nPts))
    App.feAppMessage(FCM_NORMAL, "  Candidate node pool:   " + Str$(nCand))
    If byRadius Then
        App.feAppMessage(FCM_NORMAL, "  Leg selection:         radius " + Str$(radius))
    Else
        App.feAppMessage(FCM_NORMAL, "  Leg selection:         " + Str$(nNear) + " nearest")
    End If
    App.feAppMessage(FCM_NORMAL, "  RBE2 spiders created:  " + Str$(spiderCount))
    App.feAppMessage(FCM_NORMAL, "  Total dependent nodes: " + Str$(totalLegs))
    App.feAppMessage(FCM_NORMAL, "  Dependent DOF:         " + dofStr)
    If badPts > 0 Then
        App.feAppMessage(FCM_WARNING, "  Skipped (no location):  " + Str$(badPts))
    End If
    If emptyPts > 0 Then
        App.feAppMessage(FCM_WARNING, "  Skipped (no legs):      " + Str$(emptyPts))
    End If
    If applyCTE Then
        App.feAppMessage(FCM_NORMAL, "  CTE applied to RBE2s:  " + Str$(cteValue) + cteNote)
    End If
    If doProject Then
        App.feAppMessage(FCM_NORMAL, "  Center nodes projected:" + Str$(projDone) + "  (orthogonal)")
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub

' -----------------------------------------------------------------------------
' Fill legID() with the candidate nodes that belong to the spider centered at
' (cenX, cenY, cenZ) and return how many. legD2() is scratch (squared distance).
'
' byRadius = True  -> every candidate with d^2 <= rad2, in candidate order
' byRadius = False -> the nNear closest candidates, sorted nearest-first
'
' Distances are squared throughout - no sqrt in the inner loop.
' -----------------------------------------------------------------------------
Function GatherLegs(nCand As Long, candID() As Long, _
                    candX() As Double, candY() As Double, candZ() As Double, _
                    cenX As Double, cenY As Double, cenZ As Double, _
                    byRadius As Boolean, rad2 As Double, nNear As Long, _
                    legID() As Long, legD2() As Double) As Long
    Dim k As Long, j As Long, cnt As Long
    Dim dx As Double, dy As Double, dz As Double, dd As Double

    cnt = 0

    If byRadius Then
        For k = 0 To nCand - 1
            dx = candX(k) - cenX
            dy = candY(k) - cenY
            dz = candZ(k) - cenZ
            dd = dx * dx + dy * dy + dz * dz
            If dd <= rad2 Then
                legID(cnt) = candID(k)
                legD2(cnt) = dd
                cnt = cnt + 1
            End If
        Next k
    Else
        ' Single pass, keeping the nNear best by insertion into a small array
        For k = 0 To nCand - 1
            dx = candX(k) - cenX
            dy = candY(k) - cenY
            dz = candZ(k) - cenZ
            dd = dx * dx + dy * dy + dz * dz

            If cnt < nNear Then
                ' Not full yet - insert in sorted position
                j = cnt
                Do While j > 0
                    If legD2(j - 1) <= dd Then Exit Do
                    legD2(j) = legD2(j - 1)
                    legID(j) = legID(j - 1)
                    j = j - 1
                Loop
                legD2(j) = dd
                legID(j) = candID(k)
                cnt = cnt + 1
            ElseIf dd < legD2(cnt - 1) Then
                ' Full and this beats the current worst - drop the worst, insert
                j = cnt - 1
                Do While j > 0
                    If legD2(j - 1) <= dd Then Exit Do
                    legD2(j) = legD2(j - 1)
                    legID(j) = legID(j - 1)
                    j = j - 1
                Loop
                legD2(j) = dd
                legID(j) = candID(k)
            End If
        Next k
    End If

    GatherLegs = cnt
End Function
