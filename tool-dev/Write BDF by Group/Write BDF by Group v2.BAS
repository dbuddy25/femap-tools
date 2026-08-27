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
' 20260827
' - The Femap banner is no longer written into the .bdf. Every "$" line in the
'   header is a note, so carrying them forward needs no boundary, no marker and
'   no pattern matching. Banners left in files by older builds are stripped on
'   the next export by comparing against Femap's output for that run.
' 20260826
' - Re-exporting over an existing .bdf now PRESERVES the notes already in it.
'   New custom lines are written ABOVE the retained ones, so the header reads
'   newest-first, while Femap's own banner (version / model / date) and the
'   "Exported from group" line were regenerated every run. Both were dropped
'   entirely on 20260827 - see below.
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
Begin Dialog UserDialog 560,368,"Write BDF by Group - Options" 'NasBulkLargeField %GRID:10,7,1,1
            GroupBox 8,4,268,104,"Field format",.GroupBox1
                        ListBox 20,22,248,78,FFormat(),.ListBox1
            GroupBox 284,4,268,104,"Group name is already the file name?",.GroupBox2
                        OptionGroup.Group1
                        OptionButton 300,28,236,20,"No",.OptionButton1
                        OptionButton 300,56,236,20,"Yes",.OptionButton2
            ' Three single-line boxes rather than one multiline box: every
            ' TextBox in this toolset is single-line, and this is not the script
            ' to try unproven dialog syntax on.
            GroupBox 8,116,544,110,"Header comments (optional)",.GroupBox3
                        TextBox 20,136,520,22,.hdr1
                        TextBox 20,164,520,22,.hdr2
                        TextBox 20,192,520,22,.hdr3
            ' The explanatory line is kept to ONE line that fits at this width.
            ' WinWrap Text controls do not wrap gracefully - an overlong string
            ' is clipped mid-sentence, which is worse than not saying it.
            GroupBox 8,234,544,66,"Output folder",.GroupBox4
                        CheckBox 20,254,196,16,"Write into a subfolder:",.chkSub
                        TextBox  222,250,318,22,.subBox
                        Text     20,278,520,14,"Relative to the model folder. Created if it does not exist."
            OKButton 160,314,120,34
            CancelButton 300,314,120,34
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

            ' --- do these groups contain NSM regions? -------------------------
            '
            ' *** FT_CONTACT (58) IS A FEMAP *REGION*. FT_CONNECTION (71) IS THE
            ' *** CONNECTOR (contact pair). The names are the wrong way round
            ' *** from what you would guess, and picking the wrong one here
            ' *** silently counts zero regions forever.
            '
            ' Femap will not write NSM cards for a group-filtered export, and
            ' recovering them here turned out worse than the problem: NSM
            ' regions do not respect group boundaries, so a region straddling
            ' two groups had to be skipped rather than split - for the
            ' total-mass forms, handing the same total to a subset of the
            ' elements silently changes the mass.
            '
            ' export-nsm-cards writes them all to one file instead, included
            ' once by the master deck. All this does now is say so, because a
            ' deck quietly missing its nonstructural mass is exactly the failure
            ' that went unnoticed before.
            Dim regAll As femap.Set
            Set regAll = App.feSet
            regAll.Clear
            rc = regAll.AddAll(FT_CONTACT)
            Dim nRegModel As Long
            nRegModel = regAll.Count

            Dim regGrp As femap.Set
            Set regGrp = App.feSet
            Dim rgn As Object
            Set rgn = App.feConnectionRegion

            If nRegModel > 0 Then
                        Dim probeID As Long
                        Dim pj As Long
                        Dim prID As Long
                        Dim anyNSM As Boolean
                        anyNSM = False
                        grSet.Reset
                        probeID = grSet.Next
                        Do While probeID > 0
                                    regGrp.Clear
                                    rc = regGrp.AddGroup(FT_CONTACT, probeID)
                                    If regGrp.Count > 0 Then
                                                prID = regGrp.First
                                                For pj = 1 To regGrp.Count
                                                            If rgn.Get(prID) = FE_OK Then
                                                                        If rgn.type = FRT_NSM Then anyNSM = True
                                                            End If
                                                            prID = regGrp.Next
                                                Next pj
                                    End If
                                    probeID = grSet.Next
                        Loop
                        ' The export loop walks this same set with NextInSet.
                        grSet.Reset

                        If anyNSM Then
                                    App.feAppMessage(FCM_WARNING, "These groups contain NSM regions.")
                                    App.feAppMessage(FCM_WARNING, "Femap does not write NSM cards for a group export, so these")
                                    App.feAppMessage(FCM_WARNING, "decks will have none. Run export-nsm-cards to collect them")
                                    App.feAppMessage(FCM_WARNING, "into one file and include it once from the master deck.")
                        End If
            End If


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

                                    ' --- does this group carry its NSM regions? ---
                                    '
                                    ' Counting regions is not enough. FT_CONTACT covers EVERY
                                    ' region - contact, glue, bolt, fluid - so a model with glued
                                    ' contact reports plenty of regions while carrying no
                                    ' nonstructural mass at all. The regions are walked and only
                                    ' those with a nonzero MassNSM counted.
                                    '
                                    ' MassNSM is tested rather than the documented type field:
                                    ' that field lists 0=Contact, 1=Fluid, 2=Bolt, 3=Rotor and
                                    ' has no NSM value, yet the same object carries the NSM mass
                                    ' properties - so the NSM type number is undocumented and
                                    ' cannot be relied on. A nonzero mass is unambiguous.
                                    If nRegModel > 0 Then
                                                regGrp.Clear
                                                rc = regGrp.AddGroup(FT_CONTACT, gr.ID)

                                                ' Raw field dump, not a verdict.
                                                '
                                                ' An earlier version counted regions whose MassNSM was
                                                ' nonzero and called those "NSM regions". That is not
                                                ' safe: MassNSM is only meaningful on an NSM-type
                                                ' region, and read off a contact or glue region it can
                                                ' hold anything left in the slot. It reported 8 of 8 on
                                                ' a model whose NSM never reached the deck, which is
                                                ' exactly the false positive you would expect.
                                                '
                                                ' The type field IS reliable after all - the Region
                                                ' Object property table omits NSM from its 0..3 list,
                                                ' but the constants table has FRT_NSM alongside
                                                ' FRT_CONNECTION / FRT_FLUID / FRT_BOLT / FRT_ROTOR.
                                                ' The named constant is used rather than a number so
                                                ' this does not depend on the ordering holding.
                                                Dim regID As Long
                                                Dim ri As Long
                                                Dim shown As Long
                                                shown = 0
                                                App.feAppMessage(FCM_HIGHLIGHT, _
                                                            "  Regions in group '" & gr.title & "': " & Trim(Str$(regGrp.Count)))
                                                If regGrp.Count > 0 Then
                                                            regID = regGrp.First
                                                            For ri = 1 To regGrp.Count
                                                                        If shown < 20 Then
                                                                                    If rgn.Get(regID) = FE_OK Then
                                                                                                App.feAppMessage(FCM_NORMAL, _
                                                                                                            "    ID " & Trim(Str$(regID)) _
                                                                                                            & "  type=" & Trim(Str$(rgn.type)) _
                                                                                                            & IIf(rgn.type = FRT_NSM, " (NSM)", "") _
                                                                                                            & "  MassType=" & Trim(Str$(rgn.MassType)) _
                                                                                                            & "  MassNSM=" & Format$(rgn.MassNSM, "0.000000E+00") _
                                                                                                            & "  count=" & Trim(Str$(rgn.count)) _
                                                                                                            & "  " & rgn.title)
                                                                                                shown = shown + 1
                                                                                    Else
                                                                                                App.feAppMessage(FCM_WARNING, _
                                                                                                            "    ID " & Trim(Str$(regID)) & "  could not be read")
                                                                                                shown = shown + 1
                                                                                    End If
                                                                        End If
                                                                        regID = regGrp.Next
                                                            Next ri
                                                            If regGrp.Count > 20 Then
                                                                        App.feAppMessage(FCM_NORMAL, "    ... and " _
                                                                                    & Trim(Str$(regGrp.Count - 20)) & " more")
                                                            End If
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

            ' Which names, not just how many. NSMADD combines NSM sets, so a
            ' deck with NSM1 but no NSMADD - or the reverse - is broken in a way
            ' a single total would hide completely.
            Dim nsmNames As String
            nsmNames = ""

            ' Contact cards are counted the same way, for free - this loop
            ' already sees every card. Femap's group filter drops NSM, and
            ' contact regions are Regions too, so the same thing may well happen
            ' to these. Counting them means the next ordinary export answers
            ' that, instead of it being found in a deck that solves without its
            ' contact. Same list as the export-contact-cards tool.
            Dim nCon As Long
            Dim conNames As String
            nCon = 0
            conNames = ""

            FixFile = False
            dropSummary = ""

            Set fso = CreateObject("Scripting.FileSystemObject")
            Set readOld = fso.OpenTextFile(fileName, 1)

            ' --- skip everything up to and including BEGIN BULK ---------------
            '
            ' The "$" banner is captured but NOT written to the .bdf. It is used
            ' only to recognise and strip the banner out of a file exported by an
            ' older build - same Femap, same model, so nearly every line matches
            ' character-for-character. See ExistingNotes.
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
                        oldNotes = ExistingNotes(fso, newFileName, hdr(), nHdr, notesReport)
            End If

            Set writeNew = fso.CreateTextFile(newFileName, True)

            ' --- header, newest first -----------------------------------------
            '
            '   this run's custom lines
            '   ... every note carried over from previous exports ...
            '
            ' That is the whole header. Femap's provenance banner is NOT written:
            ' the version and date it carried were not worth the space, and not
            ' writing it removes the only thing a re-export had to identify.
            ' Every "$" line in the header is now a note, so carrying them
            ' forward needs no boundary, no marker and no pattern matching -
            ' which is where every bug in this area came from.
            '
            ' hdr() is still read from Femap's output, but only to strip the
            ' banner out of files written by an older build. See ExistingNotes.
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


            ' The notes themselves are echoed above, newest first and marked
            ' "+" - that is where they are meant to be READ. Carrying notes
            ' across an overwrite fails silently otherwise, and is only noticed
            ' months later when they are already gone.
            '
            ' nCarried = 0 on a re-export means nothing was carried.
            App.feAppMessage(FCM_NORMAL, "  Notes: " & Trim(Str$(nNew)) & " new, " & _
                        Trim(Str$(nCarried)) & " carried over   [" & notesReport & "]")

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

                                    If IsContactCard(cardName) Then
                                                nCon = nCon + 1
                                                If InStr(conNames, " " & cardName & " ") = 0 Then
                                                            conNames = conNames & " " & cardName & " "
                                                End If
                                    End If

                                    If Left(cardName, 3) = "NSM" Then
                                                nNSMseen = nNSMseen + 1
                                                If Not skipping Then nNSMkept = nNSMkept + 1
                                                If InStr(nsmNames, " " & cardName & " ") = 0 Then
                                                            nsmNames = nsmNames & " " & cardName & " "
                                                End If
                                    End If

                                    If Not skipping Then nKept = nKept + 1
                        End If

                        If Not skipping Then writeNew.WriteLine textLine

                        End If
            Loop

            App.feAppMessage(FCM_NORMAL, "  NSM-family cards in Femap's output: " & Trim(Str$(nNSMseen)) _
                        & ", kept: " & Trim(Str$(nNSMkept)))
            If nNSMseen = 0 Then
                        App.feAppMessage(FCM_WARNING, "  Femap wrote no NSM, NSM1, NSML, NSML1 or NSMADD for this group.")
                        App.feAppMessage(FCM_WARNING, "  Nothing was filtered out here - they never arrived.")
            Else
                        App.feAppMessage(FCM_NORMAL, "  Card names seen:" & nsmNames)
                        If InStr(nsmNames, " NSMADD ") = 0 Then
                                    App.feAppMessage(FCM_WARNING, "  No NSMADD - the NSM sets are not combined.")
                        End If
            End If

            If nCon > 0 Then
                        App.feAppMessage(FCM_NORMAL, "  Contact cards written: " & Trim(Str$(nCon)) & "  " & conNames)
            Else
                        App.feAppMessage(FCM_NORMAL, "  Contact cards written: none")
            End If

            dropSummary = Trim(Str$(nEigrl)) & " EIGRL, " & _
                          Trim(Str$(nCord)) & " global CORD2C/S, " & _
                          Trim(Str$(nParam)) & " PARAM   (" & _
                          Trim(Str$(nKept)) & " cards kept, " & _
                          Trim(Str$(nComment)) & " comments kept)"

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
' EVERY COMMENT IS A NOTE
' The Femap banner is no longer written, so there is nothing else in the header
' to tell notes apart from. Every "$" line is a note. No boundary, no marker, no
' pattern matching - which is where every bug in this area came from.
'
' THE ONLY EXCEPTION IS CLEANING UP AFTER OLDER BUILDS
' Files exported before this change still contain a banner, and it would
' otherwise be read back as a pile of notes and carried forward forever. So a
' line is dropped if it matches one of hdr() - Femap's banner for THIS export,
' from the same Femap against the same model, so nearly every line is
' character-for-character identical and only the date moves. A 16-character
' prefix match covers "$   Date       :" while stopping short of the value that
' changes. Marker scaffolding and "$ Exported from group:" lines from those
' builds are dropped by name.
'
' Once a file has been re-exported once, none of that applies to it again.
'
' BIAS: an unmatched line is KEPT. Losing a note is unrecoverable; a stray line
' appears in the Messages echo on the next run and can be deleted.
'
' Reading stops at the first non-comment line - below that is bulk data.
' -----------------------------------------------------------------------------
Function ExistingNotes(fso As Object, path As String, hdr() As String, nHdr As Long, report As String) As String

            Dim rd As Object
            Dim ln As String
            Dim raw() As String
            Dim nRaw As Long
            Dim i As Long, j As Long
            Dim marked As Boolean
            Dim cut As Long
            Dim isBanner As Boolean
            Dim out As String
            Dim nKept As Long, nDropped As Long

            ReDim raw(255)
            nRaw = 0
            marked = False
            cut = -1
            out = ""
            nKept = 0
            nDropped = 0

            Set rd = fso.OpenTextFile(path, 1)
            Do While Not rd.AtEndOfStream
                        ln = rd.ReadLine
                        If Left(LTrim(ln), 1) <> "$" Then Exit Do
                        If nRaw > UBound(raw) Then ReDim Preserve raw(nRaw * 2)
                        raw(nRaw) = ln
                        If cut < 0 Then
                                    If Left(ln, Len(OLD_BANNER_MARK)) = OLD_BANNER_MARK Then
                                                marked = True
                                                cut = nRaw
                                    ElseIf Left(ln, Len(OLD_BANNER_MK2)) = OLD_BANNER_MK2 Then
                                                marked = True
                                                cut = nRaw
                                    End If
                        End If
                        nRaw = nRaw + 1
            Loop
            rd.Close

            If nRaw = 0 Then
                        report = "previous file had no header"
                        ExistingNotes = ""
                        Exit Function
            End If

            For i = 0 To nRaw - 1
                        ln = raw(i)

                        If marked And i >= cut Then
                                    ' Older file: everything from its marker down is banner.
                                    nDropped = nDropped + 1
                        ElseIf Left(ln, Len(OLD_NOTES_BEGIN)) = OLD_NOTES_BEGIN Then
                                    nDropped = nDropped + 1
                        ElseIf Left(ln, Len(OLD_NOTES_END)) = OLD_NOTES_END Then
                                    nDropped = nDropped + 1
                        ElseIf Left(LTrim(ln), 22) = "$ Exported from group:" Then
                                    nDropped = nDropped + 1
                        Else
                                    isBanner = False
                                    For j = 0 To nHdr - 1
                                                If ln = hdr(j) Then
                                                            isBanner = True
                                                            Exit For
                                                End If
                                                If Len(ln) >= 16 And Len(hdr(j)) >= 16 Then
                                                            If Left(ln, 16) = Left(hdr(j), 16) Then
                                                                        isBanner = True
                                                                        Exit For
                                                            End If
                                                End If
                                    Next j

                                    If isBanner Then
                                                nDropped = nDropped + 1
                                    Else
                                                out = out & ln & Chr$(10)
                                                nKept = nKept + 1
                                    End If
                        End If
            Next i

            report = Trim(Str$(nKept)) & " note(s) kept"
            If nDropped > 0 Then
                        report = report & ", " & Trim(Str$(nDropped)) & " old banner line(s) stripped"
            End If

            ExistingNotes = out

End Function

' -----------------------------------------------------------------------------
' Is this one of the contact/glue bulk data cards?
'
' Same list as the export-contact-cards tool, so the two agree on what "contact
' data" means: surfaces (BSURF/BSURFS), property-based surfaces (BCPROP/
' BCPROPS), the set and add cards for glue (BGSET/BGADD) and contact
' (BCTSET/BCTADD), and the parameter card (BGPARM).
' -----------------------------------------------------------------------------
Function IsContactCard(cardName As String) As Boolean

            IsContactCard = (cardName = "BSURF" Or cardName = "BSURFS" _
                        Or cardName = "BCPROP" Or cardName = "BCPROPS" _
                        Or cardName = "BGSET" Or cardName = "BGADD" _
                        Or cardName = "BCTSET" Or cardName = "BCTADD" _
                        Or cardName = "BGPARM")

End Function
