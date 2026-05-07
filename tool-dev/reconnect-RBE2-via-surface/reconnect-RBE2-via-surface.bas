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

    ' Remove old dependent nodes (may still be on surface from prior mesh)
    newNodeSet.RemoveSet(oldNodeSet.ID)

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

    ' Build candidate set: old nodes that are NOT in the new RBE2
    Dim candidateSet As femap.Set
    Set candidateSet = App.feSet
    candidateSet.AddSet(oldNodeSet.ID)
    candidateSet.RemoveSet(newNodeSet.ID)

    If candidateSet.Count > 0 Then
        ' Find all elements referencing any candidate node (one batch call)
        Dim refElemSet As femap.Set
        Set refElemSet = App.feSet
        refElemSet.AddSetRule(candidateSet.ID, FGD_ELEM_BYNODE)

        If refElemSet.Count > 0 Then
            ' Find nodes still referenced by those elements (one batch call)
            Dim usedNodeSet As femap.Set
            Set usedNodeSet = App.feSet
            usedNodeSet.AddSetRule(refElemSet.ID, FGD_NODE_ONELEM)

            ' Remove nodes still in use — remainder are true orphans
            candidateSet.RemoveSet(usedNodeSet.ID)
        End If

        ' Delete orphan nodes
        Dim nd As femap.Node
        Set nd = App.feNode
        Dim attempted As Long
        Dim vCandIDs As Variant
        Dim survivedMsg As String
        attempted = candidateSet.Count
        rc = candidateSet.GetArray(attempted, vCandIDs)
        rc = App.feDelete(FT_NODE, candidateSet.ID)

        Dim bcChk As femap.BCNode
        Dim bcSetChk As femap.BCSet
        Dim ldChk As femap.LoadMesh
        Dim ldSetChk As femap.LoadSet
        Dim oneNdSet As femap.Set
        Dim chkElSet As femap.Set
        Dim reasons As String
        Dim nID As Long
        Dim elRefID As Long
        Dim elRefStr As String
        Dim firstEl As Boolean
        Dim bcSetStr As String
        Dim ldSetStr As String
        Dim foundInSet As Boolean
        Dim ldRc As Long
        Set bcChk = App.feBCNode
        Set bcSetChk = App.feBCSet
        Set ldChk = App.feLoadMesh
        Set ldSetChk = App.feLoadSet

        survivedMsg = ""
        For i = 0 To attempted - 1
            nID = CLng(vCandIDs(i))
            If nd.Get(nID) <> FE_OK Then
                orphanCount = orphanCount + 1
            Else
                reasons = ""

                ' Check elements
                Set oneNdSet = App.feSet
                oneNdSet.Add(nID)
                Set chkElSet = App.feSet
                chkElSet.AddSetRule(oneNdSet.ID, FGD_ELEM_BYNODE)
                If chkElSet.Count > 0 Then
                    elRefStr = "elem["
                    elRefID = chkElSet.First()
                    firstEl = True
                    Do While elRefID > 0
                        If Not firstEl Then elRefStr = elRefStr + ","
                        elRefStr = elRefStr + Trim$(Str$(elRefID))
                        firstEl = False
                        elRefID = chkElSet.Next()
                    Loop
                    reasons = reasons + elRefStr + "]"
                End If

                ' Check constraint sets
                bcSetStr = ""
                rc = bcSetChk.First()
                Do While rc = FE_OK
                    bcChk.setID = bcSetChk.ID
                    If bcChk.Get(nID) = FE_OK Then
                        If Len(bcSetStr) > 0 Then bcSetStr = bcSetStr + ","
                        bcSetStr = bcSetStr + Trim$(Str$(bcSetChk.ID))
                    End If
                    rc = bcSetChk.Next()
                Loop
                If Len(bcSetStr) > 0 Then
                    If Len(reasons) > 0 Then reasons = reasons + " "
                    reasons = reasons + "BC[set " + bcSetStr + "]"
                End If

                ' Check load sets
                ldSetStr = ""
                rc = ldSetChk.First()
                Do While rc = FE_OK
                    ldChk.setID = ldSetChk.ID
                    foundInSet = False
                    ldRc = ldChk.First()
                    Do While ldRc = FE_OK And Not foundInSet
                        If ldChk.meshID = nID Then
                            foundInSet = True
                        Else
                            ldRc = ldChk.Next()
                        End If
                    Loop
                    If foundInSet Then
                        If Len(ldSetStr) > 0 Then ldSetStr = ldSetStr + ","
                        ldSetStr = ldSetStr + Trim$(Str$(ldSetChk.ID))
                    End If
                    rc = ldSetChk.Next()
                Loop
                If Len(ldSetStr) > 0 Then
                    If Len(reasons) > 0 Then reasons = reasons + " "
                    reasons = reasons + "load[set " + ldSetStr + "]"
                End If

                If Len(reasons) = 0 Then reasons = "geometry or locked group"
                If Len(survivedMsg) > 0 Then survivedMsg = survivedMsg + "; "
                survivedMsg = survivedMsg + "Node " + Trim$(Str$(nID)) + " (" + reasons + ")"
            End If
        Next i

        If orphanCount < attempted Then
            App.feAppMessage(FCM_WARNING, "  " + Str$(attempted - orphanCount) _
                + " orphan node(s) could not be deleted: " + survivedMsg)
        End If
    End If

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
