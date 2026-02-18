' extract_results.bas
' Reads results using the Results Browsing Object (RBO).
' Demonstrates: AddColumnV2, Populate, GetColumn, ResultsIDQuery.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' --- Create Results Browsing Object ---
    Dim rbo As femap.Results
    Set rbo = App.feResults

    ' --- Select Output Set ---
    Dim os As femap.OutputSet
    Set os = App.feOutputSet
    Dim setID As Long
    rc = os.Select(True, setID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No output set selected")
        Exit Sub
    End If

    ' --- Use ResultsIDQuery to find vector IDs ---
    Dim q As femap.ResultsIDQuery
    Set q = App.feResultsIDQuery

    Dim topVonMisesID As Long
    Dim botVonMisesID As Long
    topVonMisesID = q.Plate(VPV_STRESS, VPT_VON_MISES, VPP_TOP, VPL_CENTROID)
    botVonMisesID = q.Plate(VPV_STRESS, VPT_VON_MISES, VPP_BOT, VPL_CENTROID)

    App.feAppMessage(FCM_NORMAL, "Top Von Mises Vec ID: " + Str$(topVonMisesID))
    App.feAppMessage(FCM_NORMAL, "Bot Von Mises Vec ID: " + Str$(botVonMisesID))

    ' --- Add columns for both vectors ---
    Dim col1 As Long, vCol1 As Variant
    Dim col2 As Long, vCol2 As Variant

    rc = rbo.AddColumnV2(setID, topVonMisesID, False, col1, vCol1)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to add Top Von Mises column")
        Exit Sub
    End If

    rc = rbo.AddColumnV2(setID, botVonMisesID, False, col2, vCol2)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to add Bottom Von Mises column")
        Exit Sub
    End If

    ' --- Populate data ---
    rc = rbo.Populate
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to populate results")
        Exit Sub
    End If

    ' --- Get data arrays ---
    Dim vIDs As Variant, vTopVals As Variant, vBotVals As Variant

    rc = rbo.GetColumn(0, vIDs, vTopVals)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to get Top Von Mises data")
        Exit Sub
    End If

    Dim vIDs2 As Variant
    rc = rbo.GetColumn(1, vIDs2, vBotVals)

    ' --- Find max values ---
    Dim maxTop As Double : maxTop = 0.0
    Dim maxBot As Double : maxBot = 0.0
    Dim maxTopID As Long : maxTopID = 0
    Dim maxBotID As Long : maxBotID = 0
    Dim count As Long : count = UBound(vIDs) + 1

    Dim i As Long
    For i = 0 To count - 1
        If vTopVals(i) > maxTop Then
            maxTop = vTopVals(i)
            maxTopID = vIDs(i)
        End If
        If vBotVals(i) > maxBot Then
            maxBot = vBotVals(i)
            maxBotID = vIDs2(i)
        End If
    Next

    ' --- Report results ---
    App.feAppMessage(FCM_NORMAL, "Results for Output Set " + Str$(setID))
    App.feAppMessage(FCM_NORMAL, "  Elements processed: " + Str$(count))
    App.feAppMessage(FCM_NORMAL, "  Max Top Von Mises: " + Str$(maxTop) + _
        " at Elem " + Str$(maxTopID))
    App.feAppMessage(FCM_NORMAL, "  Max Bot Von Mises: " + Str$(maxBot) + _
        " at Elem " + Str$(maxBotID))

    ' --- Optional: Calculate envelope (max of top and bottom) ---
    App.feAppMessage(FCM_NORMAL, "--- Envelope (Max of Top/Bot) ---")
    Dim maxEnvelope As Double : maxEnvelope = 0.0
    Dim maxEnvID As Long : maxEnvID = 0

    For i = 0 To count - 1
        Dim envVal As Double
        If vTopVals(i) > vBotVals(i) Then
            envVal = vTopVals(i)
        Else
            envVal = vBotVals(i)
        End If
        If envVal > maxEnvelope Then
            maxEnvelope = envVal
            maxEnvID = vIDs(i)
        End If
    Next

    App.feAppMessage(FCM_HIGHLIGHT, "  Max Envelope Von Mises: " + _
        Str$(maxEnvelope) + " at Elem " + Str$(maxEnvID))
End Sub
