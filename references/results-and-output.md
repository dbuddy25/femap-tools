# Results and Output

## Overview

The Results Browsing Object (`App.feResults`) is the **primary** interface for reading
and writing output data in Femap v2020.1+. It replaces the deprecated `feOutput` object
and provides better performance through columnar data access.

The OutputSet Object (`App.feOutputSet`) manages result set metadata (title, value,
analysis type).

## OutputSet Object

### Create an Output Set

```vb
Dim os As femap.OutputSet
Set os = App.feOutputSet

Dim oSetID As Long
oSetID = os.NextEmptyID
os.title = "My Results"
os.value = 1.0           ' Time/frequency/load factor
os.analysis = 5          ' Analysis type
rc = os.Put(oSetID)
```

### Iterate Output Sets

```vb
Dim id As Long
id = os.First()
Do While id > 0
    rc = os.Get(id)
    App.feAppMessage(FCM_NORMAL, Str$(id) + ": " + os.title)
    id = os.Next()
Loop
```

---

## Results Browsing Object (RBO)

### Create the Object

```vb
Dim rbo As femap.Results
Set rbo = App.feResults
```

### Properties

| Property | Type | Description |
|---|---|---|
| `NumberOfColumns` | Long (read-only) | Current column count |
| `NumberOfRows` | Long (read-only) | Current row count |

---

## Reading Results

### Step-by-Step Workflow

1. **Add columns** for the vectors you want to read
2. **Populate** to load data from the database
3. **Get column data** as arrays

```vb
' 1. Add a column for a specific output vector
Dim col As Long, vCol As Variant
rc = rbo.AddColumnV2(setID, vectorID, False, col, vCol)

' 2. Populate the data
rc = rbo.Populate

' 3. Get the data arrays
Dim vIDs As Variant, vVals As Variant
rc = rbo.GetColumn(0, vIDs, vVals)
' vIDs = entity IDs (node or element)
' vVals = corresponding values
```

### Multiple Columns

```vb
rc = rbo.AddColumnV2(setID, vecID1, False, col1, vCol1)
rc = rbo.AddColumnV2(setID, vecID2, False, col2, vCol2)
rc = rbo.Populate

Dim vIDs1 As Variant, vVals1 As Variant
Dim vIDs2 As Variant, vVals2 As Variant
rc = rbo.GetColumn(0, vIDs1, vVals1)
rc = rbo.GetColumn(1, vIDs2, vVals2)
```

### Data Location

```vb
Dim dLocation As Long
rc = rbo.DataLocation(dLocation)
' dLocation = 7 → Nodal
' dLocation = 8 → Elemental
```

### Get Vector Title

```vb
Dim vecTitle As String
vecTitle = ""
rc = rbo.VectorTitleV2(setID, vectorID, vecTitle)
```

### Send to Data Table

```vb
rc = rbo.SendToDataTable   ' Useful for debugging
```

---

## Creating Output (Nodal Vectors)

Create displacement-style vectors with X, Y, Z components and total:

```vb
Dim rbo As femap.Results : Set rbo = App.feResults
Dim os As femap.OutputSet : Set os = App.feOutputSet
Dim ndSet As femap.Set : Set ndSet = App.feSet

' 1. Create output set
Dim oSetID As Long
oSetID = os.NextEmptyID
os.title = "User Defined Output"
os.value = 1.0
os.analysis = 5
os.Put(oSetID)

' 2. Select nodes
ndSet.Select(FT_NODE, True, "Select Nodes")
Dim count As Long : count = ndSet.Count
Dim nIDs As Variant : ndSet.GetArray(count, nIDs)

' 3. Prepare data arrays
ReDim xVals(count - 1) As Variant
ReDim yVals(count - 1) As Variant
ReDim zVals(count - 1) As Variant
For i = 0 To count - 1
    xVals(i) = 0.001 * i
    yVals(i) = -(0.002 * i - 0.001)
    zVals(i) = 0.0
Next

' 4. Initialize columns for vector output
' User-defined output uses IDs in the 24,000,000 range
Dim cIndex As Variant
rbo.AddVectorAtNodeColumnsV2(oSetID, 24000000, 24000001, 24000002, _
    24000003, "Displacement", FOT_DISP, True, cIndex)

' 5. Set data and save
rbo.SetVectorAtNodeColumnsV2(cIndex, count, nIDs, xVals, yVals, zVals)
rbo.Save
```

### User-Defined Output Vector ID Ranges

| Range Start | Description |
|---|---|
| 24,000,000 | User-defined vectors (safe to use) |
| 24,000,001+ | Additional user vectors |

---

## Creating Output (Elemental Scalars)

```vb
Dim rbo As femap.Results : Set rbo = App.feResults
Dim os As femap.OutputSet : Set os = App.feOutputSet
Dim eSet As femap.Set : Set eSet = App.feSet

' Create output set
Dim oSetID As Long
oSetID = os.NextEmptyID
os.title = "Element Stress Output"
os.value = 1.0
os.analysis = 5
os.Put(oSetID)

' Select elements
eSet.Select(FT_ELEM, True, "Select Elements")
Dim count As Long : count = eSet.Count
Dim eIDs As Variant : eSet.GetArray(count, eIDs)

' Prepare data
ReDim eVals(count - 1) As Variant
For i = 0 To count - 1
    eVals(i) = i * 100 + 1200
Next

' Initialize scalar column
Dim cIndex As Long
rbo.AddScalarAtElemColumnV2(oSetID, 24000000, "My Stress", FOT_STRESS, _
    False, cIndex)

' Set data and save
rbo.SetColumn(cIndex, count, eIDs, eVals)
rbo.Save
```

---

## V2 Migration Guide

### What Changed in v2020.1

Output vector IDs were remapped to new ranges to accommodate more output types.
Key changes:

- Plate stress offset: 200 → 1000 (e.g., Top VonMises was 7033, now still 7033 for top;
  Bottom was 7433, now 9033)
- All methods using vector IDs have `V2` variants
- Old methods still work but trigger deprecation warnings and internally convert IDs

### Deprecated → V2 Methods

| Old Method | New Method |
|---|---|
| `AddColumn` | `AddColumnV2` |
| `GetColumn` | `GetColumn` (unchanged — uses column index) |
| `SetColumn` | `SetColumn` (unchanged — uses column index) |
| `AddScalarAtElemColumn` | `AddScalarAtElemColumnV2` |
| `AddVectorAtNodeColumns` | `AddVectorAtNodeColumnsV2` |
| `SetVectorAtNodeColumns` | `SetVectorAtNodeColumnsV2` |
| `VectorTitle` | `VectorTitleV2` |
| `DataLocation` | `DataLocation` (unchanged) |

### Using ResultsIDQuery for Portable Vector IDs

Instead of hardcoding vector IDs, use the ResultsIDQuery object:

```vb
Dim q As femap.ResultsIDQuery
Set q = App.feResultsIDQuery

' Plate stress vectors
Dim topVM As Long, botVM As Long
topVM = q.Plate(VPV_STRESS, VPT_VON_MISES, VPP_TOP, VPL_CENTROID)
botVM = q.Plate(VPV_STRESS, VPT_VON_MISES, VPP_BOT, VPL_CENTROID)

' Nodal displacement
Dim dispTotal As Long
dispTotal = q.Nodal(VPV_DISP, VPT_TOTAL)
```

### ResultsIDQuery Methods

| Method | Entity Type | Arguments |
|---|---|---|
| `Nodal(value, comp)` | Nodal results | Value type, component |
| `Line(value, comp, end)` | Line elements | Value, component, end position |
| `Plate(value, comp, pos, loc)` | Plate elements | Value, component, position, location |
| `Solid(value, comp, loc)` | Solid elements | Value, component, location |

---

## Results Browsing Study Methods

For working with analysis studies and parametric results:

```vb
' Add study column
rc = rbo.AddStudyColumnV2(studyID, caseID, setID, vectorID, _
    False, col, vCol)

' Populate and iterate
rc = rbo.PopulateStudy
rc = rbo.GetStudyColumn(col, vIDs, vVals)
```

---

## Attached Results

Read results from attached files (OP2, XDB, etc.) without importing:

```vb
' Attach results file
rc = App.feFileAttach(type, filename)

' Iterate attached result sets
Dim attSet As femap.Set : Set attSet = App.feSet
attSet.Select(FT_RES_ATTACH, True, "Select Attached Results")
Dim id As Long : id = attSet.First()
Do While id > 0
    ' Process attached results...
    id = attSet.Next()
Loop
```

---

## Deprecated: Output Object (feOutput)

The `feOutput` object is **deprecated** as of v2020.1. Do not use for new code.
Use the Results Browsing Object instead, which provides equivalent functionality
with better performance.

If maintaining legacy scripts that use `feOutput`, the object still works but
will show deprecation warnings. Migrate to RBO methods at earliest convenience.
