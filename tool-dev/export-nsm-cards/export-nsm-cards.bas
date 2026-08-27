' export-nsm-cards.bas
' -----------------------------------------------------------------------------
' Extracts the nonstructural-mass cards - NSM, NSM1, NSML, NSML1, NSMADD - from
' a full NX Nastran deck and writes them to a standalone .bdf.
'
' WHY THIS IS A SEPARATE TOOL
' Femap will not write NSM cards for a group-filtered export. Confirmed from
' Femap's own Analysis Set Manager, not just from a script: set Bulk Data
' Options -> Group and the NSM regions are dropped even though they are in the
' group and carry real mass. There is no analysis-set switch for it.
'
' The obvious fix - have the per-group exporter recover them - runs into a worse
' problem than the one it solves. NSM regions do not respect group boundaries. A
' region straddling two groups cannot be split between their files: for the
' total-mass forms (NSML/NSML1) the value is a total to distribute across the
' listed elements, so giving that same total to a subset silently changes the
' mass. The only safe thing a per-group tool can do is skip the region.
'
' Taking NSM out of the per-group split entirely removes the problem instead of
' managing it. One file, every card, nothing skipped, included once by the
' master deck.
'
' NOTHING IS INTERPRETED
' The cards are copied VERBATIM. Generating NSM1/NSML1 from the region data
' would mean deciding which card a given MassType maps to, what goes in the TYPE
' field, and how SIDs are assigned - three things reconstructed from the Nastran
' spec that could be quietly wrong in a deck that still runs. Femap's own output
' is the specification.
'
' Companion to export-contact-cards, which does the same for contact and glue.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Step 1: Write a genuinely FULL NX Nastran deck
    '
    ' *** THE ACTIVE ANALYSIS SET CANNOT BE TRUSTED TO BE UNFILTERED ***
    ' feFileWriteNastran writes whatever the active analysis set says, and that
    ' set may carry NasBulkGroupID pointing at a single group. Write BDF by
    ' Group leaves exactly such a set behind if it is cancelled part way - so
    ' running this afterwards silently exported ONE group and reported honestly
    ' that it found no NSM, because that group's cards were filtered out.
    '
    ' A whole-model tool must not inherit a filter it did not set. This builds
    ' its own analysis set with NasBulkGroupID = 0, uses it, then deletes it and
    ' puts the previous active set back.
    ' =============================================
    Dim sao As Object
    Set sao = App.feAnalysisMgr
    Dim saoID As Long
    Dim prevActive As Long
    prevActive = sao.Active

    saoID = sao.NextEmptyID
    sao.title = "Temp Set for NSM Export"
    sao.Solver = 36                 ' NX Nastran
    sao.AnalysisType = 2            ' Modes - least extra data written
    sao.NasBulkOn = True
    sao.NasBulkGroupID = 0          ' 0 = entire model. This is the whole point.
    rc = sao.Put(saoID)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Could not create a temporary analysis set - exiting")
        Exit Sub
    End If
    sao.Active = saoID

    Dim tempFile As String
    tempFile = Environ$("TEMP") + "\femap_nsm_export_temp.dat"
    rc = App.feFileWriteNastran(8, tempFile)

    ' Put the model back the way it was before anything else can go wrong.
    If prevActive > 0 Then sao.Active = prevActive
    If sao.Deletable(saoID) Then sao.Delete(saoID)

    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to write NX Nastran file (rc=" + CStr(rc) + ")")
        Exit Sub
    End If

    ' =============================================
    ' Step 2: File save dialog for output .bdf
    ' =============================================
    Dim fName As String
    rc = App.feFileGetName("Save NSM BDF File", "Nastran BDF", "*.bdf", False, fName)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "File save cancelled - exiting")
        Kill tempFile
        Exit Sub
    End If

    If LCase$(Right$(fName, 4)) <> ".bdf" Then
        fName = fName + ".bdf"
    End If

    ' =============================================
    ' Step 3: Parse temp file, extract NSM cards
    '
    ' One prefix test covers the whole family - NSM, NSM1, NSML, NSML1 and
    ' NSMADD all start "NSM", and no other Nastran card does.
    ' =============================================
    Dim inFile As Long
    inFile = FreeFile
    Open tempFile For Input As #inFile

    Dim outFile As Long
    outFile = FreeFile
    Open fName For Output As #outFile

    Print #outFile, "$ Nonstructural mass cards extracted from Femap"
    Print #outFile, "$ Femap does not write these for a group-filtered export,"
    Print #outFile, "$ so they are collected here and included once."
    Print #outFile, "$"

    Dim ln As String
    Dim cardName As String
    Dim inNSM As Boolean
    Dim inBulk As Boolean
    Dim nCards As Long
    Dim nLines As Long
    Dim namesSeen As String
    inNSM = False
    inBulk = False
    nCards = 0
    nLines = 0
    namesSeen = ""

    ' Leading comments are buffered and flushed only in front of an NSM card, so
    ' a label lands with the card it belongs to and nothing else comes along.
    Dim commentBuf() As String
    Dim commentCount As Long
    commentCount = 0
    ReDim commentBuf(99)

    Dim i As Long

    Do While Not EOF(inFile)
        Line Input #inFile, ln

        ' Executive and case control are not bulk data.
        If Not inBulk Then
            If UCase$(Left$(Trim$(ln), 10)) = "BEGIN BULK" Then inBulk = True
            GoTo NextLine
        End If

        If UCase$(Left$(Trim$(ln), 7)) = "ENDDATA" Then Exit Do

        If Len(ln) >= 8 Then
            cardName = Trim$(Left$(ln, 8))
        Else
            cardName = Trim$(ln)
        End If
        If Left$(cardName, 1) = "*" Then cardName = Mid$(cardName, 2)
        cardName = UCase$(Replace(cardName, "*", ""))

        If Left$(Trim$(ln), 1) = "$" Then
            If inNSM Then
                ' Inside or trailing an NSM block - written straight out, so a
                ' comment is not lost the moment a non-NSM card follows.
                Print #outFile, ln
                nLines = nLines + 1
            Else
                If commentCount > UBound(commentBuf) Then
                    ReDim Preserve commentBuf(commentCount + 99)
                End If
                commentBuf(commentCount) = ln
                commentCount = commentCount + 1
            End If

        ElseIf cardName = "" Or Left$(cardName, 1) = "+" Or Left$(cardName, 1) = "*" Then
            ' Continuation - belongs to whatever card opened the block.
            If inNSM Then
                Print #outFile, ln
                nLines = nLines + 1
            End If

        Else
            If Left$(cardName, 3) = "NSM" Then
                ' Flush the buffered label ahead of the card it describes.
                For i = 0 To commentCount - 1
                    Print #outFile, commentBuf(i)
                    nLines = nLines + 1
                Next i
                commentCount = 0

                Print #outFile, ln
                nLines = nLines + 1
                nCards = nCards + 1
                inNSM = True
                If InStr(namesSeen, " " & cardName & " ") = 0 Then
                    namesSeen = namesSeen & " " & cardName & " "
                End If
            Else
                ' Any other card ends the block and discards the buffer - those
                ' comments belong to the card that is not being copied.
                inNSM = False
                commentCount = 0
            End If
        End If

NextLine:
    Loop

    Print #outFile, "$"
    Print #outFile, "$ End of nonstructural mass cards"

    Close #inFile
    Close #outFile
    Kill tempFile

    ' =============================================
    ' Step 4: Report
    ' =============================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Export NSM Cards - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL,    "  Cards written:         " + Trim$(Str$(nCards)))
    App.feAppMessage(FCM_NORMAL,    "  Lines written:         " + Trim$(Str$(nLines)))
    If nCards > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Card types:           " + namesSeen)
        If InStr(namesSeen, " NSMADD ") = 0 Then
            App.feAppMessage(FCM_WARNING, "  No NSMADD - the NSM sets are not combined.")
        End If
        App.feAppMessage(FCM_NORMAL, "  File:                  " + fName)
    Else
        App.feAppMessage(FCM_WARNING, "  No NSM cards in the deck.")
        App.feAppMessage(FCM_WARNING, "  The export was unfiltered (its own analysis set, whole model),")
        App.feAppMessage(FCM_WARNING, "  so this means the model genuinely has no nonstructural mass.")
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

End Sub
