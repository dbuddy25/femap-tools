' Write_bdf_by_Group.BAS
'
' Change History
' 20240404
' - added warning that contact entities are only written in MSC compatible format
' 20260713
' - now works with NX NASTRAN contact entities, changed message printed to FEMAP
' 20260818
' - FixFile no longer counts header lines. It skips to BEGIN BULK and then
'   filters by CARD NAME. The old fixed counts (24 header lines, then 5-10 more)
'   silently ate a bulk-data line whenever the header length changed, which is
'   what made a GRID card go missing.
' - CORD2C/CORD2S are now only dropped when their CID is 1 or 2 (Femap's global
'   cylindrical/spherical). Previously the count-based skip would take whatever
'   happened to sit in those line positions, including a user coordinate system.
' - FixFile reports failure instead of writing a truncated file.
' 20260826
' - Re-exporting over an existing .bdf now PRESERVES the notes already in it.
'   New custom lines are written ABOVE the retained ones, so the header reads
'   newest-first, while Femap's own banner (version / model / date) and the
'   "Exported from group" line are regenerated every run.
' - "Exported from group" moved out of the custom-header block. It was being
'   written as a user note, so re-exporting the same group would have stacked
'   an identical copy of that line on every single run.
' - The header classification is printed to Messages on every export, so a
'   re-export says out loud how many notes it carried over. Silent carry-over
'   would be indistinguishable from silent loss.

' -----------------------------------------------------------------------------
' Header markers. These are written into every exported .bdf and are how a
' re-export tells the analyst's notes from Femap's regenerated banner. Changing
' the text of these breaks carry-over for files written by an older build - the
' file falls back to the legacy path in ExistingNotes rather than losing notes,
' but it will carry the old banner across once.
' -----------------------------------------------------------------------------
Const NOTES_BEGIN As String = "$>>> EXPORT NOTES - kept on re-export, newest first"
Const NOTES_END   As String = "$<<< END EXPORT NOTES"
Const BANNER_MARK As String = "$--- FEMAP BANNER - regenerated every export, edits here are lost"

Sub Main

            'Define a string indicating the version of the translator
            Const GrpsToBDF_version As String = "1"

            'Load model
            Dim App As femap.model
            Set App = feFemap()

            Dim job() As String

            'Indicate which version and contact information for support
            App.feAppMessage(0,"*** Write Groups to NX Nastran Files ***")
            'Removed warning message about MSC contact
            'Save model
            'App.feFileSaveAs(True,"")

            'Get model name and path
                        Dim model As Huge_
                        Dim modelFileFull As String
                        Dim modelFileName As String
                        Dim modelFIlePath As String
                        App.feAppGetModel(model)
                        rc = App.feAppGetModelName(model,modelFileFull)
                        modelFileName = Dir(modelFileFull)
                        modelFIlePath = Left(modelFileFull, Len(modelFileFull)-Len(modelFileName))
                        If StrComp(modelFIlePath,"Untitled") = 0 Then
                                                modelFIlePath = "C:\Temp\"
                        End If

            'Make group set object
Dim grSet As femap.Set
Set grSet = App.feSet

'Make group object
Dim gr As femap.Group
Set gr = App.feGroup
Dim grName As String
Dim grFileName As String

            'Make analysis set object
Dim sao As femap.AnalysisMgr
Set sao = App.feAnalysisMgr
Dim saoID As Long

'Set properties of analysis set
saoID = sao.NextEmptyID   'Finds next available ID to make analysis set in
            sao.title = "Dummy Set for Group Export" 'Names dummy set
            sao.Solver = 36 'Sets Solver to NX Nastran (solver different from translator)
            sao.AnalysisType = 2 'Sets Analysis Type to Modes for creation of less data
            sao.NasCnlSkipNLPARM = True 'Skips more unneeded data to be written out
            'sao.SkipStandard = True ' !!! This will skip connections for NX NASTRAN !!!

            'All Field format types stored in strings
            Dim FFormat(5) As String
            FFormat(0) = "Small Field"
            FFormat(1) = "Large Csys, Material, Property"
            FFormat(2) = "Large All But Elements"
            FFormat(3) = "Large"
            FFormat(4) = "Large Csys, Node"

'Prompt user for Groups to export
grSet.SelectMultiID(FT_GROUP,1,"Select Group(s)")

'Promts user for field format
Dim UserFormat As Integer
Begin Dialog UserDialog 400,350,"Options" 'NasBulkLargeField %GRID:10,7,1,1
            GroupBox 5,0,300,100,"Select Field Format",.GroupBox1
                        ListBox 20,21,200,75,FFormat(),.ListBox1
            GroupBox 5,120,300,70,"Is Group Name already the bdf file Name?",.GroupBox2
                        OptionGroup.Group1
                        OptionButton 50,135,150,21,"No",.OptionButton1
                        OptionButton 50,160,150,21,"Yes",.OptionButton2
            ' Three single-line boxes rather than one multiline box: every
            ' TextBox in this toolset is single-line, and this is not the script
            ' to try unproven dialog syntax on.
            GroupBox 5,196,385,92,"Custom header comments (optional)",.GroupBox3
                        TextBox 15,214,365,18,.hdr1
                        TextBox 15,236,365,18,.hdr2
                        TextBox 15,258,365,18,.hdr3
            OKButton 70,300,120,35
            CancelButton 220,300,120,35
End Dialog
Dim dlg As UserDialog
UserFormat = Dialog(dlg)

If UserFormat = -1 Then 'user pressed ok
            UserFormat = dlg.ListBox1
ElseIf UserFormat = 0 Then 'terminates macro if user cancels
            End
End If

'Updates field format
sao.NasBulkLargeField = UserFormat

            Dim fixOK As Boolean
            Dim dropInfo As String
            Dim customHdr As String

            'Loop reads out all group info seperately
            While gr.NextInSet( grSet.ID ) = FE_OK

                                    sao.NasBulkOn = True
                                    sao.NasBulkGroupID = gr.ID 'User selected group
                                    sao.Put (saoID)   'adds dummy analysis to Femap session
                                    sao.Active = saoID 'activates dummy analysis set

                                    Select Case dlg.Group1
                                                Case 0
                                                            grFileName = modelFIlePath & "Group_" & gr.title 'Sets temp file name
                                                Case 1
                                                            job = Split(gr.title,".")
                                                            grFileName = modelFIlePath & job(0)
                                    End Select

                                                                        App.feFileWriteNastran(8,grFileName)  '8 for nx
                                                                        App.feAppMessage(FCM_COMMAND,"Wrote Original Nastran file: " & grFileName )

                                    ' Custom header lines, rebuilt per group so the group
                                    ' name is right. Chr$(10) separated; FixFile splits it.
                                    customHdr = ""
                                    If Trim(dlg.hdr1) <> "" Then customHdr = customHdr & AsComment(dlg.hdr1) & Chr$(10)
                                    If Trim(dlg.hdr2) <> "" Then customHdr = customHdr & AsComment(dlg.hdr2) & Chr$(10)
                                    If Trim(dlg.hdr3) <> "" Then customHdr = customHdr & AsComment(dlg.hdr3) & Chr$(10)

                                    fixOK = FixFile(grFileName, customHdr, gr.title, dropInfo, App) 'Funciton that writes correct data to new final file

                                    If fixOK Then
                                                App.feAppMessage(FCM_COMMAND,"Replaced lines and saved as bdf: " & grFileName & ".bdf")
                                                App.feAppMessage(FCM_COMMAND,"  Removed: " & dropInfo)
                                                DeleteTempFile(grFileName)  'Function that deletes the temporary file
                                                App.feAppMessage(FCM_COMMAND,"Deleted original file: " & grFileName)
                                    Else
                                                ' The temp file is deliberately KEPT here - if the header could not be
                                                ' parsed, the raw Femap output is the only way to see what happened.
                                                App.feAppMessage(FCM_ERROR,"BEGIN BULK not found in: " & grFileName & _
                                                            "  - no .bdf written, temp file kept for inspection")
                                    End If

            Wend

            'Deletes dummy analysis Set after use
                        If sao.Deletable(saoID) Then
                                    sao.Delete(saoID)
                        End If

                        App.feAppMessage( FCL_BLACK, "Done ")

End Sub

' -----------------------------------------------------------------------------
' Strip the Femap-generated header and the dummy analysis cards, and write the
' remainder as <fileName>.bdf. Returns True on success.
'
' This used to count lines: 24 for the header, then 5-10 more for EIGRL/CORD2i,
' with the second count adjusted by looking for large-field markers. Both counts
' were assumptions about how many lines Femap happens to emit. When the header
' length changed the overrun ran straight into the bulk data and swallowed a
' card - a GRID going missing with no error was the usual symptom.
'
' Now nothing is counted. The header ends at BEGIN BULK, which is definitional,
' and the unwanted cards are removed by NAME with their continuation lines.
' -----------------------------------------------------------------------------
Function FixFile(fileName As String, customHdr As String, grpTitle As String, dropSummary As String, App As Object) As Boolean

            Dim fso As Object
            Dim readOld As Object
            Dim writeNew As Object
            Dim textLine As String
            Dim cardName As String
            Dim cid As String
            Dim skipping As Boolean
            Dim foundBulk As Boolean

            ' Tally of what was removed. Printed after every export so that a
            ' card type arriving unexpectedly is VISIBLE. The whole reason a
            ' GRID went missing unnoticed is that this stage never said what it
            ' had taken out.
            Dim nEigrl As Long, nCord As Long, nParam As Long, nKept As Long
            Dim nComment As Long
            nEigrl = 0 : nCord = 0 : nParam = 0 : nKept = 0
            nComment = 0

            FixFile = False
            dropSummary = ""

            Set fso = CreateObject("Scripting.FileSystemObject")
            Set readOld = fso.OpenTextFile(fileName, 1)

            ' --- skip everything up to and including BEGIN BULK ---------------
            '
            ' The "$" banner is kept: it carries the Femap version, the source
            ' model and the export date, which is exactly the provenance an
            ' INCLUDE file should carry.
            '
            ' EVERY comment before BEGIN BULK is taken, not just the leading run.
            ' A first attempt captured only the first contiguous block of "$"
            ' lines, on the assumption the banner sat at the very top - it does
            ' not, and nothing was captured at all. Femap puts executive control
            ' (ID / SOL / CEND) around the comments, so the only reliable rule is
            ' "a comment line in the header is header text".
            Dim hdr() As String
            Dim nHdr As Long
            Dim hi As Long
            ReDim hdr(63)
            nHdr = 0

            foundBulk = False
            Do While Not readOld.AtEndOfStream
                        textLine = readOld.ReadLine

                        If UCase(Left(LTrim(textLine), 10)) = "BEGIN BULK" Then
                                    foundBulk = True
                                    Exit Do
                        End If

                        If Left(LTrim(textLine), 1) = "$" Then
                                    If nHdr > UBound(hdr) Then ReDim Preserve hdr(nHdr * 2)
                                    hdr(nHdr) = textLine
                                    nHdr = nHdr + 1
                        End If
            Loop

            If Not foundBulk Then
                        readOld.Close
                        Exit Function
            End If

            Dim newFileName As String   'This file will be the final file for the user
            newFileName = fileName & ".bdf"

            ' --- carry the notes out of the .bdf we are about to overwrite ----
            '
            ' Read this BEFORE CreateTextFile - that call truncates the file, so
            ' reading afterwards would always come back empty.
            Dim oldNotes As String
            Dim notesReport As String
            oldNotes = ""
            notesReport = "no previous file"
            If fso.FileExists(newFileName) Then
                        oldNotes = ExistingNotes(fso, newFileName, notesReport)
            End If

            Set writeNew = fso.CreateTextFile(newFileName, True)

            ' --- header, newest first -----------------------------------------
            '
            '   this run's custom lines
            '   NOTES_BEGIN
            '     ... every note carried over from previous exports ...
            '   NOTES_END
            '   BANNER_MARK
            '     Femap's provenance banner + the group line, regenerated
            '
            ' The markers are what make re-reading deterministic. Without them a
            ' re-export has to GUESS which "$" lines were the analyst's and which
            ' were Femap's, and getting that wrong either loses a note or stacks
            ' a stale banner forever. See ExistingNotes for the legacy fallback.
            Dim custLines() As String
            Dim ci As Long
            Dim nNew As Long, nCarried As Long
            nNew = 0 : nCarried = 0

            If Len(Trim(customHdr)) > 0 Then
                        custLines = Split(customHdr, Chr$(10))
                        For ci = 0 To UBound(custLines)
                                    If Len(Trim(custLines(ci))) > 0 Then
                                                writeNew.WriteLine custLines(ci)
                                                nNew = nNew + 1
                                    End If
                        Next ci
            End If

            writeNew.WriteLine NOTES_BEGIN
            If Len(oldNotes) > 0 Then
                        custLines = Split(oldNotes, Chr$(10))
                        For ci = 0 To UBound(custLines)
                                    If Len(Trim(custLines(ci))) > 0 Then
                                                writeNew.WriteLine custLines(ci)
                                                nCarried = nCarried + 1
                                    End If
                        Next ci
            End If
            writeNew.WriteLine NOTES_END

            writeNew.WriteLine BANNER_MARK
            For hi = 0 To nHdr - 1
                        writeNew.WriteLine hdr(hi)
            Next hi
            writeNew.WriteLine "$ Exported from group: " & grpTitle

            ' Printed every run, not behind a debug flag. Carrying notes across
            ' an overwrite is the kind of thing that fails silently and is only
            ' noticed months later, when the notes are already gone - so the run
            ' states what it did. nCarried = 0 on a re-export means nothing was
            ' carried; nHdr = 0 means the Femap banner was not captured.
            App.feAppMessage(FCM_NORMAL, "  Header: " & Trim(Str$(nNew)) & " new note(s), " & _
                        Trim(Str$(nCarried)) & " carried over, " & _
                        Trim(Str$(nHdr)) & " Femap banner line(s)   [" & notesReport & "]")

            ' --- copy the bulk data, dropping the dummy-analysis cards --------
            '
            ' EVERY comment line is kept, unconditionally. Femap's "$ ..." labels
            ' sit above real bulk data, so there is nothing to gain by deciding
            ' which ones to drop - and an earlier version that tried to (letting
            ' a comment share the fate of the following card) could only ever
            ' lose text that was wanted. A stray label above a removed PARAM is
            ' harmless; a missing label is not.
            skipping = False
            Do While Not readOld.AtEndOfStream
                        textLine = readOld.ReadLine

                        If Left(LTrim(textLine), 1) = "$" Then
                                    writeNew.WriteLine textLine
                                    nComment = nComment + 1
                        Else
                        ' --- not a comment: a card line or a continuation -----

                        If IsNewCard(textLine) Then
                                    cardName = CardNameOf(textLine)

                                    If cardName = "ENDDATA" Then
                                                ' commented out, as before, so the file can be included
                                                textLine = "$"
                                                skipping = False
                                    ElseIf cardName = "EIGRL" Then
                                                ' from the dummy Modes analysis set
                                                skipping = True
                                                nEigrl = nEigrl + 1
                                    ElseIf cardName = "PARAM" Then
                                                ' Solution parameters belong in the master deck, not in
                                                ' an INCLUDE file. The old line-counting version removed
                                                ' these as a side effect of its fixed skip; the name
                                                ' filter has to drop them deliberately.
                                                skipping = True
                                                nParam = nParam + 1
                                    ElseIf cardName = "CORD2C" Or cardName = "CORD2S" Then
                                                ' Only Femap's two global systems (CID 1 = cylindrical,
                                                ' 2 = spherical) are boilerplate. A user coordinate
                                                ' system must survive - the old line-counting version
                                                ' would have dropped one that landed in those slots.
                                                cid = FieldTwo(textLine)
                                                skipping = (cid = "1" Or cid = "2")
                                                If skipping Then nCord = nCord + 1
                                    Else
                                                skipping = False
                                    End If

                                    If Not skipping Then nKept = nKept + 1
                        End If

                        If Not skipping Then writeNew.WriteLine textLine

                        End If
            Loop

            dropSummary = Trim(Str$(nEigrl)) & " EIGRL, " & _
                          Trim(Str$(nCord)) & " global CORD2C/S, " & _
                          Trim(Str$(nParam)) & " PARAM   (" & _
                          Trim(Str$(nKept)) & " cards kept, " & _
                          Trim(Str$(nHdr)) & " header + " & _
                          Trim(Str$(nComment)) & " inline comments kept)"

            readOld.Close
            writeNew.Close

            FixFile = True

End Function

' -----------------------------------------------------------------------------
' True if this line starts a new bulk-data card rather than continuing one.
' Continuations begin with a blank, + or *; $ is a comment.
' -----------------------------------------------------------------------------
Function IsNewCard(ln As String) As Boolean
            Dim c As String
            IsNewCard = False
            If Len(ln) = 0 Then Exit Function
            c = Left(ln, 1)
            If c = " " Or c = Chr$(9) Or c = "+" Or c = "*" Or c = "$" Then Exit Function
            IsNewCard = True
End Function

' -----------------------------------------------------------------------------
' Card name from a bulk-data line: the first field, upper-cased, with any
' large-field "*" and comma removed. "CORD2C*" and "CORD2C," both give CORD2C.
' -----------------------------------------------------------------------------
Function CardNameOf(ln As String) As String
            Dim s As String
            Dim p As Long

            s = Left(ln, 8)
            p = InStr(s, ",")
            If p > 0 Then s = Left(s, p - 1)
            s = Replace(s, "*", "")
            CardNameOf = UCase(Trim(s))
End Function

' -----------------------------------------------------------------------------
' Second field of a bulk-data line (the ID on a CORD2i card). Handles free
' field (commas), small field (8 cols) and large field (16 cols).
' -----------------------------------------------------------------------------
Function FieldTwo(ln As String) As String
            Dim parts() As String
            Dim padded As String

            If InStr(ln, ",") > 0 Then
                        parts = Split(ln, ",")
                        If UBound(parts) >= 1 Then
                                    FieldTwo = Trim(parts(1))
                        Else
                                    FieldTwo = ""
                        End If
                        Exit Function
            End If

            padded = ln & Space(32)
            If InStr(Left(ln, 8), "*") > 0 Then
                        FieldTwo = Trim(Mid(padded, 9, 16))   'large field
            Else
                        FieldTwo = Trim(Mid(padded, 9, 8))    'small field
            End If
End Function

' -----------------------------------------------------------------------------
' Make a user-typed line safe to write into bulk data: it must be a comment.
' A line the user already started with "$" is left as-is.
' -----------------------------------------------------------------------------
Function AsComment(ln As String) As String
            Dim s As String
            s = Trim(ln)
            If Left(s, 1) = "$" Then
                        AsComment = s
            Else
                        AsComment = "$ " & s
            End If
End Function

Function DeleteTempFile(FileToDelete As String)
            SetAttr FileToDelete, vbNormal   'Makes sure it is not in the undeletable view
            Kill FileToDelete    'Deletes file

End Function

' -----------------------------------------------------------------------------
' Pull the analyst's notes out of an already-exported .bdf so a re-export can
' carry them forward. Returns them Chr$(10)-separated, oldest ordering preserved.
'
' TWO PATHS, and the difference matters:
'
' MARKED (written by this build or later) - the NOTES_BEGIN / NOTES_END pair is
' present, so the answer is exact: take what is between them, discard everything
' else. No interpretation, no guessing.
'
' LEGACY (written by an older build, or hand-made) - there are no markers, so
' every "$" line in the header has to be classified. The rule is deliberately
' LOPSIDED: a line is dropped only if it positively matches a shape Femap emits
' in its banner. Anything unrecognised is KEPT. The failure mode is therefore a
' stale banner line carried across once - visible, harmless, and self-correcting
' on the next export because markers exist from then on. The alternative bias
' would silently eat a note the analyst wrote, which is not recoverable.
'
' Reading stops at the first non-comment line. Everything below that is bulk
' data and none of it is header.
' -----------------------------------------------------------------------------
Function ExistingNotes(fso As Object, path As String, report As String) As String

            Dim rd As Object
            Dim ln As String
            Dim raw() As String
            Dim nRaw As Long
            Dim i As Long
            Dim marked As Boolean
            Dim inNotes As Boolean
            Dim out As String
            Dim nKept As Long, nDropped As Long

            ReDim raw(255)
            nRaw = 0
            marked = False
            out = ""
            nKept = 0
            nDropped = 0

            Set rd = fso.OpenTextFile(path, 1)
            Do While Not rd.AtEndOfStream
                        ln = rd.ReadLine
                        If Left(LTrim(ln), 1) <> "$" Then Exit Do
                        If nRaw > UBound(raw) Then ReDim Preserve raw(nRaw * 2)
                        raw(nRaw) = ln
                        nRaw = nRaw + 1
                        If Left(ln, Len(NOTES_BEGIN)) = NOTES_BEGIN Then marked = True
            Loop
            rd.Close

            If nRaw = 0 Then
                        report = "previous file had no header"
                        ExistingNotes = ""
                        Exit Function
            End If

            ' In a MARKED file the boundary that matters is BANNER_MARK, not
            ' NOTES_BEGIN. The previous run wrote its newest notes ABOVE
            ' NOTES_BEGIN - keeping only what sits between the two markers would
            ' drop exactly those lines, silently losing one run's notes on every
            ' re-export. So: keep every comment above BANNER_MARK, drop the
            ' marker lines themselves, discard everything from BANNER_MARK down.
            inNotes = True
            For i = 0 To nRaw - 1
                        ln = raw(i)

                        If Left(ln, Len(NOTES_BEGIN)) = NOTES_BEGIN Then
                                    ' marker - not content
                        ElseIf Left(ln, Len(NOTES_END)) = NOTES_END Then
                                    ' marker - not content
                        ElseIf Left(ln, Len(BANNER_MARK)) = BANNER_MARK Then
                                    inNotes = False
                        Else
                                    If marked Then
                                                If inNotes Then
                                                            out = out & ln & Chr$(10)
                                                            nKept = nKept + 1
                                                Else
                                                            nDropped = nDropped + 1
                                                End If
                                    Else
                                                ' Legacy: keep unless positively identified as banner.
                                                If IsBannerLine(ln) Then
                                                            nDropped = nDropped + 1
                                                Else
                                                            out = out & ln & Chr$(10)
                                                            nKept = nKept + 1
                                                End If
                                    End If
                        End If
            Next i

            If marked Then
                        report = "marked file: " & Trim(Str$(nKept)) & " note(s) kept, " & _
                                 Trim(Str$(nDropped)) & " banner line(s) dropped"
            Else
                        report = "LEGACY file (no markers): " & Trim(Str$(nKept)) & " line(s) kept, " & _
                                 Trim(Str$(nDropped)) & " recognised as banner - check the header once"
            End If

            ExistingNotes = out

End Function

' -----------------------------------------------------------------------------
' True only for the comment shapes Femap itself writes into its export banner.
' Used ONLY on legacy files that predate the markers. Kept deliberately narrow -
' see ExistingNotes for why the bias runs this way.
'
' Femap emits, with varying whitespace:
'   $ **********************************
'   $   Written by : Femap
'   $   Version    : 2306
'   $   Translator : Simcenter Nastran
'   $   From Model : C:\path\model.modfem
'   $   Date       : Tue Aug 26 ...
' plus the "Exported from group:" line this tool used to write as a note.
' -----------------------------------------------------------------------------
Function IsBannerLine(ln As String) As Boolean

            Dim t As String
            Dim u As String
            Dim i As Long
            Dim c As String
            Dim allRule As Boolean

            IsBannerLine = False
            t = Trim(ln)
            If Left(t, 1) <> "$" Then Exit Function

            t = Trim(Mid(t, 2))
            If Len(t) = 0 Then Exit Function      ' a bare "$" spacer - not banner

            ' A rule line: nothing after the "$" but * - = or _ characters.
            allRule = True
            For i = 1 To Len(t)
                        c = Mid(t, i, 1)
                        If c <> "*" And c <> "-" And c <> "=" And c <> "_" Then
                                    allRule = False
                                    Exit For
                        End If
            Next i
            If allRule Then
                        IsBannerLine = True
                        Exit Function
            End If

            u = UCase(t)
            If Left(u, 11) = "WRITTEN BY "        Then IsBannerLine = True
            If Left(u, 8)  = "VERSION "           Then IsBannerLine = True
            If Left(u, 11) = "TRANSLATOR "        Then IsBannerLine = True
            If Left(u, 11) = "FROM MODEL "        Then IsBannerLine = True
            If Left(u, 5)  = "DATE "              Then IsBannerLine = True
            If Left(u, 10) = "OUTPUT TO "         Then IsBannerLine = True
            If Left(u, 20) = "EXPORTED FROM GROUP:" Then IsBannerLine = True

End Function
