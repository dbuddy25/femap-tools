# Duplicates in Groups

Checks for entities that appear in more than one of the user-selected groups and reports exactly which group pairs share them.

**Last updated:** 2026-02-23

## Usage

- Run in Femap's API Programming window
- Select 2 or more groups to check
- The tool scans all nodes, elements, coordinate systems, materials, and properties in the model
- For each entity found in multiple selected groups, it reports the count and which group pairs share it

## What It Checks

- Nodes
- Elements
- Coordinate Systems
- Materials
- Properties

## Output

- Per-type duplicate count (warning-colored text when duplicates found)
- Per-group-pair breakdown showing how many entities are shared between each pair
- For each type with duplicates, a new Femap group is created (e.g. "Dup Nodes", "Dup Elements") containing the duplicate entity IDs
- Grand total of all duplicate entities
