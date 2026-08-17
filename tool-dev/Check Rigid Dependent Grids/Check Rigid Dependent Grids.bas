' Check Rigid Dependent Grids.bas
' -----------------------------------------------------------------------------
' Model QA: find rigid elements that fight over the same DEPENDENT GRID + DOF.
'
' Nastran rejects a deck where the same (grid, DOF) is dependent on more than
' one rigid. The check is deliberately at GRID + DOF level, not grid level: a
' grid may legally be dependent on one RBE2 for 123 and another for 456, and a
' grid-level check would report that as an error every time.
'
' Femap calls grids "nodes", so the API terms below - node lists, node(0),
' GetNodeList - are the Femap spelling of the same thing. User-facing output
' says grid.
'
' HOW EACH ELEMENT IS READ
' Femap has ONE rigid element type (FET_L_RIGID = 29). RBE2 and RBE3 are told
' apart by the Elem.RigidInterpolate flag, not by type:
'
'   RBE2 (RigidInterpolate = False)
'     node(0)          = INDEPENDENT node, its DOF in Release(0, 0..5)
'     GetNodeList(0..) = DEPENDENT nodes, DOF in dof(6i .. 6i+5)   <- checked
'
'   RBE3 (RigidInterpolate = True)
'     node(0)          = DEPENDENT / reference node, DOF in Release(0, 0..5)
'     GetNodeList(0..) = INDEPENDENT nodes, with weighting factors
'                                                                  <- node(0) checked
'
' *** THE RBE3 ARRANGEMENT IS INFERRED, NOT DOCUMENTED. ***
' The API guide never states it. It follows from feMeshConnectRigid, which
' describes its source node as "the Independent (RBE2) or Dependent (RBE3)
' node", and from GetNodeList's weight array being documented as "for
' interpolation elements" - i.e. the weighted list is the RBE3 independent
' side, as on the Nastran card. The Elem property table still labels node
' slot 0 "Independent" because that table is written per-topology and does not
' know about RigidInterpolate.
'
' Run the tool once with "Dump raw data" ticked and read the Messages window
' against a rigid you know, BEFORE trusting a clean report. Getting this
' backwards would check the wrong end of every RBE3 - worse than not checking
' them at all, because the report would look clean.
'
' The dof array values are treated as "nonzero = this DOF is dependent". The
' guide calls them "degree of freedom flags" and gives six sequential entries
' per node, but never states whether the value is 0/1 or something else. The
' dump prints them raw so this can be confirmed too.
'
' COVERAGE
' Only topology FTO_RIGIDLIST (13) is checked - that is RBE2 and RBE3. Rigid
' Bar (RBAR), Rigid Rod (RROD) and RBE1 store their dependent DOF completely
' differently (vRigidBarDOFs / RigidRodDependentDof / a second node list that
' GetNodeList does not expose). Those are COUNTED AND REPORTED AS UNCHECKED
' rather than skipped silently, so a clean report never implies coverage the
' tool does not have.
'
' Nothing is written to the model except an optional group of the offenders.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long, d As Long

    ' ============================================================
    ' Section 1: Options
    ' ============================================================
    Begin Dialog OptDlg 330, 232, "Check Rigid Dependent Grids"
        GroupBox 12, 8, 306, 64, "Elements To Check"
        OptionGroup .scopeMode
            OptionButton 22, 26, 286, 12, "All rigid elements in the model"
            OptionButton 22, 46, 286, 12, "Select the elements to check"
        CheckBox 12, 84, 306, 12, "Put the conflicting elements in a group", .chkGroup
        CheckBox 12, 104, 306, 12, "Dump raw rigid data to Messages (verification)", .chkDump
        Text     26, 120, 292, 24, "Tick the dump once and check an RBE3 you know - the RBE3 read is inferred from the API guide, not documented."
        Text     12, 156, 306, 24, "RBAR / RROD / RBE1 are not checked. They are counted and reported so a clean result is not mistaken for full coverage."
        OKButton     72, 196, 80, 20
        CancelButton 172, 196, 80, 20
    End Dialog

    Dim dlg As OptDlg
    dlg.scopeMode = 0
    dlg.chkGroup  = 1
    dlg.chkDump   = 0

    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user")
        Exit Sub
    End If

    Dim makeGroup As Boolean
    Dim doDump As Boolean
    makeGroup = (dlg.chkGroup <> 0)
    doDump    = (dlg.chkDump <> 0)

    ' ============================================================
    ' Section 2: Gather the elements to look at
    ' ============================================================
    Dim elSet As femap.Set
    Set elSet = App.feSet

    If dlg.scopeMode = 0 Then
        ' 29 = FET_L_RIGID. Rule-based so the model is never fully walked.
        rc = elSet.AddRule(FET_L_RIGID, FGD_ELEM_BYTYPE)
        If rc <> FE_OK Or elSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "No rigid elements found in the model")
            Exit Sub
        End If
    Else
        rc = elSet.Select(FT_ELEM, True, "Select elements to check")
        If rc <> FE_OK Or elSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "No elements selected - exiting")
            Exit Sub
        End If
    End If

    App.feAppMessage(FCM_NORMAL, "Checking " + Trim$(Str$(elSet.Count)) + " element(s)")

    ' ============================================================
    ' Section 3: Collect every (dependent node, DOF mask, element) entry
    '
    ' There is no bulk getter for rigid node lists - GetAllArray explicitly
    ' excludes them - so this is one Get + GetNodeList per rigid. That is the
    ' only route the API offers.
    ' ============================================================
    Dim el As femap.Elem
    Set el = App.feElem

    Dim cap As Long
    cap = 4096
    Dim entNode() As Long
    Dim entMask() As Long
    Dim entElem() As Long
    ReDim entNode(cap - 1)
    ReDim entMask(cap - 1)
    ReDim entElem(cap - 1)

    Dim nEnt As Long
    nEnt = 0

    Dim nRBE2 As Long, nRBE3 As Long, nOtherRigid As Long, nNotRigid As Long
    Dim nRBE3Ent As Long, nRBE2Ent As Long
    Dim nDumped As Long
    nRBE2 = 0 : nRBE3 = 0 : nOtherRigid = 0 : nNotRigid = 0
    nRBE3Ent = 0 : nRBE2Ent = 0
    nDumped = 0

    Dim eID As Long
    Dim nlCount As Long
    Dim vNode As Variant, vFace As Variant, vWeight As Variant, vDof As Variant
    Dim mask As Long
    Dim isRBE3 As Boolean
    Dim dumpLine As String

    App.feAppLock

    eID = elSet.First()
    Do While eID > 0
        If el.Get(eID) = FE_OK Then

            If el.type <> FET_L_RIGID Then
                nNotRigid = nNotRigid + 1
            ElseIf el.topology <> FTO_RIGIDLIST Then
                ' RBAR / RROD / RBE1 - a different storage scheme entirely.
                nOtherRigid = nOtherRigid + 1
            Else
                isRBE3 = (el.RigidInterpolate <> False)

                ' ---- optional raw dump, for verifying the two unknowns -------
                If doDump And nDumped < 6 Then
                    dumpLine = "DUMP elem " + Trim$(Str$(eID)) _
                             + "  RigidInterpolate=" + Trim$(Str$(el.RigidInterpolate)) _
                             + "  topology=" + Trim$(Str$(el.topology)) _
                             + "  node(0)=" + Trim$(Str$(el.node(0)))
                    App.feAppMessage(FCM_HIGHLIGHT, dumpLine)

                    dumpLine = "     Release(0,0..5) ="
                    For d = 0 To 5
                        dumpLine = dumpLine + " " + Trim$(Str$(el.Release(0, d)))
                    Next d
                    App.feAppMessage(FCM_NORMAL, dumpLine)

                    If el.GetNodeList(0, nlCount, vNode, vFace, vWeight, vDof) = FE_OK Then
                        App.feAppMessage(FCM_NORMAL, "     node list count = " + Trim$(Str$(nlCount)))
                        For i = 0 To nlCount - 1
                            If i < 3 Then
                                dumpLine = "     list[" + Trim$(Str$(i)) + "] grid " _
                                         + Trim$(Str$(CLng(vNode(i)))) + "  dof ="
                                For d = 0 To 5
                                    dumpLine = dumpLine + " " + Trim$(Str$(CLng(vDof(i * 6 + d))))
                                Next d
                                dumpLine = dumpLine + "   weight = " + Fmt(CDbl(vWeight(i)))
                                App.feAppMessage(FCM_NORMAL, dumpLine)
                            End If
                        Next i
                    End If
                    nDumped = nDumped + 1
                End If

                If isRBE3 Then
                    ' ---- RBE3: the reference node is the dependent one -------
                    nRBE3 = nRBE3 + 1
                    mask = 0
                    For d = 0 To 5
                        If el.Release(0, d) <> 0 Then mask = mask + Pow2(d)
                    Next d
                    If mask <> 0 Then
                        If nEnt >= cap Then
                            cap = cap * 2
                            ReDim Preserve entNode(cap - 1)
                            ReDim Preserve entMask(cap - 1)
                            ReDim Preserve entElem(cap - 1)
                        End If
                        entNode(nEnt) = el.node(0)
                        entMask(nEnt) = mask
                        entElem(nEnt) = eID
                        nEnt = nEnt + 1
                        nRBE3Ent = nRBE3Ent + 1
                    End If
                Else
                    ' ---- RBE2: every node in the list is dependent -----------
                    nRBE2 = nRBE2 + 1
                    If el.GetNodeList(0, nlCount, vNode, vFace, vWeight, vDof) = FE_OK Then
                        For i = 0 To nlCount - 1
                            mask = 0
                            For d = 0 To 5
                                If CLng(vDof(i * 6 + d)) <> 0 Then mask = mask + Pow2(d)
                            Next d
                            If mask <> 0 Then
                                If nEnt >= cap Then
                                    cap = cap * 2
                                    ReDim Preserve entNode(cap - 1)
                                    ReDim Preserve entMask(cap - 1)
                                    ReDim Preserve entElem(cap - 1)
                                End If
                                entNode(nEnt) = CLng(vNode(i))
                                entMask(nEnt) = mask
                                entElem(nEnt) = eID
                                nEnt = nEnt + 1
                                nRBE2Ent = nRBE2Ent + 1
                            End If
                        Next i
                    End If
                End If
            End If
        End If
        eID = elSet.Next()
    Loop

    App.feAppUnlock

    If nEnt = 0 Then
        App.feAppMessage(FCM_WARNING, "No dependent DOF found on any checked element - nothing to compare")
        Exit Sub
    End If

    ' ============================================================
    ' Section 4: Sort by node, then compare within each run
    '
    ' Sorting rather than bucketing by node ID: a bucket array would have to be
    ' sized to the LARGEST node ID in the model, which is fine at 50k nodes and
    ' ugly on a renumbered model with IDs in the millions.
    ' ============================================================
    QSortByNode(entNode, entMask, entElem, 0, nEnt - 1)

    Dim conflicts As Long, badNodes As Long
    conflicts = 0 : badNodes = 0

    Dim badElemSet As femap.Set
    Set badElemSet = App.feSet

    Dim runStart As Long, runEnd As Long
    Dim overlap As Long
    Dim nodeReported As Boolean

    App.feAppMessage(FCM_HIGHLIGHT, "----------------------------------------")
    App.feAppMessage(FCM_HIGHLIGHT, "  Conflicts")
    App.feAppMessage(FCM_HIGHLIGHT, "----------------------------------------")

    runStart = 0
    Do While runStart < nEnt
        runEnd = runStart
        Do While runEnd + 1 < nEnt
            If entNode(runEnd + 1) <> entNode(runStart) Then Exit Do
            runEnd = runEnd + 1
        Loop

        If runEnd > runStart Then
            nodeReported = False
            For i = runStart To runEnd - 1
                For j = i + 1 To runEnd
                    overlap = MaskAnd(entMask(i), entMask(j))
                    If overlap <> 0 Then
                        conflicts = conflicts + 1
                        If Not nodeReported Then
                            badNodes = badNodes + 1
                            nodeReported = True
                        End If
                        badElemSet.Add(entElem(i))
                        badElemSet.Add(entElem(j))
                        App.feAppMessage(FCM_ERROR, _
                            "Grid " + Trim$(Str$(entNode(i))) _
                            + "  DOF " + MaskText(overlap) _
                            + "  dependent on elements " + Trim$(Str$(entElem(i))) _
                            + " and " + Trim$(Str$(entElem(j))))
                    End If
                Next j
            Next i
        End If

        runStart = runEnd + 1
    Loop

    If conflicts = 0 Then
        App.feAppMessage(FCM_NORMAL, "  none")
    End If

    ' ============================================================
    ' Section 5: Group the offenders
    ' ============================================================
    Dim grpID As Long
    grpID = 0
    If makeGroup And conflicts > 0 And badElemSet.Count > 0 Then
        Dim gp As femap.Group
        Set gp = App.feGroup
        grpID = gp.NextEmptyID
        gp.title = "Rigid dependent DOF conflicts"

        ' SetAdd builds selection RULES on the in-memory group object - it does
        ' not write entities - so Put must come AFTER the adds. Put first and
        ' the rules are left sitting on the object and the group comes out
        ' empty. feGroupEvaluate then materialises the rules.
        rc = gp.SetAdd(FT_ELEM, badElemSet.ID)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Could not populate the group")
            grpID = 0
        Else
            rc = gp.Put(grpID)
            If rc <> FE_OK Then
                App.feAppMessage(FCM_WARNING, "Could not create the group")
                grpID = 0
            Else
                rc = App.feGroupEvaluate(-grpID, True)
            End If
        End If
    End If

    ' ============================================================
    ' Section 6: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Check Rigid Dependent Grids - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Elements examined:     " + Trim$(Str$(elSet.Count)))
    App.feAppMessage(FCM_NORMAL, "  RBE2 checked:          " + Trim$(Str$(nRBE2)) + "   (" + Trim$(Str$(nRBE2Ent)) + " dependent DOF entries)")
    App.feAppMessage(FCM_NORMAL, "  RBE3 checked:          " + Trim$(Str$(nRBE3)) + "   (" + Trim$(Str$(nRBE3Ent)) + " dependent DOF entries)")
    App.feAppMessage(FCM_NORMAL, "  Dependent DOF entries: " + Trim$(Str$(nEnt)))

    If conflicts > 0 Then
        App.feAppMessage(FCM_ERROR, "  CONFLICTS:             " + Trim$(Str$(conflicts)) _
            + "  on " + Trim$(Str$(badNodes)) + " grid(s)")
        App.feAppMessage(FCM_ERROR, "  Elements involved:     " + Trim$(Str$(badElemSet.Count)))
        If grpID > 0 Then
            App.feAppMessage(FCM_NORMAL, "  Group created:         " + Trim$(Str$(grpID)))
        End If
    Else
        App.feAppMessage(FCM_NORMAL, "  CONFLICTS:             none")
    End If

    ' Coverage caveats last, so they are the final thing read.
    If nOtherRigid > 0 Then
        App.feAppMessage(FCM_WARNING, "  NOT CHECKED - RBAR/RROD/RBE1: " + Trim$(Str$(nOtherRigid)) _
            + "   (different dependent-DOF storage; this tool does not read it)")
    End If
    If nNotRigid > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Skipped (not rigid):   " + Trim$(Str$(nNotRigid)))
    End If
    ' A type that was found but contributed no dependent DOF at all is almost
    ' certainly a bad read, not a clean model - most likely node(0) coming back
    ' as 0 for rigids, or the dof array not being the 0/1 flags assumed here.
    ' Silence would look identical to "no conflicts", so say it loudly.
    If nRBE3 > 0 And nRBE3Ent = 0 Then
        App.feAppMessage(FCM_ERROR, "  SUSPECT: " + Trim$(Str$(nRBE3)) _
            + " RBE3(s) found but NONE yielded a dependent DOF - the read is probably wrong," _
            + " not the model. Run with the dump option and check node(0)/Release(0,*).")
    End If
    If nRBE2 > 0 And nRBE2Ent = 0 Then
        App.feAppMessage(FCM_ERROR, "  SUSPECT: " + Trim$(Str$(nRBE2)) _
            + " RBE2(s) found but NONE yielded a dependent DOF - the read is probably wrong," _
            + " not the model. Run with the dump option and check the node-list dof values.")
    End If
    If nRBE3 > 0 And nRBE3Ent > 0 Then
        App.feAppMessage(FCM_WARNING, "  RBE3 handling is inferred from the API guide, not documented." _
            + " Verify with the dump option before trusting a clean RBE3 result.")
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub

' -----------------------------------------------------------------------------
' 2^d for d = 0..5. A literal lookup rather than an exponent so the result is
' unambiguously a Long.
' -----------------------------------------------------------------------------
Function Pow2(d As Long) As Long
    Select Case d
        Case 0
            Pow2 = 1
        Case 1
            Pow2 = 2
        Case 2
            Pow2 = 4
        Case 3
            Pow2 = 8
        Case 4
            Pow2 = 16
        Case 5
            Pow2 = 32
        Case Else
            Pow2 = 0
    End Select
End Function

' -----------------------------------------------------------------------------
' Bitwise AND of two 6-bit masks, done arithmetically. WinWrap's And is a
' logical operator in a Boolean context, and relying on it to behave bitwise on
' Longs is the kind of assumption that silently produces an empty report.
' -----------------------------------------------------------------------------
Function MaskAnd(m1 As Long, m2 As Long) As Long
    Dim d As Long, bit As Long, res As Long
    res = 0
    For d = 0 To 5
        bit = Pow2(d)
        If (m1 \ bit) Mod 2 = 1 Then
            If (m2 \ bit) Mod 2 = 1 Then res = res + bit
        End If
    Next d
    MaskAnd = res
End Function

' -----------------------------------------------------------------------------
' Render a 6-bit DOF mask as Nastran component digits, e.g. 1+2+3 -> "123".
' -----------------------------------------------------------------------------
Function MaskText(m As Long) As String
    Dim d As Long, bit As Long, s As String
    s = ""
    For d = 0 To 5
        bit = Pow2(d)
        If (m \ bit) Mod 2 = 1 Then s = s + Trim$(Str$(d + 1))
    Next d
    If s = "" Then s = "(none)"
    MaskText = s
End Function

' -----------------------------------------------------------------------------
' Quicksort three parallel arrays on the node key. Middle-element pivot so an
' already-ordered input (common - the entries come out roughly in element
' order) does not hit the O(n^2) worst case.
' -----------------------------------------------------------------------------
Sub QSortByNode(k() As Long, m() As Long, e() As Long, lo As Long, hi As Long)
    Dim i As Long, j As Long, p As Long, t As Long
    If lo >= hi Then Exit Sub

    i = lo
    j = hi
    p = k((lo + hi) \ 2)

    Do While i <= j
        Do While k(i) < p
            i = i + 1
        Loop
        Do While k(j) > p
            j = j - 1
        Loop
        If i <= j Then
            t = k(i) : k(i) = k(j) : k(j) = t
            t = m(i) : m(i) = m(j) : m(j) = t
            t = e(i) : e(i) = e(j) : e(j) = t
            i = i + 1
            j = j - 1
        End If
    Loop

    If lo < j Then QSortByNode(k, m, e, lo, j)
    If i < hi Then QSortByNode(k, m, e, i, hi)
End Sub

' -----------------------------------------------------------------------------
' Readable number for messages. Str$ on a Double emits up to 15 digits.
' -----------------------------------------------------------------------------
Function Fmt(v As Double) As String
    Dim a As Double
    a = Abs(v)
    If a = 0.0 Then
        Fmt = "0"
    ElseIf a >= 1000000.0 Or a < 0.0001 Then
        Fmt = Trim$(Str$(v))
    Else
        Fmt = Trim$(Str$(RoundTo(v, 4)))
    End If
End Function

' Sign-aware round to a number of decimal places (Int() truncates toward
' negative infinity, so negatives need the explicit mirror).
Function RoundTo(v As Double, places As Long) As Double
    Dim sc As Double
    Dim i As Long
    sc = 1.0
    For i = 1 To places
        sc = sc * 10.0
    Next i
    If v >= 0.0 Then
        RoundTo = Int(v * sc + 0.5) / sc
    Else
        RoundTo = -Int(-v * sc + 0.5) / sc
    End If
End Function
