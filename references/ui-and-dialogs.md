# UI and Dialogs

## Custom Dialogs (WinWrap Basic)

WinWrap Basic provides a `Begin Dialog` / `End Dialog` construct for creating
modal dialog boxes within Femap scripts.

### Basic Dialog Structure

```vb
Begin Dialog MyDialog 350, 220, "Dialog Title"
    ' Static text
    Text 10, 10, 100, 14, "Label text:"

    ' Text input
    TextBox 120, 8, 150, 14, .inputField

    ' Checkbox
    CheckBox 10, 30, 200, 14, "Enable option", .chkOption

    ' Radio buttons (grouped by GroupBox)
    GroupBox 10, 50, 200, 60, "Options"
    OptionButton 20, 65, 80, 14, "Option A", .optA
    OptionButton 20, 80, 80, 14, "Option B", .optB
    OptionButton 20, 95, 80, 14, "Option C", .optC

    ' Drop-down list
    DropListBox 10, 120, 200, 70, items$(), .listChoice

    ' Combo box (editable drop-down)
    ComboBox 10, 140, 200, 70, items$(), .comboChoice

    ' List box
    ListBox 10, 160, 200, 60, items$(), .listSel

    ' Buttons
    OKButton 60, 190, 80, 20
    CancelButton 160, 190, 80, 20
    PushButton 250, 190, 80, 20, "Custom", .btnCustom
End Dialog
```

### Using the Dialog

```vb
Sub Main
    Dim App As femap.model : Set App = feFemap()

    ' Prepare list items
    Dim items$(2)
    items$(0) = "Item 1"
    items$(1) = "Item 2"
    items$(2) = "Item 3"

    ' Show dialog
    Dim dlg As MyDialog
    dlg.inputField = "default"    ' Set defaults
    dlg.chkOption = 1             ' Checked
    dlg.listChoice = 0            ' First item

    Dim result As Long
    result = Dialog(dlg)

    If result = -1 Then           ' OK pressed
        Dim userVal As String
        userVal = dlg.inputField
        Dim checked As Boolean
        checked = (dlg.chkOption = 1)
        Dim selected As Long
        selected = dlg.listChoice

        App.feAppMessage(FCM_NORMAL, "Input: " + userVal)
    Else
        App.feAppMessage(FCM_WARNING, "User cancelled")
    End If
End Sub
```

### Dialog Controls Reference

| Control | Syntax | `.field` Type |
|---|---|---|
| `Text` | `Text x, y, w, h, "label"` | (no field — static) |
| `TextBox` | `TextBox x, y, w, h, .field` | String |
| `CheckBox` | `CheckBox x, y, w, h, "label", .field` | Long (0/1) |
| `OptionButton` | `OptionButton x, y, w, h, "label", .field` | Long (0/1) |
| `GroupBox` | `GroupBox x, y, w, h, "title"` | (no field — container) |
| `DropListBox` | `DropListBox x, y, w, h, items$(), .field` | Long (index) |
| `ComboBox` | `ComboBox x, y, w, h, items$(), .field` | String |
| `ListBox` | `ListBox x, y, w, h, items$(), .field` | Long (index) |
| `OKButton` | `OKButton x, y, w, h` | — |
| `CancelButton` | `CancelButton x, y, w, h` | — |
| `PushButton` | `PushButton x, y, w, h, "label", .field` | — |

> Coordinates are in dialog units (approximately pixels / 1.5).

### Dialog Return Values

| Return | Meaning |
|---|---|
| `-1` | OK button pressed |
| `0` | Cancel button pressed |
| `> 0` | PushButton index pressed |

---

## DialogFunc (Event Handling)

For dynamic dialog behavior, add a `DialogFunc` callback:

```vb
Begin Dialog MyDialog 300, 150, "Dynamic Dialog", .DialogFunc
    Text 10, 10, 100, 14, "Select type:"
    DropListBox 10, 28, 200, 60, types$(), .typeList
    Text 10, 50, 280, 14, "", .statusText
    OKButton 60, 120, 80, 20
    CancelButton 160, 120, 80, 20
End Dialog

Function DialogFunc(DlgItem$, Action%, SuppValue&) As Boolean
    Select Case Action%
        Case 1  ' Dialog initialized
            DlgText "statusText", "Ready"
            DialogFunc = True
        Case 2  ' Control changed or button pressed
            If DlgItem$ = "typeList" Then
                DlgText "statusText", "Selected: " + types$(DlgValue("typeList"))
                DialogFunc = True  ' Don't close dialog
            End If
            If DlgItem$ = "OK" Then
                DialogFunc = False ' Allow close
            End If
        Case 3  ' Text changed
            DialogFunc = True
    End Select
End Function
```

### DialogFunc Actions

| Action | Description |
|---|---|
| 1 | Dialog initialization |
| 2 | Button clicked or control value changed |
| 3 | Text box content changed |
| 4 | Focus changed |
| 5 | Idle processing |

### DialogFunc Helper Functions

| Function | Description |
|---|---|
| `DlgText(field, text)` | Set control text |
| `DlgText(field)` | Get control text |
| `DlgValue(field)` | Get control numeric value |
| `DlgValue(field, val)` | Set control numeric value |
| `DlgEnable(field, enable)` | Enable/disable control |
| `DlgVisible(field, vis)` | Show/hide control |
| `DlgListBoxArray(field, items$())` | Update list items |

---

## Messages

### Message Pane

```vb
App.feAppMessage(FCM_NORMAL, "Normal message")
App.feAppMessage(FCM_COMMAND, "Command echo")
App.feAppMessage(FCM_ENTITY, "Entity info")
App.feAppMessage(FCM_WARNING, "Warning message")
App.feAppMessage(FCM_ERROR, "Error message")
App.feAppMessage(FCM_HIGHLIGHT, "Highlighted message")
```

### Message Box (Modal Dialog)

```vb
' type: 0=OK, 1=OK/Cancel, 2=Abort/Retry/Ignore, 3=Yes/No/Cancel, 4=Yes/No
Dim response As Long
response = App.feAppMessageBox(4, "Continue processing?")
' Returns: 1=OK, 2=Cancel, 3=Abort, 4=Retry, 5=Ignore, 6=Yes, 7=No
```

### Status Bar

```vb
App.feAppStatusBarMessage("Processing element " + Str$(i) + "...")
```

---

## Toolbar and Menu Customization

### Add Custom Toolbar Button

```vb
rc = App.feAppManageToolbars(toolbarName, show)
```

### Run Femap Commands Programmatically

```vb
' Run a Femap command by command string
rc = App.feRunCommand(commandID)

' Run a program file (.pro, .bas)
rc = App.feFileProgramRun(wait, echo, prompt, filename)
```

---

## Event Handling

### Event Callback

Register scripts to run when specific Femap events occur:

```vb
rc = App.feAppEventCallback(eventType, parameter)
```

| Event Constant | Description |
|---|---|
| `FEVENT_RESULTSEND` | Analysis results complete |
| `FEVENT_MODELCHANGED` | Model data changed |
| `FEVENT_VIEWCHANGED` | View settings changed |

### Register as Add-In

```vb
rc = App.feAppRegisterAddInPane(register, hwnd, msgID, _
    dockable, visible, location, size)
```

---

## Window Management

```vb
' Get/set active view
Dim viewID As Long
rc = App.feAppGetActiveView(viewID)

' Manage model windows
rc = App.feAppActivateModel(modelID)
rc = App.feAppGetActiveModel(modelID)

' Manage panes
rc = App.feAppManagePanes(paneName, state)
' state: 0=Hide, 1=Show, 2=Toggle
```

---

## Embedding and Automation

### Embed Femap in External Application

```vb
' Embed Femap graphics in an external window
rc = App.feAppEmbed(hwnd, x, y, width, height)
```

### Hide UI Elements

```vb
rc = App.feAppManageToolbars("", False)      ' Hide all toolbars
rc = App.feAppManageStatusBar(False)          ' Hide status bar
rc = App.feAppManagePanes("", 0)              ' Hide all panes
rc = App.feAppManageGraphicsTabs(False)       ' Hide graphics tabs
```

### Lock/Unlock for Performance

```vb
App.feAppLock()        ' Suppress all UI updates
' ... bulk operations ...
App.feAppUnlock()      ' Resume UI updates (must pair every Lock)
App.feViewRegenerate(0)
```

### Dialog Auto-Answer (Hidden Mode)

When running Femap as a hidden server, control dialog responses:

```vb
App.DialogAutoAnswer = True   ' Auto-answer dialogs
```

---

## Model Info Tree

```vb
' Add custom item to Model Info tree
rc = App.feAppModelInfoAdd(parentID, title, icon, id)

' Remove custom item
rc = App.feAppModelInfoRemove(id)
```

---

## Real Number Formatting

```vb
Dim formatted As String
formatted = ""
rc = App.feFormatReal(value, width, decimals, formatted)
```

---

## Library Management

```vb
' Read entity from library file
rc = entity.GetLibrary(filename, libraryID)

' Write entity to library file
rc = entity.PutLibrary(filename, libraryID)
```
