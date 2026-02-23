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
    Const NUM_TYPES = 5
    Dim typeConsts(4) As Long
    typeConsts(0) = FT_CSYS
    typeConsts(1) = FT_NODE
    typeConsts(2) = FT_ELEM
    typeConsts(3) = FT_MATL
    typeConsts(4) = FT_PROP

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

    ' Traversal objects
    Dim nd As femap.Node
    Set nd = App.feNode
    Dim el As femap.Elem
    Set el = App.feElem
    Dim cs As femap.CSys
    Set cs = App.feCSys
    Dim mt As femap.Matl
    Set mt = App.feMatl
    Dim pr As femap.Prop
    Set pr = App.feProp

    ' Reusable set for feGroupsContaining results
    Dim containingSet As femap.Set
    Set containingSet = App.feSet

    Dim entityID As Long
    Dim t As Long
    Dim a As Long
    Dim b As Long
    Dim idxA As Long
    Dim idxB As Long
    Dim tmp As Long
    Dim scanCount As Long
    Dim containCount As Long
    Dim vGrpIDs As Variant

    App.feAppLock

    For t = 0 To NUM_TYPES - 1
        typeDupCounts(t) = 0
        scanCount = 0

        ' Get first entity ID for this type
        Select Case t
            Case 0: entityID = cs.First()
            Case 1: entityID = nd.First()
            Case 2: entityID = el.First()
            Case 3: entityID = mt.First()
            Case 4: entityID = pr.First()
        End Select

        Do While entityID > 0
            scanCount = scanCount + 1

            ' Progress for large entity types (nodes, elements)
            If t = 1 Or t = 2 Then
                If (scanCount Mod 10000) = 0 Then
                    App.feAppMessage(FCM_NORMAL, _
                        "  Scanning " + typeLabels(t) + "... " + Str$(scanCount))
                End If
            End If

            ' Find which groups contain this entity
            ' NOTE: negative entityID = single entity; positive = set ID
            containingSet.Clear()
            rc = App.feGroupsContaining(typeConsts(t), -entityID, containingSet.ID)

            ' Intersect with selected groups only
            containingSet.IntersectSet(groupSet.ID)

            If containingSet.Count > 1 Then
                typeDupCounts(t) = typeDupCounts(t) + 1

                ' Get array of group IDs this entity belongs to
                containingSet.GetArray(containCount, vGrpIDs)

                ' Increment pair counts for all combinations
                For a = 0 To containCount - 2
                    For b = a + 1 To containCount - 1
                        ' Map group IDs to indices
                        idxA = -1
                        idxB = -1
                        For idx = 0 To numGroups - 1
                            If groupIDs(idx) = vGrpIDs(a) Then idxA = idx
                            If groupIDs(idx) = vGrpIDs(b) Then idxB = idx
                        Next idx
                        ' Ensure idxA < idxB for consistent storage
                        If idxA > idxB Then
                            tmp = idxA
                            idxA = idxB
                            idxB = tmp
                        End If
                        If idxA >= 0 And idxB >= 0 Then
                            pairCounts(t, idxA * numGroups + idxB) = _
                                pairCounts(t, idxA * numGroups + idxB) + 1
                        End If
                    Next b
                Next a
            End If

            ' Get next entity ID
            Select Case t
                Case 0: entityID = cs.Next()
                Case 1: entityID = nd.Next()
                Case 2: entityID = el.Next()
                Case 3: entityID = mt.Next()
                Case 4: entityID = pr.Next()
            End Select
        Loop

        totalDups = totalDups + typeDupCounts(t)
        App.feAppMessage(FCM_NORMAL, _
            "  " + typeLabels(t) + ": scanned " + Str$(scanCount) + _
            ", found " + Str$(typeDupCounts(t)) + " duplicates")
    Next t

    App.feAppUnlock

    ' =============================================
    ' Section 4: Report Results
    ' =============================================
    Dim i As Long
    Dim j As Long
    Dim countStr As String
    Dim labelPad As String
    Dim pairVal As Long

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
