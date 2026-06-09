' connect-rbe2-cbush.bas
' -----------------------------------------------------------------------------
' Create CBUSH fastener elements between two parts (groups).
'
' Each part is a group containing RBE2 bolt-hole spiders. The tool matches RBE2s
' whose INDEPENDENT (center) nodes are near each other across the two groups, lets
' the user visually verify the proposed connections (temporary lines + gap-distance
' labels), then builds one CBUSH per chosen location between the two center nodes.
'
' Supports two (or more) PBUSH types in one joint (e.g. fasteners + shear pins):
' for each type the user picks a PBUSH property and selects which locations get it.
' One orientation coordinate system is applied to every CBUSH (works for
' zero-length CBUSH where the two center nodes are coincident).
'
' Results (CBUSH elements + the PBUSH property/properties used + the orientation
' CSys) are collected into a new named group or appended to an existing group.
'
' Key API:
'   CBUSH:  el.type=FET_L_SPRING (6), el.topology=FTO_LINE2 (0), node(0)/node(1),
'           el.propID, then el.Put. Orientation: el.SetSpringOrient(3, csysID, 0,0,0)
'           where 3 = FESO_ELCID (orient by coordinate system on the element).
'   RBE2:   el.type=FET_L_RIGID And el.topology=FTO_RIGIDLIST; center = el.node(0).
'   Preview: feGFXLine (temp lines) + feText (labels), removed before finishing.
'
' Note: if SetSpringOrient errors on a given Femap build, the equivalent is
'   cb.SpringNoOrient=False : cb.SpringUseCID=True : cb.SpringCID=csysID
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
    ' Section 1: Pick the two groups
    ' ============================================================
    Dim grpSet As femap.Set
    Set grpSet = App.feSet

    rc = grpSet.Select(FT_GROUP, True, "Select Group 1 (Part A)")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim grp1ID As Long
    grp1ID = grpSet.First()

    rc = grpSet.Select(FT_GROUP, True, "Select Group 2 (Part B)")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim grp2ID As Long
    grp2ID = grpSet.First()

    If grp1ID = grp2ID Then
        App.feAppMessage(FCM_ERROR, "Group 1 and Group 2 must be different groups")
        Exit Sub
    End If

    ' ============================================================
    ' Section 2: Gather RBE2 independent nodes in each group
    ' ============================================================
    ' --- Group 1 ---
    rc = gp.Get(grp1ID)
    Dim lst1 As femap.Set
    Set lst1 = gp.List(8)                 ' 8 = elements (volatile - copy now)
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
                    g1Elem(n1) = eid : g1Node(n1) = indep
                    g1x(n1) = nd.x : g1y(n1) = nd.y : g1z(n1) = nd.z
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
                    g2Elem(n2) = eid : g2Node(n2) = indep
                    g2x(n2) = nd.x : g2y(n2) = nd.y : g2z(n2) = nd.z
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
    ' Section 3: Tolerance + nearest-match (greedy, 1-to-1)
    ' ============================================================
    Dim tolStr As String
    tolStr = InputBox$("Maximum gap between matched RBE2 center nodes (model units):", _
        "CBUSH Connect - Match Tolerance", "0.1")
    If Trim$(tolStr) = "" Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim tol As Double
    tol = CDbl(tolStr)

    Dim g2Used() As Boolean
    ReDim g2Used(n2 - 1)
    For j = 0 To n2 - 1
        g2Used(j) = False
    Next j

    Dim cG1Elem() As Long, cG1Node() As Long, cG2Elem() As Long, cG2Node() As Long
    Dim cGap() As Double, cAssigned() As Boolean
    ReDim cG1Elem(n1 - 1)
    ReDim cG1Node(n1 - 1)
    ReDim cG2Elem(n1 - 1)
    ReDim cG2Node(n1 - 1)
    ReDim cGap(n1 - 1)
    ReDim cAssigned(n1 - 1)
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
                    bestD = dd : bestJ = j
                End If
            End If
        Next j
        If bestJ >= 0 And bestD <= tol Then
            cG1Elem(nCand) = g1Elem(i) : cG1Node(nCand) = g1Node(i)
            cG2Elem(nCand) = g2Elem(bestJ) : cG2Node(nCand) = g2Node(bestJ)
            cGap(nCand) = bestD : cAssigned(nCand) = False
            g2Used(bestJ) = True
            nCand = nCand + 1
        End If
    Next i

    If nCand = 0 Then
        App.feAppMessage(FCM_WARNING, "No RBE2 pairs found within tolerance " + tolStr)
        Exit Sub
    End If

    ' ============================================================
    ' Section 4: Visual preview (temp lines + labels) + numbered list
    ' ============================================================
    Dim gfx As Object
    Set gfx = App.feGFXLine
    Dim tx As Object
    Set tx = App.feText

    Dim lineIdSet As femap.Set
    Set lineIdSet = App.feSet
    Dim textIdSet As femap.Set
    Set textIdSet = App.feSet

    Dim ax As Double, ay As Double, az As Double
    Dim bx As Double, by As Double, bz As Double
    Dim lid As Long, tid As Long

    App.feAppMessage(FCM_HIGHLIGHT, "=== Candidate connections (gap = center-node distance) ===")
    For p = 0 To nCand - 1
        rc = nd.Get(cG1Node(p)) : ax = nd.x : ay = nd.y : az = nd.z
        rc = nd.Get(cG2Node(p)) : bx = nd.x : by = nd.y : bz = nd.z

        lid = gfx.NextEmptyID
        gfx.PutAll(lid, ax, ay, az, bx, by, bz, 1, 124)
        lineIdSet.Add(lid)

        tid = tx.NextEmptyID
        tx.ModelPosition = True
        tx.AllViews = True
        tx.DrawPointer = False
        tx.DrawBorder = False
        tx.color = 4
        tx.layer = 1
        tx.TextPosition(0) = (ax + bx) / 2.0
        tx.TextPosition(1) = (ay + by) / 2.0
        tx.TextPosition(2) = (az + bz) / 2.0
        tx.text = "#" + Trim$(Str$(p + 1)) + " gap=" + Format$(cGap(p), "0.####")
        tx.Put(tid)
        textIdSet.Add(tid)

        App.feAppMessage(FCM_NORMAL, "  #" + Trim$(Str$(p + 1)) _
            + ": RBE2 " + Trim$(Str$(cG1Elem(p))) + " (G1)  <->  RBE2 " _
            + Trim$(Str$(cG2Elem(p))) + " (G2)   gap=" + Format$(cGap(p), "0.####"))
    Next p
    App.feViewRegenerate(0)

    ' ============================================================
    ' Section 5: Orientation CSys (one for all CBUSH)
    ' ============================================================
    Dim csSet As femap.Set
    Set csSet = App.feSet
    rc = csSet.Select(FT_CSYS, True, "Select ORIENTATION coordinate system for all CBUSH")
    If rc <> FE_OK Then
        gfx.DeleteAll(False, lineIdSet.ID)
        App.feDelete(FT_TEXT, textIdSet.ID)
        App.feViewRegenerate(0)
        App.feAppMessage(FCM_WARNING, "Cancelled - no connections made")
        Exit Sub
    End If
    Dim csysID As Long
    csysID = csSet.First()

    ' ============================================================
    ' Section 6: Per-type rounds - pick PBUSH, select locations, build CBUSH
    ' ============================================================
    Dim createdElemSet As femap.Set
    Set createdElemSet = App.feSet
    Dim usedPropSet As femap.Set
    Set usedPropSet = App.feSet

    Dim pr As Object
    Set pr = App.feProp
    Dim cb As femap.Elem

    Dim pickSet As femap.Set
    Set pickSet = App.feSet

    Dim totalMade As Long, roundNo As Long
    totalMade = 0 : roundNo = 0

    Dim propID As Long, newID As Long, pickedID As Long
    Dim ci As Long, found As Long, roundMade As Long
    Dim moreTypes As Boolean
    moreTypes = True

    Do While moreTypes
        roundNo = roundNo + 1

        rc = pickSet.Select(FT_PROP, True, "Select PBUSH property for connection type " + Trim$(Str$(roundNo)))
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Property selection cancelled - finishing")
            Exit Do
        End If
        propID = pickSet.First()
        If pr.Get(propID) = FE_OK Then
            If pr.type <> 6 Or pr.cbush <> 1 Then
                App.feAppMessage(FCM_WARNING, "  Property " + Trim$(Str$(propID)) _
                    + " is not a CBUSH PBUSH (type=" + Trim$(Str$(pr.type)) + ") - using anyway")
            End If
        End If

        rc = pickSet.Select(FT_ELEM, True, "Select GROUP-1 RBE2s to connect with property " + Trim$(Str$(propID)))
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Location selection cancelled - finishing")
            Exit Do
        End If

        App.feAppLock
        roundMade = 0
        pickedID = pickSet.First()
        Do While pickedID > 0
            found = -1
            For ci = 0 To nCand - 1
                If cG1Elem(ci) = pickedID And Not cAssigned(ci) Then
                    found = ci
                    Exit For
                End If
            Next ci
            If found >= 0 Then
                Set cb = App.feElem
                newID = cb.NextEmptyID
                cb.type     = FET_L_SPRING
                cb.topology = FTO_LINE2
                cb.node(0)  = cG1Node(found)
                cb.node(1)  = cG2Node(found)
                cb.propID   = propID
                cb.SetSpringOrient(3, csysID, 0.0, 0.0, 0.0)   ' 3 = FESO_ELCID
                If cb.Put(newID) = FE_OK Then
                    createdElemSet.Add(newID)
                    cAssigned(found) = True
                    roundMade = roundMade + 1
                    totalMade = totalMade + 1
                End If
            End If
            pickedID = pickSet.Next()
        Loop
        App.feAppUnlock

        If roundMade > 0 Then usedPropSet.Add(propID)
        App.feAppMessage(FCM_NORMAL, "Type " + Trim$(Str$(roundNo)) + ": created " _
            + Trim$(Str$(roundMade)) + " CBUSH with property " + Trim$(Str$(propID)))

        If MsgBox("Define another connection type (e.g. shear pins)?", vbYesNo, "CBUSH Connect") = vbYes Then
            moreTypes = True
        Else
            moreTypes = False
        End If
    Loop

    ' ============================================================
    ' Section 7: Remove the preview graphics
    ' ============================================================
    gfx.DeleteAll(False, lineIdSet.ID)
    App.feDelete(FT_TEXT, textIdSet.ID)

    If totalMade = 0 Then
        App.feViewRegenerate(0)
        App.feAppMessage(FCM_WARNING, "No CBUSH elements were created")
        Exit Sub
    End If

    ' ============================================================
    ' Section 8: Output group (new or existing)
    ' ============================================================
    Dim gpOut As femap.Group
    Set gpOut = App.feGroup
    Dim outID As Long
    outID = -1

    If MsgBox("Put connections in a NEW group?  (No = add to an existing group)", _
        vbYesNo, "CBUSH Connect - Output group") = vbYes Then
        Dim gname As String
        gname = InputBox$("Name for the new connection group:", "CBUSH Connect", "CBUSH Connections")
        If Trim$(gname) = "" Then gname = "CBUSH Connections"
        outID = gpOut.NextEmptyID
        gpOut.title = gname
        gpOut.Put(outID)
    Else
        rc = grpSet.Select(FT_GROUP, True, "Select existing group to add connections to")
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "No output group selected - connections created but not grouped")
        Else
            outID = grpSet.First()
            gpOut.Get(outID)
        End If
    End If

    If outID > 0 Then
        Dim csOneSet As femap.Set
        Set csOneSet = App.feSet
        csOneSet.Add(csysID)
        gpOut.SetAdd(FT_ELEM, createdElemSet.ID)
        gpOut.SetAdd(FT_PROP, usedPropSet.ID)
        gpOut.SetAdd(FT_CSYS, csOneSet.ID)
        App.feAppMessage(FCM_NORMAL, "Connections added to group " + Trim$(Str$(outID)))
    End If

    ' ============================================================
    ' Section 9: Report
    ' ============================================================
    App.feViewRegenerate(0)
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Connect RBE2 with CBUSH - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Group 1 RBE2s:        " + Str$(n1))
    App.feAppMessage(FCM_NORMAL, "  Group 2 RBE2s:        " + Str$(n2))
    App.feAppMessage(FCM_NORMAL, "  Candidate pairs:      " + Str$(nCand))
    App.feAppMessage(FCM_NORMAL, "  CBUSH created:        " + Str$(totalMade))
    App.feAppMessage(FCM_NORMAL, "  Orientation CSys:     " + Str$(csysID))
    If outID > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Output group:         " + Str$(outID))
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
