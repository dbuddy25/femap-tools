' duplicates-in-groups.bas
' Checks for entities (nodes, elements, csys, materials, properties) that
' appear in more than one of the user-selected groups and reports which
' groups share them.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Group Selection
    ' =============================================
    Dim groupSet As femap.Set
    Set groupSet = App.feSet

    rc = groupSet.Select(FT_GROUP, True, "Select Groups to Check for Duplicates")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No groups selected - exiting")
        Exit Sub
    End If

    If groupSet.Count < 2 Then
        App.feAppMessage(FCM_ERROR, "Must select at least 2 groups - exiting")
        Exit Sub
    End If

    ' =============================================
    ' Section 2: Build Group Info Arrays
    ' =============================================
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

    ' Build header string listing selected groups
    Dim headerStr As String
    headerStr = "Checked " + Str$(numGroups) + " groups:"
    For idx = 0 To numGroups - 1
        headerStr = headerStr + " """ + groupTitles(idx) + """"
        If idx < numGroups - 1 Then headerStr = headerStr + ","
    Next idx

    ' =============================================
    ' Section 3: Scan Each Entity Type
    ' =============================================
    ' Group.List() integer types (from API PDF):
    '   0=CSys, 7=Node, 8=Elem, 9=Material, 10=Property
    Const NUM_TYPES = 5
    Dim listTypes(4) As Long
    listTypes(0) = 0
    listTypes(1) = 7
    listTypes(2) = 8
    listTypes(3) = 9
    listTypes(4) = 10

    Dim typeLabels(4) As String
    typeLabels(0) = "Coord Systems"
    typeLabels(1) = "Nodes"
    typeLabels(2) = "Elements"
    typeLabels(3) = "Materials"
    typeLabels(4) = "Properties"

    ' Per-type duplicate counts
    Dim typeDupCounts(4) As Long
    ' Per-type pair counts stored as flat 2D array (upper triangle)
    Dim pairSize As Long
    pairSize = numGroups * numGroups
    Dim pairCounts() As Long
    ReDim pairCounts(NUM_TYPES - 1, pairSize - 1)

    Dim totalDups As Long
    totalDups = 0

    Dim t As Long
    Dim i As Long
    Dim j As Long
    Dim pairVal As Long

    ' Reusable set for intersections
    Dim isectSet As femap.Set
    Set isectSet = App.feSet

    ' Track unique duplicate entities per type
    Dim dupSet As femap.Set
    Set dupSet = App.feSet

    For t = 0 To NUM_TYPES - 1
        typeDupCounts(t) = 0
        dupSet.Clear()

        ' Compare all group pairs
        For i = 0 To numGroups - 2
            For j = i + 1 To numGroups - 1
                ' Get entity set for group i (re-get each pair since gp.List
                ' returns an internal ref that gp.Get invalidates)
                rc = gp.Get(groupIDs(i))
                Dim setA As femap.Set
                Set setA = gp.List(listTypes(t))
                If setA Is Nothing Then GoTo NextJ

                ' Copy setA into isectSet before loading group j
                isectSet.Clear()
                isectSet.AddSet(setA.ID)

                ' Get entity set for group j (invalidates setA)
                rc = gp.Get(groupIDs(j))
                Dim setB As femap.Set
                Set setB = gp.List(listTypes(t))
                If setB Is Nothing Then GoTo NextJ

                ' isectSet already holds group i's entities; intersect with group j
                isectSet.RemoveNotCommon(setB.ID)

                pairCounts(t, i * numGroups + j) = isectSet.Count

                ' Add to dupSet for unique counting
                If isectSet.Count > 0 Then
                    dupSet.AddSet(isectSet.ID)
                End If
NextJ:
            Next j
        Next i

        typeDupCounts(t) = dupSet.Count
        totalDups = totalDups + typeDupCounts(t)
    Next t

    ' =============================================
    ' Section 4: Report Results
    ' =============================================
    Dim countStr As String
    Dim labelPad As String

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Duplicates in Groups - Results")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, headerStr)
    App.feAppMessage(FCM_NORMAL, "")

    Dim msgColor As Long

    For t = 0 To NUM_TYPES - 1
        countStr = Str$(typeDupCounts(t))

        ' Pad label for alignment
        labelPad = typeLabels(t) + ":"
        Do While Len(labelPad) < 18
            labelPad = labelPad + " "
        Loop

        ' Warning color for non-zero counts, normal for zero
        If typeDupCounts(t) > 0 Then
            msgColor = FCM_WARNING
        Else
            msgColor = FCM_NORMAL
        End If

        App.feAppMessage(msgColor, "  " + labelPad + countStr + " duplicates")

        ' Show pair breakdown if any duplicates
        If typeDupCounts(t) > 0 Then
            For i = 0 To numGroups - 2
                For j = i + 1 To numGroups - 1
                    pairVal = pairCounts(t, i * numGroups + j)
                    If pairVal > 0 Then
                        App.feAppMessage(FCM_WARNING, "    """ + groupTitles(i) + _
                            """ & """ + groupTitles(j) + """:" + _
                            Str$(pairVal) + " shared")
                    End If
                Next j
            Next i
        End If
    Next t

    App.feAppMessage(FCM_NORMAL, "")
    If totalDups > 0 Then
        msgColor = FCM_WARNING
    Else
        msgColor = FCM_HIGHLIGHT
    End If
    App.feAppMessage(msgColor, "  Total:" + Str$(totalDups) + " duplicate entities found")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
