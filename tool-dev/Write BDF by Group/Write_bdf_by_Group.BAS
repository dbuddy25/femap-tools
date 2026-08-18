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
Begin Dialog UserDialog 400,303,"Options" 'NasBulkLargeField %GRID:10,7,1,1
            GroupBox 5,0,300,100,"Select Field Format",.GroupBox1
                        ListBox 20,21,200,75,FFormat(),.ListBox1
            GroupBox 5,120,300,70,"Is Group Name already the bdf file Name?",.GroupBox2
                        OptionGroup.Group1
                        OptionButton 50,135,150,21,"No",.OptionButton1
                        OptionButton 50,160,150,21,"Yes",.OptionButton2
            OKButton 70,205,120,35
            CancelButton 220,205,120,35
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

                                    fixOK = FixFile(grFileName, dropInfo) 'Funciton that writes correct data to new final file

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
Function FixFile(fileName As String, dropSummary As String) As Boolean

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
            nEigrl = 0 : nCord = 0 : nParam = 0 : nKept = 0

            FixFile = False
            dropSummary = ""

            Set fso = CreateObject("Scripting.FileSystemObject")
            Set readOld = fso.OpenTextFile(fileName, 1)

            ' --- skip everything up to and including BEGIN BULK ---------------
            foundBulk = False
            Do While Not readOld.AtEndOfStream
                        textLine = readOld.ReadLine
                        If UCase(Left(LTrim(textLine), 10)) = "BEGIN BULK" Then
                                    foundBulk = True
                                    Exit Do
                        End If
            Loop

            If Not foundBulk Then
                        readOld.Close
                        Exit Function
            End If

            Dim newFileName As String   'This file will be the final file for the user
            newFileName = fileName & ".bdf"
            Set writeNew = fso.CreateTextFile(newFileName, True)

            ' --- copy the bulk data, dropping the dummy-analysis cards --------
            skipping = False
            Do While Not readOld.AtEndOfStream
                        textLine = readOld.ReadLine

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
            Loop

            dropSummary = Trim(Str$(nEigrl)) & " EIGRL, " & _
                          Trim(Str$(nCord)) & " global CORD2C/S, " & _
                          Trim(Str$(nParam)) & " PARAM   (" & _
                          Trim(Str$(nKept)) & " cards kept)"

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

Function DeleteTempFile(FileToDelete As String)
            SetAttr FileToDelete, vbNormal   'Makes sure it is not in the undeletable view
            Kill FileToDelete    'Deletes file

End Function
