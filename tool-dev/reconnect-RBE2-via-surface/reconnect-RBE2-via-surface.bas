' reconnect-RBE2-via-surface.bas
' Reconnects an RBE2 element to new surfaces after remeshing.
' Replaces dependent nodes with nodes on user-selected surfaces,
' preserving independent node and DOF settings. Cleans up orphaned old nodes.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Select RBE2 Element
    ' =============================================
    Dim elemSet As femap.Set
    Set elemSet = App.feSet

    rc = elemSet.Select(FT_ELEM, True, "Select RBE2 Element to Reconnect")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No element selected - exiting")
        Exit Sub
    End If

    If elemSet.Count <> 1 Then
        App.feAppMessage(FCM_ERROR, "Select exactly one RBE2 element (selected " + Str$(elemSet.Count) + ")")
        Exit Sub
    End If

    Dim elemID As Long
    elemID = elemSet.First()

    Dim el As femap.Elem
    Set el = App.feElem

    rc = el.Get(elemID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to read element " + Str$(elemID))
        Exit Sub
    End If

    If el.type <> FET_L_RIGID Then
        App.feAppMessage(FCM_ERROR, "Element " + Str$(elemID) + " is not a Rigid element (type=" + Str$(el.type) + ")")
        Exit Sub
    End If

    If el.topology <> FTO_RIGIDLIST Then
        App.feAppMessage(FCM_ERROR, "Element " + Str$(elemID) + " is not an RBE2 (topology=" + Str$(el.topology) + ")")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected RBE2 element " + Str$(elemID))

    ' =============================================
    ' Section 2: Read Current RBE2 Data
    ' =============================================
    Dim indepNode As Long
    indepNode = el.node(0)

    App.feAppMessage(FCM_NORMAL, "Independent node: " + Str$(indepNode))

    ' Get dependent nodes via GetNodeList
    Dim oldCount As Long
    Dim vOldNodes As Variant
    Dim vOldFaces As Variant
    Dim vOldWeights As Variant
    Dim vOldDOF As Variant

    rc = el.GetNodeList(0, oldCount, vOldNodes, vOldFaces, vOldWeights, vOldDOF)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to read dependent node list")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Current dependent nodes: " + Str$(oldCount))

    ' Save the DOF pattern from the first dependent node (6 entries per node)
    Dim dofPattern(5) As Long
    Dim d As Long
    For d = 0 To 5
        dofPattern(d) = CLng(vOldDOF(d))
    Next d

    ' Display DOF pattern
    Dim dofStr As String
    Dim dofLabels As String
    dofLabels = "TX TY TZ RX RY RZ"
    dofStr = ""
    For d = 0 To 5
        If d > 0 Then dofStr = dofStr + " "
        dofStr = dofStr + Str$(dofPattern(d))
    Next d
    App.feAppMessage(FCM_NORMAL, "DOF pattern (" + dofLabels + "): " + dofStr)

    ' Build a set of old dependent nodes for later orphan check
    Dim oldNodeSet As femap.Set
    Set oldNodeSet = App.feSet
    Dim i As Long
    For i = 0 To oldCount - 1
        oldNodeSet.Add(CLng(vOldNodes(i)))
    Next i

    ' =============================================
    ' Section 3: Select Surfaces
    ' =============================================
    Dim surfSet As femap.Set
    Set surfSet = App.feSet

    rc = surfSet.Select(FT_SURFACE, True, "Select Surfaces for New RBE2 Connections")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No surfaces selected - exiting")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(surfSet.Count) + " surface(s)")

    ' =============================================
    ' Section 4: Collect Surface Nodes
    ' =============================================
    Dim newNodeSet As femap.Set
    Set newNodeSet = App.feSet

    Dim surfID As Long
    surfID = surfSet.First()
    Do While surfID > 0
        newNodeSet.AddRule(surfID, FGD_NODE_ATSURFACE)
        surfID = surfSet.Next()
    Loop

    If newNodeSet.Count = 0 Then
        App.feAppMessage(FCM_ERROR, "No nodes found on selected surfaces")
        Exit Sub
    End If

    ' Remove the independent node if it happens to be on a selected surface
    newNodeSet.Remove(indepNode)

    If newNodeSet.Count = 0 Then
        App.feAppMessage(FCM_ERROR, "No dependent nodes remain after excluding independent node")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "New dependent nodes: " + Str$(newNodeSet.Count))

    ' =============================================
    ' Section 5: Build New Node List Arrays
    ' =============================================
    Dim newCount As Long
    newCount = newNodeSet.Count

    Dim vNewNodes As Variant
    newNodeSet.GetArray(newCount, vNewNodes)

    ' Build face, weight, and DOF arrays
    Dim vNewFaces As Variant
    Dim vNewWeights As Variant
    Dim vNewDOF As Variant
    ReDim vNewFaces(newCount - 1)
    ReDim vNewWeights(newCount - 1)
    ReDim vNewDOF(newCount * 6 - 1)

    For i = 0 To newCount - 1
        vNewFaces(i) = CLng(0)
        vNewWeights(i) = CDbl(0)
        For d = 0 To 5
            vNewDOF(i * 6 + d) = dofPattern(d)
        Next d
    Next i

    ' =============================================
    ' Section 6: Update the RBE2
    ' =============================================
    rc = el.PutNodeList(0, newCount, vNewNodes, vNewFaces, vNewWeights, vNewDOF)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to set new dependent node list")
        Exit Sub
    End If

    rc = el.Put(elemID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to save updated RBE2 element")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Updated RBE2 with " + Str$(newCount) + " new dependent nodes")

    ' =============================================
    ' Section 7: Delete Orphaned Old Nodes
    ' =============================================
    Dim orphanCount As Long
    orphanCount = 0
    Dim elemByNode As femap.Set
    Set elemByNode = App.feSet

    Dim nodeID As Long
    nodeID = oldNodeSet.First()
    Do While nodeID > 0
        ' Skip if this node is also in the new set (still in use by the RBE2)
        If Not newNodeSet.IsAdded(nodeID) Then
            ' Check if any elements still reference this node
            elemByNode.Clear()
            elemByNode.AddRule(nodeID, FGD_ELEM_BYNODE)
            If elemByNode.Count = 0 Then
                rc = App.feDelete(FT_NODE, nodeID)
                If rc = FE_OK Then orphanCount = orphanCount + 1
            End If
        End If
        nodeID = oldNodeSet.Next()
    Loop

    ' =============================================
    ' Section 8: Report
    ' =============================================
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Reconnect RBE2 via Surface - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  RBE2 Element:              " + Str$(elemID))
    App.feAppMessage(FCM_NORMAL, "  Independent Node:          " + Str$(indepNode))
    App.feAppMessage(FCM_NORMAL, "  Old Dependent Nodes:       " + Str$(oldCount))
    App.feAppMessage(FCM_NORMAL, "  New Dependent Nodes:       " + Str$(newCount))
    App.feAppMessage(FCM_NORMAL, "  Orphaned Nodes Deleted:    " + Str$(orphanCount))
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
