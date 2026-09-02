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

    ' Labels get far more width than the text appears to need. The dialog font
    ' is PROPORTIONAL, so a width guessed from the character count clips the
    ' descender end of the string - and it clips silently, looking like a typo
    ' rather than a layout bug.
    Begin Dialog PeakDlg 420, 152, "Peak Stress Table"
        Text        12, 15, 150, 14, "Summarise peaks by:"
        DropListBox 168, 12, 240, 120, dimNames(), .dimPick
        Text        12, 47, 150, 14, "Stress read at:"
        DropListBox 168, 44, 240, 100, locNames(), .locPick
        Text        12, 78, 396, 14, "Corner values are unaveraged. The default follows the active view."
        Text        12, 94, 396, 14, "Next you will pick the output sets, then the buckets themselves."
        OKButton    136, 118, 76, 22
        CancelButton 220, 118, 76, 22
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
    Dim vLoc() As Long
    ReDim vLoc(MAXCOL - 1)
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
    Dim okVM() As Integer, okMX() As Integer, okMN() As Integer
    ReDim pkVM(nB - 1, nS - 1)
    ReDim pkMX(nB - 1, nS - 1)
    ReDim pkMN(nB - 1, nS - 1)
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

    ' Scratch for the per-set vector lookup below. Declared here rather than
    ' inside the loop: WinWrap identifiers are case-insensitive, and a second
    ' Dim of a name already taken - vecIDs against GetColumn's vIDs - is an
    ' "identifier is already in use" error, not a shadow.
    Dim m As Long, ply As Long, j As Long
    Dim lo As Long, hi As Long, wantHi As Long
    Dim vecIDs As Variant
    Dim mName As String

    ' Exactly which output vectors fed the table, listed for the first output
    ' set. Not decoration: "what is the centroid column actually reading?" is
    ' not answerable from the numbers, and on this model the plate/solid vector
    ' IDs are the whole correctness argument. Printing them lets the IDs be
    ' checked against Femap's own contour vector list rather than trusted.
    Dim vecNote As String
    Dim nCorner As Long
    vecNote = ""
    nCorner = 0

    App.feAppMessage(FCM_NORMAL, "Peak Stress Table - reading " + Trim$(Str$(nS)) + _
        " output set(s) over " + Trim$(Str$(nB)) + " bucket(s)...")

    For iSet = 0 To nS - 1
        App.feAppMessage(FCM_NORMAL, "  " + setName(iSet))

        rbo.Clear

        ' --- work out which vectors exist in THIS set --------------------
        NVEC = 0

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
                    rc = q.PlateWithCorners(VPV_STRESS, VPT_VON_MISES, PlyVal(ply), vecIDs)
                ElseIf m = 1 Then
                    rc = q.PlateWithCorners(VPV_STRESS, VPT_MAX_PRIN, PlyVal(ply), vecIDs)
                Else
                    rc = q.PlateWithCorners(VPV_STRESS, VPT_MIN_PRIN, PlyVal(ply), vecIDs)
                End If
                On Error GoTo 0

                If rc <> FE_FAIL And IsArray(vecIDs) Then
                    lo = LBound(vecIDs)
                    hi = UBound(vecIDs)
                    ' locPick: 0 corner only, 1 centroid only, 2 both
                    wantHi = lo + 4
                    If hi > wantHi Then hi = wantHi
                    For j = lo To hi
                        If (locPick = 1 And j <> lo) Or (locPick = 0 And j = lo) Then
                            ' skipped by the location choice
                        ElseIf NVEC < MAXCOL Then
                            If CLng(vecIDs(j)) > 0 Then
                                vMeas(NVEC) = m
                                vClass(NVEC) = 1
                                vVec(NVEC) = CLng(vecIDs(j))
                                vLoc(NVEC) = j - lo
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
                rc = q.SolidWithCorners(VSV_STRESS, VST_VON_MISES, vecIDs)
            ElseIf m = 1 Then
                rc = q.SolidWithCorners(VSV_STRESS, VST_MAX_PRIN, vecIDs)
            Else
                rc = q.SolidWithCorners(VSV_STRESS, VST_MIN_PRIN, vecIDs)
            End If
            On Error GoTo 0

            If rc <> FE_FAIL And IsArray(vecIDs) Then
                lo = LBound(vecIDs)
                hi = UBound(vecIDs)
                wantHi = lo + 8
                If hi > wantHi Then hi = wantHi
                For j = lo To hi
                    If (locPick = 1 And j <> lo) Or (locPick = 0 And j = lo) Then
                        ' skipped by the location choice
                    ElseIf NVEC < MAXCOL Then
                        If CLng(vecIDs(j)) > 0 Then
                            vMeas(NVEC) = m
                            vClass(NVEC) = 2
                            vVec(NVEC) = CLng(vecIDs(j))
                            vLoc(NVEC) = j - lo
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

        ' Report the vectors once, off the first output set - they are the same
        ' vectors every set, only the data behind them changes.
        If iSet = 0 Then
            Dim locWord As String
            For iC = 0 To NVEC - 1
                If vLoc(iC) = 0 Then
                    locWord = "centroid"
                Else
                    locWord = "corner " + Trim$(Str$(vLoc(iC)))
                    nCorner = nCorner + 1
                End If
                App.feAppMessage(FCM_NORMAL, "      " + vLabel(iC) + "  [" + locWord + "]  vec " _
                    + Trim$(Str$(vVec(iC))))
                If Len(vecNote) > 0 Then vecNote = vecNote + ";  "
                vecNote = vecNote + vLabel(iC) + " [" + locWord + "] " + Trim$(Str$(vVec(iC)))
            Next iC

            ' Corner asked for and none found means the solve wrote centroidal
            ' data only. The table is not wrong, but it is not what was asked
            ' for, and it will read low against a corner-data plot.
            If locPick = 0 And nCorner = 0 Then
                App.feAppMessage(FCM_WARNING, "    Corner data was requested but this model has " _
                    + "NONE - every vector above is centroidal.")
                App.feAppMessage(FCM_WARNING, "    The table will read low against a corner-data plot.")
            End If
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
                                            okVM(iB, iSet) = 1
                                        End If
                                    ElseIf vMeas(iC) = 1 Then
                                        If okMX(iB, iSet) = 0 Or dVal > pkMX(iB, iSet) Then
                                            pkMX(iB, iSet) = dVal
                                            okMX(iB, iSet) = 1
                                        End If
                                    Else
                                        ' Min principal envelopes DOWNWARD - the
                                        ' governing value is the most compressive.
                                        If okMN(iB, iSet) = 0 Or dVal < pkMN(iB, iSet) Then
                                            pkMN(iB, iSet) = dVal
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
    ' Section 7: Excel - one row per bucket, output sets across
    ' ============================================================
    ' Layout: Bucket | Elements | <set 1 vM, MaxP, MinP> | <set 2 ...> | ENVELOPE
    '
    ' One row per bucket, each output set contributing its own block of three
    ' measures in the order they were picked, and an envelope block last.
    '
    ' The header is ONE row, with the set name and the measure stacked inside a
    ' single cell by a line break. Merging the set name across its three columns
    ' would look tidier and would break both sorting and AutoFilter - the whole
    ' point of a flat header.
    '
    ' The envelope is across output sets only, never across buckets: von Mises
    ' and Max Principal take the largest, Min Principal takes the most NEGATIVE.
    ' It is omitted for a single output set, where it would just repeat it.
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
    Dim envCol As Long, lastCol As Long, cBase As Long
    Dim wantEnv As Boolean
    hdrRow = 2
    firstRow = 3
    lastRow = firstRow + nB - 1
    wantEnv = (nS > 1)
    envCol = 4 + nS * 3
    If wantEnv Then
        lastCol = envCol + 2
    Else
        lastCol = envCol - 1
    End If

    ' Bucket names are forced to Text BEFORE anything is written. Excel type-
    ' infers on write, so a group called "3-4 Bracket" becomes a date and one
    ' called "1E5" becomes 100000 - silent corruption of the only column that
    ' identifies the row, and unrecoverable once written.
    wsD.Columns(2).NumberFormat = "@"

    wsD.Cells(hdrRow, 2).Value = dimNames(dimPick)
    wsD.Cells(hdrRow, 3).Value = "Elements"
    For iSet = 0 To nS - 1
        cBase = 4 + iSet * 3
        wsD.Cells(hdrRow, cBase).Value     = setName(iSet) + Chr$(10) + "Von Mises"
        wsD.Cells(hdrRow, cBase + 1).Value = setName(iSet) + Chr$(10) + "Max Prin"
        wsD.Cells(hdrRow, cBase + 2).Value = setName(iSet) + Chr$(10) + "Min Prin"
    Next iSet
    If wantEnv Then
        wsD.Cells(hdrRow, envCol).Value     = "ENVELOPE" + Chr$(10) + "Von Mises"
        wsD.Cells(hdrRow, envCol + 1).Value = "ENVELOPE" + Chr$(10) + "Max Prin"
        wsD.Cells(hdrRow, envCol + 2).Value = "ENVELOPE" + Chr$(10) + "Min Prin"
    End If

    Dim r As Long
    Dim eVM As Double, eMX As Double, eMN As Double
    Dim hVM As Long, hMX As Long, hMN As Long
    Dim govS As Long
    Dim govV As Double

    For iB = 0 To nB - 1
        r = firstRow + iB
        wsD.Cells(r, 2).Value = bName(iB)
        wsD.Cells(r, 3).Value = bElems(iB)

        eVM = 0.0 : eMX = 0.0 : eMN = 0.0
        hVM = 0 : hMX = 0 : hMN = 0
        govS = -1
        govV = 0.0

        For iSet = 0 To nS - 1
            cBase = 4 + iSet * 3
            ' Blank, not zero, where nothing qualified. See the README sheet.
            If okVM(iB, iSet) <> 0 Then
                wsD.Cells(r, cBase).Value = pkVM(iB, iSet)
                If hVM = 0 Or pkVM(iB, iSet) > eVM Then
                    eVM = pkVM(iB, iSet)
                    hVM = 1
                End If
                If govS < 0 Or pkVM(iB, iSet) > govV Then
                    govV = pkVM(iB, iSet)
                    govS = iSet
                End If
            End If
            If okMX(iB, iSet) <> 0 Then
                wsD.Cells(r, cBase + 1).Value = pkMX(iB, iSet)
                If hMX = 0 Or pkMX(iB, iSet) > eMX Then
                    eMX = pkMX(iB, iSet)
                    hMX = 1
                End If
            End If
            If okMN(iB, iSet) <> 0 Then
                wsD.Cells(r, cBase + 2).Value = pkMN(iB, iSet)
                ' Min Principal envelopes DOWNWARD - most negative governs.
                If hMN = 0 Or pkMN(iB, iSet) < eMN Then
                    eMN = pkMN(iB, iSet)
                    hMN = 1
                End If
            End If
        Next iSet

        If wantEnv Then
            If hVM <> 0 Then wsD.Cells(r, envCol).Value = eVM
            If hMX <> 0 Then wsD.Cells(r, envCol + 1).Value = eMX
            If hMN <> 0 Then wsD.Cells(r, envCol + 2).Value = eMN
        End If

        ' Amber on the von Mises cell of the set that drives this bucket, so the
        ' governing load case is visible without reading across the row.
        If wantEnv And govS >= 0 Then
            wsD.Cells(r, 4 + govS * 3).Interior.Color = RGB(255, 235, 200)
            wsD.Cells(r, 4 + govS * 3).Font.Bold = True
        End If
    Next iB

    wsD.Cells.Font.Name = "Calibri"
    wsD.Cells.Font.Size = 10
    wsD.Range(wsD.Cells(firstRow, 3), wsD.Cells(lastRow, 3)).NumberFormat = "#,##0"
    wsD.Range(wsD.Cells(firstRow, 4), wsD.Cells(lastRow, lastCol)).NumberFormat = "0.0000E+00"

    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, lastCol)).Interior.Color = RGB(46, 84, 141)
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, lastCol)).Font.Color = RGB(255, 255, 255)
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, lastCol)).Font.Bold = True
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(hdrRow, lastCol)).WrapText = True
    wsD.Rows(hdrRow).RowHeight = 42
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, lastCol)).Borders.LineStyle = 1
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, lastCol)).HorizontalAlignment = -4108
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, 2)).HorizontalAlignment = -4131

    ' The envelope block reads as a summary, not as another load case.
    If wantEnv Then
        wsD.Range(wsD.Cells(firstRow, envCol), wsD.Cells(lastRow, envCol + 2)).Interior.Color = RGB(221, 230, 243)
        wsD.Range(wsD.Cells(firstRow, envCol), wsD.Cells(lastRow, envCol + 2)).Font.Bold = True
    End If

    wsD.Columns(1).ColumnWidth = 3
    wsD.Columns(2).ColumnWidth = 30
    wsD.Columns(3).ColumnWidth = 10
    For i = 4 To lastCol
        wsD.Columns(i).ColumnWidth = 14
    Next i

    On Error Resume Next
    wsD.Range(wsD.Cells(hdrRow, 2), wsD.Cells(lastRow, lastCol)).AutoFilter
    wsD.Activate
    appExcel.ActiveWindow.FreezePanes = False
    wsD.Range("D3").Select
    appExcel.ActiveWindow.FreezePanes = True
    appExcel.ActiveWindow.DisplayGridlines = False
    On Error GoTo 0

    ' ============================================================
    ' Section 8: README sheet
    ' ============================================================
    ' Everything that changes how the numbers should be read lives here, so a
    ' sheet that gets emailed on carries its own caveats.
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

    wsR.Cells(11, 1).Value = "Layout:"
    wsR.Cells(11, 2).Value = "One row per bucket. Each output set contributes its own block of " _
        + "three columns, in the order you picked them. With more than one set an ENVELOPE " _
        + "block is added last, and the von Mises cell of the governing set is tinted on " _
        + "each row."

    wsR.Cells(12, 1).Value = "Envelope:"
    wsR.Cells(12, 2).Value = "Across OUTPUT SETS only, never across buckets. Von Mises and Max " _
        + "Principal take the largest value; Min Principal takes the most NEGATIVE, because " _
        + "the governing compressive value is the most negative, not the largest."

    wsR.Cells(14, 1).Value = "Measures:"
    wsR.Cells(14, 2).Value = "Max von Mises, Max Principal (peak tension) and Min Principal " _
        + "(peak compression), per bucket per output set."

    wsR.Cells(15, 1).Value = "Enveloped over:"
    wsR.Cells(15, 2).Value = "Plate TOP fibre, plate BOTTOM fibre and solids, at every location " _
        + "the setting above selects. A bucket holding both plates and solids reports the " _
        + "single governing number across all of them."

    wsR.Cells(16, 1).Value = "Corner values:"
    wsR.Cells(16, 2).Value = "Read RAW from the corner vectors, so they are UNAVERAGED. This " _
        + "tool does no nodal averaging; to match an averaged contour you would have to " _
        + "average across the elements meeting at each node, which is a different number. " _
        + "Centroidal stress is materially lower than corner stress on the same element, " _
        + "which is why this setting decides whether the table agrees with Femap's group max."

    wsR.Cells(18, 1).Value = "Blank vs zero:"
    wsR.Cells(18, 2).Value = "A blank cell means no element carrying that result was found in " _
        + "that bucket for that output set. It does NOT mean zero stress. Zero is written " _
        + "only where an element really reported zero."

    wsR.Cells(19, 1).Value = "Element class filter:"
    wsR.Cells(19, 2).Value = "Femap returns one results row per element that has ANY requested " _
        + "result, and pads the other element class with exactly 0.0. Rows are therefore " _
        + "filtered by element class before they can move a peak. Without that filter an " _
        + "all-solid bucket would report 0.0 for a plate measure, and any all-compressive " _
        + "bucket would report 0.0 for Min Principal, because 0.0 beats every negative value."

    wsR.Cells(21, 1).Value = "Missing vectors:"
    If nMissing = 0 Then
        wsR.Cells(21, 2).Value = "None - every stress vector requested resolved in every output set."
    Else
        wsR.Cells(21, 2).Value = "Not present in at least one output set: " + missNote _
            + ".  Those contributions are simply absent; the peaks shown come from the " _
            + "vectors that did resolve. If a plate BOTTOM vector is listed here, the solve " _
            + "may not have written bottom-surface stress - and in bending that is usually " _
            + "the governing fibre."
    End If

    wsR.Cells(22, 1).Value = "Overlap:"
    If nOverlap = 0 Then
        wsR.Cells(22, 2).Value = "No element appears in more than one bucket."
    Else
        wsR.Cells(22, 2).Value = Trim$(Str$(nOverlap)) + " element assignments were overwritten " _
            + "because the buckets overlap. Each element is counted in the LAST bucket that " _
            + "claims it, so an overlapped bucket understates its peak. Peaks are maxima, not " _
            + "sums, so this cannot double-count - but it can hide one."
    End If

    wsR.Cells(23, 1).Value = "Coverage:"
    wsR.Cells(23, 2).Value = "Model has " + Trim$(Str$(nAll)) + " elements: " _
        + Trim$(Str$(nP)) + " plate/membrane, " + Trim$(Str$(nSo)) + " solid. Only those two " _
        + "classes carry the stress vectors used here."

    wsR.Cells(25, 1).Value = "Vectors used:"
    wsR.Cells(25, 2).Value = vecNote
    wsR.Cells(26, 1).Value = ""
    wsR.Cells(26, 2).Value = "Listed so they can be checked against Femap's own contour vector " _
        + "list rather than trusted. [centroid] is the solver's value at the element centroid - " _
        + "one number per element, no averaging. [corner N] is that element's raw corner value, " _
        + "also unaveraged."

    wsR.Rows("1:1").Font.Bold = True
    wsR.Columns(1).ColumnWidth = 22
    wsR.Columns(2).ColumnWidth = 110
    wsR.Range(wsR.Cells(1, 2), wsR.Cells(26, 2)).WrapText = True

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
