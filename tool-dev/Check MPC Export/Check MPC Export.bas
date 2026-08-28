' Check MPC Export.bas
' -----------------------------------------------------------------------------
' Diagnostic. Answers one question: WHERE do constraint equations stop being
' written on their way into a Nastran deck?
'
' Constraint equations that plainly exist in the model can come out of an export
' as nothing at all - no MPC cards, no warning, no empty section. There are at
' least three independent gates between an equation and a deck, they fail
' identically, and no message distinguishes them:
'
'   1. THE EQUATIONS ARE NOT WHERE YOU THINK. They live in a constraint SET,
'      and a set that looks active in the UI is not necessarily the one that
'      got written to.
'   2. THE ANALYSIS SET DOES NOT SELECT THEM. An analysis set names its
'      constraint equations in BCSet[1], a SEPARATE slot from BCSet[0]
'      constraints. Unset - which is what a fresh analysis set has - means no
'      set is selected and nothing is written.
'   3. THE GROUP FILTER DROPS THEM. NasBulkGroupID limits a deck to the
'      entities in that group, and that governs equations exactly as it governs
'      elements: every node an equation references must be in the group.
'
' This tool does not reason about any of that. It writes real decks and counts
' the MPC cards in them:
'
'   PROBE A - whole model, BCSet[1] set        -> do the equations export AT ALL?
'   PROBE B - filtered to a group you pick     -> does the group filter drop them?
'
' Comparing the two counts localises the failure to one gate:
'
'   A = 0, B = 0    the equations never export. Gate 1 or 2 - check the set
'                   report above the probes, it lists every constraint set and
'                   how many equations are actually in each.
'   A > 0, B = 0    the equations export fine; the GROUP is the problem. The
'                   group is missing at least one node that the equations
'                   reference. The per-equation node list says which.
'   A > 0, B > 0    they export in both. Whatever is wrong is downstream of
'                   Femap - the tool consuming the deck, or the master deck's
'                   case control not selecting the MPC set.
'
' NOTHING IN THE MODEL IS MODIFIED. The probe analysis set is created and then
' deleted again; the two .bdf files are the only output.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long

    ' ============================================================
    ' Section 1: Where do the equations actually live?
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Check MPC Export")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

    Dim activeBC As Long
    activeBC = App.Info_ActiveID(FT_BC_DIR)
    App.feAppMessage(FCM_NORMAL, "  Active constraint set:  " + Trim$(Str$(activeBC)))

    Dim bsEnum As Object
    Set bsEnum = App.feBCSet
    Dim eq As Object
    Set eq = App.feBCEqn

    Dim setIDs() As Long, setNames() As String, setEqn() As Long
    Dim nSets As Long
    ReDim setIDs(63)
    ReDim setNames(63)
    ReDim setEqn(63)
    nSets = 0

    Dim totalEqn As Long
    totalEqn = 0

    bsEnum.Reset
    Do While bsEnum.Next()
        If nSets <= 63 Then
            setIDs(nSets) = bsEnum.ID
            setNames(nSets) = bsEnum.title
            ' CountSet is scoped to SetID, and means nothing until it is set.
            eq.SetID = bsEnum.ID
            setEqn(nSets) = eq.CountSet()
            totalEqn = totalEqn + setEqn(nSets)
            nSets = nSets + 1
        End If
    Loop

    If nSets = 0 Then
        App.feAppMessage(FCM_ERROR, "  No constraint sets in the model - nothing to export")
        Exit Sub
    End If

    App.feAppMessage(FCM_HIGHLIGHT, "  ----------------------------------------")
    App.feAppMessage(FCM_HIGHLIGHT, "  Set   Equations   Title")
    For i = 0 To nSets - 1
        App.feAppMessage(FCM_NORMAL, "  " + PadTo(Trim$(Str$(setIDs(i))), 6) _
            + PadTo(Trim$(Str$(setEqn(i))), 12) + setNames(i))
    Next i
    App.feAppMessage(FCM_HIGHLIGHT, "  ----------------------------------------")

    If totalEqn = 0 Then
        App.feAppMessage(FCM_ERROR, "  NO CONSTRAINT EQUATIONS EXIST IN ANY SET.")
        App.feAppMessage(FCM_ERROR, "  Nothing can export them. This is gate 1 - the")
        App.feAppMessage(FCM_ERROR, "  equations were never created, or were created")
        App.feAppMessage(FCM_ERROR, "  into a set that has since been deleted.")
        Exit Sub
    End If

    ' --- which set to probe with ---
    Dim pickNames() As String
    ReDim pickNames(nSets - 1)
    For i = 0 To nSets - 1
        pickNames(i) = Trim$(Str$(setIDs(i))) + " - " + Trim$(Str$(setEqn(i))) _
            + " eqn - " + setNames(i)
    Next i

    Dim defSet As Long
    defSet = 0
    For i = 0 To nSets - 1
        If setEqn(i) > 0 Then
            defSet = i
            Exit For
        End If
    Next i

    Begin Dialog SetDlg 420, 130, "Check MPC Export"
        Text 12, 10, 396, 12, "Which constraint set should the probe decks select?"
        DropListBox 12, 30, 396, 140, pickNames(), .setPick
        Text 12, 58, 396, 12, "Two decks are written. Nothing in the model is changed."
        OKButton     114, 92, 90, 24
        CancelButton 224, 92, 90, 24
    End Dialog

    Dim sdlg As SetDlg
    sdlg.setPick = defSet
    If Dialog(sdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim probeSet As Long
    probeSet = setIDs(sdlg.setPick)

    ' --- what nodes do those equations reference? ---
    ' Printed because when the group filter is the culprit, this is the list you
    ' check the group against. IDs run 1..N inside a set.
    App.feAppMessage(FCM_HIGHLIGHT, "  Equations in set " + Trim$(Str$(probeSet)) + ":")

    Dim shown As Long
    Dim nodesSeen As String
    shown = 0
    nodesSeen = ""

    Dim defID As Long, nTerm As Long, eColor As Long, eLayer As Long
    Dim vNode As Variant, vDof As Variant, vCoef As Variant
    Dim lineStr As String

    eq.SetID = probeSet
    For i = 1 To setEqn(sdlg.setPick)
        If eq.GetAll(i, probeSet, defID, nTerm, vNode, vDof, vCoef, eColor, eLayer) = FE_OK Then
            lineStr = ""
            For j = 0 To nTerm - 1
                If Len(lineStr) > 0 Then lineStr = lineStr + "  "
                lineStr = lineStr + Trim$(Str$(CLng(vNode(j)))) + ":" _
                    + Trim$(Str$(CLng(vDof(j))))
                If InStr(nodesSeen, " " + Trim$(Str$(CLng(vNode(j)))) + " ") = 0 Then
                    nodesSeen = nodesSeen + " " + Trim$(Str$(CLng(vNode(j)))) + " "
                End If
            Next j
            If shown < 12 Then
                App.feAppMessage(FCM_NORMAL, "    eqn " + PadTo(Trim$(Str$(i)), 5) _
                    + "node:dof  " + lineStr)
                shown = shown + 1
            End If
        End If
    Next i
    If setEqn(sdlg.setPick) > 12 Then
        App.feAppMessage(FCM_NORMAL, "    ... " + Trim$(Str$(setEqn(sdlg.setPick) - 12)) _
            + " more not listed")
    End If

    ' ============================================================
    ' Section 2: Pick a group for the filtered probe
    ' ============================================================
    Dim grSet As femap.Set
    Set grSet = App.feSet
    ' Parameter 3 is an OUT param. Passing a literal 0 for it is a type
    ' mismatch - there is nothing for Femap to write the picked ID back into.
    Dim pickedGrp As Long
    pickedGrp = 0
    rc = grSet.SelectID(FT_GROUP, "Group to test the group filter against", pickedGrp)
    Dim probeGroup As Long
    probeGroup = 0
    If rc = FE_OK Then
        probeGroup = pickedGrp
    End If

    If probeGroup <= 0 Then
        App.feAppMessage(FCM_WARNING, "  No group picked - only the whole-model probe will run")
    End If

    ' ============================================================
    ' Section 3: Write the probe decks and count the MPC cards
    ' ============================================================
    Dim baseName As String
    rc = App.feFileGetName("Where to write the two probe decks", "Nastran BDF", "*.bdf", False, baseName)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim fileA As String, fileB As String
    fileA = baseName + ".probeA_wholemodel.bdf"
    fileB = baseName + ".probeB_group.bdf"

    Dim sao As femap.AnalysisMgr
    Set sao = App.feAnalysisMgr
    Dim saoID As Long
    saoID = sao.NextEmptyID
    sao.title = "MPC export probe"
    sao.Solver = 36
    sao.AnalysisType = 2
    ' The slot under test. [0] is Constraints, [1] is Constraint Equations.
    sao.BCSet(1) = probeSet

    Dim countA As Long, countB As Long
    countA = -1
    countB = -1

    ' --- PROBE A: whole model ---
    sao.NasBulkOn = True
    sao.NasBulkGroupID = 0          ' 0 = entire model
    If sao.Put(saoID) = FE_OK Then
        sao.Active = saoID
        If App.feFileWriteNastran(8, fileA) = FE_OK Then
            countA = CountMPC(fileA)
        Else
            App.feAppMessage(FCM_ERROR, "  Probe A: the Nastran write failed")
        End If
    Else
        App.feAppMessage(FCM_ERROR, "  Probe A: could not create the probe analysis set")
    End If

    ' --- PROBE B: filtered to the picked group ---
    If probeGroup > 0 Then
        sao.NasBulkOn = True
        sao.NasBulkGroupID = probeGroup
        If sao.Put(saoID) = FE_OK Then
            sao.Active = saoID
            If App.feFileWriteNastran(8, fileB) = FE_OK Then
                countB = CountMPC(fileB)
            Else
                App.feAppMessage(FCM_ERROR, "  Probe B: the Nastran write failed")
            End If
        End If
    End If

    If sao.Deletable(saoID) Then sao.Delete(saoID)

    ' ============================================================
    ' Section 4: Verdict
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Probe results")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Equations in set " + Trim$(Str$(probeSet)) + ":   " _
        + Trim$(Str$(setEqn(sdlg.setPick))))
    App.feAppMessage(FCM_NORMAL, "  A whole model  MPC cards: " + Trim$(Str$(countA)))
    If probeGroup > 0 Then
        App.feAppMessage(FCM_NORMAL, "  B group " + PadTo(Trim$(Str$(probeGroup)), 7) _
            + "MPC cards: " + Trim$(Str$(countB)))
    End If
    App.feAppMessage(FCM_NORMAL, "  A: " + fileA)
    If probeGroup > 0 Then App.feAppMessage(FCM_NORMAL, "  B: " + fileB)

    App.feAppMessage(FCM_HIGHLIGHT, "  ----------------------------------------")
    If countA = 0 Then
        App.feAppMessage(FCM_ERROR,   "  THE EQUATIONS DO NOT EXPORT AT ALL.")
        App.feAppMessage(FCM_ERROR,   "  Not the group filter - an unfiltered whole-model")
        App.feAppMessage(FCM_ERROR,   "  deck with BCSet[1] set still has no MPC cards.")
        App.feAppMessage(FCM_ERROR,   "  Suspect the equations are in a different set than")
        App.feAppMessage(FCM_ERROR,   "  the one probed, or BCSet[1] is not the mechanism")
        App.feAppMessage(FCM_ERROR,   "  on this Femap build. Open probe A and look.")
    ElseIf countA > 0 And probeGroup > 0 And countB = 0 Then
        App.feAppMessage(FCM_WARNING, "  THE GROUP FILTER IS DROPPING THEM.")
        App.feAppMessage(FCM_WARNING, "  They export whole-model but not for this group.")
        App.feAppMessage(FCM_WARNING, "  Every node listed above must be IN the group.")
        App.feAppMessage(FCM_WARNING, "  Add the missing ones and re-run.")
    ElseIf countA > 0 And countB > 0 Then
        App.feAppMessage(FCM_NORMAL,  "  BOTH DECKS CARRY MPC CARDS.")
        App.feAppMessage(FCM_NORMAL,  "  Export is working. Anything still missing is")
        App.feAppMessage(FCM_NORMAL,  "  downstream: the master deck's case control must")
        App.feAppMessage(FCM_NORMAL,  "  select this MPC set for the subcase to use it.")
    ElseIf countA > 0 Then
        App.feAppMessage(FCM_NORMAL,  "  Whole-model export works. Re-run and pick a group")
        App.feAppMessage(FCM_NORMAL,  "  to test the group filter as well.")
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

End Sub


' -----------------------------------------------------------------------------
' Count MPC / MPCADD cards in a written deck.
'
' Counts CARD lines only - a continuation is indented or starts with a
' continuation marker, and a comment starts with "$", so neither is counted as
' a card. The number is a signal, not an inventory: what matters is whether it
' is zero.
' -----------------------------------------------------------------------------
Function CountMPC(path As String) As Long

    Dim fso As Object
    Dim rd As Object
    Dim ln As String
    Dim n As Long
    Dim head As String

    n = 0
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FileExists(path) Then
        CountMPC = -1
        Exit Function
    End If

    Set rd = fso.OpenTextFile(path, 1)
    Do While Not rd.AtEndOfStream
        ln = rd.ReadLine
        If Len(ln) > 0 Then
            If Left(ln, 1) <> "$" And Left(ln, 1) <> " " And Left(ln, 1) <> "+" _
                And Left(ln, 1) <> "*" Then
                head = UCase(Trim(Left(ln, 8)))
                If Left(head, 1) = "M" Then
                    If head = "MPC" Or head = "MPC*" Or head = "MPCADD" Or head = "MPCADD*" Then
                        n = n + 1
                    End If
                End If
            End If
        End If
    Loop
    rd.Close

    CountMPC = n

End Function


' -----------------------------------------------------------------------------
' Right-pad to a column. The Messages window is fixed-pitch, so this lines the
' report tables up.
' -----------------------------------------------------------------------------
Function PadTo(s As String, n As Long) As String

    Dim out As String
    out = s
    Do While Len(out) < n
        out = out + " "
    Loop
    PadTo = out

End Function
