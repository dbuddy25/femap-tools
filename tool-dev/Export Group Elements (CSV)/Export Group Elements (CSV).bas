' Export Group Elements (CSV).bas
' -----------------------------------------------------------------------------
' Export the element membership of selected groups to a CSV:
'     element_id,group_id,group_title
' One row per (element, group). Useful for cross-checking group-based
' post-processing (e.g. %ESE/%EKE by group) against a solver file (F06/PUNCH):
' join this mapping to the per-element results and sum by group.
'
' An element that is in more than one selected group appears on multiple rows.
' -----------------------------------------------------------------------------

Sub Main
    Dim App As femap.model
    Set App = feFemap()
    Dim rc As Long
    Dim i As Long

    ' --- select groups ---
    Dim gset As femap.Set
    Set gset = App.feSet
    rc = gset.Select(FT_GROUP, True, "Select element group(s) to export")
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Cancelled - exiting")
        Exit Sub
    End If
    Dim nGroups As Long
    nGroups = gset.Count
    If nGroups = 0 Then
        App.feAppMessage(FCM_ERROR, "No groups selected")
        Exit Sub
    End If
    Dim grpIDs() As Long
    ReDim grpIDs(nGroups - 1)
    Dim gid As Long
    i = 0
    gid = gset.First()
    Do While gid > 0
        grpIDs(i) = gid
        i = i + 1
        gid = gset.Next()
    Loop

    ' --- output file ---
    Dim fName As String
    rc = App.feFileGetName("Save Group Elements CSV", "CSV", "*.csv", False, fName)
    If rc <> FE_OK Then
        App.feAppMessage(FCM_WARNING, "Save cancelled - exiting")
        Exit Sub
    End If
    If LCase$(Right$(fName, 4)) <> ".csv" Then fName = fName + ".csv"

    Dim gp As femap.Group
    Set gp = App.feGroup
    Dim lst As femap.Set
    Dim es As femap.Set
    Set es = App.feSet
    Dim gtitle As String
    Dim eid As Long
    Dim g As Long
    Dim nRows As Long
    nRows = 0

    Dim outF As Long
    outF = FreeFile
    Open fName For Output As #outF
    Print #outF, "element_id,group_id,group_title"

    For g = 0 To nGroups - 1
        rc = gp.Get(grpIDs(g))
        gtitle = gp.title
        Set lst = gp.List(8)                     ' 8 = elements (volatile - copy now)
        es.Clear()
        If Not (lst Is Nothing) Then es.AddSet(lst.ID)
        eid = es.First()
        Do While eid > 0
            Print #outF, Trim$(Str$(eid)) + "," + Trim$(Str$(grpIDs(g))) _
                + "," + Chr$(34) + gtitle + Chr$(34)
            nRows = nRows + 1
            eid = es.Next()
        Loop
    Next g

    Close #outF

    App.feAppMessage(FCM_NORMAL, "Wrote " + Trim$(Str$(nRows)) + " element-group rows for " _
        + Trim$(Str$(nGroups)) + " group(s) to:")
    App.feAppMessage(FCM_NORMAL, "  " + fName)
End Sub
