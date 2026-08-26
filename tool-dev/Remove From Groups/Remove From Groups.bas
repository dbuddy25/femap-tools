' Remove From Groups.bas
' -----------------------------------------------------------------------------
' Pick entities once, see every group that currently contains them, and remove
' them from the groups you choose - in one pass.
'
' Femap has no native command for this. Group -> <entity> -> Remove works on the
' ACTIVE group only, so stripping one node out of a dozen groups means activating
' and re-picking a dozen times. This tool inverts that: the entity is picked once
' and the groups become the selection.
'
' HOW THE REMOVAL IS DONE - AND WHY IT IS A RULE, NOT A DELETION
' A Femap group is not a stored list of IDs. It is an ordered list of selection
' RULES that Femap evaluates to produce the contents. Rules can be explicit ID
' ranges ("elements 100 to 250") or generative ("all elements on surface 5").
'
' So this tool does not "delete" the entity from the group - there is nothing to
' delete. It appends a Remove rule:
'
'     gp.SetAddOpt( entityType, setID, 0 )      ' 0 = Remove, 1 = Add, -1 = Exclude
'
' RangeAdd/SetAddOpt append to the END of the rule list, and Femap evaluates the
' list in order, so a trailing Remove beats every Add before it. That is what
' makes this work even when the entity got into the group through a generative
' rule - the rule still selects it, and the Remove then takes it back out.
'
' The existing rules are NOT edited or narrowed - the Remove is appended after
' them. A group whose rule is "all elements on surface 5" keeps that rule
' verbatim and gains a trailing "Remove element 1234". Correct today, but the
' generative rule keeps generating: remesh surface 5 and it re-picks up whatever
' is there now, while the stale Remove still runs last. After a renumber that ID
' may be a DIFFERENT element, which then gets silently stripped. Femap's own UI
' behaves the same way - there is no API to carve one entity out of a generative
' rule.
'
' *** THE CONSEQUENCE, WHICH IS EASY TO GET BITTEN BY ***
' The Remove rule is PERMANENT and it stays at the end of the list. If you later
' add that same entity back to the group by hand, the next Group -> Operations ->
' Evaluate will strip it out again, because the trailing Remove still runs last.
' To genuinely undo this, open Group -> Operations -> Edit Rules on the group and
' delete the Remove range - do not just re-add the entity.
'
' This is reported in the summary every run, not buried here, because a group that
' silently refuses to accept an entity is a nasty thing to debug months later.
'
' ENTITY TYPE CONSTANTS - A TRAP THIS TOOL SIDESTEPS
' Femap has TWO numbering schemes for entity types and they do not agree:
'
'     Entity Types (FT_)          Group List Types (FGR_)
'       FT_POINT   = 3              FGR_POINT   = 1
'       FT_SURFACE = 5              FGR_SURFACE = 3
'       FT_NODE    = 7              FGR_NODE    = 7     <- these two happen to match
'       FT_ELEM    = 8              FGR_ELEM    = 8     <- so does this one
'       FT_SOLID   = 39             FGR_SOLID   = 21
'
' Node and Elem matching is a coincidence, and it is exactly the coincidence that
' makes this bug survive testing: code written with FT_ constants against
' Group.List() works perfectly on nodes and elements and then reads the wrong list
' the moment someone picks surfaces.
'
' This tool never calls Group.List(), so it never needs the FGR_ scheme. It reads
' group contents with Set.AddGroup( entityTYPE, groupID ), which takes FT_ types -
' the same constants SetAddOpt takes. One scheme end to end.
'
' NOTHING IS MODIFIED UNTIL THE CONFIRM DIALOG, and "Report only" mode skips the
' write entirely - use it just to answer "which groups is this node in?".
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long

    ' ============================================================
    ' Section 1: What kind of entity, and are we writing anything
    '
    ' Only the types that can actually live in a group are offered. The FT_
    ' values are hardcoded alongside the names so the dropdown index maps
    ' straight to a type without a second lookup table.
    ' ============================================================
    Dim typeNames(9) As String
    Dim typeIDs(9) As Long

    typeNames(0) = "Node"              : typeIDs(0) = FT_NODE
    typeNames(1) = "Element"           : typeIDs(1) = FT_ELEM
    typeNames(2) = "Point"             : typeIDs(2) = FT_POINT
    typeNames(3) = "Curve"             : typeIDs(3) = FT_CURVE
    typeNames(4) = "Surface"           : typeIDs(4) = FT_SURFACE
    typeNames(5) = "Solid"             : typeIDs(5) = FT_SOLID
    typeNames(6) = "Volume"            : typeIDs(6) = FT_VOLUME
    typeNames(7) = "Property"          : typeIDs(7) = FT_PROP
    typeNames(8) = "Material"          : typeIDs(8) = FT_MATL
    typeNames(9) = "Coordinate System" : typeIDs(9) = FT_CSYS

    Begin Dialog TypeDlg 340, 176, "Remove From Groups"
        Text        12, 12, 316, 24, "Pick entities, see which groups hold them, then remove them from the groups you choose."
        Text        12, 46, 100, 12, "Entity type:"
        DropListBox 116, 44, 212, 140, typeNames(), .typePick
        CheckBox    12, 70, 316, 12, "Report only - list the groups, change nothing", .chkDryRun
        Text        12, 92, 316, 32, "Removal appends a permanent Remove rule to each group. Re-adding the entity later will not stick until that rule is deleted."
        OKButton     84, 140, 80, 20
        CancelButton 184, 140, 80, 20
    End Dialog

    Dim tdlg As TypeDlg
    tdlg.typePick  = 0
    tdlg.chkDryRun = 0
    If Dialog(tdlg) <> -1 Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If

    Dim entType As Long
    Dim entName As String
    Dim dryRun As Boolean
    entType = typeIDs(tdlg.typePick)
    entName = typeNames(tdlg.typePick)
    dryRun  = (tdlg.chkDryRun <> 0)

    ' ============================================================
    ' Section 2: Pick the entities
    ' ============================================================
    Dim pickSet As femap.Set
    Set pickSet = App.feSet
    rc = pickSet.Select(entType, True, "Select " + entName + "(s) to remove from groups")
    If rc <> FE_OK Or pickSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "Nothing selected - exiting")
        Exit Sub
    End If

    ' ============================================================
    ' Section 3: Which groups actually contain them
    '
    ' Every group is evaluated with forceEval=False first. That is cheap - it
    ' only touches groups Femap has already flagged as stale - but without it a
    ' rule-based group can report contents that are out of date, and the tool
    ' would either miss a group or offer one that no longer holds the entity.
    '
    ' Every group ID and title is harvested into arrays BEFORE any evaluating or
    ' set work begins. The enumerator cursor lives on the Group object, and the
    ' scan below calls feGroupEvaluate and Set.AddGroup - both of which reach
    ' into group data - so walking the enumerator and doing that work in the same
    ' loop risks the cursor moving under us. Two passes, no shared cursor.
    ' ============================================================
    Dim grpEnum As Object
    Set grpEnum = App.feGroup

    Dim grpCount As Long
    grpCount = 0
    grpEnum.Reset
    Do While grpEnum.Next()
        grpCount = grpCount + 1
    Loop
    If grpCount = 0 Then
        App.feAppMessage(FCM_WARNING, "No groups in the model - nothing to do")
        Exit Sub
    End If

    Dim allIDs() As Long, allNames() As String
    ReDim allIDs(grpCount - 1)
    ReDim allNames(grpCount - 1)
    Dim gi As Long
    gi = 0
    grpEnum.Reset
    Do While grpEnum.Next()
        allIDs(gi)   = grpEnum.ID
        allNames(gi) = Trim$(Str$(grpEnum.ID)) + " - " + grpEnum.title
        gi = gi + 1
    Loop

    Dim gset As femap.Set
    Dim inter As femap.Set
    Set gset  = App.feSet
    Set inter = App.feSet

    Dim hitIDs() As Long, hitNames() As String, hitCounts() As Long
    ReDim hitIDs(grpCount - 1)
    ReDim hitNames(grpCount - 1)
    ReDim hitCounts(grpCount - 1)

    Dim nHit As Long
    nHit = 0

    For i = 0 To grpCount - 1
        rc = App.feGroupEvaluate(-allIDs(i), False)

        gset.Clear
        rc = gset.AddGroup(entType, allIDs(i))
        If rc = FE_OK And gset.Count > 0 Then
            ' Intersection of "what I picked" with "what this group holds".
            inter.Clear
            rc = inter.AddCommon(pickSet.ID, gset.ID)
            If inter.Count > 0 Then
                hitIDs(nHit)    = allIDs(i)
                hitNames(nHit)  = allNames(i)
                hitCounts(nHit) = inter.Count
                nHit = nHit + 1
            End If
        End If
    Next i

    App.feAppMessage(FCM_HIGHLIGHT, "----------------------------------------")
    App.feAppMessage(FCM_HIGHLIGHT, "  Groups containing the selected " + entName + "(s)")
    App.feAppMessage(FCM_HIGHLIGHT, "----------------------------------------")
    If nHit = 0 Then
        App.feAppMessage(FCM_NORMAL, "  none - the selection is not in any group")
        App.feAppMessage(FCM_NORMAL, "Nothing to do - exiting")
        Exit Sub
    End If
    For i = 0 To nHit - 1
        App.feAppMessage(FCM_NORMAL, "  " + hitNames(i) _
            + "   (" + Trim$(Str$(hitCounts(i))) + " of " _
            + Trim$(Str$(pickSet.Count)) + ")")
    Next i

    If dryRun Then
        App.feAppMessage(FCM_HIGHLIGHT, "Report only - nothing was modified")
        Exit Sub
    End If

    ' ============================================================
    ' Section 4: Which of those groups to strip
    '
    ' The set is pre-loaded with every group that scored a hit and handed to
    ' Femap's own group selection dialog with clear=False, so it opens already
    ' populated - deselect the ones to keep rather than hunting for the ones to
    ' strip. Groups added by hand that do not contain the selection fall out
    ' harmlessly in Section 5 (empty intersection = skipped).
    ' ============================================================
    Dim grpSet As femap.Set
    Set grpSet = App.feSet
    grpSet.Clear
    For i = 0 To nHit - 1
        rc = grpSet.Add(hitIDs(i))
    Next i

    rc = grpSet.Select(FT_GROUP, False, "Groups to remove from - deselect any you want to keep")
    If rc <> FE_OK Or grpSet.Count = 0 Then
        App.feAppMessage(FCM_WARNING, "No groups selected - nothing modified")
        Exit Sub
    End If

    ' ============================================================
    ' Section 5: Confirm, then append the Remove rules
    ' ============================================================
    Dim answer As Long
    answer = App.feAppMessageBox(1, _
        "Remove " + Trim$(Str$(pickSet.Count)) + " " + entName + "(s) from " _
        + Trim$(Str$(grpSet.Count)) + " group(s)?" + Chr(13) + Chr(10) + Chr(13) + Chr(10) _
        + "This appends a permanent Remove rule to each group.")
    If answer <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - nothing modified")
        Exit Sub
    End If

    Dim gp As femap.Group
    Set gp = App.feGroup

    Dim nDone As Long, nSkip As Long, nFail As Long
    Dim nStripped As Long
    nDone = 0 : nSkip = 0 : nFail = 0 : nStripped = 0

    ' Same two-pass discipline as the scan: pull the chosen group IDs out of the
    ' Set before touching any group, so the Set cursor is never live across a
    ' Get/Put/Evaluate.
    Dim chosen() As Long
    ReDim chosen(grpSet.Count - 1)
    Dim gID As Long
    gID = grpSet.First
    For i = 0 To grpSet.Count - 1
        chosen(i) = gID
        gID = grpSet.Next
    Next i

    For i = 0 To UBound(chosen)
        gID = chosen(i)
        ' Re-derive the intersection per group so each Remove rule covers only
        ' the entities that group actually holds. Dumping the whole pick set in
        ' would work, but it litters every group's rule list with removals for
        ' entities that were never there.
        gset.Clear
        rc = gset.AddGroup(entType, gID)
        inter.Clear
        If rc = FE_OK And gset.Count > 0 Then
            rc = inter.AddCommon(pickSet.ID, gset.ID)
        End If

        If inter.Count = 0 Then
            nSkip = nSkip + 1
        Else
            ' Get loads the existing rule list onto the object, SetAddOpt appends
            ' to it, Put writes the whole list back. Skipping the Get would write
            ' a group whose only rule is the Remove - i.e. an empty group.
            rc = gp.Get(gID)
            If rc <> FE_OK Then
                nFail = nFail + 1
            Else
                rc = gp.SetAddOpt(entType, inter.ID, 0)     ' 0 = Remove
                If rc <> FE_OK Then
                    nFail = nFail + 1
                Else
                    rc = gp.Put(gID)
                    If rc <> FE_OK Then
                        nFail = nFail + 1
                    Else
                        rc = App.feGroupEvaluate(-gID, True)
                        nDone = nDone + 1
                        nStripped = nStripped + inter.Count
                    End If
                End If
            End If
        End If
    Next i

    ' ============================================================
    ' Section 6: Report
    ' ============================================================
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_HIGHLIGHT, "  Remove From Groups - Summary")
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
    App.feAppMessage(FCM_NORMAL,    "  Entity type:           " + entName)
    App.feAppMessage(FCM_NORMAL,    "  Selected:              " + Trim$(Str$(pickSet.Count)))
    App.feAppMessage(FCM_NORMAL,    "  Groups modified:       " + Trim$(Str$(nDone)))
    App.feAppMessage(FCM_NORMAL,    "  Removals written:      " + Trim$(Str$(nStripped)))
    If nSkip > 0 Then
        App.feAppMessage(FCM_NORMAL, "  Skipped (not in group):" + Trim$(Str$(nSkip)))
    End If
    If nFail > 0 Then
        App.feAppMessage(FCM_ERROR,  "  FAILED:                " + Trim$(Str$(nFail)) _
            + "   (group could not be read or written)")
    End If
    If nDone > 0 Then
        App.feAppMessage(FCM_WARNING, "  Each modified group now ends with a Remove rule.")
        App.feAppMessage(FCM_WARNING, "  Re-adding these entities will NOT stick until that")
        App.feAppMessage(FCM_WARNING, "  rule is deleted in Group -> Operations -> Edit Rules.")
    End If
    App.feAppMessage(FCM_HIGHLIGHT, "========================================")
End Sub
