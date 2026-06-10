' connect-rbe2-cbush.bas
' -----------------------------------------------------------------------------
' Create CBUSH fastener elements between two parts (groups).
'
' Each part is a group containing RBE2 bolt-hole spiders. The tool matches RBE2s
' whose INDEPENDENT (center) nodes are near each other across the two groups, then
' builds one CBUSH per matched location between the two center nodes.
'
' ALL global choices are made in ONE settings window: the two groups, the gap
' tolerance, the orientation CSys, up to two PBUSH properties (fasteners + shear
' pins), and the output group. The only per-location step is: if a 2nd (shear-pin)
' PBUSH is chosen, the user graphically picks the shear-pin locations and the rest
' become fasteners; with a single PBUSH all matches connect to it automatically.
' The matched RBE2s are isolated in the view as a visual check.
'
' Key API:
'   CBUSH:  el.type=FET_L_SPRING (6), el.topology=FTO_LINE2 (0), node(0)/node(1),
'           el.propID, el.SetSpringOrient(3 /*FESO_ELCID*/, csysID, 0,0,0), el.Put.
'   RBE2:   el.type=FET_L_RIGID And el.topology=FTO_RIGIDLIST; center = el.node(0).
'   Group:  SetAdd(...) BEFORE Put, then feGroupEvaluate, or the group is empty.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long, p As Long

    Dim el As femap.Elem
    Set el = App.feElem
    Dim nd As femap.Node
    Set nd = App.feNode
    Dim gp As femap.Group
    Set gp = App.feGroup

    Dim eid As Long, indep As Long

    ' ============================================================
    ' Section 1: Enumerate groups, coordinate systems, PBUSH props
    ' ============================================================
    ' --- groups ---
    Dim grpEnum As femap.Group
    Set grpEnum = App.feGroup
    Dim grpCount As Long
    grpCount = 0
    grpEnum.Reset
    Do While grpEnum.Next()
        grpCount = grpCount + 1
    Loop
    If grpCount < 2 Then
        App.feAppMessage(FCM_ERROR, "Need at least 2 groups in the model")
        Exit Sub
    End If
    Dim grpIDs() As Long, grpNames() As String
    ReDim grpIDs(grpCount - 1)
    ReDim grpNames(grpCount - 1)
    Dim gi As Long
    gi = 0
    grpEnum.Reset
    Do While grpEnum.Next()
        grpIDs(gi) = grpEnum.ID
        grpNames(gi) = Trim$(Str$(grpEnum.ID)) + " - " + grpEnum.title
        gi = gi + 1
    Loop

    ' --- coordinate systems (prepend global 0) ---
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
    Dim cj As Long
    cj = 1
    csEnum.Reset
    Do While csEnum.Next()
        csIDs(cj) = csEnum.ID
        csNames(cj) = Trim$(Str$(csEnum.ID)) + " - " + csEnum.title
        cj = cj + 1
    Loop

    ' --- PBUSH (spring/damper, property type 6) ---
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
    Dim pj As Long
    pj = 0
    prEnum.Reset
    Do While prEnum.Next()
        If prEnum.type = 6 Then
            pbIDs(pj) = prEnum.ID
            pbNames(pj) = Trim$(Str$(prEnum.ID)) + " - " + prEnum.title
            pj = pj + 1
        End If
    Loop

    ' --- derived lists: PBUSH type-2 with a "(none)" entry, output with "(new)" ---
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
    Begin Dialog SetupDlg 460, 252, "Connect Groups by CBUSH"
        Text        12, 12, 150, 12, "Group 1 (Part A):"
        DropListBox 168, 10, 280, 120, grpNames(), .g1Pick
        Text        12, 34, 150, 12, "Group 2 (Part B):"
        DropListBox 168, 32, 280, 120, grpNames(), .g2Pick
        Text        12, 56, 150, 12, "Max gap tolerance:"
        TextBox     168, 54, 110, 12, .tolBox
        Text        12, 78, 150, 12, "Orientation CSys (all CBUSH):"
        DropListBox 168, 76, 280, 120, csNames(), .csPick
        GroupBox    12, 100, 436, 56, "Fastener properties (PBUSH)"
        Text        22, 118, 124, 12, "Type 1 (fasteners):"
        DropListBox 150, 116, 290, 120, pbNames(), .pb1Pick
        Text        22, 136, 124, 12, "Type 2 (shear pins):"
        DropListBox 150, 134, 290, 120, pb2Names(), .pb2Pick
        Text        12, 164, 150, 12, "Output group:"
        DropListBox 168, 162, 280, 120, outNames(), .outPick
        Text        12, 186, 154, 12, "New group name:"
        TextBox     168, 184, 280, 12, .nameBox
        OKButton    140, 216, 80, 20
        CancelButton 240, 216, 80, 20
    End Dialog

    Dim sdlg As SetupDlg
    sdlg.g1Pick = 0
    sdlg.g2Pick = 0
    sdlg.tolBox = "0.1"
    sdlg.csPick = 0
    sdlg.pb1Pick = 0
    sdlg.pb2Pick = 0
    sdlg.outPick = 0
    sdlg.nameBox = "CBUSH Connections"
    If Dialog(sdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim grp1ID As Long, grp2ID As Long, csysID As Long, tol As Double
    Dim pb1ID As Long, pb2ID As Long, outChoice As Long
    Dim gname As String
    grp1ID = grpIDs(sdlg.g1Pick)
    grp2ID = grpIDs(sdlg.g2Pick)
    tol = CDbl(sdlg.tolBox)
    csysID = csIDs(sdlg.csPick)
    pb1ID = pbIDs(sdlg.pb1Pick)
    If sdlg.pb2Pick = 0 Then
        pb2ID = -1
    Else
        pb2ID = pbIDs(sdlg.pb2Pick - 1)
    End If
    outChoice = sdlg.outPick
    gname = Trim$(sdlg.nameBox)
    If gname = "" Then gname = "CBUSH Connections"

    If grp1ID = grp2ID Then
        App.feAppMessage(FCM_ERROR, "Group 1 and Group 2 must be different groups")
        Exit Sub
    End If

    ' ============================================================
    ' Section 3: Gather RBE2 independent nodes in each group
    ' ============================================================
    ' --- Group 1 ---
    rc = gp.Get(grp1ID)
    Dim lst1 As femap.Set
    Set lst1 = gp.List(8)
    Dim es1 As femap.Set
    Set es1 = App.feSet
    If Not (lst1 Is Nothing) Then es1.AddSet(lst1.ID)
    Dim cap1 As Long
    cap1 = es1.Count
    If cap1 = 0 Then
        App.feAppMessage(FCM_ERROR, "Group 1 has no elements")
        Exit Sub
    End If
    Dim g1Elem() As Long, g1Node() As Long
    Dim g1x() As Double, g1y() As Double, g1z() As Double
    ReDim g1Elem(cap1 - 1)
    ReDim g1Node(cap1 - 1)
    ReDim g1x(cap1 - 1)
    ReDim g1y(cap1 - 1)
    ReDim g1z(cap1 - 1)
    Dim n1 As Long
    n1 = 0
    eid = es1.First()
    Do While eid > 0
        If el.Get(eid) = FE_OK Then
            If el.type = FET_L_RIGID And el.topology = FTO_RIGIDLIST Then
                indep = el.node(0)
                If nd.Get(indep) = FE_OK Then
                    g1Elem(n1) = eid
                    g1Node(n1) = indep
                    g1x(n1) = nd.x
                    g1y(n1) = nd.y
                    g1z(n1) = nd.z
                    n1 = n1 + 1
                End If
            End If
        End If
        eid = es1.Next()
    Loop
    If n1 = 0 Then
        App.feAppMessage(FCM_ERROR, "Group 1 contains no RBE2 elements")
        Exit Sub
    End If

    ' --- Group 2 ---
    rc = gp.Get(grp2ID)
    Dim lst2 As femap.Set
    Set lst2 = gp.List(8)
    Dim es2 As femap.Set
    Set es2 = App.feSet
    If Not (lst2 Is Nothing) Then es2.AddSet(lst2.ID)
    Dim cap2 As Long
    cap2 = es2.Count
    If cap2 = 0 Then
        App.feAppMessage(FCM_ERROR, "Group 2 has no elements")
        Exit Sub
    End If
    Dim g2Elem() As Long, g2Node() As Long
    Dim g2x() As Double, g2y() As Double, g2z() As Double
    ReDim g2Elem(cap2 - 1)
    ReDim g2Node(cap2 - 1)
    ReDim g2x(cap2 - 1)
    ReDim g2y(cap2 - 1)
    ReDim g2z(cap2 - 1)
    Dim n2 As Long
    n2 = 0
    eid = es2.First()
    Do While eid > 0
        If el.Get(eid) = FE_OK Then
            If el.type = FET_L_RIGID And el.topology = FTO_RIGIDLIST Then
                indep = el.node(0)
                If nd.Get(indep) = FE_OK Then
                    g2Elem(n2) = eid
                    g2Node(n2) = indep
                    g2x(n2) = nd.x
                    g2y(n2) = nd.y
                    g2z(n2) = nd.z
                    n2 = n2 + 1
                End If
            End If
        End If
        eid = es2.Next()
    Loop
    If n2 = 0 Then
        App.feAppMessage(FCM_ERROR, "Group 2 contains no RBE2 elements")
        Exit Sub
    End If

    ' ============================================================
    ' Section 4: Nearest-match (greedy, 1-to-1) within tolerance
    ' ============================================================
    Dim g2Used() As Boolean
    ReDim g2Used(n2 - 1)
    For j = 0 To n2 - 1
        g2Used(j) = False
    Next j

    Dim cG1Elem() As Long, cG1Node() As Long, cG2Elem() As Long, cG2Node() As Long
    Dim cGap() As Double, isPin() As Boolean
    ReDim cG1Elem(n1 - 1)
    ReDim cG1Node(n1 - 1)
    ReDim cG2Elem(n1 - 1)
    ReDim cG2Node(n1 - 1)
    ReDim cGap(n1 - 1)
    ReDim isPin(n1 - 1)
    Dim nCand As Long
    nCand = 0

    Dim bestJ As Long, bestD As Double, dxx As Double, dyy As Double, dzz As Double, dd As Double
    For i = 0 To n1 - 1
        bestJ = -1
        bestD = 1E+30
        For j = 0 To n2 - 1
            If Not g2Used(j) Then
                dxx = g1x(i) - g2x(j)
                dyy = g1y(i) - g2y(j)
                dzz = g1z(i) - g2z(j)
                dd = Sqr(dxx * dxx + dyy * dyy + dzz * dzz)
                If dd < bestD Then
                    bestD = dd
                    bestJ = j
                End If
            End If
        Next j
        If bestJ >= 0 And bestD <= tol Then
            cG1Elem(nCand) = g1Elem(i)
            cG1Node(nCand) = g1Node(i)
            cG2Elem(nCand) = g2Elem(bestJ)
            cG2Node(nCand) = g2Node(bestJ)
            cGap(nCand) = bestD
            isPin(nCand) = False
            g2Used(bestJ) = True
            nCand = nCand + 1
        End If
    Next i

    If nCand = 0 Then
        App.feAppMessage(FCM_WARNING, "No RBE2 pairs found within tolerance " + sdlg.tolBox)
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: List + isolate matched RBE2s + assign properties
    ' ============================================================
    Dim matchSet As femap.Set
    Set matchSet = App.feSet
    App.feAppMessage(FCM_HIGHLIGHT, "=== Candidate connections (gap = center-node distance) ===")
    For p = 0 To nCand - 1
        matchSet.Add(cG1Elem(p))
        matchSet.Add(cG2Elem(p))
        App.feAppMessage(FCM_NORMAL, "  #" + Trim$(Str$(p + 1)) _
            + ": RBE2 " + Trim$(Str$(cG1Elem(p))) + " (G1)  <->  RBE2 " _
            + Trim$(Str$(cG2Elem(p))) + " (G2)   gap=" + Format$(cGap(p), "0.####"))
    Next p

    Dim pickSet As femap.Set
    Set pickSet = App.feSet
    Dim pickedID As Long, ci As Long

    If pb2ID < 0 Then
        ' single type - show matched pairs, confirm, connect ALL with pb1
        App.feViewShow2(FT_ELEM, matchSet.ID, False)   ' keep current zoom
        If MsgBox(Trim$(Str$(nCand)) + " matched pair(s) shown in the view." + Chr$(10) _
            + "Connect all with PBUSH " + Trim$(Str$(pb1ID)) + "?", _
            vbOKCancel, "Connect Groups by CBUSH - Confirm") <> vbOK Then
            Dim allC As femap.Set
            Set allC = App.feSet
            allC.AddAll(FT_ELEM)
            App.feViewShow2(FT_ELEM, allC.ID, False)
            App.feViewRegenerate(0)
            App.feAppMessage(FCM_WARNING, "Cancelled - no connections made")
            Exit Sub
        End If
    Else
        ' two types - show ONLY the group-1 matched RBE2s, then pick the shear pins
        Dim g1MatchSet As femap.Set
        Set g1MatchSet = App.feSet
        For ci = 0 To nCand - 1
            g1MatchSet.Add(cG1Elem(ci))
        Next ci
        App.feViewShow2(FT_ELEM, g1MatchSet.ID, False)   ' group-1 candidates only, keep zoom
        MsgBox "Showing the group-1 RBE2s of the " + Trim$(Str$(nCand)) + " matched pair(s)." + Chr$(10) _
            + "Click OK, then SELECT the shear-pin locations." + Chr$(10) _
            + "Cancel in the picker = none are shear pins; the rest become fasteners.", _
            vbOKOnly, "Connect Groups by CBUSH - Assign shear pins"
        If pickSet.Select(FT_ELEM, True, "Select SHEAR-PIN RBE2 locations (group 1)") = FE_OK Then
            pickedID = pickSet.First()
            Do While pickedID > 0
                For ci = 0 To nCand - 1
                    If cG1Elem(ci) = pickedID Then isPin(ci) = True
                Next ci
                pickedID = pickSet.Next()
            Loop
        End If
    End If

    ' ============================================================
    ' Section 6: Create the CBUSH elements
    ' ============================================================
    Dim createdElemSet As femap.Set
    Set createdElemSet = App.feSet
    Dim cb As femap.Elem
    Dim propID As Long, newID As Long
    Dim totalMade As Long, made1 As Long, made2 As Long
    Dim pb1Used As Boolean, pb2Used As Boolean
    totalMade = 0
    made1 = 0
    made2 = 0
    pb1Used = False
    pb2Used = False

    ' Temporarily disable Group Automatic Add so the created entities are not also
    ' auto-added to the active group; restored right after creation.
    Dim savedAutoAdd As Long
    savedAutoAdd = App.Info_GroupAutomaticAdd
    App.Info_GroupAutomaticAdd = 0

    App.feAppLock
    For p = 0 To nCand - 1
        propID = pb1ID
        If isPin(p) Then propID = pb2ID
        Set cb = App.feElem
        newID = cb.NextEmptyID
        cb.type = FET_L_SPRING
        cb.topology = FTO_LINE2
        cb.node(0) = cG1Node(p)
        cb.node(1) = cG2Node(p)
        cb.propID = propID
        cb.SetSpringOrient(3, csysID, 0.0, 0.0, 0.0)
        If cb.Put(newID) = FE_OK Then
            createdElemSet.Add(newID)
            totalMade = totalMade + 1
            If isPin(p) Then
                pb2Used = True
                made2 = made2 + 1
            Else
                pb1Used = True
                made1 = made1 + 1
            End If
        End If
    Next p
    App.feAppUnlock
    App.Info_GroupAutomaticAdd = savedAutoAdd   ' restore the user's setting

    Dim usedPropSet As femap.Set
    Set usedPropSet = App.feSet
    If pb1Used Then usedPropSet.Add(pb1ID)
    If pb2Used And pb2ID >= 0 Then usedPropSet.Add(pb2ID)

    ' ============================================================
    ' Section 7: Restore full element visibility (shows the new CBUSHes)
    ' ============================================================
    Dim allE As femap.Set
    Set allE = App.feSet
    allE.AddAll(FT_ELEM)
    App.feViewShow2(FT_ELEM, allE.ID, False)
    App.feViewRegenerate(0)

    If totalMade = 0 Then
        App.feAppMessage(FCM_WARNING, "No CBUSH elements were created")
        Exit Sub
    End If

    ' ============================================================
    ' Section 8: Populate the chosen output group
    ' ============================================================
    Dim gpOut As femap.Group
    Set gpOut = App.feGroup
    Dim outID As Long
    If outChoice = 0 Then
        outID = gpOut.NextEmptyID
        gpOut.title = gname
    Else
        outID = grpIDs(outChoice - 1)
        gpOut.Get(outID)
    End If

    Dim csOneSet As femap.Set
    Set csOneSet = App.feSet
    csOneSet.Add(csysID)
    ' SetAdd builds rules on the in-memory group; Put commits them (order matters)
    gpOut.SetAdd(FT_ELEM, createdElemSet.ID)
    gpOut.SetAdd(FT_PROP, usedPropSet.ID)
    gpOut.SetAdd(FT_CSYS, csOneSet.ID)
    gpOut.Put(outID)
    App.feGroupEvaluate(-outID, True)

    ' ============================================================
    ' Section 9: Report
    ' ============================================================
    App.feViewRegenerate(0)
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Connect Groups by CBUSH - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Group 1 RBE2s:        " + Str$(n1))
    App.feAppMessage(FCM_NORMAL, "  Group 2 RBE2s:        " + Str$(n2))
    App.feAppMessage(FCM_NORMAL, "  Candidate pairs:      " + Str$(nCand))
    App.feAppMessage(FCM_NORMAL, "  CBUSH created:        " + Str$(totalMade))
    App.feAppMessage(FCM_NORMAL, "    Type 1 (PBUSH " + Trim$(Str$(pb1ID)) + "): " + Str$(made1))
    If pb2ID >= 0 Then
        App.feAppMessage(FCM_NORMAL, "    Type 2 (PBUSH " + Trim$(Str$(pb2ID)) + "): " + Str$(made2))
    End If
    App.feAppMessage(FCM_NORMAL, "  Orientation CSys:     " + Str$(csysID))
    App.feAppMessage(FCM_NORMAL, "  Output group:         " + Str$(outID))
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
