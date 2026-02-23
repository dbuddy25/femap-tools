' debug-groups.bas
' Diagnostic script to figure out how to get entities from groups.
' Select 2 groups, then this prints what works and what doesn't.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' Select 2 groups
    Dim groupSet As femap.Set
    Set groupSet = App.feSet
    rc = groupSet.Select(FT_GROUP, True, "Select 2 Groups")
    If rc <> FE_OK Or groupSet.Count < 2 Then
        App.feAppMessage(FCM_ERROR, "Need 2 groups")
        Exit Sub
    End If

    Dim gpA As Long
    Dim gpB As Long
    gpA = groupSet.First()
    gpB = groupSet.Next()
    App.feAppMessage(FCM_HIGHLIGHT, "Group A ID: " + Str$(gpA))
    App.feAppMessage(FCM_HIGHLIGHT, "Group B ID: " + Str$(gpB))

    Dim gp As femap.Group
    Set gp = App.feGroup

    ' ========================================
    ' TEST 1: Group.List(7) for nodes
    ' ========================================
    App.feAppMessage(FCM_HIGHLIGHT, "--- TEST 1: gp.List(7) ---")
    rc = gp.Get(gpA)
    App.feAppMessage(FCM_NORMAL, "gp.Get rc: " + Str$(rc))

    On Error Resume Next
    Dim listSet As femap.Set
    Set listSet = gp.List(7)
    If Err.Number <> 0 Then
        App.feAppMessage(FCM_ERROR, "gp.List(7) FAILED: " + Err.Description)
        Err.Clear
    Else
        If listSet Is Nothing Then
            App.feAppMessage(FCM_ERROR, "gp.List(7) returned Nothing")
        Else
            App.feAppMessage(FCM_NORMAL, "gp.List(7) count: " + Str$(listSet.Count))
        End If
    End If
    On Error GoTo 0

    ' ========================================
    ' TEST 2: feGroupsContaining with negative ID
    ' ========================================
    App.feAppMessage(FCM_HIGHLIGHT, "--- TEST 2: feGroupsContaining ---")

    ' Get first node in model
    Dim nd As femap.Node
    Set nd = App.feNode
    Dim firstNode As Long
    firstNode = nd.First()
    App.feAppMessage(FCM_NORMAL, "First node in model: " + Str$(firstNode))

    Dim containSet As femap.Set
    Set containSet = App.feSet

    If firstNode > 0 Then
        containSet.Clear()
        rc = App.feGroupsContaining(FT_NODE, -firstNode, containSet.ID)
        App.feAppMessage(FCM_NORMAL, "feGroupsContaining(-" + Str$(firstNode) + ") rc: " + Str$(rc))
        App.feAppMessage(FCM_NORMAL, "  Groups containing node: " + Str$(containSet.Count))

        Dim gID As Long
        gID = containSet.First()
        Do While gID > 0
            App.feAppMessage(FCM_NORMAL, "  -> Group " + Str$(gID))
            gID = containSet.Next()
        Loop
    End If

    ' ========================================
    ' TEST 3: feGroupsContaining with positive ID (set-based)
    ' ========================================
    App.feAppMessage(FCM_HIGHLIGHT, "--- TEST 3: feGroupsContaining with Set ---")

    ' Put first 5 nodes into a set
    Dim nodeTestSet As femap.Set
    Set nodeTestSet = App.feSet
    Dim nID As Long
    Dim nCount As Long
    nID = nd.First()
    nCount = 0
    Do While nID > 0 And nCount < 5
        nodeTestSet.Add(nID)
        nCount = nCount + 1
        nID = nd.Next()
    Loop
    App.feAppMessage(FCM_NORMAL, "Test set has " + Str$(nodeTestSet.Count) + " nodes")

    containSet.Clear()
    rc = App.feGroupsContaining(FT_NODE, nodeTestSet.ID, containSet.ID)
    App.feAppMessage(FCM_NORMAL, "feGroupsContaining(setID=" + Str$(nodeTestSet.ID) + ") rc: " + Str$(rc))
    App.feAppMessage(FCM_NORMAL, "  Groups containing set: " + Str$(containSet.Count))

    gID = containSet.First()
    Do While gID > 0
        App.feAppMessage(FCM_NORMAL, "  -> Group " + Str$(gID))
        gID = containSet.Next()
    Loop

    ' ========================================
    ' TEST 4: Try CSys - first csys in model
    ' ========================================
    App.feAppMessage(FCM_HIGHLIGHT, "--- TEST 4: CSys feGroupsContaining ---")
    Dim cs As femap.CSys
    Set cs = App.feCSys
    Dim firstCS As Long
    firstCS = cs.First()
    App.feAppMessage(FCM_NORMAL, "First csys in model: " + Str$(firstCS))

    If firstCS > 0 Then
        containSet.Clear()
        rc = App.feGroupsContaining(FT_CSYS, -firstCS, containSet.ID)
        App.feAppMessage(FCM_NORMAL, "feGroupsContaining(FT_CSYS, -" + Str$(firstCS) + ") rc: " + Str$(rc))
        App.feAppMessage(FCM_NORMAL, "  Groups containing csys: " + Str$(containSet.Count))

        gID = containSet.First()
        Do While gID > 0
            App.feAppMessage(FCM_NORMAL, "  -> Group " + Str$(gID))
            gID = containSet.Next()
        Loop
    End If

    ' ========================================
    ' TEST 5: Group.List with integer 0 (csys)
    ' ========================================
    App.feAppMessage(FCM_HIGHLIGHT, "--- TEST 5: gp.List(0) for csys ---")
    rc = gp.Get(gpA)
    On Error Resume Next
    Dim csListSet As femap.Set
    Set csListSet = gp.List(0)
    If Err.Number <> 0 Then
        App.feAppMessage(FCM_ERROR, "gp.List(0) FAILED: " + Err.Description)
        Err.Clear
    Else
        If csListSet Is Nothing Then
            App.feAppMessage(FCM_ERROR, "gp.List(0) returned Nothing")
        Else
            App.feAppMessage(FCM_NORMAL, "gp.List(0) count: " + Str$(csListSet.Count))
        End If
    End If
    On Error GoTo 0

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  DONE - paste all output above")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
