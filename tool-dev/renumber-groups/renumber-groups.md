# Renumber Groups

Renumbers all entities (nodes, elements, CSys, materials, properties) in selected groups into non-overlapping ID ranges with growth buffer. Uses an Excel spreadsheet for interactive confirmation and editing. Groups can be marked "Skip" to keep their current IDs while reserving their ID space.

**Last updated:** 2026-03-03

## Usage

1. Run the tool — a group selection dialog appears
2. Select the groups you want to renumber (including any you want to keep as-is)
3. An Excel spreadsheet opens showing two sections:
   - **Small groups** (max entity count <= 100) — ranges round to nearest 100, starting at ID 1
   - **Large groups** (max entity count > 100) — ranges round to nearest 1000, starting at ID 100001
4. Edit the yellow **Start ID** and light-yellow **Range Size** cells as needed
5. Type **Yes** in the **Skip** column for any group that should keep its current IDs
6. The **Headroom** column (read-only) shows unused IDs within each group's allotted range
7. Click OK in the MsgBox to proceed, Cancel to abort
8. A confirmation dialog shows entity/range conflicts and inter-group overlap warnings
9. Entities are renumbered in dependency order: CSys, Materials, Properties, Elements, Nodes
10. Results are printed to the Femap message pane — group names appear as section headers with entity rows underneath, followed by a skipped groups summary

## Skip (Keep As-Is)

- Mark a group with "Yes" in the Skip column to exclude it from renumbering
- Skipped groups' actual occupied range (Cur Min to Cur Max) is reserved for conflict detection
- If a non-skipped group's target range overlaps a skipped group's entities, a warning is shown
- If all groups are marked Skip, the tool exits early with a message
- Skipped groups appear in a separate "Skipped (kept as-is)" section in the results report

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
| N   | Skip       | **Yes**  | Yellow highlight — type "Yes" to keep current IDs |

## How Ranges Work

- Each group gets a range sized to 1.5x its largest entity count
- Large groups (>100 entities): rounded up to nearest 1000, minimum 1000
- Small groups (<=100 entities): rounded up to nearest 100, minimum 100
- Ranges are assigned sequentially within each section

## Conflict Detection

Two checks run after the user confirms in Excel:

1. **Entity conflicts**: For each entity type, finds IDs outside the non-skipped selected groups that fall within a target range (skipped groups' entities are treated as obstacles)
2. **Inter-group overlap**: Checks all pairs of selected groups for overlapping target ranges (skips pairs where both groups are skipped)

Both append to the same warning list shown in the confirmation MsgBox.

## Code Architecture

| Section | Purpose |
|---------|---------|
| 1       | Group selection dialog, collect group IDs/titles |
| 2       | Count entities per group, track current min/max IDs |
| 2.5     | Partition groups into large/small, build sort order |
| 3       | Calculate range sizes (round to 100 or 1000) |
| 4       | Excel spreadsheet: build, display, read back values and skip flags |
| 4→5     | Conflict check (entity + inter-group overlap), skip-aware |
| 5       | Two-pass renumber (non-skipped groups only): evacuate to temp IDs (900M+), then place at target start IDs |
| 6       | Report results to Femap message pane — renumbered groups as section headers, skipped groups summary, combined totals |
