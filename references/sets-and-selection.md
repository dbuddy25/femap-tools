# Sets and Selection

The Set Object (`App.feSet`) is the most-used utility object in the Femap API.
It stores collections of entity IDs and provides methods for selection, iteration,
filtering, and rule-based population.

## Creating a Set

```vb
Dim mySet As femap.Set
Set mySet = App.feSet
```

You can create multiple independent Sets in the same script:

```vb
Dim elemSet As femap.Set : Set elemSet = App.feSet
Dim nodeSet As femap.Set : Set nodeSet = App.feSet
Dim propSet As femap.Set : Set propSet = App.feSet
```

## Interactive Selection

```vb
rc = mySet.Select(entityType, clearFirst, promptText)
```

| Parameter | Type | Description |
|---|---|---|
| `entityType` | Long | `FT_NODE`, `FT_ELEM`, `FT_PROP`, `FT_SURFACE`, etc. |
| `clearFirst` | Boolean | `True` = clear set before selecting; `False` = add to existing |
| `promptText` | String | Dialog prompt shown to user |

**Examples:**
```vb
rc = elemSet.Select(FT_ELEM, True, "Select Elements")
rc = nodeSet.Select(FT_NODE, True, "Select Nodes")
rc = propSet.Select(FT_PROP, True, "Select Properties")
rc = surfSet.Select(FT_SURFACE, True, "Select Surfaces")
```

> Returns `FE_OK` (-1) if user selects entities, `FE_CANCEL` (-2) if user cancels.

## Set Properties

| Property | Type | Description |
|---|---|---|
| `ID` | Long (read-only) | ID of current entity (after First/Next) |
| `Count` | Long (read-only) | Number of entities in the set |

## Iteration Methods

```vb
Dim id As Long
id = mySet.First()           ' Move to first entity, return its ID
Do While id > 0
    ' Process entity with this ID
    id = mySet.Next()        ' Move to next, return ID (0 when done)
Loop
```

| Method | Returns | Description |
|---|---|---|
| `First()` | Long | First ID in set (0 if empty) |
| `Next()` | Long | Next ID (0 if at end) |
| `Prev()` | Long | Previous ID (0 if at start) |
| `Last()` | Long | Last ID in set |
| `Reset()` | — | Reset cursor to before first (call First() again to start) |
| `NextAfter(id)` | Long | Next ID after specified ID |
| `PrevBefore(id)` | Long | Previous ID before specified ID |

## Adding and Removing Entities

### Direct Add/Remove

```vb
mySet.Add(42)                ' Add single ID
mySet.AddRange(1, 100)       ' Add IDs 1 through 100
mySet.Remove(42)             ' Remove single ID
mySet.RemoveRange(50, 100)   ' Remove IDs 50 through 100
mySet.Clear()                ' Remove all entries
```

### Add All of a Type

```vb
mySet.AddAll(FT_ELEM)        ' Add all element IDs
mySet.AddAll(FT_NODE)        ' Add all node IDs
```

### Rule-Based Population (FGD_ constants)

Rules add entities based on relationships to other entities:

```vb
mySet.AddRule(entityID, ruleType)
```

**Common rules:**

| Rule Constant | Description |
|---|---|
| `FGD_ELEM_BYPROP` | Elements using property ID |
| `FGD_ELEM_BYMATL` | Elements using material ID |
| `FGD_ELEM_BYTYPE` | Elements of element type |
| `FGD_ELEM_ATSURFACE` | Elements on surface ID |
| `FGD_ELEM_ATSOLID` | Elements on solid ID |
| `FGD_NODE_ONELEM` | Nodes on elements (use with `AddSetRule`) |
| `FGD_NODE_ATSURFACE` | Nodes on surface ID |
| `FGD_NODE_ATCURVE` | Nodes on curve ID |
| `FGD_Surface_onSolid` | Surfaces on solid ID |
| `FGD_Curve_onSurface` | Curves on surface ID |

### Set-Based Rules (AddSetRule)

Use when the rule input is another Set rather than a single ID:

```vb
' Get all nodes on elements in elemSet:
nodeSet.AddSetRule(elemSet.ID, FGD_NODE_ONELEM)

' Get elements using any property in propSet:
elemSet.AddSetRule(propSet.ID, FGD_ELEM_BYPROP)
```

### Boolean Operations on Sets

```vb
resultSet.AddSet(otherSet.ID)      ' Union: add all from otherSet
resultSet.RemoveSet(otherSet.ID)   ' Difference: remove all in otherSet
resultSet.IntersectSet(otherSet.ID) ' Intersection: keep only common IDs
```

## Array Conversion

Convert between Set and array for bulk operations:

```vb
' Set → Array
Dim count As Long
Dim vIDs As Variant
count = mySet.Count
mySet.GetArray(count, vIDs)    ' vIDs now contains all IDs

' Array → Set
Dim ids(4) As Long
ids(0) = 1 : ids(1) = 5 : ids(2) = 10 : ids(3) = 20 : ids(4) = 30
mySet.AddArray(5, ids)
```

## Testing Membership

```vb
If mySet.IsAdded(42) Then
    ' ID 42 is in the set
End If

If mySet.IsEmpty() Then
    ' Set has no entries
End If
```

## SavedSet Methods

Sets can be saved to and loaded from the Femap database (persisted between sessions):

```vb
' Save a named set
rc = mySet.SaveSet("My Element Selection")

' Load a previously saved set
rc = mySet.LoadSet("My Element Selection")

' Delete a saved set
rc = mySet.DeleteSavedSet("My Element Selection")
```

## Selector Object

The Selector Object (`App.feSelector`) provides access to the graphical selection
state in Femap. It's useful for reading what the user has selected in the GUI:

```vb
Dim sel As femap.Selector
Set sel = App.feSelector

' Get the current selection as a Set
Dim selSet As femap.Set
Set selSet = App.feSet
rc = sel.GetSelected(FT_ELEM, selSet)
```

### Selector Methods

| Method | Description |
|---|---|
| `GetSelected(type, set)` | Get currently selected entities of type into set |
| `Select(type, set)` | Programmatically select entities in GUI |
| `Deselect(type, set)` | Deselect entities |
| `DeselectAll(type)` | Deselect all of given type |
| `Highlight(type, set)` | Highlight entities without selecting |

## Common Patterns

### Select Property → Get Elements → Get Nodes

```vb
Dim propSet As femap.Set : Set propSet = App.feSet
Dim elemSet As femap.Set : Set elemSet = App.feSet
Dim nodeSet As femap.Set : Set nodeSet = App.feSet

rc = propSet.Select(FT_PROP, True, "Select Properties")
elemSet.AddSetRule(propSet.ID, FGD_ELEM_BYPROP)
nodeSet.AddSetRule(elemSet.ID, FGD_NODE_ONELEM)

App.feAppMessage(FCM_NORMAL, "Found " + Str$(nodeSet.Count) + " nodes")
```

### Filter Elements by Type

```vb
Dim allElem As femap.Set : Set allElem = App.feSet
Dim quadSet As femap.Set : Set quadSet = App.feSet

allElem.AddAll(FT_ELEM)
quadSet.AddRule(FET_L_PLATE, FGD_ELEM_BYTYPE)    ' Linear plates
quadSet.IntersectSet(allElem.ID)                   ' Only existing elements
```

### Get Elements on a Surface

```vb
Dim surfElem As femap.Set : Set surfElem = App.feSet
surfElem.AddRule(surfaceID, FGD_ELEM_ATSURFACE)
```
