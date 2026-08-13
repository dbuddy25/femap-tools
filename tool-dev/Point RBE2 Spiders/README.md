# Point RBE2 Spiders

Builds one RBE2 spider per picked **mesh point** or **geometric point**, gathering the legs from a user-scoped pool of nearby nodes. The sibling of *Batch Hole RBE2 Spiders*, for locations that have no hole geometry to key off.

**Last updated:** 2026-08-13
**Status:** Built and run in Femap; spiders verified correct.

## Usage

- Run in Femap's API Programming window
- Pick the point source (**Mesh Points** or **Points**) and the dependent DOF (**123456** shell / **123** solid)
- Select the points that mark the spider centers
- Select the **candidate node pool** — the nodes the legs are allowed to come from
- Set leg selection (radius or N nearest) and options, then review the tally dialog and click OK

## What It Does

- Resolves each picked point to an XYZ (mesh points use their on-geometry location if associated to geometry, otherwise their underlying point's coords)
- For each point: creates a new center node **at the point location**, finds the surrounding nodes in the candidate pool, and builds an RBE2 (independent = center node, dependent = the found nodes)
- Coincident nodes are expected and fine — a mesh point usually already forced a node at that location, and it just becomes a zero-length leg

## Options

- **Leg selection** — all nodes within a **radius**, or the **N nearest** nodes
- **CTE** on the RBE2s — from a model material (`mval(36)`) or a typed value
- **Project** the new center nodes onto a picked plane — **orthogonal** (along the plane normal), since there is no per-spider axis to travel along the way a bolt hole has one

## Output

- One RBE2 + one center node per point
- Summary report: points selected, candidate pool size, leg rule, spiders created, total legs, DOF, CTE, projection count

## Notes

- **Spiders created but not drawing?** Check **View > Visibility (Ctrl+Q) > Entity/Element > "elements with no property"**. RBE2s carry no property, so unchecking that box hides every rigid in the model — they still appear when highlighted, which makes it look like a creation failure. Next suspects: hidden layer, or a view filtered to a group.
- **Group → Automatic Add is handled if you use it.** With it on, new entities join the target group but leave it flagged as needing evaluation, so a group-filtered view won't draw them. The tool reads `Info_GroupAutomaticAdd`, evaluates that group, then regenerates. No-op if Automatic Add is off.
- **The candidate pool is the safety net.** A bare sphere will happily reach through a plate thickness or into an adjacent part. Scope the pool to the surface/group/part you actually want tied and the distance filter can't misbehave.
- Nodes already dependent on another RBE2/RBE3 are **not** screened — Nastran will reject a duplicate dependent DOF. Check the pool if the model already has rigids in the area.
- Node coordinates from the API are global rectangular, so the radius is a plain global sphere.
- Mesh point handling (`feMeshHardPoint`, `vLocationOnGeometry`, `PointID`) is written from the API guide and has not been exercised against a live model yet.
