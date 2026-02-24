' renumber-groups.bas
' Renumbers all entities (nodes, elements, csys, materials, properties) in
' selected groups into non-overlapping ID ranges with growth buffer.
' Uses Excel spreadsheet for interactive confirmation and editing.

Const NUM_TYPES = 5

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Group Selection
    ' =============================================
    Dim groupSet As femap.Set
    Set groupSet = App.feSet

    rc = groupSet.Select(FT_GROUP, True, "Select Groups to Renumber")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No groups selected - exiting")
        Exit Sub
    End If

    If groupSet.Count < 1 Then
        App.feAppMessage(FCM_ERROR, "Must select at least 1 group - exiting")
        Exit Sub
    End If

    Dim numGroups As Long
    numGroups = groupSet.Count
    Dim groupIDs() As Long
    Dim groupTitles() As String
    ReDim groupIDs(numGroups - 1)
    ReDim groupTitles(numGroups - 1)

    Dim gp As femap.Group
    Set gp = App.feGroup
    Dim gpID As Long
    Dim idx As Long
    idx = 0

    gpID = groupSet.First()
    Do While gpID > 0
        groupIDs(idx) = gpID
        rc = gp.Get(gpID)
        If rc = FE_OK Then
            groupTitles(idx) = gp.title
        Else
            groupTitles(idx) = "Group " + Str$(gpID)
        End If
        idx = idx + 1
        gpID = groupSet.Next()
    Loop

    ' =============================================
    ' Section 2: Count Entities Per Group
    ' =============================================
    ' listTypes for gp.List(), allFtTypes for Set.AddAll/feRenumberOpt2
    '   CSys:     list=0,  ft=FT_CSYS(9)
    '   Material: list=9,  ft=FT_MATL(10)
    '   Property: list=10, ft=FT_PROP(11)
    '   Element:  list=8,  ft=FT_ELEM(8)
    '   Node:     list=7,  ft=FT_NODE(7)
    Dim listTypes(4) As Long
    listTypes(0) = 0   ' CSys
    listTypes(1) = 9   ' Material
    listTypes(2) = 10  ' Property
    listTypes(3) = 8   ' Element
    listTypes(4) = 7   ' Node

    Dim allFtTypes(4) As Long
    allFtTypes(0) = FT_CSYS
    allFtTypes(1) = FT_MATL
    allFtTypes(2) = FT_PROP
    allFtTypes(3) = FT_ELEM
    allFtTypes(4) = FT_NODE

    Dim typeLabels(4) As String
    typeLabels(0) = "CSys"
    typeLabels(1) = "Matl"
    typeLabels(2) = "Prop"
    typeLabels(3) = "Elem"
    typeLabels(4) = "Node"

    Dim entityCounts() As Long
    Dim maxCount() As Long
    ReDim entityCounts(numGroups - 1, NUM_TYPES - 1)
    ReDim maxCount(numGroups - 1)

    Dim copySet As femap.Set
    Set copySet = App.feSet

    Dim g As Long
    Dim t As Long

    For g = 0 To numGroups - 1
        maxCount(g) = 0
        For t = 0 To NUM_TYPES - 1
            rc = gp.Get(groupIDs(g))
            If rc <> FE_OK Then
                entityCounts(g, t) = 0
                GoTo NextType
            End If

            Dim entSet As femap.Set
            Set entSet = gp.List(listTypes(t))
            If entSet Is Nothing Then
                entityCounts(g, t) = 0
            Else
                ' Copy to avoid stale ref
                copySet.Clear()
                copySet.AddSet(entSet.ID)
                entityCounts(g, t) = copySet.Count
            End If

            If entityCounts(g, t) > maxCount(g) Then
                maxCount(g) = entityCounts(g, t)
            End If
NextType:
        Next t
    Next g

    ' =============================================
    ' Section 3: Calculate Range Sizes
    ' =============================================
    Dim rangeSize() As Long
    Dim startIDs() As Long
    ReDim rangeSize(numGroups - 1)
    ReDim startIDs(numGroups - 1)

    ' Range size per group: maxCount * 1.5 rounded up to nearest 1000, min 1000
    For g = 0 To numGroups - 1
        If maxCount(g) = 0 Then
            rangeSize(g) = 1000
        Else
            rangeSize(g) = Int((maxCount(g) * 1.5) / 1000 + 0.999) * 1000
            If rangeSize(g) < 1000 Then rangeSize(g) = 1000
        End If
    Next g

    ' =============================================
    ' Section 4: Excel Confirmation
    ' =============================================
    Dim xlApp As Object
    Dim xlWB As Object
    Dim ws As Object

    On Error Resume Next
    Set xlApp = CreateObject("Excel.Application")
    If xlApp Is Nothing Then
        On Error GoTo 0
        App.feAppMessage(FCM_ERROR, "Failed to open Excel - exiting")
        Exit Sub
    End If
    On Error GoTo 0

    xlApp.Visible = True
    Set xlWB = xlApp.Workbooks.Add
    Set ws = xlWB.Sheets(1)
    ws.Name = "Renumber Groups"

    ' -- Headers --
    ws.Cells(1, 1).Value = "Group Name"
    ws.Cells(1, 2).Value = "CSys"
    ws.Cells(1, 3).Value = "Matl"
    ws.Cells(1, 4).Value = "Prop"
    ws.Cells(1, 5).Value = "Elem"
    ws.Cells(1, 6).Value = "Node"
    ws.Cells(1, 7).Value = "Max"
    ws.Cells(1, 8).Value = "Start ID"
    ws.Cells(1, 9).Value = "End ID"
    ws.Cells(1, 10).Value = "Range Size"

    ' Bold headers
    ws.Range("A1:J1").Font.Bold = True

    ' -- Data rows --
    For g = 0 To numGroups - 1
        Dim r As Long
        r = g + 2  ' Row index (1-based, row 1 = headers)

        ws.Cells(r, 1).Value = groupTitles(g)
        ws.Cells(r, 2).Value = entityCounts(g, 0)  ' CSys
        ws.Cells(r, 3).Value = entityCounts(g, 1)  ' Matl
        ws.Cells(r, 4).Value = entityCounts(g, 2)  ' Prop
        ws.Cells(r, 5).Value = entityCounts(g, 3)  ' Elem
        ws.Cells(r, 6).Value = entityCounts(g, 4)  ' Node
        ws.Cells(r, 7).Value = maxCount(g)

        ' Start ID: first row = 100000, subsequent rows = formula chaining
        If g = 0 Then
            ws.Cells(r, 8).Value = 100000
        Else
            ws.Cells(r, 8).Formula = "=H" & CStr(r - 1) & "+J" & CStr(r - 1)
        End If

        ' End ID: formula = Start ID + Range Size - 1
        ws.Cells(r, 9).Formula = "=H" & CStr(r) & "+J" & CStr(r) & "-1"

        ' Range Size: pre-filled with calculated value
        ws.Cells(r, 10).Value = rangeSize(g)
    Next g

    ' -- Formatting --
    ' Yellow background for editable Start ID column (H)
    Dim lastRow As Long
    lastRow = numGroups + 1
    ws.Range("H2:H" & CStr(lastRow)).Interior.Color = RGB(255, 255, 153)
    ' Light yellow for editable Range Size column (J)
    ws.Range("J2:J" & CStr(lastRow)).Interior.Color = RGB(255, 255, 204)

    ' Auto-fit columns
    ws.Columns("A:J").AutoFit

    ' -- Sheet protection: lock all except H and J --
    ws.Columns("H").Locked = False
    ws.Columns("J").Locked = False
    ws.Protect Password:=""

    ' -- Wait for user --
    Dim msgResult As Long
    msgResult = MsgBox("Edit Start IDs (yellow) and Range Sizes (light yellow) in Excel," & _
        Chr$(10) & "then click OK to proceed or Cancel to abort.", _
        vbOKCancel + vbInformation, "Renumber Groups")

    ' -- Read back values --
    Dim xlClosed As Boolean
    xlClosed = False

    If msgResult <> vbOK Then
        ' User cancelled
        On Error Resume Next
        xlWB.Close False
        xlApp.Quit
        Set ws = Nothing
        Set xlWB = Nothing
        Set xlApp = Nothing
        On Error GoTo 0
        App.feAppMessage(FCM_WARNING, "Cancelled by user - exiting")
        Exit Sub
    End If

    ' Check that Excel is still open before reading
    On Error Resume Next
    Dim testVal As Variant
    testVal = ws.Cells(1, 1).Value
    If Err.Number <> 0 Then
        xlClosed = True
    End If
    On Error GoTo 0

    If xlClosed Then
        Set ws = Nothing
        Set xlWB = Nothing
        Set xlApp = Nothing
        App.feAppMessage(FCM_ERROR, "Excel was closed before values could be read - exiting")
        Exit Sub
    End If

    ' Read Start IDs and Range Sizes from Excel
    For g = 0 To numGroups - 1
        startIDs(g) = CLng(ws.Cells(g + 2, 8).Value)   ' Column H
        rangeSize(g) = CLng(ws.Cells(g + 2, 10).Value)  ' Column J
    Next g

    ' Close Excel
    On Error Resume Next
    xlWB.Close False
    xlApp.Quit
    On Error GoTo 0
    Set ws = Nothing
    Set xlWB = Nothing
    Set xlApp = Nothing

    ' -- Conflict check --
    Dim conflictText As String
    conflictText = ""
    Dim conflictCount As Long
    conflictCount = 0

    Dim allEntSet As femap.Set
    Set allEntSet = App.feSet
    Dim rangeCheckSet As femap.Set
    Set rangeCheckSet = App.feSet
    Dim checkSet As femap.Set
    Set checkSet = App.feSet

    For t = 0 To NUM_TYPES - 1
        ' Get all entities of this type in the model
        allEntSet.Clear()
        allEntSet.AddAll(allFtTypes(t))
        If allEntSet.Count = 0 Then GoTo NextConflictType

        ' Remove entities that belong to any selected group
        For g = 0 To numGroups - 1
            rc = gp.Get(groupIDs(g))
            If rc = FE_OK Then
                Dim gpEntSet As femap.Set
                Set gpEntSet = gp.List(listTypes(t))
                If Not gpEntSet Is Nothing Then
                    copySet.Clear()
                    copySet.AddSet(gpEntSet.ID)
                    allEntSet.RemoveSet(copySet.ID)
                End If
            End If
        Next g

        ' allEntSet now contains only entities outside the selected groups
        ' Check each target range for overlap
        If allEntSet.Count > 0 Then
            For g = 0 To numGroups - 1
                rangeCheckSet.Clear()
                rangeCheckSet.AddRange(startIDs(g), 1, startIDs(g) + rangeSize(g) - 1)
                checkSet.Clear()
                checkSet.AddSet(allEntSet.ID)
                checkSet.RemoveNotCommon(rangeCheckSet.ID)
                If checkSet.Count > 0 Then
                    If conflictCount > 0 Then conflictText = conflictText + Chr$(10)
                    conflictText = conflictText + "WARNING:" + Str$(checkSet.Count) + _
                        " " + typeLabels(t) + " in range" + _
                        Str$(startIDs(g)) + " -" + Str$(startIDs(g) + rangeSize(g) - 1)
                    conflictCount = conflictCount + 1
                End If
            Next g
        End If
NextConflictType:
    Next t

    ' -- Confirmation MsgBox --
    Dim totalEntities As Long
    totalEntities = 0
    For g = 0 To numGroups - 1
        For t = 0 To NUM_TYPES - 1
            totalEntities = totalEntities + entityCounts(g, t)
        Next t
    Next g

    Dim confirmMsg As String
    Dim confirmStyle As Long
    If conflictCount = 0 Then
        confirmMsg = Str$(numGroups) + " groups," + Str$(totalEntities) + " entities." + _
            Chr$(10) + "No conflicts with existing IDs." + _
            Chr$(10) + Chr$(10) + "Proceed with renumbering?"
        confirmStyle = vbOKCancel + vbInformation
    Else
        confirmMsg = Str$(numGroups) + " groups," + Str$(totalEntities) + " entities." + _
            Chr$(10) + Chr$(10) + conflictText + _
            Chr$(10) + Chr$(10) + "Proceed anyway?"
        confirmStyle = vbOKCancel + vbExclamation
    End If

    If MsgBox(confirmMsg, confirmStyle, "Renumber Groups - Confirm") <> vbOK Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - exiting")
        Exit Sub
    End If

    ' =============================================
    ' Section 5: Renumber
    ' =============================================
    ' Order: CSys(0) -> Materials(1) -> Properties(2) -> Elements(3) -> Nodes(4)
    Dim xyzOrder(2) As Long
    xyzOrder(0) = 0
    xyzOrder(1) = 0
    xyzOrder(2) = 0

    Dim workSet As femap.Set
    Set workSet = App.feSet

    Dim renumCounts() As Long
    ReDim renumCounts(numGroups - 1, NUM_TYPES - 1)

    For g = 0 To numGroups - 1
        For t = 0 To NUM_TYPES - 1
            renumCounts(g, t) = 0

            ' Get entity set from group (must re-get each time due to stale ref)
            rc = gp.Get(groupIDs(g))
            If rc <> FE_OK Then GoTo NextRenum

            Dim renumEntSet As femap.Set
            Set renumEntSet = gp.List(listTypes(t))
            If renumEntSet Is Nothing Then GoTo NextRenum

            ' Copy to working set (stale-ref pattern)
            workSet.Clear()
            workSet.AddSet(renumEntSet.ID)
            If workSet.Count = 0 Then GoTo NextRenum

            renumCounts(g, t) = workSet.Count

            rc = App.feRenumberOpt2(allFtTypes(t), workSet.ID, startIDs(g), _
                0, 0, False, False, False, xyzOrder)
NextRenum:
        Next t
    Next g

    App.feViewRegenerate(0)

    ' =============================================
    ' Section 6: Report Results
    ' =============================================
    Dim reportLabels(4) As String
    reportLabels(0) = "CSys"
    reportLabels(1) = "Materials"
    reportLabels(2) = "Properties"
    reportLabels(3) = "Elements"
    reportLabels(4) = "Nodes"

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Renumber Groups - Results")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

    For g = 0 To numGroups - 1
        App.feAppMessage(FCM_HIGHLIGHT, "  """ + groupTitles(g) + """ (start ID:" + Str$(startIDs(g)) + ")")

        Dim grpRenumTotal As Long
        grpRenumTotal = 0
        For t = 0 To NUM_TYPES - 1
            grpRenumTotal = grpRenumTotal + renumCounts(g, t)
            If renumCounts(g, t) > 0 Then
                Dim labelPad As String
                labelPad = reportLabels(t) + ":"
                Do While Len(labelPad) < 16
                    labelPad = labelPad + " "
                Loop
                App.feAppMessage(FCM_NORMAL, "    " + labelPad + Str$(renumCounts(g, t)) + " renumbered")
            End If
        Next t

        If grpRenumTotal = 0 Then
            App.feAppMessage(FCM_NORMAL, "    (no entities)")
        End If
    Next g

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_HIGHLIGHT, "  Total:" + Str$(totalEntities) + " entities renumbered")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
