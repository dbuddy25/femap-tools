' export-contact-cards.bas
' Exports contact bulk data cards from a full NX Nastran deck.
' Extracts BSURF/BSURFS, BCPROP/BCPROPS, BGSET/BGADD, BCTSET/BCTADD cards.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Step 1: Write full NX Nastran deck to temp file
    ' =============================================
    Dim tempFile As String
    tempFile = Environ$("TEMP") + "\femap_contact_export_temp.dat"
    rc = App.feFileWriteNastran(8, tempFile)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to write NX Nastran file (rc=" + CStr(rc) + ")")
        App.feAppMessage(FCM_ERROR, "Ensure an NX Nastran analysis set is configured.")
        Exit Sub
    End If

    ' =============================================
    ' Step 2: File save dialog for output .bdf
    ' =============================================
    Dim fName As String
    rc = App.feFileGetName("Save Contact BDF File", "Nastran BDF", "*.bdf", False, fName)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "File save cancelled - exiting")
        Kill tempFile
        Exit Sub
    End If

    If LCase$(Right$(fName, 4)) <> ".bdf" Then
        fName = fName + ".bdf"
    End If

    ' =============================================
    ' Step 3: Parse temp file, extract contact cards
    ' =============================================
    ' Target card types
    Dim targets(7) As String
    targets(0) = "BSURF"
    targets(1) = "BSURFS"
    targets(2) = "BCPROP"
    targets(3) = "BCPROPS"
    targets(4) = "BGSET"
    targets(5) = "BGADD"
    targets(6) = "BCTSET"
    targets(7) = "BCTADD"

    ' Card counters
    Dim counts(7) As Long
    Dim i As Long
    For i = 0 To 7
        counts(i) = 0
    Next i

    ' Read temp file, extract contact cards
    Dim inFile As Long
    inFile = FreeFile
    Open tempFile For Input As #inFile

    Dim outFile As Long
    outFile = FreeFile
    Open fName For Output As #outFile

    Print #outFile, "$ Contact bulk data extracted from Femap"
    Print #outFile, "$"

    Dim ln As String
    Dim cardName As String
    Dim inContact As Boolean
    Dim lastContactIdx As Long
    inContact = False
    lastContactIdx = -1

    ' Comment buffer - collect $ lines, flush only if followed by contact card
    Dim commentBuf() As String
    Dim commentCount As Long
    commentCount = 0
    ReDim commentBuf(99)

    Do While Not EOF(inFile)
        Line Input #inFile, ln

        ' Get first 8 characters (card name field in small-field format)
        If Len(ln) >= 8 Then
            cardName = Trim$(Left$(ln, 8))
        Else
            cardName = Trim$(ln)
        End If

        ' Handle large-field variants (e.g., *BSURF)
        If Left$(cardName, 1) = "*" Then
            cardName = Mid$(cardName, 2)
        End If

        ' Check what kind of line this is
        If Left$(Trim$(ln), 1) = "$" Then
            ' Comment line - buffer it
            If commentCount > UBound(commentBuf) Then
                ReDim Preserve commentBuf(commentCount + 99)
            End If
            commentBuf(commentCount) = ln
            commentCount = commentCount + 1

        ElseIf cardName = "" Or Left$(cardName, 1) = "+" Or Left$(cardName, 1) = "*" Then
            ' Continuation line - include if previous card was contact
            If inContact Then
                Print #outFile, ln
            End If

        Else
            ' Check if this is a target contact card
            Dim isTarget As Boolean
            Dim targetIdx As Long
            isTarget = False
            targetIdx = -1

            For i = 0 To 7
                If UCase$(cardName) = targets(i) Then
                    isTarget = True
                    targetIdx = i
                    Exit For
                End If
            Next i

            If isTarget Then
                ' Flush comment buffer before this contact card
                Dim c As Long
                For c = 0 To commentCount - 1
                    Print #outFile, commentBuf(c)
                Next c
                commentCount = 0

                Print #outFile, ln
                inContact = True
                lastContactIdx = targetIdx
                counts(targetIdx) = counts(targetIdx) + 1
            Else
                ' Non-contact card - stop collecting, clear comment buffer
                inContact = False
                commentCount = 0
            End If
        End If
    Loop

    Close #inFile
    Close #outFile

    ' =============================================
    ' Step 4: Clean up temp file, report summary
    ' =============================================
    Kill tempFile

    ' Check if any contact cards were found
    Dim totalCards As Long
    totalCards = 0
    For i = 0 To 7
        totalCards = totalCards + counts(i)
    Next i

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Export Contact Cards")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

    If totalCards = 0 Then
        App.feAppMessage(FCM_WARNING, "  No contact cards found in model!")
        App.feAppMessage(FCM_NORMAL, "  File: " + fName)
        App.feAppMessage(FCM_HIGHLIGHT, "========================================")
        Exit Sub
    End If

    ' Print counts for each card type that has entries
    For i = 0 To 7
        If counts(i) > 0 Then
            App.feAppMessage(FCM_NORMAL, "  " + targets(i) + ": " + CStr(counts(i)))
        End If
    Next i

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "  Total: " + CStr(totalCards) + " cards")
    App.feAppMessage(FCM_NORMAL, "  File: " + fName)
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
