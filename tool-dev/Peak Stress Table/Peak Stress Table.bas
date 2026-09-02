' =============================================================================
' Peak Stress Table
' -----------------------------------------------------------------------------
' Peak stress per bucket (group / property / material / element type), one
' column per output set, written to Excel. Read-only on the model.
'
' Three measures per bucket: max von Mises, max principal (peak tension) and
' min principal (peak compression). Each is enveloped over the plate TOP fibre,
' the plate BOTTOM fibre and the solid centroid, so a bucket holding both plates
' and solids reports one governing number.
'
' -----------------------------------------------------------------------------
' THE TWO MEASURED FACTS THIS TOOL IS BUILT ON
' -----------------------------------------------------------------------------
' Both came out of Check Stress Vectors and List Output Vectors run against a
' real model. Neither is guessable, and getting either wrong produces a report
' that is wrong while looking right.
'
' 1. VPP_BOT IS 2. The API guide says 3, and the guide is wrong.
'    Plate(VPV_STRESS, VPT_VON_MISES, 3, 0) returns FE_FAIL. ply=2 returns 9033,
'    which Femap's own contour list titles "Plate Bot VonMises Stress" (top is
'    7033). The guide prints these constants in two-column tables whose right-
'    hand values are shifted a row - the same block claims VPL_2 = 3, which is
'    impossible. Do not "fix" the 2 back to a 3 on the strength of the document.
'
'    This one matters because bottom-surface plate stress usually GOVERNS in
'    bending, and FE_FAIL reads as "the solver never wrote it" rather than as a
'    bug, so the wrong constant silently drops the governing fibre.
'
' 2. COLUMNS ARE PADDED WITH EXACTLY 0.0 ON THE WRONG ELEMENT CLASS.
'    Populate returns one row per element that has ANY of the requested results,
'    not one row per element the vector applies to. In the measured model the
'    plate columns carried 187881 rows of exactly 0.0 - precisely the solid
'    count - and the solid columns carried 134771, precisely the plate count.
'
'    So every row is filtered by element class before it is allowed to move a
'    peak. Bucket membership alone is not enough. Without the filter an all-
'    solid bucket asked for a plate column reports a confident 0.0, and a
'    min-principal column reports 0.0 for any bucket whose real values are all
'    compressive - because 0.0 beats every negative number.
'
' A bucket with no qualifying rows is written BLANK, never 0. Zero is a stress
' value; blank is the absence of one, and the reader must be able to tell them
' apart.
' =============================================================================

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, k As Long

    ' ============================================================
    ' Section 1: What to bucket by
    ' ============================================================
    Dim dimNames(3) As String
    dimNames(0) = "Group"
    dimNames(1) = "Property"
    dimNames(2) = "Material"
    dimNames(3) = "Element type"

    Dim dimPick As Long
    dimPick = 0

    Begin Dialog PeakDlg 340, 96, "Peak Stress Table"
        Text        12, 14, 116, 12, "Summarise peaks by:"
        DropListBox 132, 12, 196, 120, dimNames(), .dimPick
        Text        12, 40, 316, 20, "Next you will pick the output sets, then the buckets themselves."
        OKButton     92, 68, 76, 20
        CancelButton 176, 68, 76, 20
    End Dialog
    Dim dlg As PeakDlg
    dlg.dimPick = 0
    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    dimPick = dlg.dimPick

    ' ============================================================
    ' Section 2: Output sets
    ' ============================================================
    Dim osSet As femap.Set
    Set osSet = App.feSet
    rc = osSet.SelectMultiIDV2(FT_OUT_CASE, 1, "Select the output sets to report")
    If rc = FE_CANCEL Or osSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim nS As Long
    nS = osSet.Count
    Dim setID() As Long
    Dim setName() As String
    ReDim setID(nS - 1)
    ReDim setName(nS - 1)

    Dim os As femap.OutputSet
    Set os = App.feOutputSet
    Dim oid As Long
    oid = osSet.First()
    For i = 0 To nS - 1
        setID(i) = oid
        rc = os.Get(oid)
        If rc = FE_OK Then
            setName(i) = Trim$(Str$(oid)) + ".." + os.title
        Else
            setName(i) = "Set " + Trim$(Str$(oid))
        End If
        oid = osSet.Next()
    Next i

    ' ============================================================
    ' Section 3: Element class maps
    ' ============================================================
    ' *** THE L IN FET_L_* MEANS LINEAR, NOT "ELEMENT TYPE" ***
    ' FET_L_SOLID is tet4/wedge6/brick8; FET_P_SOLID is tet10/wedge15/brick20.
    ' Listing only the L half silently drops every parabolic element - which in
    ' a real aerospace model is most of them.
    Dim plateSet As femap.Set
    Set plateSet = App.feSet
    plateSet.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_P_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_L_LAMINATE_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_P_LAMINATE_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_L_MEMBRANE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_P_MEMBRANE, FGD_ELEM_BYTYPE)

    Dim solidSet As femap.Set
    Set solidSet = App.feSet
    solidSet.AddRule(FET_L_SOLID, FGD_ELEM_BYTYPE)
    solidSet.AddRule(FET_P_SOLID, FGD_ELEM_BYTYPE)
    solidSet.AddRule(FET_L_LAMINATE_SOLID, FGD_ELEM_BYTYPE)
    solidSet.AddRule(FET_P_LAMINATE_SOLID, FGD_ELEM_BYTYPE)

    If plateSet.Count = 0 And solidSet.Count = 0 Then
        App.feAppMessage(FCM_ERROR, "No plate or solid elements - nothing to report.")
        Exit Sub
    End If

    ' Highest element ID in the model, so the lookup arrays can be sized. Read
    ' from the model rather than assumed: IDs are not dense and a big model can
    ' easily run into the millions with large gaps.
    Dim allSet As femap.Set
    Set allSet = App.feSet
    allSet.AddAll(FT_ELEM)
    Dim nAll As Long
    Dim allIDs As Variant
    rc = allSet.GetArray(nAll, allIDs)
    If rc <> FE_OK Or nAll = 0 Then
        App.feAppMessage(FCM_ERROR, "Could not read the element list - exiting.")
        Exit Sub
    End If
    Dim maxEID As Long
    maxEID = 0
    For k = LBound(allIDs) To UBound(allIDs)
        If allIDs(k) > maxEID Then maxEID = allIDs(k)
    Next k

    ' eCls(eID): 1 = plate/membrane, 2 = solid, 0 = neither.
    ' An array lookup, not plateSet.IsAdded() inside the row loop - IsAdded is a
    ' COM call, and the row loop runs (rows x 9 columns x output sets) times.
    Dim eCls() As Integer
    ReDim eCls(maxEID)

    Dim nP As Long
    Dim pIDs As Variant
    rc = plateSet.GetArray(nP, pIDs)
    If rc = FE_OK Then
        For k = LBound(pIDs) To UBound(pIDs)
            eCls(pIDs(k)) = 1
        Next k
    End If

    Dim nSo As Long
    Dim soIDs As Variant
    rc = solidSet.GetArray(nSo, soIDs)
    If rc = FE_OK Then
        For k = LBound(soIDs) To UBound(soIDs)
            eCls(soIDs(k)) = 2
        Next k
    End If

    ' ============================================================
    ' Section 4: Build the buckets
    ' ============================================================
    ' Every bucket dimension collapses to the same thing - a name plus an
    ' element set - so there is one code path below, not four.
    Dim MAXB As Long
    MAXB = 400
    Dim bName() As String
    Dim bElems() As Long
    ReDim bName(MAXB - 1)
    ReDim bElems(MAXB - 1)
    Dim nB As Long
    nB = 0

    ' bkt(eID) = bucket index + 1, 0 = in no selected bucket.
    Dim bkt() As Integer
    ReDim bkt(maxEID)

    Dim bs As femap.Set
    Dim pickSet As femap.Set
    Set pickSet = App.feSet
    Dim entID As Long
    Dim nInB As Long
    Dim bIDs As Variant
    Dim nOverlap As Long
    nOverlap = 0

    If dimPick = 3 Then
        ' ---- Element type: no picker, just the classes that carry stress ----
        Dim tName(4) As String
        Dim tLin(4) As Long
        Dim tPar(4) As Long
        tName(0) = "Plate"           : tLin(0) = FET_L_PLATE           : tPar(0) = FET_P_PLATE
        tName(1) = "Laminate Plate"  : tLin(1) = FET_L_LAMINATE_PLATE  : tPar(1) = FET_P_LAMINATE_PLATE
        tName(2) = "Membrane"        : tLin(2) = FET_L_MEMBRANE        : tPar(2) = FET_P_MEMBRANE
        tName(3) = "Solid"           : tLin(3) = FET_L_SOLID           : tPar(3) = FET_P_SOLID
        tName(4) = "Laminate Solid"  : tLin(4) = FET_L_LAMINATE_SOLID  : tPar(4) = FET_P_LAMINATE_SOLID

        For i = 0 To 4
            Set bs = App.feSet
            bs.AddRule(tLin(i), FGD_ELEM_BYTYPE)
            bs.AddRule(tPar(i), FGD_ELEM_BYTYPE)
            If bs.Count > 0 Then
                bName(nB) = tName(i)
                bElems(nB) = bs.Count
                rc = bs.GetArray(nInB, bIDs)
                If rc = FE_OK Then
                    For k = LBound(bIDs) To UBound(bIDs)
                        If bkt(bIDs(k)) > 0 Then nOverlap = nOverlap + 1
                        bkt(bIDs(k)) = nB + 1
                    Next k
                End If
                nB = nB + 1
            End If
        Next i
    Else
        ' ---- Group / Property / Material: pick them, then resolve each ----
        Dim entType As Long
        If dimPick = 0 Then
            entType = FT_GROUP
        ElseIf dimPick = 1 Then
            entType = FT_PROP
        Else
            entType = FT_MATL
        End If

        rc = pickSet.SelectMultiIDV2(entType, 1, "Select the " + dimNames(dimPick) + "s to report")
        If rc = FE_CANCEL Or pickSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
            Exit Sub
        End If

        Dim gp As femap.Group
        Set gp = App.feGroup
        Dim pr As femap.Prop
        Set pr = App.feProp
        Dim mt As femap.Matl
        Set mt = App.feMatl
        Dim gElemSet As femap.Set

        entID = pickSet.First()
        Do While entID > 0
            If nB >= MAXB Then
                App.feAppMessage(FCM_WARNING, "More than " + Trim$(Str$(MAXB)) + _
                    " buckets selected - the rest are ignored.")
                Exit Do
            End If

            Set bs = App.feSet
            bName(nB) = ""

            If dimPick = 0 Then
                rc = gp.Get(entID)
                If rc = FE_OK Then bName(nB) = gp.title
                ' Group.List(FGR_ELEM) - FGR_ELEM is 8. Returns Nothing, not an
                ' empty set, when the group holds no elements.
                Set gElemSet = gp.List(FGR_ELEM)
                If Not (gElemSet Is Nothing) Then
                    If gElemSet.Count > 0 Then
                        rc = gElemSet.GetArray(nInB, bIDs)
                        If rc = FE_OK Then bs.AddArray(nInB, bIDs)
                    End If
                End If
            ElseIf dimPick = 1 Then
                rc = pr.Get(entID)
                If rc = FE_OK Then bName(nB) = pr.title
                bs.AddRule(entID, FGD_ELEM_BYPROP)
            Else
                rc = mt.Get(entID)
                If rc = FE_OK Then bName(nB) = mt.title
                ' FGD_ELEM_BYMATL resolves the property indirection itself - no
                ' loop over properties needed to find a material's elements.
                bs.AddRule(entID, FGD_ELEM_BYMATL)
            End If

            If Len(Trim$(bName(nB))) = 0 Then
                bName(nB) = dimNames(dimPick) + " " + Trim$(Str$(entID))
            End If
            bName(nB) = Trim$(Str$(entID)) + ".." + bName(nB)

            bElems(nB) = bs.Count
            If bs.Count > 0 Then
                rc = bs.GetArray(nInB, bIDs)
                If rc = FE_OK Then
                    For k = LBound(bIDs) To UBound(bIDs)
                        If bkt(bIDs(k)) > 0 Then nOverlap = nOverlap + 1
                        bkt(bIDs(k)) = nB + 1
                    Next k
                End If
            End If
            nB = nB + 1
            entID = pickSet.Next()
        Loop
    End If

    If nB = 0 Then
        App.feAppMessage(FCM_ERROR, "No buckets to report - exiting.")
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: The nine vectors
    ' ============================================================
    ' measure: 0 = von Mises, 1 = max principal, 2 = min principal
    ' class:   1 = plate, 2 = solid
    ' Plies are integer literals. TOP = 0, BOT = 2 - see the header; the API
    ' guide's 3 returns FE_FAIL.
    Dim NVEC As Long
    NVEC = 9
    Dim vMeas(8) As Long
    Dim vClass(8) As Long
    Dim vLabel(8) As String

    vMeas(0) = 0 : vClass(0) = 1 : vLabel(0) = "Plate Top vonMises"
    vMeas(1) = 0 : vClass(1) = 1 : vLabel(1) = "Plate Bot vonMises"
    vMeas(2) = 0 : vClass(2) = 2 : vLabel(2) = "Solid vonMises"
    vMeas(3) = 1 : vClass(3) = 1 : vLabel(3) = "Plate Top MaxPrin"
    vMeas(4) = 1 : vClass(4) = 1 : vLabel(4) = "Plate Bot MaxPrin"
    vMeas(5) = 1 : vClass(5) = 2 : vLabel(5) = "Solid MaxPrin"
    vMeas(6) = 2 : vClass(6) = 1 : vLabel(6) = "Plate Top MinPrin"
    vMeas(7) = 2 : vClass(7) = 1 : vLabel(7) = "Plate Bot MinPrin"
    vMeas(8) = 2 : vClass(8) = 2 : vLabel(8) = "Solid MinPrin"

    Dim q As femap.ResultsIDQuery
    Set q = App.feResultsIDQuery

    ' ============================================================
    ' Section 6: Walk the output sets
    ' ============================================================
    ' pk*(bucket, set) hold the peaks; ok*(bucket, set) says whether any row
    ' ever qualified. A cell with ok = 0 is written blank, not 0.
    Dim pkVM() As Double, pkMX() As Double, pkMN() As Double
    Dim idVM() As Long,   idMX() As Long,   idMN() As Long
    Dim okVM() As Integer, okMX() As Integer, okMN() As Integer
    ReDim pkVM(nB - 1, nS - 1)
    ReDim pkMX(nB - 1, nS - 1)
    ReDim pkMN(nB - 1, nS - 1)
    ReDim idVM(nB - 1, nS - 1)
    ReDim idMX(nB - 1, nS - 1)
    ReDim idMN(nB - 1, nS - 1)
    ReDim okVM(nB - 1, nS - 1)
    ReDim okMX(nB - 1, nS - 1)
    ReDim okMN(nB - 1, nS - 1)

    Dim rbo As femap.Results
    Set rbo = App.feResults

    Dim vecID(8) As Long
    Dim colOf(8) As Long
    Dim nAdded As Long
    Dim vCols As Variant
    Dim vIDs As Variant
    Dim vVals As Variant
    Dim eID As Long
    Dim dVal As Double
    Dim iB As Long, iSet As Long, iC As Long
    Dim nMissing As Long
    Dim missNote As String
    nMissing = 0
    missNote = ""

    App.feAppMessage(FCM_NORMAL, "Peak Stress Table - reading " + Trim$(Str$(nS)) + _
        " output set(s) over " + Trim$(Str$(nB)) + " bucket(s)...")

    For iSet = 0 To nS - 1
        App.feAppMessage(FCM_NORMAL, "  " + setName(iSet))

        rbo.Clear
        For iC = 0 To NVEC - 1
            colOf(iC) = -1
            If vClass(iC) = 1 Then
                If vMeas(iC) = 0 Then
                    vecID(iC) = q.Plate(VPV_STRESS, VPT_VON_MISES, PlyOf(iC), VPL_CENTROID)
                ElseIf vMeas(iC) = 1 Then
                    vecID(iC) = q.Plate(VPV_STRESS, VPT_MAX_PRIN, PlyOf(iC), VPL_CENTROID)
                Else
                    vecID(iC) = q.Plate(VPV_STRESS, VPT_MIN_PRIN, PlyOf(iC), VPL_CENTROID)
                End If
            Else
                If vMeas(iC) = 0 Then
                    vecID(iC) = q.Solid(VSV_STRESS, VST_VON_MISES, 0)
                ElseIf vMeas(iC) = 1 Then
                    vecID(iC) = q.Solid(VSV_STRESS, VST_MAX_PRIN, 0)
                Else
                    vecID(iC) = q.Solid(VSV_STRESS, VST_MIN_PRIN, 0)
                End If
            End If

            If vecID(iC) > 0 Then
                rc = rbo.AddColumnV2(setID(iSet), vecID(iC), False, nAdded, vCols)
                If rc = FE_OK And nAdded > 0 Then
                    colOf(iC) = vCols(0)
                End If
            End If

            If colOf(iC) < 0 Then
                nMissing = nMissing + 1
                If InStr(missNote, vLabel(iC)) = 0 Then
                    If Len(missNote) > 0 Then missNote = missNote + ", "
                    missNote = missNote + vLabel(iC)
                End If
            End If
        Next iC

        rc = rbo.Populate
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "    Populate failed (rc=" + Trim$(Str$(rc)) + _
                ") - this set is left blank.")
        Else
            For iC = 0 To NVEC - 1
                If colOf(iC) >= 0 Then
                    rc = rbo.GetColumn(colOf(iC), vIDs, vVals)
                    If rc = FE_OK Then
                        For k = LBound(vVals) To UBound(vVals)
                            eID = vIDs(k)
                            iB = bkt(eID) - 1
                            ' Bucket first - it is the cheapest reject, and in a
                            ' real report most of the model is outside it.
                            If iB >= 0 Then
                                ' *** The class filter. Without it the 0.0 padding
                                ' on the other element class becomes a reported
                                ' stress. See the header. ***
                                If eCls(eID) = vClass(iC) Then
                                    dVal = vVals(k)
                                    If vMeas(iC) = 0 Then
                                        If okVM(iB, iSet) = 0 Or dVal > pkVM(iB, iSet) Then
                                            pkVM(iB, iSet) = dVal
                                            idVM(iB, iSet) = eID
                                            okVM(iB, iSet) = 1
                                        End If
                                    ElseIf vMeas(iC) = 1 Then
                                        If okMX(iB, iSet) = 0 Or dVal > pkMX(iB, iSet) Then
                                            pkMX(iB, iSet) = dVal
                                            idMX(iB, iSet) = eID
                                            okMX(iB, iSet) = 1
                                        End If
                                    Else
                                        ' Min principal envelopes DOWNWARD - the
                                        ' governing value is the most compressive.
                                        If okMN(iB, iSet) = 0 Or dVal < pkMN(iB, iSet) Then
                                            pkMN(iB, iSet) = dVal
                                            idMN(iB, iSet) = eID
                                            okMN(iB, iSet) = 1
                                        End If
                                    End If
                                End If
                            End If
                        Next k
                    End If
                End If
            Next iC
        End If
    Next iSet

    ' ============================================================
    ' Section 7: Excel
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

    Dim wsVM As Object, wsMX As Object, wsMN As Object, wsLoc As Object
    Set wsVM = wbk.Worksheets.Add
    wsVM.Name = "Von Mises"
    Set wsMX = wbk.Worksheets.Add
    wsMX.Name = "Max Principal"
    Set wsMN = wbk.Worksheets.Add
    wsMN.Name = "Min Principal"
    Set wsLoc = wbk.Worksheets.Add
    wsLoc.Name = "Governing"

    WriteGrid wsVM, "Max von Mises", nB, nS, bName(), bElems(), setName(), _
        pkVM(), okVM(), 0
    WriteGrid wsMX, "Max Principal (peak tension)", nB, nS, bName(), bElems(), setName(), _
        pkMX(), okMX(), 0
    WriteGrid wsMN, "Min Principal (peak compression)", nB, nS, bName(), bElems(), setName(), _
        pkMN(), okMN(), 1

    ' ---- Governing sheet: envelope across every set, and say which set won ----
    Dim hdrRow As Long, firstRow As Long, lastRow As Long
    hdrRow = 2
    firstRow = 3
    lastRow = firstRow + nB - 1

    wsLoc.Columns(2).NumberFormat = "@"
    wsLoc.Columns(5).NumberFormat = "@"
    wsLoc.Columns(8).NumberFormat = "@"
    wsLoc.Columns(11).NumberFormat = "@"

    wsLoc.Cells(hdrRow, 2).Value  = dimNames(dimPick)
    wsLoc.Cells(hdrRow, 3).Value  = "Elements"
    wsLoc.Cells(hdrRow, 4).Value  = "Max von Mises"
    wsLoc.Cells(hdrRow, 5).Value  = "vM governing set"
    wsLoc.Cells(hdrRow, 6).Value  = "vM element"
    wsLoc.Cells(hdrRow, 7).Value  = "Max Principal"
    wsLoc.Cells(hdrRow, 8).Value  = "MaxP governing set"
    wsLoc.Cells(hdrRow, 9).Value  = "MaxP element"
    wsLoc.Cells(hdrRow, 10).Value = "Min Principal"
    wsLoc.Cells(hdrRow, 11).Value = "MinP governing set"
    wsLoc.Cells(hdrRow, 12).Value = "MinP element"

    Dim bestV As Double
    Dim bestS As Long
    Dim r As Long
    For iB = 0 To nB - 1
        r = firstRow + iB
        wsLoc.Cells(r, 2).Value = bName(iB)
        wsLoc.Cells(r, 3).Value = bElems(iB)

        ' von Mises - envelope up
        bestS = -1
        bestV = 0.0
        For iSet = 0 To nS - 1
            If okVM(iB, iSet) <> 0 Then
                If bestS < 0 Or pkVM(iB, iSet) > bestV Then
                    bestV = pkVM(iB, iSet)
                    bestS = iSet
                End If
            End If
        Next iSet
        If bestS >= 0 Then
            wsLoc.Cells(r, 4).Value = bestV
            wsLoc.Cells(r, 5).Value = setName(bestS)
            wsLoc.Cells(r, 6).Value = idVM(iB, bestS)
        End If

        ' max principal - envelope up
        bestS = -1
        bestV = 0.0
        For iSet = 0 To nS - 1
            If okMX(iB, iSet) <> 0 Then
                If bestS < 0 Or pkMX(iB, iSet) > bestV Then
                    bestV = pkMX(iB, iSet)
                    bestS = iSet
                End If
            End If
        Next iSet
        If bestS >= 0 Then
            wsLoc.Cells(r, 7).Value = bestV
            wsLoc.Cells(r, 8).Value = setName(bestS)
            wsLoc.Cells(r, 9).Value = idMX(iB, bestS)
        End If

        ' min principal - envelope DOWN
        bestS = -1
        bestV = 0.0
        For iSet = 0 To nS - 1
            If okMN(iB, iSet) <> 0 Then
                If bestS < 0 Or pkMN(iB, iSet) < bestV Then
                    bestV = pkMN(iB, iSet)
                    bestS = iSet
                End If
            End If
        Next iSet
        If bestS >= 0 Then
            wsLoc.Cells(r, 10).Value = bestV
            wsLoc.Cells(r, 11).Value = setName(bestS)
            wsLoc.Cells(r, 12).Value = idMN(iB, bestS)
        End If
    Next iB

    wsLoc.Cells.Font.Name = "Calibri"
    wsLoc.Cells.Font.Size = 10
    wsLoc.Range(wsLoc.Cells(firstRow, 3), wsLoc.Cells(lastRow, 3)).NumberFormat = "#,##0"
    wsLoc.Range(wsLoc.Cells(firstRow, 4), wsLoc.Cells(lastRow, 4)).NumberFormat = "0.0000E+00"
    wsLoc.Range(wsLoc.Cells(firstRow, 7), wsLoc.Cells(lastRow, 7)).NumberFormat = "0.0000E+00"
    wsLoc.Range(wsLoc.Cells(firstRow, 10), wsLoc.Cells(lastRow, 10)).NumberFormat = "0.0000E+00"
    wsLoc.Range(wsLoc.Cells(firstRow, 6), wsLoc.Cells(lastRow, 6)).NumberFormat = "0"
    wsLoc.Range(wsLoc.Cells(firstRow, 9), wsLoc.Cells(lastRow, 9)).NumberFormat = "0"
    wsLoc.Range(wsLoc.Cells(firstRow, 12), wsLoc.Cells(lastRow, 12)).NumberFormat = "0"

    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(hdrRow, 12)).Interior.Color = RGB(46, 84, 141)
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(hdrRow, 12)).Font.Color = RGB(255, 255, 255)
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(hdrRow, 12)).Font.Bold = True
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(hdrRow, 12)).WrapText = True
    wsLoc.Rows(hdrRow).RowHeight = 30
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(lastRow, 12)).Borders.LineStyle = 1
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(lastRow, 12)).HorizontalAlignment = -4108
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(lastRow, 2)).HorizontalAlignment = -4131

    wsLoc.Columns(1).ColumnWidth = 3
    wsLoc.Columns(2).ColumnWidth = 30
    wsLoc.Columns(3).ColumnWidth = 10
    For i = 4 To 12
        wsLoc.Columns(i).ColumnWidth = 15
    Next i
    wsLoc.Columns(5).ColumnWidth = 24
    wsLoc.Columns(8).ColumnWidth = 24
    wsLoc.Columns(11).ColumnWidth = 24

    On Error Resume Next
    wsLoc.Range(wsLoc.Cells(hdrRow, 2), wsLoc.Cells(lastRow, 12)).AutoFilter
    wsLoc.Activate
    appExcel.ActiveWindow.FreezePanes = False
    wsLoc.Range("C3").Select
    appExcel.ActiveWindow.FreezePanes = True
    appExcel.ActiveWindow.DisplayGridlines = False
    On Error GoTo 0

    ' ============================================================
    ' Section 8: README sheet
    ' ============================================================
    wsR.Cells(1, 1).Value = "Peak Stress Table"
    wsR.Cells(3, 1).Value = "Model:"
    wsR.Cells(3, 2).Value = App.ModelName
    wsR.Cells(4, 1).Value = "User:"
    wsR.Cells(4, 2).Value = appExcel.UserName
    wsR.Cells(5, 1).Value = "Date:"
    wsR.Cells(5, 2).Value = Now
    wsR.Cells(6, 1).Value = "Bucketed by:"
    wsR.Cells(6, 2).Value = dimNames(dimPick)
    wsR.Cells(7, 1).Value = "Buckets:"
    wsR.Cells(7, 2).Value = nB
    wsR.Cells(8, 1).Value = "Output sets:"
    wsR.Cells(8, 2).Value = nS

    wsR.Cells(10, 1).Value = "Measures:"
    wsR.Cells(10, 2).Value = "Max von Mises, Max Principal (peak tension) and Min Principal " _
        + "(peak compression). Min Principal envelopes DOWNWARD - the governing value is the " _
        + "most negative, not the largest."
    wsR.Cells(11, 1).Value = "Enveloped over:"
    wsR.Cells(11, 2).Value = "Plate TOP fibre, plate BOTTOM fibre and solid centroid. A bucket " _
        + "holding both plates and solids reports the single governing number across all three."

    wsR.Cells(13, 1).Value = "Blank vs zero:"
    wsR.Cells(13, 2).Value = "A blank cell means no element of a type carrying that result was " _
        + "found in that bucket for that output set. It does NOT mean zero stress. Zero is " _
        + "written only where an element really reported zero."

    wsR.Cells(15, 1).Value = "Element class filter:"
    wsR.Cells(15, 2).Value = "Femap returns one results row per element that has ANY requested " _
        + "result, and pads the other element class with exactly 0.0. Rows are therefore " _
        + "filtered by element class before they can move a peak. Without that filter an " _
        + "all-solid bucket would report 0.0 for a plate measure, and any all-compressive " _
        + "bucket would report 0.0 for Min Principal, because 0.0 beats every negative value."

    wsR.Cells(17, 1).Value = "Missing vectors:"
    If nMissing = 0 Then
        wsR.Cells(17, 2).Value = "None - all nine stress vectors resolved in every output set."
    Else
        wsR.Cells(17, 2).Value = "Not present in at least one output set: " + missNote _
            + ".  Those contributions are simply absent; the peaks shown come from the " _
            + "vectors that did resolve. If a plate BOTTOM vector is listed here, the solve " _
            + "may not have written bottom-surface stress - and in bending that is usually " _
            + "the governing fibre."
    End If

    wsR.Cells(19, 1).Value = "Overlap:"
    If nOverlap = 0 Then
        wsR.Cells(19, 2).Value = "No element appears in more than one bucket."
    Else
        wsR.Cells(19, 2).Value = Trim$(Str$(nOverlap)) + " element assignments were overwritten " _
            + "because the buckets overlap. Each element is counted in the LAST bucket that " _
            + "claims it, so an overlapped bucket understates its peak. Peaks are maxima, not " _
            + "sums, so this cannot double-count - but it can hide one."
    End If

    wsR.Cells(21, 1).Value = "Coverage:"
    wsR.Cells(21, 2).Value = "Model has " + Trim$(Str$(nAll)) + " elements: " _
        + Trim$(Str$(nP)) + " plate/membrane, " + Trim$(Str$(nSo)) + " solid. Only those two " _
        + "classes carry the stress vectors used here."

    wsR.Rows("1:1").Font.Bold = True
    wsR.Columns(1).ColumnWidth = 22
    wsR.Columns(2).ColumnWidth = 110
    wsR.Range(wsR.Cells(1, 2), wsR.Cells(21, 2)).WrapText = True

    wsR.Activate
    appExcel.Visible = True

    ' ============================================================
    ' Section 9: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Peak Stress Table - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Bucketed by:      " + dimNames(dimPick))
    App.feAppMessage(FCM_NORMAL, "  Buckets:          " + Trim$(Str$(nB)))
    App.feAppMessage(FCM_NORMAL, "  Output sets:      " + Trim$(Str$(nS)))
    If nMissing > 0 Then
        App.feAppMessage(FCM_WARNING, "  Missing vectors:  " + missNote)
    End If
    If nOverlap > 0 Then
        App.feAppMessage(FCM_WARNING, "  Bucket overlap:   " + Trim$(Str$(nOverlap)) _
            + " element assignments overwritten - see the README sheet.")
    End If
    App.feAppMessage(FCM_NORMAL, "  Nothing in the model was modified.")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub


' -----------------------------------------------------------------------------
' PlyOf - which plate fibre column iC reads.
' -----------------------------------------------------------------------------
' TOP = 0, BOT = 2. The API guide says BOT = 3; measured against a real model,
' ply 3 returns FE_FAIL and ply 2 returns the vector Femap itself titles
' "Plate Bot ...". See the file header before changing this.
Function PlyOf(iC As Long) As Long
    If iC = 1 Or iC = 4 Or iC = 7 Then
        PlyOf = 2
    Else
        PlyOf = 0
    End If
End Function


' -----------------------------------------------------------------------------
' WriteGrid - one measure: buckets down, output sets across.
' -----------------------------------------------------------------------------
' bDown = 1 for min principal, which is highlighted on its most NEGATIVE value
' rather than its largest.
Sub WriteGrid(ws As Object, caption As String, nB As Long, nS As Long, _
              bName() As String, bElems() As Long, setName() As String, _
              pk() As Double, ok() As Integer, bDown As Long)

    Dim hdrRow As Long, firstRow As Long, lastRow As Long, lastCol As Long
    Dim iB As Long, iSet As Long, r As Long, c As Long
    hdrRow = 2
    firstRow = 3
    lastRow = firstRow + nB - 1
    lastCol = 3 + nS

    ' Bucket names are forced to Text BEFORE anything is written. Excel type-
    ' infers on write, so a group called "3-4 Bracket" becomes a date and one
    ' called "1E5" becomes 100000 - silent corruption of the only column that
    ' identifies the row, and unrecoverable once written.
    ws.Columns(2).NumberFormat = "@"

    ws.Cells(1, 2).Value = caption
    ws.Cells(1, 2).Font.Bold = True

    ws.Cells(hdrRow, 2).Value = "Bucket"
    ws.Cells(hdrRow, 3).Value = "Elements"
    For iSet = 0 To nS - 1
        ws.Cells(hdrRow, 4 + iSet).Value = setName(iSet)
    Next iSet

    For iB = 0 To nB - 1
        r = firstRow + iB
        ws.Cells(r, 2).Value = bName(iB)
        ws.Cells(r, 3).Value = bElems(iB)
        For iSet = 0 To nS - 1
            ' Blank, not zero, where nothing qualified. See the README sheet.
            If ok(iB, iSet) <> 0 Then
                ws.Cells(r, 4 + iSet).Value = pk(iB, iSet)
            End If
        Next iSet
    Next iB

    ws.Cells.Font.Name = "Calibri"
    ws.Cells.Font.Size = 10
    ws.Range(ws.Cells(firstRow, 3), ws.Cells(lastRow, 3)).NumberFormat = "#,##0"
    ws.Range(ws.Cells(firstRow, 4), ws.Cells(lastRow, lastCol)).NumberFormat = "0.0000E+00"

    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(hdrRow, lastCol)).Interior.Color = RGB(46, 84, 141)
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(hdrRow, lastCol)).Font.Color = RGB(255, 255, 255)
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(hdrRow, lastCol)).Font.Bold = True
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(hdrRow, lastCol)).WrapText = True
    ws.Rows(hdrRow).RowHeight = 34
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(lastRow, lastCol)).Borders.LineStyle = 1
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(lastRow, lastCol)).HorizontalAlignment = -4108
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(lastRow, 2)).HorizontalAlignment = -4131

    ws.Columns(1).ColumnWidth = 3
    ws.Columns(2).ColumnWidth = 30
    ws.Columns(3).ColumnWidth = 10
    For c = 4 To lastCol
        ws.Columns(c).ColumnWidth = 15
    Next c

    ' Tint the governing cell in each row, so the load case that drives a bucket
    ' is visible without reading across the sheet.
    Dim bestC As Long
    Dim bestV As Double
    For iB = 0 To nB - 1
        r = firstRow + iB
        bestC = -1
        bestV = 0.0
        For iSet = 0 To nS - 1
            If ok(iB, iSet) <> 0 Then
                If bestC < 0 Then
                    bestV = pk(iB, iSet)
                    bestC = iSet
                ElseIf bDown = 1 And pk(iB, iSet) < bestV Then
                    bestV = pk(iB, iSet)
                    bestC = iSet
                ElseIf bDown = 0 And pk(iB, iSet) > bestV Then
                    bestV = pk(iB, iSet)
                    bestC = iSet
                End If
            End If
        Next iSet
        If bestC >= 0 Then
            ws.Cells(r, 4 + bestC).Interior.Color = RGB(255, 235, 200)
            ws.Cells(r, 4 + bestC).Font.Bold = True
        End If
    Next iB

    On Error Resume Next
    ws.Range(ws.Cells(hdrRow, 2), ws.Cells(lastRow, lastCol)).AutoFilter
    ws.Activate
    ws.Application.ActiveWindow.FreezePanes = False
    ws.Range("D3").Select
    ws.Application.ActiveWindow.FreezePanes = True
    ws.Application.ActiveWindow.DisplayGridlines = False
    On Error GoTo 0
End Sub
