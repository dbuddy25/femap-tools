# Femap Custom Tools

Custom VBA tools for Femap FEA preprocessing workflows. Each tool is in its own folder under `tool-dev/`.

## Tools

### reconnect-RBE2-via-surface
Reconnects a single RBE2 element to new mesh nodes on selected surfaces after remeshing. Replaces dependent nodes while preserving the independent node and DOF settings, then cleans up orphaned old nodes.

**Use case:** Reattach an RBE2 spider to a remeshed surface without manually re-pointing nodes.

### batch-reconnect-RBE2
Reconnects multiple RBE2 elements to new surfaces after remeshing. Automatically matches each surface to the nearest RBE2 based on old dependent node positions (centroid proximity), then updates all connections and cleans up orphans in one pass.

**Use case:** Bulk reattach all RBE2 spiders (e.g., a bolt pattern) after remeshing multiple surfaces.

### Renumber Groups  *(archived — deployed to internal repo; moved to [`archive/`](archive/Renumber%20Groups/Renumber%20Groups.md))*
Renumbers all entities (nodes, elements, coordinate systems, materials, properties) in selected groups into non-overlapping ID ranges. Opens an interactive Excel spreadsheet where you can review and edit Start IDs, Range Sizes, and mark groups to Skip. Includes conflict detection for range overlaps.

**Use case:** Organize IDs when combining multiple FEA subassemblies into a single model while avoiding ID collisions.

### Part Mass Scale  *(archived — deployed to internal repo; moved to [`archive/`](archive/Part%20Mass%20Scale/Part%20Mass%20Scale.md))*
Scales the mass of selected elements by modifying material densities, CONM2 mass values, and non-structural mass. Includes a verification step that recalculates total mass and reports pass/fail based on percent difference from the target.

**Use case:** Adjust component weight to match actual hardware or prototype measurements while preserving mass distribution.

### Duplicates in Groups  *(archived — deployed to internal repo; moved to [`archive/`](archive/Duplicates%20in%20Groups/Duplicates%20in%20Groups.md))*
Scans selected groups and identifies entities (nodes, elements, coordinate systems, materials, properties) that appear in more than one group. Reports exactly which group pairs share entities.

**Use case:** Detect unintended shared entities across assembly groups that should be isolated.

### export-contact-cards
Extracts contact bulk data cards (BSURF, BSURFS, BCPROP, BCPROPS, BGSET, BGADD, BCTSET, BCTADD, BGPARM) from a full NX Nastran deck export. Writes a standalone BDF file with just the contact definitions.

**Use case:** Isolate glued contact definitions from a complete Nastran deck for documentation, review, or transfer to other analyses.

### Batch Hole RBE2 Spiders  *(archived — deployed to internal repo; moved to [`archive/`](archive/Batch%20Hole%20RBE2%20Spiders/README.md))*
Select a set of clearance-hole (bolt-hole) **surfaces** (solid bore) or **curves** (shell/plate hole edge) and have Femap build one RBE2 spider per hole automatically. An up-front prompt chooses the geometry type. The selected entities are grouped into individual holes by shared geometric points (a hole is usually 2+ cylindrical surfaces, or 2+ half-circle curves, that share the bore/edge seam points), then for each hole the tool gathers all bore/edge mesh nodes, creates a new independent node at their centroid (on the bore axis, or the in-plane circle center for a shell hole), and builds an RBE2. Dependent DOF follows the mode: 123 for surfaces (solid nodes have no rotational stiffness) and 123456 for curves (shell nodes carry rotations). Optionally applies a thermal expansion coefficient (CTE) to the created RBE2s — either pick a model material (uses its thermal-expansion coeff, `mval(36)`) or enter a value. Optionally projects the new center nodes onto a user-picked plane after creation, moving each node along its own hole axis (from `ArcCircleInfo` / `feVectorAxisOfSurface`) so it stays centered on the hole even for tilted planes. Single confirm dialog before anything is written.

**Use case:** Quickly spider a whole bolt pattern for fastener modeling — pick the hole surfaces (solids) or hole-edge curves (shells), get clean RBE2s without manually finding nodes or creating center nodes one at a time.

### Connect Groups by CBUSH
Create CBUSH fastener elements between two parts (groups). Matches RBE2s whose independent (center) nodes are near each other across the two groups, draws a temporary visual preview of the proposed connections with gap-distance labels for verification, then builds one CBUSH per chosen location between the two center nodes. Supports two PBUSH types in one joint (e.g. fasteners + shear pins) via per-type rounds — pick a PBUSH property, select its locations, repeat — and applies one chosen orientation coordinate system to every CBUSH (`SetSpringOrient` with `FESO_ELCID`, valid for zero-length CBUSH). Results (CBUSH elements + PBUSH properties + orientation CSys) go into a new named group or an existing one.

**Use case:** Fasten two meshed parts at their bolt-hole spiders without hand-building each CBUSH — verify the auto-matched locations visually, then drop in fasteners and shear pins with the right properties and orientation in one pass.

### Ground Interface by CBUSH
Grounding variant of *Connect Groups by CBUSH*. Pick one group and a plane; the tool fastens the group's RBE2 spiders whose center node is within a tolerance of the plane to a single ground interface node. For each found spider it creates a coincident node + a zero-length CBUSH (fastener/shear-pin PBUSH, one orientation CSys), then ties all the new nodes to a new ground RBE2 (DOF 123456, optional CTE from material or value) whose center node sits at the centroid of the pattern projected onto the plane. Results split into two groups (each new or existing): the CBUSH elements + PBUSH(es) + CSys (no nodes), and the ground RBE2 with its nodes.

**Use case:** Build a single ground/boundary interface for a bolted part — represent the fasteners and collapse the attachment to one node for applying constraints or loads.

### Mode Identification (ESE EKE)
Modal post-processing: for each selected output set (mode) and element group, reports the group's % Element Strain Energy (ESE) and % Element Kinetic Energy (EKE), into one Excel sheet (ESE and EKE side by side, each with a per-mode Total column and red/green data bars). Resolves the energy output vectors at runtime via `ResultsIDQuery` (no hardcoded IDs — version-proof, no hand-editing when results change). Populates the Results browser once per mode and sums per group via the set-limit argument for speed. Warns if the selected groups don't cover all model elements (totals < 100%) or overlap (> 100%).

**Use case:** Identify the nature of vibration modes — see which parts carry the strain vs kinetic energy of each mode, ranked by group, to interpret a normal-modes (SOL 103) run.

### Remove From Groups
Pick entities once, see every group that currently contains them, and remove them from the groups you choose — in one pass. Femap's `Group → <entity> → Remove` works on the *active* group only, so stripping one node out of a dozen groups otherwise means activating and re-picking a dozen times. Supports Node, Element, Point, Curve, Surface, Solid, Volume, Property, Material and CSys. The scan reports each containing group with a hit count (`3 of 8`), then Femap's own group-selection dialog opens pre-loaded with exactly those groups so you deselect the ones to keep. A **Report only** mode answers "which groups is this node in?" without touching the model. Removal appends a `SetAddOpt(..., 0)` Remove rule to the end of each group's rule list — existing rules are left untouched, so a generative rule keeps generating and the trailing Remove is permanent until deleted in `Group → Operations → Edit Rules`; the summary reprints that warning on every modifying run.

**Use case:** A stale or misfiled node/element is referenced by several groups after a remesh or an over-generous selection rule — get it out of the ones that matter without hunting group by group.

### Group Mass Properties
Per-group mass, CG and inertia for a set of selected groups, into one flat Excel table (single header row, AutoFilter, frozen panes) with a combined totals row. The coordinate system is chosen once from a dropdown built from the model. Groups are measured with `feMeasureMeshMassProp`; overlapping, empty and zero-mass groups are detected and flagged. The totals row sums the about-origin inertias (valid — all about one point) and applies the parallel-axis theorem once to reach the combined CG, rather than summing per-group about-CG values that are each about a different point. Because the API guide never states whether the off-diagonal terms are products of inertia or inertia-tensor terms — and the parallel-axis sign flips with it — the tool determines the convention at runtime from the two arrays it already has, corroborates across three slots, and blanks the totals inertia rather than guessing if it can't. Totals CG is likewise blanked when groups overlap or any group reported negative mass. The totals are then checked end-to-end: the union of the selected groups is measured directly by Femap in one extra call, and its mass, CG and inertia-about-CG compared against the tool's own — which validates the summation, the parallel-axis shift and the detected sign convention in a single PASS/FAIL, on the user's own model.

**Use case:** Mass-properties reporting across an assembly — pick the groups that make up the parts, get one sortable table of what each weighs and where its CG sits, plus a trustworthy rollup for the whole selection.
