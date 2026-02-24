# Renumber Groups

Renumbers all entities (nodes, elements, coordinate systems, materials, properties) in selected groups into non-overlapping ID ranges with growth buffer.

**Last updated:** 2026-02-24

## Usage

- Run in Femap's API Programming window
- Select 1 or more groups to renumber
- A dialog shows per-group entity counts, assigned ranges, and conflict warnings
- Change the start ID and click **Recalculate** to see updated ranges and conflicts
- Click **OK** to proceed or **Cancel** to abort
- Entities are renumbered in dependency order: CSys, Materials, Properties, Elements, Nodes

## How Ranges Work

- Each group gets a range sized to 1.5x its largest entity count, rounded up to the nearest 1000 (minimum 1000)
- Ranges are assigned sequentially with no gaps or overlaps
- Example: if "Wing Rib 1" has 3200 entities max, its range is 5000 (3200 * 1.5 = 4800, rounded up to 5000)

## Conflict Detection

- Before renumbering, the tool checks if any entities outside the selected groups already occupy the target ID ranges
- If conflicts are found, they are listed in the confirmation dialog as warnings
- You can cancel and choose a different starting ID to avoid conflicts

## Output

- Per-group breakdown of start ID and entity counts renumbered by type
- Total entity count renumbered
