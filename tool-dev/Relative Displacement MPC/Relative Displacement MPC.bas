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
' The tool therefore GATES on it: both output systems must be RECTANGULAR and
' must have the same ORIENTATION. Note orientation, not ID - two systems with
' different IDs and different origins but parallel axes resolve T1/T2/T3 along
' the same physical directions, so subtracting them is valid and the pair is
' accepted. A DOF direction depends on how a system is turned, not where it
' sits. The measurement node then takes node A's outCSys.
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

    ' --- coordinate systems for the tracking node ---
    ' Entry 0 is the sentinel that follows the picked nodes; entry 1 is global
    ' rectangular; then every user CSys.
    Dim csEnum As Object
    Set csEnum = App.feCSys
    Dim csUser As Long
    csUser = 0
    csEnum.Reset
    Do While csEnum.Next()
        csUser = csUser + 1
    Loop

    Dim csIDs() As Long, csNames() As String
    ReDim csIDs(csUser + 1)
    ReDim csNames(csUser + 1)
    csIDs(0) = -1
    csNames(0) = "(same as the picked nodes)"
    csIDs(1) = 0
    csNames(1) = "0 - Global Rectangular"
    Dim cj As Long
    cj = 2
    csEnum.Reset
    Do While csEnum.Next()
        csIDs(cj) = csEnum.ID
        csNames(cj) = Trim$(Str$(csEnum.ID)) + " - " + csEnum.title
        cj = cj + 1
    Loop

    ' Default the dropdown to the ACTIVE constraint set rather than to the
    ' create-new sentinel. A brand new set is the option most likely to produce
    ' a deck with no MPC cards in it: the analysis case selects constraint
    ' equations through its OWN slot (AnalysisCase.BCSet[1]), separately from
    ' constraints in BCSet[0], and a set that did not exist when the case was
    ' set up is not in that slot. See the summary note at the end.
    Dim activeBC As Long
    activeBC = App.Info_ActiveID(FT_BC_DIR)
    Dim defPick As Long
    defPick = 0
    If activeBC > 0 Then
        For i = 1 To bsCount
            If setIDs(i) = activeBC Then defPick = i
        Next i
    End If

    Begin Dialog OptDlg 400, 232, "Relative Displacement MPC"
        GroupBox 12, 8, 376, 46, "Directions to measure"
        CheckBox  28, 28, 56, 14, "T1", .chkT1
        CheckBox 100, 28, 56, 14, "T2", .chkT2
        CheckBox 172, 28, 56, 14, "T3", .chkT3
        Text     12, 70, 176, 12, "MPC equations go in:"
        DropListBox 192, 68, 196, 120, setNames(), .setPick
        Text     12, 96, 176, 12, "Tracking node output CSys:"
        DropListBox 192, 94, 196, 120, csNames(), .csPick
        CheckBox 12, 124, 376, 14, "Show orientation arrows at both nodes before creating", .chkArrows
        CheckBox 12, 144, 376, 14, "Report only - change nothing", .chkDry
        Text     12, 168, 376, 12, "Cancel the node A pick to finish."
        OKButton     104, 192, 90, 24
        CancelButton 214, 192, 90, 24
    End Dialog

    Dim dlg As OptDlg
    dlg.chkT1 = 1
    dlg.chkT2 = 1
    dlg.chkT3 = 1
    dlg.setPick = defPick
    dlg.csPick = 0
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

    ' -1 = follow the picked nodes. Anything else is an explicit override, and
    ' see the warning in Section 2 for what that does and does not do.
    Dim wantOutCS As Long
    wantOutCS = csIDs(dlg.csPick)

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
    Dim eq As Object
    Set eq = App.feBCEqn

    Dim recM() As Long, recA() As Long, recB() As Long, recCS() As Long
    ReDim recM(MAXPAIRS - 1)
    ReDim recA(MAXPAIRS - 1)
    ReDim recB(MAXPAIRS - 1)
    ReDim recCS(MAXPAIRS - 1)

    Dim nPairs As Long, nSkipped As Long, nEqn As Long, nFail As Long
    Dim nCoincident As Long, nMismatch As Long
    nPairs = 0 : nSkipped = 0 : nEqn = 0 : nFail = 0
    nCoincident = 0 : nMismatch = 0

    Dim aID As Long, bID As Long, mID As Long
    Dim aX As Double, aY As Double, aZ As Double
    Dim bX As Double, bY As Double, bZ As Double
    Dim aOut As Long, bOut As Long
    Dim csName As String
    Dim aType As Long, bType As Long
    Dim aCSName As String, bCSName As String
    Dim align As Long
    Dim mOut As Long
    Dim csMismatch As Boolean
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
    Dim cLine4 As String, cLine5 As String, cLine6 As String

    Do
        ' --- pick A, then B ---
        ' SelectID loads the node straight into the object, so every value is
        ' read out immediately: any later call on the same object overwrites it.
        rc = ndA.SelectID("Pick node A (measured FROM)")
        If rc <> FE_OK Then Exit Do
        aID = ndA.ID
        aX = ndA.x : aY = ndA.y : aZ = ndA.z
        aOut = ndA.outCSys

        rc = ndB.SelectID("Pick node B (measured TO)")
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

        ' --- gate: rectangular output CSys, ALIGNED between the two nodes ---
        '
        ' What matters is ORIENTATION, not the CSys ID. Two different systems
        ' that happen to be parallel resolve T1/T2/T3 along the same physical
        ' directions, so subtracting them is perfectly valid - and rejecting
        ' that pair on an ID comparison would be refusing correct work.
        ' Origins are irrelevant: a DOF direction does not depend on where the
        ' system is, only on how it is turned.
        aType = CSysInfo(App, aOut, aCSName)
        bType = CSysInfo(App, bOut, bCSName)

        If aType < 0 Or bType < 0 Then
            App.feAppMessage(FCM_WARNING, "Could not read the output CSys of node " _
                + Trim$(Str$(aID)) + " or " + Trim$(Str$(bID)) + " - pair skipped")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If

        If aType <> 0 Then
            App.feAppMessage(FCM_WARNING, "Node " + Trim$(Str$(aID)) + " output CSys " _
                + aCSName + " is not rectangular - pair skipped")
            App.feAppMessage(FCM_NORMAL, "      Radial and theta directions depend on position," _
                + " so they differ at A and at B.")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If
        If bType <> 0 Then
            App.feAppMessage(FCM_WARNING, "Node " + Trim$(Str$(bID)) + " output CSys " _
                + bCSName + " is not rectangular - pair skipped")
            nSkipped = nSkipped + 1
            GoTo NextPair
        End If

        If aOut = bOut Then
            csName = aCSName
        Else
            align = SameOrientation(App, aOut, bOut)
            If align < 0 Then
                App.feAppMessage(FCM_WARNING, "Could not compare CSys " + Trim$(Str$(aOut)) _
                    + " and " + Trim$(Str$(bOut)) + " - pair skipped")
                nSkipped = nSkipped + 1
                GoTo NextPair
            End If
            If align = 0 Then
                App.feAppMessage(FCM_WARNING, "Nodes " + Trim$(Str$(aID)) + " and " _
                    + Trim$(Str$(bID)) + " have output CSys " + Trim$(Str$(aOut)) + " and " _
                    + Trim$(Str$(bOut)) + ", which are NOT aligned - pair skipped")
                App.feAppMessage(FCM_NORMAL, "      Their T1/T2/T3 point in different directions," _
                    + " so the subtraction would be meaningless.")
                nSkipped = nSkipped + 1
                GoTo NextPair
            End If
            ' Different systems, same orientation - allowed, and said out loud
            ' so it is clear the tool noticed rather than missed it.
            csName = Trim$(Str$(aOut)) + " / " + Trim$(Str$(bOut)) + " (aligned)"
            App.feAppMessage(FCM_NORMAL, "  CSys " + Trim$(Str$(aOut)) + " and " _
                + Trim$(Str$(bOut)) + " differ by ID but are aligned - accepted")
        End If

        sep = Sqr((aX - bX) * (aX - bX) + (aY - bY) * (aY - bY) + (aZ - bZ) * (aZ - bZ))

        ' --- output CSys for the tracking node ---
        ' *** AN OVERRIDE RELABELS THE ANSWER, IT DOES NOT ROTATE IT ***
        ' The MPC equates DOF NUMBERS: u_M(T1) = u_A(T1) - u_B(T1). Those A and B
        ' terms are resolved in THEIR output system. Giving the tracking node a
        ' different one does not transform anything - the value it reports is
        ' still the relative displacement along the PICKED nodes' first axis,
        ' while the node now calls that direction by another system's name.
        ' Useful when the two systems are parallel and you just want the label
        ' to match a report CSys. Wrong, and silently so, when they are not.
        If wantOutCS = -1 Then
            mOut = aOut
            csMismatch = False
        Else
            mOut = wantOutCS
            If mOut = aOut Then
                csMismatch = False
            Else
                ' Same test as the gate: an override to a system that is merely
                ' a different ID but the same orientation changes nothing, and
                ' warning about it would be crying wolf.
                align = SameOrientation(App, mOut, aOut)
                csMismatch = (align <> 1)
            End If
        End If

        If csMismatch Then
            App.feAppMessage(FCM_WARNING, "  Tracking node CSys " + Trim$(Str$(mOut)) _
                + " differs from the picked nodes' CSys " + Trim$(Str$(aOut)))
            App.feAppMessage(FCM_WARNING, "  The VALUE stays along CSys " + Trim$(Str$(aOut)) _
                + " axes - only the axis labels change.")
        End If

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
            cLine5 = "Arrows:  red = axis 1,  green = axis 2,  blue = axis 3"
        Else
            cLine5 = "Separation:  " + Format$(sep, "0.####")
        End If
        If csMismatch Then
            cLine6 = "Tracking node CSys " + Trim$(Str$(mOut)) + " - LABELS ONLY, value is CSys " _
                + Trim$(Str$(aOut))
        Else
            cLine6 = "Tracking node CSys:  " + Trim$(Str$(mOut))
        End If

        Begin Dialog ConfirmDlg 420, 208, "Relative Displacement MPC - Confirm"
            Text 12, 10, 396, 12, cLine1
            Text 12, 28, 396, 12, cLine2
            Text 12, 46, 396, 12, cLine3
            Text 12, 64, 396, 12, cLine4
            Text 12, 82, 396, 12, cLine6
            Text 12, 100, 396, 12, cLine5
            Text 12, 126, 396, 12, "OK creates one node and one equation per direction."
            OKButton     114, 166, 90, 24
            CancelButton 224, 166, 90, 24
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
            ' Make it active. A model where no constraint set is active reports
            ' an active ID of 0, and anything downstream that keys off "the
            ' active constraint set" then silently does nothing - which is
            ' exactly how these equations first failed to reach a deck.
            bsNew.Active = bcSetID
            App.feAppMessage(FCM_NORMAL, "Created constraint set " + Trim$(Str$(bcSetID)) _
                + " - Relative Displacement (now active)")
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
        ' Normally the same system as A and B, which is what makes T1/T2/T3
        ' read as the relative X/Y/Z. An override only renames the axes - see
        ' the warning above.
        ndM.outCSys = mOut
        ndM.layer = ndA.layer
        If ndM.Put(mID) <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "Could not create the measurement node for pair " _
                + Trim$(Str$(aID)) + "/" + Trim$(Str$(bID)) + " - pair skipped")
            nFail = nFail + 1
            GoTo NextPair
        End If

        If sep <= 0.0 Then nCoincident = nCoincident + 1
        If csMismatch Then nMismatch = nMismatch + 1

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

        ' The equations existing is not the same as the deck containing them.
        ' An analysis case picks constraint equations through its own slot,
        ' separate from the one that picks constraints, and a set it does not
        ' name is silently absent from the export - no warning, no empty
        ' section, just no MPC cards.
        App.feAppMessage(FCM_WARNING, "  BEFORE EXPORTING: in the Analysis Set")
        App.feAppMessage(FCM_WARNING, "  Manager, set Constraint Equations to set " _
            + Trim$(Str$(bcSetID)) + ".")
        App.feAppMessage(FCM_WARNING, "  It is a SEPARATE slot from Constraints - if it")
        App.feAppMessage(FCM_WARNING, "  names another set, the deck gets no MPC cards.")

        ' Not optional. A copy of this tool handed to somebody else must not let
        ' their deck fail on a singularity nobody can explain.
        App.feAppMessage(FCM_WARNING, "  The measurement nodes' rotations - and any")
        App.feAppMessage(FCM_WARNING, "  translation you did not instrument - are")
        App.feAppMessage(FCM_WARNING, "  singular. PARAM,AUTOSPC must be ON.")

        If nMismatch > 0 Then
            App.feAppMessage(FCM_WARNING, "  Relabelled CSys:       " + Trim$(Str$(nMismatch)))
            App.feAppMessage(FCM_WARNING, "  Those nodes report along their PICKED nodes'")
            App.feAppMessage(FCM_WARNING, "  axes, not the axes their own CSys names.")
        End If

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
    Dim axDir(2, 2) As Double
    If AxesOf(App, csysID, _
              axDir(0, 0), axDir(0, 1), axDir(0, 2), _
              axDir(1, 0), axDir(1, 1), axDir(1, 2), _
              axDir(2, 0), axDir(2, 1), axDir(2, 2)) <> FE_OK Then
        Exit Function
    End If

    ' --- six arrows: one triad at A, one at B ---
    Dim a As Long
    Dim arw As Object
    Set arw = App.feGFXArrow
    arw.setID = gfxSet

    Dim cols(2) As Long
    cols(0) = FCL_RED
    cols(1) = FCL_GREEN
    cols(2) = FCL_BLUE

    ' Named axNo, not ax: WinWrap identifiers are case-insensitive, so a
    ' variable called ax IS the aX parameter above and the script will not load.
    Dim axNo As Long
    For a = 0 To 5
        If a < 3 Then
            arw.x = aX : arw.y = aY : arw.z = aZ
        Else
            arw.x = bX : arw.y = bY : arw.z = bZ
        End If
        axNo = a Mod 3
        arw.dx = axDir(axNo, 0)
        arw.dy = axDir(axNo, 1)
        arw.dz = axDir(axNo, 2)
        ' 1 = Scaled to view, so the triad stays visible at any model scale -
        ' and, critically, still draws when A and B are coincident and there is
        ' no separation distance to size it from.
        arw.length = 1.0
        arw.lengthmode = 1
        ' 0.0 = base of the arrow sits at the given point, so it emanates from
        ' the node instead of ending there.
        arw.location = 0.0
        arw.style = 1
        arw.color = cols(axNo)
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


' -----------------------------------------------------------------------------
' The three axis unit vectors of a coordinate system, in global rectangular.
'
' Derived by transforming the system's origin and its three unit points into
' global and differencing them. That is immune to the row/column ambiguity in
' the documented direction-cosine matrix - api.pdf says CSys.matrix holds "the
' rows stored sequentially" but never says whether a row is an axis or its
' transpose, and a transposed answer is wrong in a way that still looks right.
'
' Nine ByRef Doubles rather than an array because passing a fixed array into an
' arr() parameter is not reliable across Basic dialects.
' -----------------------------------------------------------------------------
Function AxesOf(App As Object, csysID As Long, _
                xx As Double, xy As Double, xz As Double, _
                yx As Double, yy As Double, yz As Double, _
                zx As Double, zy As Double, zz As Double) As Long

    AxesOf = FE_FAIL

    Dim p(2) As Double
    Dim org(2) As Double
    Dim vIn As Variant, vOut As Variant
    Dim rc As Long
    Dim k As Long
    Dim e(2, 2) As Double
    Dim a As Long

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
            e(a, k) = CDbl(vOut(k)) - org(k)
        Next k
    Next a

    xx = e(0, 0) : xy = e(0, 1) : xz = e(0, 2)
    yx = e(1, 0) : yy = e(1, 1) : yz = e(1, 2)
    zx = e(2, 0) : zy = e(2, 1) : zz = e(2, 2)

    AxesOf = FE_OK

End Function


' -----------------------------------------------------------------------------
' Do two coordinate systems have the same ORIENTATION?
'
' Returns 1 = aligned, 0 = not aligned, -1 = could not be evaluated.
'
' Origins are deliberately ignored. A nodal DOF direction depends only on how
' the system is turned, not on where it sits, so two systems with different IDs
' and different origins but parallel axes resolve T1/T2/T3 the same way and are
' interchangeable for this purpose. Comparing IDs instead would reject correct
' work - which is exactly what this tool used to do.
'
' TOL is per axis component. Aligned systems agree to rounding, so anything
' this loose is genuinely a different orientation; 1e-6 is about 0.00006 deg,
' tight enough to catch a real misalignment and slack enough to survive a CSys
' that was built by picking geometry.
' -----------------------------------------------------------------------------
Function SameOrientation(App As Object, cs1 As Long, cs2 As Long) As Long

    SameOrientation = -1

    Dim TOL As Double
    TOL = 0.000001

    Dim ax1 As Double, ay1 As Double, az1 As Double
    Dim bx1 As Double, by1 As Double, bz1 As Double
    Dim cx1 As Double, cy1 As Double, cz1 As Double
    Dim ax2 As Double, ay2 As Double, az2 As Double
    Dim bx2 As Double, by2 As Double, bz2 As Double
    Dim cx2 As Double, cy2 As Double, cz2 As Double

    If AxesOf(App, cs1, ax1, ay1, az1, bx1, by1, bz1, cx1, cy1, cz1) <> FE_OK Then Exit Function
    If AxesOf(App, cs2, ax2, ay2, az2, bx2, by2, bz2, cx2, cy2, cz2) <> FE_OK Then Exit Function

    SameOrientation = 0
    If Abs(ax1 - ax2) > TOL Then Exit Function
    If Abs(ay1 - ay2) > TOL Then Exit Function
    If Abs(az1 - az2) > TOL Then Exit Function
    If Abs(bx1 - bx2) > TOL Then Exit Function
    If Abs(by1 - by2) > TOL Then Exit Function
    If Abs(bz1 - bz2) > TOL Then Exit Function
    If Abs(cx1 - cx2) > TOL Then Exit Function
    If Abs(cy1 - cy2) > TOL Then Exit Function
    If Abs(cz1 - cz2) > TOL Then Exit Function

    SameOrientation = 1

End Function


' -----------------------------------------------------------------------------
' A coordinate system's type, with a display name out the side.
'
' Returns 0=Rectangular, 1=Cylindrical, 2=Spherical, or -1 if it could not be
' read. IDs 0/1/2 are the predefined globals: they cannot be Get, and they are
' rectangular / cylindrical / spherical in that order, so the ID is the type.
' -----------------------------------------------------------------------------
Function CSysInfo(App As Object, csysID As Long, csTitle As String) As Long

    If csysID <= 2 Then
        If csysID = 0 Then
            csTitle = "0 - Global Rectangular"
        ElseIf csysID = 1 Then
            csTitle = "1 - Global Cylindrical"
        Else
            csTitle = "2 - Global Spherical"
        End If
        CSysInfo = csysID
        Exit Function
    End If

    Dim cs As femap.CSys
    Set cs = App.feCSys
    If cs.Get(csysID) <> FE_OK Then
        csTitle = Trim$(Str$(csysID)) + " - (unreadable)"
        CSysInfo = -1
        Exit Function
    End If

    csTitle = Trim$(Str$(csysID)) + " - " + cs.title
    CSysInfo = cs.type

End Function
