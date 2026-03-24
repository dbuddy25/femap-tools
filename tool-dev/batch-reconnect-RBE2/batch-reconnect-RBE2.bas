' batch-reconnect-RBE2.bas
' Reconnects multiple RBE2 elements to new surfaces after remeshing.
' Automatically matches each surface to the nearest RBE2 based on
' old dependent node positions, then reconnects. Cleans up orphaned nodes.

Const MAX_ENT = 500

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Select RBE2 Elements
    ' =============================================
    Dim rbe2Set As femap.Set
    Set rbe2Set = App.feSet

    rc = rbe2Set.Select(FT_ELEM, True, "Select RBE2 Elements to Reconnect")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected - exiting")
        Exit Sub
    End If

    ' Validate all selected elements are RBE2s
    Dim el As femap.Elem
    Set el = App.feElem
    Dim tempID As Long
    tempID = rbe2Set.First()
    Do While tempID > 0
        rc = el.Get(tempID)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Failed to read element " + Str$(tempID))
            Exit Sub
        End If
        If el.type <> FET_L_RIGID Or el.topology <> FTO_RIGIDLIST Then
            App.feAppMessage(FCM_ERROR, "Element " + Str$(tempID) + " is not an RBE2 - exiting")
            Exit Sub
        End If
        tempID = rbe2Set.Next()
    Loop

    Dim numRBE2 As Long
    numRBE2 = rbe2Set.Count

    If numRBE2 > MAX_ENT Then
        App.feAppMessage(FCM_ERROR, "Too many RBE2s selected (max " + Str$(MAX_ENT) + ")")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(numRBE2) + " RBE2 element(s)")

    ' =============================================
    ' Section 2: Read RBE2 Data + Compute Centroids
    ' =============================================
    Dim nd As femap.Node
    Set nd = App.feNode

    Dim rbe2IDs(MAX_ENT) As Long
    Dim rbe2IndepNodes(MAX_ENT) As Long
    Dim rbe2Cx(MAX_ENT) As Double
    Dim rbe2Cy(MAX_ENT) As Double
    Dim rbe2Cz(MAX_ENT) As Double
    Dim rbe2OldCount(MAX_ENT) As Long
    Dim rbe2DOF(MAX_ENT, 5) As Long
    Dim rbe2NewCount(MAX_ENT) As Long

    ' Combined old node set for orphan cleanup
    Dim allOldNodes As femap.Set
    Set allOldNodes = App.feSet

    Dim r As Long
    r = 0
    Dim elemID As Long
    elemID = rbe2Set.First()

    Do While elemID > 0
        rc = el.Get(elemID)
        rbe2IDs(r) = elemID
        rbe2IndepNodes(r) = el.node(0)

        ' Get dependent nodes
        Dim oldCount As Long
        Dim vOldNodes As Variant
        Dim vOldFaces As Variant
        Dim vOldWeights As Variant
        Dim vOldDOF As Variant

        rc = el.GetNodeList(0, oldCount, vOldNodes, vOldFaces, vOldWeights, vOldDOF)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Failed to read node list for RBE2 " + Str$(elemID))
            Exit Sub
        End If

        rbe2OldCount(r) = oldCount

        ' Store DOF pattern
        Dim d As Long
        For d = 0 To 5
            rbe2DOF(r, d) = CLng(vOldDOF(d))
        Next d

        ' Compute centroid of old dependent nodes + add to combined set
        Dim sumX As Double, sumY As Double, sumZ As Double
        Dim validCount As Long
        sumX = 0: sumY = 0: sumZ = 0: validCount = 0

        Dim i As Long
        For i = 0 To oldCount - 1
            Dim nodeID As Long
            nodeID = CLng(vOldNodes(i))
            allOldNodes.Add(nodeID)
            rc = nd.Get(nodeID)
            If rc = FE_OK Then
                sumX = sumX + nd.x
                sumY = sumY + nd.y
                sumZ = sumZ + nd.z
                validCount = validCount + 1
            End If
        Next i

        If validCount > 0 Then
            rbe2Cx(r) = sumX / validCount
            rbe2Cy(r) = sumY / validCount
            rbe2Cz(r) = sumZ / validCount
        Else
            App.feAppMessage(FCM_WARNING, "RBE2 " + Str$(elemID) + " has no readable dependent nodes")
        End If

        r = r + 1
        elemID = rbe2Set.Next()
    Loop

    ' =============================================
    ' Section 3: Select Surfaces
    ' =============================================
    Dim surfSet As femap.Set
    Set surfSet = App.feSet

    rc = surfSet.Select(FT_SURFACE, True, "Select Surfaces for RBE2 Reconnection")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No surfaces selected - exiting")
        Exit Sub
    End If

    Dim numSurfaces As Long
    numSurfaces = surfSet.Count

    If numSurfaces > MAX_ENT Then
        App.feAppMessage(FCM_ERROR, "Too many surfaces selected (max " + Str$(MAX_ENT) + ")")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(numSurfaces) + " surface(s)")

    ' =============================================
    ' Section 4: Compute Surface Centroids
    ' =============================================
    Dim surfIDs(MAX_ENT) As Long
    Dim surfCx(MAX_ENT) As Double
    Dim surfCy(MAX_ENT) As Double
    Dim surfCz(MAX_ENT) As Double
    Dim surfMatchedRBE2(MAX_ENT) As Long

    Dim tempNodeSet As femap.Set
    Set tempNodeSet = App.feSet

    Dim s As Long
    s = 0
    Dim surfID As Long
    surfID = surfSet.First()

    Do While surfID > 0
        surfIDs(s) = surfID

        tempNodeSet.Clear()
        tempNodeSet.AddRule(surfID, FGD_NODE_ATSURFACE)

        If tempNodeSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "Surface " + Str$(surfID) + " has no mesh nodes - skipping")
            surfCx(s) = 1E+30: surfCy(s) = 1E+30: surfCz(s) = 1E+30
        Else
            sumX = 0: sumY = 0: sumZ = 0: validCount = 0
            nodeID = tempNodeSet.First()
            Do While nodeID > 0
                rc = nd.Get(nodeID)
                If rc = FE_OK Then
                    sumX = sumX + nd.x
                    sumY = sumY + nd.y
                    sumZ = sumZ + nd.z
                    validCount = validCount + 1
                End If
                nodeID = tempNodeSet.Next()
            Loop

            If validCount > 0 Then
                surfCx(s) = sumX / validCount
                surfCy(s) = sumY / validCount
                surfCz(s) = sumZ / validCount
            End If
        End If

        s = s + 1
        surfID = surfSet.Next()
    Loop

    ' =============================================
    ' Section 5: Match Surfaces to RBE2s
    ' =============================================
    Dim dx As Double, dy As Double, dz As Double
    Dim dist As Double, bestDist As Double
    Dim bestRBE2 As Long

    For s = 0 To numSurfaces - 1
        bestDist = 1E+30
        bestRBE2 = -1
        For r = 0 To numRBE2 - 1
            dx = surfCx(s) - rbe2Cx(r)
            dy = surfCy(s) - rbe2Cy(r)
            dz = surfCz(s) - rbe2Cz(r)
            dist = Sqr(dx * dx + dy * dy + dz * dz)
            If dist < bestDist Then
                bestDist = dist
                bestRBE2 = r
            End If
        Next r
        surfMatchedRBE2(s) = bestRBE2

        If bestRBE2 >= 0 Then
            App.feAppMessage(FCM_NORMAL, "Surface " + Str$(surfIDs(s)) + _
                " -> RBE2 " + Str$(rbe2IDs(bestRBE2)) + " (dist=" + Format$(bestDist, "0.000") + ")")
        End If
    Next s

    ' =============================================
    ' Section 6: Reconnect Each RBE2
    ' =============================================
    Dim newNodeSet As femap.Set
    Set newNodeSet = App.feSet

    ' Combined new node set for orphan cleanup
    Dim allNewNodes As femap.Set
    Set allNewNodes = App.feSet

    Dim reconnected As Long
    reconnected = 0

    ' Per-RBE2 surface list strings for the report
    Dim rbe2SurfStr(MAX_ENT) As String
    Dim rbe2MatchDist(MAX_ENT) As Double

    For r = 0 To numRBE2 - 1
        ' Build node set from all surfaces matched to this RBE2
        newNodeSet.Clear()
        rbe2SurfStr(r) = ""
        rbe2MatchDist(r) = 0

        Dim matchCount As Long
        matchCount = 0

        For s = 0 To numSurfaces - 1
            If surfMatchedRBE2(s) = r Then
                newNodeSet.AddRule(surfIDs(s), FGD_NODE_ATSURFACE)
                If Len(rbe2SurfStr(r)) > 0 Then rbe2SurfStr(r) = rbe2SurfStr(r) + ", "
                rbe2SurfStr(r) = rbe2SurfStr(r) + Trim$(Str$(surfIDs(s)))
                ' Track distance to this RBE2's centroid
                dx = surfCx(s) - rbe2Cx(r)
                dy = surfCy(s) - rbe2Cy(r)
                dz = surfCz(s) - rbe2Cz(r)
                dist = Sqr(dx * dx + dy * dy + dz * dz)
                If dist > rbe2MatchDist(r) Then rbe2MatchDist(r) = dist
                matchCount = matchCount + 1
            End If
        Next s

        If matchCount = 0 Then
            App.feAppMessage(FCM_WARNING, "RBE2 " + Str$(rbe2IDs(r)) + " - no surfaces matched, skipping")
            rbe2NewCount(r) = 0
            GoTo NextRBE2
        End If

        ' Remove the independent node
        newNodeSet.Remove(rbe2IndepNodes(r))

        If newNodeSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "RBE2 " + Str$(rbe2IDs(r)) + " - no dependent nodes on matched surfaces")
            rbe2NewCount(r) = 0
            GoTo NextRBE2
        End If

        ' Add to combined new node set
        allNewNodes.AddSet(newNodeSet.ID)

        ' Build arrays
        Dim newCount As Long
        newCount = newNodeSet.Count
        rbe2NewCount(r) = newCount

        Dim vNewNodes As Variant
        newNodeSet.GetArray(newCount, vNewNodes)

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
                vNewDOF(i * 6 + d) = rbe2DOF(r, d)
            Next d
        Next i

        ' Update the element
        rc = el.Get(rbe2IDs(r))
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Failed to re-read RBE2 " + Str$(rbe2IDs(r)))
            GoTo NextRBE2
        End If

        rc = el.PutNodeList(0, newCount, vNewNodes, vNewFaces, vNewWeights, vNewDOF)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Failed to set node list for RBE2 " + Str$(rbe2IDs(r)))
            GoTo NextRBE2
        End If

        rc = el.Put(rbe2IDs(r))
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Failed to save RBE2 " + Str$(rbe2IDs(r)))
            GoTo NextRBE2
        End If

        reconnected = reconnected + 1
NextRBE2:
    Next r

    ' =============================================
    ' Section 7: Delete Orphaned Old Nodes
    ' =============================================
    Dim orphanCount As Long
    orphanCount = 0

    Dim candidateSet As femap.Set
    Set candidateSet = App.feSet
    candidateSet.AddSet(allOldNodes.ID)
    candidateSet.RemoveSet(allNewNodes.ID)

    If candidateSet.Count > 0 Then
        Dim refElemSet As femap.Set
        Set refElemSet = App.feSet
        refElemSet.AddSetRule(candidateSet.ID, FGD_ELEM_BYNODE)

        If refElemSet.Count > 0 Then
            Dim usedNodeSet As femap.Set
            Set usedNodeSet = App.feSet
            usedNodeSet.AddSetRule(refElemSet.ID, FGD_NODE_ONELEM)
            candidateSet.RemoveSet(usedNodeSet.ID)
        End If

        nodeID = candidateSet.First()
        Do While nodeID > 0
            rc = App.feDelete(FT_NODE, nodeID)
            If rc = FE_OK Then orphanCount = orphanCount + 1
            nodeID = candidateSet.Next()
        Loop
    End If

    ' =============================================
    ' Section 8: Report
    ' =============================================
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_HIGHLIGHT, "==========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Batch Reconnect RBE2 - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "==========================================")
    App.feAppMessage(FCM_NORMAL, "  RBE2s selected:          " + Str$(numRBE2))
    App.feAppMessage(FCM_NORMAL, "  RBE2s reconnected:       " + Str$(reconnected))
    App.feAppMessage(FCM_NORMAL, "  Surfaces matched:        " + Str$(numSurfaces))
    App.feAppMessage(FCM_NORMAL, "  Orphaned nodes deleted:  " + Str$(orphanCount))
    App.feAppMessage(FCM_HIGHLIGHT, "------------------------------------------")
    App.feAppMessage(FCM_NORMAL, "  RBE2     Indep   Surfaces          Old > New")

    For r = 0 To numRBE2 - 1
        Dim line As String
        line = "  " + Format$(rbe2IDs(r), "@@@@@@") + _
               "  " + Format$(rbe2IndepNodes(r), "@@@@@@") + _
               "   " + rbe2SurfStr(r)
        ' Pad surface list to ~20 chars
        Do While Len(line) < 52
            line = line + " "
        Loop
        line = line + Str$(rbe2OldCount(r)) + " >" + Str$(rbe2NewCount(r))
        App.feAppMessage(FCM_NORMAL, line)
    Next r

    App.feAppMessage(FCM_HIGHLIGHT, "==========================================")
End Sub
