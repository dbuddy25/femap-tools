' create_nodes_and_elements.bas
' Creates nodes, an isotropic material, a shell property, and a CQUAD4 element.
' Demonstrates the basic entity creation workflow in the Femap API.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' --- Create an Isotropic Material ---
    Dim mt As femap.Matl
    Set mt = App.feMaterial
    mt.title = "Aluminum 6061-T6"
    mt.type = 0                          ' 0 = Isotropic
    mt.mval(0) = 68900.0                 ' E (Young's Modulus) [MPa]
    mt.mval(1) = 25900.0                 ' G (Shear Modulus) [MPa]
    mt.mval(2) = 0.33                    ' NU (Poisson's Ratio)
    mt.mval(3) = 2.71E-09               ' RHO (Density) [tonne/mm^3]
    Dim matlID As Long
    matlID = mt.NextEmptyID
    rc = mt.Put(matlID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to create material")
        Exit Sub
    End If

    ' --- Create a Shell Property (PSHELL) ---
    Dim pr As femap.Prop
    Set pr = App.feProperty
    pr.title = "Shell t=2.0"
    pr.type = FET_L_PLATE                ' Linear plate property
    pr.matlID = matlID
    pr.pval(0) = 2.0                     ' Thickness
    Dim propID As Long
    propID = pr.NextEmptyID
    rc = pr.Put(propID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to create property")
        Exit Sub
    End If

    ' --- Create 4 Nodes for a CQUAD4 ---
    Dim nd As femap.Node
    Set nd = App.feNode

    ' Node 1: (0, 0, 0)
    nd.x = 0.0 : nd.y = 0.0 : nd.z = 0.0
    rc = nd.Put(1)

    ' Node 2: (10, 0, 0)
    nd.x = 10.0 : nd.y = 0.0 : nd.z = 0.0
    rc = nd.Put(2)

    ' Node 3: (10, 10, 0)
    nd.x = 10.0 : nd.y = 10.0 : nd.z = 0.0
    rc = nd.Put(3)

    ' Node 4: (0, 10, 0)
    nd.x = 0.0 : nd.y = 10.0 : nd.z = 0.0
    rc = nd.Put(4)

    ' --- Create a CQUAD4 Element ---
    Dim el As femap.Elem
    Set el = App.feElem
    el.type = FET_L_PLATE                ' Linear plate
    el.topology = FTO_QUAD4              ' Quad4 topology
    el.propID = propID
    el.node(0) = 1
    el.node(1) = 2
    el.node(2) = 3
    el.node(3) = 4
    Dim elemID As Long
    elemID = el.NextEmptyID
    rc = el.Put(elemID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to create element")
        Exit Sub
    End If

    ' --- Refresh and report ---
    App.feViewRegenerate(0)
    App.feAppMessage(FCM_NORMAL, "Created material " + Str$(matlID) + _
        ", property " + Str$(propID) + ", element " + Str$(elemID))
End Sub
