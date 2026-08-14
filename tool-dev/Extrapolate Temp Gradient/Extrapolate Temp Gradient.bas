' Extrapolate Temp Gradient.bas
' -----------------------------------------------------------------------------
' Read the nodal temperatures that already exist on part of a model, fit a
' LINEAR gradient along a chosen axis, and apply that gradient to the rest of
' the model - extrapolating in both directions past the seeded region.
'
' Typical use: a thermal run (or a hand-built map) covers one component, and the
' surrounding structure needs a consistent temperature field on the same trend.
'
' Flow:
'   1. Pick the SOURCE load set (the one holding the existing temperatures)
'   2. The tool reads every nodal temperature in it and the matching node coords
'   3. It least-squares fits T = a + b*s along global X, Y and Z, and reports
'      the R-squared of each so you can see which axis the gradient really runs
'      along - and whether the field is actually linear at all
'   4. Pick the axis (or a custom vector), the target nodes, and the target set
'   5. Confirm dialog shows the fit and the resulting temperature range
'   6. Temperatures are written with LoadNTemp.PutArray
'
' The R-squared readout is the point of the confirm step. If it is well below
' 1.0 the field is not linear along that axis and extrapolating it is wrong -
' abort rather than manufacture a plausible-looking but meaningless field.
'
' Notes / limits (v1):
'   - Every target node gets the FITTED value, including nodes that were part of
'     the seed. With a truly linear source field (R-squared = 1.0) those come
'     back identical; if they don't, the source was not linear and the confirm
'     dialog will have said so.
'   - Node coordinates from the API are global rectangular, so the projection
'     axis is interpreted in global rectangular coordinates.
'   - Temperature-dependent functions (LoadNTemp.function) are not carried over;
'     created temperatures are constant values (function ID 0).
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, k As Long

    ' ============================================================
    ' Section 1: Pick the source load set
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
        lsIDs(i)   = ls.ID
        lsNames(i) = Trim$(Str$(ls.ID)) + " - " + ls.title
        If ls.ID = activeLS Then activeIdx = i
        i = i + 1
    Loop

    Begin Dialog SrcDlg 400, 134, "Extrapolate Temp Gradient - Source"
        Text        12, 12, 376, 12, "Load set holding the existing nodal temperatures:"
        DropListBox 12, 32, 376, 60, lsNames(), .lsPick
        OKButton     110, 96, 80, 20
        CancelButton 210, 96, 80, 20
    End Dialog

    Dim sdlg As SrcDlg
    sdlg.lsPick = activeIdx
    If Dialog(sdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim srcSetID As Long
    srcSetID = lsIDs(sdlg.lsPick)

    ' ============================================================
    ' Section 2: Read the existing nodal temperatures
    ' ============================================================
    Dim nt As femap.LoadNTemp
    Set nt = App.feLoadNTemp
    nt.setID = srcSetID                  ' GetAllArray requires setID be set first

    Dim nSeed As Long
    Dim vExp As Variant, vTNode As Variant, vTLayer As Variant
    Dim vTColor As Variant, vTDef As Variant, vTemp As Variant, vTFunc As Variant
    rc = nt.GetAllArray(nSeed, vExp, vTNode, vTLayer, vTColor, vTDef, vTemp, vTFunc)
    If rc <> FE_OK Or nSeed = 0 Then
        App.feAppMessage(FCM_ERROR, "Load set " + Trim$(Str$(srcSetID)) _
            + " has no nodal temperatures - exiting")
        Exit Sub
    End If
    If nSeed < 2 Then
        App.feAppMessage(FCM_ERROR, "Need at least 2 seeded nodes to fit a gradient - exiting")
        Exit Sub
    End If

    ' ============================================================
    ' Section 3: Get coordinates for the seeded nodes
    ' Both GetAllArray calls return ascending entity ID, so the arrays normally
    ' pair position-for-position. Verify that, and binary-search if they don't.
    ' ============================================================
    Dim seedSet As femap.Set
    Set seedSet = App.feSet
    seedSet.AddArray(nSeed, vTNode)

    Dim nd As femap.Node
    Set nd = App.feNode

    Dim nSN As Long
    Dim vSNID As Variant, vSXYZ As Variant
    Dim vL1 As Variant, vC1 As Variant, vT1 As Variant
    Dim vD1 As Variant, vO1 As Variant, vP1 As Variant
    rc = nd.GetAllArray(seedSet.ID, nSN, vSNID, vSXYZ, vL1, vC1, vT1, vD1, vO1, vP1)
    If rc <> FE_OK Or nSN = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read coordinates for the seeded nodes - exiting")
        Exit Sub
    End If

    ' Unpack into typed arrays: seed coords aligned with seed temperatures
    Dim sX() As Double, sY() As Double, sZ() As Double, sT() As Double
    ReDim sX(nSeed - 1)
    ReDim sY(nSeed - 1)
    ReDim sZ(nSeed - 1)
    ReDim sT(nSeed - 1)

    Dim nID() As Long
    ReDim nID(nSN - 1)
    For k = 0 To nSN - 1
        nID(k) = CLng(vSNID(k))
    Next k

    Dim aligned As Boolean
    aligned = (nSN = nSeed)
    If aligned Then
        For k = 0 To nSeed - 1
            If nID(k) <> CLng(vTNode(k)) Then
                aligned = False
                Exit For
            End If
        Next k
    End If

    Dim hit As Long, missing As Long
    missing = 0
    For k = 0 To nSeed - 1
        If aligned Then
            hit = k
        Else
            hit = FindID(nID, nSN, CLng(vTNode(k)))
        End If
        If hit < 0 Then
            missing = missing + 1
            sX(k) = 0.0 : sY(k) = 0.0 : sZ(k) = 0.0 : sT(k) = 0.0
        Else
            sX(k) = CDbl(vSXYZ(hit * 3))
            sY(k) = CDbl(vSXYZ(hit * 3 + 1))
            sZ(k) = CDbl(vSXYZ(hit * 3 + 2))
            sT(k) = CDbl(vTemp(k))
        End If
    Next k

    If missing >= nSeed - 1 Then
        App.feAppMessage(FCM_ERROR, "Could not match seeded temperatures to nodes - exiting")
        Exit Sub
    End If

    ' Seeded temperature range (used for the optional clamp)
    Dim tMin As Double, tMax As Double
    tMin = sT(0) : tMax = sT(0)
    For k = 1 To nSeed - 1
        If sT(k) < tMin Then tMin = sT(k)
        If sT(k) > tMax Then tMax = sT(k)
    Next k

    App.feAppMessage(FCM_NORMAL, "Read " + Trim$(Str$(nSeed)) + " nodal temperature(s) from load set " _
        + Trim$(Str$(srcSetID)) + "   (range " + Fmt(tMin) + " to " + Fmt(tMax) + ")")

    ' ============================================================
    ' Section 4: Fit along global X, Y, Z so the user can see which axis wins
    ' ============================================================
    Dim aX As Double, bX As Double, r2X As Double, okX As Boolean
    Dim aY As Double, bY As Double, r2Y As Double, okY As Boolean
    Dim aZ As Double, bZ As Double, r2Z As Double, okZ As Boolean
    okX = FitAxis(nSeed, sX, sY, sZ, sT, 1.0, 0.0, 0.0, aX, bX, r2X)
    okY = FitAxis(nSeed, sX, sY, sZ, sT, 0.0, 1.0, 0.0, aY, bY, r2Y)
    okZ = FitAxis(nSeed, sX, sY, sZ, sT, 0.0, 0.0, 1.0, aZ, bZ, r2Z)

    ' Slope and R2 go in their own columns - the dialog font is proportional,
    ' so padding them into one string does not line up.
    Dim slpX As String, slpY As String, slpZ As String
    Dim rsqX As String, rsqY As String, rsqZ As String
    slpX = SlopeText(okX, bX) : rsqX = R2Text(okX, r2X)
    slpY = SlopeText(okY, bY) : rsqY = R2Text(okY, r2Y)
    slpZ = SlopeText(okZ, bZ) : rsqZ = R2Text(okZ, r2Z)

    Dim seedLine As String
    seedLine = Trim$(Str$(nSeed)) + " seeded nodes,  T from " _
             + Fmt(tMin) + " to " + Fmt(tMax)

    Begin Dialog AxisDlg 430, 286, "Extrapolate Temp Gradient - Axis"
        Text     12, 10, 406, 12, seedLine
        Text     12, 30, 406, 12, "Linear fit per axis.  R2 near 1 means the field really is a linear gradient:"
        Text     28, 50, 44, 12, "Axis"
        Text     76, 50, 170, 12, "Slope (per unit length)"
        Text     256, 50, 100, 12, "R2"
        Text     28, 68, 44, 12, "X"
        Text     76, 68, 170, 12, slpX
        Text     256, 68, 160, 12, rsqX
        Text     28, 84, 44, 12, "Y"
        Text     76, 84, 170, 12, slpY
        Text     256, 84, 160, 12, rsqY
        Text     28, 100, 44, 12, "Z"
        Text     76, 100, 170, 12, slpZ
        Text     256, 100, 160, 12, rsqZ
        GroupBox 12, 126, 406, 104, "Extrapolate Along"
        OptionGroup .axisPick
            OptionButton 26, 146, 240, 12, "Global X"
            OptionButton 26, 166, 240, 12, "Global Y"
            OptionButton 26, 186, 240, 12, "Global Z"
            OptionButton 26, 206, 340, 12, "Custom vector  (you pick it next)"
        OKButton     125, 248, 80, 20
        CancelButton 225, 248, 80, 20
    End Dialog

    Dim adlg As AxisDlg
    ' Default to whichever global axis fits best
    adlg.axisPick = 0
    If okY And (Not okX Or r2Y > r2X) Then adlg.axisPick = 1
    If okZ And ((Not okX And Not okY) Or (r2Z > r2X And r2Z > r2Y)) Then adlg.axisPick = 2

    If Dialog(adlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim ux As Double, uy As Double, uz As Double
    Dim axisName As String
    If adlg.axisPick = 0 Then
        ux = 1.0 : uy = 0.0 : uz = 0.0 : axisName = "global X"
    ElseIf adlg.axisPick = 1 Then
        ux = 0.0 : uy = 1.0 : uz = 0.0 : axisName = "global Y"
    ElseIf adlg.axisPick = 2 Then
        ux = 0.0 : uy = 0.0 : uz = 1.0 : axisName = "global Z"
    Else
        ' feVectorPick( dlgTitle, unitVector, vecLength, vecBase, vecDir )
        ' vecDir always comes back as a unit vector, so use it directly.
        Dim vecLen As Double
        Dim vBase As Variant, vDir As Variant
        rc = App.feVectorPick("Pick the direction to extrapolate the gradient along", _
                              True, vecLen, vBase, vDir)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Vector pick cancelled - no changes made")
            Exit Sub
        End If
        ux = CDbl(vDir(0))
        uy = CDbl(vDir(1))
        uz = CDbl(vDir(2))
        axisName = "custom vector"
    End If

    Dim fitA As Double, fitB As Double, fitR2 As Double, fitOK As Boolean
    fitOK = FitAxis(nSeed, sX, sY, sZ, sT, ux, uy, uz, fitA, fitB, fitR2)
    If Not fitOK Then
        App.feAppMessage(FCM_ERROR, "Cannot fit along " + axisName _
            + " - the seeded nodes have no spread in that direction. Exiting.")
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: Target nodes + write options
    ' ============================================================
    Dim tgtSet As femap.Set
    Set tgtSet = App.feSet
    rc = tgtSet.Select(FT_NODE, True, "Select nodes to apply the extrapolated gradient to")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No target nodes selected - no changes made")
        Exit Sub
    End If

    Dim nTgt As Long
    Dim vTID As Variant, vTXYZ As Variant
    Dim vL2 As Variant, vC2 As Variant, vT2 As Variant
    Dim vD2 As Variant, vO2 As Variant, vP2 As Variant
    rc = nd.GetAllArray(tgtSet.ID, nTgt, vTID, vTXYZ, vL2, vC2, vT2, vD2, vO2, vP2)
    If rc <> FE_OK Or nTgt = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read target node coordinates - exiting")
        Exit Sub
    End If

    Dim tgtLine As String, srcLine As String
    tgtLine = Trim$(Str$(nTgt)) + " target node(s) selected"
    srcLine = "Extrapolating along " + axisName + "   (R2 = " + Fmt(fitR2) + ")"

    Begin Dialog OptDlg 430, 262, "Extrapolate Temp Gradient - Options"
        Text     12, 10, 406, 12, tgtLine
        Text     12, 26, 406, 12, srcLine
        GroupBox 12, 48, 406, 84, "Write Temperatures To"
        OptionGroup .dest
            OptionButton 26, 68, 300, 12, "The source load set"
            OptionButton 26, 92, 90, 12, "New set:"
        TextBox  120, 90, 288, 12, .newTitle
        CheckBox 12, 146, 406, 12, "Clamp results to the seeded temperature range", .chkClamp
        Text     30, 162, 388, 12, "(caps runaway values far outside the seeded region)"
        Text     12, 186, 406, 24, "The next dialog shows the fit and the resulting temperature range before anything is written."
        OKButton     125, 224, 80, 20
        CancelButton 225, 224, 80, 20
    End Dialog

    Dim odlg As OptDlg
    odlg.dest     = 0
    odlg.newTitle = "Extrapolated Temp Gradient"
    odlg.chkClamp = 0
    If Dialog(odlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim doClamp As Boolean
    doClamp = (odlg.chkClamp <> 0)

    ' ============================================================
    ' Section 6: Evaluate the gradient at every target node
    ' ============================================================
    Dim uLen As Double
    uLen = Sqr(ux * ux + uy * uy + uz * uz)
    Dim nux As Double, nuy As Double, nuz As Double
    nux = ux / uLen : nuy = uy / uLen : nuz = uz / uLen

    Dim vOutNode As Variant, vOutTemp As Variant, vOutFunc As Variant
    ReDim vOutNode(nTgt - 1)
    ReDim vOutTemp(nTgt - 1)
    ReDim vOutFunc(nTgt - 1)

    Dim ss As Double, tv As Double
    Dim outMin As Double, outMax As Double
    Dim clampedCnt As Long
    clampedCnt = 0

    For k = 0 To nTgt - 1
        ss = CDbl(vTXYZ(k * 3)) * nux _
           + CDbl(vTXYZ(k * 3 + 1)) * nuy _
           + CDbl(vTXYZ(k * 3 + 2)) * nuz
        tv = fitA + fitB * ss
        If doClamp Then
            If tv < tMin Then
                tv = tMin
                clampedCnt = clampedCnt + 1
            ElseIf tv > tMax Then
                tv = tMax
                clampedCnt = clampedCnt + 1
            End If
        End If
        If k = 0 Then
            outMin = tv : outMax = tv
        Else
            If tv < outMin Then outMin = tv
            If tv > outMax Then outMax = tv
        End If
        vOutNode(k) = CLng(vTID(k))
        vOutTemp(k) = CDbl(tv)
        vOutFunc(k) = CLng(0)
    Next k

    ' ============================================================
    ' Section 7: Confirm (nothing written yet)
    ' ============================================================
    ' Label column / value column - one value per row, so nothing gets clipped.
    Dim vAxis As String, vFit As String, vR2 As String
    Dim vNodes As String, vSeedRng As String, vOutRng As String
    vAxis    = axisName + "   (" + Fmt(nux) + ", " + Fmt(nuy) + ", " + Fmt(nuz) + ")"
    vFit     = "T = " + Fmt(fitA) + "  +  " + Fmt(fitB) + " * s"
    vR2      = Fmt(fitR2)
    vNodes   = Trim$(Str$(nTgt)) + " nodes will receive temperatures"
    vSeedRng = Fmt(tMin) + "  to  " + Fmt(tMax)
    vOutRng  = Fmt(outMin) + "  to  " + Fmt(outMax)

    Dim warnLine As String
    warnLine = ""
    If fitR2 < 0.99 Then
        warnLine = "WARNING:  R2 is below 0.99 - the source field is NOT linear along this axis," _
                 + " so the extrapolated values are not trustworthy."
    ElseIf doClamp And clampedCnt > 0 Then
        warnLine = Trim$(Str$(clampedCnt)) + " node(s) will be clamped to the seeded range."
    End If

    Begin Dialog ConfDlg 460, 250, "Extrapolate Temp Gradient - Confirm"
        Text     12, 12, 104, 12, "Axis:"
        Text     120, 12, 328, 12, vAxis
        Text     12, 30, 104, 12, "Fit:"
        Text     120, 30, 328, 12, vFit
        Text     12, 48, 104, 12, "R2:"
        Text     120, 48, 328, 12, vR2
        Text     12, 66, 104, 12, "Nodes:"
        Text     120, 66, 328, 12, vNodes
        Text     12, 88, 104, 12, "Seeded range:"
        Text     120, 88, 328, 12, vSeedRng
        Text     12, 106, 104, 12, "Result range:"
        Text     120, 106, 328, 12, vOutRng
        Text     12, 132, 436, 28, warnLine
        Text     12, 168, 436, 12, "Click OK to write the temperatures, Cancel to abort."
        OKButton     140, 210, 80, 20
        CancelButton 240, 210, 80, 20
    End Dialog

    Dim cdlg As ConfDlg
    If Dialog(cdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    ' ============================================================
    ' Section 8: Write
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
    rc = ntW.PutArray(nTgt, True, True, vOutNode, vOutTemp, vOutFunc)
    App.feAppUnlock

    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "PutArray failed - no temperatures written")
        Exit Sub
    End If

    ' Re-evaluate the Group Automatic Add target, if the user runs with it on
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
    ' Section 9: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Extrapolate Temp Gradient - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Source load set:       " + Trim$(Str$(srcSetID)))
    App.feAppMessage(FCM_NORMAL, "  Seeded nodes read:     " + Trim$(Str$(nSeed)))
    App.feAppMessage(FCM_NORMAL, "  Seeded range:          " + Fmt(tMin) + " to " + Fmt(tMax))
    App.feAppMessage(FCM_NORMAL, "  Axis:                  " + axisName _
        + "  (" + Fmt(nux) + ", " + Fmt(nuy) + ", " + Fmt(nuz) + ")")
    App.feAppMessage(FCM_NORMAL, "  Fit:                   T = " + Fmt(fitA) _
        + " + " + Fmt(fitB) + " * s")
    App.feAppMessage(FCM_NORMAL, "  R-squared:             " + Fmt(fitR2))
    If fitR2 < 0.99 Then
        App.feAppMessage(FCM_WARNING, "  Source field is not linear along this axis - review the result")
    End If
    App.feAppMessage(FCM_NORMAL, "  Target load set:       " + Trim$(Str$(dstSetID)))
    App.feAppMessage(FCM_NORMAL, "  Temperatures written:  " + Trim$(Str$(nTgt)))
    App.feAppMessage(FCM_NORMAL, "  Result range:          " + Fmt(outMin) + " to " + Fmt(outMax))
    If doClamp Then
        App.feAppMessage(FCM_NORMAL, "  Clamped to seed range: " + Trim$(Str$(clampedCnt)) + " node(s)")
    End If
    If missing > 0 Then
        App.feAppMessage(FCM_WARNING, "  Seeded temps with no matching node: " + Trim$(Str$(missing)))
    End If
    If autoGrp > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Auto-add group evaluated: " + Trim$(Str$(autoGrp)))
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub

' -----------------------------------------------------------------------------
' Least-squares fit of T = a + b*s, where s is the projection of each seeded
' node onto the (ux,uy,uz) direction. Returns False if the seeded nodes have no
' spread along that direction (nothing to fit).
'
' r2 is set to 1.0 when every seeded temperature is identical (a flat field is
' perfectly represented by a zero-slope line).
' -----------------------------------------------------------------------------
Function FitAxis(cnt As Long, px() As Double, py() As Double, pz() As Double, _
                 tt() As Double, ux As Double, uy As Double, uz As Double, _
                 outA As Double, outB As Double, outR2 As Double) As Boolean
    Dim k As Long
    Dim uLen As Double, nux As Double, nuy As Double, nuz As Double
    Dim ss As Double
    Dim sumS As Double, sumT As Double, sumSS As Double, sumST As Double
    Dim den As Double, meanT As Double, sTot As Double, sRes As Double, pred As Double

    FitAxis = False
    outA = 0.0 : outB = 0.0 : outR2 = 0.0

    uLen = Sqr(ux * ux + uy * uy + uz * uz)
    If uLen <= 0.0 Then Exit Function
    nux = ux / uLen : nuy = uy / uLen : nuz = uz / uLen

    sumS = 0.0 : sumT = 0.0 : sumSS = 0.0 : sumST = 0.0
    For k = 0 To cnt - 1
        ss = px(k) * nux + py(k) * nuy + pz(k) * nuz
        sumS  = sumS + ss
        sumT  = sumT + tt(k)
        sumSS = sumSS + ss * ss
        sumST = sumST + ss * tt(k)
    Next k

    den = cnt * sumSS - sumS * sumS
    ' Scale-aware zero test: no meaningful spread along this direction
    If Abs(den) <= 0.000000000001 * (1.0 + Abs(cnt * sumSS)) Then Exit Function

    outB = (cnt * sumST - sumS * sumT) / den
    outA = (sumT - outB * sumS) / cnt

    meanT = sumT / cnt
    sTot = 0.0 : sRes = 0.0
    For k = 0 To cnt - 1
        ss = px(k) * nux + py(k) * nuy + pz(k) * nuz
        pred = outA + outB * ss
        sTot = sTot + (tt(k) - meanT) * (tt(k) - meanT)
        sRes = sRes + (tt(k) - pred) * (tt(k) - pred)
    Next k

    If sTot <= 0.0 Then
        outR2 = 1.0                  ' flat field - a zero-slope line fits it exactly
    Else
        outR2 = 1.0 - sRes / sTot
    End If

    FitAxis = True
End Function

' -----------------------------------------------------------------------------
' Per-axis fit columns for the axis dialog.
' -----------------------------------------------------------------------------
Function SlopeText(ok As Boolean, slope As Double) As String
    If Not ok Then
        SlopeText = "(no spread this way)"
    Else
        SlopeText = Fmt(slope)
    End If
End Function

Function R2Text(ok As Boolean, r2 As Double) As String
    If Not ok Then
        R2Text = "-"
    ElseIf r2 >= 0.99999 Then
        R2Text = "1.0000   (perfectly linear)"
    ElseIf r2 < 0.99 Then
        R2Text = Fmt(r2) + "   (not linear)"
    Else
        R2Text = Fmt(r2)
    End If
End Function

' -----------------------------------------------------------------------------
' Readable number for dialogs and messages. Str$ on a Double prints up to 15
' significant digits, which overruns every fixed-width Text control - round to
' 4 decimals in the normal range and fall back to Basic's own notation only for
' values too large or too small to show that way.
' -----------------------------------------------------------------------------
Function Fmt(v As Double) As String
    Dim a As Double
    a = Abs(v)
    If a = 0.0 Then
        Fmt = "0"
    ElseIf a >= 1000000.0 Or a < 0.0001 Then
        Fmt = Trim$(Str$(v))
    Else
        Fmt = Trim$(Str$(RoundTo(v, 4)))
    End If
End Function

' Sign-aware round to a number of decimal places (Int() truncates toward
' negative infinity, so negatives need the explicit mirror).
Function RoundTo(v As Double, places As Long) As Double
    Dim sc As Double, i As Long
    sc = 1.0
    For i = 1 To places
        sc = sc * 10.0
    Next i
    If v >= 0.0 Then
        RoundTo = Int(v * sc + 0.5) / sc
    Else
        RoundTo = -Int(-v * sc + 0.5) / sc
    End If
End Function

' -----------------------------------------------------------------------------
' Binary search for target in the ascending array ids(0..cnt-1).
' Returns the index, or -1 if not found.
' -----------------------------------------------------------------------------
Function FindID(ids() As Long, cnt As Long, target As Long) As Long
    Dim lo As Long, hi As Long, mid As Long
    lo = 0
    hi = cnt - 1
    FindID = -1
    Do While lo <= hi
        mid = (lo + hi) \ 2
        If ids(mid) = target Then
            FindID = mid
            Exit Function
        ElseIf ids(mid) < target Then
            lo = mid + 1
        Else
            hi = mid - 1
        End If
    Loop
End Function
