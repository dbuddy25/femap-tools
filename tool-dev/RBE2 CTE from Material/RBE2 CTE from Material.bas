' RBE2 CTE from Material.bas
' -----------------------------------------------------------------------------
' Set each RBE2's thermal expansion coefficient from the material it is actually
' attached to, across the whole model in one pass. Where a spider bridges two
' materials with different CTEs, it is LEFT ALONE and reported.
'
' THE CHAIN
'   RBE2 -> its dependent nodes -> the non-rigid elements on those nodes
'        -> those elements' materials -> mval(36) -> el.RigidThermalExpansion
'
' Dependent nodes, not independent. On a hole spider or bolt pattern the
' dependent nodes are the legs sitting on the mesh; the independent centre node
' is usually free, or tied to a CBUSH, and carries no material at all. Reading
' the centre node would find nothing on most spiders and the wrong thing on the
' rest.
'
' RBE2 vs RBE3. Femap has ONE rigid element type (FET_L_RIGID). The two are told
' apart by Elem.RigidInterpolate, not by type: False = RBE2, True = RBE3. Only
' RBE2 is touched here. On an RBE3 the node roles are reversed - node(0) is the
' dependent one - so the same code would read the wrong end.
'
' *** WHAT COUNTS AS A CONFLICT IS THE CTE VALUE, NOT THE MATERIAL ID ***
' A spider landing on two different aluminium materials that happen to share a
' CTE is not ambiguous, and flagging it would bury the real conflicts under
' dozens of false ones. Materials are resolved to their CTE first, and only
' differing CTEs conflict. The comparison is relative, because CTE values are
' around 1e-5 and an absolute tolerance is meaningless at that scale.
'
' Conflicted elements are SKIPPED - their existing CTE is not modified - and
' collected into a group so they can be looked at. The tool never picks a winner
' on its own: an RBE2 spanning a steel fitting and an aluminium skin is a real
' modelling decision, and quietly writing one of the two values would hide it.
'
' Elements attached to nothing with a material - all-rigid neighbourhoods, mass
' elements, plot-only - are reported separately from conflicts. A spider with no
' material to read is a different problem from one with too many.
'
' Nothing is written until the confirm dialog, and "Report only" skips the write
' entirely.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, j As Long, k As Long

    ' ============================================================
    ' Section 1: Options
    ' ============================================================
    Begin Dialog OptDlg 400, 256, "RBE2 CTE from Material"
        GroupBox 12, 8, 376, 64, "Which RBE2s"
        OptionGroup .scopeMode
            OptionButton 24, 26, 352, 14, "Every RBE2 in the model"
            OptionButton 24, 48, 352, 14, "Select them"
        Text     12, 84, 200, 12, "CTE match tolerance (%):"
        TextBox  216, 82, 80, 18, .tolBox
        Text     12, 106, 376, 22, "Two materials whose CTEs agree within this are treated as one value, not a conflict."
        CheckBox 12, 136, 376, 14, "Leave RBE2s that already have a CTE alone", .chkKeep
        CheckBox 12, 156, 376, 14, "Put conflicted RBE2s in a group", .chkGroup
        CheckBox 12, 176, 376, 14, "Report only - change nothing", .chkDry
        OKButton     104, 216, 90, 24
        CancelButton 214, 216, 90, 24
    End Dialog

    Dim dlg As OptDlg
    dlg.scopeMode = 0
    dlg.tolBox = "0.1"
    dlg.chkKeep = 1
    dlg.chkGroup = 1
    dlg.chkDry = 0
    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim tolPct As Double
    Dim makeGroup As Boolean, dryRun As Boolean, keepExisting As Boolean
    tolPct = Val(dlg.tolBox)
    If tolPct < 0 Then tolPct = 0
    makeGroup = (dlg.chkGroup <> 0)
    dryRun = (dlg.chkDry <> 0)
    keepExisting = (dlg.chkKeep <> 0)

    ' ============================================================
    ' Section 2: Every rigid in scope
    ' ============================================================
    Dim rigidSet As femap.Set
    Set rigidSet = App.feSet

    If dlg.scopeMode = 0 Then
        ' Rule-based so the model is never fully walked just to find rigids.
        rc = rigidSet.AddRule(FET_L_RIGID, FGD_ELEM_BYTYPE)
        If rc <> FE_OK Or rigidSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "No rigid elements in the model - exiting")
            Exit Sub
        End If
    Else
        rc = rigidSet.Select(FT_ELEM, True, "Select RBE2 elements")
        If rc <> FE_OK Or rigidSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "Nothing selected - exiting")
            Exit Sub
        End If
    End If

    ' A set of EVERY rigid in the model, whatever the scope. Used below to strip
    ' rigids out of each spider's attached-element list - a spider tied to
    ' another spider must not read a CTE through it.
    Dim allRigid As femap.Set
    Set allRigid = App.feSet
    rc = allRigid.AddRule(FET_L_RIGID, FGD_ELEM_BYTYPE)

    ' Pull the IDs out before any measuring starts - the loop below runs set
    ' rules and element Gets, and a live cursor across those is asking for it.
    Dim nR As Long
    nR = rigidSet.Count
    Dim rIDs() As Long
    ReDim rIDs(nR - 1)
    Dim v As Long
    rigidSet.Reset
    v = rigidSet.Next
    For i = 0 To nR - 1
        rIDs(i) = v
        v = rigidSet.Next
    Next i

    ' ============================================================
    ' Section 3: Material -> CTE, once
    '
    ' Read up front so the per-element loop never touches a Material object.
    ' mval(36) is the thermal expansion coefficient.
    ' ============================================================
    Dim mtl As Object
    Set mtl = App.feMatl
    Dim nM As Long
    nM = 0
    mtl.Reset
    Do While mtl.Next()
        nM = nM + 1
    Loop
    If nM = 0 Then
        App.feAppMessage(FCM_WARNING, "No materials in the model - nothing to read a CTE from")
        Exit Sub
    End If

    Dim mIDs() As Long, mCTE() As Double, mNames() As String
    ReDim mIDs(nM - 1)
    ReDim mCTE(nM - 1)
    ReDim mNames(nM - 1)
    j = 0
    mtl.Reset
    Do While mtl.Next()
        mIDs(j) = mtl.ID
        mCTE(j) = mtl.mval(36)
        mNames(j) = Trim$(Str$(mtl.ID)) + " - " + mtl.title
        j = j + 1
    Loop

    ' ============================================================
    ' Section 4: Work out each RBE2's CTE
    ' ============================================================
    Dim el As femap.Elem
    Set el = App.feElem
    Dim elBulk As femap.Elem
    Set elBulk = App.feElem

    Dim ndSet As femap.Set, attSet As femap.Set
    Set ndSet = App.feSet
    Set attSet = App.feSet

    Dim badSet As femap.Set
    Set badSet = App.feSet

    Dim tgtIDs() As Long, tgtCTE() As Double, tgtName() As String, tgtOld() As Double
    ReDim tgtIDs(nR - 1)
    ReDim tgtCTE(nR - 1)
    ReDim tgtName(nR - 1)
    ReDim tgtOld(nR - 1)
    Dim nTgt As Long
    nTgt = 0

    Dim nRBE3 As Long, nNotRigid As Long, nNoMatl As Long, nConflict As Long
    nRBE3 = 0 : nNotRigid = 0 : nNoMatl = 0 : nConflict = 0

    Dim numElem As Long
    Dim entID As Variant, propID As Variant, matlID As Variant, elemTYPE As Variant
    Dim etopo As Variant, vCG As Variant, elen As Variant, earea As Variant, evol As Variant

    Dim cteVals(63) As Double
    Dim cteNames(63) As String
    Dim nCte As Long

    App.feAppStatusShow(True, nR)

    For i = 0 To nR - 1
        App.feAppStatusUpdate(i + 1)

        If el.Get(rIDs(i)) <> FE_OK Then
            nNotRigid = nNotRigid + 1
        ElseIf el.topology <> FTO_RIGIDLIST Then
            nNotRigid = nNotRigid + 1
        ElseIf el.RigidInterpolate Then
            ' RBE3 - node roles are reversed, so this code would read the wrong
            ' end. Counted, not silently skipped.
            nRBE3 = nRBE3 + 1
        Else
            ' --- dependent nodes ---
            ' Six arguments, and vFace is one of them - it is easy to write
            ' this with five and have the weights land in the DOF slot.
            Dim nlCount As Long
            Dim vNode As Variant, vFace As Variant, vWeight As Variant, vDof As Variant

            ndSet.Clear
            If el.GetNodeList(0, nlCount, vNode, vFace, vWeight, vDof) = FE_OK Then
                For k = 0 To nlCount - 1
                    If CLng(vNode(k)) > 0 Then rc = ndSet.Add(CLng(vNode(k)))
                Next k
            End If

            nCte = 0
            If ndSet.Count > 0 Then
                ' --- elements on those nodes, rigids removed ---
                attSet.Clear
                rc = attSet.AddSetRule(ndSet.ID, FGD_ELEM_BYNODE)
                rc = attSet.RemoveSet(allRigid.ID)

                If attSet.Count > 0 Then
                    ' One call for the whole attached set - no Get per element.
                    ' GetGeomPropArray is an Elem OBJECT method, and it needs
                    ' its own object: calling it on `el` would overwrite the
                    ' RBE2 currently loaded there and the Put in Section 5 would
                    ' write back the wrong element.
                    rc = elBulk.GetGeomPropArray(attSet.ID, numElem, entID, propID, _
                        matlID, elemTYPE, etopo, vCG, elen, earea, evol)

                    If rc = FE_OK Then
                        For k = 0 To numElem - 1
                            If matlID(k) > 0 Then
                                Dim thisCTE As Double
                                Dim thisName As String
                                Dim found As Boolean
                                thisCTE = 0
                                thisName = ""
                                found = False
                                For j = 0 To nM - 1
                                    If mIDs(j) = matlID(k) Then
                                        thisCTE = mCTE(j)
                                        thisName = mNames(j)
                                        found = True
                                        Exit For
                                    End If
                                Next j

                                If found Then
                                    ' Distinct by VALUE, within tolerance - two
                                    ' materials sharing a CTE are one answer.
                                    Dim isNew As Boolean
                                    isNew = True
                                    For j = 0 To nCte - 1
                                        If SameCTE(cteVals(j), thisCTE, tolPct) Then
                                            isNew = False
                                            Exit For
                                        End If
                                    Next j
                                    If isNew And nCte <= UBound(cteVals) Then
                                        cteVals(nCte) = thisCTE
                                        cteNames(nCte) = thisName
                                        nCte = nCte + 1
                                    End If
                                End If
                            End If
                        Next k
                    End If
                End If
            End If

            If nCte = 0 Then
                nNoMatl = nNoMatl + 1
            ElseIf nCte = 1 Then
                tgtIDs(nTgt) = rIDs(i)
                tgtCTE(nTgt) = cteVals(0)
                tgtName(nTgt) = cteNames(0)
                tgtOld(nTgt) = el.RigidThermalExpansion
                nTgt = nTgt + 1
            Else
                nConflict = nConflict + 1
                rc = badSet.Add(rIDs(i))
                App.feAppMessage(FCM_WARNING, "  RBE2 " + Trim$(Str$(rIDs(i))) _
                    + " spans " + Trim$(Str$(nCte)) + " CTEs:")
                For j = 0 To nCte - 1
                    App.feAppMessage(FCM_NORMAL, "      " + Format$(cteVals(j), "0.0000E+00") _
                        + "   " + cteNames(j))
                Next j
            End If
        End If
    Next i

    App.feAppStatusShow(False, 0)

    ' ============================================================
    ' Section 5: Confirm, then write
    ' ============================================================
    Dim nWrote As Long, nFail As Long, nLeft As Long
    nWrote = 0 : nFail = 0 : nLeft = 0

    ' --- what is already on these elements ---
    '
    ' An existing CTE that DISAGREES with the derived one is worth seeing on its
    ' own. It means either somebody set it by hand, or the material under the
    ' spider changed since it was set - and the second case is a stale model,
    ' not a preference. Reported whether or not it is going to be overwritten.
    Dim nHad As Long, nHadSame As Long, nHadDiff As Long
    nHad = 0 : nHadSame = 0 : nHadDiff = 0
    For i = 0 To nTgt - 1
        If tgtOld(i) <> 0 Then
            nHad = nHad + 1
            If SameCTE(tgtOld(i), tgtCTE(i), tolPct) Then
                nHadSame = nHadSame + 1
            Else
                nHadDiff = nHadDiff + 1
                App.feAppMessage(FCM_WARNING, "  RBE2 " + Trim$(Str$(tgtIDs(i))) _
                    + " already has " + Format$(tgtOld(i), "0.0000E+00") _
                    + ", material says " + Format$(tgtCTE(i), "0.0000E+00") _
                    + "   (" + tgtName(i) + ")")
            End If
        End If
    Next i

    If dryRun Then
        App.feAppMessage(FCM_HIGHLIGHT, "Report only - nothing was modified")
    ElseIf nTgt = 0 Then
        App.feAppMessage(FCM_WARNING, "No RBE2 resolved to a single CTE - nothing to write")
    Else
        Dim answer As Long
        answer = App.feAppMessageBox(1, "Set the CTE on " + Trim$(Str$(nTgt)) _
            + " RBE2 element(s) from their attached material?")
        If answer <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Cancelled - nothing modified")
        Else
            For i = 0 To nTgt - 1
                Dim doWrite As Boolean
                doWrite = True
                If tgtOld(i) <> 0 And keepExisting Then doWrite = False

                If Not doWrite Then
                    nLeft = nLeft + 1
                ElseIf el.Get(tgtIDs(i)) = FE_OK Then
                    el.RigidThermalExpansion = tgtCTE(i)
                    If el.Put(tgtIDs(i)) = FE_OK Then
                        nWrote = nWrote + 1
                    Else
                        nFail = nFail + 1
                    End If
                Else
                    nFail = nFail + 1
                End If
            Next i
        End If
    End If

    ' ============================================================
    ' Section 6: Group the conflicts
    ' ============================================================
    Dim grpID As Long
    grpID = 0
    If makeGroup And badSet.Count > 0 Then
        Dim gp As femap.Group
        Set gp = App.feGroup
        grpID = gp.NextEmptyID
        gp.title = "RBE2 CTE conflicts"
        ' Rules go on the object BEFORE Put, then Evaluate materialises them.
        rc = gp.SetAdd(FT_ELEM, badSet.ID)
        If rc = FE_OK Then
            If gp.Put(grpID) = FE_OK Then
                rc = App.feGroupEvaluate(-grpID, True)
            Else
                grpID = 0
            End If
        Else
            grpID = 0
        End If
    End If

    ' ============================================================
    ' Section 7: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  RBE2 CTE from Material - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL,    "  Elements examined:     " + Trim$(Str$(nR)))
    App.feAppMessage(FCM_NORMAL,    "  RBE2 resolved:         " + Trim$(Str$(nTgt)))
    If Not dryRun Then
        App.feAppMessage(FCM_NORMAL, "  CTE written:           " + Trim$(Str$(nWrote)))
        If nLeft > 0 Then
            App.feAppMessage(FCM_NORMAL, "  Left alone (had one):  " + Trim$(Str$(nLeft)))
        End If
    End If
    If nHad > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Already had a CTE:     " + Trim$(Str$(nHad)) _
            + "   (" + Trim$(Str$(nHadSame)) + " matching, " + Trim$(Str$(nHadDiff)) + " different)")
        If nHadDiff > 0 And keepExisting Then
            App.feAppMessage(FCM_WARNING, "  The " + Trim$(Str$(nHadDiff)) _
                + " that differ were NOT changed - untick the keep option to overwrite.")
        End If
    End If

    ' --- what was actually applied, and to how many ---
    '
    ' The per-element count is the point. "142 RBE2 got the aluminium CTE, 38
    ' got the steel one" is checkable against what you expect the model to look
    ' like; a single total is not.
    If nTgt > 0 Then
        Dim uCTE(63) As Double
        Dim uName(63) As String
        Dim uCount(63) As Long
        Dim nU As Long
        nU = 0
        For i = 0 To nTgt - 1
            Dim hit As Long
            hit = -1
            For j = 0 To nU - 1
                If SameCTE(uCTE(j), tgtCTE(i), tolPct) Then
                    hit = j
                    Exit For
                End If
            Next j
            If hit >= 0 Then
                uCount(hit) = uCount(hit) + 1
            ElseIf nU <= UBound(uCTE) Then
                uCTE(nU) = tgtCTE(i)
                uName(nU) = tgtName(i)
                uCount(nU) = 1
                nU = nU + 1
            End If
        Next i

        If dryRun Then
            App.feAppMessage(FCM_HIGHLIGHT, "  CTE that WOULD be applied:")
        Else
            App.feAppMessage(FCM_HIGHLIGHT, "  CTE applied:")
        End If
        For j = 0 To nU - 1
            App.feAppMessage(FCM_NORMAL, "    " + Format$(uCTE(j), "0.0000E+00") _
                + "   " + Right$("     " + Trim$(Str$(uCount(j))), 5) + " RBE2" _
                + "   (" + uName(j) + ")")
        Next j
    End If
    If nConflict > 0 Then
        App.feAppMessage(FCM_ERROR,  "  CONFLICTS (skipped):   " + Trim$(Str$(nConflict)))
        If grpID > 0 Then
            App.feAppMessage(FCM_NORMAL, "  Group created:         " + Trim$(Str$(grpID)))
        End If
    Else
        App.feAppMessage(FCM_NORMAL, "  Conflicts:             none")
    End If
    If nNoMatl > 0 Then
        App.feAppMessage(FCM_WARNING, "  No material found:     " + Trim$(Str$(nNoMatl)) _
            + "   (attached only to rigids, masses or plot-only)")
    End If
    If nRBE3 > 0 Then
        App.feAppMessage(FCM_WARNING, "  RBE3 skipped:          " + Trim$(Str$(nRBE3)) _
            + "   (node roles are reversed - not handled)")
    End If
    If nNotRigid > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Not a rigid:           " + Trim$(Str$(nNotRigid)))
    End If
    If nFail > 0 Then
        App.feAppMessage(FCM_ERROR,  "  FAILED to write:       " + Trim$(Str$(nFail)))
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

End Sub

' -----------------------------------------------------------------------------
' Do two CTEs count as the same value?
'
' Relative, not absolute. CTE values sit around 1e-5, so any fixed epsilon is
' either meaningless or unmeetable. Two values that are both essentially zero
' agree - a material with no CTE entered should not read as a conflict against
' another one that also has none.
' -----------------------------------------------------------------------------
Function SameCTE(a As Double, b As Double, tolPct As Double) As Boolean

    Dim mag As Double

    mag = Abs(a)
    If Abs(b) > mag Then mag = Abs(b)

    If mag = 0 Then
        SameCTE = True
    Else
        SameCTE = (Abs(a - b) / mag <= tolPct / 100#)
    End If

End Function
