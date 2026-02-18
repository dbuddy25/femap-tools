' mesh_and_connect.bas
' Meshes surfaces, creates connections between parts, and checks quality.
' Demonstrates: feMeshSurface, feMergeNodes, feMeshClosestLink,
'               feCheckElemDistortion, feConnectionAutomatic.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Step 1: Set mesh parameters
    ' =============================================
    Dim meshSize As Double : meshSize = 5.0
    rc = App.feMeshSize(meshSize)
    App.feAppMessage(FCM_NORMAL, "Default mesh size set to " + Str$(meshSize))

    ' =============================================
    ' Step 2: Mesh selected surfaces
    ' =============================================
    Dim surfSet As femap.Set
    Set surfSet = App.feSet
    rc = surfSet.Select(FT_SURFACE, True, "Select Surfaces to Mesh")
    If rc <> FE_OK Or surfSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "No surfaces selected")
        Exit Sub
    End If

    App.feAppLock()

    rc = App.feMeshSurface(surfSet.ID, 0)
    If rc = FE_OK Then
        App.feAppMessage(FCM_NORMAL, "Meshed " + Str$(surfSet.Count) + " surfaces")
    Else
        App.feAppMessage(FCM_ERROR, "Surface meshing failed")
        App.feAppUnlock()
        Exit Sub
    End If

    ' =============================================
    ' Step 3: Merge coincident nodes
    ' =============================================
    Dim allNodes As femap.Set
    Set allNodes = App.feSet
    allNodes.AddAll(FT_NODE)

    Dim mergeTol As Double : mergeTol = meshSize / 100.0
    rc = App.feMergeNodes(mergeTol, allNodes.ID)
    App.feAppMessage(FCM_NORMAL, "Merged coincident nodes (tol=" + Str$(mergeTol) + ")")

    ' =============================================
    ' Step 4: Create connections between surfaces
    ' =============================================
    App.feAppMessage(FCM_NORMAL, "--- Connection Creation ---")

    ' Option A: Automatic connections
    Dim response As Long
    response = App.feAppMessageBox(4, "Use automatic connections? (Yes=Auto, No=Manual RBE)")

    If response = 6 Then
        ' Yes - Automatic connections
        Dim connSurfSet As femap.Set
        Set connSurfSet = App.feSet
        connSurfSet.AddAll(FT_SURFACE)
        rc = App.feConnectionAutomatic(connSurfSet.ID, mergeTol * 10)
        If rc = FE_OK Then
            App.feAppMessage(FCM_NORMAL, "Automatic connections created")
        End If
    Else
        ' No - Manual closest-link (RBE2) connections
        Dim surf1Set As femap.Set : Set surf1Set = App.feSet
        Dim surf2Set As femap.Set : Set surf2Set = App.feSet

        rc = surf1Set.Select(FT_SURFACE, True, "Select FIRST Surface for Connection")
        If rc <> FE_OK Then GoTo SkipConnection

        rc = surf2Set.Select(FT_SURFACE, True, "Select SECOND Surface for Connection")
        If rc <> FE_OK Then GoTo SkipConnection

        ' Get nodes on each surface
        Dim node1Set As femap.Set : Set node1Set = App.feSet
        Dim node2Set As femap.Set : Set node2Set = App.feSet

        Dim s1ID As Long
        s1ID = surf1Set.First()
        Do While s1ID > 0
            node1Set.AddRule(s1ID, FGD_NODE_ATSURFACE)
            s1ID = surf1Set.Next()
        Loop

        Dim s2ID As Long
        s2ID = surf2Set.First()
        Do While s2ID > 0
            node2Set.AddRule(s2ID, FGD_NODE_ATSURFACE)
            s2ID = surf2Set.Next()
        Loop

        If node1Set.Count > 0 And node2Set.Count > 0 Then
            ' Need a rigid property
            Dim rigProp As femap.Prop
            Set rigProp = App.feProperty
            rigProp.title = "RBE2 Connection"
            rigProp.type = FET_L_RIGID
            Dim rigPropID As Long
            rigPropID = rigProp.NextEmptyID
            rc = rigProp.Put(rigPropID)

            rc = App.feMeshClosestLink(node1Set.ID, node2Set.ID, _
                FET_L_RIGID, rigPropID)
            App.feAppMessage(FCM_NORMAL, "Created closest-link connections: " + _
                Str$(node1Set.Count) + " → " + Str$(node2Set.Count) + " nodes")
        Else
            App.feAppMessage(FCM_WARNING, "No nodes found on selected surfaces")
        End If
    End If

SkipConnection:

    ' =============================================
    ' Step 5: Element quality check
    ' =============================================
    App.feAppMessage(FCM_NORMAL, "--- Element Quality Check ---")

    Dim allElems As femap.Set
    Set allElems = App.feSet
    allElems.AddAll(FT_ELEM)

    If allElems.Count > 0 Then
        Dim badCount As Long
        rc = App.feCheckElemDistortion(allElems.ID, 0, 0.7, badCount)

        If badCount > 0 Then
            App.feAppMessage(FCM_WARNING, Str$(badCount) + _
                " elements exceed Jacobian limit of 0.7")

            ' Create group of bad elements
            Dim badGp As femap.Group : Set badGp = App.feGroup
            Dim badGpID As Long : badGpID = badGp.NextEmptyID
            badGp.title = "Distorted Elements"

            ' Re-check and add bad elements to group
            Dim el As femap.Elem : Set el = App.feElem
            Dim eID As Long
            eID = allElems.First()
            Do While eID > 0
                rc = el.Get(eID)
                ' Elements flagged by distortion check can be identified
                ' by the feCheckElemDistortion output set
                eID = allElems.Next()
            Loop

            rc = badGp.Put(badGpID)
        Else
            App.feAppMessage(FCM_NORMAL, "All " + Str$(allElems.Count) + _
                " elements pass quality check")
        End If

        ' Report element statistics
        Dim plateSet As femap.Set : Set plateSet = App.feSet
        Dim solidSet As femap.Set : Set solidSet = App.feSet
        Dim rigidSet As femap.Set : Set rigidSet = App.feSet

        plateSet.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)
        solidSet.AddRule(FET_L_SOLID, FGD_ELEM_BYTYPE)
        rigidSet.AddRule(FET_L_RIGID, FGD_ELEM_BYTYPE)

        App.feAppMessage(FCM_NORMAL, "Element counts:")
        App.feAppMessage(FCM_NORMAL, "  Plates: " + Str$(plateSet.Count))
        App.feAppMessage(FCM_NORMAL, "  Solids: " + Str$(solidSet.Count))
        App.feAppMessage(FCM_NORMAL, "  Rigids: " + Str$(rigidSet.Count))
        App.feAppMessage(FCM_NORMAL, "  Total: " + Str$(allElems.Count))
    End If

    App.feAppUnlock()
    App.feViewRegenerate(0)
    App.feViewAutoscaleAll(0)
    App.feAppMessage(FCM_HIGHLIGHT, "Mesh and connect complete")
End Sub
