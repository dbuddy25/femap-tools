' Group Mass Properties.bas
' -----------------------------------------------------------------------------
' Per-group mass, CG and inertia for a set of selected groups, written to one
' flat Excel table with a totals row. Read-only on the model.
'
' Pick the groups, pick the coordinate system, and every group is measured with
' feMeasureMeshMassProp. Overlapping, empty and zero-mass groups are flagged.
'
' *** THE INERTIA ARRAY PACKING IS NOT WHAT IT LOOKS LIKE ***
' feMeasureMeshMassProp returns inertia[0..5] packed LOWER-TRIANGULAR:
'
'   0 = I11 (Ixx)    1 = I21 (Ixy)    2 = I22 (Iyy)
'   3 = I31 (Izx)    4 = I32 (Iyz)    5 = I33 (Izz)
'
' so reading Ixx,Iyy,Izz,Ixy,Iyz,Izx means indices 0,2,5,1,4,3. That looks like
' a typo and is not. Do not "correct" it.
'
' Two arrays come back: "inertia" is about the ORIGIN of the chosen coordinate
' system, "inertiaCG" is about that group's OWN centre of gravity.
'
' WHAT IS NOT SUMMABLE
' Per-group "inertiaCG" values are each about a DIFFERENT point, so summing them
' is meaningless. The totals row sums the about-ORIGIN arrays instead (all about
' the same point, so that IS valid) and applies parallel-axis once at the end.
' This is why the about-origin values are still computed even though the sheet
' does not show them.
'
' *** THE SIGN CONVENTION IS UNDOCUMENTED, SO THE TOOL MEASURES IT ***
' The API guide never says whether Ixy is a PRODUCT OF INERTIA (+integral xy dm)
' or an INERTIA TENSOR term (-integral xy dm). The parallel-axis theorem needs
' the opposite sign in each case, so a guess would produce a silently wrong
' totals row - the worst possible failure for a mass properties report.
'
' Both arrays come back from a single call, and they are related by exactly the
' parallel-axis shift we need to identify:
'
'   Ixy(origin) - Ixy(cg) = conv * M * cx * cy      conv = +1 products
'                                                   conv = -1 tensor
'
' so the tool divides one by the other on the group with the strongest signal,
' corroborates on the other two off-diagonal slots, and reports what it found.
' It is never assumed. See Section 6.
'
' The totals are then checked against Femap's own direct measurement of the
' union of the selected groups (Section 7), which validates the summing, the
' parallel-axis shift and the detected convention together.
'
' The totals row blanks its CG and inertia cells - rather than printing
' something wrong - whenever the selected groups overlap, any group reported
' negative mass or volume, or the convention could not be established.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, g As Long, k As Long

    ' ============================================================
    ' Section 1: Pick the groups
    ' ============================================================
    Dim grSet As femap.Set
    Set grSet = App.feSet
    rc = grSet.SelectMultiIDV2(FT_GROUP, 1, "Select group(s) for mass properties")
    If rc = FE_CANCEL Or grSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    ' Group IDs are pulled into an array before any measuring starts. The scan
    ' calls feMeasureMeshMassProp and several Set operations, and leaving the
    ' Set cursor live across those invites it moving underneath us.
    Dim nG As Long
    nG = grSet.Count
    Dim gID() As Long, gTitle() As String
    ReDim gID(nG - 1)
    ReDim gTitle(nG - 1)

    Dim gp As femap.Group
    Set gp = App.feGroup

    Dim gv As Long
    grSet.Reset                                 ' the docs are explicit: Reset before the first Next
    gv = grSet.Next
    For i = 0 To nG - 1
        gID(i) = gv
        gTitle(i) = ""
        If gp.Get(gv) = FE_OK Then gTitle(i) = gp.title
        gv = grSet.Next
    Next i

    ' ============================================================
    ' Section 2: Pick the coordinate system
    '
    ' The dropdown only ever offers IDs read back from THIS model, so a
    ' coordinate system that does not exist cannot be chosen - which matters
    ' because the API guide never says what feMeasureMeshMassProp does with
    ' one.
    ' ============================================================
    Dim csEnum As Object
    Set csEnum = App.feCSys
    Dim nCS As Long
    nCS = 0
    csEnum.Reset
    Do While csEnum.Next()
        nCS = nCS + 1
    Loop

    Dim csIDs() As Long, csNames() As String
    ReDim csIDs(nCS)
    ReDim csNames(nCS)
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

    Begin Dialog CsysDlg 340, 88, "Group Mass Properties"
        Text        12, 18, 108, 12, "Coordinate system:"
        DropListBox 124, 16, 204, 180, csNames(), .csPick
        OKButton     84, 52, 80, 20
        CancelButton 184, 52, 80, 20
    End Dialog

    Dim cdlg As CsysDlg
    cdlg.csPick = 0
    If Dialog(cdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim csysID As Long
    Dim csysName As String
    csysID = csIDs(cdlg.csPick)
    csysName = csNames(cdlg.csPick)

    ' ============================================================
    ' Section 3: Measure each group, and watch for overlap
    '
    ' Overlap matters more than it looks. If two selected groups share elements
    ' the mass is double counted, which makes the totals row's combined CG and
    ' inertia meaningless - not merely imprecise. It is detected here and used
    ' in Section 7 to blank those cells rather than print a plausible wrong
    ' number.
    ' ============================================================
    Dim eset As femap.Set, seenSet As femap.Set, interSet As femap.Set
    Set eset = App.feSet
    Set seenSet = App.feSet
    Set interSet = App.feSet

    Dim gElems() As Long
    Dim gMassT() As Double, gMassS() As Double, gMassN() As Double
    Dim gCGx() As Double, gCGy() As Double, gCGz() As Double
    Dim gIcg() As Double, gIo() As Double
    Dim gFlag() As String
    ReDim gElems(nG - 1)
    ReDim gMassT(nG - 1)
    ReDim gMassS(nG - 1)
    ReDim gMassN(nG - 1)
    ReDim gCGx(nG - 1)
    ReDim gCGy(nG - 1)
    ReDim gCGz(nG - 1)
    ReDim gIcg(nG - 1, 5)
    ReDim gIo(nG - 1, 5)
    ReDim gFlag(nG - 1)

    Dim mlen As Double, marea As Double, mvol As Double
    Dim structMass As Double, nonstructMass As Double, totalMass As Double
    Dim structCG As Variant, nonstructCG As Variant, totalCG As Variant
    Dim inertia As Variant, inertiaCG As Variant

    Dim nOverlap As Long, nEmpty As Long, nZero As Long, nNeg As Long
    nOverlap = 0 : nEmpty = 0 : nZero = 0 : nNeg = 0
    Dim overlapNames As String
    overlapNames = ""

    App.feAppStatusShow(True, nG)

    For g = 0 To nG - 1
        gFlag(g) = ""

        eset.Clear
        rc = eset.AddGroup(FT_ELEM, gID(g))
        gElems(g) = eset.Count

        If gElems(g) = 0 Then
            gFlag(g) = "EMPTY"
            nEmpty = nEmpty + 1
        Else
            ' --- overlap against everything seen so far ---
            interSet.Clear
            rc = interSet.AddCommon(eset.ID, seenSet.ID)
            If interSet.Count > 0 Then
                gFlag(g) = "OVERLAP"
                nOverlap = nOverlap + 1
                If Len(overlapNames) > 0 Then overlapNames = overlapNames + ", "
                overlapNames = overlapNames + gTitle(g)
            End If
            rc = seenSet.AddSet(eset.ID)

            rc = App.feMeasureMeshMassProp(eset.ID, csysID, False, False, _
                mlen, marea, mvol, structMass, nonstructMass, totalMass, _
                structCG, nonstructCG, totalCG, inertia, inertiaCG)

            If rc = FE_NEGATIVE_MASS_VOLUME Then
                ' Documented as "returned values may be less than the total
                ' absolute mass or volume" - the numbers are suspect, not absent.
                If Len(gFlag(g)) > 0 Then gFlag(g) = gFlag(g) + " / "
                gFlag(g) = gFlag(g) + "NEG MASS-VOL"
                nNeg = nNeg + 1
            ElseIf rc <> FE_OK Then
                If Len(gFlag(g)) > 0 Then gFlag(g) = gFlag(g) + " / "
                gFlag(g) = gFlag(g) + "MEASURE FAILED"
            End If

            If rc = FE_OK Or rc = FE_NEGATIVE_MASS_VOLUME Then
                gMassT(g) = totalMass
                gMassS(g) = structMass
                gMassN(g) = nonstructMass
                gCGx(g) = totalCG(0)
                gCGy(g) = totalCG(1)
                gCGz(g) = totalCG(2)
                For k = 0 To 5
                    gIcg(g, k) = inertiaCG(k)
                    gIo(g, k) = inertia(k)
                Next k

                If totalMass = 0 Then
                    If Len(gFlag(g)) > 0 Then gFlag(g) = gFlag(g) + " / "
                    gFlag(g) = gFlag(g) + "ZERO MASS"
                    nZero = nZero + 1
                End If
            End If
        End If

        App.feAppStatusUpdate(g + 1)
        App.feAppStatusRedraw()
    Next g

    App.feAppStatusShow(False, 0)

    ' ============================================================
    ' Section 4: Coverage - how much of the model was not looked at
    ' ============================================================
    Dim allSet As femap.Set
    Set allSet = App.feSet
    rc = allSet.AddAll(FT_ELEM)
    Dim nModelElems As Long, nCovered As Long
    nModelElems = allSet.Count
    nCovered = seenSet.Count

    ' ============================================================
    ' Section 5: Totals
    ' ============================================================
    Dim sumMassT As Double, sumMassS As Double, sumMassN As Double
    Dim sumMx As Double, sumMy As Double, sumMz As Double
    Dim sumIo(5) As Double
    Dim totElems As Long
    sumMassT = 0 : sumMassS = 0 : sumMassN = 0
    sumMx = 0 : sumMy = 0 : sumMz = 0
    totElems = 0
    For k = 0 To 5
        sumIo(k) = 0
    Next k

    For g = 0 To nG - 1
        sumMassT = sumMassT + gMassT(g)
        sumMassS = sumMassS + gMassS(g)
        sumMassN = sumMassN + gMassN(g)
        totElems = totElems + gElems(g)
        sumMx = sumMx + gMassT(g) * gCGx(g)
        sumMy = sumMy + gMassT(g) * gCGy(g)
        sumMz = sumMz + gMassT(g) * gCGz(g)
        For k = 0 To 5
            sumIo(k) = sumIo(k) + gIo(g, k)
        Next k
    Next g

    Dim cgX As Double, cgY As Double, cgZ As Double
    Dim cgValid As Boolean
    cgValid = (sumMassT <> 0 And nOverlap = 0 And nNeg = 0)
    cgX = 0 : cgY = 0 : cgZ = 0
    If sumMassT <> 0 Then
        cgX = sumMx / sumMassT
        cgY = sumMy / sumMassT
        cgZ = sumMz / sumMassT
    End If

    ' ============================================================
    ' Section 6: Work out the inertia sign convention
    '
    ' Ixy(origin) - Ixy(cg) = conv * M * cx * cy, so dividing one by the other
    ' recovers conv. Done on the group with the strongest signal: a group whose
    ' CG sits near a coordinate plane makes M*cx*cy tiny and proves nothing.
    '
    ' Before trusting that, a DIAGONAL term is checked. Ixx(origin) - Ixx(cg)
    ' must equal M*(cy^2+cz^2) under BOTH conventions, so if that identity fails
    ' the premise itself is wrong - the arrays are not what the guide says they
    ' are - and no convention should be inferred at all.
    ' ============================================================
    Dim convSign As Double
    Dim convName As String
    Dim convOK As Boolean
    convSign = 0
    convName = "not determined"
    convOK = False

    Dim best As Long, bestScore As Double, sc As Double
    best = -1
    bestScore = 0
    For g = 0 To nG - 1
        If gMassT(g) <> 0 And gElems(g) > 0 Then
            sc = Abs(gMassT(g) * gCGx(g) * gCGy(g)) _
               + Abs(gMassT(g) * gCGy(g) * gCGz(g)) _
               + Abs(gMassT(g) * gCGz(g) * gCGx(g))
            If sc > bestScore Then
                bestScore = sc
                best = g
            End If
        End If
    Next g

    Dim diagPred As Double, diagAct As Double, diagRef As Double
    Dim votePos As Long, voteNeg As Long
    votePos = 0 : voteNeg = 0

    If best >= 0 And bestScore > 0 Then
        ' --- validation gate: the diagonal identity must hold ---
        diagPred = gMassT(best) * (gCGy(best) * gCGy(best) + gCGz(best) * gCGz(best))
        diagAct = gIo(best, 0) - gIcg(best, 0)
        diagRef = Abs(gIo(best, 0)) + Abs(gIcg(best, 0)) + Abs(diagPred)

        If diagRef > 0 And Abs(diagAct - diagPred) <= 0.001 * diagRef Then
            ' --- three independent votes, one per off-diagonal slot ---
            VoteConv gIo(best, 1) - gIcg(best, 1), gMassT(best) * gCGx(best) * gCGy(best), votePos, voteNeg
            VoteConv gIo(best, 4) - gIcg(best, 4), gMassT(best) * gCGy(best) * gCGz(best), votePos, voteNeg
            VoteConv gIo(best, 3) - gIcg(best, 3), gMassT(best) * gCGz(best) * gCGx(best), votePos, voteNeg

            If votePos > 0 And voteNeg = 0 Then
                convSign = 1
                convName = "products of inertia (+ integral xy dm)"
                convOK = True
            ElseIf voteNeg > 0 And votePos = 0 Then
                convSign = -1
                convName = "inertia tensor (- integral xy dm)"
                convOK = True
            Else
                convName = "AMBIGUOUS - off-diagonal slots disagreed"
            End If
        Else
            convName = "UNVERIFIABLE - parallel-axis identity did not hold"
        End If
    Else
        convName = "not determined - no group has an off-axis CG"
    End If

    ' --- combined inertia about the combined CG ---
    Dim tIcg(5) As Double
    Dim inertiaValid As Boolean
    inertiaValid = (cgValid And convOK)
    For k = 0 To 5
        tIcg(k) = 0
    Next k
    If inertiaValid Then
        tIcg(0) = sumIo(0) - sumMassT * (cgY * cgY + cgZ * cgZ)          ' Ixx
        tIcg(2) = sumIo(2) - sumMassT * (cgZ * cgZ + cgX * cgX)          ' Iyy
        tIcg(5) = sumIo(5) - sumMassT * (cgX * cgX + cgY * cgY)          ' Izz
        tIcg(1) = sumIo(1) - convSign * sumMassT * cgX * cgY             ' Ixy
        tIcg(4) = sumIo(4) - convSign * sumMassT * cgY * cgZ             ' Iyz
        tIcg(3) = sumIo(3) - convSign * sumMassT * cgZ * cgX             ' Izx
    End If

    ' ============================================================
    ' Section 7: Check the totals against Femap's own measurement
    '
    ' seenSet is the union of every selected group, so - provided nothing
    ' overlaps - it is EXACTLY the aggregate body the totals row describes.
    ' Measuring it directly gives Femap's own answer for the combined mass, the
    ' combined CG, and the inertia about that combined CG, computed internally
    ' with no parallel-axis step and no sign assumption from us.
    '
    ' That makes this an end-to-end check of Sections 5 and 6 together,
    ' INCLUDING the convention vote: if the sign were wrong, the three
    ' off-diagonal terms would disagree by 2 * M * Rx * Ry - a large, obvious
    ' number, not a rounding artefact.
    '
    ' It costs one extra API call and does not depend on the groups covering the
    ' whole model - only on them not overlapping each other.
    ' ============================================================
    Dim chkDone As Boolean, chkPass As Boolean
    Dim chkWorst As Double
    Dim chkNote As String
    chkDone = False
    chkPass = False
    chkWorst = 0
    chkNote = "not run"

    If nOverlap = 0 And nNeg = 0 And seenSet.Count > 0 And sumMassT <> 0 Then
        Dim uMass As Double, uS As Double, uN As Double
        Dim uCG As Variant, uCGs As Variant, uCGn As Variant
        Dim uIo As Variant, uIcg As Variant
        Dim uLen As Double, uArea As Double, uVol As Double

        rc = App.feMeasureMeshMassProp(seenSet.ID, csysID, False, False, _
            uLen, uArea, uVol, uS, uN, uMass, _
            uCGs, uCGn, uCG, uIo, uIcg)

        If rc = FE_OK Then
            chkDone = True
            chkWorst = RelDiff(sumMassT, uMass)
            chkWorst = MaxOf(chkWorst, RelDiff(cgX, uCG(0)))
            chkWorst = MaxOf(chkWorst, RelDiff(cgY, uCG(1)))
            chkWorst = MaxOf(chkWorst, RelDiff(cgZ, uCG(2)))
            If inertiaValid Then
                For k = 0 To 5
                    chkWorst = MaxOf(chkWorst, RelDiff(tIcg(k), uIcg(k)))
                Next k
            End If
            chkPass = (chkWorst <= 0.0001)
            If chkPass Then
                chkNote = "PASS - agrees with Femap's direct measurement of the same elements"
            Else
                chkNote = "FAIL - disagrees with Femap's direct measurement"
            End If
        Else
            chkNote = "could not measure the union"
        End If
    ElseIf nOverlap > 0 Then
        chkNote = "not applicable - groups overlap"
    End If

    ' ============================================================
    ' Section 8: Excel (late bound) + sheets
    ' ============================================================
    Dim appExcel As Object
    On Error Resume Next
    Set appExcel = CreateObject("Excel.Application")
    On Error GoTo 0
    If appExcel Is Nothing Then
        App.feAppMessage(FCM_ERROR, "Could not start Excel - exiting")
        Exit Sub
    End If
    Dim wbk As Object
    Set wbk = appExcel.Workbooks.Add
    Dim wsR As Object
    Set wsR = wbk.Worksheets(1)
    wsR.Name = "README"
    Dim wsD As Object
    Set wsD = wbk.Worksheets.Add
    wsD.Name = "Mass by Group"

    ' Column A and row 1 are left blank as a margin (cleaner screenshots).
    ' Header on row 2, data from row 3. One header row only - merged header
    ' cells would break sorting and filtering.
    Dim hdrRow As Long, firstRow As Long
    hdrRow = 2
    firstRow = 3

    ' Group Name and Flags are forced to Text BEFORE anything is written.
    ' Excel type-infers on write, so a group titled "3-4 Bracket" becomes a date
    ' and one titled "1E5" becomes 100000. Silent corruption of the one column
    ' the reader uses to identify the row - and unrecoverable, because the
    ' original string is gone by the time anyone looks.
    wsD.Columns(3).NumberFormat = "@"
    wsD.Columns(17).NumberFormat = "@"

    wsD.Cells(hdrRow, 2).Value  = "Group ID"
    wsD.Cells(hdrRow, 3).Value  = "Group Name"
    wsD.Cells(hdrRow, 4).Value  = "Elements"
    wsD.Cells(hdrRow, 5).Value  = "Mass (total)"
    wsD.Cells(hdrRow, 6).Value  = "Mass (structural)"
    wsD.Cells(hdrRow, 7).Value  = "Mass (non-struct)"
    wsD.Cells(hdrRow, 8).Value  = "CG X"
    wsD.Cells(hdrRow, 9).Value  = "CG Y"
    wsD.Cells(hdrRow, 10).Value = "CG Z"
    wsD.Cells(hdrRow, 11).Value = "Ixx (cg)"
    wsD.Cells(hdrRow, 12).Value = "Iyy (cg)"
    wsD.Cells(hdrRow, 13).Value = "Izz (cg)"
    wsD.Cells(hdrRow, 14).Value = "Ixy (cg)"
    wsD.Cells(hdrRow, 15).Value = "Iyz (cg)"
    wsD.Cells(hdrRow, 16).Value = "Izx (cg)"
    wsD.Cells(hdrRow, 17).Value = "Flags"

    Dim r As Long
    For g = 0 To nG - 1
        r = firstRow + g
        wsD.Cells(r, 2).Value  = gID(g)
        wsD.Cells(r, 3).Value  = gTitle(g)
        wsD.Cells(r, 4).Value  = gElems(g)
        If gElems(g) > 0 Then
            wsD.Cells(r, 5).Value  = gMassT(g)
            wsD.Cells(r, 6).Value  = gMassS(g)
            wsD.Cells(r, 7).Value  = gMassN(g)
            wsD.Cells(r, 8).Value  = gCGx(g)
            wsD.Cells(r, 9).Value  = gCGy(g)
            wsD.Cells(r, 10).Value = gCGz(g)
            ' 0,2,5,1,4,3 - the lower-triangular packing. See the header block.
            wsD.Cells(r, 11).Value = gIcg(g, 0)
            wsD.Cells(r, 12).Value = gIcg(g, 2)
            wsD.Cells(r, 13).Value = gIcg(g, 5)
            wsD.Cells(r, 14).Value = gIcg(g, 1)
            wsD.Cells(r, 15).Value = gIcg(g, 4)
            wsD.Cells(r, 16).Value = gIcg(g, 3)
        End If
        wsD.Cells(r, 17).Value = gFlag(g)
    Next g

    ' --- totals row, two blank rows below the data ---
    Dim lastRow As Long, totRow As Long
    lastRow = firstRow + nG - 1
    totRow = lastRow + 2

    wsD.Cells(totRow, 3).Value = "TOTAL (" + Trim$(Str$(nG)) + " groups)"
    wsD.Cells(totRow, 4).Value = totElems
    wsD.Cells(totRow, 5).Value = sumMassT
    wsD.Cells(totRow, 6).Value = sumMassS
    wsD.Cells(totRow, 7).Value = sumMassN

    ' The mass sums are always valid - a sum of masses is a sum of masses even
    ' when groups overlap. The CG and inertia are not, so they are left BLANK
    ' rather than printed wrong, with the reason in the Flags cell.
    Dim totNote As String
    totNote = ""
    If cgValid Then
        wsD.Cells(totRow, 8).Value  = cgX
        wsD.Cells(totRow, 9).Value  = cgY
        wsD.Cells(totRow, 10).Value = cgZ
    Else
        If nOverlap > 0 Then
            totNote = "CG/inertia omitted: groups overlap, mass double counted"
        ElseIf nNeg > 0 Then
            totNote = "CG/inertia omitted: a group reported negative mass or volume"
        Else
            totNote = "CG/inertia omitted: total mass is zero"
        End If
    End If

    If inertiaValid Then
        wsD.Cells(totRow, 11).Value = tIcg(0)
        wsD.Cells(totRow, 12).Value = tIcg(2)
        wsD.Cells(totRow, 13).Value = tIcg(5)
        wsD.Cells(totRow, 14).Value = tIcg(1)
        wsD.Cells(totRow, 15).Value = tIcg(4)
        wsD.Cells(totRow, 16).Value = tIcg(3)
    ElseIf cgValid Then
        totNote = "Inertia omitted: sign convention " + convName
    End If
    wsD.Cells(totRow, 17).Value = totNote

    ' ============================================================
    ' Section 9: Formatting
    ' ============================================================
    wsD.Cells.Font.Name = "Calibri"
    wsD.Cells.Font.Size = 10

    ' number formats, per column class. Mass and inertia get scientific
    ' notation: across a real model these span many orders of magnitude and a
    ' fixed decimal format either loses the small ones or is unreadable.
    wsD.Range(wsD.Cells(firstRow, 2), wsD.Cells(totRow, 2)).NumberFormat = "0"
    wsD.Range(wsD.Cells(firstRow, 4), wsD.Cells(totRow, 4)).NumberFormat = "#,##0"
    wsD.Range(wsD.Cells(firstRow, 5), wsD.Cells(totRow, 7)).NumberFormat = "0.0000E+00"
    wsD.Range(wsD.Cells(firstRow, 8), wsD.Cells(totRow, 10)).NumberFormat = "0.0000"
    wsD.Range(wsD.Cells(firstRow, 11), wsD.Cells(totRow, 16)).NumberFormat = "0.0000E+00"

    ' header bar
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 17)).Interior.Color = RGB(46, 84, 141)
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 17)).Font.Color = RGB(255, 255, 255)
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 17)).Font.Bold = True
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 17)).VerticalAlignment = -4107    ' xlBottom
    wsD.Rows(hdrRow).RowHeight = 30

    ' totals row
    wsD.Range(wsD.Cells(totRow, 2), wsD.Cells(totRow, 17)).Font.Bold = True
    wsD.Range(wsD.Cells(totRow, 2), wsD.Cells(totRow, 17)).Interior.Color = RGB(221, 230, 243)
    wsD.Range(wsD.Cells(totRow, 2), wsD.Cells(totRow, 17)).Borders.LineStyle = 1

    ' borders + alignment on the data block
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 17)).Borders.LineStyle = 1
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(totRow, 17)).HorizontalAlignment = -4108   ' xlCenter
    wsD.Range(wsD.Cells(hdrRow, 3), wsD.Cells(totRow, 3)).HorizontalAlignment = -4131    ' xlLeft
    wsD.Range(wsD.Cells(hdrRow, 17), wsD.Cells(totRow, 17)).HorizontalAlignment = -4131  ' xlLeft

    ' flagged rows tinted amber so a problem group is visible without reading
    For g = 0 To nG - 1
        If Len(gFlag(g)) > 0 Then
            wsD.Range(wsD.Cells(firstRow + g, 2), wsD.Cells(firstRow + g, 17)).Interior.Color = RGB(255, 235, 200)
        End If
    Next g

    ' column widths
    wsD.Columns(1).ColumnWidth = 3
    wsD.Columns(2).ColumnWidth = 9
    wsD.Columns(3).ColumnWidth = 28
    wsD.Columns(4).ColumnWidth = 9
    For i = 5 To 16
        wsD.Columns(i).ColumnWidth = 13
    Next i
    wsD.Columns(17).ColumnWidth = 34

    ' AutoFilter + frozen panes: the whole point of a flat table. Fenced
    ' individually - a COM refusal here should not lose the report.
    On Error Resume Next
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 17)).AutoFilter
    wsD.Activate
    appExcel.ActiveWindow.FreezePanes = False
    wsD.Range("D3").Select
    appExcel.ActiveWindow.FreezePanes = True
    appExcel.ActiveWindow.DisplayGridlines = False
    On Error GoTo 0

    ' ============================================================
    ' Section 10: README sheet
    ' ============================================================
    wsR.Cells(1, 1).Value = "Group Mass Properties"
    wsR.Cells(3, 1).Value = "Model:"
    wsR.Cells(3, 2).Value = App.ModelName
    wsR.Cells(4, 1).Value = "User:"
    wsR.Cells(4, 2).Value = appExcel.UserName
    wsR.Cells(5, 1).Value = "Date:"
    wsR.Cells(5, 2).Value = Now
    wsR.Cells(6, 1).Value = "Coordinate system:"
    wsR.Cells(6, 2).Value = csysName
    wsR.Cells(7, 1).Value = "Groups reported:"
    wsR.Cells(7, 2).Value = nG

    wsR.Cells(9, 1).Value = "Inertia convention:"
    wsR.Cells(9, 2).Value = convName
    wsR.Cells(10, 2).Value = "Detected at runtime, not assumed - the API guide does not state it. " _
        + "The parallel-axis sign used for the totals row depends on this."

    wsR.Cells(12, 1).Value = "Inertia columns:"
    wsR.Cells(12, 2).Value = "Per group, about that group's OWN CG, in the coordinate system above."
    wsR.Cells(13, 2).Value = "Totals row: about the COMBINED CG. Computed by summing the about-origin " _
        + "inertias (all about one point, so summable) then shifting once by parallel-axis. " _
        + "Per-group about-CG values are each about a different point and must never be summed."

    wsR.Cells(15, 1).Value = "Totals row:"
    If cgValid And inertiaValid Then
        wsR.Cells(15, 2).Value = "Valid - no group overlap, no negative mass/volume, convention established."
    Else
        wsR.Cells(15, 2).Value = "CG and/or inertia omitted. " + totNote
    End If

    wsR.Cells(16, 1).Value = "Totals cross-check:"
    wsR.Cells(16, 2).Value = chkNote
    If chkDone Then
        wsR.Cells(16, 2).Value = chkNote + "   (worst relative difference " _
            + Format$(chkWorst, "0.00E+00") + ")"
    End If

    wsR.Cells(17, 1).Value = "Coverage:"
    wsR.Cells(17, 2).Value = Trim$(Str$(nCovered)) + " of " + Trim$(Str$(nModelElems)) _
        + " model elements are in the selected groups"

    wsR.Cells(19, 1).Value = "Flags:"
    wsR.Cells(19, 2).Value = "OVERLAP = shares elements with an earlier group (mass double counted).  " _
        + "EMPTY = no elements.  ZERO MASS = elements but no mass (geometry only, or no density).  " _
        + "NEG MASS-VOL = Femap reported negative mass or volume; totals may understate."

    wsR.Rows("1:1").Font.Bold = True
    wsR.Columns(1).ColumnWidth = 20
    wsR.Columns(2).ColumnWidth = 110
    wsR.Range(wsR.Cells(1, 2), wsR.Cells(19, 2)).WrapText = True

    appExcel.Visible = True

    ' ============================================================
    ' Section 11: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Group Mass Properties - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL,    "  Groups reported:       " + Trim$(Str$(nG)))
    App.feAppMessage(FCM_NORMAL,    "  Coordinate system:     " + csysName)
    App.feAppMessage(FCM_NORMAL,    "  Elements measured:     " + Trim$(Str$(nCovered)) _
        + " of " + Trim$(Str$(nModelElems)) + " in the model")
    App.feAppMessage(FCM_NORMAL,    "  Total mass:            " + Format$(sumMassT, "0.0000E+00"))
    If cgValid Then
        App.feAppMessage(FCM_NORMAL, "  Combined CG:           " _
            + Format$(cgX, "0.0000") + ", " + Format$(cgY, "0.0000") + ", " + Format$(cgZ, "0.0000"))
    Else
        App.feAppMessage(FCM_WARNING, "  Combined CG:           omitted - " + totNote)
    End If
    App.feAppMessage(FCM_NORMAL,    "  Inertia convention:    " + convName)
    If Not convOK Then
        App.feAppMessage(FCM_WARNING, "  Totals inertia omitted - the convention could not be established.")
    End If
    If chkDone Then
        If chkPass Then
            App.feAppMessage(FCM_NORMAL, "  Totals cross-check:    PASS   (worst rel. diff " _
                + Format$(chkWorst, "0.00E+00") + " vs Femap's own measurement)")
        Else
            App.feAppMessage(FCM_ERROR,  "  Totals cross-check:    FAIL   (worst rel. diff " _
                + Format$(chkWorst, "0.00E+00") + " vs Femap's own measurement)")
            App.feAppMessage(FCM_ERROR,  "  Do not trust the totals row - report this.")
        End If
    Else
        App.feAppMessage(FCM_WARNING, "  Totals cross-check:    " + chkNote)
    End If
    If nOverlap > 0 Then
        App.feAppMessage(FCM_ERROR,  "  OVERLAPPING GROUPS:    " + Trim$(Str$(nOverlap)) _
            + "   (" + overlapNames + ")")
        App.feAppMessage(FCM_ERROR,  "  Mass in those groups is counted more than once.")
    End If
    If nEmpty > 0 Then App.feAppMessage(FCM_WARNING, "  Empty groups:          " + Trim$(Str$(nEmpty)))
    If nZero > 0 Then App.feAppMessage(FCM_WARNING,  "  Zero-mass groups:      " + Trim$(Str$(nZero)))
    If nNeg > 0 Then App.feAppMessage(FCM_ERROR,     "  Negative mass/volume:  " + Trim$(Str$(nNeg)))
    If nModelElems > nCovered Then
        App.feAppMessage(FCM_NORMAL, "  Not in any group:      " + Trim$(Str$(nModelElems - nCovered)) + " elements")
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

End Sub

' -----------------------------------------------------------------------------
' One vote on the inertia sign convention, from one off-diagonal slot.
'
' actual = I(origin) - I(cg) for that slot; pred = M * ca * cb for the matching
' CG components. Their ratio is +1 under the products-of-inertia convention and
' -1 under the inertia-tensor convention.
'
' Slots whose predicted shift is negligible next to the values themselves are
' abstentions, not votes - a group whose CG lies near a coordinate plane makes
' pred tiny and the ratio meaningless.
' -----------------------------------------------------------------------------
Sub VoteConv(actual As Double, pred As Double, votePos As Long, voteNeg As Long)

    Dim ratio As Double

    If pred = 0 Then Exit Sub
    If Abs(pred) < 0.000001 * Abs(actual) Then Exit Sub

    ratio = actual / pred
    If Abs(ratio - 1) <= 0.01 Then
        votePos = votePos + 1
    ElseIf Abs(ratio + 1) <= 0.01 Then
        voteNeg = voteNeg + 1
    End If

End Sub

' -----------------------------------------------------------------------------
' Relative difference between two values, scaled by their own magnitude.
'
' An absolute tolerance is useless here: inertia terms in a real model run from
' 1e-3 to 1e+6 in the same table, so any fixed epsilon is either meaningless on
' the large terms or unmeetable on the small ones. Scaling by the larger
' magnitude gives one threshold that works across the whole range.
'
' Two values that are both essentially zero agree - that is not a failure, and
' returning a huge ratio for 1e-18 vs 2e-18 would make the check cry wolf.
' -----------------------------------------------------------------------------
Function RelDiff(a As Double, b As Double) As Double

    Dim mag As Double

    mag = Abs(a)
    If Abs(b) > mag Then mag = Abs(b)

    If mag = 0 Then
        RelDiff = 0
    Else
        RelDiff = Abs(a - b) / mag
    End If

End Function

' -----------------------------------------------------------------------------
' Larger of two values. WinWrap has no Max.
' -----------------------------------------------------------------------------
Function MaxOf(a As Double, b As Double) As Double

    If a > b Then
        MaxOf = a
    Else
        MaxOf = b
    End If

End Function
