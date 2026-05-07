' batch-reconnect-RBE2.bas
' Reconnects multiple RBE2 elements to new surfaces after remeshing.
' Automatically matches each surface to the nearest RBE2 based on
' old dependent node positions, then reconnects. Cleans up orphaned nodes.

Const MAX_ENT = 500

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' All variable declarations up front
    Dim el As femap.Elem
    Dim nd As femap.Node
    Dim rbe2Set As femap.Set
    Dim surfSet As femap.Set
    Dim tempNodeSet As femap.Set
    Dim newNodeSet As femap.Set
    Dim allOldNodes As femap.Set
    Dim allNewNodes As femap.Set
    Dim candidateSet As femap.Set
    Dim refElemSet As femap.Set
    Dim usedNodeSet As femap.Set

    Dim rbe2IDs(MAX_ENT) As Long
    Dim rbe2IndepNodes(MAX_ENT) As Long
    Dim rbe2Cx(MAX_ENT) As Double
    Dim rbe2Cy(MAX_ENT) As Double
    Dim rbe2Cz(MAX_ENT) As Double
    Dim rbe2OldCount(MAX_ENT) As Long
    Dim rbe2DOF(MAX_ENT, 5) As Long
    Dim rbe2NewCount(MAX_ENT) As Long
    Dim rbe2SurfStr(MAX_ENT) As String

    Dim surfIDs(MAX_ENT) As Long
    Dim surfCx(MAX_ENT) As Double
    Dim surfCy(MAX_ENT) As Double
    Dim surfCz(MAX_ENT) As Double
    Dim surfMatchedRBE2(MAX_ENT) As Long

    Dim numRBE2 As Long
    Dim numSurfaces As Long
    Dim r As Long
    Dim s As Long
    Dim i As Long
    Dim d As Long
    Dim elemID As Long
    Dim surfID As Long
    Dim nodeID As Long
    Dim tempID As Long
    Dim oldCount As Long
    Dim newCount As Long
    Dim matchCount As Long
    Dim reconnected As Long
    Dim orphanCount As Long
    Dim validCount As Long
    Dim sumX As Double
    Dim sumY As Double
    Dim sumZ As Double
    Dim dx As Double
    Dim dy As Double
    Dim dz As Double
    Dim dist As Double
    Dim bestDist As Double
    Dim bestRBE2 As Long
    Dim skipRBE2 As Boolean
    Dim vOldNodes As Variant
    Dim vOldFaces As Variant
    Dim vOldWeights As Variant
    Dim vOldDOF As Variant
    Dim vNewNodes As Variant
    Dim vNewFaces As Variant
    Dim vNewWeights As Variant
    Dim vNewDOF As Variant
    Dim attempted As Long
    Dim vCandIDs As Variant
    Dim survivedMsg As String

    Set el = App.feElem
    Set nd = App.feNode

    ' =============================================
    ' Section 1: Select RBE2 Elements
    ' =============================================
    Set rbe2Set = App.feSet

    rc = rbe2Set.Select(FT_ELEM, True, "Select RBE2 Elements to Reconnect")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected - exiting")
        Exit Sub
    End If

    ' Validate all selected elements are RBE2s
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

    numRBE2 = rbe2Set.Count

    If numRBE2 > MAX_ENT Then
        App.feAppMessage(FCM_ERROR, "Too many RBE2s selected (max " + Str$(MAX_ENT) + ")")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(numRBE2) + " RBE2 element(s)")

    ' =============================================
    ' Section 2: Read RBE2 Data + Compute Centroids
    ' =============================================
    Set allOldNodes = App.feSet

    r = 0
    elemID = rbe2Set.First()

    Do While elemID > 0
        rc = el.Get(elemID)
        rbe2IDs(r) = elemID
        rbe2IndepNodes(r) = el.node(0)

        rc = el.GetNodeList(0, oldCount, vOldNodes, vOldFaces, vOldWeights, vOldDOF)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Failed to read node list for RBE2 " + Str$(elemID))
            Exit Sub
        End If

        rbe2OldCount(r) = oldCount

        ' Store DOF pattern
        For d = 0 To 5
            rbe2DOF(r, d) = CLng(vOldDOF(d))
        Next d

        ' Compute centroid of old dependent nodes + add to combined set
        sumX = 0: sumY = 0: sumZ = 0: validCount = 0

        For i = 0 To oldCount - 1
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

        App.feAppMessage(FCM_NORMAL, "RBE2 " + Str$(elemID) + " centroid: " + Str$(rbe2Cx(r)) + "," + Str$(rbe2Cy(r)) + "," + Str$(rbe2Cz(r)) + " (" + Str$(oldCount) + " dep nodes)")

        r = r + 1
        elemID = rbe2Set.Next()
    Loop

    ' =============================================
    ' Section 3: Select Surfaces
    ' =============================================
    Set surfSet = App.feSet

    rc = surfSet.Select(FT_SURFACE, True, "Select Surfaces for RBE2 Reconnection")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No surfaces selected - exiting")
        Exit Sub
    End If

    numSurfaces = surfSet.Count

    If numSurfaces > MAX_ENT Then
        App.feAppMessage(FCM_ERROR, "Too many surfaces selected (max " + Str$(MAX_ENT) + ")")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(numSurfaces) + " surface(s)")

    ' =============================================
    ' Section 4: Compute Surface Centroids
    ' =============================================
    Set tempNodeSet = App.feSet

    s = 0
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

            App.feAppMessage(FCM_NORMAL, "Surface " + Str$(surfID) + ": " + Str$(tempNodeSet.Count) + " nodes, centroid: " + Str$(surfCx(s)) + "," + Str$(surfCy(s)) + "," + Str$(surfCz(s)))
        End If

        s = s + 1
        surfID = surfSet.Next()
    Loop

    ' =============================================
    ' Section 5: Match Surfaces to RBE2s
    ' =============================================
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
            App.feAppMessage(FCM_NORMAL, "Match: Surface " + Str$(surfIDs(s)) + " -> RBE2 " + Str$(rbe2IDs(bestRBE2)) + " (dist=" + Str$(Int(bestDist * 1000) / 1000) + ")")
        End If
    Next s

    ' =============================================
    ' Section 6: Reconnect Each RBE2
    ' =============================================
    Set newNodeSet = App.feSet
    Set allNewNodes = App.feSet

    reconnected = 0

    For r = 0 To numRBE2 - 1
        skipRBE2 = False

        ' Build node set from all surfaces matched to this RBE2
        newNodeSet.Clear()
        rbe2SurfStr(r) = ""
        matchCount = 0

        For s = 0 To numSurfaces - 1
            If surfMatchedRBE2(s) = r Then
                newNodeSet.AddRule(surfIDs(s), FGD_NODE_ATSURFACE)
                If Len(rbe2SurfStr(r)) > 0 Then rbe2SurfStr(r) = rbe2SurfStr(r) + ", "
                rbe2SurfStr(r) = rbe2SurfStr(r) + Trim$(Str$(surfIDs(s)))
                matchCount = matchCount + 1
            End If
        Next s

        App.feAppMessage(FCM_NORMAL, "RBE2 " + Str$(rbe2IDs(r)) + ": " + Str$(matchCount) + " surface(s), " + Str$(newNodeSet.Count) + " nodes")

        If matchCount = 0 Then
            App.feAppMessage(FCM_WARNING, "RBE2 " + Str$(rbe2IDs(r)) + " - no surfaces matched, skipping")
            rbe2NewCount(r) = 0
            skipRBE2 = True
        End If

        If Not skipRBE2 Then
            ' Remove old dependent nodes (may still be on surface from prior mesh)
            newNodeSet.RemoveSet(allOldNodes.ID)

            ' Remove the independent node
            newNodeSet.Remove(rbe2IndepNodes(r))

            App.feAppMessage(FCM_NORMAL, "  After removing indep node: " + Str$(newNodeSet.Count) + " nodes")

            If newNodeSet.Count = 0 Then
                App.feAppMessage(FCM_WARNING, "RBE2 " + Str$(rbe2IDs(r)) + " - no dependent nodes on matched surfaces")
                rbe2NewCount(r) = 0
                skipRBE2 = True
            End If
        End If

        If Not skipRBE2 Then
            ' Add to combined new node set
            allNewNodes.AddSet(newNodeSet.ID)

            ' Build arrays
            newCount = newNodeSet.Count
            rbe2NewCount(r) = newCount

            newNodeSet.GetArray(newCount, vNewNodes)

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
                skipRBE2 = True
            End If
        End If

        If Not skipRBE2 Then
            rc = el.PutNodeList(0, newCount, vNewNodes, vNewFaces, vNewWeights, vNewDOF)
            If rc <> FE_OK Then
                App.feAppMessage(FCM_ERROR, "PutNodeList FAILED for RBE2 " + Str$(rbe2IDs(r)) + " rc=" + Str$(rc))
                skipRBE2 = True
            End If
        End If

        If Not skipRBE2 Then
            rc = el.Put(rbe2IDs(r))
            If rc <> FE_OK Then
                App.feAppMessage(FCM_ERROR, "Put FAILED for RBE2 " + Str$(rbe2IDs(r)) + " rc=" + Str$(rc))
                skipRBE2 = True
            End If
        End If

        If Not skipRBE2 Then
            App.feAppMessage(FCM_NORMAL, "Updated RBE2 " + Str$(rbe2IDs(r)) + " with " + Str$(newCount) + " new dependent nodes")
            reconnected = reconnected + 1
        End If
    Next r

    ' =============================================
    ' Section 7: Delete Orphaned Old Nodes
    ' =============================================
    orphanCount = 0

    Set candidateSet = App.feSet
    candidateSet.AddSet(allOldNodes.ID)
    candidateSet.RemoveSet(allNewNodes.ID)

    App.feAppMessage(FCM_NORMAL, "Orphan candidates: " + Str$(candidateSet.Count) + " (old=" + Str$(allOldNodes.Count) + " new=" + Str$(allNewNodes.Count) + ")")

    If candidateSet.Count > 0 Then
        Set refElemSet = App.feSet
        refElemSet.AddSetRule(candidateSet.ID, FGD_ELEM_BYNODE)

        If refElemSet.Count > 0 Then
            Set usedNodeSet = App.feSet
            usedNodeSet.AddSetRule(refElemSet.ID, FGD_NODE_ONELEM)
            candidateSet.RemoveSet(usedNodeSet.ID)
        End If

        App.feAppMessage(FCM_NORMAL, "True orphans after element check: " + Str$(candidateSet.Count))

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

    App.feAppMessage(FCM_HIGHLIGHT, "==========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Batch Reconnect RBE2 - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "==========================================")
    App.feAppMessage(FCM_NORMAL, "  RBE2s selected:          " + Str$(numRBE2))
    App.feAppMessage(FCM_NORMAL, "  RBE2s reconnected:       " + Str$(reconnected))
    App.feAppMessage(FCM_NORMAL, "  Surfaces matched:        " + Str$(numSurfaces))
    App.feAppMessage(FCM_NORMAL, "  Orphaned nodes deleted:  " + Str$(orphanCount))
    App.feAppMessage(FCM_HIGHLIGHT, "------------------------------------------")

    For r = 0 To numRBE2 - 1
        App.feAppMessage(FCM_NORMAL, "  RBE2 " + Str$(rbe2IDs(r)) + " (indep " + Str$(rbe2IndepNodes(r)) + ") -> Surfs: " + rbe2SurfStr(r) + "  [" + Str$(rbe2OldCount(r)) + " >" + Str$(rbe2NewCount(r)) + "]")
    Next r

    App.feAppMessage(FCM_HIGHLIGHT, "==========================================")
End Sub
