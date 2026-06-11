' Mode Identification (ESE EKE).bas
' -----------------------------------------------------------------------------
' Modal post-processing: for each selected output set (mode) and each selected
' element group, report the group's % of Element Strain Energy (ESE) and %
' Element Kinetic Energy (EKE). Results go to one Excel sheet (ESE block + EKE
' block side by side), each with a per-mode Total column to check ~100%.
'
' - Output vectors are resolved at RUNTIME (no hardcoded IDs) via ResultsIDQuery:
'     ESE % = Elemental(1)  (VEO_STRAIN_ENERGY_PERCENT)
'     EKE % = Elemental(30) (VEO_KINETIC_ENERGY_PERCENT)
'   Fallback: Find(outSetID, "...Percent") by title.
' - The Results browser is populated ONCE per mode (over all elements); each
'   group's sum uses GetColumnSum's set-limit argument (fast).
' - Warns if the selected groups don't cover all model elements (totals < 100%)
'   or overlap (totals > 100%).
'
' Requires Element Strain Energy + Element Kinetic Energy output from the modal
' run (SOL 103) with PARAM,TINY,1.-20 so every element reports energy.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim m As Long, g As Long, i As Long

    ' ============================================================
    ' Section 1: Select output sets (modes) and element groups
    ' ============================================================
    Dim oset As femap.Set
    Set oset = App.feSet
    rc = oset.Select(FT_OUT_CASE, True, "Select output sets (modes) to process")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim nSets As Long
    nSets = oset.Count
    If nSets = 0 Then
        App.feAppMessage(FCM_ERROR, "No output sets selected")
        Exit Sub
    End If
    Dim osetIDs() As Long
    ReDim osetIDs(nSets - 1)
    Dim sid As Long
    i = 0
    sid = oset.First()
    Do While sid > 0
        osetIDs(i) = sid
        i = i + 1
        sid = oset.Next()
    Loop

    Dim gset As femap.Set
    Set gset = App.feSet
    rc = gset.Select(FT_GROUP, True, "Select element group(s) to process")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim nGroups As Long
    nGroups = gset.Count
    If nGroups = 0 Then
        App.feAppMessage(FCM_ERROR, "No groups selected")
        Exit Sub
    End If
    Dim grpIDs() As Long, grpTitles() As String
    ReDim grpIDs(nGroups - 1)
    ReDim grpTitles(nGroups - 1)
    Dim gid As Long
    i = 0
    gid = gset.First()
    Do While gid > 0
        grpIDs(i) = gid
        i = i + 1
        gid = gset.Next()
    Loop
    Dim gp As femap.Group
    Set gp = App.feGroup
    For g = 0 To nGroups - 1
        gp.Get(grpIDs(g))
        grpTitles(g) = gp.title
    Next g

    ' ============================================================
    ' Section 2: Resolve ESE% / EKE% output vectors at runtime
    ' ============================================================
    Dim riq As Object
    Set riq = App.feResultsIDQuery
    Dim eseID As Long, ekeID As Long
    eseID = riq.Elemental(1)    ' VEO_STRAIN_ENERGY_PERCENT
    ekeID = riq.Elemental(30)   ' VEO_KINETIC_ENERGY_PERCENT
    If eseID <= 0 Then eseID = riq.Find(osetIDs(0), "Strain Energy Percent")
    If ekeID <= 0 Then ekeID = riq.Find(osetIDs(0), "Kinetic Energy Percent")
    If eseID <= 0 Or ekeID <= 0 Then
        App.feAppMessage(FCM_ERROR, "Could not find ESE % / EKE % output vectors in the results.")
        App.feAppMessage(FCM_ERROR, "Request Element Strain Energy + Element Kinetic Energy (PARAM,TINY,1.-20) in the SOL 103 run.")
        Exit Sub
    End If

    ' ============================================================
    ' Section 3: Coverage / overlap check
    ' ============================================================
    Dim allSet As femap.Set
    Set allSet = App.feSet
    allSet.AddAll(FT_ELEM)
    Dim totalElem As Long
    totalElem = allSet.Count

    Dim unionSet As femap.Set
    Set unionSet = App.feSet
    Dim tmpSet As femap.Set
    Set tmpSet = App.feSet
    Dim sumPerGroup As Long
    sumPerGroup = 0
    For g = 0 To nGroups - 1
        tmpSet.Clear()
        tmpSet.AddGroup(FT_ELEM, grpIDs(g))
        sumPerGroup = sumPerGroup + tmpSet.Count
        unionSet.AddGroup(FT_ELEM, grpIDs(g))
    Next g
    Dim coveredElem As Long, uncovered As Long, overlapDup As Long
    coveredElem = unionSet.Count
    uncovered = totalElem - coveredElem
    overlapDup = sumPerGroup - coveredElem

    If uncovered > 0 Or overlapDup > 0 Then
        Dim wmsg As String
        wmsg = ""
        If uncovered > 0 Then
            wmsg = wmsg + Trim$(Str$(uncovered)) + " of " + Trim$(Str$(totalElem)) _
                + " model elements are NOT in any selected group (per-mode totals will read < 100%)." + Chr$(10)
        End If
        If overlapDup > 0 Then
            wmsg = wmsg + Trim$(Str$(overlapDup)) + " element(s) appear in more than one selected group" _
                + " (totals may exceed 100%)." + Chr$(10)
        End If
        wmsg = wmsg + Chr$(10) + "Continue anyway?"
        If MsgBox(wmsg, vbOKCancel + vbExclamation, "Mode Identification (ESE EKE) - Coverage check") <> vbOK Then
            App.feAppMessage(FCM_WARNING, "Cancelled at coverage check - nothing written")
            Exit Sub
        End If
    End If

    ' ============================================================
    ' Section 4: Open Excel (late bound) + sheets
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
    wsD.Name = "Energy by Group"

    ' ============================================================
    ' Section 5: Column layout + headers
    ' ============================================================
    Dim eseStart As Long, eseTotalCol As Long, ekeStart As Long, ekeTotalCol As Long
    eseStart = 4
    eseTotalCol = eseStart + nGroups        ' first group col + nGroups
    ekeStart = eseTotalCol + 2              ' one gap column after ESE Total
    ekeTotalCol = ekeStart + nGroups

    wsD.Cells(1, 1).Value = "Mode Identification (ESE EKE)  (% of model total, per mode)"
    wsD.Cells(3, 1).Value = "Output Set #"
    wsD.Cells(3, 2).Value = "Title"
    wsD.Cells(3, 3).Value = "Freq [Hz]"
    wsD.Cells(2, eseStart).Value = "Element Strain Energy %  (by group)"
    wsD.Cells(2, ekeStart).Value = "Element Kinetic Energy %  (by group)"
    For g = 0 To nGroups - 1
        wsD.Cells(3, eseStart + g).Value = grpIDs(g)
        wsD.Cells(4, eseStart + g).Value = grpTitles(g)
        wsD.Cells(3, ekeStart + g).Value = grpIDs(g)
        wsD.Cells(4, ekeStart + g).Value = grpTitles(g)
    Next g
    wsD.Cells(3, eseTotalCol).Value = "Total"
    wsD.Cells(3, ekeTotalCol).Value = "Total"

    ' ============================================================
    ' Section 6: Build the matrix - one Populate per mode
    ' ============================================================
    Dim rbo As femap.Results
    Set rbo = App.feResults
    Dim os As femap.OutputSet
    Set os = App.feOutputSet
    Dim eset As femap.Set
    Set eset = App.feSet

    Dim nAddedE As Long, nAddedK As Long
    Dim vIdxE As Variant, vIdxK As Variant
    Dim eseCol As Long, ekeCol As Long
    Dim nNumVal As Long
    Dim eseSum As Double, ekeSum As Double, dSq As Double
    Dim rowD As Long
    Dim fmla As String
    fmla = "=SUM(RC[-" + Trim$(Str$(nGroups)) + "]:RC[-1])"

    App.feAppStatusShow(True, nSets)
    For m = 0 To nSets - 1
        rowD = 5 + m
        os.Get(osetIDs(m))
        wsD.Cells(rowD, 1).Value = osetIDs(m)
        wsD.Cells(rowD, 2).Value = os.title
        wsD.Cells(rowD, 3).Value = os.value

        rbo.Clear()
        rbo.DataNeeded(8, 0)                 ' 8 = elements, 0 = all
        rbo.AddColumnV2(osetIDs(m), eseID, False, nAddedE, vIdxE)
        rbo.AddColumnV2(osetIDs(m), ekeID, False, nAddedK, vIdxK)
        rbo.Populate
        eseCol = CLng(vIdxE(0))
        ekeCol = CLng(vIdxK(0))

        For g = 0 To nGroups - 1
            eset.Clear()
            eset.AddGroup(FT_ELEM, grpIDs(g))
            rbo.GetColumnSum(eseCol, eset.ID, nNumVal, eseSum, dSq)
            rbo.GetColumnSum(ekeCol, eset.ID, nNumVal, ekeSum, dSq)
            wsD.Cells(rowD, eseStart + g).Value = eseSum
            wsD.Cells(rowD, ekeStart + g).Value = ekeSum
        Next g
        wsD.Cells(rowD, eseTotalCol).FormulaR1C1 = fmla
        wsD.Cells(rowD, ekeTotalCol).FormulaR1C1 = fmla

        App.feAppStatusUpdate(m + 1)
        App.feAppStatusRedraw()
    Next m
    App.feAppStatusShow(False, 0)

    ' ============================================================
    ' Section 7: Formatting
    ' ============================================================
    Dim lastRow As Long
    lastRow = 4 + nSets
    ' number format (freq + both energy blocks incl. totals)
    wsD.Range(wsD.Cells(5, 3), wsD.Cells(lastRow, ekeTotalCol)).NumberFormat = "0.00"
    ' data bars: red on ESE group columns, green on EKE group columns
    wsD.Range(wsD.Cells(5, eseStart), wsD.Cells(lastRow, eseStart + nGroups - 1)).FormatConditions.AddDatabar.BarColor.Color = RGB(220, 80, 80)
    wsD.Range(wsD.Cells(5, ekeStart), wsD.Cells(lastRow, ekeStart + nGroups - 1)).FormatConditions.AddDatabar.BarColor.Color = RGB(80, 170, 90)
    ' vertical group-title headers
    wsD.Range(wsD.Cells(4, eseStart), wsD.Cells(4, eseStart + nGroups - 1)).Orientation = 90
    wsD.Range(wsD.Cells(4, ekeStart), wsD.Cells(4, ekeStart + nGroups - 1)).Orientation = 90
    ' center + bold headers
    wsD.UsedRange.HorizontalAlignment = -4108        ' xlCenter
    wsD.Rows("1:4").Font.Bold = True
    wsD.UsedRange.Columns.AutoFit

    ' ============================================================
    ' Section 8: README sheet
    ' ============================================================
    wsR.Cells(1, 1).Value = "Mode Identification (ESE EKE)"
    wsR.Cells(3, 1).Value = "Model:"
    wsR.Cells(3, 2).Value = App.ModelName
    wsR.Cells(4, 1).Value = "User:"
    wsR.Cells(4, 2).Value = appExcel.UserName
    wsR.Cells(5, 1).Value = "Date:"
    wsR.Cells(5, 2).Value = Now
    wsR.Cells(7, 1).Value = "ESE % vector ID:"
    wsR.Cells(7, 2).Value = eseID
    wsR.Cells(8, 1).Value = "EKE % vector ID:"
    wsR.Cells(8, 2).Value = ekeID
    wsR.Cells(9, 1).Value = "Output sets (modes):"
    wsR.Cells(9, 2).Value = nSets
    wsR.Cells(10, 1).Value = "Groups:"
    wsR.Cells(10, 2).Value = nGroups
    wsR.Cells(11, 1).Value = "Model elements:"
    wsR.Cells(11, 2).Value = totalElem
    wsR.Cells(12, 1).Value = "Covered by groups:"
    wsR.Cells(12, 2).Value = coveredElem
    wsR.Cells(13, 1).Value = "Uncovered elements:"
    wsR.Cells(13, 2).Value = uncovered
    wsR.Cells(14, 1).Value = "Elements in >1 group:"
    wsR.Cells(14, 2).Value = overlapDup
    wsR.Cells(16, 1).Value = "Note:"
    wsR.Cells(16, 2).Value = "ESE/EKE are % of model total per mode; each mode's group Total is ~100% only if the selected groups partition the model."
    wsR.Rows("1:1").Font.Bold = True
    wsR.UsedRange.Columns.AutoFit

    ' ============================================================
    ' Section 9: Finish
    ' ============================================================
    appExcel.Visible = True
    App.feAppMessage(FCM_NORMAL, "Mode Identification (ESE EKE): wrote " + Trim$(Str$(nSets)) _
        + " modes x " + Trim$(Str$(nGroups)) + " groups to Excel. ESE% vec " _
        + Trim$(Str$(eseID)) + ", EKE% vec " + Trim$(Str$(ekeID)) + ".")
End Sub
