' modify_element_properties.bas
' Changes element properties, colors, and demonstrates element update patterns.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' --- Select elements to modify ---
    Dim elemSet As femap.Set
    Set elemSet = App.feSet
    rc = elemSet.Select(FT_ELEM, True, "Select Elements to Modify")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected")
        Exit Sub
    End If

    ' --- Select target property ---
    Dim targetPropID As Long
    rc = App.feSelectEntity(FT_PROP, "Select Target Property", targetPropID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No property selected")
        Exit Sub
    End If

    ' --- Lock UI for performance ---
    App.feAppLock()

    ' --- Iterate and modify ---
    Dim el As femap.Elem
    Set el = App.feElem
    Dim id As Long
    Dim modCount As Long : modCount = 0

    id = elemSet.First()
    Do While id > 0
        rc = el.Get(id)
        If rc = FE_OK Then
            ' Change property
            el.propID = targetPropID

            ' Save back
            rc = el.Put(id)
            If rc = FE_OK Then modCount = modCount + 1
        End If
        id = elemSet.Next()
    Loop

    ' --- Unlock UI and refresh ---
    App.feAppUnlock()
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_NORMAL, "Modified " + Str$(modCount) + " elements")

    ' ================================================================
    ' Bonus: Color RBE2 and RBE3 elements with different colors
    ' ================================================================
    Dim allElem As femap.Set
    Set allElem = App.feSet
    allElem.AddAll(FT_ELEM)

    Dim rbe2Color As Long : rbe2Color = 1  ' Red
    Dim rbe3Color As Long : rbe3Color = 4  ' Blue

    Dim rbe2Count As Long : rbe2Count = 0
    Dim rbe3Count As Long : rbe3Count = 0

    App.feAppLock()

    id = allElem.First()
    Do While id > 0
        rc = el.Get(id)
        If rc = FE_OK Then
            If el.type = FET_L_RIGID Then
                If el.topology = FTO_RIGIDLIST Then
                    ' RBE2
                    el.color = rbe2Color
                    rc = el.Put(id)
                    rbe2Count = rbe2Count + 1
                ElseIf el.topology = FTO_RIGIDLIST2 Then
                    ' RBE3
                    el.color = rbe3Color
                    rc = el.Put(id)
                    rbe3Count = rbe3Count + 1
                End If
            End If
        End If
        id = allElem.Next()
    Loop

    App.feAppUnlock()
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_NORMAL, "Colored " + Str$(rbe2Count) + " RBE2 (red), " + _
        Str$(rbe3Count) + " RBE3 (blue)")
End Sub
