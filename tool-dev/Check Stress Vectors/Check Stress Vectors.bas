' Check Stress Vectors.bas
' -----------------------------------------------------------------------------
' Diagnostic. Answers one question: what do the stress output vectors in THIS
' model actually contain, per element type?
'
' A "peak stress by group" table is one max() away from being trivial. The part
' that is not trivial is knowing which output vector to take the max OF. Every
' element type stores stress in a DIFFERENT vector - plate von Mises top is not
' solid von Mises - and a wrong vector ID does not error. It returns numbers.
' Plausible ones. So this probe reads the vectors before any table is built.
'
' It answers four things that a peak-stress tool cannot be written without:
'
'   1. DO THE IDs RESOLVE? ResultsIDQuery.Plate() and .Solid() return an ID or
'      FE_FAIL. FE_FAIL means the model has no such vector - usually because the
'      solver was never asked for that output. Printed per vector.
'
'   2. WHAT IS IN THE ROWS? A column populates for the whole model, not just the
'      elements the vector applies to. So a plate-von-Mises column may well
'      return rows for solid elements too. This probe counts, for each column,
'      how many nonzero rows belong to plates, to solids, and to neither.
'
'   3. IS THE PADDING ZERO OR GARBAGE? If a plate column pads its solid rows
'      with 0.0, a max() over von Mises is still correct (stress is positive) -
'      but a MIN PRINCIPAL max() is NOT, because a padded 0.0 beats any real
'      compressive value. The probe prints min and max per column so the padding
'      value is visible rather than assumed.
'
'   4. IS VPP_BOT REALLY 3? The plate "ply" enum runs TOP=0, MID=1, BOT=3 - it
'      skips 2. And the Solid() location argument is documented under two
'      different names (VSL_CENTROID in the method, VPL_CENTROID in the constant
'      table). Both are read here as literals so the answer is measured.
'
' HOW TO READ THE OUTPUT
'
'   A vector ID of FAIL          -> that result was not written by the solver.
'                                   Exclude that column from the table, or
'                                   re-run the solve asking for it.
'   Nonzero rows on the WRONG    -> the column is padded across the whole model.
'   element class                   The table must filter rows by element class,
'                                   not just by bucket membership.
'   A min of exactly 0.0 on a    -> the padding is zero. Min-principal columns
'   min-principal column            must skip padded rows or they report 0.
'
' NOTHING IN THE MODEL IS MODIFIED. This is a read-only probe.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long, k As Long

    App.feAppMessage(FCM_NORMAL, "==================================================")
    App.feAppMessage(FCM_NORMAL, "CHECK STRESS VECTORS - read-only probe")
    App.feAppMessage(FCM_NORMAL, "==================================================")

    ' ============================================================
    ' Section 1: Element inventory by class
    ' ============================================================
    ' Built with AddRule(FET_*, FGD_ELEM_BYTYPE) rather than by walking topology
    ' codes, so laminates are counted with their non-laminate kin.
    '
    ' *** THE L IN FET_L_* MEANS LINEAR, NOT "ELEMENT TYPE" ***
    ' Linear and parabolic elements have SEPARATE type codes - FET_L_SOLID is 25
    ' and FET_P_SOLID is 26. Listing only the L half matches tet4/wedge6/brick8
    ' and silently misses every tet10, wedge15 and brick20. Both halves, always.
    Dim plateSet As femap.Set
    Set plateSet = App.feSet
    plateSet.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_P_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_L_LAMINATE_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_P_LAMINATE_PLATE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_L_MEMBRANE, FGD_ELEM_BYTYPE)
    plateSet.AddRule(FET_P_MEMBRANE, FGD_ELEM_BYTYPE)

    Dim solidSet As femap.Set
    Set solidSet = App.feSet
    solidSet.AddRule(FET_L_SOLID, FGD_ELEM_BYTYPE)
    solidSet.AddRule(FET_P_SOLID, FGD_ELEM_BYTYPE)
    solidSet.AddRule(FET_L_LAMINATE_SOLID, FGD_ELEM_BYTYPE)
    solidSet.AddRule(FET_P_LAMINATE_SOLID, FGD_ELEM_BYTYPE)

    Dim lineSet As femap.Set
    Set lineSet = App.feSet
    lineSet.AddRule(FET_L_BEAM, FGD_ELEM_BYTYPE)
    lineSet.AddRule(FET_P_BEAM, FGD_ELEM_BYTYPE)
    lineSet.AddRule(FET_L_BAR, FGD_ELEM_BYTYPE)
    lineSet.AddRule(FET_L_ROD, FGD_ELEM_BYTYPE)

    Dim allSet As femap.Set
    Set allSet = App.feSet
    allSet.AddAll(FT_ELEM)

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "ELEMENT INVENTORY")
    App.feAppMessage(FCM_NORMAL, "  Plate/membrane : " & Str$(plateSet.Count))
    App.feAppMessage(FCM_NORMAL, "  Solid          : " & Str$(solidSet.Count))
    App.feAppMessage(FCM_NORMAL, "  Beam/bar/rod   : " & Str$(lineSet.Count))
    App.feAppMessage(FCM_NORMAL, "  All elements   : " & Str$(allSet.Count))

    If plateSet.Count = 0 And solidSet.Count = 0 Then
        App.feAppMessage(FCM_ERROR, "No plate or solid elements - nothing to probe.")
        Exit Sub
    End If

    ' ============================================================
    ' Section 2: Pick one output set
    ' ============================================================
    Dim osSet As femap.Set
    Set osSet = App.feSet
    rc = osSet.SelectMultiIDV2(FT_OUT_CASE, 1, "Select ONE output set to probe")
    If rc = FE_CANCEL Or osSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim oSetID As Long
    oSetID = osSet.First()

    Dim os As femap.OutputSet
    Set os = App.feOutputSet
    rc = os.Get(oSetID)
    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "OUTPUT SET " & Str$(oSetID) & " : " & os.title)
    If osSet.Count > 1 Then
        App.feAppMessage(FCM_WARNING, "  (" & Str$(osSet.Count) & " selected; probing the first only)")
    End If

    ' ============================================================
    ' Section 3: Resolve the vector IDs
    ' ============================================================
    ' Plate( result, type, ply, location )   ply: TOP=0 MID=1 BOT=3
    ' Solid( result, type, location )        location: centroid=0
    ' Literals are used for ply and location so the enum-name ambiguity
    ' (VSL_CENTROID vs VPL_CENTROID) cannot silently pick the wrong one.
    Dim q As femap.ResultsIDQuery
    Set q = App.feResultsIDQuery

    Dim nVec As Long
    nVec = 9
    Dim vecID(8) As Long
    Dim vecName(8) As String
    Dim vecClass(8) As Long      ' 1 = plate vector, 2 = solid vector
    Dim vecIsMin(8) As Long      ' 1 = min-principal, where zero padding lies

    vecName(0) = "Plate vonMises TOP"    : vecClass(0) = 1 : vecIsMin(0) = 0
    vecID(0) = q.Plate(VPV_STRESS, VPT_VON_MISES, 0, VPL_CENTROID)
    vecName(1) = "Plate vonMises BOT"    : vecClass(1) = 1 : vecIsMin(1) = 0
    vecID(1) = q.Plate(VPV_STRESS, VPT_VON_MISES, 3, VPL_CENTROID)
    vecName(2) = "Plate MaxPrin  TOP"    : vecClass(2) = 1 : vecIsMin(2) = 0
    vecID(2) = q.Plate(VPV_STRESS, VPT_MAX_PRIN, 0, VPL_CENTROID)
    vecName(3) = "Plate MaxPrin  BOT"    : vecClass(3) = 1 : vecIsMin(3) = 0
    vecID(3) = q.Plate(VPV_STRESS, VPT_MAX_PRIN, 3, VPL_CENTROID)
    vecName(4) = "Plate MinPrin  TOP"    : vecClass(4) = 1 : vecIsMin(4) = 1
    vecID(4) = q.Plate(VPV_STRESS, VPT_MIN_PRIN, 0, VPL_CENTROID)
    vecName(5) = "Plate MinPrin  BOT"    : vecClass(5) = 1 : vecIsMin(5) = 1
    vecID(5) = q.Plate(VPV_STRESS, VPT_MIN_PRIN, 3, VPL_CENTROID)
    vecName(6) = "Solid vonMises"        : vecClass(6) = 2 : vecIsMin(6) = 0
    vecID(6) = q.Solid(VSV_STRESS, VST_VON_MISES, 0)
    vecName(7) = "Solid MaxPrin"         : vecClass(7) = 2 : vecIsMin(7) = 0
    vecID(7) = q.Solid(VSV_STRESS, VST_MAX_PRIN, 0)
    vecName(8) = "Solid MinPrin"         : vecClass(8) = 2 : vecIsMin(8) = 1
    vecID(8) = q.Solid(VSV_STRESS, VST_MIN_PRIN, 0)

    ' A cross-check on the ply enum: if BOT really is 3, then ply 2 should NOT
    ' return the same ID as ply 3. Printed rather than trusted.
    Dim plyTwoID As Long
    plyTwoID = q.Plate(VPV_STRESS, VPT_VON_MISES, 2, VPL_CENTROID)

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "VECTOR ID LOOKUP")
    For i = 0 To nVec - 1
        If vecID(i) = FE_FAIL Or vecID(i) <= 0 Then
            App.feAppMessage(FCM_WARNING, "  " & vecName(i) & " : FAIL (not in model)")
        Else
            App.feAppMessage(FCM_NORMAL, "  " & vecName(i) & " : " & Str$(vecID(i)))
        End If
    Next i
    App.feAppMessage(FCM_NORMAL, "  --- ply enum cross-check ---")
    App.feAppMessage(FCM_NORMAL, "  Plate vonMises ply=2 : " & Str$(plyTwoID) & _
        "   (ply=0 TOP was " & Str$(vecID(0)) & ", ply=3 BOT was " & Str$(vecID(1)) & ")")
    App.feAppMessage(FCM_NORMAL, "  If ply=2 equals neither, MID is a real third vector and BOT=3 is right.")

    ' ============================================================
    ' Section 4: Load every resolvable vector into one Results object
    ' ============================================================
    ' All of these are ELEMENTAL vectors, so they can share one object -
    ' AddColumnV2 returns FE_BAD_TYPE if nodal and elemental are mixed.
    Dim rbo As femap.Results
    Set rbo = App.feResults
    rbo.Clear

    Dim colOf(8) As Long
    Dim nAdded As Long, vCols As Variant
    Dim anyAdded As Long
    anyAdded = 0

    For i = 0 To nVec - 1
        colOf(i) = -1
        If vecID(i) > 0 Then
            rc = rbo.AddColumnV2(oSetID, vecID(i), False, nAdded, vCols)
            If rc = FE_OK And nAdded > 0 Then
                colOf(i) = vCols(0)
                anyAdded = anyAdded + 1
            Else
                App.feAppMessage(FCM_WARNING, "  AddColumnV2 refused " & vecName(i) & _
                    "  rc=" & Str$(rc))
            End If
        End If
    Next i

    If anyAdded = 0 Then
        App.feAppMessage(FCM_ERROR, "No stress columns could be added - nothing to measure.")
        Exit Sub
    End If

    rc = rbo.Populate
    If rc <> FE_OK Then
        App.feAppMessage(FCM_ERROR, "Populate failed, rc=" & Str$(rc))
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: Measure each column
    ' ============================================================
    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "COLUMN CONTENTS  (rows = what Populate returned)")
    App.feAppMessage(FCM_NORMAL, "  vector                rows   nz  nzPlate  nzSolid  nzOther")

    Dim vIDs As Variant, vVals As Variant
    Dim nRows As Long
    Dim nNZ As Long, nNZPlate As Long, nNZSolid As Long, nNZOther As Long
    Dim nZero As Long
    Dim vMin As Double, vMax As Double
    Dim idAtMax As Long, idAtMin As Long
    Dim eID As Long, dVal As Double

    For i = 0 To nVec - 1
        If colOf(i) >= 0 Then
            rc = rbo.GetColumn(colOf(i), vIDs, vVals)
            If rc <> FE_OK Then
                App.feAppMessage(FCM_WARNING, "  " & vecName(i) & " : GetColumn rc=" & Str$(rc))
            Else
                nRows = UBound(vVals) - LBound(vVals) + 1
                nNZ = 0 : nNZPlate = 0 : nNZSolid = 0 : nNZOther = 0 : nZero = 0
                vMin = 1.0E30 : vMax = -1.0E30
                idAtMax = 0 : idAtMin = 0

                For k = LBound(vVals) To UBound(vVals)
                    eID = vIDs(k)
                    dVal = vVals(k)
                    If dVal > vMax Then
                        vMax = dVal
                        idAtMax = eID
                    End If
                    If dVal < vMin Then
                        vMin = dVal
                        idAtMin = eID
                    End If
                    If dVal = 0.0 Then
                        nZero = nZero + 1
                    Else
                        nNZ = nNZ + 1
                        If plateSet.IsAdded(eID) Then
                            nNZPlate = nNZPlate + 1
                        ElseIf solidSet.IsAdded(eID) Then
                            nNZSolid = nNZSolid + 1
                        Else
                            nNZOther = nNZOther + 1
                        End If
                    End If
                Next k

                App.feAppMessage(FCM_NORMAL, "  " & vecName(i) & _
                    "  rows=" & Str$(nRows) & "  nz=" & Str$(nNZ) & _
                    "  nzPlate=" & Str$(nNZPlate) & "  nzSolid=" & Str$(nNZSolid) & _
                    "  nzOther=" & Str$(nNZOther))
                App.feAppMessage(FCM_NORMAL, "      max=" & Format$(vMax, "0.000E+00") & _
                    " @elem" & Str$(idAtMax) & "   min=" & Format$(vMin, "0.000E+00") & _
                    " @elem" & Str$(idAtMin) & "   exactZero=" & Str$(nZero))

                ' The specific trap this probe exists to catch.
                If vecIsMin(i) = 1 And nZero > 0 And vMax = 0.0 Then
                    App.feAppMessage(FCM_WARNING, _
                        "      ^ min-principal column is padded with 0.0 and 0.0 is its max." & _
                        " A naive max() here would report 0. Filter by element class.")
                End If
                If vecClass(i) = 1 And nNZSolid > 0 Then
                    App.feAppMessage(FCM_WARNING, _
                        "      ^ PLATE vector has nonzero values on SOLID elements. Do not trust" & _
                        " bucket membership alone - filter rows by element class.")
                End If
                If vecClass(i) = 2 And nNZPlate > 0 Then
                    App.feAppMessage(FCM_WARNING, _
                        "      ^ SOLID vector has nonzero values on PLATE elements. Do not trust" & _
                        " bucket membership alone - filter rows by element class.")
                End If
            End If
        End If
    Next i

    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_NORMAL, "Probe complete. Nothing was modified.")
    App.feAppMessage(FCM_NORMAL, "==================================================")

End Sub
