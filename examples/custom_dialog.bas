' custom_dialog.bas
' Creates a custom dialog for user input using WinWrap Basic dialog syntax.
' Demonstrates: Begin Dialog, TextBox, CheckBox, DropListBox, DialogFunc.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Simple Dialog Example
    ' =============================================

    ' Prepare items for drop-down lists
    Dim materials$(3)
    materials$(0) = "Aluminum 6061-T6"
    materials$(1) = "Steel AISI 4130"
    materials$(2) = "Titanium Ti-6Al-4V"
    materials$(3) = "Inconel 718"

    Dim elemTypes$(2)
    elemTypes$(0) = "CQUAD4 (Linear Quad)"
    elemTypes$(1) = "CTRIA3 (Linear Tri)"
    elemTypes$(2) = "CQUAD8 (Parabolic Quad)"

    ' Define the dialog
    Begin Dialog MeshSetupDialog 360, 220, "Mesh Setup Tool"
        Text 10, 10, 100, 14, "Mesh Size:"
        TextBox 120, 8, 80, 14, .meshSize

        Text 10, 32, 100, 14, "Material:"
        DropListBox 120, 30, 220, 70, materials$(), .matlChoice

        Text 10, 54, 100, 14, "Element Type:"
        DropListBox 120, 52, 220, 70, elemTypes$(), .elemChoice

        Text 10, 76, 100, 14, "Thickness:"
        TextBox 120, 74, 80, 14, .thickness

        GroupBox 10, 98, 330, 60, "Options"
        CheckBox 20, 114, 150, 14, "Merge coincident nodes", .chkMerge
        CheckBox 20, 132, 150, 14, "Check element quality", .chkQuality
        CheckBox 180, 114, 150, 14, "Autoscale view", .chkAutoscale

        OKButton 80, 190, 90, 22
        CancelButton 190, 190, 90, 22
    End Dialog

    ' Set defaults
    Dim dlg As MeshSetupDialog
    dlg.meshSize = "5.0"
    dlg.matlChoice = 0         ' Aluminum
    dlg.elemChoice = 0         ' CQUAD4
    dlg.thickness = "2.0"
    dlg.chkMerge = 1           ' Checked
    dlg.chkQuality = 1         ' Checked
    dlg.chkAutoscale = 1       ' Checked

    ' Show dialog
    Dim result As Long
    result = Dialog(dlg)

    If result <> -1 Then
        App.feAppMessage(FCM_WARNING, "User cancelled")
        Exit Sub
    End If

    ' --- Process dialog results ---
    Dim meshSizeVal As Double
    meshSizeVal = CDbl(dlg.meshSize)

    Dim thicknessVal As Double
    thicknessVal = CDbl(dlg.thickness)

    Dim doMerge As Boolean
    doMerge = (dlg.chkMerge = 1)

    Dim doQuality As Boolean
    doQuality = (dlg.chkQuality = 1)

    Dim doAutoscale As Boolean
    doAutoscale = (dlg.chkAutoscale = 1)

    ' Report selections
    App.feAppMessage(FCM_NORMAL, "Mesh Size: " + Str$(meshSizeVal))
    App.feAppMessage(FCM_NORMAL, "Material: " + materials$(dlg.matlChoice))
    App.feAppMessage(FCM_NORMAL, "Element Type: " + elemTypes$(dlg.elemChoice))
    App.feAppMessage(FCM_NORMAL, "Thickness: " + Str$(thicknessVal))
    App.feAppMessage(FCM_NORMAL, "Merge: " + Str$(doMerge))
    App.feAppMessage(FCM_NORMAL, "Quality Check: " + Str$(doQuality))

    ' --- Create material based on selection ---
    Dim mt As femap.Matl
    Set mt = App.feMaterial

    Select Case dlg.matlChoice
        Case 0  ' Aluminum
            mt.title = "Aluminum 6061-T6"
            mt.mval(0) = 68900 : mt.mval(2) = 0.33 : mt.mval(3) = 2.71E-09
        Case 1  ' Steel
            mt.title = "Steel AISI 4130"
            mt.mval(0) = 200000 : mt.mval(2) = 0.29 : mt.mval(3) = 7.85E-09
        Case 2  ' Titanium
            mt.title = "Titanium Ti-6Al-4V"
            mt.mval(0) = 113800 : mt.mval(2) = 0.342 : mt.mval(3) = 4.43E-09
        Case 3  ' Inconel
            mt.title = "Inconel 718"
            mt.mval(0) = 205000 : mt.mval(2) = 0.284 : mt.mval(3) = 8.19E-09
    End Select
    mt.type = 0
    mt.mval(1) = mt.mval(0) / (2.0 * (1.0 + mt.mval(2)))  ' G = E / 2(1+nu)
    Dim matlID As Long
    matlID = mt.NextEmptyID
    rc = mt.Put(matlID)

    ' --- Create property ---
    Dim pr As femap.Prop
    Set pr = App.feProperty
    pr.title = "Shell t=" + dlg.thickness
    pr.type = FET_L_PLATE
    pr.matlID = matlID
    pr.pval(0) = thicknessVal
    Dim propID As Long
    propID = pr.NextEmptyID
    rc = pr.Put(propID)

    ' --- Set mesh size ---
    rc = App.feMeshSize(meshSizeVal)

    ' --- Mesh surfaces ---
    Dim surfSet As femap.Set
    Set surfSet = App.feSet
    rc = surfSet.Select(FT_SURFACE, True, "Select Surfaces to Mesh")
    If rc = FE_OK And surfSet.Count > 0 Then
        rc = App.feMeshSurface(surfSet.ID, 0)
        App.feAppMessage(FCM_NORMAL, "Meshed " + Str$(surfSet.Count) + " surfaces")

        ' Merge if requested
        If doMerge Then
            Dim nodeSet As femap.Set
            Set nodeSet = App.feSet
            nodeSet.AddAll(FT_NODE)
            rc = App.feMergeNodes(meshSizeVal / 100.0, nodeSet.ID)
            App.feAppMessage(FCM_NORMAL, "Merged coincident nodes")
        End If

        ' Quality check if requested
        If doQuality Then
            Dim elemSet As femap.Set
            Set elemSet = App.feSet
            elemSet.AddAll(FT_ELEM)
            Dim badCount As Long
            rc = App.feCheckElemDistortion(elemSet.ID, 0, 0.7, badCount)
            If badCount > 0 Then
                App.feAppMessage(FCM_WARNING, Str$(badCount) + _
                    " elements exceed Jacobian limit")
            Else
                App.feAppMessage(FCM_NORMAL, "All elements pass quality check")
            End If
        End If
    End If

    ' Autoscale if requested
    If doAutoscale Then
        App.feViewRegenerate(0)
        App.feViewAutoscaleAll(0)
    End If

    App.feAppMessage(FCM_HIGHLIGHT, "Mesh setup complete")
End Sub
