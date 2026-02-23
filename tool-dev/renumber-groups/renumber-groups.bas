' renumber-groups.bas
' Renumbers all entities (nodes, elements, csys, materials, properties) in
' selected groups into non-overlapping ID ranges with growth buffer.

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
    ReDim groupIDs(numGroups - 1)
    Dim groupTitles() As String
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
    ' Two parallel type arrays: listTypes for gp.List(), ftTypes for feRenumberOpt2
    '   CSys:     list=0,  ft=9
    '   Material: list=9,  ft=10
    '   Property: list=10, ft=11
    '   Element:  list=8,  ft=8
    '   Node:     list=7,  ft=7
    Const NUM_TYPES = 5
    Dim listTypes(4) As Long
    listTypes(0) = 0   ' CSys
    listTypes(1) = 9   ' Material
    listTypes(2) = 10  ' Property
    listTypes(3) = 8   ' Element
    listTypes(4) = 7   ' Node

    Dim ftTypes(4) As Long
    ftTypes(0) = 9     ' CSys
    ftTypes(1) = 10    ' Material
    ftTypes(2) = 11    ' Property
    ftTypes(3) = 8     ' Element
    ftTypes(4) = 7     ' Node

    Dim typeLabels(4) As String
    typeLabels(0) = "CSys"
    typeLabels(1) = "Materials"
    typeLabels(2) = "Properties"
    typeLabels(3) = "Elements"
    typeLabels(4) = "Nodes"

    ' Count entities per group per type, track max across types
    Dim entityCounts() As Long
    ReDim entityCounts(numGroups - 1, NUM_TYPES - 1)
    Dim maxCount() As Long
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
    ' Section 3: Calculate Ranges
    ' =============================================
    Dim rangeSize() As Long
    ReDim rangeSize(numGroups - 1)
    Dim startIDs() As Long
    ReDim startIDs(numGroups - 1)

    ' Calculate range size for each group: maxCount * 1.5 rounded up to nearest 1000, min 1000
    For g = 0 To numGroups - 1
        If maxCount(g) = 0 Then
            rangeSize(g) = 1000
        Else
            rangeSize(g) = Int((maxCount(g) * 1.5) / 1000 + 0.999) * 1000
            If rangeSize(g) < 1000 Then rangeSize(g) = 1000
        End If
    Next g

    ' Ask user for starting ID
    Dim startInput As String
    startInput = InputBox$("Enter starting ID for the first group:" + Chr$(10) + Chr$(10) + _
        "Subsequent groups will be auto-assigned" + Chr$(10) + _
        "non-overlapping ranges.", "Renumber Groups - Start ID", "100000")
    If startInput = "" Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim firstStart As Long
    firstStart = CLng(startInput)
    If firstStart < 1 Then
        App.feAppMessage(FCM_ERROR, "Start ID must be >= 1 - exiting")
        Exit Sub
    End If

    ' Assign start IDs sequentially
    startIDs(0) = firstStart
    For g = 1 To numGroups - 1
        startIDs(g) = startIDs(g - 1) + rangeSize(g - 1)
    Next g

    ' =============================================
    ' Section 4: Conflict Check & Confirm
    ' =============================================
    ' For each entity type, build a set of all entities NOT in any selected group,
    ' then check if any fall within any target range.
    Dim conflictMsg As String
    conflictMsg = ""
    Dim hasConflicts As Boolean
    hasConflicts = False

    Dim allEntSet As femap.Set
    Set allEntSet = App.feSet
    Dim rangeSet As femap.Set
    Set rangeSet = App.feSet
    Dim checkSet As femap.Set
    Set checkSet = App.feSet

    ' FT_ types for selecting all entities (same as ftTypes)
    Dim allFtTypes(4) As Long
    allFtTypes(0) = FT_CSYS
    allFtTypes(1) = FT_MATL
    allFtTypes(2) = FT_PROP
    allFtTypes(3) = FT_ELEM
    allFtTypes(4) = FT_NODE

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
                rangeSet.Clear()
                rangeSet.AddRange(startIDs(g), 1, startIDs(g) + rangeSize(g) - 1)

                checkSet.Clear()
                checkSet.AddSet(allEntSet.ID)
                checkSet.RemoveNotCommon(rangeSet.ID)

                If checkSet.Count > 0 Then
                    hasConflicts = True
                    conflictMsg = conflictMsg + "  WARNING: " + Str$(checkSet.Count) + _
                        " existing " + typeLabels(t) + " in range " + _
                        Str$(startIDs(g)) + "-" + Str$(startIDs(g) + rangeSize(g) - 1) + Chr$(10)
                End If
            Next g
        End If
NextConflictType:
    Next t

    ' Build summary message
    Dim summaryMsg As String
    Dim totalEntities As Long
    totalEntities = 0

    summaryMsg = "Renumbering Plan:" + Chr$(10) + Chr$(10)
    For g = 0 To numGroups - 1
        Dim groupTotal As Long
        groupTotal = 0
        For t = 0 To NUM_TYPES - 1
            groupTotal = groupTotal + entityCounts(g, t)
        Next t
        totalEntities = totalEntities + groupTotal

        summaryMsg = summaryMsg + """" + groupTitles(g) + """: " + _
            Str$(startIDs(g)) + " - " + Str$(startIDs(g) + rangeSize(g) - 1) + _
            "  (" + Str$(groupTotal) + " entities, range " + Str$(rangeSize(g)) + ")" + Chr$(10)
    Next g

    If hasConflicts Then
        summaryMsg = summaryMsg + Chr$(10) + "CONFLICTS DETECTED:" + Chr$(10) + conflictMsg
    End If

    summaryMsg = summaryMsg + Chr$(10) + "Total entities to renumber:" + Str$(totalEntities) + Chr$(10) + Chr$(10) + "Proceed?"

    Dim answer As Long
    answer = MsgBox(summaryMsg, MB_OKCANCEL + MB_ICONQUESTION, "Renumber Groups - Confirm")
    If answer <> IDOK Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - exiting")
        Exit Sub
    End If

    ' =============================================
    ' Section 5: Renumber
    ' =============================================
    ' Order: CSys(0) → Materials(1) → Properties(2) → Elements(3) → Nodes(4)
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

            ' feRenumberOpt2(entityTYPE, entitySET, startID, renumMethod,
            '                renumCSysID, renumAbs, renumDescend, renumConstOff, xyzSortOrder)
            rc = App.feRenumberOpt2(ftTypes(t), workSet.ID, startIDs(g), _
                0, 0, False, False, False, xyzOrder)
NextRenum:
        Next t
    Next g

    App.feViewRegenerate(0)

    ' =============================================
    ' Section 6: Report Results
    ' =============================================
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
                ' Pad label for alignment
                Dim labelPad As String
                labelPad = typeLabels(t) + ":"
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
