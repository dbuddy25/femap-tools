' export-contact-cards.bas
' Exports BSURF/BGSET/BGADD bulk data cards for glued contact connectors
' to a Nastran BDF include file.

Function FormatField(s As String, w As Long) As String
    If Len(s) >= w Then
        FormatField = Left$(s, w)
    Else
        FormatField = s + Space$(w - Len(s))
    End If
End Function

Function FormatInt(n As Long, w As Long) As String
    Dim s As String
    s = CStr(n)
    If Len(s) >= w Then
        FormatInt = s
    Else
        FormatInt = Space$(w - Len(s)) + s
    End If
End Function

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long

    ' =============================================
    ' Section 1: Find Glued Connectors
    ' =============================================
    Dim cn As femap.Connection
    Set cn = App.feConnection
    Dim cp As femap.ConnectionProp
    Set cp = App.feConnectionProp

    Dim allConnSet As femap.Set
    Set allConnSet = App.feSet
    allConnSet.AddAll(FT_CONNECTION)

    If allConnSet.Count = 0 Then
        App.feAppMessage(FCM_ERROR, "No connectors found in model - exiting")
        Exit Sub
    End If

    ' Filter to glued connectors only
    Dim gluedSet As femap.Set
    Set gluedSet = App.feSet
    Dim cID As Long
    cID = allConnSet.First()
    Do While cID > 0
        rc = cn.Get(cID)
        If rc = FE_OK Then
            rc = cp.Get(cn.propID)
            If rc = FE_OK Then
                If cp.type = 1 Then gluedSet.Add(cID)
            End If
        End If
        cID = allConnSet.Next()
    Loop

    If gluedSet.Count = 0 Then
        App.feAppMessage(FCM_ERROR, "No glued connectors found - exiting")
        Exit Sub
    End If

    ' =============================================
    ' Section 2: User Selection
    ' =============================================
    rc = gluedSet.Select(FT_CONNECTION, False, "Select Glued Connectors to Export")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Selection cancelled - exiting")
        Exit Sub
    End If

    If gluedSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "No connectors selected - exiting")
        Exit Sub
    End If

    ' =============================================
    ' Section 3: Collect Region Data
    ' =============================================
    Dim cr As femap.ConnectionRegion
    Set cr = App.feConnectionRegion

    Dim numConn As Long
    numConn = gluedSet.Count

    ' Connector arrays
    Dim connIDs() As Long
    Dim connTitles() As String
    Dim connRgn0() As Long
    Dim connRgn1() As Long
    ReDim connIDs(numConn - 1)
    ReDim connTitles(numConn - 1)
    ReDim connRgn0(numConn - 1)
    ReDim connRgn1(numConn - 1)

    ' Collect unique region IDs
    Dim rgnSet As femap.Set
    Set rgnSet = App.feSet

    Dim ci As Long
    ci = 0
    cID = gluedSet.First()
    Do While cID > 0
        rc = cn.Get(cID)
        If rc = FE_OK Then
            connIDs(ci) = cID
            connTitles(ci) = cn.title
            connRgn0(ci) = cn.contact(0)
            connRgn1(ci) = cn.contact(1)
            rgnSet.Add(cn.contact(0))
            rgnSet.Add(cn.contact(1))
        End If
        ci = ci + 1
        cID = gluedSet.Next()
    Loop

    ' Collect region data
    Dim numRgn As Long
    numRgn = rgnSet.Count
    Dim rgnIDs() As Long
    Dim rgnTitles() As String
    Dim rgnElemCounts() As Long
    ReDim rgnIDs(numRgn - 1)
    ReDim rgnTitles(numRgn - 1)
    ReDim rgnElemCounts(numRgn - 1)

    ' Store element sets per region for BDF writing
    ' Use parallel arrays of element ID arrays
    Dim rgnElemIDs() As Variant
    ReDim rgnElemIDs(numRgn - 1)

    Dim ri As Long
    ri = 0
    Dim rID As Long
    Dim hasWarning As Boolean
    hasWarning = False

    rID = rgnSet.First()
    Do While rID > 0
        rgnIDs(ri) = rID
        rc = cr.Get(rID)
        If rc = FE_OK Then
            rgnTitles(ri) = cr.title

            Dim elemSet As femap.Set
            Set elemSet = cr.GetEntitySet(FT_ELEM, True)
            If elemSet Is Nothing Then
                rgnElemCounts(ri) = 0
            Else
                rgnElemCounts(ri) = elemSet.Count
            End If

            If rgnElemCounts(ri) = 0 Then
                hasWarning = True
                App.feAppMessage(FCM_WARNING, "Region " + Str$(rID) + " """ + _
                    cr.title + """ has 0 elements (unmeshed geometry?)")
            Else
                ' Store element IDs for BDF writing
                Dim eIDs() As Long
                ReDim eIDs(rgnElemCounts(ri) - 1)
                Dim eIdx As Long
                eIdx = 0
                Dim eID As Long
                eID = elemSet.First()
                Do While eID > 0
                    eIDs(eIdx) = eID
                    eIdx = eIdx + 1
                    eID = elemSet.Next()
                Loop
                rgnElemIDs(ri) = eIDs
            End If
        Else
            rgnTitles(ri) = "Region " + Str$(rID)
            rgnElemCounts(ri) = 0
            hasWarning = True
            App.feAppMessage(FCM_WARNING, "Failed to read region" + Str$(rID))
        End If

        ri = ri + 1
        rID = rgnSet.Next()
    Loop

    ' =============================================
    ' Section 4: File Save Dialog
    ' =============================================
    Dim fName As String
    rc = App.feFileGetName("Save Contact BDF File", "Nastran BDF", "*.bdf", False, fName)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "File save cancelled - exiting")
        Exit Sub
    End If

    ' Append .bdf if missing
    If LCase$(Right$(fName, 4)) <> ".bdf" Then
        fName = fName + ".bdf"
    End If

    ' =============================================
    ' Section 5: Write BDF File
    ' =============================================
    Dim fNum As Long
    fNum = FreeFile
    Open fName For Output As #fNum

    Print #fNum, "$ Contact bulk data exported from Femap"
    Print #fNum, "$"

    ' --- BSURF cards (one per region) ---
    Dim r As Long
    For r = 0 To numRgn - 1
        If rgnElemCounts(r) = 0 Then GoTo NextBSURF

        Print #fNum, "$ Region: " + rgnTitles(r)
        Dim eArr As Variant
        eArr = rgnElemIDs(r)
        Dim nElems As Long
        nElems = rgnElemCounts(r)

        ' First line: BSURF + SID + up to 6 EIDs (fields 3-8)
        ' Continuation lines: 8-blank prefix + up to 8 EIDs
        Dim bLine As String
        bLine = FormatField("BSURF", 8) + FormatInt(rgnIDs(r), 8)
        Dim ePos As Long
        Dim lineElems As Long
        Dim onFirstLine As Boolean
        lineElems = 0
        onFirstLine = True

        For ePos = 0 To nElems - 1
            If lineElems = 0 And Not onFirstLine Then
                bLine = Space$(8)
            End If
            bLine = bLine + FormatInt(eArr(ePos), 8)
            lineElems = lineElems + 1

            Dim maxThisLine As Long
            If onFirstLine Then maxThisLine = 6 Else maxThisLine = 8

            If lineElems = maxThisLine Or ePos = nElems - 1 Then
                Print #fNum, bLine
                bLine = ""
                lineElems = 0
                onFirstLine = False
            End If
        Next ePos

NextBSURF:
    Next r

    Print #fNum, "$"

    ' --- BGSET cards (one per connector) ---
    Dim maxConnID As Long
    maxConnID = 0
    For ci = 0 To numConn - 1
        Print #fNum, "$ Connector: " + connTitles(ci)
        Dim bgLine As String
        bgLine = FormatField("BGSET", 8) + FormatInt(connIDs(ci), 8) + _
                 FormatInt(connRgn0(ci), 8) + FormatInt(connRgn1(ci), 8)
        Print #fNum, bgLine
        If connIDs(ci) > maxConnID Then maxConnID = connIDs(ci)
    Next ci

    ' --- BGADD card (only if >1 connector) ---
    Dim bgaddID As Long
    bgaddID = 0
    If numConn > 1 Then
        bgaddID = maxConnID + 100
        Print #fNum, "$"

        Dim baLine As String
        baLine = FormatField("BGADD", 8) + FormatInt(bgaddID, 8)
        Dim baCount As Long
        Dim baFirstLine As Boolean
        baCount = 0
        baFirstLine = True
        For ci = 0 To numConn - 1
            If baCount = 0 And Not baFirstLine Then
                baLine = Space$(8)
            End If
            baLine = baLine + FormatInt(connIDs(ci), 8)
            baCount = baCount + 1

            Dim baMax As Long
            If baFirstLine Then baMax = 6 Else baMax = 8

            If baCount = baMax Or ci = numConn - 1 Then
                Print #fNum, baLine
                baLine = ""
                baCount = 0
                baFirstLine = False
            End If
        Next ci
    End If

    ' --- Case control comment ---
    Print #fNum, "$"
    If numConn = 1 Then
        Print #fNum, "$ Case Control: BGSET = " + CStr(connIDs(0))
    Else
        Print #fNum, "$ Case Control: BGSET = " + CStr(bgaddID)
    End If

    Close #fNum

    ' =============================================
    ' Section 6: Message Pane Summary
    ' =============================================
    ' Calculate column widths
    Dim cTyp As Long, cCnt As Long, cBID As Long
    cTyp = 4   ' "Type"
    cCnt = 8   ' "Elements"
    cBID = 8   ' "BSURF ID"

    For r = 0 To numRgn - 1
        If Len(CStr(rgnElemCounts(r))) > cCnt Then cCnt = Len(CStr(rgnElemCounts(r)))
        If Len(CStr(rgnIDs(r))) > cBID Then cBID = Len(CStr(rgnIDs(r)))
    Next r

    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Export Contact Cards")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")

    Dim rHdr As String
    rHdr = "  " + FormatField("Type", cTyp) + "  " + _
           Right$(Space$(cCnt) + "Elements", cCnt) + "  " + _
           Right$(Space$(cBID) + "BSURF ID", cBID)
    App.feAppMessage(FCM_HIGHLIGHT, rHdr)

    Dim rSep As String
    rSep = "  " + String$(cTyp, "-") + "  " + String$(cCnt, "-") + _
           "  " + String$(cBID, "-")
    App.feAppMessage(FCM_HIGHLIGHT, rSep)

    For r = 0 To numRgn - 1
        App.feAppMessage(FCM_NORMAL, "")
        App.feAppMessage(FCM_HIGHLIGHT, "  " + rgnTitles(r))

        Dim rRow As String
        If rgnElemCounts(r) > 0 Then
            rRow = "  " + FormatField("Elem", cTyp) + "  " + _
                   Right$(Space$(cCnt) + CStr(rgnElemCounts(r)), cCnt) + "  " + _
                   Right$(Space$(cBID) + CStr(rgnIDs(r)), cBID)
        Else
            rRow = "  " + FormatField("Elem", cTyp) + "  " + _
                   Right$(Space$(cCnt) + "0", cCnt) + "  " + _
                   Right$(Space$(cBID) + "(skip)", cBID)
        End If
        App.feAppMessage(FCM_NORMAL, rRow)
    Next r

    ' Connector summary
    App.feAppMessage(FCM_NORMAL, "")
    App.feAppMessage(FCM_HIGHLIGHT, "  Connectors:")
    For ci = 0 To numConn - 1
        ' Find region titles for this connector
        Dim srcTitle As String, tgtTitle As String
        srcTitle = "Region " + CStr(connRgn0(ci))
        tgtTitle = "Region " + CStr(connRgn1(ci))
        For r = 0 To numRgn - 1
            If rgnIDs(r) = connRgn0(ci) Then srcTitle = rgnTitles(r)
            If rgnIDs(r) = connRgn1(ci) Then tgtTitle = rgnTitles(r)
        Next r
        App.feAppMessage(FCM_NORMAL, "  #" + CStr(ci + 1) + " " + srcTitle + _
            " -> " + tgtTitle + " (BGSET " + CStr(connIDs(ci)) + ")")
    Next ci

    ' Case control and file path
    App.feAppMessage(FCM_NORMAL, "")
    If numConn = 1 Then
        App.feAppMessage(FCM_HIGHLIGHT, "  Case Control: BGSET = " + CStr(connIDs(0)))
    Else
        App.feAppMessage(FCM_HIGHLIGHT, "  Case Control: BGSET = " + CStr(bgaddID))
    End If
    App.feAppMessage(FCM_NORMAL, "  File: " + fName)
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
