' Stress Groups by Material.bas
' -----------------------------------------------------------------------------
' Builds groups holding the elements whose stress is worth reporting - and, just
' as importantly, leaving out the elements whose stress is an artefact.
'
' TWO MODES, set by a checkbox:
'   ONE GROUP PER MATERIAL  named "<prefix> - <material title>"
'   ONE COMBINED GROUP      the union of every selected material, named exactly
'                           what you type. Pick three materials, get one group.
'
' Either way the contents are assembled per material as:
'
'   + ALL plate elements of that material          (plate, laminate, membrane)
'   + ALL beam elements of that material           (beam, bar, rod)
'   + ONLY the FREE FACE solids of that material
'   - EVERY element directly attached to a rigid   (the exclusion, see below)
'
' *** WHY ONLY FREE-FACE SOLIDS ***
' In a solid, peak stress lives on the exterior surface - the free face - where
' there is no through-thickness constraint. Interior solids are along for the
' ride. Reporting them dilutes the summary and buries the number you want.
'
' *** FREE FACES ARE COMPUTED OVER THE WHOLE SOLID MESH, NOT PER MATERIAL ***
' This is the trap in this tool, and it is silent. If free faces were computed
' from only ONE material's solids, then every face where that material is bonded
' to a DIFFERENT material's solid would look free - because from inside that one
' material's subset, nothing is on the other side. Those faces are interior. The
' stress there is not free-surface stress.
'
' So feElementFreeFace is called ONCE against every solid in the model, and the
' result is intersected with each material afterwards. Do not "optimise" this by
' moving the call inside the per-material loop. It would run faster and be
' wrong, and it would be wrong in a way that only shows up at material
' interfaces - the exact place anyone reads this report to look at.
'
' *** WHY ELEMENTS AT RIGIDS COME OUT ***
' An RBE2/RBE3 imposes infinite stiffness on the nodes it touches. The elements
' sharing those nodes report a stress concentration that is a modelling artefact,
' not a load path - and it is routinely the model-wide maximum, so it hijacks
' every peak-stress summary it appears in.
'
' ONE element layer is removed: the elements directly tied to a rigid. The
' SECOND element away is kept, which is the first ring far enough out for the
' artefact to have decayed. That is a deliberate depth, not an arbitrary one -
' see "Tuning the exclusion depth" below if it needs to change.
'
' NOTHING IN THE MODEL IS MODIFIED except that groups are created.
'
' TUNING THE EXCLUSION DEPTH
' Set.AddConnectedElements() grows the set by exactly one element layer - it
' adds every element sharing at least one node with the set. Section 4 calls it
' once. Call it twice to remove two layers, and so on. That single call is the
' whole knob.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long

    ' All declarations live here. WinWrap can baulk at a Dim inside a loop or a
    ' conditional block, and this Sub has both.
    Dim prefix As String, mTitle As String, gName As String
    Dim nFree As Long, vFreeData As Variant
    Dim vElems() As Long
    Dim matID As Long, gid As Long, nMade As Long
    Dim nPlate As Long, nSolid As Long, nBeam As Long, nSolidAll As Long
    Dim nBefore As Long, nRemoved As Long, nRigid As Long
    Dim lb As Long

    ' ============================================================
    ' Section 1: Pick the materials
    ' ============================================================
    Dim mtSet As femap.Set
    Set mtSet = App.feSet
    rc = mtSet.SelectMultiIDV2(FT_MATL, 1, "Select material(s) to build stress groups for")
    If rc = FE_CANCEL Or mtSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    ' ============================================================
    ' Section 2: Options
    ' ============================================================
    ' Sizing note: these are dialog units, not pixels, and the font is
    ' proportional - a label that fits in the editor can still clip at runtime.
    ' Every control is given far more width and height than its text needs.
    ' If a label is ever lengthened, widen the dialog with it.
    Begin Dialog StressGrpDlg 520, 250, "Stress Groups by Material"
        Text        14,  12, 480, 16, "Group name:"
        TextBox     14,  32, 480, 20, .prefixBox
        Text        14,  60, 480, 16, "Per material: the material title is appended to this."
        Text        14,  78, 480, 16, "Combined: this name is used verbatim."
        CheckBox    14, 106, 480, 18, "Combine ALL selected materials into ONE group", .chkCombine
        CheckBox    14, 136, 480, 18, "Exclude elements attached to rigid elements", .chkRigid
        CheckBox    14, 158, 480, 18, "Plate elements cover a solid face (face is NOT free)", .chkPlaneElem
        CheckBox    14, 180, 480, 18, "Consider midside nodes when finding free faces", .chkParabolic
        OKButton   150, 214, 90, 24
        CancelButton 260, 214, 90, 24
    End Dialog

    Dim dlg As StressGrpDlg
    dlg.prefixBox = "Stress"
    dlg.chkCombine = 0
    dlg.chkRigid = 1
    dlg.chkPlaneElem = 0
    dlg.chkParabolic = 1
    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    prefix = Trim$(dlg.prefixBox)
    If prefix = "" Then prefix = "Stress"

    Dim bRigid As Boolean, bPlane As Boolean, bParab As Boolean, bCombine As Boolean
    bCombine = (dlg.chkCombine = 1)
    bRigid = (dlg.chkRigid = 1)
    bPlane = (dlg.chkPlaneElem = 1)
    bParab = (dlg.chkParabolic = 1)

    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feAppMessage(FCM_NORMAL, "STRESS GROUPS BY MATERIAL")
    App.feAppMessage(FCM_NORMAL, "==================================================")

    ' ============================================================
    ' Section 3: Model-wide element classes, built ONCE
    ' ============================================================
    Dim allPlate As femap.Set
    Set allPlate = App.feSet
    allPlate.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)
    allPlate.AddRule(FET_L_LAMINATE_PLATE, FGD_ELEM_BYTYPE)
    allPlate.AddRule(FET_L_MEMBRANE, FGD_ELEM_BYTYPE)

    Dim allSolid As femap.Set
    Set allSolid = App.feSet
    allSolid.AddRule(FET_L_SOLID, FGD_ELEM_BYTYPE)
    allSolid.AddRule(FET_L_LAMINATE_SOLID, FGD_ELEM_BYTYPE)

    Dim allBeam As femap.Set
    Set allBeam = App.feSet
    allBeam.AddRule(FET_L_BEAM, FGD_ELEM_BYTYPE)
    allBeam.AddRule(FET_L_BAR, FGD_ELEM_BYTYPE)
    allBeam.AddRule(FET_L_ROD, FGD_ELEM_BYTYPE)

    App.feAppMessage(FCM_NORMAL, "Model: " & Str$(allPlate.Count) & " plate, " & _
        Str$(allSolid.Count) & " solid, " & Str$(allBeam.Count) & " beam elements")

    ' ---- Free faces, computed against the WHOLE solid mesh (see header) ----
    Dim freeSolid As femap.Set
    Set freeSolid = App.feSet
    Dim freeInput As femap.Set

    If allSolid.Count > 0 Then
        ' bPlaneElem only counts plates that are IN the set handed to the call,
        ' so when that option is on the plates must be included in the input.
        Set freeInput = App.feSet
        freeInput.AddSet(allSolid.ID)
        If bPlane Then freeInput.AddSet(allPlate.ID)

        rc = App.feElementFreeFace(freeInput.ID, bParab, bPlane, nFree, vFreeData)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_ERROR, "feElementFreeFace failed, rc=" & Str$(rc))
            Exit Sub
        End If

        ' vFreeData is [elem1, face1, elem2, face2, ...] - the even slots are the
        ' element IDs, and one element appears once per free face it owns. The
        ' Set absorbs the duplicates.
        If nFree > 0 Then
            ' The guide documents nFreeData as [0..2*nFreeCount-1], but this
            ' array arrives over COM - read LBound rather than assume it is 0.
            lb = LBound(vFreeData)
            ReDim vElems(nFree - 1)
            For i = 0 To nFree - 1
                vElems(i) = vFreeData(lb + 2 * i)
            Next i
            freeSolid.AddArray(nFree, vElems)
        End If

        ' A plate handed in as a "cover" can come back owning a free face. Only
        ' solids belong in this set.
        freeSolid.RemoveNotCommon(allSolid.ID)

        App.feAppMessage(FCM_NORMAL, "Free faces found: " & Str$(nFree) & _
            "  on " & Str$(freeSolid.Count) & " solid elements")
    Else
        App.feAppMessage(FCM_NORMAL, "No solid elements in the model.")
    End If

    ' ============================================================
    ' Section 4: The rigid exclusion band, built ONCE
    ' ============================================================
    ' The band is the rigid elements themselves PLUS one layer of everything
    ' touching them. AddConnectedElements() adds every element sharing at least
    ' one node with the set - that one call IS the one-element layer. Call it
    ' again to go a layer deeper.
    Dim rigidBand As femap.Set
    Set rigidBand = App.feSet
    nRigid = 0

    If bRigid Then
        rigidBand.AddRule(FET_L_RIGID, FGD_ELEM_BYTYPE)
        nRigid = rigidBand.Count
        If nRigid > 0 Then
            rigidBand.AddConnectedElements
        End If
        App.feAppMessage(FCM_NORMAL, "Rigid elements: " & Str$(nRigid) & _
            "  -> exclusion band of " & Str$(rigidBand.Count) & " elements (rigids + 1 layer)")
    Else
        App.feAppMessage(FCM_NORMAL, "Rigid exclusion is OFF.")
    End If

    ' ============================================================
    ' Section 5: Walk the materials
    ' ============================================================
    Dim mt As femap.Matl
    Set mt = App.feMatl
    Dim gp As femap.Group
    Set gp = App.feGroup

    Dim matSet As femap.Set
    Set matSet = App.feSet
    Dim keepSet As femap.Set
    Set keepSet = App.feSet
    Dim workSet As femap.Set
    Set workSet = App.feSet
    Dim combinedSet As femap.Set
    Set combinedSet = App.feSet

    nMade = 0

    If bCombine Then
        App.feAppMessage(FCM_NORMAL, "")
        App.feAppMessage(FCM_NORMAL, "COMBINING " & Str$(mtSet.Count) & _
            " material(s) into one group.")
    End If

    matID = mtSet.First()
    Do While matID > 0

        rc = mt.Get(matID)
        mTitle = mt.title
        If Trim$(mTitle) = "" Then mTitle = "Material " & Trim$(Str$(matID))

        ' ---- every element of this material ----
        matSet.Clear
        matSet.AddRule(matID, FGD_ELEM_BYMATL)

        App.feAppMessage(FCM_NORMAL, "")
        App.feAppMessage(FCM_NORMAL, "MATERIAL " & Str$(matID) & " : " & mTitle & _
            "   (" & Str$(matSet.Count) & " elements)")

        If matSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "  no elements use this material - skipped")
        Else
            keepSet.Clear

            ' ---- plates ----
            workSet.Clear
            workSet.AddSet(allPlate.ID)
            workSet.RemoveNotCommon(matSet.ID)
            nPlate = workSet.Count
            If nPlate > 0 Then keepSet.AddSet(workSet.ID)

            ' ---- beams ----
            workSet.Clear
            workSet.AddSet(allBeam.ID)
            workSet.RemoveNotCommon(matSet.ID)
            nBeam = workSet.Count
            If nBeam > 0 Then keepSet.AddSet(workSet.ID)

            ' ---- free-face solids ----
            workSet.Clear
            workSet.AddSet(freeSolid.ID)
            workSet.RemoveNotCommon(matSet.ID)
            nSolid = workSet.Count
            If nSolid > 0 Then keepSet.AddSet(workSet.ID)

            ' how many solids this material has in total, for the ratio
            workSet.Clear
            workSet.AddSet(allSolid.ID)
            workSet.RemoveNotCommon(matSet.ID)
            nSolidAll = workSet.Count

            ' ---- the rigid exclusion ----
            ' In combined mode the exclusion is applied once to the union after
            ' the loop instead. Removing an element is idempotent, so per
            ' material and once at the end give the same answer - but doing it
            ' at the end means the per-material counts printed here are the
            ' pre-exclusion contributions, which is what makes them add up.
            nRemoved = 0
            If Not bCombine Then
                nBefore = keepSet.Count
                If bRigid And rigidBand.Count > 0 Then
                    keepSet.RemoveSet(rigidBand.ID)
                End If
                nRemoved = nBefore - keepSet.Count
            End If

            App.feAppMessage(FCM_NORMAL, "  plates            : " & Str$(nPlate))
            App.feAppMessage(FCM_NORMAL, "  beams             : " & Str$(nBeam))
            App.feAppMessage(FCM_NORMAL, "  free-face solids  : " & Str$(nSolid) & _
                "   (of " & Str$(nSolidAll) & " solids in this material)")
            If Not bCombine Then
                App.feAppMessage(FCM_NORMAL, "  removed at rigids : " & Str$(nRemoved))
            End If

            If bCombine Then
                combinedSet.AddSet(keepSet.ID)
                App.feAppMessage(FCM_NORMAL, "  contributes       : " & Str$(keepSet.Count) & _
                    "   (running union " & Str$(combinedSet.Count) & ")")
            ElseIf keepSet.Count = 0 Then
                App.feAppMessage(FCM_WARNING, "  nothing left to report on - no group created")
            Else
                ' ---- create the group ----
                ' SetAdd builds selection RULES on the in-memory object, so it
                ' must come BEFORE Put, and feGroupEvaluate forces the rules to
                ' materialise. Put first and the group comes out empty.
                gName = prefix & " - " & mTitle
                gid = gp.NextEmptyID
                gp.title = gName
                gp.SetAdd(FT_ELEM, keepSet.ID)
                rc = gp.Put(gid)
                If rc <> FE_OK Then
                    App.feAppMessage(FCM_ERROR, "  group Put failed, rc=" & Str$(rc))
                Else
                    App.feGroupEvaluate(-gid, True)
                    App.feAppMessage(FCM_NORMAL, "  GROUP " & Str$(gid) & " """ & gName & _
                        """ : " & Str$(keepSet.Count) & " elements")
                    nMade = nMade + 1
                End If
            End If
        End If

        matID = mtSet.Next()
    Loop

    ' ============================================================
    ' Section 6: The combined group, if that is what was asked for
    ' ============================================================
    ' The rigid exclusion is applied ONCE here rather than per material. An
    ' element attached to a rigid has to come out regardless of which material
    ' contributed it, and a material boundary is not a reason to keep it.
    If bCombine Then
        nBefore = combinedSet.Count
        If bRigid And rigidBand.Count > 0 Then
            combinedSet.RemoveSet(rigidBand.ID)
        End If
        nRemoved = nBefore - combinedSet.Count

        App.feAppMessage(FCM_NORMAL, "")
        App.feAppMessage(FCM_NORMAL, "COMBINED")
        App.feAppMessage(FCM_NORMAL, "  union of all materials : " & Str$(nBefore))
        App.feAppMessage(FCM_NORMAL, "  removed at rigids      : " & Str$(nRemoved))

        If combinedSet.Count = 0 Then
            App.feAppMessage(FCM_WARNING, "  nothing left to report on - no group created")
        Else
            gName = prefix
            gid = gp.NextEmptyID
            gp.title = gName
            gp.SetAdd(FT_ELEM, combinedSet.ID)
            rc = gp.Put(gid)
            If rc <> FE_OK Then
                App.feAppMessage(FCM_ERROR, "  group Put failed, rc=" & Str$(rc))
            Else
                App.feGroupEvaluate(-gid, True)
                App.feAppMessage(FCM_NORMAL, "  GROUP " & Str$(gid) & " """ & gName & _
                    """ : " & Str$(combinedSet.Count) & " elements")
                nMade = nMade + 1
            End If
        End If
    End If

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "Done. " & Str$(nMade) & " group(s) created.")
    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feViewRegenerate(0)

End Sub
