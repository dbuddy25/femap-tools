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

- Per-type duplicate count
- Per-group-pair breakdown showing how many entities are shared between each pair
- Grand total of all duplicate entities

## Performance

- Uses `feAppLock` to suppress UI redraws during scanning
- Prints progress every 10,000 entities for nodes and elements (which can be large)
- Materials, properties, and coordinate systems are typically small and scan quickly
