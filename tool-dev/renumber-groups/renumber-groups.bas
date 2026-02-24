' renumber-groups.bas
' Renumbers all entities (nodes, elements, csys, materials, properties) in
' selected groups into non-overlapping ID ranges with growth buffer.

Const NUM_TYPES = 5

' Module-level variables shared between Sub Main and dialog
Dim mApp As femap.model
Dim mNumGroups As Long
Dim mGroupIDs() As Long
Dim mGroupTitles() As String
Dim mEntityCounts() As Long
Dim mMaxCount() As Long
Dim mRangeSize() As Long
Dim mStartIDs() As Long
Dim mListTypes(4) As Long
Dim mAllFtTypes(4) As Long
Dim mTypeLabels(4) As String
Dim mConflictText As String

Sub Main
    Set mApp = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Group Selection
    ' =============================================
    Dim groupSet As femap.Set
    Set groupSet = mApp.feSet

    rc = groupSet.Select(FT_GROUP, True, "Select Groups to Renumber")
    If rc <> FE_OK Then
        mApp.feAppMessage(FCM_WARNING, "No groups selected - exiting")
        Exit Sub
    End If

    If groupSet.Count < 1 Then
        mApp.feAppMessage(FCM_ERROR, "Must select at least 1 group - exiting")
        Exit Sub
    End If

    mNumGroups = groupSet.Count
    ReDim mGroupIDs(mNumGroups - 1)
    ReDim mGroupTitles(mNumGroups - 1)

    Dim gp As femap.Group
    Set gp = mApp.feGroup
    Dim gpID As Long
    Dim idx As Long
    idx = 0

    gpID = groupSet.First()
    Do While gpID > 0
        mGroupIDs(idx) = gpID
        rc = gp.Get(gpID)
        If rc = FE_OK Then
            mGroupTitles(idx) = gp.title
        Else
            mGroupTitles(idx) = "Group " + Str$(gpID)
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
    mListTypes(0) = 0   ' CSys
    mListTypes(1) = 9   ' Material
    mListTypes(2) = 10  ' Property
    mListTypes(3) = 8   ' Element
    mListTypes(4) = 7   ' Node

    mAllFtTypes(0) = FT_CSYS
    mAllFtTypes(1) = FT_MATL
    mAllFtTypes(2) = FT_PROP
    mAllFtTypes(3) = FT_ELEM
    mAllFtTypes(4) = FT_NODE

    mTypeLabels(0) = "CSys"
    mTypeLabels(1) = "Matl"
    mTypeLabels(2) = "Prop"
    mTypeLabels(3) = "Elem"
    mTypeLabels(4) = "Node"

    ReDim mEntityCounts(mNumGroups - 1, NUM_TYPES - 1)
    ReDim mMaxCount(mNumGroups - 1)

    Dim copySet As femap.Set
    Set copySet = mApp.feSet

    Dim g As Long
    Dim t As Long

    For g = 0 To mNumGroups - 1
        mMaxCount(g) = 0
        For t = 0 To NUM_TYPES - 1
            rc = gp.Get(mGroupIDs(g))
            If rc <> FE_OK Then
                mEntityCounts(g, t) = 0
                GoTo NextType
            End If

            Dim entSet As femap.Set
            Set entSet = gp.List(mListTypes(t))
            If entSet Is Nothing Then
                mEntityCounts(g, t) = 0
            Else
                ' Copy to avoid stale ref
                copySet.Clear()
                copySet.AddSet(entSet.ID)
                mEntityCounts(g, t) = copySet.Count
            End If

            If mEntityCounts(g, t) > mMaxCount(g) Then
                mMaxCount(g) = mEntityCounts(g, t)
            End If
NextType:
        Next t
    Next g

    ' =============================================
    ' Section 3: Calculate Range Sizes
    ' =============================================
    ReDim mRangeSize(mNumGroups - 1)
    ReDim mStartIDs(mNumGroups - 1)

    ' Range size per group: maxCount * 1.5 rounded up to nearest 1000, min 1000
    For g = 0 To mNumGroups - 1
        If mMaxCount(g) = 0 Then
            mRangeSize(g) = 1000
        Else
            mRangeSize(g) = Int((mMaxCount(g) * 1.5) / 1000 + 0.999) * 1000
            If mRangeSize(g) < 1000 Then mRangeSize(g) = 1000
        End If
    Next g

    ' =============================================
    ' Section 4: Show Dialog
    ' =============================================
    Begin Dialog RenumberDialog 420, 340, "Renumber Groups", .RenumberDlgFunc
        Text 10, 6, 400, 180, "", .tableLabel
        Text 10, 192, 65, 14, "Start ID:"
        TextBox 80, 190, 80, 14, .startID
        PushButton 170, 189, 80, 16, "Recalculate", .btnRecalc
        Text 10, 212, 400, 80, "", .conflictLabel
        OKButton 100, 304, 90, 22
        CancelButton 220, 304, 90, 22
    End Dialog

    Dim dlg As RenumberDialog
    dlg.startID = "100000"

    If Dialog(dlg) <> -1 Then
        mApp.feAppMessage(FCM_WARNING, "Cancelled by user - exiting")
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
    Set workSet = mApp.feSet

    Dim renumCounts() As Long
    ReDim renumCounts(mNumGroups - 1, NUM_TYPES - 1)

    For g = 0 To mNumGroups - 1
        For t = 0 To NUM_TYPES - 1
            renumCounts(g, t) = 0

            ' Get entity set from group (must re-get each time due to stale ref)
            rc = gp.Get(mGroupIDs(g))
            If rc <> FE_OK Then GoTo NextRenum

            Dim renumEntSet As femap.Set
            Set renumEntSet = gp.List(mListTypes(t))
            If renumEntSet Is Nothing Then GoTo NextRenum

            ' Copy to working set (stale-ref pattern)
            workSet.Clear()
            workSet.AddSet(renumEntSet.ID)
            If workSet.Count = 0 Then GoTo NextRenum

            renumCounts(g, t) = workSet.Count

            rc = mApp.feRenumberOpt2(mAllFtTypes(t), workSet.ID, mStartIDs(g), _
                0, 0, False, False, False, xyzOrder)
NextRenum:
        Next t
    Next g

    mApp.feViewRegenerate(0)

    ' =============================================
    ' Section 6: Report Results
    ' =============================================
    Dim reportLabels(4) As String
    reportLabels(0) = "CSys"
    reportLabels(1) = "Materials"
    reportLabels(2) = "Properties"
    reportLabels(3) = "Elements"
    reportLabels(4) = "Nodes"

    Dim totalEntities As Long
    totalEntities = 0
    For g = 0 To mNumGroups - 1
        For t = 0 To NUM_TYPES - 1
            totalEntities = totalEntities + mEntityCounts(g, t)
        Next t
    Next g

    mApp.feAppMessage(FCM_HIGHLIGHT, "========================================")
    mApp.feAppMessage(FCM_HIGHLIGHT, "  Renumber Groups - Results")
    mApp.feAppMessage(FCM_HIGHLIGHT, "========================================")

    For g = 0 To mNumGroups - 1
        mApp.feAppMessage(FCM_HIGHLIGHT, "  """ + mGroupTitles(g) + """ (start ID:" + Str$(mStartIDs(g)) + ")")

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
                mApp.feAppMessage(FCM_NORMAL, "    " + labelPad + Str$(renumCounts(g, t)) + " renumbered")
            End If
        Next t

        If grpRenumTotal = 0 Then
            mApp.feAppMessage(FCM_NORMAL, "    (no entities)")
        End If
    Next g

    mApp.feAppMessage(FCM_NORMAL, "")
    mApp.feAppMessage(FCM_HIGHLIGHT, "  Total:" + Str$(totalEntities) + " entities renumbered")
    mApp.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub

' =============================================
' Dialog callback
' =============================================
Function RenumberDlgFunc(DlgItem$, Action%, SuppValue&) As Boolean
    Select Case Action
    Case 1  ' Initialization
        Dim initStart As Long
        Dim initStr As String
        initStr = Trim$(DlgText$("startID"))
        If IsNumeric(initStr) Then
            initStart = CLng(initStr)
        Else
            initStart = 100000
        End If
        If initStart < 1 Then initStart = 100000
        CalcStartIDs initStart
        CheckConflicts
        DlgText "tableLabel", BuildTableText()
        DlgText "conflictLabel", mConflictText

    Case 2  ' Control action
        Select Case DlgItem$
        Case "btnRecalc"
            Dim recalcStart As Long
            Dim recalcErr As String
            recalcErr = ValidateStartID(Trim$(DlgText$("startID")), recalcStart)
            If recalcErr <> "" Then
                DlgText "conflictLabel", recalcErr
                RenumberDlgFunc = True
                Exit Function
            End If
            CalcStartIDs recalcStart
            CheckConflicts
            DlgText "tableLabel", BuildTableText()
            DlgText "conflictLabel", mConflictText
            RenumberDlgFunc = True

        Case "OK"
            Dim okStart As Long
            Dim okErr As String
            okErr = ValidateStartID(Trim$(DlgText$("startID")), okStart)
            If okErr <> "" Then
                DlgText "conflictLabel", okErr
                RenumberDlgFunc = True
                Exit Function
            End If
            CalcStartIDs okStart
            RenumberDlgFunc = False
        End Select
    End Select
End Function

' =============================================
' Validate start ID input string
' Returns empty string if valid, error message otherwise
' =============================================
Function ValidateStartID(inputStr As String, ByRef startVal As Long) As String
    If inputStr = "" Or Not IsNumeric(inputStr) Then
        ValidateStartID = "ERROR: Start ID must be a number."
        Exit Function
    End If
    On Error Resume Next
    startVal = CLng(inputStr)
    If Err.Number <> 0 Then
        On Error GoTo 0
        ValidateStartID = "ERROR: Start ID value is out of range."
        Exit Function
    End If
    On Error GoTo 0
    If startVal < 1 Then
        ValidateStartID = "ERROR: Start ID must be >= 1."
        Exit Function
    End If
    ValidateStartID = ""
End Function

' =============================================
' Fill mStartIDs() sequentially from the given first start ID
' =============================================
Sub CalcStartIDs(firstStart As Long)
    mStartIDs(0) = firstStart
    Dim g As Long
    For g = 1 To mNumGroups - 1
        mStartIDs(g) = mStartIDs(g - 1) + mRangeSize(g - 1)
    Next g
End Sub

' =============================================
' Build proportional-font-friendly table text for dialog
' =============================================
Function BuildTableText() As String
    Dim NL As String
    NL = Chr$(13)
    Dim txt As String
    txt = ""

    Dim g As Long
    For g = 0 To mNumGroups - 1
        If g > 0 Then txt = txt + NL
        txt = txt + mGroupTitles(g) + " (max:" + Str$(mMaxCount(g)) + ")" + NL
        txt = txt + "  CSys:" + Str$(mEntityCounts(g, 0)) + _
            "  Matl:" + Str$(mEntityCounts(g, 1)) + _
            "  Prop:" + Str$(mEntityCounts(g, 2)) + _
            "  Elem:" + Str$(mEntityCounts(g, 3)) + _
            "  Node:" + Str$(mEntityCounts(g, 4)) + NL
        txt = txt + "  Range:" + Str$(mStartIDs(g)) + " -" + _
            Str$(mStartIDs(g) + mRangeSize(g) - 1) + _
            " (size:" + Str$(mRangeSize(g)) + ")"
    Next g

    BuildTableText = txt
End Function

' =============================================
' Check for ID conflicts with entities outside the selected groups
' =============================================
Sub CheckConflicts()
    Dim NL As String
    NL = Chr$(13)
    mConflictText = ""

    Dim gp As femap.Group
    Set gp = mApp.feGroup
    Dim copySet As femap.Set
    Set copySet = mApp.feSet
    Dim allEntSet As femap.Set
    Set allEntSet = mApp.feSet
    Dim rangeSet As femap.Set
    Set rangeSet = mApp.feSet
    Dim checkSet As femap.Set
    Set checkSet = mApp.feSet

    Dim conflictCount As Long
    conflictCount = 0
    Dim rc As Long
    Dim g As Long
    Dim t As Long

    For t = 0 To NUM_TYPES - 1
        ' Get all entities of this type in the model
        allEntSet.Clear()
        allEntSet.AddAll(mAllFtTypes(t))
        If allEntSet.Count = 0 Then GoTo NextConflictType

        ' Remove entities that belong to any selected group
        For g = 0 To mNumGroups - 1
            rc = gp.Get(mGroupIDs(g))
            If rc = FE_OK Then
                Dim gpEntSet As femap.Set
                Set gpEntSet = gp.List(mListTypes(t))
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
            For g = 0 To mNumGroups - 1
                rangeSet.Clear()
                rangeSet.AddRange(mStartIDs(g), 1, mStartIDs(g) + mRangeSize(g) - 1)
                checkSet.Clear()
                checkSet.AddSet(allEntSet.ID)
                checkSet.RemoveNotCommon(rangeSet.ID)
                If checkSet.Count > 0 Then
                    If conflictCount > 0 Then mConflictText = mConflictText + NL
                    mConflictText = mConflictText + "WARNING:" + Str$(checkSet.Count) + _
                        " " + mTypeLabels(t) + " in range" + _
                        Str$(mStartIDs(g)) + " -" + Str$(mStartIDs(g) + mRangeSize(g) - 1)
                    conflictCount = conflictCount + 1
                End If
            Next g
        End If
NextConflictType:
    Next t

    If conflictCount = 0 Then
        mConflictText = "No conflicts with existing IDs."
    End If
End Sub
