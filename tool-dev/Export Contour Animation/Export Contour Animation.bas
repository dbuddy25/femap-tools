' =============================================================================
' Export Contour Animation
' -----------------------------------------------------------------------------
' Saves the CURRENTLY DISPLAYED contour animation in the active view as an
' animated GIF, named from the model title and the output set on screen -
' no Save dialog, no manual typing.
'
' *** WHAT THIS TOOL CANNOT VERIFY ***
' The API guide's ENTIRE remark on animated export is one line in the format
' table: Animated GIF is "only available for animating windows." There is no
' documented property or method anywhere in the guide that reports whether a
' view is CURRENTLY PLAYING an animation. Searched exhaustively - nothing.
'
' So this tool checks the one thing that IS documented and real - View.Deformed,
' the display-style SETTING (2=Animate, 3=Animate Multi-Case) - and warns if it
' is not one of those. That is necessary, not sufficient: the setting can be
' right while the animation is paused or stopped, and there is no way to tell
' from the API. If the exported GIF turns out to be a single frame, that is
' what happened, and there is nothing further to check programmatically.
'
' WHICH OUTPUT SET
' -----------------
' Read from View.OutputSet on the ACTIVE view (via feAppGetActiveView + a fresh
' View.Get), not from Info_ActiveID(FT_OUT_CASE). The FT_OUT_CASE route is
' undocumented in the guide - no statement either way about whether it reflects
' what is on screen or a stale UI selection. Info_ActiveID(FT_VIEW) already
' turned out to always return 0 despite looking like the obvious call; the same
' shape of risk is not worth taking a second time when a properly documented,
' view-scoped property (View.OutputSet) does the same job.
'
' MODIFIES NOTHING IN THE MODEL. Writes one file to disk.
' =============================================================================

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feAppMessage(FCM_NORMAL, "EXPORT CONTOUR ANIMATION")
    App.feAppMessage(FCM_NORMAL, "==================================================")

    ' ------------------------------------------------------------
    ' Section 1: The active view
    ' ------------------------------------------------------------
    ' NOT Info_ActiveID(FT_VIEW) - measured to always return 0 even with a
    ' window open and focused. feAppGetActiveView takes the ID as an OUT-param
    ' and is the call the guide's own example uses.
    Dim viewID As Long
    viewID = 0
    rc = App.feAppGetActiveView(viewID)
    If rc <> FE_OK Or viewID <= 0 Then
        App.feAppMessage(FCM_ERROR, "No active view - open and select a graphics window first.")
        Exit Sub
    End If

    Dim vw As femap.View
    Set vw = App.feView
    rc = vw.Get(viewID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "View.Get failed, rc=" & Str$(rc))
        Exit Sub
    End If

    ' ------------------------------------------------------------
    ' Section 2: The one animation check the API actually supports
    ' ------------------------------------------------------------
    If vw.Deformed <> 2 And vw.Deformed <> 3 Then
        rc = App.feAppMessageBox(1, "This view's display style is not set to Animate. " _
            + "The export may come back as a single still frame instead of a GIF. Continue?")
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Cancelled - no file written")
            Exit Sub
        End If
    End If

    ' ------------------------------------------------------------
    ' Section 3: Output set on screen
    ' ------------------------------------------------------------
    Dim outSetID As Long
    outSetID = vw.OutputSet

    Dim setTitle As String
    setTitle = "NoOutputSet"
    If outSetID > 0 Then
        Dim os As femap.OutputSet
        Set os = App.feOutputSet
        rc = os.Get(outSetID)
        If rc = FE_OK And Len(Trim$(os.title)) > 0 Then
            setTitle = os.title
        Else
            setTitle = "Set" + Trim$(Str$(outSetID))
        End If
    Else
        App.feAppMessage(FCM_WARNING, "  View has no output set assigned - naming it 'NoOutputSet'.")
    End If

    ' ------------------------------------------------------------
    ' Section 4: Model title and folder, from ModelName
    ' ------------------------------------------------------------
    ' ModelName is the FULL PATH including the .modfem/.mod extension, or blank
    ' if the model has never been saved - confirmed in the guide's own remark on
    ' feAppSetModelByName. Both cases are handled: blank falls back to a typed
    ' folder and a fixed title; a real path is split by hand, since WinWrap
    ' offers no documented equivalent of InStrRev to search from the end.
    Dim modelPath As String
    modelPath = App.ModelName

    Dim outDir As String
    Dim modelTitle As String

    If Len(Trim$(modelPath)) = 0 Then
        App.feAppMessage(FCM_WARNING, "  Model has never been saved - no path to build from.")
        outDir = InputBox$("Folder to save the GIF in:", "Export Contour Animation", "C:\Temp\")
        If Len(Trim$(outDir)) = 0 Then
            App.feAppMessage(FCM_WARNING, "Cancelled - no file written")
            Exit Sub
        End If
        modelTitle = "UntitledModel"
    Else
        Dim lastSlash As Long
        Dim lastDot As Long
        lastSlash = LastIndexOf(modelPath, "\")
        outDir = Left$(modelPath, lastSlash)

        Dim baseName As String
        baseName = Mid$(modelPath, lastSlash + 1)
        lastDot = LastIndexOf(baseName, ".")
        If lastDot > 0 Then
            modelTitle = Left$(baseName, lastDot - 1)
        Else
            modelTitle = baseName
        End If
    End If

    If Right$(outDir, 1) <> "\" Then outDir = outDir & "\"

    ' ------------------------------------------------------------
    ' Section 5: Build a safe, non-colliding filename
    ' ------------------------------------------------------------
    Dim safeModel As String
    Dim safeSet As String
    safeModel = SanitizeFileName(modelTitle)
    safeSet = SanitizeFileName(setTitle)

    Dim fso As Object
    Set fso = CreateObject("Scripting.FileSystemObject")

    Dim baseFile As String
    Dim fName As String
    Dim suffix As Long
    baseFile = outDir & safeModel & "_" & safeSet
    fName = baseFile & ".gif"
    suffix = 1

    ' Never overwrite silently - a re-run after nudging the animation would
    ' otherwise clobber the previous export with no trace it happened.
    Do While fso.FileExists(fName)
        suffix = suffix + 1
        fName = baseFile & "_" & Trim$(Str$(suffix)) & ".gif"
    Loop

    App.feAppMessage(FCM_NORMAL, "  Model:      " & modelTitle)
    App.feAppMessage(FCM_NORMAL, "  Output set: " & setTitle & "   (ID " & Str$(outSetID) & ")")
    App.feAppMessage(FCM_NORMAL, "  Saving to:  " & fName)

    ' ------------------------------------------------------------
    ' Section 6: Export
    ' ------------------------------------------------------------
    ' feFilePictureSave2( useDlg, saveRegion, format, fName )
    '   saveRegion 0 = graphics window, format 10 = Animated GIF
    ' The guide is explicit elsewhere that the window must be visible and
    ' unobscured for a picture save to come out correct - true here too.
    rc = App.feFilePictureSave2(False, 0, 10, fName)

    If rc = FE_OK Then
        App.feAppMessage(FCM_HIGHLIGHT, "  Saved: " & fName)
    Else
        App.feAppMessage(FCM_ERROR, "  feFilePictureSave2 failed, rc=" & Str$(rc))
        App.feAppMessage(FCM_ERROR, "  Check the graphics window is visible and not covered.")
    End If

    App.feAppMessage(FCM_NORMAL, "==================================================")
End Sub


' -----------------------------------------------------------------------------
' Position of the LAST occurrence of a single-character needle, 0 if absent.
' WinWrap's InStr only searches forward from a start position; there is no
' documented InStrRev, so finding the last "\" or "." means scanning from the
' end by hand rather than guessing at an undocumented function.
' -----------------------------------------------------------------------------
Function LastIndexOf(s As String, needle As String) As Long
    Dim p As Long
    p = Len(s)
    Do While p > 0
        If Mid$(s, p, 1) = needle Then
            LastIndexOf = p
            Exit Function
        End If
        p = p - 1
    Loop
    LastIndexOf = 0
End Function


' -----------------------------------------------------------------------------
' Strip characters Windows will not allow in a filename, and trim the trailing
' spaces/periods Windows silently drops - an output set titled "Case 1." would
' otherwise ask for a file Windows refuses to create.
' -----------------------------------------------------------------------------
Function SanitizeFileName(s As String) As String
    Dim bad As String
    bad = "\/:*?""<>|"
    Dim result As String
    Dim c As String
    Dim i As Long
    result = ""
    For i = 1 To Len(s)
        c = Mid$(s, i, 1)
        If InStr(bad, c) > 0 Then
            result = result & "_"
        Else
            result = result & c
        End If
    Next i

    Do While Len(result) > 0 And (Right$(result, 1) = " " Or Right$(result, 1) = ".")
        result = Left$(result, Len(result) - 1)
    Loop

    If Len(result) = 0 Then result = "Untitled"
    SanitizeFileName = result
End Function
