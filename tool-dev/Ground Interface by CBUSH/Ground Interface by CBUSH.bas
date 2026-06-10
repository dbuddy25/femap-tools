' Ground Interface by CBUSH.bas
' -----------------------------------------------------------------------------
' Ground a part's RBE2 bolt-hole spiders to a single interface node through
' fasteners.
'
' Pick one group and a plane. The tool finds the RBE2 spiders in the group whose
' CENTER (independent) node is within a distance tolerance of the plane, and for
' each one:
'   - creates a new node Gi coincident with the RBE2 center node Ci,
'   - creates a zero-length CBUSH between Ci and Gi (fastener / shear-pin PBUSH,
'     one orientation CSys for all).
' All Gi become the dependent nodes of a NEW "ground" RBE2 whose single independent
' node G0 sits at the centroid of the participating centers projected onto the
' plane. The ground RBE2 has DOF 123456 and an optional thermal-expansion (CTE).
'
' Two output groups (each new or existing):
'   - CBUSH group:  the CBUSH elements + PBUSH(es) + orientation CSys.  NO nodes.
'   - Ground group: the ground RBE2 element + its nodes (G0 + all Gi).
'
' Reuses the conventions of Connect-Groups-by-CBUSH and make-rbe2-from-holes.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long, p As Long, dk As Long

    Dim el As femap.Elem
    Set el = App.feElem
    Dim nd As femap.Node
    Set nd = App.feNode
    Dim gp As femap.Group
    Set gp = App.feGroup

    Dim eid As Long, ctrNode As Long

    ' ============================================================
    ' Section 1: Enumerate groups, CSys, PBUSH props, materials
    ' ============================================================
    Dim grpEnum As femap.Group
    Set grpEnum = App.feGroup
    Dim grpCount As Long
    grpCount = 0
    grpEnum.Reset
    Do While grpEnum.Next()
        grpCount = grpCount + 1
    Loop
    If grpCount < 1 Then
        App.feAppMessage(FCM_ERROR, "No groups in the model")
        Exit Sub
    End If
    Dim grpIDs() As Long, grpNames() As String
    ReDim grpIDs(grpCount - 1)
    ReDim grpNames(grpCount - 1)
    Dim gx As Long
    gx = 0
    grpEnum.Reset
    Do While grpEnum.Next()
        grpIDs(gx) = grpEnum.ID
        grpNames(gx) = Trim$(Str$(grpEnum.ID)) + " - " + grpEnum.title
        gx = gx + 1
    Loop

    Dim csEnum As Object
    Set csEnum = App.feCSys
    Dim csUser As Long
    csUser = 0
    csEnum.Reset
    Do While csEnum.Next()
        csUser = csUser + 1
    Loop
    Dim csIDs() As Long, csNames() As String
    ReDim csIDs(csUser)
    ReDim csNames(csUser)
    csIDs(0) = 0
    csNames(0) = "0 - Global Rectangular"
    Dim cx As Long
    cx = 1
    csEnum.Reset
    Do While csEnum.Next()
        csIDs(cx) = csEnum.ID
        csNames(cx) = Trim$(Str$(csEnum.ID)) + " - " + csEnum.title
        cx = cx + 1
    Loop

    Dim prEnum As Object
    Set prEnum = App.feProp
    Dim pbCount As Long
    pbCount = 0
    prEnum.Reset
    Do While prEnum.Next()
        If prEnum.type = 6 Then pbCount = pbCount + 1
    Loop
    If pbCount = 0 Then
        App.feAppMessage(FCM_ERROR, "No spring/damper (PBUSH) properties in the model - create one first")
        Exit Sub
    End If
    Dim pbIDs() As Long, pbNames() As String
    ReDim pbIDs(pbCount - 1)
    ReDim pbNames(pbCount - 1)
    Dim px As Long
    px = 0
    prEnum.Reset
    Do While prEnum.Next()
        If prEnum.type = 6 Then
            pbIDs(px) = prEnum.ID
            pbNames(px) = Trim$(Str$(prEnum.ID)) + " - " + prEnum.title
            px = px + 1
        End If
    Loop

    Dim mtEnum As Object
    Set mtEnum = App.feMatl
    Dim matCount As Long
    matCount = 0
    mtEnum.Reset
    Do While mtEnum.Next()
        matCount = matCount + 1
    Loop
    Dim matIDs() As Long, matNames() As String
    If matCount > 0 Then
        ReDim matIDs(matCount - 1)
        ReDim matNames(matCount - 1)
        Dim mx As Long
        mx = 0
        mtEnum.Reset
        Do While mtEnum.Next()
            matIDs(mx) = mtEnum.ID
            matNames(mx) = Trim$(Str$(mtEnum.ID)) + " - " + mtEnum.title
            mx = mx + 1
        Loop
    Else
        ReDim matIDs(0)
        ReDim matNames(0)
        matIDs(0) = 0
        matNames(0) = "(no materials in model)"
    End If

    ' derived dropdown lists
    Dim pb2Names() As String
    ReDim pb2Names(pbCount)
    pb2Names(0) = "(none - single type)"
    Dim k As Long
    For k = 0 To pbCount - 1
        pb2Names(k + 1) = pbNames(k)
    Next k

    Dim outNames() As String
    ReDim outNames(grpCount)
    outNames(0) = "(create new group)"
    For k = 0 To grpCount - 1
        outNames(k + 1) = grpNames(k)
    Next k

    ' ============================================================
    ' Section 2: One settings window
    ' ============================================================
    Begin Dialog SetupDlg 460, 340, "Ground Interface by CBUSH"
        Text        12, 12, 150, 12, "Source group:"
        DropListBox 168, 10, 280, 120, grpNames(), .grpPick
        Text        12, 34, 150, 12, "Near-plane tolerance:"
        TextBox     168, 32, 110, 12, .tolBox
        Text        12, 56, 150, 12, "Orientation CSys (all CBUSH):"
        DropListBox 168, 54, 280, 120, csNames(), .csPick
        GroupBox    12, 78, 436, 56, "Fastener properties (PBUSH)"
        Text        22, 96, 124, 12, "Type 1 (fasteners):"
        DropListBox 150, 94, 290, 120, pbNames(), .pb1Pick
        Text        22, 114, 124, 12, "Type 2 (shear pins):"
        DropListBox 150, 112, 290, 120, pb2Names(), .pb2Pick
        Text        12, 140, 150, 12, "CBUSH group:"
        DropListBox 168, 138, 280, 120, outNames(), .cbGrpPick
        Text        12, 158, 150, 12, "  new name:"
        TextBox     168, 156, 280, 12, .cbName
        Text        12, 178, 150, 12, "Ground RBE2 group:"
        DropListBox 168, 176, 280, 120, outNames(), .grGrpPick
        Text        12, 196, 150, 12, "  new name:"
        TextBox     168, 194, 280, 12, .grName
        GroupBox    12, 216, 436, 78, "Ground RBE2 thermal expansion (optional)"
        CheckBox    22, 232, 290, 12, "Apply CTE to ground RBE2", .chkCTE
        OptionGroup .cteSource
            OptionButton 22, 252, 100, 12, "From material:"
            OptionButton 22, 272, 100, 12, "Enter value:"
        DropListBox 128, 250, 312, 120, matNames(), .matPick
        TextBox     128, 270, 110, 12, .cteVal
        OKButton    140, 304, 80, 20
        CancelButton 240, 304, 80, 20
    End Dialog

    Dim sdlg As SetupDlg
    sdlg.grpPick = 0
    sdlg.tolBox = "0.01"
    sdlg.csPick = 0
    sdlg.pb1Pick = 0
    sdlg.pb2Pick = 0
    sdlg.cbGrpPick = 0
    sdlg.cbName = "CBUSH Fasteners"
    sdlg.grGrpPick = 0
    sdlg.grName = "Ground Interface"
    sdlg.chkCTE = 0
    sdlg.cteSource = 0
    sdlg.matPick = 0
    sdlg.cteVal = "0.0"
    If matCount = 0 Then sdlg.cteSource = 1
    If Dialog(sdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim srcGrpID As Long, csysID As Long, tol As Double
    Dim pb1ID As Long, pb2ID As Long
    Dim cbChoice As Long, grChoice As Long
    Dim cbName As String, grName As String
    srcGrpID = grpIDs(sdlg.grpPick)
    tol = CDbl(sdlg.tolBox)
    csysID = csIDs(sdlg.csPick)
    pb1ID = pbIDs(sdlg.pb1Pick)
    If sdlg.pb2Pick = 0 Then
        pb2ID = -1
    Else
        pb2ID = pbIDs(sdlg.pb2Pick - 1)
    End If
    cbChoice = sdlg.cbGrpPick
    grChoice = sdlg.grGrpPick
    cbName = Trim$(sdlg.cbName)
    If cbName = "" Then cbName = "CBUSH Fasteners"
    grName = Trim$(sdlg.grName)
    If grName = "" Then grName = "Ground Interface"

    Dim applyCTE As Boolean
    Dim cteValue As Double
    Dim cteNote As String
    applyCTE = (sdlg.chkCTE <> 0)
    cteValue = 0.0
    cteNote = ""
    If applyCTE Then
        If sdlg.cteSource = 0 Then
            If matCount > 0 Then
                Dim mtl As Object
                Set mtl = App.feMatl
                If mtl.Get(matIDs(sdlg.matPick)) = FE_OK Then
                    cteValue = mtl.mval(36)
                    cteNote = " (material " + matNames(sdlg.matPick) + ")"
                Else
                    App.feAppMessage(FCM_WARNING, "Could not read selected material - CTE not applied")
                    applyCTE = False
                End If
            Else
                App.feAppMessage(FCM_WARNING, "No materials in model - CTE not applied")
                applyCTE = False
            End If
        Else
            cteValue = CDbl(sdlg.cteVal)
            cteNote = " (entered)"
        End If
    End If

    ' ============================================================
    ' Section 3: Pick the ground plane
    ' ============================================================
    Dim plBase As Variant, plNormal As Variant, plAxis As Variant
    rc = App.fePlanePick("Pick the ground plane", plBase, plNormal, plAxis)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Plane pick cancelled - exiting")
        Exit Sub
    End If
    Dim nx As Double, ny As Double, nz As Double, nLen As Double
    nx = plNormal(0)
    ny = plNormal(1)
    nz = plNormal(2)
    nLen = Sqr(nx * nx + ny * ny + nz * nz)
    If nLen <= 0.0 Then nLen = 1.0
    nx = nx / nLen
    ny = ny / nLen
    nz = nz / nLen

    ' ============================================================
    ' Section 4: Find RBE2 centers in the group near the plane
    ' ============================================================
    rc = gp.Get(srcGrpID)
    Dim lstS As femap.Set
    Set lstS = gp.List(8)
    Dim esS As femap.Set
    Set esS = App.feSet
    If Not (lstS Is Nothing) Then esS.AddSet(lstS.ID)
    Dim capS As Long
    capS = esS.Count
    If capS = 0 Then
        App.feAppMessage(FCM_ERROR, "Source group has no elements")
        Exit Sub
    End If

    Dim fElem() As Long, fNode() As Long
    Dim fx() As Double, fy() As Double, fz() As Double
    Dim isPin() As Boolean
    ReDim fElem(capS - 1)
    ReDim fNode(capS - 1)
    ReDim fx(capS - 1)
    ReDim fy(capS - 1)
    ReDim fz(capS - 1)
    ReDim isPin(capS - 1)
    Dim nF As Long
    nF = 0
    Dim ax As Double, ay As Double, az As Double, dPlane As Double
    eid = esS.First()
    Do While eid > 0
        If el.Get(eid) = FE_OK Then
            If el.type = FET_L_RIGID And el.topology = FTO_RIGIDLIST Then
                ctrNode = el.node(0)
                If nd.Get(ctrNode) = FE_OK Then
                    ax = nd.x
                    ay = nd.y
                    az = nd.z
                    dPlane = Abs((ax - plBase(0)) * nx + (ay - plBase(1)) * ny + (az - plBase(2)) * nz)
                    If dPlane <= tol Then
                        fElem(nF) = eid
                        fNode(nF) = ctrNode
                        fx(nF) = ax
                        fy(nF) = ay
                        fz(nF) = az
                        isPin(nF) = False
                        nF = nF + 1
                    End If
                End If
            End If
        End If
        eid = esS.Next()
    Loop
    If nF = 0 Then
        App.feAppMessage(FCM_WARNING, "No RBE2 centers within " + sdlg.tolBox + " of the plane")
        Exit Sub
    End If

    App.feAppMessage(FCM_HIGHLIGHT, "=== RBE2 centers near the plane ===")
    For p = 0 To nF - 1
        App.feAppMessage(FCM_NORMAL, "  #" + Trim$(Str$(p + 1)) + ": RBE2 " + Trim$(Str$(fElem(p))) _
            + "  center node " + Trim$(Str$(fNode(p))))
    Next p

    ' ============================================================
    ' Section 5: Isolate the found RBE2s + assign shear pins
    ' ============================================================
    Dim foundSet As femap.Set
    Set foundSet = App.feSet
    For p = 0 To nF - 1
        foundSet.Add(fElem(p))
    Next p
    App.feViewShow2(FT_ELEM, foundSet.ID, False)

    Dim pickSet As femap.Set
    Set pickSet = App.feSet
    Dim pickedID As Long, kk As Long

    If pb2ID < 0 Then
        If MsgBox(Trim$(Str$(nF)) + " RBE2(s) near the plane (shown in the view)." + Chr$(10) _
            + "Ground them with PBUSH " + Trim$(Str$(pb1ID)) + "?", _
            vbOKCancel, "Ground Interface - Confirm") <> vbOK Then
            Dim allC As femap.Set
            Set allC = App.feSet
            allC.AddAll(FT_ELEM)
            App.feViewShow2(FT_ELEM, allC.ID, False)
            App.feViewRegenerate(0)
            App.feAppMessage(FCM_WARNING, "Cancelled - nothing created")
            Exit Sub
        End If
    Else
        MsgBox Trim$(Str$(nF)) + " RBE2(s) near the plane (shown in the view)." + Chr$(10) _
            + "Click OK, then SELECT the shear-pin RBE2s." + Chr$(10) _
            + "Cancel in the picker = none are shear pins; the rest become fasteners.", _
            vbOKOnly, "Ground Interface - Assign shear pins"
        If pickSet.Select(FT_ELEM, True, "Select SHEAR-PIN RBE2s") = FE_OK Then
            pickedID = pickSet.First()
            Do While pickedID > 0
                For kk = 0 To nF - 1
                    If fElem(kk) = pickedID Then isPin(kk) = True
                Next kk
                pickedID = pickSet.Next()
            Loop
        End If
    End If

    ' ============================================================
    ' Section 6: Create Gi nodes, CBUSHes, the ground node, ground RBE2
    ' ============================================================
    Dim ndNew As femap.Node
    Dim cb As femap.Elem
    Dim giID() As Long
    ReDim giID(nF - 1)
    Dim cbushSet As femap.Set
    Set cbushSet = App.feSet
    Dim groundNodeSet As femap.Set
    Set groundNodeSet = App.feSet
    Dim propID As Long, newID As Long, giNew As Long
    Dim made1 As Long, made2 As Long
    Dim pb1Used As Boolean, pb2Used As Boolean
    Dim sumx As Double, sumy As Double, sumz As Double
    made1 = 0
    made2 = 0
    pb1Used = False
    pb2Used = False
    sumx = 0.0
    sumy = 0.0
    sumz = 0.0

    ' Temporarily suspend Group Automatic Add so the created entities are not also
    ' auto-added to the active group. Two levers: turn the mode off AND clear the
    ' active group (the auto-add target). Both restored right after creation.
    Dim savedAutoAdd As Long, savedActiveGrp As Long
    savedAutoAdd = App.Info_GroupAutomaticAdd
    savedActiveGrp = App.Info_ActiveID(FT_GROUP)
    App.Info_GroupAutomaticAdd = 0
    App.Info_ActiveID(FT_GROUP) = 0

    App.feAppLock
    For p = 0 To nF - 1
        ' new node Gi coincident with the center node Ci
        Set ndNew = App.feNode
        giNew = ndNew.NextEmptyID
        ndNew.x = fx(p)
        ndNew.y = fy(p)
        ndNew.z = fz(p)
        If ndNew.Put(giNew) = FE_OK Then
            giID(p) = giNew
            groundNodeSet.Add(giNew)

            propID = pb1ID
            If isPin(p) Then propID = pb2ID

            Set cb = App.feElem
            newID = cb.NextEmptyID
            cb.type = FET_L_SPRING
            cb.topology = FTO_LINE2
            cb.node(0) = fNode(p)
            cb.node(1) = giNew
            cb.propID = propID
            cb.SetSpringOrient(3, csysID, 0.0, 0.0, 0.0)
            If cb.Put(newID) = FE_OK Then
                cbushSet.Add(newID)
                If isPin(p) Then
                    pb2Used = True
                    made2 = made2 + 1
                Else
                    pb1Used = True
                    made1 = made1 + 1
                End If
            End If
        End If
        sumx = sumx + fx(p)
        sumy = sumy + fy(p)
        sumz = sumz + fz(p)
    Next p

    ' ground node G0 = centroid of the centers projected onto the plane
    Dim avgx As Double, avgy As Double, avgz As Double, dotc As Double
    avgx = sumx / nF
    avgy = sumy / nF
    avgz = sumz / nF
    dotc = (avgx - plBase(0)) * nx + (avgy - plBase(1)) * ny + (avgz - plBase(2)) * nz
    Dim g0x As Double, g0y As Double, g0z As Double
    g0x = avgx - dotc * nx
    g0y = avgy - dotc * ny
    g0z = avgz - dotc * nz
    Set ndNew = App.feNode
    Dim g0ID As Long
    g0ID = ndNew.NextEmptyID
    ndNew.x = g0x
    ndNew.y = g0y
    ndNew.z = g0z
    rc = ndNew.Put(g0ID)
    groundNodeSet.Add(g0ID)

    ' ground RBE2: independent G0, dependents all Gi, DOF 123456
    Dim vGi As Variant, vFaces As Variant, vWeights As Variant, vDOF As Variant
    ReDim vGi(nF - 1)
    ReDim vFaces(nF - 1)
    ReDim vWeights(nF - 1)
    ReDim vDOF(nF * 6 - 1)
    For p = 0 To nF - 1
        vGi(p) = CLng(giID(p))
        vFaces(p) = CLng(0)
        vWeights(p) = CDbl(0)
        For dk = 0 To 5
            vDOF(p * 6 + dk) = CLng(1)
        Next dk
    Next p

    Dim cb2 As femap.Elem
    Set cb2 = App.feElem
    Dim groundRBE2ID As Long
    groundRBE2ID = cb2.NextEmptyID
    cb2.type = FET_L_RIGID
    cb2.topology = FTO_RIGIDLIST
    cb2.node(0) = g0ID
    For dk = 0 To 5
        cb2.Release(0, dk) = 1
    Next dk
    If applyCTE Then cb2.RigidThermalExpansion = cteValue
    rc = cb2.PutNodeList(0, nF, vGi, vFaces, vWeights, vDOF)
    rc = cb2.Put(groundRBE2ID)
    App.feAppUnlock
    App.Info_ActiveID(FT_GROUP) = savedActiveGrp   ' restore the user's settings
    App.Info_GroupAutomaticAdd = savedAutoAdd

    ' ============================================================
    ' Section 7: Restore full element visibility
    ' ============================================================
    Dim allE As femap.Set
    Set allE = App.feSet
    allE.AddAll(FT_ELEM)
    App.feViewShow2(FT_ELEM, allE.ID, False)
    App.feViewRegenerate(0)

    ' ============================================================
    ' Section 8: Populate the two output groups
    ' ============================================================
    Dim usedPropSet As femap.Set
    Set usedPropSet = App.feSet
    If pb1Used Then usedPropSet.Add(pb1ID)
    If pb2Used And pb2ID >= 0 Then usedPropSet.Add(pb2ID)

    Dim csOneSet As femap.Set
    Set csOneSet = App.feSet
    csOneSet.Add(csysID)

    ' CBUSH group (elements + props + csys, NO nodes)
    Dim gpC As femap.Group
    Set gpC = App.feGroup
    Dim cbGrpID As Long
    If cbChoice = 0 Then
        cbGrpID = gpC.NextEmptyID
        gpC.title = cbName
    Else
        cbGrpID = grpIDs(cbChoice - 1)
        gpC.Get(cbGrpID)
    End If
    gpC.SetAdd(FT_ELEM, cbushSet.ID)
    gpC.SetAdd(FT_PROP, usedPropSet.ID)
    gpC.SetAdd(FT_CSYS, csOneSet.ID)
    gpC.Put(cbGrpID)
    App.feGroupEvaluate(-cbGrpID, True)

    ' Ground RBE2 group (the RBE2 element + its nodes)
    Dim grElemSet As femap.Set
    Set grElemSet = App.feSet
    grElemSet.Add(groundRBE2ID)
    Dim gpG As femap.Group
    Set gpG = App.feGroup
    Dim grGrpID As Long
    If grChoice = 0 Then
        grGrpID = gpG.NextEmptyID
        gpG.title = grName
    Else
        grGrpID = grpIDs(grChoice - 1)
        gpG.Get(grGrpID)
    End If
    gpG.SetAdd(FT_ELEM, grElemSet.ID)
    gpG.SetAdd(FT_NODE, groundNodeSet.ID)
    gpG.Put(grGrpID)
    App.feGroupEvaluate(-grGrpID, True)

    ' ============================================================
    ' Section 9: Report
    ' ============================================================
    App.feViewRegenerate(0)
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Ground Interface by CBUSH - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  RBE2s near plane:     " + Str$(nF))
    App.feAppMessage(FCM_NORMAL, "  CBUSH created:        " + Str$(made1 + made2))
    App.feAppMessage(FCM_NORMAL, "    Type 1 (PBUSH " + Trim$(Str$(pb1ID)) + "): " + Str$(made1))
    If pb2ID >= 0 Then
        App.feAppMessage(FCM_NORMAL, "    Type 2 (PBUSH " + Trim$(Str$(pb2ID)) + "): " + Str$(made2))
    End If
    App.feAppMessage(FCM_NORMAL, "  Ground RBE2 element:  " + Str$(groundRBE2ID))
    App.feAppMessage(FCM_NORMAL, "  Ground center node:   " + Str$(g0ID))
    App.feAppMessage(FCM_NORMAL, "  Orientation CSys:     " + Str$(csysID))
    If applyCTE Then
        App.feAppMessage(FCM_NORMAL, "  Ground RBE2 CTE:      " + Str$(cteValue) + cteNote)
    End If
    App.feAppMessage(FCM_NORMAL, "  CBUSH group:          " + Str$(cbGrpID))
    App.feAppMessage(FCM_NORMAL, "  Ground RBE2 group:    " + Str$(grGrpID))
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
