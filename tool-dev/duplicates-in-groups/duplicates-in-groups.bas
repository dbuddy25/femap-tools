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
    ' Group list type constants (FGR_*) for Group.List()
    Const NUM_TYPES = 5
    Dim listConsts(4) As Long
    listConsts(0) = FGR_CSYS
    listConsts(1) = FGR_NODE
    listConsts(2) = FGR_ELEM
    listConsts(3) = FGR_MATL
    listConsts(4) = FGR_PROP

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
    Dim g As Long
    Dim i As Long
    Dim j As Long
    Dim entityID As Long
    Dim pairVal As Long

    ' Reusable set for intersections
    Dim isectSet As femap.Set
    Set isectSet = App.feSet

    ' Track unique duplicate entities per type (an entity in 3 groups
    ' shows up in multiple pairs but should only count once)
    Dim dupSet As femap.Set
    Set dupSet = App.feSet

    For t = 0 To NUM_TYPES - 1
        typeDupCounts(t) = 0
        dupSet.Clear()

        ' Get entity sets for each group via Group.List()
        ' Store sets in an array for pairwise comparison
        Dim grpSets() As femap.Set
        ReDim grpSets(numGroups - 1)

        For g = 0 To numGroups - 1
            rc = gp.Get(groupIDs(g))
            If rc = FE_OK Then
                Set grpSets(g) = gp.List(listConsts(t))
            Else
                Set grpSets(g) = App.feSet
            End If
        Next g

        ' Compare all pairs
        For i = 0 To numGroups - 2
            For j = i + 1 To numGroups - 1
                ' Intersect copies of the two group sets
                isectSet.Clear()
                isectSet.AddSet(grpSets(i).ID)
                isectSet.IntersectSet(grpSets(j).ID)

                pairCounts(t, i * numGroups + j) = isectSet.Count

                ' Add shared entities to dupSet for unique counting
                If isectSet.Count > 0 Then
                    dupSet.AddSet(isectSet.ID)
                End If
            Next j
        Next i

        typeDupCounts(t) = dupSet.Count
        totalDups = totalDups + typeDupCounts(t)

        App.feAppMessage(FCM_NORMAL, _
            "  " + typeLabels(t) + ": found " + Str$(typeDupCounts(t)) + " duplicates")
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

    For t = 0 To NUM_TYPES - 1
        countStr = Str$(typeDupCounts(t))

        ' Pad label for alignment
        labelPad = typeLabels(t) + ":"
        Do While Len(labelPad) < 18
            labelPad = labelPad + " "
        Loop

        App.feAppMessage(FCM_NORMAL, "  " + labelPad + countStr + " duplicates")

        ' Show pair breakdown if any duplicates
        If typeDupCounts(t) > 0 Then
            For i = 0 To numGroups - 2
                For j = i + 1 To numGroups - 1
                    pairVal = pairCounts(t, i * numGroups + j)
                    If pairVal > 0 Then
                        App.feAppMessage(FCM_NORMAL, "    """ + groupTitles(i) + _
                            """ & """ + groupTitles(j) + """:" + _
                            Str$(pairVal) + " shared")
                    End If
                Next j
            Next i
        End If
    Next t

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_HIGHLIGHT, "  Total:" + Str$(totalDups) + " duplicate entities found")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
