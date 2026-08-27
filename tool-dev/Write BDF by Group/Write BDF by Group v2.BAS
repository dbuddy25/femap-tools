' Write BDF by Group v2.BAS
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
' Markers left in files by earlier builds. Nothing is written now.
' -----------------------------------------------------------------------------
' Scaffolding written by earlier builds. NOTHING is written into the file any
' more - see ExistingNotes for how the banner is found without a marker - but
' any .bdf already exported by those builds carries these lines, and without
' recognising them they would be read back as notes and carried forward forever.
Const OLD_NOTES_BEGIN As String = "$>>> EXPORT NOTES"
Const OLD_NOTES_END   As String = "$<<< END EXPORT NOTES"
Const OLD_BANNER_MARK As String = "$--- FEMAP BANNER"
Const OLD_BANNER_MK2  As String = "$--- Femap banner below is regenerated"

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
Begin Dialog UserDialog 560,392,"Write BDF by Group - Options" 'NasBulkLargeField %GRID:10,7,1,1
            GroupBox 8,4,268,108,"Field format",.GroupBox1
                        ListBox 20,24,248,80,FFormat(),.ListBox1
            GroupBox 284,4,268,108,"Group name is already the file name?",.GroupBox2
                        OptionGroup.Group1
                        OptionButton 300,30,236,20,"No",.OptionButton1
                        OptionButton 300,58,236,20,"Yes",.OptionButton2
            ' Three single-line boxes rather than one multiline box: every
            ' TextBox in this toolset is single-line, and this is not the script
            ' to try unproven dialog syntax on.
            GroupBox 8,122,544,116,"Header comments (optional)",.GroupBox3
                        TextBox 20,144,520,22,.hdr1
                        TextBox 20,172,520,22,.hdr2
                        TextBox 20,200,520,22,.hdr3
            GroupBox 8,246,544,76,"Output folder",.GroupBox4
                        CheckBox 20,268,200,16,"Write into a subfolder:",.chkSub
                        TextBox  226,264,314,22,.subBox
                        Text     20,294,520,20,"Relative to the model folder, created if missing. A full path (with a drive letter) is used as-is."
            OKButton 160,340,120,34
            CancelButton 300,340,120,34
End Dialog
Dim dlg As UserDialog
dlg.chkSub = 0
dlg.subBox = "Model"
UserFormat = Dialog(dlg)

If UserFormat = -1 Then 'user pressed ok
            UserFormat = dlg.ListBox1
ElseIf UserFormat = 0 Then 'terminates macro if user cancels
            End
End If

'Updates field format
sao.NasBulkLargeField = UserFormat

            ' --- where the files go -------------------------------------------
            '
            ' Off by default: the export lands beside the model, which is where
            ' this tool has always put it, and changing where a shared tool
            ' writes without being asked is how someone loses a deck. Tick it and
            ' the box is already filled in with "Model" - one click for the
            ' common case, since a group export drops one file per group and
            ' they bury the model file otherwise.
            '
            ' A value containing ":" is taken as a full path and used as-is, so
            ' the same box handles "send it somewhere else entirely" without a
            ' second control.
            Dim outPath As String
            Dim subWanted As String
            outPath = modelFIlePath
            subWanted = Trim(dlg.subBox)

            If dlg.chkSub <> 0 And Len(subWanted) > 0 Then
                        If InStr(subWanted, ":") > 0 Then
                                    outPath = subWanted
                        Else
                                    outPath = modelFIlePath & subWanted
                        End If
                        If Right(outPath, 1) <> "\" Then outPath = outPath & "\"

                        Dim fsoDir As Object
                        Set fsoDir = CreateObject("Scripting.FileSystemObject")
                        If Not fsoDir.FolderExists(outPath) Then
                                    On Error Resume Next
                                    fsoDir.CreateFolder(outPath)
                                    On Error GoTo 0
                        End If
                        If Not fsoDir.FolderExists(outPath) Then
                                    App.feAppMessage(FCM_ERROR, "Could not create output folder: " & outPath)
                                    App.feAppMessage(FCM_ERROR, "Nothing was written - exiting")
                                    Exit Sub
                        End If
            End If

            App.feAppMessage(FCM_NORMAL, "Writing to: " & outPath)

            ' --- regions in the model, for the NSM check below ----------------
            '
            ' *** FT_CONTACT (58) IS A FEMAP *REGION*. FT_CONNECTION (71) IS THE
            ' *** CONNECTOR (contact pair). The names are the wrong way round
            ' *** from what you would guess, and picking the wrong one here
            ' *** silently counts zero regions forever.
            '
            ' Nonstructural-mass regions are Regions, not elements. Femap's
            ' group-filtered write emits only entities that are IN the group
            ' (NasBulkGroupID), so a group holding the elements but not the
            ' region gets the section comment and no NSM card - which reads as
            ' "the NSM went missing" when nothing is actually broken.
            Dim regAll As femap.Set
            Set regAll = App.feSet
            regAll.Clear
            rc = regAll.AddAll(FT_CONTACT)
            Dim nRegModel As Long
            nRegModel = regAll.Count

            Dim regGrp As femap.Set
            Set regGrp = App.feSet
            Dim nRegMissing As Long
            nRegMissing = 0

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
                                                            grFileName = outPath & "Group_" & gr.title 'Sets temp file name
                                                Case 1
                                                            job = Split(gr.title,".")
                                                            grFileName = outPath & job(0)
                                    End Select

                                                                        App.feFileWriteNastran(8,grFileName)  '8 for nx
                                                                        App.feAppMessage(FCM_COMMAND,"Wrote Original Nastran file: " & grFileName )

                                    ' --- does this group carry its regions? ---
                                    If nRegModel > 0 Then
                                                regGrp.Clear
                                                rc = regGrp.AddGroup(FT_CONTACT, gr.ID)
                                                If regGrp.Count = 0 Then
                                                            nRegMissing = nRegMissing + 1
                                                            App.feAppMessage(FCM_WARNING, _
                                                                        "  No regions in group '" & gr.title & _
                                                                        "' - any NSM on it will not be written")
                                                Else
                                                            App.feAppMessage(FCM_NORMAL, _
                                                                        "  Regions in group: " & Trim(Str$(regGrp.Count)))
                                                End If
                                    End If

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

                        If nRegMissing > 0 Then
                                    App.feAppMessage(FCM_ERROR, "----------------------------------------")
                                    App.feAppMessage(FCM_ERROR, "  " & Trim(Str$(nRegMissing)) & " of " & _
                                                Trim(Str$(grSet.Count)) & " group(s) contain no Regions, but the")
                                    App.feAppMessage(FCM_ERROR, "  model has " & Trim(Str$(nRegModel)) & ".")
                                    App.feAppMessage(FCM_ERROR, "  Nonstructural mass lives on a REGION, not on the")
                                    App.feAppMessage(FCM_ERROR, "  elements. Femap writes only what is in the group,")
                                    App.feAppMessage(FCM_ERROR, "  so those NSM cards were skipped - you may see the")
                                    App.feAppMessage(FCM_ERROR, "  section comment with no card under it.")
                                    App.feAppMessage(FCM_ERROR, "  Fix: add the Region to the group")
                                    App.feAppMessage(FCM_ERROR, "  (Group - Set - <group>, then Group - Region).")
                                    App.feAppMessage(FCM_ERROR, "----------------------------------------")
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

            ' Counted separately because "the NSM went missing" has two very
            ' different causes and this number tells them apart outright:
            '   0 seen  -> Femap never wrote them. The region is not in the
            '              group, so nothing here can help.
            '   N seen, N kept -> they ARE in the .bdf and the problem is
            '              elsewhere.
            ' Covers NSM, NSM1, NSML, NSML1 and NSMADD via the name prefix.
            Dim nNSMseen As Long, nNSMkept As Long
            nNSMseen = 0
            nNSMkept = 0

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
            '   ... every note carried over from previous exports ...
            '   Femap's provenance banner + the group line, regenerated
            '
            ' Nothing marks the boundary - the file is plain comments. A
            ' re-export finds it by walking UP from the bulk data through the
            ' banner, which is a contiguous run of recognisable shapes sitting at
            ' the bottom of the header. See ExistingNotes.
            Dim custLines() As String
            Dim ci As Long
            Dim nNew As Long, nCarried As Long
            nNew = 0 : nCarried = 0

            App.feAppMessage(FCM_HIGHLIGHT, "  Notes in " & newFileName & ":")

            If Len(Trim(customHdr)) > 0 Then
                        custLines = Split(customHdr, Chr$(10))
                        For ci = 0 To UBound(custLines)
                                    If Len(Trim(custLines(ci))) > 0 Then
                                                writeNew.WriteLine custLines(ci)
                                                nNew = nNew + 1
                                                App.feAppMessage(FCM_NORMAL, "    + " & custLines(ci))
                                    End If
                        Next ci
            End If

            If Len(oldNotes) > 0 Then
                        custLines = Split(oldNotes, Chr$(10))
                        For ci = 0 To UBound(custLines)
                                    If Len(Trim(custLines(ci))) > 0 Then
                                                writeNew.WriteLine custLines(ci)
                                                nCarried = nCarried + 1
                                                App.feAppMessage(FCM_NORMAL, "      " & custLines(ci))
                                    End If
                        Next ci
            End If

            For hi = 0 To nHdr - 1
                        writeNew.WriteLine hdr(hi)
            Next hi
            writeNew.WriteLine "$ Exported from group: " & grpTitle

            ' The notes themselves are echoed above, newest first and marked
            ' "+" - that is where they are meant to be READ. Carrying notes
            ' across an overwrite fails silently otherwise, and is only noticed
            ' months later when they are already gone.
            '
            ' nCarried = 0 on a re-export means nothing was carried;
            ' nHdr = 0 means the Femap banner was not captured.
            App.feAppMessage(FCM_NORMAL, "  Notes: " & Trim(Str$(nNew)) & " new, " & _
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

                                    If Left(cardName, 3) = "NSM" Then
                                                nNSMseen = nNSMseen + 1
                                                If Not skipping Then nNSMkept = nNSMkept + 1
                                    End If

                                    If Not skipping Then nKept = nKept + 1
                        End If

                        If Not skipping Then writeNew.WriteLine textLine

                        End If
            Loop

            App.feAppMessage(FCM_NORMAL, "  NSM cards in Femap's output: " & Trim(Str$(nNSMseen)) _
                        & ", kept: " & Trim(Str$(nNSMkept)))
            If nNSMseen = 0 Then
                        App.feAppMessage(FCM_WARNING, "  Femap wrote no NSM cards for this group - nothing was filtered out here.")
            End If

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
' carry them forward. Returns them Chr$(10)-separated, order preserved.
'
' HOW THE BOUNDARY IS FOUND WITHOUT A MARKER
' The header of a file this tool wrote is:
'
'   notes        <- newest first, may be empty
'   banner       <- Femap's, regenerated every export, always last
'
' so the split is found by walking UP from the bulk data. Femap's banner is a
' CONTIGUOUS run of recognisable shapes at the bottom of the header, so the scan
' stops at the first line from the bottom that is not one of them; everything
' above that is a note.
'
' Walking up matters. Classifying every line independently would drop a note
' that merely happens to start "Date reviewed by..." wherever it sat. Walking up
' only exposes the note directly adjacent to the banner, which is a far narrower
' target - and one the Messages echo makes visible immediately, because a lost
' or gained line shows up in the list printed on the very next export.
'
' Bare "$" spacers are absorbed into the banner run rather than stopping it.
' They carry nothing, so losing one costs nothing, while stopping on one would
' strand the whole banner above it and carry it forward as notes.
'
' BIAS: if the banner is not recognised at all, the scan stops immediately and
' everything becomes a note. That keeps text rather than losing it - the right
' way round, since a stale banner line appears in the Messages echo on the next
' run and can be deleted, whereas a silently eaten note cannot be recovered.
'
' Files from earlier builds carry explicit markers. Those are still honoured as
' a hard boundary when present, and their scaffolding lines are dropped.
'
' Reading stops at the first non-comment line - below that is bulk data.
' -----------------------------------------------------------------------------
Function ExistingNotes(fso As Object, path As String, report As String) As String

            Dim rd As Object
            Dim ln As String
            Dim raw() As String
            Dim nRaw As Long
            Dim i As Long
            Dim marked As Boolean
            Dim cut As Long
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
                        If Left(ln, Len(OLD_BANNER_MARK)) = OLD_BANNER_MARK Then marked = True
                        If Left(ln, Len(OLD_BANNER_MK2)) = OLD_BANNER_MK2 Then marked = True
            Loop
            rd.Close

            If nRaw = 0 Then
                        report = "previous file had no header"
                        ExistingNotes = ""
                        Exit Function
            End If

            ' --- find where the notes end ---
            cut = nRaw
            If marked Then
                        ' An older file: its marker is the boundary, exactly.
                        For i = 0 To nRaw - 1
                                    If Left(raw(i), Len(OLD_BANNER_MARK)) = OLD_BANNER_MARK Then
                                                cut = i
                                                Exit For
                                    End If
                                    If Left(raw(i), Len(OLD_BANNER_MK2)) = OLD_BANNER_MK2 Then
                                                cut = i
                                                Exit For
                                    End If
                        Next i
            Else
                        ' Walk up through the banner run.
                        cut = nRaw
                        Do While cut > 0
                                    If IsBannerLine(raw(cut - 1)) Then
                                                cut = cut - 1
                                    ElseIf Trim(raw(cut - 1)) = "$" Then
                                                cut = cut - 1
                                    Else
                                                Exit Do
                                    End If
                        Loop
            End If

            For i = 0 To nRaw - 1
                        ln = raw(i)
                        If Left(ln, Len(OLD_NOTES_BEGIN)) = OLD_NOTES_BEGIN Then
                                    ' old scaffolding - not content
                        ElseIf Left(ln, Len(OLD_NOTES_END)) = OLD_NOTES_END Then
                                    ' old scaffolding - not content
                        ElseIf i < cut Then
                                    out = out & ln & Chr$(10)
                                    nKept = nKept + 1
                        Else
                                    nDropped = nDropped + 1
                        End If
            Next i

            report = Trim(Str$(nKept)) & " note(s) kept, " & _
                     Trim(Str$(nDropped)) & " banner line(s) dropped"
            If nKept > 0 And cut = nRaw Then
                        report = report & " - BANNER NOT RECOGNISED, check the notes list above"
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
