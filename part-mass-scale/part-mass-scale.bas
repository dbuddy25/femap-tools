' part-mass-scale.bas
' Scales the mass of user-selected elements by modifying material densities
' and CONM2 mass values.
' Includes verification step comparing recalculated mass against expected scaled mass.

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Element Selection
    ' =============================================
    Dim elemSet As femap.Set
    Set elemSet = App.feSet

    rc = elemSet.Select(FT_ELEM, True, "Select Elements to Scale Mass")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No elements selected - exiting")
        Exit Sub
    End If

    If elemSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Empty selection - exiting")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Selected " + Str$(elemSet.Count) + " elements")

    ' =============================================
    ' Section 2: Calculate Original Mass
    ' =============================================
    Dim len0 As Double
    Dim area0 As Double
    Dim volume0 As Double
    Dim structMass0 As Double
    Dim nonstructMass0 As Double
    Dim totalMass0 As Double
    Dim structCG0 As Variant
    Dim nonstructCG0 As Variant
    Dim totalCG0 As Variant
    Dim inertia0 As Variant
    Dim inertiaCG0 As Variant

    rc = App.feMeasureMeshMassProp(elemSet.ID, 0, False, False, _
        len0, area0, volume0, structMass0, nonstructMass0, totalMass0, _
        structCG0, nonstructCG0, totalCG0, inertia0, inertiaCG0)

    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to calculate mass properties")
        Exit Sub
    End If

    App.feAppMessage(FCM_NORMAL, "Original Total Mass:         " + Format$(totalMass0, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Structural Mass:           " + Format$(structMass0, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Non-structural Mass:       " + Format$(nonstructMass0, "0.0000E+00"))

    If totalMass0 <= 0 Then
        App.feAppMessage(FCM_ERROR, "Total mass is zero or negative - nothing to scale")
        Exit Sub
    End If

    ' =============================================
    ' Section 3: Scale Factor Dialog
    ' =============================================
    Begin Dialog ScaleDialog 300, 100, "Part Mass Scale"
        Text 10, 10, 280, 14, "Original Total Mass: " + Format$(totalMass0, "0.0000E+00")
        Text 10, 30, 100, 14, "Scale Factor:"
        TextBox 120, 28, 80, 14, .scaleFactor
        OKButton 60, 70, 80, 22
        CancelButton 160, 70, 80, 22
    End Dialog

    Dim dlg As ScaleDialog
    dlg.scaleFactor = "1.0"

    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "User cancelled - no changes made")
        Exit Sub
    End If

    Dim scaleFactor As Double
    scaleFactor = CDbl(dlg.scaleFactor)

    If scaleFactor <= 0 Then
        App.feAppMessage(FCM_ERROR, "Scale factor must be greater than zero")
        Exit Sub
    End If

    Dim expectedMass As Double
    expectedMass = totalMass0 * scaleFactor

    App.feAppMessage(FCM_NORMAL, "Scale Factor: " + Format$(scaleFactor, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "Expected Mass: " + Format$(expectedMass, "0.0000E+00"))

    ' =============================================
    ' Section 4: Classify Properties from Selection
    ' =============================================
    Dim el As femap.Elem
    Set el = App.feElem
    Dim pr As femap.Prop
    Set pr = App.feProp

    ' Collect unique property IDs from selected elements
    Dim propSet As femap.Set
    Set propSet = App.feSet
    ' Unique material IDs to scale density
    Dim matlSet As femap.Set
    Set matlSet = App.feSet
    ' CONM2 property IDs to scale mass
    Dim massPropSet As femap.Set
    Set massPropSet = App.feSet
    ' Structural properties with nonzero NSM to scale
    Dim nsmPropSet As femap.Set
    Set nsmPropSet = App.feSet
    ' PCOMP properties (for sharing check — ply materials live on shared Layup)
    Dim pcompPropSet As femap.Set
    Set pcompPropSet = App.feSet
    ' Layup object for reading PCOMP ply materials
    Dim ly As femap.Layup
    Set ly = App.feLayup
    Dim ply As Long

    Dim id As Long
    id = elemSet.First()
    Do While id > 0
        rc = el.Get(id)
        If rc = FE_OK Then propSet.Add(el.propID)
        id = elemSet.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Found " + Str$(propSet.Count) + " unique property/properties from " + Str$(elemSet.Count) + " elements")

    ' Classify each unique property
    Dim propID As Long
    Dim classification As String
    propID = propSet.First()
    Do While propID > 0
        rc = pr.Get(propID)
        If rc = FE_OK Then
            If pr.type = FET_L_MASS Then
                massPropSet.Add(propID)
                classification = "CONM2"
            Else
                If pr.matlID > 0 Then
                    matlSet.Add(pr.matlID)
                End If
                ' Add PCOMP ply materials via Layup object
                If (pr.type = 21 Or pr.type = 22) And pr.layupID > 0 Then
                    pcompPropSet.Add(propID)
                    rc = ly.Get(pr.layupID)
                    If rc = FE_OK Then
                        For ply = 0 To ly.NumberOfPlys - 1
                            If ly.matlID(ply) > 0 Then
                                matlSet.Add(ly.matlID(ply))
                            End If
                        Next ply
                        classification = "PCOMP (layupID=" + Str$(pr.layupID) + ", plies=" + Str$(ly.NumberOfPlys) + ")"
                    Else
                        classification = "PCOMP (layupID=" + Str$(pr.layupID) + ", layup read FAILED)"
                    End If
                Else
                    classification = "STRUCT (matlID=" + Str$(pr.matlID) + ")"
                End If
                ' Check for non-structural mass (NSM)
                Select Case pr.type
                    Case 1, 2, 3, 5, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
                        If pr.pval(7) <> 0 Then nsmPropSet.Add(propID)
                        If pr.type = 5 And pr.pval(27) <> 0 Then nsmPropSet.Add(propID)
                    Case 21, 22
                        If pr.pval(1) <> 0 Then nsmPropSet.Add(propID)
                End Select
            End If
        End If
        propID = propSet.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Found " + Str$(matlSet.Count) + " unique material(s)")
    App.feAppMessage(FCM_NORMAL, "Found " + Str$(massPropSet.Count) + " CONM2 property/properties")
    App.feAppMessage(FCM_NORMAL, "Found " + Str$(nsmPropSet.Count) + " property/properties with NSM")
    If pcompPropSet.Count > 0 Then
        App.feAppMessage(FCM_NORMAL, "Found " + Str$(pcompPropSet.Count) + " PCOMP property/properties (ply materials via layup)")
    End If

    ' =============================================
    ' Section 5: Check for Shared Materials/Properties
    ' =============================================
    Dim hasShared As Boolean
    hasShared = False
    Dim warningMsg As String
    warningMsg = "WARNING: The following are shared with elements outside your selection:" _
        + Chr$(10) + Chr$(10)

    ' Reusable sets for checking
    Dim allByRule As femap.Set
    Set allByRule = App.feSet
    Dim checkSet As femap.Set
    Set checkSet = App.feSet

    ' Check materials
    Dim matlID As Long
    matlID = matlSet.First()
    Do While matlID > 0
        allByRule.Clear()
        allByRule.AddRule(matlID, FGD_ELEM_BYMATL)
        checkSet.Clear()
        checkSet.AddSet(allByRule.ID)
        checkSet.RemoveSet(elemSet.ID)
        If checkSet.Count > 0 Then
            hasShared = True
            warningMsg = warningMsg + "  Material " + Str$(matlID) + _
                " shared with " + Str$(checkSet.Count) + " other element(s)" + Chr$(10)
        End If
        matlID = matlSet.Next()
    Loop

    ' Check CONM2 properties
    propID = massPropSet.First()
    Do While propID > 0
        allByRule.Clear()
        allByRule.AddRule(propID, FGD_ELEM_BYPROP)
        checkSet.Clear()
        checkSet.AddSet(allByRule.ID)
        checkSet.RemoveSet(elemSet.ID)
        If checkSet.Count > 0 Then
            hasShared = True
            warningMsg = warningMsg + "  CONM2 Property " + Str$(propID) + _
                " shared with " + Str$(checkSet.Count) + " other element(s)" + Chr$(10)
        End If
        propID = massPropSet.Next()
    Loop

    ' Check NSM properties
    propID = nsmPropSet.First()
    Do While propID > 0
        allByRule.Clear()
        allByRule.AddRule(propID, FGD_ELEM_BYPROP)
        checkSet.Clear()
        checkSet.AddSet(allByRule.ID)
        checkSet.RemoveSet(elemSet.ID)
        If checkSet.Count > 0 Then
            hasShared = True
            warningMsg = warningMsg + "  Property " + Str$(propID) + _
                " (NSM) shared with " + Str$(checkSet.Count) + " other element(s)" + Chr$(10)
        End If
        propID = nsmPropSet.Next()
    Loop

    ' Check PCOMP properties (ply materials are shared via layup)
    propID = pcompPropSet.First()
    Do While propID > 0
        allByRule.Clear()
        allByRule.AddRule(propID, FGD_ELEM_BYPROP)
        checkSet.Clear()
        checkSet.AddSet(allByRule.ID)
        checkSet.RemoveSet(elemSet.ID)
        If checkSet.Count > 0 Then
            hasShared = True
            warningMsg = warningMsg + "  PCOMP Property " + Str$(propID) + _
                " (ply materials) shared with " + Str$(checkSet.Count) + " other element(s)" + Chr$(10)
        End If
        propID = pcompPropSet.Next()
    Loop

    If hasShared Then
        warningMsg = warningMsg + Chr$(10) + _
            "Scaling these will affect ALL elements using them." + Chr$(10) + _
            "Do you want to proceed?"
        Dim response As Long
        response = App.feAppMessageBox(4, warningMsg)
        If response <> 6 Then   ' 6 = Yes
            App.feAppMessage(FCM_WARNING, "User cancelled - no changes made")
            Exit Sub
        End If
    End If

    ' =============================================
    ' Section 6: Apply Scaling
    ' =============================================
    ' 6a. Scale material densities
    Dim mt As femap.Matl
    Set mt = App.feMatl
    Dim matlCount As Long
    matlCount = 0

    matlID = matlSet.First()
    Do While matlID > 0
        rc = mt.Get(matlID)
        If rc = FE_OK Then
            mt.mval(49) = mt.mval(49) * scaleFactor   ' DENSITY (API PDF 5-875)
            rc = mt.Put(matlID)
            If rc = FE_OK Then matlCount = matlCount + 1
        End If
        matlID = matlSet.Next()
    Loop

    ' 6b. Scale NSM on structural properties
    Dim nsmCount As Long
    nsmCount = 0

    propID = nsmPropSet.First()
    Do While propID > 0
        rc = pr.Get(propID)
        If rc = FE_OK Then
            ' pval(7) = NSM for types 1-5, 8, 11-20
            If pr.type <= 20 Or pr.type = 8 Then
                pr.pval(7) = pr.pval(7) * scaleFactor
            End If
            ' Beam End B: pval(27) = NSM_B
            If pr.type = 5 Then
                pr.pval(27) = pr.pval(27) * scaleFactor
            End If
            ' Laminate: pval(1) = NSM
            If pr.type = 21 Or pr.type = 22 Then
                pr.pval(1) = pr.pval(1) * scaleFactor
            End If
            rc = pr.Put(propID)
            If rc = FE_OK Then nsmCount = nsmCount + 1
        End If
        propID = nsmPropSet.Next()
    Loop

    ' 6c. Scale CONM2 mass properties (property type 27)
    Dim massCount As Long
    massCount = 0

    propID = massPropSet.First()
    Do While propID > 0
        rc = pr.Get(propID)
        If rc = FE_OK Then
            pr.pval(1) = pr.pval(1) * scaleFactor    ' I11 (Ixx)
            pr.pval(2) = pr.pval(2) * scaleFactor    ' I21 (Ixy)
            pr.pval(3) = pr.pval(3) * scaleFactor    ' I22 (Iyy)
            pr.pval(4) = pr.pval(4) * scaleFactor    ' I31 (Izx)
            pr.pval(5) = pr.pval(5) * scaleFactor    ' I32 (Iyz)
            pr.pval(6) = pr.pval(6) * scaleFactor    ' I33 (Izz)
            pr.pval(7) = pr.pval(7) * scaleFactor    ' Mx
            pr.pval(11) = pr.pval(11) * scaleFactor   ' My
            pr.pval(12) = pr.pval(12) * scaleFactor   ' Mz
            rc = pr.Put(propID)
            If rc = FE_OK Then massCount = massCount + 1
        End If
        propID = massPropSet.Next()
    Loop

    ' 6d. Detect Connection Region NSM (report only, not auto-scaled)
    Dim cr As femap.ConnectionRegion
    Set cr = App.feConnectionRegion
    Dim crNsmCount As Long
    crNsmCount = 0

    Dim crID As Long
    crID = cr.First()
    Do While crID > 0
        rc = cr.Get(crID)
        If rc = FE_OK Then
            If cr.MassNSM <> 0 Then crNsmCount = crNsmCount + 1
        End If
        crID = cr.Next()
    Loop

    App.feViewRegenerate(0)

    App.feAppMessage(FCM_NORMAL, "Scaled " + Str$(matlCount) + " material density/densities")
    App.feAppMessage(FCM_NORMAL, "Scaled " + Str$(nsmCount) + " NSM property/properties")
    App.feAppMessage(FCM_NORMAL, "Scaled " + Str$(massCount) + " CONM2 mass property/properties")
    If crNsmCount > 0 Then
        App.feAppMessage(FCM_WARNING, "Note: " + Str$(crNsmCount) + " Connection Region(s) with NSM found - not auto-scaled")
    End If

    ' =============================================
    ' Section 7: Verification
    ' =============================================
    Dim len1 As Double
    Dim area1 As Double
    Dim volume1 As Double
    Dim structMass1 As Double
    Dim nonstructMass1 As Double
    Dim totalMass1 As Double
    Dim structCG1 As Variant
    Dim nonstructCG1 As Variant
    Dim totalCG1 As Variant
    Dim inertia1 As Variant
    Dim inertiaCG1 As Variant

    rc = App.feMeasureMeshMassProp(elemSet.ID, 0, False, False, _
        len1, area1, volume1, structMass1, nonstructMass1, totalMass1, _
        structCG1, nonstructCG1, totalCG1, inertia1, inertiaCG1)

    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Failed to recalculate mass properties for verification")
        Exit Sub
    End If

    ' Per-category % differences
    Dim pctDiffTotal As Double
    pctDiffTotal = (totalMass1 - expectedMass) / expectedMass * 100.0

    Dim pctDiffStruct As Double
    If structMass0 > 0 Then
        pctDiffStruct = (structMass1 - structMass0 * scaleFactor) / (structMass0 * scaleFactor) * 100.0
    Else
        pctDiffStruct = 0
    End If

    Dim pctDiffNonstruct As Double
    If nonstructMass0 > 0 Then
        pctDiffNonstruct = (nonstructMass1 - nonstructMass0 * scaleFactor) / (nonstructMass0 * scaleFactor) * 100.0
    Else
        pctDiffNonstruct = 0
    End If

    ' Per-category CG shifts
    Dim cgDist As Double
    cgDist = Sqr((totalCG1(0)-totalCG0(0))^2 + (totalCG1(1)-totalCG0(1))^2 + (totalCG1(2)-totalCG0(2))^2)

    Dim cgDistStruct As Double
    If structMass0 > 0 Then
        cgDistStruct = Sqr((structCG1(0)-structCG0(0))^2 + (structCG1(1)-structCG0(1))^2 + (structCG1(2)-structCG0(2))^2)
    Else
        cgDistStruct = 0
    End If

    Dim cgDistNonstruct As Double
    If nonstructMass0 > 0 Then
        cgDistNonstruct = Sqr((nonstructCG1(0)-nonstructCG0(0))^2 + (nonstructCG1(1)-nonstructCG0(1))^2 + (nonstructCG1(2)-nonstructCG0(2))^2)
    Else
        cgDistNonstruct = 0
    End If

    ' Display results summary
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Part Mass Scale - Results Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Original Total Mass:       " + Format$(totalMass0, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Scale Factor:              " + Format$(scaleFactor, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Expected Total Mass:       " + Format$(expectedMass, "0.0000E+00"))
    App.feAppMessage(FCM_NORMAL, "  Actual Total Mass:         " + Format$(totalMass1, "0.0000E+00"))
    If structMass0 > 0 Then
        App.feAppMessage(FCM_NORMAL, "    Structural:              " + Format$(structMass1, "0.0000E+00") + _
            "  (diff: " + Format$(pctDiffStruct, "0.000") + " %%, CG shift: " + Format$(cgDistStruct, "0.0000E+00") + ")")
    End If
    If nonstructMass0 > 0 Then
        App.feAppMessage(FCM_NORMAL, "    Non-structural:          " + Format$(nonstructMass1, "0.0000E+00") + _
            "  (diff: " + Format$(pctDiffNonstruct, "0.000") + " %%, CG shift: " + Format$(cgDistNonstruct, "0.0000E+00") + ")")
    End If
    App.feAppMessage(FCM_NORMAL, "  Total Difference:          " + Format$(pctDiffTotal, "0.000") + " %%")
    App.feAppMessage(FCM_NORMAL, "  Total CG Shift:            " + Format$(cgDist, "0.0000E+00"))

    If crNsmCount > 0 Then
        App.feAppMessage(FCM_WARNING, "  ConnRegion NSM:            " + Str$(crNsmCount) + " region(s) not auto-scaled")
    End If

    ' PASS/FAIL uses worst of per-category diffs and CG shifts
    Dim maxDiff As Double
    maxDiff = Abs(pctDiffTotal)
    If structMass0 > 0 And Abs(pctDiffStruct) > maxDiff Then maxDiff = Abs(pctDiffStruct)
    If nonstructMass0 > 0 And Abs(pctDiffNonstruct) > maxDiff Then maxDiff = Abs(pctDiffNonstruct)

    Dim maxCgShift As Double
    maxCgShift = cgDist
    If cgDistStruct > maxCgShift Then maxCgShift = cgDistStruct
    If cgDistNonstruct > maxCgShift Then maxCgShift = cgDistNonstruct

    If maxDiff < 0.01 And maxCgShift < 1e-6 Then
        App.feAppMessage(FCM_HIGHLIGHT, "  Result: PASS")
    ElseIf maxDiff < 1.0 Then
        App.feAppMessage(FCM_WARNING, "  Result: MARGINAL (worst diff: " + Format$(maxDiff, "0.000") + "%%)")
    Else
        App.feAppMessage(FCM_ERROR, "  Result: FAIL (worst diff: " + Format$(maxDiff, "0.000") + "%%)")
        App.feAppMessage(FCM_ERROR, "  This may indicate unscaled mass contributions")
    End If

    If maxCgShift >= 1e-6 Then
        App.feAppMessage(FCM_WARNING, "  CG shifted by " + Format$(maxCgShift, "0.0000E+00") + " — check for non-uniform scaling")
    End If

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
