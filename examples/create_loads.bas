' create_loads.bas
' Creates load sets with forces, pressures, and nodal temperatures.
' Demonstrates the LoadSet → LoadDefinition → LoadMesh workflow.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' ===========================================
    ' Part 1: Create Nodal Forces
    ' ===========================================

    ' 1. Create Load Set
    Dim ls As femap.LoadSet
    Set ls = App.feLoadSet
    ls.title = "Applied Forces"
    Dim lsID As Long
    lsID = ls.NextEmptyID
    rc = ls.Put(lsID)

    ' 2. Create Load Definition
    Dim ld As femap.LoadDefinition
    Set ld = App.feLoadDefinition
    ld.setID = lsID
    ld.title = "Tip Forces"
    ld.loadType = FLT_NFORCE
    Dim ldID As Long
    ldID = ld.NextEmptyID
    rc = ld.Put(ldID)

    ' 3. Select nodes to apply forces
    Dim forceNodes As femap.Set
    Set forceNodes = App.feSet
    rc = forceNodes.Select(FT_NODE, True, "Select Nodes for Force Application")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No nodes selected for forces")
        Exit Sub
    End If

    ' 4. Apply -1000 N force in Z direction to each selected node
    Dim lm As femap.LoadMesh
    Set lm = App.feLoadMesh
    Dim nID As Long

    nID = forceNodes.First()
    Do While nID > 0
        lm.setID = lsID
        lm.LoadDefinitionID = ldID
        lm.type = FLT_NFORCE
        lm.nodeID = nID
        lm.dof(0) = False : lm.dof(1) = False : lm.dof(2) = True
        lm.dof(3) = False : lm.dof(4) = False : lm.dof(5) = False
        lm.load(0) = 0.0 : lm.load(1) = 0.0 : lm.load(2) = -1000.0
        lm.load(3) = 0.0 : lm.load(4) = 0.0 : lm.load(5) = 0.0
        rc = lm.Put(-1)
        nID = forceNodes.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Created " + Str$(forceNodes.Count) + _
        " nodal forces in Load Set " + Str$(lsID))

    ' ===========================================
    ' Part 2: Create Elemental Pressure
    ' ===========================================

    ' Create another Load Set for pressure
    Dim ls2 As femap.LoadSet
    Set ls2 = App.feLoadSet
    ls2.title = "Surface Pressure"
    Dim ls2ID As Long
    ls2ID = ls2.NextEmptyID
    rc = ls2.Put(ls2ID)

    ' Load Definition for pressure
    Dim ld2 As femap.LoadDefinition
    Set ld2 = App.feLoadDefinition
    ld2.setID = ls2ID
    ld2.title = "Uniform Pressure"
    ld2.loadType = FLT_EPRESSURE
    Dim ld2ID As Long
    ld2ID = ld2.NextEmptyID
    rc = ld2.Put(ld2ID)

    ' Select elements for pressure
    Dim pressElems As femap.Set
    Set pressElems = App.feSet
    rc = pressElems.Select(FT_ELEM, True, "Select Elements for Pressure")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected for pressure")
        GoTo SkipPressure
    End If

    ' Apply pressure to each element
    Dim lm2 As femap.LoadMesh
    Set lm2 = App.feLoadMesh
    Dim eID As Long

    eID = pressElems.First()
    Do While eID > 0
        lm2.setID = ls2ID
        lm2.LoadDefinitionID = ld2ID
        lm2.type = FLT_EPRESSURE
        lm2.elemID = eID
        lm2.elemFace = 1                ' Top face
        lm2.load(0) = 10.0              ' Pressure value [MPa]
        rc = lm2.Put(-1)
        eID = pressElems.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Created pressure on " + _
        Str$(pressElems.Count) + " elements in Load Set " + Str$(ls2ID))

SkipPressure:

    ' ===========================================
    ' Part 3: Create Nodal Temperature Loads
    ' ===========================================

    ' Temperature gradient in X direction
    Dim ls3 As femap.LoadSet
    Set ls3 = App.feLoadSet
    ls3.title = "Thermal Load"
    Dim ls3ID As Long
    ls3ID = ls3.NextEmptyID
    rc = ls3.Put(ls3ID)

    ' Get all nodes and apply temperature gradient
    Dim nd As femap.Node
    Set nd = App.feNode
    Dim nt As femap.LoadNTemp
    Set nt = App.feLoadNTemp

    Dim allNodes As femap.Set
    Set allNodes = App.feSet
    allNodes.AddAll(FT_NODE)

    If allNodes.Count > 0 Then
        ' Find X range
        Dim xMin As Double : xMin = 1E+30
        Dim xMax As Double : xMax = -1E+30

        nID = allNodes.First()
        Do While nID > 0
            rc = nd.Get(nID)
            If rc = FE_OK Then
                If nd.x < xMin Then xMin = nd.x
                If nd.x > xMax Then xMax = nd.x
            End If
            nID = allNodes.Next()
        Loop

        Dim xRange As Double
        xRange = xMax - xMin
        If xRange < 1E-10 Then xRange = 1.0

        ' Apply linear temperature gradient: 20°C to 120°C
        Dim tMin As Double : tMin = 20.0
        Dim tMax As Double : tMax = 120.0

        allNodes.Reset()
        nID = allNodes.First()
        Do While nID > 0
            rc = nd.Get(nID)
            If rc = FE_OK Then
                Dim frac As Double
                frac = (nd.x - xMin) / xRange
                nt.setID = ls3ID
                nt.nodeID = nID
                nt.temp = tMin + frac * (tMax - tMin)
                rc = nt.Put(-1)
            End If
            nID = allNodes.Next()
        Loop

        App.feAppMessage(FCM_NORMAL, "Applied temperature gradient (" + _
            Str$(tMin) + " to " + Str$(tMax) + " deg) to " + _
            Str$(allNodes.Count) + " nodes")
    End If

    App.feViewRegenerate(0)
    App.feAppMessage(FCM_NORMAL, "Load creation complete")
End Sub
