' select_and_iterate.bas
' Demonstrates Set selection, iteration, rule-based population, and array conversion.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' === Pattern 1: Interactive Selection and Iteration ===
    Dim elemSet As femap.Set
    Set elemSet = App.feSet

    rc = elemSet.Select(FT_ELEM, True, "Select Elements to Process")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(elemSet.Count) + " elements")

    Dim el As femap.Elem
    Set el = App.feElem
    Dim id As Long

    id = elemSet.First()
    Do While id > 0
        rc = el.Get(id)
        If rc = FE_OK Then
            App.feAppMessage(FCM_NORMAL, "Elem " + Str$(id) + _
                " PropID=" + Str$(el.propID) + _
                " Type=" + Str$(el.type))
        End If
        id = elemSet.Next()
    Loop

    ' === Pattern 2: Rule-Based Population ===
    ' Get all elements using a specific property
    Dim propElemSet As femap.Set
    Set propElemSet = App.feSet

    Dim propSet As femap.Set
    Set propSet = App.feSet
    rc = propSet.Select(FT_PROP, True, "Select Property to Find Elements")
    If rc <> FE_OK Then Exit Sub

    ' Add elements by property rule
    Dim pID As Long
    pID = propSet.First()
    Do While pID > 0
        propElemSet.AddRule(pID, FGD_ELEM_BYPROP)
        pID = propSet.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Found " + Str$(propElemSet.Count) + _
        " elements with selected properties")

    ' === Pattern 3: Chained Rules (Property → Elements → Nodes) ===
    Dim nodeSet As femap.Set
    Set nodeSet = App.feSet
    nodeSet.AddSetRule(propElemSet.ID, FGD_NODE_ONELEM)

    App.feAppMessage(FCM_NORMAL, "Found " + Str$(nodeSet.Count) + _
        " nodes on those elements")

    ' === Pattern 4: Set to Array Conversion ===
    Dim count As Long
    Dim vIDs As Variant
    count = nodeSet.Count
    If count > 0 Then
        nodeSet.GetArray(count, vIDs)

        ' Process array
        Dim nd As femap.Node
        Set nd = App.feNode
        Dim sumX As Double : sumX = 0.0
        Dim sumY As Double : sumY = 0.0
        Dim sumZ As Double : sumZ = 0.0

        Dim i As Long
        For i = 0 To count - 1
            rc = nd.Get(vIDs(i))
            If rc = FE_OK Then
                sumX = sumX + nd.x
                sumY = sumY + nd.y
                sumZ = sumZ + nd.z
            End If
        Next

        App.feAppMessage(FCM_NORMAL, "Centroid: (" + _
            Str$(sumX / count) + ", " + _
            Str$(sumY / count) + ", " + _
            Str$(sumZ / count) + ")")
    End If

    ' === Pattern 5: Boolean Set Operations ===
    Dim allPlates As femap.Set
    Set allPlates = App.feSet
    allPlates.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)

    Dim allQuads As femap.Set
    Set allQuads = App.feSet
    allQuads.AddRule(FTO_QUAD4, FGD_ELEM_BYSHAPE)

    ' Intersection: only CQUAD4 plates
    Dim quadPlates As femap.Set
    Set quadPlates = App.feSet
    quadPlates.AddSet(allPlates.ID)
    quadPlates.IntersectSet(allQuads.ID)

    App.feAppMessage(FCM_NORMAL, "CQUAD4 count: " + Str$(quadPlates.Count))

    ' === Pattern 6: Membership Testing ===
    If elemSet.IsAdded(1) Then
        App.feAppMessage(FCM_NORMAL, "Element 1 is in the selection")
    Else
        App.feAppMessage(FCM_NORMAL, "Element 1 is NOT in the selection")
    End If

    App.feAppMessage(FCM_NORMAL, "Done - all patterns demonstrated")
End Sub
