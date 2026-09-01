' =============================================================================
' List Output Vectors
' -----------------------------------------------------------------------------
' Diagnostic. Prints every STRESS output vector that actually exists in a chosen
' output set, by ID and title.
'
' WHY THIS EXISTS
' ---------------
' Check Stress Vectors asked ResultsIDQuery for nine plate/solid stress vectors.
' Six resolved. All three plate BOTTOM vectors came back FE_FAIL, using ply=3,
' which the API guide confirms is VPP_BOT (zVecPlatePly: TOP=0, MID=1, BOT=3).
'
' FE_FAIL from ResultsIDQuery means "no such vector in THIS model". It does not
' say why. Two very different causes produce it, and they need opposite fixes:
'
'   a) The solver never wrote bottom-surface plate stress. Fix: re-run the solve
'      asking for it. The table simply cannot offer those columns today.
'   b) The vectors are there, but ResultsIDQuery is not finding them under the
'      enum combination we asked for. Fix: address them by ID.
'
' Guessing between (a) and (b) is exactly the mistake this codebase keeps
' punishing. Bottom-surface stress usually GOVERNS in bending, so a table that
' silently reports top-surface only is not a conservative simplification - it is
' a wrong answer that looks right.
'
' So: list what is really in the set and read it.
'
' HOW TO READ THE OUTPUT
' ----------------------
'   A "Plate Bot ..." line appears     -> cause (b). The vector exists. Note its
'                                         ID; the table addresses it directly
'                                         instead of via ResultsIDQuery.
'   No "Plate Bot ..." line anywhere   -> cause (a). The solve did not write it.
'                                         The table offers top-surface only, and
'                                         says so on the sheet.
'
' NOTHING IN THE MODEL IS MODIFIED. This is a read-only probe.
' =============================================================================

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long

    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feAppMessage(FCM_NORMAL, "LIST OUTPUT VECTORS - read-only probe")
    App.feAppMessage(FCM_NORMAL, "==================================================")

    ' ------------------------------------------------------------
    ' Pick one output set
    ' ------------------------------------------------------------
    Dim osSet As femap.Set
    Set osSet = App.feSet
    rc = osSet.SelectMultiIDV2(FT_OUT_CASE, 1, "Select ONE output set to list")
    If rc = FE_CANCEL Or osSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim oSetID As Long
    oSetID = osSet.First()

    Dim os As femap.OutputSet
    Set os = App.feOutputSet
    rc = os.Get(oSetID)
    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "OUTPUT SET " & Str$(oSetID) & " : " & os.title)

    ' ------------------------------------------------------------
    ' Pull every vector ID + title in the set
    ' ------------------------------------------------------------
    ' VectorTitlesV2( nSetID, bIncludeID, minID, maxID, Count, listID, listTITLE )
    ' minID = maxID = 0 means "every vector in the set".
    ' bIncludeID = False so the title comes back clean, without an "ID.." prefix
    ' glued on - the ID is printed separately.
    Dim rbo As femap.Results
    Set rbo = App.feResults

    Dim vCount As Long
    Dim vIDs As Variant
    Dim vTitles As Variant

    rc = rbo.VectorTitlesV2(oSetID, False, 0, 0, vCount, vIDs, vTitles)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "VectorTitlesV2 failed, rc = " & Str$(rc))
        App.feAppMessage(FCM_ERROR, "(FE_NOT_EXIST means the set holds no vectors at all.)")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "  Vectors in set : " & Str$(vCount))
    App.feAppMessage(FCM_NORMAL, "")

    ' ------------------------------------------------------------
    ' Print the stress vectors
    ' ------------------------------------------------------------
    ' Filtered to titles containing "STRESS". An unfiltered dump of a real model
    ' runs to hundreds of lines of displacement, force and strain vectors that
    ' have no bearing on the question being asked here.
    App.feAppMessage(FCM_NORMAL, "--- STRESS VECTORS ---")

    Dim t As String
    Dim u As String
    Dim nStress As Long
    Dim nPlateBot As Long
    nStress = 0
    nPlateBot = 0

    For i = 0 To vCount - 1
        t = CStr(vTitles(i))
        u = UCase$(t)
        If InStr(u, "STRESS") > 0 Then
            nStress = nStress + 1
            App.feAppMessage(FCM_NORMAL, "  " & Str$(CLng(vIDs(i))) & "   " & t)
            If InStr(u, "BOT") > 0 Then
                nPlateBot = nPlateBot + 1
            End If
        End If
    Next i

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "  Stress vectors listed : " & Str$(nStress))
    App.feAppMessage(FCM_NORMAL, "  ...of those, titled BOT : " & Str$(nPlateBot))

    ' The verdict, stated rather than left to be inferred from the list.
    App.feAppMessage(FCM_NORMAL, "")
    If nPlateBot > 0 Then
        App.feAppMessage(FCM_WARNING, "VERDICT: bottom-surface stress EXISTS in this set.")
        App.feAppMessage(FCM_WARNING, "  ResultsIDQuery is not finding it - the table must")
        App.feAppMessage(FCM_WARNING, "  address these vectors by ID.")
    Else
        App.feAppMessage(FCM_NORMAL, "VERDICT: no bottom-surface stress in this set.")
        App.feAppMessage(FCM_NORMAL, "  The solve did not write it. The table can offer")
        App.feAppMessage(FCM_NORMAL, "  top-surface plate stress only, and must say so.")
    End If

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "Probe complete. Nothing was modified.")
    App.feAppMessage(FCM_NORMAL, "==================================================")
End Sub
