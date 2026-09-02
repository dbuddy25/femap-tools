' =============================================================================
' Check View Capture
' -----------------------------------------------------------------------------
' Diagnostic. Proves the four API steps a contour-plot export tool would depend
' on, before any such tool gets written:
'
'   1. Can a view be restricted to ONE group?          View.Group + Put + Regenerate
'   2. Can it be fitted at the current orientation?    View.FitVisible
'   3. Can orientation be READ and WRITTEN back?       ViewOrient.Get/SetRotationAngles
'   4. Does the graphics window export to a file?      feFilePictureSave2
'
' Step 3 is the one the whole design rests on. If orientation round-trips, the
' workflow can be "orient by hand, click Record, repeat" and then replay every
' saved orientation unattended. If it does not, every plot has to be posed by
' hand at the moment it is captured.
'
' WHY NOT AN "ORIENT IT NOW, THEN CLICK OK" LOOP
' ----------------------------------------------
' Because the API has no modeless dialog. feAppMessageBox is modal and the only
' documented persistent UI is a registered add-in pane, which needs a compiled
' application, not a .BAS. So a dialog cannot sit open while the model is
' rotated. Recording orientations and replaying them sidesteps that entirely -
' and the recording is reusable, which posing by hand is not.
'
' THIS MODIFIES THE VIEW, NOT THE MODEL. No entity is created, changed or
' deleted. The original view orientation and group are restored at the end.
' =============================================================================

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feAppMessage(FCM_NORMAL, "CHECK VIEW CAPTURE - view-only probe")
    App.feAppMessage(FCM_NORMAL, "==================================================")

    ' ------------------------------------------------------------
    ' The active view
    ' ------------------------------------------------------------
    ' *** NOT Info_ActiveID(FT_VIEW) ***
    ' That returns 0 even with a graphics window open and focused - measured
    ' twice, here and in Peak Stress Table, which silently fell back to its
    ' default every run because of it. Views are not an "active entity" in the
    ' sense Info_ActiveID reports on.
    '
    ' feAppGetActiveView takes the view ID as an OUT-param and returns FE_FAIL
    ' when there genuinely is no active view.
    Dim viewID As Long
    viewID = 0
    rc = App.feAppGetActiveView(viewID)
    If rc <> FE_OK Or viewID <= 0 Then
        App.feAppMessage(FCM_ERROR, "No active view - open a graphics window first.")
        Exit Sub
    End If
    App.feAppMessage(FCM_NORMAL, "  Active view: " & Str$(viewID))

    ' ------------------------------------------------------------
    ' Output folder
    ' ------------------------------------------------------------
    Dim outDir As String
    outDir = InputBox$("Folder for the two test PNGs:", "Check View Capture", "C:\Temp\")
    If Len(Trim$(outDir)) = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    If Right$(outDir, 1) <> "\" Then outDir = outDir & "\"

    ' ------------------------------------------------------------
    ' One group to isolate
    ' ------------------------------------------------------------
    Dim gSet As femap.Set
    Set gSet = App.feSet
    rc = gSet.SelectMultiIDV2(FT_GROUP, 1, "Select ONE group to isolate")
    If rc = FE_CANCEL Or gSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim grpID As Long
    grpID = gSet.First()

    ' ------------------------------------------------------------
    ' Capture the starting state so it can be put back
    ' ------------------------------------------------------------
    Dim vw As femap.View
    Set vw = App.feView
    rc = vw.Get(viewID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "View.Get failed, rc=" & Str$(rc))
        Exit Sub
    End If
    Dim wasGroup As Long
    Dim wasMag As Double
    wasGroup = vw.Group
    wasMag = vw.Magnification
    App.feAppMessage(FCM_NORMAL, "  View.Group was " & Str$(wasGroup) & _
        "   (-1 active, -2 multiple, 0 all)")

    Dim vo As femap.ViewOrient
    Set vo = App.feViewOrient
    rc = vo.Get(viewID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "ViewOrient.Get failed, rc=" & Str$(rc))
        Exit Sub
    End If

    ' GetRotationAngles has THREE OUT-PARAMS - degrees, about the Basic
    ' Rectangular system, wrapped to -179.9999..180.
    Dim aX As Double, aY As Double, aZ As Double
    aX = 0.0
    aY = 0.0
    aZ = 0.0
    rc = vo.GetRotationAngles(aX, aY, aZ)
    App.feAppMessage(FCM_NORMAL, "  Start angles: " & Format$(aX, "0.000") & ", " & _
        Format$(aY, "0.000") & ", " & Format$(aZ, "0.000") & "   rc=" & Str$(rc))

    ' Six more OUT-params. Printed alongside the angles because the two are
    ' alternative descriptions of the same orientation, and it is not obvious
    ' which one survives a round trip more faithfully.
    Dim eX As Double, eY As Double, eZ As Double
    Dim rX As Double, rY As Double, rZ As Double
    rc = vo.GetEyeDirection(eX, eY, eZ, rX, rY, rZ)
    App.feAppMessage(FCM_NORMAL, "  Start eye:    " & Format$(eX, "0.000") & ", " & _
        Format$(eY, "0.000") & ", " & Format$(eZ, "0.000") & _
        "   right: " & Format$(rX, "0.000") & ", " & Format$(rY, "0.000") & _
        ", " & Format$(rZ, "0.000") & "   rc=" & Str$(rc))

    ' ------------------------------------------------------------
    ' TEST 1+2: isolate the group and fit it
    ' ------------------------------------------------------------
    ' FitVisible, unlike AutoscaleVisible, accounts for the CURRENT orientation -
    ' it is the real "fit what I am looking at". All three only update the object;
    ' the view must be Put and redrawn before anything changes on screen.
    vw.Group = grpID
    vw.FitVisible(True)
    rc = vw.Put(viewID)
    App.feAppMessage(FCM_NORMAL, "  Isolate + fit: View.Put rc=" & Str$(rc))
    App.feViewRegenerate(viewID)

    ' ------------------------------------------------------------
    ' TEST 4: export what is on screen
    ' ------------------------------------------------------------
    ' feFilePictureSave2( useDlg, saveRegion, format, fName )
    '   saveRegion 0 = graphics window, format 12 = PNG
    ' *** THE WINDOW MUST BE VISIBLE AND UNOBSCURED ***
    ' The guide is explicit: if the view is covered by another application the
    ' saved file is wrong. So an export tool cannot run behind a maximised Excel,
    ' and that is a real operating limit, not a detail.
    Dim f1 As String
    f1 = outDir & "viewprobe_A.png"
    rc = App.feFilePictureSave2(False, 0, 12, f1)
    App.feAppMessage(FCM_NORMAL, "  Saved A: " & f1 & "   rc=" & Str$(rc))

    ' ------------------------------------------------------------
    ' TEST 3: write an orientation, then read it back
    ' ------------------------------------------------------------
    ' Rotated by a deliberately odd amount so a value that merely LOOKS plausible
    ' cannot be mistaken for a real round trip.
    Dim nX As Double, nY As Double, nZ As Double
    nX = aX + 37.0
    nY = aY - 23.0
    nZ = aZ + 11.0

    rc = vo.SetRotationAngles(nX, nY, nZ)
    ' ViewOrient must be Put AFTER the View object when both are touched - the
    ' guide is explicit, and the View.Put above would otherwise overwrite this.
    rc = vo.Put(viewID)
    App.feAppMessage(FCM_NORMAL, "  SetRotationAngles + Put rc=" & Str$(rc))
    App.feViewRegenerate(viewID)

    Dim gX As Double, gY As Double, gZ As Double
    rc = vo.Get(viewID)
    rc = vo.GetRotationAngles(gX, gY, gZ)
    App.feAppMessage(FCM_NORMAL, "  Asked for:    " & Format$(nX, "0.000") & ", " & _
        Format$(nY, "0.000") & ", " & Format$(nZ, "0.000"))
    App.feAppMessage(FCM_NORMAL, "  Read back:    " & Format$(gX, "0.000") & ", " & _
        Format$(gY, "0.000") & ", " & Format$(gZ, "0.000"))

    ' Angles wrap at +/-180, so compare on the wrapped difference rather than on
    ' equality - asking for 190 and reading -170 is a correct round trip.
    Dim dMax As Double
    dMax = AngleDiff(nX, gX)
    If AngleDiff(nY, gY) > dMax Then dMax = AngleDiff(nY, gY)
    If AngleDiff(nZ, gZ) > dMax Then dMax = AngleDiff(nZ, gZ)
    App.feAppMessage(FCM_NORMAL, "  Worst angle error: " & Format$(dMax, "0.0000") & " deg")

    If dMax < 0.01 Then
        App.feAppMessage(FCM_HIGHLIGHT, "  ROUND TRIP OK - orientations can be recorded and replayed.")
    Else
        App.feAppMessage(FCM_ERROR, "  ROUND TRIP FAILED - the angles did not come back.")
        App.feAppMessage(FCM_ERROR, "  Record-and-replay is not viable on angles; try EyeDirection.")
    End If

    Dim f2 As String
    f2 = outDir & "viewprobe_B.png"
    rc = App.feFilePictureSave2(False, 0, 12, f2)
    App.feAppMessage(FCM_NORMAL, "  Saved B: " & f2 & "   rc=" & Str$(rc))

    ' ------------------------------------------------------------
    ' Put it back the way it was
    ' ------------------------------------------------------------
    rc = vw.Get(viewID)
    vw.Group = wasGroup
    vw.Magnification = wasMag
    rc = vw.Put(viewID)
    rc = vo.Get(viewID)
    rc = vo.SetRotationAngles(aX, aY, aZ)
    rc = vo.Put(viewID)
    App.feViewRegenerate(viewID)

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "  View restored. Nothing in the MODEL was touched.")
    App.feAppMessage(FCM_NORMAL, "  Compare the two PNGs: A is the group fitted, B is it rotated.")
    App.feAppMessage(FCM_NORMAL, "==================================================")
End Sub


' -----------------------------------------------------------------------------
' Smallest angular difference in degrees, accounting for the +/-180 wrap.
' Femap wraps out-of-range angles, so a plain subtraction reports a 360-degree
' error on a round trip that was actually exact.
' -----------------------------------------------------------------------------
Function AngleDiff(a As Double, b As Double) As Double
    Dim d As Double
    d = Abs(a - b)
    Do While d > 360.0
        d = d - 360.0
    Loop
    If d > 180.0 Then d = 360.0 - d
    AngleDiff = d
End Function
