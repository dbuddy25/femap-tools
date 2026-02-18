' group_management.bas
' Creates and modifies groups using rules and boolean operations.
' Demonstrates: Group creation, AddRule, Group generation, Boolean ops.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Pattern 1: Create Group from Selected Elements
    ' =============================================
    Dim elemSet As femap.Set
    Set elemSet = App.feSet
    rc = elemSet.Select(FT_ELEM, True, "Select Elements for Group")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected")
        Exit Sub
    End If

    Dim gp As femap.Group
    Set gp = App.feGroup
    Dim gpID As Long
    gpID = gp.NextEmptyID
    gp.title = "Selected Elements"

    ' Add elements from set to group
    Dim eID As Long
    eID = elemSet.First()
    Do While eID > 0
        gp.Add(FT_ELEM, eID)
        eID = elemSet.Next()
    Loop

    rc = gp.Put(gpID)
    App.feAppMessage(FCM_NORMAL, "Created group " + Str$(gpID) + _
        " with " + Str$(elemSet.Count) + " elements")

    ' =============================================
    ' Pattern 2: Generate Group from Property
    ' =============================================
    Dim propID As Long
    rc = App.feSelectEntity(FT_PROP, "Select Property for Group", propID)
    If rc = FE_OK Then
        Dim propGpID As Long
        rc = App.feGroupGenProp(propGpID, propID)
        If rc = FE_OK Then
            App.feAppMessage(FCM_NORMAL, "Generated property group " + _
                Str$(propGpID))
        End If
    End If

    ' =============================================
    ' Pattern 3: Create Group with Rules
    ' =============================================
    Dim gp2 As femap.Group
    Set gp2 = App.feGroup
    Dim gp2ID As Long
    gp2ID = gp2.NextEmptyID
    gp2.title = "Plate Elements"

    ' Add all linear plate elements by type rule
    gp2.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)

    rc = gp2.Put(gp2ID)

    ' Evaluate to populate from rules
    rc = App.feGroupEvaluate(gp2ID)

    App.feAppMessage(FCM_NORMAL, "Created plate element group " + Str$(gp2ID))

    ' =============================================
    ' Pattern 4: Create Group per Solid
    ' =============================================
    Dim sd As femap.Solid
    Set sd = App.feSolid
    Dim sdID As Long

    sdID = sd.First()
    Do While sdID > 0
        rc = sd.Get(sdID)
        If rc = FE_OK Then
            Dim solidGpID As Long
            rc = App.feGroupGenSolid(solidGpID, sdID)
            If rc = FE_OK Then
                ' Rename the group with solid title
                Dim tmpGp As femap.Group
                Set tmpGp = App.feGroup
                rc = tmpGp.Get(solidGpID)
                If rc = FE_OK Then
                    tmpGp.title = "Solid " + Str$(sdID) + " - " + sd.title
                    rc = tmpGp.Put(solidGpID)
                End If
            End If
        End If
        sdID = sd.Next()
    Loop

    ' =============================================
    ' Pattern 5: Boolean Operations on Groups
    ' =============================================

    ' Create two groups for boolean demo
    Dim gpA As femap.Group : Set gpA = App.feGroup
    Dim gpAID As Long : gpAID = gpA.NextEmptyID
    gpA.title = "Group A - All Plates"
    gpA.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)
    rc = gpA.Put(gpAID)
    rc = App.feGroupEvaluate(gpAID)

    Dim gpB As femap.Group : Set gpB = App.feGroup
    Dim gpBID As Long : gpBID = gpB.NextEmptyID
    gpB.title = "Group B - All Solids"
    gpB.AddRule(FET_L_SOLID, FGD_ELEM_BYTYPE)
    rc = gpB.Put(gpBID)
    rc = App.feGroupEvaluate(gpBID)

    ' Union: A + B
    Dim unionID As Long
    rc = App.feGroupBoolean(unionID, 0, gpAID, gpBID)  ' 0 = Union
    If rc = FE_OK Then
        Dim unionGp As femap.Group : Set unionGp = App.feGroup
        rc = unionGp.Get(unionID)
        unionGp.title = "Union (Plates + Solids)"
        rc = unionGp.Put(unionID)
        App.feAppMessage(FCM_NORMAL, "Created union group " + Str$(unionID))
    End If

    ' =============================================
    ' Pattern 6: Add Related Entities to Group
    ' =============================================
    rc = gp.Get(gpID)
    If rc = FE_OK Then
        rc = gp.AddRelatedEntities()
        rc = gp.Put(gpID)
        App.feAppMessage(FCM_NORMAL, "Added related entities to group " + Str$(gpID))
    End If

    App.feViewRegenerate(0)
    App.feAppMessage(FCM_HIGHLIGHT, "Group management complete")
End Sub
