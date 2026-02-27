# Export Contact Cards

Exports BSURF/BGSET/BGADD Nastran bulk data cards for glued contact connectors to a .bdf include file.

**Last updated:** 2026-02-27

## Usage

1. Run the tool — it scans for all glued connectors (ConnectionProp type = 1)
2. A selection dialog shows all glued connectors pre-selected — deselect any you don't want
3. Choose a save location for the .bdf file
4. The tool writes the bulk data and prints a summary to the message pane

## Cards Written

| Card | Count | Purpose |
|------|-------|---------|
| **BSURF** | One per region | Lists element IDs belonging to each contact surface |
| **BGSET** | One per connector | Pairs source/target region IDs (SID = Femap connector ID) |
| **BGADD** | One (if >1 connector) | Combines all BGSETs (SID = max connector ID + 100) |

A case control comment at the bottom tells you which ID to reference: `$ Case Control: BGSET = <ID>`

## Edge Cases

- **No connectors in model** — error message, exits
- **No glued connectors** — error message, exits
- **User cancels selection** — exits
- **Region with 0 elements** — warning in message pane, BSURF skipped but BGSET still written
- **Single connector** — BGADD skipped, case control references BGSET directly

## Code Architecture

| Section | Purpose |
|---------|---------|
| 1 | Find all glued connectors (filter by ConnectionProp.type = 1) |
| 2 | User selection dialog with pre-selected glued connectors |
| 3 | Collect region data — titles, element sets via GetEntitySet |
| 4 | File save dialog (feFileGetName) |
| 5 | Write BDF file — BSURF, BGSET, BGADD cards in small-field format |
| 6 | Message pane summary — region table + connector list |
