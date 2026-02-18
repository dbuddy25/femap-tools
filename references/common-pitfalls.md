# Common Pitfalls in Femap API Scripting

## 1. Forgetting `Set` When Creating Objects

**Wrong:**
```vb
Dim nd As femap.Node
nd = App.feNode          ' FAILS — no Set keyword
```

**Right:**
```vb
Dim nd As femap.Node
Set nd = App.feNode      ' Required for COM objects in WinWrap Basic
```

> In VB.NET, `Set` is not used. In WinWrap Basic (Femap's built-in editor), it is **required**.

## 2. Using `GetObject` Inside the Femap API Window

**Wrong:**
```vb
Set App = GetObject(,"femap.model")  ' May connect to wrong Femap instance
```

**Right:**
```vb
Set App = feFemap()  ' Always connects to the current Femap session
```

> `GetObject` connects to the first-started Femap process. `feFemap()` always connects
> to the session that launched your script.

## 3. Not Checking Return Codes

**Wrong:**
```vb
nd.Get(42)
nd.x = nd.x + 10.0    ' If Get failed, nd still has stale data
```

**Right:**
```vb
rc = nd.Get(42)
If rc <> FE_OK Then
    App.feAppMessage(FCM_ERROR, "Node 42 not found")
    Exit Sub
End If
nd.x = nd.x + 10.0
```

> `FE_OK` = -1 (success), `FE_FAIL` = 0 (failure). Always check after Get/Put/Select.

## 4. Confusing Entity ID with Object Index

The `Set.Next()` method returns the **entity ID**, not a sequential index:

```vb
id = mySet.First()       ' Returns actual entity ID (e.g., 1042)
Do While id > 0
    rc = el.Get(id)       ' Use the ID to Get the entity
    id = mySet.Next()     ' Next entity ID (e.g., 3087), NOT id+1
Loop
```

## 5. Not Calling `Put` After Modifying an Entity

Modifying object properties changes the **in-memory copy** only. You must call `Put`
to save changes to the Femap database:

```vb
rc = el.Get(100)
el.propID = 5            ' Only changes in-memory copy
rc = el.Put(100)         ' NOW saved to database
```

## 6. Using Wrong Data Types for API Parameters

The API documentation uses language-neutral types. In WinWrap Basic:

| API Doc | WinWrap Basic | Common Mistake |
|---|---|---|
| INT4 | `Long` | Using `Integer` (only 2 bytes in VB6/WinWrap) |
| REAL8 | `Double` | Using `Single` (4-byte float, loses precision) |
| BOOL | `Boolean` | Using `Long` or `Integer` |
| Array | `Variant` | Not using `Variant` for array returns |

## 7. Forgetting Array Shortcut Rules

When an API method requires an array parameter and you want all values the same,
you can pass a single value. But this **only works for input parameters**:

```vb
' OK — all layers set to 1:
rc = nd.PutAllArray(numNode, ndID, xyz, 1, 43, 0, 0, 0, 0)

' NOT OK — output arrays must be declared as Variant:
Dim vIDs As Variant    ' Correct for output
rc = rbo.GetColumn(0, vIDs, vVals)
```

## 8. Using Old Output Vector IDs (Pre-v2020.1)

**Wrong (deprecated):**
```vb
rc = rbo.AddColumn(setID, 7433, False, col, vCol)  ' Old von Mises ID
```

**Right (v2020.1+):**
```vb
rc = rbo.AddColumnV2(setID, 9033, False, col, vCol)  ' New von Mises ID
```

Or better, use `ResultsIDQuery` to look up IDs programmatically:
```vb
Dim q As femap.ResultsIDQuery
Set q = App.feResultsIDQuery
vecID = q.Plate(VPV_STRESS, VPT_VON_MISES, VPP_BOT, VPL_CENTROID)
rc = rbo.AddColumnV2(setID, vecID, False, col, vCol)
```

> All `V2` methods use the new vector ID ranges. Old methods still work but trigger
> deprecation warnings. See `references/results-and-output.md` for full migration guide.

## 9. Not Locking the UI During Bulk Operations

Without locking, Femap redraws the UI after every API call — extremely slow for loops:

**Wrong:**
```vb
For i = 1 To 10000
    nd.Get(i)
    nd.x = nd.x + offset
    nd.Put(i)            ' UI redraws 10,000 times
Next
```

**Right:**
```vb
App.feAppLock()
For i = 1 To 10000
    nd.Get(i)
    nd.x = nd.x + offset
    nd.Put(i)
Next
App.feAppUnlock()
App.feViewRegenerate(0)
```

> Even better: use `GetAllArray` / `PutAllArray` for bulk node operations.

## 10. Set Object Not Reset Before Reuse

The Set object cursor (`First`/`Next`) is stateful. Forgetting to reset causes
missed entities:

```vb
' First pass
id = mySet.First()
Do While id > 0
    id = mySet.Next()
Loop

' Second pass — MUST reset cursor
mySet.Reset()
id = mySet.First()
Do While id > 0
    id = mySet.Next()
Loop
```

## 11. Creating Loads Without a Load Set and Load Definition

Loads require a parent Load Set AND a Load Definition before `LoadMesh.Put`:

```vb
' 1. Create Load Set
Dim ls As femap.LoadSet : Set ls = App.feLoadSet
ls.title = "My Loads"
ls.Put(ls.NextEmptyID)

' 2. Create Load Definition
Dim ld As femap.LoadDefinition : Set ld = App.feLoadDefinition
ld.setID = ls.ID
ld.title = "Force"
ld.Put(ld.NextEmptyID)

' 3. NOW create LoadMesh entries
Dim lm As femap.LoadMesh : Set lm = App.feLoadMesh
lm.setID = ls.ID
lm.LoadDefinitionID = ld.ID
' ... set type, values, etc. ...
lm.Put(-1)
```

## 12. Incorrect Element Node Array Handling

Element node arrays are 0-based. The number of nodes depends on element topology:

```vb
el.node(0) = 1    ' First node (0-based index)
el.node(1) = 2
el.node(2) = 3
el.node(3) = 4    ' CQUAD4 has 4 nodes: indices 0-3
```

For rigid elements, `node(0)` is the **independent** node. Use `PutNodeList` for
variable-length node lists (RBE2, RBE3):

```vb
rc = el.PutNodeList(0, nodeCount, vNodeArray, vFaceArray, vWeight, vDOF)
```

## 13. Accessing Properties Before `Get`

Entity object properties contain garbage until `Get` is called:

```vb
Dim nd As femap.Node
Set nd = App.feNode
' nd.x is UNDEFINED here — must call Get first
rc = nd.Get(1)
' NOW nd.x, nd.y, nd.z contain valid data
```

## 14. Forgetting to Call `rbo.Populate` After Adding Columns

The Results Browsing Object requires `Populate` to actually load data after
`AddColumnV2`:

```vb
rc = rbo.AddColumnV2(setID, vecID, False, col, vCol)
rc = rbo.Populate        ' <-- Must call this!
rc = rbo.GetColumn(0, vIDs, vVals)  ' Now data is available
```

Without `Populate`, `GetColumn` returns empty/zero data.

## 15. `feAppMessage` Uses Printf-Style Formatting

`feAppMessage` passes strings through a C-style printf formatter. A `%` followed by
a letter is interpreted as a format specifier, producing garbage output:

**Wrong:**
```vb
App.feAppMessage(FCM_NORMAL, "Result: 0.01% difference")
' Outputs: "Result: 0.01 1845731121ifference" — %d consumed a stack value
```

**Right:**
```vb
App.feAppMessage(FCM_NORMAL, "Result: 0.01%% difference")
' Outputs: "Result: 0.01% difference" — %% escapes to literal %
```

> This affects ANY `%` followed by a letter: `%d`, `%s`, `%f`, etc. Always use `%%`
> for literal percent signs in `feAppMessage`, `feAppMessageBox`, and similar calls.

## 16. Trusting `mval`/`pval` Index Documentation Without Verification

The API PDF and skill references may have incorrect array index mappings. The `mval`
and `pval` arrays are sparse with non-obvious layouts that differ by entity type.

**Example:** Density was documented as `mval(3)` but is actually at `mval(49)`.
`mval(3)` is the first shear modulus (G[1]) — scaling it doubled G instead of density.

**Best practice:** When working with `mval` or `pval` for the first time, add a
temporary diagnostic dump to confirm indices against known values:

```vb
' Temporary: dump pval to find correct indices
Dim i As Long
For i = 0 To 20
    App.feAppMessage(FCM_NORMAL, "  pval(" + Str$(i) + ") = " + _
        Format$(pr.pval(i), "0.0000E+00"))
Next i
```

> Compare dumped values against what Femap shows in the GUI for the same entity.
> Remove the dump after confirming the correct indices.
