' Relative Displacement MPC.bas
' -----------------------------------------------------------------------------
' Instrument the RELATIVE displacement between two grids so it comes straight out
' of the solve as an output quantity - no hand-subtracting two result vectors,
' and it works in statics, normal modes and frequency response alike.
'
' Pick node A and node B. The tool creates one new grid - the MEASUREMENT NODE -
' and writes one MPC constraint equation per direction you asked for:
'
'     1.0*u_M(dof)  -  1.0*u_A(dof)  +  1.0*u_B(dof)  =  0
'
' which rearranges to  u_M = u_A - u_B.  After the solve, the measurement node's
' T1/T2/T3 ARE the relative displacement, read directly off the node.
'
' *** THE SIGN CONVENTION IS A MINUS B ***
' Node A is the one you are measuring FROM. Swap the picks and every number
' changes sign. The confirm dialog restates this on every pair, because it is
' the single easiest thing to get backwards and it is invisible in the results.
'
' WHY A GRID NODE AND NOT A SPOINT
' A scalar point has only DOF 1, so three of them are needed for three
' directions, and each reading then lives in some SPOINT's T1 column - which
' means the answer is only interpretable next to a lookup table mapping SPOINT
' to direction. A grid node carries all three at once, in the directions they
' are named: T1 is X, T2 is Y, T3 is Z. One node per pair, and the result
' explains itself to somebody who did not run the tool.
'
' *** THE MEASUREMENT NODE HAS SINGULAR DOFS AND RELIES ON PARAM,AUTOSPC ***
' The measurement node carries no elements and no mass. Its three rotations -
' and any translation you did NOT instrument - are attached to nothing and are
' singular. They are left for PARAM,AUTOSPC to pick up. If AUTOSPC is off in
' your deck the run will fail on a singularity at this node, and the summary
' reprints that warning on every run that writes anything.
'
' THE OUTPUT COORDINATE SYSTEM IS THE WHOLE BALL GAME
' A nodal DOF is expressed in that node's OUTPUT coordinate system, not in
' global. So "u_A(T1) - u_B(T1)" is only a physically meaningful subtraction if
' A and B share one output CSys - otherwise it silently subtracts a displacement
' along one direction from a displacement along a different one and returns a
' plausible-looking number that means nothing.
'
' The tool therefore GATES on it: A and B must have the same outCSys, and that
' system must be RECTANGULAR. The measurement node is then created with the same
' outCSys, so all three nodes agree.
'
' Cylindrical and spherical systems are rejected rather than handled. Their
' directions are position-dependent - the radial direction at A does not point
' the same way as the radial direction at B, even though both nodes name the
' same CSys ID - so the subtraction mixes directions. That is a real analysis
' question, not a coding one, and guessing at it here would be worse than
' refusing.
'
' *** WHICH TERM IS THE DEPENDENT ONE IS NOT DOCUMENTED ***
' api.pdf specifies every argument of BCEqn.PutAll except this. Nastran
' convention is that the FIRST term of an MPC is the dependent DOF, and that is
' what the term order below assumes - the measurement node is written first.
' The three terms are built in ONE place (Section 3) precisely so that if a BDF
' export ever shows Femap reordering them, the fix is one block, not a hunt.
'
' Verify it the same way everything else in this toolset gets verified: export
' the deck and read the MPC card.
'
' NOTHING IS MODIFIED UNTIL THE CONFIRM DIALOG, and "Report only" mode skips
' every write - use it to check the gate and the pairing without touching the
' model.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long, d As Long

    ' The User Graphics set the confirm arrows live in. High, so it does not
    ' collide with a set the user is already using for their own graphics.
    Dim GFX_SET As Long
    GFX_SET = 991

    Dim MAXPAIRS As Long
    MAXPAIRS = 500

    ' ============================================================
    ' Section 1: Options
    '
    ' Asked once and reused for every pair - the loop below re-prompts only for
    ' the node picks, so a run of a dozen joints is a dozen pairs of clicks.
    ' ============================================================

    ' --- constraint sets (prepend a "create new" sentinel) ---
    ' Declared As Object: these are only ever walked as enumerators, and the
    ' typed declarations are the flaky ones in this toolset.
    Dim bsEnum As Object
    Set bsEnum = App.feBCSet
    Dim bsCount As Long
    bsCount = 0
    bsEnum.Reset
    Do While bsEnum.Next()
        bsCount = bsCount + 1
    Loop

    Dim setIDs() As Long, setNames() As String
    ReDim setIDs(bsCount)
    ReDim setNames(bsCount)
    setIDs(0) = -1
    setNames(0) = "(create new constraint set)"
    Dim si As Long
    si = 1
    bsEnum.Reset
    Do While bsEnum.Next()
        setIDs(si) = bsEnum.ID
        setNames(si) = Trim$(Str$(bsEnum.ID)) + " - " + bsEnum.title
        si = si + 1
    Loop

    Begin Dialog OptDlg 400, 268, "Relative Displacement MPC"
        GroupBox 12, 8, 376, 80, "Directions to measure"
        CheckBox 24, 26, 352, 14, "T1  - first axis of the shared output CSys", .chkT1
        CheckBox 24, 46, 352, 14, "T2  - second axis", .chkT2
        CheckBox 24, 66, 352, 14, "T3  - third axis", .chkT3
        Text     12, 100, 124, 12, "Equations go in:"
        DropListBox 140, 98, 248, 120, setNames(), .setPick
        Text     12, 126, 376, 12, "Sign convention: the new node reads node A MINUS node B."
        CheckBox 12, 148, 376, 14, "Show orientation arrows at both nodes before creating", .chkArrows
        CheckBox 12, 168, 376, 14, "Report only - change nothing", .chkDry
        Text     12, 192, 376, 12, "The new node's rotations are left to PARAM,AUTOSPC."
        OKButton     104, 226, 90, 24
        CancelButton 214, 226, 90, 24
    End Dialog

    Dim dlg As OptDlg
    dlg.chkT1 = 1
    dlg.chkT2 = 1
    dlg.chkT3 = 1
    dlg.setPick = 0
    dlg.chkArrows = 1
    dlg.chkDry = 0
    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim wantDof(2) As Boolean
    wantDof(0) = (dlg.chkT1 <> 0)
    wantDof(1) = (dlg.chkT2 <> 0)
    wantDof(2) = (dlg.chkT3 <> 0)

    Dim nDof As Long
    nDof = 0
    For i = 0 To 2
        If wantDof(i) Then nDof = nDof + 1
    Next i
    If nDof = 0 Then
        App.feAppMessage(FCM_ERROR, "No directions selected - nothing to measure, exiting")
        Exit Sub
    End If

    Dim dofStr As String
    dofStr = ""
    For i = 0 To 2
        If wantDof(i) Then
            If Len(dofStr) > 0 Then dofStr = dofStr + " "
            dofStr = dofStr + "T" + Trim$(Str$(i + 1))
        End If
    Next i

    Dim showArrows As Boolean, dryRun As Boolean
    showArrows = (dlg.chkArrows <> 0)
    dryRun = (dlg.chkDry <> 0)

    ' The constraint set is resolved but NOT created here - a new set is made
    ' lazily on the first pair that actually writes, so cancelling out of every
    ' confirm (or a Report-only run) leaves no empty set behind.
    Dim bcSetID As Long
    Dim makeNewSet As Boolean
    makeNewSet = (setIDs(dlg.setPick) = -1)
    If makeNewSet Then
        bcSetID = 0
    Else
        bcSetID = setIDs(dlg.setPick)
    End If

    ' ============================================================
    ' Section 2: The pair loop
    '
    ' Runs until the node-A pick is cancelled. Each pair is committed as it is
    ' confirmed, so quitting mid-run keeps everything already created.
    ' ============================================================
    Dim ndA As femap.Node
    Set ndA = App.feNode
    Dim ndB As femap.Node
    Set ndB = App.feNode
    Dim ndM As femap.Node
    Set ndM = App.feNode
    Dim cs As femap.CSys
    Set cs = App.feCSys
    Dim eq As Object
    Set eq = App.feBCEqn

    Dim recM() As Long, recA() As Long, recB() As Long, recCS() As Long
    ReDim recM(MAXPAIRS - 1)
    ReDim recA(MAXPAIRS - 1)
    ReDim recB(MAXPAIRS - 1)
    ReDim recCS(MAXPAIRS - 1)

    Dim nPairs As Long, nSkipped As Long, nEqn As Long, nFail As Long
    Dim nCoincident As Long
    nPairs = 0 : nSkipped = 0 : nEqn = 0 : nFail = 0 : nCoincident = 0

    Dim aID As Long, bID As Long, mID As Long
    Dim aX As Double, aY As Double, aZ As Double
    Dim bX As Double, bY As Double, bZ As Double
    Dim aOut As Long, bOut As Long
    Dim csType As Long, csName As String
    Dim sep As Double
    Dim eqID As Long
    Dim arrowsOK As Boolean
    arrowsOK = showArrows

    ' The three terms of one equation. Built once per DOF in Section 3.
    Dim eNode(2) As Long
    Dim eDof(2) As Long
    Dim eCoef(2) As Double
    Dim vN As Variant, vD As Variant, vC As Variant

    Dim cLine1 As String, cLine2 As String, cLine3 As String
    Dim cLine4 As String, cLine5 As String

    Do
        ' --- pick A, then B ---
        ' SelectID loads the node straight into the object, so every value is
        ' read out immediately: any later call on the same object overwrites it.
        rc = ndA.SelectID("Pick node A - measured FROM  (Cancel to finish)")
        If rc <> FE_OK Then Exit Do
        aID = ndA.ID
        aX = ndA.x : aY = ndA.y : aZ = ndA.z
        aOut = ndA.outCSys

        rc = ndB.SelectID("Pick node B - measured TO")
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Node B pick cancelled - pair skipped")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If
        bID = ndB.ID
        bX = ndB.x : bY = ndB.y : bZ = ndB.z
        bOut = ndB.outCSys

        If aID = bID Then
            App.feAppMessage(FCM_WARNING, "Node " + Trim$(Str$(aID)) _
                + " picked twice - a node cannot be measured against itself, pair skipped")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If

        ' --- gate: shared, rectangular output CSys ---
        If aOut <> bOut Then
            App.feAppMessage(FCM_WARNING, "Nodes " + Trim$(Str$(aID)) + " and " _
                + Trim$(Str$(bID)) + " have different output CSys (" _
                + Trim$(Str$(aOut)) + " vs " + Trim$(Str$(bOut)) + ") - pair skipped")
            App.feAppMessage(FCM_NORMAL, "      Their T1/T2/T3 point in different directions," _
                + " so the subtraction would be meaningless.")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If

        ' CSys 0/1/2 are the predefined globals and cannot be Get - and they are
        ' 0=Rectangular, 1=Cylindrical, 2=Spherical, so the ID IS the type.
        If aOut <= 2 Then
            csType = aOut
            If aOut = 0 Then
                csName = "0 - Global Rectangular"
            ElseIf aOut = 1 Then
                csName = "1 - Global Cylindrical"
            Else
                csName = "2 - Global Spherical"
            End If
        Else
            If cs.Get(aOut) <> FE_OK Then
                App.feAppMessage(FCM_WARNING, "Could not read CSys " + Trim$(Str$(aOut)) _
                    + " - pair skipped")
                nSkipped = nSkipped + 1
                GoTo NextPair
            End If
            csType = cs.type
            csName = Trim$(Str$(aOut)) + " - " + cs.title
        End If

        If csType <> 0 Then
            App.feAppMessage(FCM_WARNING, "Output CSys " + csName _
                + " is not rectangular - pair " + Trim$(Str$(aID)) + "/" _
                + Trim$(Str$(bID)) + " skipped")
            App.feAppMessage(FCM_NORMAL, "      Radial and theta directions depend on position," _
                + " so they differ at A and at B.")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If

        sep = Sqr((aX - bX) * (aX - bX) + (aY - bY) * (aY - bY) + (aZ - bZ) * (aZ - bZ))

        ' --- confirm ---
        If arrowsOK Then
            If ShowTriads(App, GFX_SET, aOut, aX, aY, aZ, bX, bY, bZ) <> FE_OK Then
                App.feAppMessage(FCM_WARNING, "User Graphics arrows unavailable on this build" _
                    + " - continuing with the text confirm only")
                arrowsOK = False
            End If
        End If

        cLine1 = "A (from):  node " + Trim$(Str$(aID)) + "    " + PtStr(aX, aY, aZ)
        cLine2 = "B (to):    node " + Trim$(Str$(bID)) + "    " + PtStr(bX, bY, bZ)
        cLine3 = "Output CSys:  " + csName + "   (rectangular)"
        cLine4 = "Measuring:  " + dofStr + "     as  A minus B"
        If arrowsOK Then
            cLine5 = "Arrows at both nodes:  red = first axis, green = second, blue = third."
        Else
            cLine5 = "Separation:  " + Format$(sep, "0.####")
        End If

        Begin Dialog ConfirmDlg 400, 190, "Relative Displacement MPC - Confirm"
            Text 12, 10, 376, 12, cLine1
            Text 12, 28, 376, 12, cLine2
            Text 12, 46, 376, 12, cLine3
            Text 12, 64, 376, 12, cLine4
            Text 12, 82, 376, 12, cLine5
            Text 12, 108, 376, 12, "OK creates one node and one equation per direction."
            OKButton     104, 148, 90, 24
            CancelButton 214, 148, 90, 24
        End Dialog

        Dim cdlg As ConfirmDlg
        Dim confirmed As Long
        confirmed = Dialog(cdlg)

        ' Cleared on showArrows, not arrowsOK: if ShowTriads got some arrows
        ' down before failing it turned arrowsOK off, and those would be left
        ' on screen. ClearTriads is harmless when nothing was drawn.
        If showArrows Then ClearTriads App, GFX_SET

        If confirmed <> -1 Then
            App.feAppMessage(FCM_WARNING, "Pair " + Trim$(Str$(aID)) + "/" + Trim$(Str$(bID)) _
                + " cancelled - nothing created")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If

        If dryRun Then
            App.feAppMessage(FCM_NORMAL, "  [report only] would measure node " _
                + Trim$(Str$(aID)) + " minus node " + Trim$(Str$(bID)) _
                + "   " + dofStr + "   CSys " + Trim$(Str$(aOut)))
            nPairs = nPairs + 1
            GoTo NextPair
        End If

        If nPairs >= MAXPAIRS Then
            App.feAppMessage(FCM_ERROR, "Reached the " + Trim$(Str$(MAXPAIRS)) _
                + " pair limit for one run - stopping")
            Exit Do
        End If

        ' ============================================================
        ' Section 3: Create
        ' ============================================================

        ' --- the constraint set, made on demand ---
        If makeNewSet And bcSetID = 0 Then
            Dim bsNew As Object
            Set bsNew = App.feBCSet
            bcSetID = bsNew.NextEmptyID
            bsNew.title = "Relative Displacement"
            If bsNew.Put(bcSetID) <> FE_OK Then
                App.feAppMessage(FCM_ERROR, "Could not create the constraint set - exiting")
                Exit Sub
            End If
            App.feAppMessage(FCM_NORMAL, "Created constraint set " + Trim$(Str$(bcSetID)) _
                + " - Relative Displacement")
        End If

        ' --- the measurement node, at the midpoint ---
        ' Node coordinates are always global rectangular, so a plain average is
        ' the midpoint regardless of what CSys anything is defined in.
        mID = ndM.NextEmptyID
        ndM.x = 0.5 * (aX + bX)
        ndM.y = 0.5 * (aY + bY)
        ndM.z = 0.5 * (aZ + bZ)
        ndM.type = 0
        ndM.defCSys = 0
        ' The one property that makes the equation mean what it says: the
        ' measurement node must report in the SAME system as A and B.
        ndM.outCSys = aOut
        ndM.layer = ndA.layer
        If ndM.Put(mID) <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Could not create the measurement node for pair " _
                + Trim$(Str$(aID)) + "/" + Trim$(Str$(bID)) + " - pair skipped")
            nFail = nFail + 1
            GoTo NextPair
        End If

        If sep <= 0.0 Then nCoincident = nCoincident + 1

        ' --- one equation per requested direction ---
        Dim madeHere As Long
        madeHere = 0
        For d = 0 To 2
            If wantDof(d) Then
                ' *** TERM ORDER. The measurement node is written FIRST because
                ' *** the first term of an MPC is the dependent DOF. api.pdf
                ' *** does not state this - see the header. If a BDF export ever
                ' *** shows otherwise, this is the block to change.
                eNode(0) = mID : eDof(0) = d + 1 : eCoef(0) = 1.0
                eNode(1) = aID : eDof(1) = d + 1 : eCoef(1) = -1.0
                eNode(2) = bID : eDof(2) = d + 1 : eCoef(2) = 1.0
                ' BCEqn dof is 1-based (1..6). BCNode dof is 0-based. Do not
                ' carry an index between the two.

                vN = eNode
                vD = eDof
                vC = eCoef

                eqID = FreeEqnID(eq, bcSetID)
                rc = eq.PutAll(eqID, bcSetID, 0, 3, vN, vD, vC, FCL_GREEN, 1)
                If rc <> FE_OK Then
                    App.feAppMessage(FCM_ERROR, "  Equation for T" + Trim$(Str$(d + 1)) _
                        + " on pair " + Trim$(Str$(aID)) + "/" + Trim$(Str$(bID)) _
                        + " failed (rc=" + Trim$(Str$(rc)) + ")")
                    nFail = nFail + 1
                Else
                    nEqn = nEqn + 1
                    madeHere = madeHere + 1
                End If
            End If
        Next d

        If madeHere = 0 Then
            App.feAppMessage(FCM_ERROR, "  No equations written for pair " + Trim$(Str$(aID)) _
                + "/" + Trim$(Str$(bID)) + " - the measurement node is orphaned")
            GoTo NextPair
        End If

        ' --- bookkeeping group ---
        ' Femap nodes have no title, so this group is the only PERSISTENT record
        ' of what node mID measures. Without it the mapping lives solely in the
        ' Messages window and is gone as soon as that scrolls.
        MakeRelDispGroup App, mID, aID, bID

        recM(nPairs) = mID
        recA(nPairs) = aID
        recB(nPairs) = bID
        recCS(nPairs) = aOut
        nPairs = nPairs + 1

        App.feAppMessage(FCM_NORMAL, "  node " + Trim$(Str$(mID)) + "  =  " _
            + Trim$(Str$(aID)) + " - " + Trim$(Str$(bID)) + "   " + dofStr)

NextPair:
    Loop

    ' Belt and braces: if the user broke out of the loop while arrows were up,
    ' the graphics must not be left on screen.
    If showArrows Then ClearTriads App, GFX_SET

    ' ============================================================
    ' Section 4: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Relative Displacement MPC - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

    If dryRun Then
        App.feAppMessage(FCM_WARNING, "  REPORT ONLY - nothing was created")
        App.feAppMessage(FCM_NORMAL,  "  Pairs that would be built:" + Str$(nPairs))
    Else
        App.feAppMessage(FCM_NORMAL,  "  Pairs instrumented:    " + Trim$(Str$(nPairs)))
        App.feAppMessage(FCM_NORMAL,  "  Equations written:     " + Trim$(Str$(nEqn)))
        If nPairs > 0 Then
            App.feAppMessage(FCM_NORMAL, "  Constraint set:        " + Trim$(Str$(bcSetID)))
        End If
    End If
    App.feAppMessage(FCM_NORMAL,      "  Directions:            " + dofStr)

    If nSkipped > 0 Then
        App.feAppMessage(FCM_WARNING, "  Pairs skipped:         " + Trim$(Str$(nSkipped)))
    End If
    If nFail > 0 Then
        App.feAppMessage(FCM_ERROR,   "  FAILED writes:         " + Trim$(Str$(nFail)))
    End If

    If nPairs > 0 And Not dryRun Then
        App.feAppMessage(FCM_HIGHLIGHT, "  ----------------------------------------")
        App.feAppMessage(FCM_HIGHLIGHT, "  Node    reads                  CSys")
        For i = 0 To nPairs - 1
            App.feAppMessage(FCM_NORMAL, "  " + PadTo(Trim$(Str$(recM(i))), 8) _
                + PadTo(Trim$(Str$(recA(i))) + " - " + Trim$(Str$(recB(i))), 23) _
                + Trim$(Str$(recCS(i))))
        Next i
        App.feAppMessage(FCM_HIGHLIGHT, "  ----------------------------------------")
        App.feAppMessage(FCM_NORMAL,  "  Each is grouped as RelDisp <A>-<B>.")
        App.feAppMessage(FCM_NORMAL,  "  Sign convention: node A MINUS node B.")

        ' Not optional. A copy of this tool handed to somebody else must not let
        ' their deck fail on a singularity nobody can explain.
        App.feAppMessage(FCM_WARNING, "  The measurement nodes' rotations - and any")
        App.feAppMessage(FCM_WARNING, "  translation you did not instrument - are")
        App.feAppMessage(FCM_WARNING, "  singular. PARAM,AUTOSPC must be ON.")

        If nCoincident > 0 Then
            App.feAppMessage(FCM_WARNING, "  Coincident pairs:      " + Trim$(Str$(nCoincident)))
            App.feAppMessage(FCM_WARNING, "  Their measurement node sits ON nodes A and B.")
            App.feAppMessage(FCM_WARNING, "  A coincident-node merge would destroy it.")
        End If
    End If

    If nPairs = 0 And nSkipped = 0 Then
        App.feAppMessage(FCM_WARNING, "  Nothing picked - no changes made.")
    End If

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

End Sub


' -----------------------------------------------------------------------------
' Next free constraint-equation ID within one constraint set.
'
' BCEqn IDs run 1..N inside their set, and SetID must be assigned BEFORE
' NextEmptyID or CountSet - both are set-scoped and mean nothing without it.
' PutAll documents no duplicate-ID error, which almost certainly means it
' silently overwrites, so the candidate is proved free with a Get rather than
' trusted.
' -----------------------------------------------------------------------------
Function FreeEqnID(eq As Object, setID As Long) As Long

    eq.SetID = setID
    Dim cand As Long
    cand = eq.NextEmptyID
    If cand < 1 Then cand = 1

    Do While eq.Get(cand) = FE_OK
        cand = cand + 1
    Loop

    FreeEqnID = cand

End Function


' -----------------------------------------------------------------------------
' The per-pair bookkeeping group. Holds the measurement node and both of the
' nodes it measures, so the pair can be reconstructed from the model alone.
'
' SetAdd puts selection RULES on the in-memory group object - it does not write
' entities - so Put must come AFTER the adds, and feGroupEvaluate then
' materialises them. Put first and the group comes out empty.
' -----------------------------------------------------------------------------
Sub MakeRelDispGroup(App As Object, mID As Long, aID As Long, bID As Long)

    Dim gp As femap.Group
    Set gp = App.feGroup

    Dim ns As femap.Set
    Set ns = App.feSet
    ns.Add(mID)
    ns.Add(aID)
    ns.Add(bID)

    Dim gname As String
    gname = "RelDisp " + Trim$(Str$(aID)) + "-" + Trim$(Str$(bID))

    ' Re-run guard. There is no find-by-title method, so the whole title list is
    ' pulled and compared. This does not block anything - the second measurement
    ' node is a different node, so nothing conflicts - but two groups with the
    ' same name and two sets of equations measuring the same pair is almost
    ' certainly a mistake, and it is invisible afterwards.
    Dim cnt As Long
    Dim vIDs As Variant, vTitles As Variant
    Dim t As Long
    If gp.GetTitleList(0, 0, cnt, vIDs, vTitles) = FE_OK Then
        For t = 0 To cnt - 1
            If vTitles(t) = gname Then
                App.feAppMessage(FCM_WARNING, "  Group '" + gname _
                    + "' already exists - this pair is now instrumented twice")
                Exit For
            End If
        Next t
    End If

    Dim gID As Long
    gID = gp.NextEmptyID
    gp.title = gname

    If gp.SetAdd(FT_NODE, ns.ID) <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "  Could not populate the RelDisp group for " _
            + Trim$(Str$(aID)) + "-" + Trim$(Str$(bID)))
        Exit Sub
    End If
    If gp.Put(gID) <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "  Could not create the RelDisp group for " _
            + Trim$(Str$(aID)) + "-" + Trim$(Str$(bID)))
        Exit Sub
    End If
    App.feGroupEvaluate(-gID, True)

End Sub


' -----------------------------------------------------------------------------
' Draw a colour-coded axis triad at both nodes, in the shared output CSys.
'
' Red / green / blue = first / second / third axis. User Graphics carries no
' text, so colour is the whole legend - the confirm dialog says which is which.
'
' The axis directions come from feCoordTransform rather than from the CSys
' direction-cosine matrix: the doc does not say whether the matrix rows are the
' axes or their transpose, and a transposed triad would point confidently in the
' wrong directions. Transforming the unit points and differencing cannot be got
' backwards. It is done inline rather than in a helper because passing a fixed
' 2-D array into an arr() parameter is not reliable across Basic dialects.
' -----------------------------------------------------------------------------
Function ShowTriads(App As Object, gfxSet As Long, csysID As Long, _
                    aX As Double, aY As Double, aZ As Double, _
                    bX As Double, bY As Double, bZ As Double) As Long

    ShowTriads = FE_FAIL

    ' --- the three axis directions, in global rectangular ---
    Dim dir(2, 2) As Double
    Dim org(2) As Double
    Dim p(2) As Double
    Dim vIn As Variant, vOut As Variant
    Dim rc As Long
    Dim a As Long, k As Long

    p(0) = 0.0 : p(1) = 0.0 : p(2) = 0.0
    vIn = p
    rc = App.feCoordTransform(csysID, vIn, 0, vOut)
    If rc <> FE_OK Then Exit Function
    For k = 0 To 2
        org(k) = CDbl(vOut(k))
    Next k

    For a = 0 To 2
        p(0) = 0.0 : p(1) = 0.0 : p(2) = 0.0
        p(a) = 1.0
        vIn = p
        rc = App.feCoordTransform(csysID, vIn, 0, vOut)
        If rc <> FE_OK Then Exit Function
        For k = 0 To 2
            dir(a, k) = CDbl(vOut(k)) - org(k)
        Next k
    Next a

    ' --- six arrows: one triad at A, one at B ---
    Dim arw As Object
    Set arw = App.feGFXArrow
    arw.setID = gfxSet

    Dim cols(2) As Long
    cols(0) = FCL_RED
    cols(1) = FCL_GREEN
    cols(2) = FCL_BLUE

    Dim ax As Long
    For a = 0 To 5
        If a < 3 Then
            arw.x = aX : arw.y = aY : arw.z = aZ
        Else
            arw.x = bX : arw.y = bY : arw.z = bZ
        End If
        ax = a Mod 3
        arw.dx = dir(ax, 0)
        arw.dy = dir(ax, 1)
        arw.dz = dir(ax, 2)
        ' 1 = Scaled to view, so the triad stays visible at any model scale -
        ' and, critically, still draws when A and B are coincident and there is
        ' no separation distance to size it from.
        arw.length = 1.0
        arw.lengthmode = 1
        ' 0.0 = base of the arrow sits at the given point, so it emanates from
        ' the node instead of ending there.
        arw.location = 0.0
        arw.style = 1
        arw.color = cols(ax)
        arw.layer = 1
        If arw.Put(a + 1) <> FE_OK Then Exit Function
    Next a

    App.feGFXSelect(gfxSet, True, True)
    ShowTriads = FE_OK

End Function


' -----------------------------------------------------------------------------
' Erase the confirm triads.
'
' The order is not interchangeable and the doc is explicit about it: deleting
' the data alone leaves the graphics ON SCREEN, because display is driven by the
' selected set rather than by the data. Delete, then Reset, then regenerate.
' -----------------------------------------------------------------------------
Sub ClearTriads(App As Object, gfxSet As Long)

    App.feGFXDelete(False, gfxSet)
    App.feGFXReset()
    App.feViewRegenerate(0)

End Sub


' -----------------------------------------------------------------------------
' A point as a short bracketed string for the confirm dialog.
' -----------------------------------------------------------------------------
Function PtStr(x As Double, y As Double, z As Double) As String

    PtStr = "(" + Format$(x, "0.###") + ", " + Format$(y, "0.###") _
        + ", " + Format$(z, "0.###") + ")"

End Function


' -----------------------------------------------------------------------------
' Right-pad to a column. The Messages window is fixed-pitch, so this lines the
' summary table up - unlike a dialog, where padding does nothing.
' -----------------------------------------------------------------------------
Function PadTo(s As String, n As Long) As String

    Dim out As String
    out = s
    Do While Len(out) < n
        out = out + " "
    Loop
    PadTo = out

End Function
