' =============================================================================
' Interpolate Temp Between Sets
' -----------------------------------------------------------------------------
' Two node sets that already carry nodal temperatures, plus the nodes between
' them, and a linear gradient is written across the middle.
'
' Distinct from Extrapolate Temp Gradient, which fits a line through ONE seeded
' region and projects it outward. This one is BOUNDED: both ends are known, so
' nothing is predicted beyond the data. That difference matters - extrapolation
' can run to physically absurd temperatures far from the seed, and interpolation
' between two measured faces cannot.
'
' HOW A NODE'S POSITION IS MEASURED
' ---------------------------------
' The axis runs from the centroid of set A to the centroid of set B. A middle
' node's fraction is its projection onto that axis, so the field is constant on
' every plane perpendicular to it - the textbook linear gradient through a wall,
' a flange, a standoff.
'
' This is the right model when A and B are roughly parallel faces. It is the
' WRONG model when the path between them curves, because the projection then
' measures the straight-line distance rather than the distance through material.
' There is no way for the tool to detect that from the node positions alone, so
' it is stated here rather than guarded against.
'
' MODIFIES THE MODEL - it creates nodal temperature loads.
' =============================================================================

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, k As Long

    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feAppMessage(FCM_NORMAL, "INTERPOLATE TEMP BETWEEN SETS")
    App.feAppMessage(FCM_NORMAL, "==================================================")

    ' ============================================================
    ' Section 1: Pick the load set holding the existing temperatures
    ' ============================================================
    Dim ls As femap.LoadSet
    Set ls = App.feLoadSet

    Dim lsCount As Long
    lsCount = 0
    ls.Reset
    Do While ls.Next()
        lsCount = lsCount + 1
    Loop
    If lsCount = 0 Then
        App.feAppMessage(FCM_ERROR, "No load sets in the model - exiting")
        Exit Sub
    End If

    Dim lsIDs() As Long
    Dim lsNames() As String
    ReDim lsIDs(lsCount - 1)
    ReDim lsNames(lsCount - 1)
    Dim activeLS As Long, activeIdx As Long
    activeLS = App.Info_ActiveID(FT_LOAD_DIR)
    activeIdx = 0
    i = 0
    ls.Reset
    Do While ls.Next()
        lsIDs(i) = ls.ID
        lsNames(i) = Trim$(Str$(ls.ID)) + " - " + ls.title
        If ls.ID = activeLS Then activeIdx = i
        i = i + 1
    Loop

    ' Labels get generous width - the dialog font is proportional, so a width
    ' guessed from the character count clips the tail of the string silently.
    Begin Dialog SrcDlg 420, 134, "Interpolate Temp Between Sets - Source"
        Text        12, 12, 396, 14, "Load set holding the existing nodal temperatures:"
        DropListBox 12, 34, 396, 80, lsNames(), .lsPick
        OKButton    120, 98, 84, 22
        CancelButton 216, 98, 84, 22
    End Dialog
    Dim sdlg As SrcDlg
    sdlg.lsPick = activeIdx
    If Dialog(sdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - no changes made")
        Exit Sub
    End If
    Dim srcSetID As Long
    srcSetID = lsIDs(sdlg.lsPick)

    ' ============================================================
    ' Section 2: The three node selections
    ' ============================================================
    Dim setA As femap.Set
    Set setA = App.feSet
    rc = setA.Select(FT_NODE, True, "Select END SET A - nodes that already have temperatures")
    If rc = FE_CANCEL Or setA.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - no changes made")
        Exit Sub
    End If

    Dim setB As femap.Set
    Set setB = App.feSet
    rc = setB.Select(FT_NODE, True, "Select END SET B - nodes that already have temperatures")
    If rc = FE_CANCEL Or setB.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - no changes made")
        Exit Sub
    End If

    Dim setM As femap.Set
    Set setM = App.feSet
    rc = setM.Select(FT_NODE, True, "Select the nodes BETWEEN A and B")
    If rc = FE_CANCEL Or setM.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - no changes made")
        Exit Sub
    End If

    ' ============================================================
    ' Section 3: Read the existing temperatures
    ' ============================================================
    Dim nt As femap.LoadNTemp
    Set nt = App.feLoadNTemp
    nt.setID = srcSetID              ' GetAllArray requires setID be set first

    Dim nSeed As Long
    Dim vExp As Variant, vTNode As Variant, vTLayer As Variant
    Dim vTColor As Variant, vTDef As Variant, vTemp As Variant, vTFunc As Variant
    rc = nt.GetAllArray(nSeed, vExp, vTNode, vTLayer, vTColor, vTDef, vTemp, vTFunc)
    If rc <> FE_OK Or nSeed = 0 Then
        App.feAppMessage(FCM_ERROR, "Load set " + Trim$(Str$(srcSetID)) _
            + " has no nodal temperatures - exiting")
        Exit Sub
    End If

    ' ============================================================
    ' Section 4: Coordinates
    ' ============================================================
    Dim nd As femap.Node
    Set nd = App.feNode

    Dim nA As Long, nBn As Long, nM As Long
    Dim vAID As Variant, vAXYZ As Variant
    Dim vBID As Variant, vBXYZ As Variant
    Dim vMID As Variant, vMXYZ As Variant
    Dim vLa As Variant, vCa As Variant, vTa As Variant
    Dim vDa As Variant, vOa As Variant, vPa As Variant

    rc = nd.GetAllArray(setA.ID, nA, vAID, vAXYZ, vLa, vCa, vTa, vDa, vOa, vPa)
    If rc <> FE_OK Or nA = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read coordinates for set A - exiting")
        Exit Sub
    End If
    rc = nd.GetAllArray(setB.ID, nBn, vBID, vBXYZ, vLa, vCa, vTa, vDa, vOa, vPa)
    If rc <> FE_OK Or nBn = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read coordinates for set B - exiting")
        Exit Sub
    End If
    rc = nd.GetAllArray(setM.ID, nM, vMID, vMXYZ, vLa, vCa, vTa, vDa, vOa, vPa)
    If rc <> FE_OK Or nM = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read coordinates for the middle nodes - exiting")
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: Temperature lookup by node ID
    ' ============================================================
    ' An array indexed by node ID, not a search per node. Node IDs are not dense
    ' so the array is sparse, but a lookup is O(1) against O(n) for a scan and
    ' this runs once per end node.
    Dim maxID As Long
    maxID = 0
    For k = LBound(vTNode) To UBound(vTNode)
        If vTNode(k) > maxID Then maxID = vTNode(k)
    Next k
    For k = LBound(vAID) To UBound(vAID)
        If vAID(k) > maxID Then maxID = vAID(k)
    Next k
    For k = LBound(vBID) To UBound(vBID)
        If vBID(k) > maxID Then maxID = vBID(k)
    Next k

    Dim tempOf() As Double
    Dim hasT() As Integer
    ReDim tempOf(maxID)
    ReDim hasT(maxID)
    For k = LBound(vTNode) To UBound(vTNode)
        If vTNode(k) > 0 And vTNode(k) <= maxID Then
            tempOf(vTNode(k)) = CDbl(vTemp(k))
            hasT(vTNode(k)) = 1
        End If
    Next k

    ' ============================================================
    ' Section 6: End temperatures, and whether they are really uniform
    ' ============================================================
    ' The tool was asked for on the understanding that each end set is all one
    ' temperature. If that is not true, averaging silently would produce a
    ' gradient that looks right and is not - so the spread is measured and shown
    ' before anything is written.
    Dim sumA As Double, minA As Double, maxA As Double, cntA As Long
    Dim sumB As Double, minB As Double, maxB As Double, cntB As Long
    Dim missA As Long, missB As Long
    Dim tv As Double
    Dim nid As Long
    sumA = 0.0 : minA = 0.0 : maxA = 0.0 : cntA = 0 : missA = 0
    sumB = 0.0 : minB = 0.0 : maxB = 0.0 : cntB = 0 : missB = 0

    For k = LBound(vAID) To UBound(vAID)
        nid = vAID(k)
        If nid > 0 And nid <= maxID Then
            If hasT(nid) = 1 Then
                tv = tempOf(nid)
                If cntA = 0 Then
                    minA = tv
                    maxA = tv
                Else
                    If tv < minA Then minA = tv
                    If tv > maxA Then maxA = tv
                End If
                sumA = sumA + tv
                cntA = cntA + 1
            Else
                missA = missA + 1
            End If
        End If
    Next k

    For k = LBound(vBID) To UBound(vBID)
        nid = vBID(k)
        If nid > 0 And nid <= maxID Then
            If hasT(nid) = 1 Then
                tv = tempOf(nid)
                If cntB = 0 Then
                    minB = tv
                    maxB = tv
                Else
                    If tv < minB Then minB = tv
                    If tv > maxB Then maxB = tv
                End If
                sumB = sumB + tv
                cntB = cntB + 1
            Else
                missB = missB + 1
            End If
        End If
    Next k

    If cntA = 0 Or cntB = 0 Then
        App.feAppMessage(FCM_ERROR, "One of the end sets has NO temperatures in load set " _
            + Trim$(Str$(srcSetID)) + " - exiting")
        App.feAppMessage(FCM_ERROR, "  Set A: " + Trim$(Str$(cntA)) + " of " + Trim$(Str$(nA)) _
            + " nodes have a temperature")
        App.feAppMessage(FCM_ERROR, "  Set B: " + Trim$(Str$(cntB)) + " of " + Trim$(Str$(nBn)) _
            + " nodes have a temperature")
        Exit Sub
    End If

    Dim tA As Double, tB As Double
    tA = sumA / CDbl(cntA)
    tB = sumB / CDbl(cntB)

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "  Set A: " + Trim$(Str$(cntA)) + " of " + Trim$(Str$(nA)) _
        + " nodes have temps   value " + Format$(tA, "0.0000") _
        + "   spread " + Format$(maxA - minA, "0.000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Set B: " + Trim$(Str$(cntB)) + " of " + Trim$(Str$(nBn)) _
        + " nodes have temps   value " + Format$(tB, "0.0000") _
        + "   spread " + Format$(maxB - minB, "0.000E+00"))
    If missA > 0 Or missB > 0 Then
        App.feAppMessage(FCM_WARNING, "  " + Trim$(Str$(missA + missB)) _
            + " end node(s) have no temperature and were ignored in the average.")
    End If

    Dim spread As Double
    spread = maxA - minA
    If (maxB - minB) > spread Then spread = maxB - minB
    If spread > 0.0 Then
        App.feAppMessage(FCM_WARNING, "  An end set is NOT uniform - the average is being used.")
        ' Kept under 160 characters: feAppMessageBox truncates beyond that.
        rc = App.feAppMessageBox(1, "An end set is not uniform (spread " _
            + Format$(spread, "0.000") + "). The average will be used. Continue?")
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Cancelled - no changes made")
            Exit Sub
        End If
    End If

    ' ============================================================
    ' Section 7: The axis, from centroid to centroid
    ' ============================================================
    Dim aX As Double, aY As Double, aZ As Double
    Dim bX As Double, bY As Double, bZ As Double
    aX = 0.0 : aY = 0.0 : aZ = 0.0
    bX = 0.0 : bY = 0.0 : bZ = 0.0

    ' GetAllArray returns xyz packed three-per-node, so node k is at 3k, 3k+1, 3k+2.
    For k = 0 To nA - 1
        aX = aX + CDbl(vAXYZ(3 * k))
        aY = aY + CDbl(vAXYZ(3 * k + 1))
        aZ = aZ + CDbl(vAXYZ(3 * k + 2))
    Next k
    aX = aX / CDbl(nA)
    aY = aY / CDbl(nA)
    aZ = aZ / CDbl(nA)

    For k = 0 To nBn - 1
        bX = bX + CDbl(vBXYZ(3 * k))
        bY = bY + CDbl(vBXYZ(3 * k + 1))
        bZ = bZ + CDbl(vBXYZ(3 * k + 2))
    Next k
    bX = bX / CDbl(nBn)
    bY = bY / CDbl(nBn)
    bZ = bZ / CDbl(nBn)

    Dim dX As Double, dY As Double, dZ As Double
    Dim axLen As Double
    dX = bX - aX
    dY = bY - aY
    dZ = bZ - aZ
    axLen = Sqr(dX * dX + dY * dY + dZ * dZ)

    ' Coincident centroids give no direction at all. This happens when A and B
    ' are concentric - inner and outer face of a cylinder, say - where the two
    ' sets are genuinely nested rather than opposed. Projection cannot describe
    ' that, so it stops rather than dividing by zero.
    If axLen <= 0.0 Then
        App.feAppMessage(FCM_ERROR, "The two end sets have the same centroid - no axis exists.")
        App.feAppMessage(FCM_ERROR, "Concentric or interleaved sets cannot use a projected gradient.")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "  Axis A->B: (" + Format$(dX / axLen, "0.0000") + ", " _
        + Format$(dY / axLen, "0.0000") + ", " + Format$(dZ / axLen, "0.0000") _
        + ")   length " + Format$(axLen, "0.0000"))

    ' ============================================================
    ' Section 8: Options
    ' ============================================================
    Dim destNames(1) As String
    destNames(0) = "The source load set " + Trim$(Str$(srcSetID))
    destNames(1) = "A new load set"

    Begin Dialog OptDlg 430, 190, "Interpolate Temp Between Sets - Options"
        Text        12, 12, 406, 14, "Middle nodes get T = Ta + f (Tb - Ta), f = projection onto the A->B axis."
        Text        12, 30, 406, 14, "Ta and Tb are the two end-set temperatures shown in the Messages window."
        CheckBox    12, 54, 406, 14, "Clamp f to the 0..1 range (nodes outside A..B take the nearer end value)", .doClamp
        Text        12, 80, 130, 14, "Write results to:"
        DropListBox 150, 78, 268, 60, destNames(), .dest
        Text        12, 108, 130, 14, "New load set title:"
        TextBox     150, 106, 268, 18, .newTitle
        OKButton    126, 152, 84, 22
        CancelButton 222, 152, 84, 22
    End Dialog
    Dim odlg As OptDlg
    odlg.doClamp = 1
    odlg.dest = 0
    odlg.newTitle = "Interpolated gradient"
    If Dialog(odlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - no changes made")
        Exit Sub
    End If

    ' ============================================================
    ' Section 9: Interpolate
    ' ============================================================
    Dim vOutNode() As Long
    Dim vOutTemp() As Double
    Dim vOutFunc() As Long
    ReDim vOutNode(nM - 1)
    ReDim vOutTemp(nM - 1)
    ReDim vOutFunc(nM - 1)

    Dim f As Double
    Dim pX As Double, pY As Double, pZ As Double
    Dim nClamp As Long
    Dim outMin As Double, outMax As Double
    nClamp = 0
    outMin = 0.0
    outMax = 0.0

    For k = 0 To nM - 1
        pX = CDbl(vMXYZ(3 * k)) - aX
        pY = CDbl(vMXYZ(3 * k + 1)) - aY
        pZ = CDbl(vMXYZ(3 * k + 2)) - aZ

        ' Fraction along the axis. Dividing by axLen twice - once to normalise
        ' the axis, once to turn the projected length into a fraction.
        f = (pX * dX + pY * dY + pZ * dZ) / (axLen * axLen)

        If f < 0.0 Or f > 1.0 Then
            nClamp = nClamp + 1
            If odlg.doClamp <> 0 Then
                If f < 0.0 Then
                    f = 0.0
                Else
                    f = 1.0
                End If
            End If
        End If

        vOutNode(k) = CLng(vMID(k))
        vOutTemp(k) = tA + f * (tB - tA)
        vOutFunc(k) = 0
        If k = 0 Then
            outMin = vOutTemp(k)
            outMax = vOutTemp(k)
        Else
            If vOutTemp(k) < outMin Then outMin = vOutTemp(k)
            If vOutTemp(k) > outMax Then outMax = vOutTemp(k)
        End If
    Next k

    ' A middle node outside the A..B span is a selection problem, not a maths
    ' problem - it says the "between" set reaches past one of the ends.
    If nClamp > 0 Then
        If odlg.doClamp <> 0 Then
            App.feAppMessage(FCM_WARNING, "  " + Trim$(Str$(nClamp)) _
                + " middle node(s) lie outside the A..B span and were clamped to an end value.")
        Else
            App.feAppMessage(FCM_WARNING, "  " + Trim$(Str$(nClamp)) _
                + " middle node(s) lie outside the A..B span - they were EXTRAPOLATED.")
        End If
        App.feAppMessage(FCM_WARNING, "  Check the middle selection does not reach past an end set.")
    End If

    ' ============================================================
    ' Section 10: Write
    ' ============================================================
    Dim dstSetID As Long
    If odlg.dest = 0 Then
        dstSetID = srcSetID
    Else
        Dim lsNew As femap.LoadSet
        Set lsNew = App.feLoadSet
        dstSetID = lsNew.NextEmptyID
        lsNew.title = odlg.newTitle
        rc = lsNew.Put(dstSetID)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Could not create the new load set - exiting")
            Exit Sub
        End If
    End If

    Dim ntW As femap.LoadNTemp
    Set ntW = App.feLoadNTemp
    ntW.setID = dstSetID

    App.feAppLock
    rc = ntW.PutArray(nM, True, True, vOutNode, vOutTemp, vOutFunc)
    App.feAppUnlock

    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "PutArray failed - no temperatures written")
        Exit Sub
    End If

    ' Group Automatic Add writes into whatever group it targets, so the target
    ' has to be re-evaluated or it shows stale contents. No-op when it is off.
    Dim autoAdd As Long, autoGrp As Long
    autoGrp = 0
    autoAdd = App.Info_GroupAutomaticAdd
    If autoAdd = -1 Then
        autoGrp = App.Info_ActiveID(FT_GROUP)
    ElseIf autoAdd > 0 Then
        autoGrp = autoAdd
    End If
    If autoGrp > 0 Then App.feGroupEvaluate(-autoGrp, True)

    App.feViewRegenerate(0)

    ' ============================================================
    ' Section 11: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "")
    App.feAppMessage(FCM_HIGHLIGHT, "  Interpolate Temp Between Sets - done")
    App.feAppMessage(FCM_NORMAL, "    Source load set:   " + Trim$(Str$(srcSetID)))
    App.feAppMessage(FCM_NORMAL, "    End A temperature: " + Format$(tA, "0.0000") _
        + "   (" + Trim$(Str$(cntA)) + " nodes)")
    App.feAppMessage(FCM_NORMAL, "    End B temperature: " + Format$(tB, "0.0000") _
        + "   (" + Trim$(Str$(cntB)) + " nodes)")
    App.feAppMessage(FCM_NORMAL, "    Middle nodes:      " + Trim$(Str$(nM)))
    App.feAppMessage(FCM_NORMAL, "    Written to set:    " + Trim$(Str$(dstSetID)))
    App.feAppMessage(FCM_NORMAL, "    Result range:      " + Format$(outMin, "0.0000") _
        + " to " + Format$(outMax, "0.0000"))
    If nClamp > 0 Then
        App.feAppMessage(FCM_WARNING, "    Outside A..B span: " + Trim$(Str$(nClamp)))
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "==================================================")
End Sub
