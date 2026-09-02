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

    ' --- where on the element the stress is read -------------------------
    ' *** THIS IS THE SETTING THAT MAKES THE NUMBERS MATCH FEMAP ***
    ' Centroidal stress is materially LOWER than corner stress on the same
    ' element. A table built on the centroid does not disagree with Femap's own
    ' group max by a rounding error - it disagrees by a visible margin, and it
    ' is the tool that is wrong, because the number an analyst quotes comes off
    ' a corner-data plot.
    '
    ' Corner values are read RAW, straight out of the corner vectors, so they
    ' are unaveraged by construction. This tool does no nodal averaging at all;
    ' to match an averaged plot you would have to average across the elements
    ' meeting at each node, which is a different number and is not offered.
    Dim locNames(2) As String
    locNames(0) = "Corner, unaveraged"
    locNames(1) = "Centroid"
    locNames(2) = "Both (worst of the two)"

    Dim locPick As Long
    locPick = 0

    ' Seed the dialog from the active view's Contour Options, so the default
    ' matches whatever is on screen. Fenced: a model with no active view must
    ' not stop the tool, it just falls back to corner.
    Dim viewNote As String
    viewNote = "no active view - defaulted to corner"
    Dim vw As Object
    Dim vwID As Long
    On Error Resume Next
    vwID = App.Info_ActiveID(FT_VIEW)
    If vwID > 0 Then
        Set vw = App.feView
        If vw.Get(vwID) = FE_OK Then
            If vw.ContourCornerData Then
                locPick = 0
                viewNote = "active view has Use Corner Data ON"
            Else
                locPick = 1
                viewNote = "active view has Use Corner Data OFF"
            End If
        End If
    End If
    On Error GoTo 0

    Begin Dialog PeakDlg 340, 136, "Peak Stress Table"
        Text        12, 14, 116, 12, "Summarise peaks by:"
        DropListBox 132, 12, 196, 120, dimNames(), .dimPick
        Text        12, 42, 116, 12, "Stress read at:"
        DropListBox 132, 40, 196, 100, locNames(), .locPick
        Text        12, 66, 316, 20, "Next you will pick the output sets, then the buckets themselves."
        OKButton     92, 106, 76, 20
        CancelButton 176, 106, 76, 20
    End Dialog
    Dim dlg As PeakDlg
    dlg.dimPick = 0
    dlg.locPick = locPick
    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    dimPick = dlg.dimPick
    locPick = dlg.locPick

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

    ' Every bucketed element, in one set. Used only to narrow Populate via
    ' DataNeeded - the report itself is driven by bkt() above.
    Dim bktSet As femap.Set
    Set bktSet = App.feSet

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
                    bktSet.AddArray(nInB, bIDs)
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
                    bktSet.AddArray(nInB, bIDs)
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
    ' Section 5: Which vectors, and where on the element
    ' ============================================================
    ' PlateWithCorners returns FIVE vector IDs for one result/type/ply:
    '   0 = centroid, 1..4 = corners
    ' SolidWithCorners returns NINE for one result/type:
    '   0 = centroid, 1..8 = corners
    ' (The guide's Output line says VectorIDs[0..4] for the solid method and
    ' then lists nine entries. The nine is right; the bound is a typo. Indices
    ' are taken from LBound and clamped to UBound so it cannot overrun either
    ' way.)
    '
    ' Every location for a measure becomes its own column, and they all feed the
    ' same running peak - so "corner" means the worst of that element's corners,
    ' which is what Femap's group max reports with Use Corner Data on.
    '
    ' Plies are integer literals. TOP = 0, BOT = 2 - see the file header; the
    ' API guide's 3 returns FE_FAIL.
    Dim MAXCOL As Long
    MAXCOL = 96
    Dim vMeas() As Long
    Dim vClass() As Long
    Dim vVec() As Long
    Dim vLabel() As String
    ReDim vMeas(MAXCOL - 1)
    ReDim vClass(MAXCOL - 1)
    ReDim vVec(MAXCOL - 1)
    ReDim vLabel(MAXCOL - 1)
    Dim NVEC As Long
    NVEC = 0

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

    Dim colOf() As Long
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

        ' --- work out which vectors exist in THIS set --------------------
        NVEC = 0
        Dim m As Long, ply As Long, j As Long
        Dim lo As Long, hi As Long, wantHi As Long
        Dim vids As Variant
        Dim mName As String

        For m = 0 To 2
            If m = 0 Then
                mName = "vonMises"
            ElseIf m = 1 Then
                mName = "MaxPrin"
            Else
                mName = "MinPrin"
            End If

            ' ---- plates: top and bottom fibre -------------------------
            For ply = 0 To 1
                rc = FE_FAIL
                On Error Resume Next
                If m = 0 Then
                    rc = q.PlateWithCorners(VPV_STRESS, VPT_VON_MISES, PlyVal(ply), vids)
                ElseIf m = 1 Then
                    rc = q.PlateWithCorners(VPV_STRESS, VPT_MAX_PRIN, PlyVal(ply), vids)
                Else
                    rc = q.PlateWithCorners(VPV_STRESS, VPT_MIN_PRIN, PlyVal(ply), vids)
                End If
                On Error GoTo 0

                If rc <> FE_FAIL And IsArray(vids) Then
                    lo = LBound(vids)
                    hi = UBound(vids)
                    ' locPick: 0 corner only, 1 centroid only, 2 both
                    wantHi = lo + 4
                    If hi > wantHi Then hi = wantHi
                    For j = lo To hi
                        If (locPick = 1 And j <> lo) Or (locPick = 0 And j = lo) Then
                            ' skipped by the location choice
                        ElseIf NVEC < MAXCOL Then
                            If CLng(vids(j)) > 0 Then
                                vMeas(NVEC) = m
                                vClass(NVEC) = 1
                                vVec(NVEC) = CLng(vids(j))
                                If ply = 0 Then
                                    vLabel(NVEC) = "Plate Top " + mName
                                Else
                                    vLabel(NVEC) = "Plate Bot " + mName
                                End If
                                NVEC = NVEC + 1
                            End If
                        End If
                    Next j
                End If
            Next ply

            ' ---- solids ------------------------------------------------
            rc = FE_FAIL
            On Error Resume Next
            If m = 0 Then
                rc = q.SolidWithCorners(VSV_STRESS, VST_VON_MISES, vids)
            ElseIf m = 1 Then
                rc = q.SolidWithCorners(VSV_STRESS, VST_MAX_PRIN, vids)
            Else
                rc = q.SolidWithCorners(VSV_STRESS, VST_MIN_PRIN, vids)
            End If
            On Error GoTo 0

            If rc <> FE_FAIL And IsArray(vids) Then
                lo = LBound(vids)
                hi = UBound(vids)
                wantHi = lo + 8
                If hi > wantHi Then hi = wantHi
                For j = lo To hi
                    If (locPick = 1 And j <> lo) Or (locPick = 0 And j = lo) Then
                        ' skipped by the location choice
                    ElseIf NVEC < MAXCOL Then
                        If CLng(vids(j)) > 0 Then
                            vMeas(NVEC) = m
                            vClass(NVEC) = 2
                            vVec(NVEC) = CLng(vids(j))
                            vLabel(NVEC) = "Solid " + mName
                            NVEC = NVEC + 1
                        End If
                    End If
                Next j
            End If
        Next m

        If NVEC = 0 Then
            App.feAppMessage(FCM_WARNING, "    No stress vectors in this set - left blank.")
            nMissing = nMissing + 1
        End If

        ' --- load them --------------------------------------------------
        ReDim colOf(MAXCOL - 1)
        For iC = 0 To NVEC - 1
            colOf(iC) = -1
            rc = rbo.AddColumnV2(setID(iSet), vVec(iC), False, nAdded, vCols)
            If rc = FE_OK And nAdded > 0 Then
                colOf(iC) = vCols(0)
            Else
                nMissing = nMissing + 1
                If InStr(missNote, vLabel(iC)) = 0 Then
                    If Len(missNote) > 0 Then missNote = missNote + ", "
                    missNote = missNote + vLabel(iC)
                End If
            End If
        Next iC

        ' Narrow Populate to the elements actually being reported. Without this
        ' it loads a row per element in the MODEL for every one of these columns,
        ' and with corner data that is tens of columns - the row loop below is
        ' the whole cost of the tool. Optional by design: if it is refused the
        ' result is only slower, never wrong.
        On Error Resume Next
        rbo.DataNeeded(8, bktSet.ID)
        On Error GoTo 0

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
    ' Section 7: Excel - ONE flat table
    ' ============================================================
    ' One row per bucket per output set, three measure columns side by side.
    ' Flat rather than a grid-per-measure: it keeps AutoFilter and sorting
    ' working, it grows DOWN as load cases are added instead of sideways, and
    ' finding the governing case is a sort rather than a second sheet. A wide
    ' layout would need the set names spanning three columns each, and a merged
    ' header row breaks both filtering and sorting.
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
    wsD.Name = "Peak Stress"

    Dim hdrRow As Long, firstRow As Long, lastRow As Long
    hdrRow = 2
    firstRow = 3

    ' Bucket and Output Set are forced to Text BEFORE anything is written. Excel
    ' type-infers on write, so a group called "3-4 Bracket" becomes a date and
    ' one called "1E5" becomes 100000 - silent corruption of the only columns
    ' that identify the row, and unrecoverable once written.
    wsD.Columns(2).NumberFormat = "@"
    wsD.Columns(4).NumberFormat = "@"

    wsD.Cells(hdrRow, 2).Value  = dimNames(dimPick)
    wsD.Cells(hdrRow, 3).Value  = "Elements"
    wsD.Cells(hdrRow, 4).Value  = "Output Set"
    wsD.Cells(hdrRow, 5).Value  = "Von Mises"
    wsD.Cells(hdrRow, 6).Value  = "vM Elem"
    wsD.Cells(hdrRow, 7).Value  = "Max Prin"
    wsD.Cells(hdrRow, 8).Value  = "MaxP Elem"
    wsD.Cells(hdrRow, 9).Value  = "Min Prin"
    wsD.Cells(hdrRow, 10).Value = "MinP Elem"

    Dim r As Long
    r = firstRow
    For iB = 0 To nB - 1
        For iSet = 0 To nS - 1
            wsD.Cells(r, 2).Value = bName(iB)
            wsD.Cells(r, 3).Value = bElems(iB)
            wsD.Cells(r, 4).Value = setName(iSet)
            ' Blank, not zero, where nothing qualified. See the README sheet.
            If okVM(iB, iSet) <> 0 Then
                wsD.Cells(r, 5).Value = pkVM(iB, iSet)
                wsD.Cells(r, 6).Value = idVM(iB, iSet)
            End If
            If okMX(iB, iSet) <> 0 Then
                wsD.Cells(r, 7).Value = pkMX(iB, iSet)
                wsD.Cells(r, 8).Value = idMX(iB, iSet)
            End If
            If okMN(iB, iSet) <> 0 Then
                wsD.Cells(r, 9).Value = pkMN(iB, iSet)
                wsD.Cells(r, 10).Value = idMN(iB, iSet)
            End If
            r = r + 1
        Next iSet
    Next iB
    lastRow = r - 1

    wsD.Cells.Font.Name = "Calibri"
    wsD.Cells.Font.Size = 10
    wsD.Range(wsD.Cells(firstRow, 3), wsD.Cells(lastRow, 3)).NumberFormat = "#,##0"
    wsD.Range(wsD.Cells(firstRow, 5), wsD.Cells(lastRow, 5)).NumberFormat = "0.0000E+00"
    wsD.Range(wsD.Cells(firstRow, 7), wsD.Cells(lastRow, 7)).NumberFormat = "0.0000E+00"
    wsD.Range(wsD.Cells(firstRow, 9), wsD.Cells(lastRow, 9)).NumberFormat = "0.0000E+00"
    wsD.Range(wsD.Cells(firstRow, 6), wsD.Cells(lastRow, 6)).NumberFormat = "0"
    wsD.Range(wsD.Cells(firstRow, 8), wsD.Cells(lastRow, 8)).NumberFormat = "0"
    wsD.Range(wsD.Cells(firstRow, 10), wsD.Cells(lastRow, 10)).NumberFormat = "0"

    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 10)).Interior.Color = RGB(46, 84, 141)
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 10)).Font.Color = RGB(255, 255, 255)
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 10)).Font.Bold = True
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, 10)).WrapText = True
    wsD.Rows(hdrRow).RowHeight = 30
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 10)).Borders.LineStyle = 1
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 10)).HorizontalAlignment = -4108
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 2)).HorizontalAlignment = -4131
    wsD.Range(wsD.Cells(hdrRow, 4), wsD.Cells(lastRow, 4)).HorizontalAlignment = -4131

    ' Tint the governing row for each bucket - the load case that drives it,
    ' visible without sorting. Only worth doing when there is a choice to make.
    If nS > 1 Then
        Dim bestS As Long
        Dim bestV As Double
        For iB = 0 To nB - 1
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
                r = firstRow + iB * nS + bestS
                wsD.Range(wsD.Cells(r, 2), wsD.Cells(r, 10)).Interior.Color = RGB(255, 235, 200)
                wsD.Range(wsD.Cells(r, 2), wsD.Cells(r, 10)).Font.Bold = True
            End If
        Next iB
    End If

    wsD.Columns(1).ColumnWidth = 3
    wsD.Columns(2).ColumnWidth = 30
    wsD.Columns(3).ColumnWidth = 10
    wsD.Columns(4).ColumnWidth = 26
    wsD.Columns(5).ColumnWidth = 14
    wsD.Columns(6).ColumnWidth = 11
    wsD.Columns(7).ColumnWidth = 14
    wsD.Columns(8).ColumnWidth = 11
    wsD.Columns(9).ColumnWidth = 14
    wsD.Columns(10).ColumnWidth = 11

    On Error Resume Next
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 10)).AutoFilter
    wsD.Activate
    appExcel.ActiveWindow.FreezePanes = False
    wsD.Range("E3").Select
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
    wsR.Cells(9, 1).Value = "Stress read at:"
    wsR.Cells(9, 2).Value = locNames(locPick) + "   (" + viewNote + ")"

    wsR.Cells(10, 1).Value = "Measures:"
    wsR.Cells(10, 2).Value = "Max von Mises, Max Principal (peak tension) and Min Principal " _
        + "(peak compression). Min Principal envelopes DOWNWARD - the governing value is the " _
        + "most negative, not the largest."
    wsR.Cells(11, 1).Value = "Enveloped over:"
    wsR.Cells(11, 2).Value = "Plate TOP fibre, plate BOTTOM fibre and solids, at every location " _
        + "the setting above selects. A bucket holding both plates and solids reports the " _
        + "single governing number across all of them."
    wsR.Cells(12, 1).Value = "Corner values:"
    wsR.Cells(12, 2).Value = "Read RAW from the corner vectors, so they are UNAVERAGED. This " _
        + "tool does no nodal averaging; to match an averaged contour you would have to " _
        + "average across the elements meeting at each node, which is a different number. " _
        + "Centroidal stress is materially lower than corner stress on the same element, " _
        + "which is why this setting decides whether the table agrees with Femap's group max."

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
        wsR.Cells(17, 2).Value = "None - every stress vector requested resolved in every output set."
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
    App.feAppMessage(FCM_NORMAL, "  Stress read at:   " + locNames(locPick) + "   (" + viewNote + ")")
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
' PlyVal - fibre 0 = top, 1 = bottom.
' -----------------------------------------------------------------------------
' TOP = 0, BOT = 2. The API guide says BOT = 3; measured against a real model,
' ply 3 returns FE_FAIL and ply 2 returns the vector Femap itself titles
' "Plate Bot ...". See the file header before changing this.
Function PlyVal(ply As Long) As Long
    If ply = 1 Then
        PlyVal = 2
    Else
        PlyVal = 0
    End If
End Function
