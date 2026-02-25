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

    Dim curMinID() As Long
    Dim curMaxID() As Long
    ReDim curMinID(numGroups - 1)
    ReDim curMaxID(numGroups - 1)

    Dim copySet As femap.Set
    Set copySet = App.feSet

    Dim g As Long
    Dim t As Long

    For g = 0 To numGroups - 1
        maxCount(g) = 0
        curMinID(g) = 2147483647
        curMaxID(g) = 0
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

                ' Track min/max IDs across all entity types
                If copySet.Count > 0 Then
                    Dim firstID As Long, lastID As Long, curID As Long
                    firstID = copySet.First()
                    If firstID < curMinID(g) Then curMinID(g) = firstID
                    lastID = firstID
                    curID = copySet.Next()
                    Do While curID > 0
                        lastID = curID
                        curID = copySet.Next()
                    Loop
                    If lastID > curMaxID(g) Then curMaxID(g) = lastID
                End If
            End If

            If entityCounts(g, t) > maxCount(g) Then
                maxCount(g) = entityCounts(g, t)
            End If
NextType:
        Next t

        ' Clean up sentinel for empty groups
        If curMaxID(g) = 0 Then curMinID(g) = 0
    Next g

    ' =============================================
    ' Section 2a: Detect Overlapping Groups
    ' =============================================
    If numGroups > 1 Then
        Dim overlapSet As femap.Set
        Set overlapSet = App.feSet
        Dim setA As femap.Set
        Set setA = App.feSet
        Dim overlapText As String
        overlapText = ""
        Dim overlapCount As Long
        overlapCount = 0

        Dim g1 As Long
        Dim g2 As Long
        For t = 0 To NUM_TYPES - 1
            For g1 = 0 To numGroups - 2
                For g2 = g1 + 1 To numGroups - 1
                    ' Get g1's entity set
                    rc = gp.Get(groupIDs(g1))
                    If rc <> FE_OK Then GoTo NextPair
                    Dim g1EntSet As femap.Set
                    Set g1EntSet = gp.List(listTypes(t))
                    If g1EntSet Is Nothing Then GoTo NextPair
                    setA.Clear()
                    setA.AddSet(g1EntSet.ID)
                    If setA.Count = 0 Then GoTo NextPair

                    ' Get g2's entity set
                    rc = gp.Get(groupIDs(g2))
                    If rc <> FE_OK Then GoTo NextPair
                    Dim g2EntSet As femap.Set
                    Set g2EntSet = gp.List(listTypes(t))
                    If g2EntSet Is Nothing Then GoTo NextPair
                    overlapSet.Clear()
                    overlapSet.AddSet(g2EntSet.ID)
                    If overlapSet.Count = 0 Then GoTo NextPair

                    ' Intersect to find shared entities
                    setA.RemoveNotCommon(overlapSet.ID)
                    If setA.Count > 0 Then
                        overlapText = overlapText + "  """ + groupTitles(g1) + """ and """ + _
                            groupTitles(g2) + """ share" + Str$(setA.Count) + " " + _
                            typeLabels(t) + Chr$(10)
                        overlapCount = overlapCount + 1
                    End If
NextPair:
                Next g2
            Next g1
        Next t

        If overlapCount > 0 Then
            App.feAppMessage(FCM_ERROR, "========================================")
            App.feAppMessage(FCM_ERROR, "  Renumber Groups - Overlap Detected")
            App.feAppMessage(FCM_ERROR, "========================================")

            ' Print each overlap line to message pane
            Dim olLines() As String
            olLines = Split(overlapText, Chr$(10))
            Dim olIdx As Long
            For olIdx = 0 To UBound(olLines)
                If Len(olLines(olIdx)) > 0 Then
                    App.feAppMessage(FCM_ERROR, olLines(olIdx))
                End If
            Next olIdx

            App.feAppMessage(FCM_ERROR, "========================================")

            MsgBox "Overlapping groups detected - cannot renumber." & Chr$(10) & Chr$(10) & _
                overlapText & Chr$(10) & _
                "Remove shared entities so each entity belongs to only one group.", _
                vbOKOnly + vbCritical, "Renumber Groups - Overlap Detected"
            Exit Sub
        End If
    End If

    ' =============================================
    ' Section 2.5: Partition Groups into Large/Small
    ' =============================================
    Dim sortOrder() As Long
    ReDim sortOrder(numGroups - 1)
    Dim numLarge As Long, numSmall As Long
    numLarge = 0
    numSmall = 0

    ' First pass: collect small groups (max <= 100)
    For g = 0 To numGroups - 1
        If maxCount(g) <= 100 Then
            sortOrder(numSmall) = g
            numSmall = numSmall + 1
        End If
    Next g

    ' Second pass: collect large groups (max > 100)
    For g = 0 To numGroups - 1
        If maxCount(g) > 100 Then
            sortOrder(numSmall + numLarge) = g
            numLarge = numLarge + 1
        End If
    Next g

    ' =============================================
    ' Section 3: Calculate Range Sizes
    ' =============================================
    Dim rangeSize() As Long
    Dim startIDs() As Long
    ReDim rangeSize(numGroups - 1)
    ReDim startIDs(numGroups - 1)

    ' Range size per group: large rounds to nearest 1000, small to nearest 100
    For g = 0 To numGroups - 1
        If maxCount(g) > 100 Then
            ' Large: round up to nearest 1000, min 1000
            rangeSize(g) = Int((maxCount(g) * 1.5) / 1000 + 0.999) * 1000
            If rangeSize(g) < 1000 Then rangeSize(g) = 1000
        Else
            ' Small: round up to nearest 100, min 100
            If maxCount(g) = 0 Then
                rangeSize(g) = 100
            Else
                rangeSize(g) = Int((maxCount(g) * 1.5) / 100 + 0.999) * 100
                If rangeSize(g) < 100 Then rangeSize(g) = 100
            End If
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
    App.feAppMessage(FCM_NORMAL, "Building Excel spreadsheet, please wait...")
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
    ws.Cells(1, 8).Value = "Cur Min"
    ws.Cells(1, 9).Value = "Cur Max"
    ws.Cells(1, 10).Value = "Start ID"
    ws.Cells(1, 11).Value = "End ID"
    ws.Cells(1, 12).Value = "Range Size"
    ws.Cells(1, 13).Value = "Headroom"

    ' Bold headers
    ws.Range("A1:M1").Font.Bold = True

    ' -- Data rows (two sections: small then large) --
    Dim curRow As Long
    curRow = 1  ' Start after headers
    Dim excelRows() As Long
    ReDim excelRows(numGroups - 1)
    Dim i As Long
    Dim gi As Long

    ' -- Small groups section --
    If numSmall > 0 Then
        curRow = curRow + 1
        ws.Range("A" & CStr(curRow) & ":M" & CStr(curRow)).Merge
        ws.Cells(curRow, 1).Value = "Small Groups (max <= 100)"
        ws.Cells(curRow, 1).Font.Bold = True
        ws.Cells(curRow, 1).Interior.Color = RGB(217, 217, 217)

        For i = 0 To numSmall - 1
            curRow = curRow + 1
            excelRows(i) = curRow
            gi = sortOrder(i)

            ws.Cells(curRow, 1).Value = groupTitles(gi)
            ws.Cells(curRow, 2).Value = entityCounts(gi, 0)
            ws.Cells(curRow, 3).Value = entityCounts(gi, 1)
            ws.Cells(curRow, 4).Value = entityCounts(gi, 2)
            ws.Cells(curRow, 5).Value = entityCounts(gi, 3)
            ws.Cells(curRow, 6).Value = entityCounts(gi, 4)
            ws.Cells(curRow, 7).Value = maxCount(gi)
            ws.Cells(curRow, 8).Value = curMinID(gi)
            ws.Cells(curRow, 9).Value = curMaxID(gi)

            If i = 0 Then
                ws.Cells(curRow, 10).Value = 1
            Else
                ws.Cells(curRow, 10).Formula = "=J" & CStr(curRow - 1) & "+L" & CStr(curRow - 1)
            End If

            ws.Cells(curRow, 11).Formula = "=J" & CStr(curRow) & "+L" & CStr(curRow) & "-1"
            ws.Cells(curRow, 12).Value = rangeSize(gi)
            ws.Cells(curRow, 10).Interior.Color = RGB(255, 255, 153)
            ws.Cells(curRow, 12).Interior.Color = RGB(255, 255, 204)
        Next i
    End If

    ' -- Large groups section --
    If numLarge > 0 Then
        If numSmall > 0 Then curRow = curRow + 1  ' Blank separator row

        curRow = curRow + 1
        ws.Range("A" & CStr(curRow) & ":M" & CStr(curRow)).Merge
        ws.Cells(curRow, 1).Value = "Large Groups (max > 100)"
        ws.Cells(curRow, 1).Font.Bold = True
        ws.Cells(curRow, 1).Interior.Color = RGB(217, 217, 217)

        For i = numSmall To numGroups - 1
            curRow = curRow + 1
            excelRows(i) = curRow
            gi = sortOrder(i)

            ws.Cells(curRow, 1).Value = groupTitles(gi)
            ws.Cells(curRow, 2).Value = entityCounts(gi, 0)
            ws.Cells(curRow, 3).Value = entityCounts(gi, 1)
            ws.Cells(curRow, 4).Value = entityCounts(gi, 2)
            ws.Cells(curRow, 5).Value = entityCounts(gi, 3)
            ws.Cells(curRow, 6).Value = entityCounts(gi, 4)
            ws.Cells(curRow, 7).Value = maxCount(gi)
            ws.Cells(curRow, 8).Value = curMinID(gi)
            ws.Cells(curRow, 9).Value = curMaxID(gi)

            If i = numSmall Then
                ws.Cells(curRow, 10).Value = 100001
            Else
                ws.Cells(curRow, 10).Formula = "=J" & CStr(curRow - 1) & "+L" & CStr(curRow - 1)
            End If

            ws.Cells(curRow, 11).Formula = "=J" & CStr(curRow) & "+L" & CStr(curRow) & "-1"
            ws.Cells(curRow, 12).Value = rangeSize(gi)
            ws.Cells(curRow, 10).Interior.Color = RGB(255, 255, 153)
            ws.Cells(curRow, 12).Interior.Color = RGB(255, 255, 204)
        Next i
    End If

    ' -- Headroom formulas: unused IDs within allotted range (Range Size - Max Count) --
    For i = 0 To numGroups - 1
        ws.Cells(excelRows(i), 13).Formula = "=L" & CStr(excelRows(i)) & "-G" & CStr(excelRows(i))
    Next i

    ' -- Formatting --
    ' Auto-fit columns
    ws.Columns("A:M").AutoFit

    ' -- Sheet protection: lock all except data cells in J and L --
    Dim er As Long
    For er = 0 To numGroups - 1
        ws.Cells(excelRows(er), 10).Locked = False  ' Start ID
        ws.Cells(excelRows(er), 12).Locked = False  ' Range Size
    Next er
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

    ' Read Start IDs and Range Sizes from Excel (map sorted rows back to original indices)
    For i = 0 To numGroups - 1
        gi = sortOrder(i)
        startIDs(gi) = CLng(ws.Cells(excelRows(i), 10).Value)  ' Column J
        rangeSize(gi) = CLng(ws.Cells(excelRows(i), 12).Value)  ' Column L
    Next i

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

    ' Check for overlapping ranges between selected groups
    For g = 0 To numGroups - 2
        For g2 = g + 1 To numGroups - 1
            If startIDs(g) < startIDs(g2) + rangeSize(g2) And _
               startIDs(g2) < startIDs(g) + rangeSize(g) Then
                If conflictCount > 0 Then conflictText = conflictText + Chr$(10)
                conflictText = conflictText + "WARNING: """ + groupTitles(g) + """ and """ + _
                    groupTitles(g2) + """ ranges overlap"
                conflictCount = conflictCount + 1
            End If
        Next g2
    Next g

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

    ' --- Pass 1: Evacuate all groups to temp range to clear target ranges ---
    Const TEMP_BASE = 900000000
    Dim tempOffset As Long
    tempOffset = 0

    App.feAppLock()
    For g = 0 To numGroups - 1
        For t = 0 To NUM_TYPES - 1
            rc = gp.Get(groupIDs(g))
            If rc <> FE_OK Then GoTo NextEvac

            Dim evacEntSet As femap.Set
            Set evacEntSet = gp.List(listTypes(t))
            If evacEntSet Is Nothing Then GoTo NextEvac

            workSet.Clear()
            workSet.AddSet(evacEntSet.ID)
            If workSet.Count = 0 Then GoTo NextEvac

            rc = App.feRenumberOpt2(allFtTypes(t), workSet.ID, TEMP_BASE + tempOffset, _
                0, 0, False, False, False, xyzOrder)
NextEvac:
        Next t
        tempOffset = tempOffset + rangeSize(g)
    Next g
    App.feAppUnlock()

    ' --- Pass 2: Place each group at its target start ID ---
    App.feAppLock()
    For g = 0 To numGroups - 1
        For t = 0 To NUM_TYPES - 1
            renumCounts(g, t) = 0

            ' Re-read group entity list (IDs changed in pass 1)
            rc = gp.Get(groupIDs(g))
            If rc <> FE_OK Then GoTo NextPlace

            Dim placeEntSet As femap.Set
            Set placeEntSet = gp.List(listTypes(t))
            If placeEntSet Is Nothing Then GoTo NextPlace

            workSet.Clear()
            workSet.AddSet(placeEntSet.ID)
            If workSet.Count = 0 Then GoTo NextPlace

            renumCounts(g, t) = workSet.Count

            rc = App.feRenumberOpt2(allFtTypes(t), workSet.ID, startIDs(g), _
                0, 0, False, False, False, xyzOrder)
NextPlace:
        Next t
    Next g
    App.feAppUnlock()

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

                ' Re-read group to get actual post-renumber ID range
                Dim countStr As String
                countStr = Str$(renumCounts(g, t)) + " renumbered"
                Do While Len(countStr) < 16
                    countStr = countStr + " "
                Loop

                Dim rangeStr As String
                rangeStr = ""
                rc = gp.Get(groupIDs(g))
                If rc = FE_OK Then
                    Dim postSet As femap.Set
                    Set postSet = gp.List(listTypes(t))
                    If Not postSet Is Nothing Then
                        copySet.Clear()
                        copySet.AddSet(postSet.ID)
                        If copySet.Count > 0 Then
                            Dim minID As Long, maxID As Long, walkID As Long
                            minID = copySet.First()
                            maxID = minID
                            walkID = copySet.Next()
                            Do While walkID > 0
                                maxID = walkID
                                walkID = copySet.Next()
                            Loop
                            rangeStr = "  [" + Str$(minID) + " -" + Str$(maxID) + "]"
                        End If
                    End If
                End If

                App.feAppMessage(FCM_NORMAL, "    " + labelPad + countStr + rangeStr)
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
