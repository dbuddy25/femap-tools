# Batch Hole RBE2 Spiders

Builds one RBE2 spider per clearance (bolt) hole from selected hole **surfaces** (solid bore) or hole-edge **curves** (shell/plate), grouping the picked geometry into individual holes automatically.

**Last updated:** 2026-06-11
**Status:** Archived — deployed to internal repo.

## Usage

- Run in Femap's API Programming window
- Pick the geometry mode: **Surfaces** (solid bore) or **Curves** (shell/plate hole edge)
- Select the hole surfaces (or hole-edge curves) — the whole bolt pattern at once is fine
- Review the confirm dialog (hole count, total nodes, DOF), set options, click OK

## What It Does

- Groups the selected surfaces/curves into individual holes by shared geometric points (a hole is usually 2+ pieces sharing the bore/edge seam points)
- For each hole: gathers the bore/edge mesh nodes, creates a new center node at their centroid (on the hole axis), and builds an RBE2 (independent = center node, dependent = ring nodes)
- Dependent DOF by mode: **123** for surfaces (solid), **123456** for curves (shell)

## Options

- **CTE** on the RBE2s — from a model material (`mval(36)`) or a typed value
- **Project** the new center nodes onto a picked plane — each node moves along its own hole axis so it stays centered on the hole

## Output

- One RBE2 + one center node per hole
- Summary report: geometry selected, holes found, spiders created, DOF, CTE applied, projection counts
