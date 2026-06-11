# Batch Hole RBE2 Spiders

*(file: `Batch Hole RBE2 Spiders.bas`; formerly `make-rbe2-from-holes`)*

**Status:** Archived — deployed to the internal repo (2026-06-11). Kept here for reference; further changes happen in the internal repo.

Custom tool to build **RBE2 spiders on clearance (bolt) holes** in one shot. Select
the hole geometry — cylindrical **surfaces** (solid models) or hole-edge **curves**
(shell/plate models) — and the tool figures out which pieces belong to the same
hole, creates a center node on the bore axis, and connects an RBE2 to the ring of
mesh nodes. Handles a whole bolt pattern at once.

## How it works

A single clearance hole is rarely one clean entity — it's usually **2+ surfaces**
(half-cylinders of a solid bore) or **2+ arcs** (half-circles of a shell cutout)
that **share their seam points**. The tool groups the selected geometry into holes
by that shared-point relationship, then for each hole:

1. Gathers every mesh node on the hole's surface(s)/curve(s).
2. Drops a new **independent node** at the centroid of those nodes — which lands on
   the bore axis (mid-thickness for a solid bore, the circle center in-plane for a
   shell hole).
3. Creates one **RBE2**: independent = center node, dependent = the ring/bore nodes.

### Grouping by shared points

Surfaces (or curves) belong to the same hole **iff they share a geometric point**.
This is robust because distinct holes are separated by the plate/solid and never
share points, so two adjacent bolt holes can't accidentally merge. Implemented as a
small **union-find**: collect each entity's boundary points
(`FGD_POINT_ONSURFACE` / `FGD_POINT_ONCURVE`), union any two entities that share a
point, and each resulting group is one hole.

### Dependent DOF by mode

| Mode | Geometry | Dependent DOF | Why |
|---|---|---|---|
| **Surfaces** | solid bore | **123** | solid element nodes have no rotational stiffness — coupling 456 is meaningless and can trip solver warnings |
| **Curves** | shell/plate edge | **123456** | shell nodes carry rotational DOF |

The independent node's DOF flags (`Release(0,0..5)`) are all set, so the center node
drives all six DOF; the per-dependent-node DOF lives in the `PutNodeList` array.

## Workflow

1. **Geometry-type prompt:** choose **Surfaces (Solid Mesh)** or **Curves (Plate
   Mesh)** — Femap's selector is entity-type specific, so the mode is picked first.
2. **Select** the hole surfaces/curves (one pick; the whole bolt pattern is fine).
3. Tool groups them into holes and gathers nodes (no model changes yet).
4. **Confirm dialog** (single dialog, nothing written until OK) showing hole count,
   total nodes, and the DOF that will be used, with options:
   - **Apply CTE to RBE2s** — thermal expansion coefficient, either **from a model
     material** (dropdown; uses its `mval(36)` α) or a **typed value**.
   - **Project center nodes onto a plane** (see below).
5. Creates one RBE2 per hole, printing a per-hole line (RBE2 id, center node id,
   dependent count).
6. If projection was checked, prompts for the plane and moves the center nodes.
7. **Summary** report: surfaces/holes/spiders, DOF, CTE, projection counts. Holes
   with no mesh nodes are reported as skipped (no crash).

## Optional: project center nodes onto a plane

After creation, the center nodes can be projected onto a user-picked plane
(`fePlanePick`) — useful when the fastener attach point must sit on a mating face,
bolt-head plane, or mid-surface rather than at the hole's mid-thickness.

**Staying centered is the whole point.** Each node moves **along its own hole axis**
(the bolt centerline) until it pierces the plane, so it stays on the hole centerline
for **any** plane tilt — not the nearest point on the plane. The axis comes straight
from geometry:

- Curve mode: `Curve.ArcCircleInfo` → arc **normal** is the axis.
- Surface mode: `feVectorAxisOfSurface` → revolution **vecDir** is the axis.

Math (no built-in projector exists): with center `C`, axis `a`, plane base `B`,
normal `N` → `t = ((B − C)·N)/(a·N)`, `Cnew = C + t·a`. If a hole's axis can't be
read (non-revolute surface / non-arc curve) or is parallel to the plane, it falls
back to **orthogonal** projection and is counted/warned in the report.

Only the independent (center) node moves; the dependent ring nodes stay on the hole.
An RBE2 independent node may sit anywhere, so an offset attach point is valid.

## Key API (verified against api.pdf)

| Need | Surface mode | Curve mode |
|---|---|---|
| Interactive selection | `Set.Select(FT_SURFACE, …)` | `Set.Select(FT_CURVE, …)` |
| Boundary points (grouping) | `FGD_POINT_ONSURFACE` | `FGD_POINT_ONCURVE` |
| Mesh nodes | `FGD_NODE_ATSURFACE` | `FGD_NODE_ATCURVE` |
| Hole axis (projection) | `feVectorAxisOfSurface(suID, base, vecDir)` | `Curve.ArcCircleInfo(ctr, normal, …)` |

- **RBE2 create:** `Elem` with `type = FET_L_RIGID` (29), `topology = FTO_RIGIDLIST`
  (13), `node(0) = centerNode`, `Release(0,0..5) = 1`, then
  `PutNodeList(0, count, vNodes, vFaces, vWeights, vDOF)` (6 DOF flags/node), then
  `Put(NextEmptyID)`. No property/material needed (RBE2 is property-less).
- **CTE on RBE2:** `Elem.RigidThermalExpansion` (REAL8), set before `Put`.
- **Material α (isotropic):** `Matl.Get(id)` → `mval(36)`.
- **Node coords:** `Node.x/y/z` are **always global rectangular**, so the centroid
  needs no CSys transform.
- **Plane pick:** `fePlanePick(title, plBase, plNormal, plAxis)` — pass the output
  arrays as **Variant**.

## Notes / gotchas

- Select **only** hole geometry, all of one type per run.
- A full-circle hole modeled as a single surface/curve still works — it's just a
  one-member group.
- WinWrap Basic identifiers are **case-insensitive** (`cx` and `Cx` are the same
  name) — watch for accidental duplicate `Dim`s when editing.
