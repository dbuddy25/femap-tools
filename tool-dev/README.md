# Femap Custom Tools

Custom VBA tools for Femap FEA preprocessing workflows. Each tool is in its own folder under `tool-dev/`.

## Tools

### reconnect-RBE2-via-surface
Reconnects a single RBE2 element to new mesh nodes on selected surfaces after remeshing. Replaces dependent nodes while preserving the independent node and DOF settings, then cleans up orphaned old nodes.

**Use case:** Reattach an RBE2 spider to a remeshed surface without manually re-pointing nodes.

### batch-reconnect-RBE2
Reconnects multiple RBE2 elements to new surfaces after remeshing. Automatically matches each surface to the nearest RBE2 based on old dependent node positions (centroid proximity), then updates all connections and cleans up orphans in one pass.

**Use case:** Bulk reattach all RBE2 spiders (e.g., a bolt pattern) after remeshing multiple surfaces.

### renumber-groups
Renumbers all entities (nodes, elements, coordinate systems, materials, properties) in selected groups into non-overlapping ID ranges. Opens an interactive Excel spreadsheet where you can review and edit Start IDs, Range Sizes, and mark groups to Skip. Includes conflict detection for range overlaps.

**Use case:** Organize IDs when combining multiple FEA subassemblies into a single model while avoiding ID collisions.

### part-mass-scale
Scales the mass of selected elements by modifying material densities, CONM2 mass values, and non-structural mass. Includes a verification step that recalculates total mass and reports pass/fail based on percent difference from the target.

**Use case:** Adjust component weight to match actual hardware or prototype measurements while preserving mass distribution.

### duplicates-in-groups
Scans selected groups and identifies entities (nodes, elements, coordinate systems, materials, properties) that appear in more than one group. Reports exactly which group pairs share entities.

**Use case:** Detect unintended shared entities across assembly groups that should be isolated.

### export-contact-cards
Extracts contact bulk data cards (BSURF, BSURFS, BCPROP, BCPROPS, BGSET, BGADD, BCTSET, BCTADD, BGPARM) from a full NX Nastran deck export. Writes a standalone BDF file with just the contact definitions.

**Use case:** Isolate glued contact definitions from a complete Nastran deck for documentation, review, or transfer to other analyses.
