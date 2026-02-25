# Renumber Groups

Renumbers all entities (nodes, elements, CSys, materials, properties) in selected groups into non-overlapping ID ranges with growth buffer. Uses an Excel spreadsheet for interactive confirmation and editing.

**Last updated:** 2026-02-25

## Usage

1. Run the tool — a group selection dialog appears
2. Select the groups you want to renumber
3. An Excel spreadsheet opens showing two sections:
   - **Small groups** (max entity count <= 100) — ranges round to nearest 100, starting at ID 1
   - **Large groups** (max entity count > 100) — ranges round to nearest 1000, starting at ID 100001
4. Edit the yellow **Start ID** and light-yellow **Range Size** cells as needed
5. The **Headroom** column (read-only) shows the gap between each group's End ID and the next group's Start ID — negative values mean overlap
6. Click OK in the MsgBox to proceed, Cancel to abort
7. A confirmation dialog shows entity/range conflicts and inter-group overlap warnings
8. Entities are renumbered in dependency order: CSys, Materials, Properties, Elements, Nodes
9. Results are printed to the Femap message pane

## Excel Column Layout

| Col | Header     | Editable | Notes |
|-----|------------|----------|-------|
| A   | Group Name | No       |       |
| B-F | CSys, Matl, Prop, Elem, Node | No | Entity counts per type |
| G   | Max        | No       | Largest entity count across types |
| H   | Cur Min    | No       | Current minimum ID across all entity types |
| I   | Cur Max    | No       | Current maximum ID across all entity types |
| J   | Start ID   | **Yes**  | Yellow highlight — target start ID |
| K   | End ID     | No       | Formula: Start ID + Range Size - 1 |
| L   | Range Size | **Yes**  | Light yellow highlight — allocated range |
| M   | Headroom   | No       | Range Size minus Max Count (unused IDs within allotted range) |

## How Ranges Work

- Each group gets a range sized to 1.5x its largest entity count
- Large groups (>100 entities): rounded up to nearest 1000, minimum 1000
- Small groups (<=100 entities): rounded up to nearest 100, minimum 100
- Ranges are assigned sequentially within each section

## Conflict Detection

Two checks run after the user confirms in Excel:

1. **Entity conflicts**: For each entity type, finds IDs outside the selected groups that fall within a target range
2. **Inter-group overlap**: Checks all pairs of selected groups for overlapping target ranges

Both append to the same warning list shown in the confirmation MsgBox.

## Code Architecture

| Section | Purpose |
|---------|---------|
| 1       | Group selection dialog, collect group IDs/titles |
| 2       | Count entities per group, track current min/max IDs |
| 2.5     | Partition groups into large/small, build sort order |
| 3       | Calculate range sizes (round to 100 or 1000) |
| 4       | Excel spreadsheet: build, display, read back values |
| 4→5     | Conflict check (entity + inter-group overlap) |
| 5       | Two-pass renumber: evacuate all groups to temp IDs (900M+), then place at target start IDs — prevents collisions when groups' current IDs overlap target ranges |
| 6       | Report results to Femap message pane |
