# Tool Objects

Femap Tool Objects are utility objects accessed from the Application Object that
provide specialized functionality beyond basic entity CRUD.

## DataTable Object (`App.feDataTable`)

The Data Table is Femap's spreadsheet-like data view. The API provides full control
over rows, columns, data, grouping, sorting, and selection.

### Create and Access

```vb
Dim dt As femap.DataTable
Set dt = App.feDataTable
```

### Row Methods

| Method | Description |
|---|---|
| `AddRow(rowID)` | Add a row |
| `DeleteRow(rowID)` | Delete a row |
| `RowCount()` | Get total row count |
| `GetRowID(index, id)` | Get row ID at index |
| `LockRow(rowID, lock)` | Lock/unlock a row |

### Column Methods

| Method | Description |
|---|---|
| `AddColumn(title, type, width, col)` | Add a column |
| `DeleteColumn(col)` | Delete a column |
| `ColumnCount()` | Get total column count |
| `SetColumnTitle(col, title)` | Set column header |
| `GetColumnTitle(col, title)` | Get column header |
| `SetColumnWidth(col, width)` | Set column width |
| `ShowColumn(col, show)` | Show/hide column |
| `MoveColumn(fromCol, toCol)` | Reorder columns |

### Data Methods

| Method | Description |
|---|---|
| `SetValue(row, col, value)` | Set cell value |
| `GetValue(row, col, value)` | Get cell value |
| `SetText(row, col, text)` | Set cell text |
| `GetText(row, col, text)` | Get cell text |
| `SetColor(row, col, color)` | Set cell color |
| `Clear()` | Clear all data |
| `Refresh()` | Refresh display |
| `Lock(lock)` | Lock/unlock entire table |

### Sorting and Grouping

```vb
rc = dt.Sort(col, ascending)        ' Sort by column
rc = dt.GroupBy(col)                 ' Group by column
rc = dt.ExpandAll()                  ' Expand all groups
rc = dt.CollapseAll()                ' Collapse all groups
```

### Selection

```vb
rc = dt.SelectRow(rowID, select)     ' Select/deselect row
rc = dt.GetSelectedRows(set)         ' Get selected row IDs
```

---

## Set Object (`App.feSet`)

The Set Object is covered in detail in `references/sets-and-selection.md`.
It is listed here for completeness as it is technically a Tool Object.

---

## ReadFile Object (`App.feRead`)

Parse text files with field-based extraction. Faster than native Basic file I/O
due to internal buffering.

### Basic Usage

```vb
Dim f As femap.ReadFile
Set f = App.feRead

' Set up search and format
rc = f.SetSearchString("GRID", "")       ' Only read lines starting with "GRID"
Dim w(9) As Long
For i = 0 To 9 : w(i) = 8 : Next         ' 10 fields, 8 chars wide
rc = f.FixedFormat(10, w)
rc = f.SetAutoFormat()

' Open and read
rc = f.Open("C:\data\model.nas", 100)     ' Buffer 100 lines
Do
    rc = f.Read()
    Dim nodeID As Long : nodeID = f.IntField(2, 0)
    Dim x As Double : x = f.RealField(4, 0#)
    Dim y As Double : y = f.RealField(5, 0#)
    Dim z As Double : z = f.RealField(6, 0#)
    ' Process data...
Loop Until f.AtEOF()
rc = f.Close()
```

### Properties

| Property | Type | Description |
|---|---|---|
| `LineNumber` | Long (read-only) | Current line number |

### Methods

| Method | Description |
|---|---|
| `Open(file, bufferSize)` | Open file for reading |
| `Close()` | Close file |
| `Read()` | Read next matching line |
| `AtEOF()` | Check for end of file |
| `SetSearchString(str1, str2)` | Filter lines by prefix |
| `FixedFormat(nFields, widths)` | Set fixed-width field format |
| `SetAutoFormat()` | Enable auto format detection |
| `FreeFormat(delimiters)` | Set free-format delimiters |
| `IntField(field, default)` | Get integer from field |
| `RealField(field, default)` | Get double from field |
| `StringField(field, default)` | Get string from field |
| `BoolField(field, default)` | Get boolean from field |

---

## UserData Object (`App.feUserData`)

Store custom binary data in the Femap database that persists with the model.

### Writing Data

```vb
Dim ud As femap.UserData
Set ud = App.feUserData

' Write various data types
rc = ud.WriteLong(42)
rc = ud.WriteDouble(3.14159)
rc = ud.WriteString("hello")

' Write arrays
Dim vals(2) As Double
vals(0) = 1.0 : vals(1) = 2.0 : vals(2) = 3.0
rc = ud.WriteDoubleArray(3, vals)

' Save to database
rc = ud.Put(1)   ' ID = 1
```

### Reading Data

```vb
Dim ud2 As femap.UserData
Set ud2 = App.feUserData
rc = ud2.Get(1)

Dim myLong As Long : rc = ud2.ReadLong(myLong)
Dim myDouble As Double : rc = ud2.ReadDouble(myDouble)
Dim myString As String : myString = "" : rc = ud2.ReadString(myString)

Dim count As Long, vVals As Variant
rc = ud2.ReadDoubleArray(count, vVals)
```

### Methods

| Method | Description |
|---|---|
| `WriteLong(val)` | Write 4-byte integer |
| `WriteDouble(val)` | Write 8-byte double |
| `WriteString(val)` | Write string |
| `WriteLongArray(count, vals)` | Write integer array |
| `WriteDoubleArray(count, vals)` | Write double array |
| `ReadLong(val)` | Read 4-byte integer |
| `ReadDouble(val)` | Read 8-byte double |
| `ReadString(val)` | Read string |
| `ReadLongArray(count, vals)` | Read integer array |
| `ReadDoubleArray(count, vals)` | Read double array |
| `Clear()` | Clear stored data |

---

## Results Browsing Object (`App.feResults`)

Covered in detail in `references/results-and-output.md`.

---

## CopyTool Object (`App.feCopyTool`)

Programmatic access to Femap's Model → Copy command for copying entities
between models or within a model.

### Properties

| Property | Type | Description |
|---|---|---|
| `SourceModel` | Long | Source model ID |
| `DestModel` | Long | Destination model ID |
| `IncrementID` | Long | ID increment for copied entities |
| `MergeCoincident` | Boolean | Merge coincident nodes |
| `MergeTolerance` | Double | Merge tolerance |

### Options Methods

| Method | Description |
|---|---|
| `SetEntityOption(type, copy)` | Enable/disable copying of entity type |
| `SetAllOptions(copy)` | Enable/disable all entity types |
| `SetIDRange(type, startID)` | Set start ID for copied entities |
| `SetTranslation(dx, dy, dz)` | Set translation offset |
| `SetRotation(axis, angle)` | Set rotation |
| `SetScale(sx, sy, sz)` | Set scale factors |

### Operation Methods

```vb
Dim ct As femap.CopyTool
Set ct = App.feCopyTool

ct.SourceModel = 0          ' Current model
ct.DestModel = 0             ' Same model
ct.IncrementID = 1000
ct.SetAllOptions(True)
ct.SetTranslation(100, 0, 0)

Dim srcSet As femap.Set : Set srcSet = App.feSet
srcSet.Select(FT_ELEM, True, "Select Elements to Copy")
rc = ct.Copy(srcSet.ID)
```

---

## MoveTool Object (`App.feMoveTool`)

Similar to CopyTool but moves entities instead of copying.

### Key Methods

```vb
Dim mt As femap.MoveTool : Set mt = App.feMoveTool
mt.SetTranslation(dx, dy, dz)
rc = mt.Move(entitySet.ID)
```

---

## MergeTool Object (`App.feMergeTool`)

For merging models or portions of models together.

### Key Methods

| Method | Description |
|---|---|
| `AddModel(file)` | Add a model file to merge |
| `SetEntitySelection(type, set)` | Select entities to merge |
| `Merge()` | Execute merge operation |

---

## Sort Object (`App.feSort`)

General-purpose sorting utility for arrays.

```vb
Dim srt As femap.Sort : Set srt = App.feSort
srt.SortOnReal(count, vValues, vIndex)
' vIndex now contains sorted order indices
```

### Methods

| Method | Description |
|---|---|
| `SortOnReal(count, vals, index)` | Sort doubles, return index order |
| `SortOnLong(count, vals, index)` | Sort integers, return index order |
| `SortOnString(count, vals, index)` | Sort strings, return index order |

---

## Element Quality Object

Provides detailed element quality metrics beyond `feCheckElemDistortion`.

```vb
Dim eq As femap.ElemQuality
Set eq = App.feElemQuality

' Check quality for a set of elements
rc = eq.Check(elemSet.ID)

' Get results
Dim minJac As Double, maxJac As Double
rc = eq.GetJacobian(minJac, maxJac)
```

### Quality Metrics

| Method | Description |
|---|---|
| `GetJacobian(min, max)` | Jacobian ratio |
| `GetAspectRatio(min, max)` | Aspect ratio |
| `GetWarpage(min, max)` | Warpage angle |
| `GetSkew(min, max)` | Skew angle |
| `GetTaper(min, max)` | Taper ratio |

---

## Geometry Preparation and Meshing Object

For advanced geometry preparation before meshing (defeature, simplify, etc.).

```vb
Dim gpm As femap.GeomPrepMesh
Set gpm = App.feGeomPrepMesh

' Properties control defeature tolerances
gpm.SmallFeatureSize = 0.5
gpm.SlenderFaceWidth = 0.1

' Methods
rc = gpm.Prepare(solidSet.ID)
```

---

## MapData Object

For mapping data between different meshes or coordinate systems.

```vb
Dim md As femap.MapData
Set md = App.feMapData

rc = md.MapOutputToNewMesh(srcSetID, srcVecID, destSetID, tol)
```

---

## PublishTool / PublishTable Objects

For creating formatted reports and output tables.

```vb
Dim pt As femap.PublishTool : Set pt = App.fePublishTool
rc = pt.AddSection("Results Summary")
rc = pt.AddTable(tableID)
rc = pt.Publish("report.html")
```

---

## StressLinear Object

For stress linearization calculations (membrane + bending decomposition).

```vb
Dim sl As femap.StressLinear
Set sl = App.feStressLinear
rc = sl.SetLine(x1,y1,z1, x2,y2,z2)
rc = sl.Calculate(setID, vecID)
Dim membrane As Double, bending As Double
rc = sl.GetResults(membrane, bending)
```
