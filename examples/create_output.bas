' create_output.bas
' Creates user-defined output vectors using the Results Browsing Object.
' Demonstrates: nodal vector output and elemental scalar output creation.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Part 1: Create Nodal Vector Output
    ' =============================================
    Dim rbo As femap.Results
    Set rbo = App.feResults
    Dim os As femap.OutputSet
    Set os = App.feOutputSet
    Dim ndSet As femap.Set
    Set ndSet = App.feSet

    ' Create Output Set
    Dim oSetID As Long
    oSetID = os.NextEmptyID
    os.title = "User-Defined Nodal Output"
    os.value = 1.0
    os.analysis = 5
    rc = os.Put(oSetID)

    ' Select nodes
    rc = ndSet.Select(FT_NODE, True, "Select Nodes for Output")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No nodes selected")
        Exit Sub
    End If

    Dim count As Long : count = ndSet.Count
    Dim nIDs As Variant
    ndSet.GetArray(count, nIDs)

    ' Prepare data arrays
    ReDim xVals(count - 1) As Variant
    ReDim yVals(count - 1) As Variant
    ReDim zVals(count - 1) As Variant

    ' Fill with sample data (linear ramp)
    Dim i As Long
    For i = 0 To count - 1
        xVals(i) = 0.001 * CDbl(i)
        yVals(i) = -(0.002 * CDbl(i) - 0.001)
        zVals(i) = 0.0
    Next

    ' Initialize columns for vector output (total + 3 components)
    ' User-defined output starts at 24,000,000
    Dim cIndex As Variant
    rbo.AddVectorAtNodeColumnsV2(oSetID, 24000000, 24000001, 24000002, _
        24000003, "Custom Displacement", FOT_DISP, True, cIndex)

    ' Set data and save
    rbo.SetVectorAtNodeColumnsV2(cIndex, count, nIDs, xVals, yVals, zVals)
    rbo.Save

    App.feAppMessage(FCM_NORMAL, "Created nodal vector output on " + _
        Str$(count) + " nodes in Set " + Str$(oSetID))

    ' =============================================
    ' Part 2: Create Elemental Scalar Output
    ' =============================================
    Dim rbo2 As femap.Results
    Set rbo2 = App.feResults
    Dim os2 As femap.OutputSet
    Set os2 = App.feOutputSet
    Dim eSet As femap.Set
    Set eSet = App.feSet

    ' Create another Output Set
    Dim oSetID2 As Long
    oSetID2 = os2.NextEmptyID
    os2.title = "User-Defined Element Output"
    os2.value = 2.0
    os2.analysis = 5
    rc = os2.Put(oSetID2)

    ' Select elements
    rc = eSet.Select(FT_ELEM, True, "Select Elements for Output")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected")
        Exit Sub
    End If

    Dim eCount As Long : eCount = eSet.Count
    Dim eIDs As Variant
    eSet.GetArray(eCount, eIDs)

    ' Prepare element data
    ReDim eVals(eCount - 1) As Variant
    For i = 0 To eCount - 1
        eVals(i) = CDbl(i) * 100.0 + 1200.0
    Next

    ' Initialize scalar column
    Dim cIndex2 As Long
    rbo2.AddScalarAtElemColumnV2(oSetID2, 24000010, "Custom Stress", _
        FOT_STRESS, False, cIndex2)

    ' Set data and save
    rbo2.SetColumn(cIndex2, eCount, eIDs, eVals)
    rbo2.Save

    App.feAppMessage(FCM_NORMAL, "Created elemental scalar output on " + _
        Str$(eCount) + " elements in Set " + Str$(oSetID2))

    App.feViewRegenerate(0)
    App.feAppMessage(FCM_HIGHLIGHT, "Output creation complete")
End Sub
