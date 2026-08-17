' Square Around Holes.bas
' -----------------------------------------------------------------------------
' Pick any number of circles / arcs and drop a SQUARE around each one, lying in
' that circle's own plane, centered on its center, with its four edges TANGENT
' to the circle (side = 2 * radius). The square is created as four curves.
'
' Per selected curve the tool needs three things, all of which Femap can give
' for BOTH native arc/circle curves and solid (imported CAD) curves:
'   - center  -> feCoordCurveCenter
'   - plane   -> fePlaneCurveNormal (returns the plane normal AND a plane X axis)
'   - radius  -> distance from the center to a point on the curve
'                (Curve.ParamToXYZ at s=0.5, i.e. the arc midpoint)
'
' Curve.ArcCircleInfo would hand back center/normal/radius in one call, but it
' is documented to fail on solid curves - which is exactly the case for a hole
' edge on imported geometry - so the three calls above are used instead.
'
' Screening non-circular curves takes a little care. feCoordCurveCenter is
' documented to do NO checking on a solid curve - it assumes whatever it is
' handed is an arc - so a planar spline would return a plausible "center" and
' a meaningless radius. After computing the radius the tool therefore samples
' two more parametric locations on the curve and requires them to be the same
' distance from the center (SameRadius). Anything that fails is counted as
' skipped rather than squared.
'
' ORIENTATION
' A circumscribing square has infinitely many valid rotations about the hole
' axis, so the rotation has to come from somewhere:
'   - Pick a direction vector (feVectorPick). The picked vector is PROJECTED
'     into each hole's plane, so one pick orients a whole bolt pattern even if
'     the holes are not all coplanar.
'   - Or use each hole plane's own X axis (whatever fePlaneCurveNormal reports).
'     Zero extra picks, but the rotation is arbitrary per hole.
' If the picked vector is (near-)parallel to a hole's axis the projection
' collapses and the direction is meaningless. Those holes fall back to the
' plane X axis and are reported separately in the confirm dialog - the tally is
' shown before anything is written, so a bad pick can be cancelled.
'
' SIZE
' Tangent (side = 2R) is the default, but a washer / doubler footprint is
' usually a spec dimension rather than a function of the hole, so the same
' dialog also offers "2R x factor" and an explicit side length.
'
' Assumptions / limits (v1):
'   - Coordinates from the API are global rectangular throughout.
'   - feLinePoints is called with ontoWorkplane = False so the computed 3D
'     corners are used as-is. (feLineRectangle exists and looks perfect for
'     this, but it projects onto the workplane and there is no API function to
'     SET the workplane, so it cannot be aimed at a tilted hole.)
'   - Nothing is done about duplicate/overlapping squares if the same hole is
'     picked twice, or if concentric arcs are both selected.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long

    ' ============================================================
    ' Section 1: Select the circles / arcs
    ' ============================================================
    Dim cSet As femap.Set
    Set cSet = App.feSet

    rc = cSet.Select(FT_CURVE, True, "Select circles / arcs to square")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "No curves selected - exiting")
        Exit Sub
    End If

    Dim nCur As Long
    nCur = cSet.Count
    If nCur = 0 Then
        App.feAppMessage(FCM_ERROR, "No curves selected - exiting")
        Exit Sub
    End If

    Dim curID() As Long
    ReDim curID(nCur - 1)

    Dim sID As Long
    i = 0
    sID = cSet.First()
    Do While sID > 0
        curID(i) = sID
        i = i + 1
        sID = cSet.Next()
    Loop

    App.feAppMessage(FCM_NORMAL, "Selected " + Trim$(Str$(nCur)) + " curve(s)")

    ' ============================================================
    ' Section 2: Options dialog (size rule, orientation source)
    ' ============================================================
    Dim hdrLine As String
    hdrLine = Trim$(Str$(nCur)) + " curve(s) selected"

    Begin Dialog OptDlg 340, 268, "Square Around Holes - Options"
        Text       12, 8,  316, 12, hdrLine
        GroupBox   12, 26, 316, 90, "Square Size"
        OptionGroup .sizeMode
            OptionButton 22, 44, 200, 12, "Tangent to the hole  (side = 2R)"
            OptionButton 22, 66, 120, 12, "2R x factor:"
            OptionButton 22, 90, 120, 12, "Side length:"
        TextBox    150, 64, 90, 12, .factVal
        TextBox    150, 88, 90, 12, .sideVal
        GroupBox   12, 124, 316, 74, "Square Orientation (rotation about the hole axis)"
        OptionGroup .orientMode
            OptionButton 22, 142, 290, 12, "Pick a direction vector (projected into each hole plane)"
            OptionButton 22, 164, 290, 12, "Use each hole plane's own X axis (no extra pick)"
        Text       12, 206, 316, 12, "Next dialog shows the tally before anything is created."
        OKButton    82, 232, 80, 20
        CancelButton 182, 232, 80, 20
    End Dialog

    Dim dlg As OptDlg
    dlg.sizeMode   = 0
    dlg.orientMode = 0
    dlg.factVal    = "1.0"
    dlg.sideVal    = "1.0"

    If Dialog(dlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    Dim sizeMode As Long
    Dim sizeFactor As Double
    Dim fixedSide As Double
    Dim sizeNote As String
    sizeMode   = dlg.sizeMode
    sizeFactor = 1.0
    fixedSide  = 0.0

    If sizeMode = 0 Then
        sizeNote = "tangent (side = 2R)"
    ElseIf sizeMode = 1 Then
        sizeFactor = CDbl(dlg.factVal)
        If sizeFactor <= 0.0 Then
            App.feAppMessage(FCM_ERROR, "Size factor must be greater than zero - exiting")
            Exit Sub
        End If
        sizeNote = "2R x " + Fmt(sizeFactor)
    Else
        fixedSide = CDbl(dlg.sideVal)
        If fixedSide <= 0.0 Then
            App.feAppMessage(FCM_ERROR, "Side length must be greater than zero - exiting")
            Exit Sub
        End If
        sizeNote = "fixed side " + Fmt(fixedSide)
    End If

    ' ============================================================
    ' Section 3: Orientation vector (optional pick)
    ' vecDir always comes back as a unit vector.
    ' ============================================================
    Dim usePicked As Boolean
    Dim vx As Double, vy As Double, vz As Double
    Dim orientNote As String
    usePicked = (dlg.orientMode = 0)
    vx = 0.0 : vy = 0.0 : vz = 0.0

    If usePicked Then
        Dim vecLen As Double
        Dim vBase As Variant, vDir As Variant
        rc = App.feVectorPick("Pick the direction for the square's edges", _
                              True, vecLen, vBase, vDir)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Vector pick cancelled - no changes made")
            Exit Sub
        End If
        vx = CDbl(vDir(0))
        vy = CDbl(vDir(1))
        vz = CDbl(vDir(2))
        orientNote = "picked vector"
    Else
        orientNote = "hole plane X axis"
    End If

    ' ============================================================
    ' Section 4: Resolve every curve to center / axes / radius
    ' Nothing is written to the model in this pass.
    ' ============================================================
    Dim cu As femap.Curve
    Set cu = App.feCurve

    Dim cenX() As Double, cenY() As Double, cenZ() As Double
    Dim axX() As Double,  axY() As Double,  axZ() As Double
    Dim ayX() As Double,  ayY() As Double,  ayZ() As Double
    Dim halfSide() As Double
    Dim radArr() As Double
    Dim curOK() As Boolean
    Dim curFell() As Boolean
    ReDim cenX(nCur - 1)
    ReDim cenY(nCur - 1)
    ReDim cenZ(nCur - 1)
    ReDim axX(nCur - 1)
    ReDim axY(nCur - 1)
    ReDim axZ(nCur - 1)
    ReDim ayX(nCur - 1)
    ReDim ayY(nCur - 1)
    ReDim ayZ(nCur - 1)
    ReDim halfSide(nCur - 1)
    ReDim radArr(nCur - 1)
    ReDim curOK(nCur - 1)
    ReDim curFell(nCur - 1)

    Dim vCen As Variant
    Dim plBase As Variant, plNormal As Variant, plAxis As Variant
    Dim vOnCurve As Variant

    Dim ccx As Double, ccy As Double, ccz As Double
    Dim pnx As Double, pny As Double, pnz As Double
    Dim pax As Double, pay As Double, paz As Double
    Dim ptx As Double, pty As Double, ptz As Double
    Dim ex As Double, ey As Double, ez As Double
    Dim fx As Double, fy As Double, fz As Double
    Dim vlen As Double, vdot As Double, rad As Double

    Dim nGood As Long, nBad As Long, nDegen As Long
    Dim minR As Double, maxR As Double
    Dim stepOK As Boolean
    nGood = 0 : nBad = 0 : nDegen = 0
    minR = 0.0 : maxR = 0.0

    ' Every API call below is assigned to rc on its own line rather than tested
    ' inline. WinWrap can pass an argument ByVal when the call appears inside a
    ' larger expression, which would silently drop these out-params.
    For i = 0 To nCur - 1
        curOK(i)   = False
        curFell(i) = False
        stepOK = True

        ' -- center (works for native arcs/circles AND solid curves) ----------
        rc = App.feCoordCurveCenter(curID(i), vCen)
        If rc <> FE_OK Then stepOK = False

        ' -- plane: normal + a reference X axis in that plane -----------------
        If stepOK Then
            ccx = CDbl(vCen(0)) : ccy = CDbl(vCen(1)) : ccz = CDbl(vCen(2))
            rc = App.fePlaneCurveNormal(curID(i), plBase, plNormal, plAxis)
            If rc <> FE_OK Then stepOK = False
        End If

        If stepOK Then
            pnx = CDbl(plNormal(0)) : pny = CDbl(plNormal(1)) : pnz = CDbl(plNormal(2))
            pax = CDbl(plAxis(0))   : pay = CDbl(plAxis(1))   : paz = CDbl(plAxis(2))
            vlen = Sqr(pnx * pnx + pny * pny + pnz * pnz)
            If vlen > 0.0 Then
                pnx = pnx / vlen : pny = pny / vlen : pnz = pnz / vlen
            Else
                stepOK = False
            End If
        End If

        ' -- radius: distance from the center to a point on the curve ---------
        If stepOK Then
            rc = cu.Get(curID(i))
            If rc <> FE_OK Then stepOK = False
        End If

        If stepOK Then
            rc = cu.ParamToXYZ(0.5, vOnCurve)
            If rc <> FE_OK Then stepOK = False
        End If

        If stepOK Then
            ptx = CDbl(vOnCurve(0)) : pty = CDbl(vOnCurve(1)) : ptz = CDbl(vOnCurve(2))
            rad = Sqr((ptx - ccx) * (ptx - ccx) _
                    + (pty - ccy) * (pty - ccy) _
                    + (ptz - ccz) * (ptz - ccz))
            If rad <= 0.0 Then stepOK = False
        End If

        ' -- circularity check -------------------------------------------------
        ' feCoordCurveCenter is documented to do NO checking on solid curves -
        ' it just assumes whatever it is handed is an arc. A planar spline would
        ' therefore return a "center" and a plane and produce a meaningless
        ' radius. Sample two more parametric locations: on a real arc/circle
        ' every point is the same distance from the center.
        If stepOK Then
            If Not SameRadius(cu, 0.2, ccx, ccy, ccz, rad) Then stepOK = False
        End If
        If stepOK Then
            If Not SameRadius(cu, 0.8, ccx, ccy, ccz, rad) Then stepOK = False
        End If

        ' -- in-plane X direction ---------------------------------------------
        If stepOK Then
            If usePicked Then
                ' Project the picked vector into this hole's plane.
                vdot = vx * pnx + vy * pny + vz * pnz
                ex = vx - vdot * pnx
                ey = vy - vdot * pny
                ez = vz - vdot * pnz
                vlen = Sqr(ex * ex + ey * ey + ez * ez)
                ' vDir came back as a unit vector, so vlen is sin(angle between
                ' the pick and the hole plane). Below ~3 deg the projected
                ' direction is numerical noise - fall back to the plane axis.
                If vlen < 0.05 Then
                    ex = pax : ey = pay : ez = paz
                    vlen = Sqr(ex * ex + ey * ey + ez * ez)
                    curFell(i) = True
                End If
            Else
                ex = pax : ey = pay : ez = paz
                vlen = Sqr(ex * ex + ey * ey + ez * ez)
            End If
            If vlen > 0.0 Then
                ex = ex / vlen : ey = ey / vlen : ez = ez / vlen
            Else
                stepOK = False
            End If
        End If

        ' -- in-plane Y = normal x X ------------------------------------------
        If stepOK Then
            fx = pny * ez - pnz * ey
            fy = pnz * ex - pnx * ez
            fz = pnx * ey - pny * ex
            vlen = Sqr(fx * fx + fy * fy + fz * fz)
            If vlen > 0.0 Then
                fx = fx / vlen : fy = fy / vlen : fz = fz / vlen
            Else
                stepOK = False
            End If
        End If

        If stepOK Then
            cenX(i) = ccx : cenY(i) = ccy : cenZ(i) = ccz
            axX(i)  = ex  : axY(i)  = ey  : axZ(i)  = ez
            ayX(i)  = fx  : ayY(i)  = fy  : ayZ(i)  = fz
            radArr(i) = rad

            If sizeMode = 0 Then
                halfSide(i) = rad
            ElseIf sizeMode = 1 Then
                halfSide(i) = rad * sizeFactor
            Else
                halfSide(i) = fixedSide * 0.5
            End If

            If nGood = 0 Then
                minR = rad : maxR = rad
            Else
                If rad < minR Then minR = rad
                If rad > maxR Then maxR = rad
            End If
            nGood = nGood + 1
            ' Only count a fallback once the square is actually going to be built.
            If curFell(i) Then nDegen = nDegen + 1
            curOK(i) = True
        Else
            curFell(i) = False
            nBad = nBad + 1
        End If
    Next i

    If nGood = 0 Then
        App.feAppMessage(FCM_ERROR, "None of the selected curves resolved to a circle or arc - nothing created")
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: Confirm dialog with the tally
    ' ============================================================
    Dim cLine1 As String, cLine2 As String, cLine3 As String
    Dim cLine4 As String, cLine5 As String

    cLine1 = "Squares to create:  " + Trim$(Str$(nGood)) + "   (" + Trim$(Str$(nGood * 4)) + " curves)"
    cLine2 = "Size rule:          " + sizeNote
    If sizeMode = 2 Then
        cLine3 = "Hole radii:         " + Fmt(minR) + " to " + Fmt(maxR) + "  (not used for size)"
    Else
        cLine3 = "Hole radii:         " + Fmt(minR) + " to " + Fmt(maxR)
    End If
    cLine4 = "Orientation:        " + orientNote

    cLine5 = ""
    If nBad > 0 Then
        cLine5 = "WARNING: " + Trim$(Str$(nBad)) + " curve(s) are not arcs/circles - skipped."
    End If
    If nDegen > 0 Then
        If cLine5 <> "" Then cLine5 = cLine5 + "  "
        cLine5 = cLine5 + "WARNING: " + Trim$(Str$(nDegen)) _
               + " hole(s) have an axis nearly parallel to the picked vector" _
               + " - those use the hole plane X axis instead."
    End If

    Begin Dialog ConfirmDlg 360, 190, "Square Around Holes - Confirm"
        Text       12, 8,  336, 12, cLine1
        Text       12, 22, 336, 12, cLine2
        Text       12, 36, 336, 12, cLine3
        Text       12, 50, 336, 12, cLine4
        Text       12, 68, 336, 44, cLine5
        Text       12, 118, 336, 12, "Click OK to create the squares, Cancel to abort."
        OKButton    90, 154, 80, 20
        CancelButton 190, 154, 80, 20
    End Dialog

    Dim cdlg As ConfirmDlg
    If Dialog(cdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled by user - no changes made")
        Exit Sub
    End If

    ' ============================================================
    ' Section 6: Create four curves per hole
    ' Corners walk the loop c1 -> c2 -> c3 -> c4 so the four lines close.
    ' ============================================================
    Dim cor(11) As Double        ' four corners, packed x,y,z per corner
    Dim p1(2) As Double
    Dim p2(2) As Double
    Dim vP1 As Variant, vP2 As Variant

    Dim hs As Double
    Dim c As Long, cNext As Long
    Dim madeAll As Boolean
    Dim sqCount As Long, lineFail As Long
    sqCount = 0 : lineFail = 0

    App.feAppLock

    For i = 0 To nCur - 1
        If curOK(i) Then
            hs = halfSide(i)

            cor(0)  = cenX(i) + hs * axX(i) + hs * ayX(i)
            cor(1)  = cenY(i) + hs * axY(i) + hs * ayY(i)
            cor(2)  = cenZ(i) + hs * axZ(i) + hs * ayZ(i)

            cor(3)  = cenX(i) - hs * axX(i) + hs * ayX(i)
            cor(4)  = cenY(i) - hs * axY(i) + hs * ayY(i)
            cor(5)  = cenZ(i) - hs * axZ(i) + hs * ayZ(i)

            cor(6)  = cenX(i) - hs * axX(i) - hs * ayX(i)
            cor(7)  = cenY(i) - hs * axY(i) - hs * ayY(i)
            cor(8)  = cenZ(i) - hs * axZ(i) - hs * ayZ(i)

            cor(9)  = cenX(i) + hs * axX(i) - hs * ayX(i)
            cor(10) = cenY(i) + hs * axY(i) - hs * ayY(i)
            cor(11) = cenZ(i) + hs * axZ(i) - hs * ayZ(i)

            madeAll = True

            For c = 0 To 3
                cNext = (c + 1) Mod 4

                p1(0) = cor(c * 3)
                p1(1) = cor(c * 3 + 1)
                p1(2) = cor(c * 3 + 2)
                p2(0) = cor(cNext * 3)
                p2(1) = cor(cNext * 3 + 1)
                p2(2) = cor(cNext * 3 + 2)

                vP1 = p1
                vP2 = p2

                ' ontoWorkplane = False so the computed 3D corners are used as-is
                rc = App.feLinePoints(False, vP1, vP2, False)
                If rc <> FE_OK Then
                    madeAll = False
                    lineFail = lineFail + 1
                End If
            Next c

            If madeAll Then
                sqCount = sqCount + 1
                App.feAppMessage(FCM_NORMAL, "Curve " + Trim$(Str$(curID(i))) _
                    + ": R = " + Fmt(radArr(i)) _
                    + ", square side " + Fmt(hs * 2.0))
            Else
                App.feAppMessage(FCM_ERROR, "Curve " + Trim$(Str$(curID(i))) _
                    + ": one or more edges failed to create")
            End If
        End If
    Next i

    App.feAppUnlock

    ' ============================================================
    ' Section 7: Re-evaluate the auto-add group
    ' With Group -> Automatic Add on, new curves land in the target group but
    ' the group is left flagged as needing evaluation, so a group-filtered view
    ' will not draw them. Evaluating here makes them appear immediately.
    ' ============================================================
    Dim autoAdd As Long, autoGrp As Long
    autoGrp = 0
    autoAdd = App.Info_GroupAutomaticAdd
    If autoAdd = -1 Then
        autoGrp = App.Info_ActiveID(FT_GROUP)      ' -1 = "Active Group"
    ElseIf autoAdd > 0 Then
        autoGrp = autoAdd                          ' a specific group ID
    End If
    If autoGrp > 0 Then
        ' Negative arg = a single group ID (positive would be a Set of group IDs)
        rc = App.feGroupEvaluate(-autoGrp, True)
        If rc <> FE_OK Then
            App.feAppMessage(FCM_WARNING, "Could not evaluate auto-add group " _
                + Trim$(Str$(autoGrp)) + " - run Group > Operations > Evaluate if the squares don't draw")
        End If
    End If

    ' ============================================================
    ' Section 8: Report
    ' ============================================================
    App.feViewRegenerate(0)

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Square Around Holes - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL, "  Curves selected:       " + Trim$(Str$(nCur)))
    App.feAppMessage(FCM_NORMAL, "  Squares created:       " + Trim$(Str$(sqCount)))
    App.feAppMessage(FCM_NORMAL, "  Curves created:        " + Trim$(Str$(sqCount * 4)))
    App.feAppMessage(FCM_NORMAL, "  Size rule:             " + sizeNote)
    App.feAppMessage(FCM_NORMAL, "  Hole radii:            " + Fmt(minR) + " to " + Fmt(maxR))
    App.feAppMessage(FCM_NORMAL, "  Orientation:           " + orientNote)
    If nBad > 0 Then
        App.feAppMessage(FCM_WARNING, "  Skipped (not arc/circle): " + Trim$(Str$(nBad)))
    End If
    If nDegen > 0 Then
        App.feAppMessage(FCM_WARNING, "  Fell back to plane axis:  " + Trim$(Str$(nDegen)) _
            + "  (hole axis nearly parallel to the picked vector)")
    End If
    If lineFail > 0 Then
        App.feAppMessage(FCM_ERROR, "  Edges that failed:     " + Trim$(Str$(lineFail)))
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub

' -----------------------------------------------------------------------------
' True if the point at parametric location s on the loaded curve sits the same
' distance from (ccx,ccy,ccz) as refRad, within a relative tolerance. Used to
' reject curves that are not actually arcs or circles.
' -----------------------------------------------------------------------------
Function SameRadius(cu As femap.Curve, s As Double, _
                    ccx As Double, ccy As Double, ccz As Double, _
                    refRad As Double) As Boolean
    Dim vXYZ As Variant
    Dim rc As Long
    Dim dx As Double, dy As Double, dz As Double, dr As Double

    SameRadius = False
    rc = cu.ParamToXYZ(s, vXYZ)
    If rc <> FE_OK Then Exit Function

    dx = CDbl(vXYZ(0)) - ccx
    dy = CDbl(vXYZ(1)) - ccy
    dz = CDbl(vXYZ(2)) - ccz
    dr = Sqr(dx * dx + dy * dy + dz * dz)

    If Abs(dr - refRad) <= 0.001 * refRad Then SameRadius = True
End Function

' -----------------------------------------------------------------------------
' Readable number for dialogs and messages. Str$ on a Double emits up to 15
' digits, which overflows a dialog Text control; anything genuinely tiny or
' huge is left in Femap's own notation rather than rounded into "0".
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
