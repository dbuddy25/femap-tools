# Constants and Enumerations

All Femap API constants are accessible by name in WinWrap Basic when the Femap
Type Library is referenced (automatic in the API Programming window).

## Entity Type Constants (FT_*)

Used with `Set.Select()`, `Set.AddAll()`, `App.feDelete()`, etc.

| Constant | Value | Entity |
|---|---|---|
| `FT_POINT` | 1 | Point |
| `FT_CURVE` | 3 | Curve |
| `FT_SURFACE` | 5 | Surface |
| `FT_VOLUME` | 7 | Volume |
| `FT_NODE` | 9 | Node |
| `FT_ELEM` | 10 | Element |
| `FT_CSYS` | 11 | Coordinate System |
| `FT_MATL` | 12 | Material |
| `FT_PROP` | 13 | Property |
| `FT_LOAD_DIR` | 15 | Load Set |
| `FT_BC_DIR` | 17 | Constraint Set |
| `FT_BCO` | 18 | Nodal Constraint |
| `FT_BCO_GEOM` | 19 | Geometric Constraint |
| `FT_BEQ` | 20 | Constraint Equation |
| `FT_TEXT` | 21 | Text |
| `FT_VIEW` | 22 | View |
| `FT_GROUP` | 23 | Group |
| `FT_OUT_CASE` | 25 | Output Set |
| `FT_VECTOR` | 26 | Output Vector |
| `FT_PLANE` | 27 | Plane |
| `FT_BOUNDARY` | 28 | Boundary |
| `FT_LAYER` | 30 | Layer |
| `FT_FUNCTION_DIR` | 32 | Function |
| `FT_SOLID` | 33 | Solid |
| `FT_COLOR` | 34 | Color |
| `FT_FUNCTION_TABLE` | 36 | Function Table |
| `FT_MESH_POINT` | 37 | Mesh Point |
| `FT_DATA_SURF` | 8 | Data Surface |
| `FT_CONNECTION` | 38 | Connection (Connector) |
| `FT_CONNECTION_PR` | 39 | Connection Property |
| `FT_REPORT` | 29 | Report (Output Format) |
| `FT_LAYUP` | 14 | Layup |
| `FT_LAYUP_PLY` | 16 | Layup Ply |
| `FT_BOLT_PRELOAD` | 41 | Bolt Preload |
| `FT_FREQUENCY` | 42 | Frequency |
| `FT_AERO_PANEL` | 43 | Aero Panel |
| `FT_AERO_PROP` | 44 | Aero Property |
| `FT_AERO_SPLINE` | 45 | Aero Spline |
| `FT_AERO_SURF` | 46 | Aero Surface |
| `FT_FREEBODY` | 47 | Freebody |
| `FT_RES_ATTACH` | 48 | Attached Results File |
| `FT_CHART` | 49 | Chart |
| `FT_CHART_SERIES` | 50 | Chart Data Series |
| `FT_BC_DEFINITION` | 51 | Constraint Definition |
| `FT_JOINT` | 52 | Kinematic Joint |
| `FT_MONITOR_POINT` | 53 | Monitor Point |
| `FT_MATRIX_INPUT` | 54 | Direct Matrix Input |
| `FT_ANALYSIS_STUDY` | 55 | Analysis Study |
| `FT_DISCRETE_VALUE` | 56 | Discrete Value Set |

### Load Sub-Types

| Constant | Description |
|---|---|
| `FT_SURF_LOAD` | Nodal or Elemental Load |
| `FT_NTHERM_LOAD` | Nodal Temperature |
| `FT_ETHERM_LOAD` | Elemental Temperature |
| `FT_GEOM_LOAD` | Geometric Load |

---

## Element Type Constants (FET_*)

Used with `Elem.type` property.

### Line Elements

| Constant | Value | Element |
|---|---|---|
| `FET_L_ROD` | 2 | Linear Rod |
| `FET_L_TUBE` | 3 | Linear Tube |
| `FET_L_BAR` | 5 | Linear Bar |
| `FET_L_BEAM` | 6 | Linear Beam |
| `FET_P_BEAM` | 7 | Parabolic Beam |
| `FET_L_CURVED_BEAM` | 8 | Linear Curved Beam |
| `FET_L_LINK` | 9 | Linear Link |
| `FET_L_SPRING` | 15 | Linear Spring/CBUSH |
| `FET_L_DOF_SPRING` | 16 | DOF Spring |
| `FET_L_GAP` | 14 | Gap |
| `FET_L_RIGID` | 29 | Rigid (RBE2/RBE3) |

### Plate Elements

| Constant | Value | Element |
|---|---|---|
| `FET_L_PLATE` | 20 | Linear Plate (CTRIA3/CQUAD4) |
| `FET_P_PLATE` | 21 | Parabolic Plate (CTRIA6/CQUAD8) |
| `FET_L_LAMINATE_PLATE` | 22 | Linear Laminate Plate |
| `FET_P_LAMINATE_PLATE` | 23 | Parabolic Laminate Plate |
| `FET_L_MEMBRANE` | 18 | Linear Membrane |
| `FET_P_MEMBRANE` | 19 | Parabolic Membrane |
| `FET_L_BENDING` | 24 | Linear Bending |
| `FET_P_BENDING` | 25 | Parabolic Bending (note: same as L_SOLID) |
| `FET_L_SHEAR` | 32 | Linear Shear |
| `FET_P_SHEAR` | 33 | Parabolic Shear |

### Solid Elements

| Constant | Value | Element |
|---|---|---|
| `FET_L_SOLID` | 25 | Linear Solid (CTETRA4/CHEXA8/CPENTA6) |
| `FET_P_SOLID` | 26 | Parabolic Solid (CTETRA10/CHEXA20/CPENTA15) |
| `FET_L_LAMINATE_SOLID` | 27 | Linear Laminate Solid |
| `FET_P_LAMINATE_SOLID` | 28 | Parabolic Laminate Solid |
| `FET_L_COHESIVE_SOLID` | 34 | Linear Cohesive Solid |
| `FET_P_COHESIVE_SOLID` | 35 | Parabolic Cohesive Solid |

### Other Element Types

| Constant | Value | Element |
|---|---|---|
| `FET_L_MASS` | 17 | Mass |
| `FET_L_MASS_MATRIX` | 30 | Mass Matrix |
| `FET_L_STIFF_MATRIX` | 31 | Stiffness Matrix |
| `FET_L_PLOT` | 10 | Plot Only |
| `FET_L_PLOT_PLATE` | 11 | Plot Plate |
| `FET_L_AXISYM` | 12 | Linear Axisymmetric |
| `FET_P_AXISYM` | 13 | Parabolic Axisymmetric |
| `FET_L_AXISYM_SHELL` | 4 | Linear Axisym Shell |
| `FET_P_AXISYM_SHELL` | 36 | Parabolic Axisym Shell |
| `FET_L_PLANE_STRAIN` | 1 | Linear Plane Strain |
| `FET_P_PLANE_STRAIN` | 37 | Parabolic Plane Strain |
| `FET_L_WELD` | 38 | Weld |
| `FET_L_CONTACT` | 39 | Contact |
| `FET_L_SLIDE_LINE` | 40 | Slide Line |
| `FET_L_SPRING_TO_GROUND` | 41 | Spring to Ground |
| `FET_L_DOF_SPRING_TO_GROUND` | 42 | DOF Spring to Ground |
| `FET_L_NASTRAN_MATRIX` | 43 | Nastran DMIG Matrix |

---

## Element Topology Constants (FTO_*)

Used with `Elem.topology` property.

| Constant | Value | Shape | Nodes |
|---|---|---|---|
| `FTO_POINT1` | 1 | Point | 1 |
| `FTO_LINE2` | 2 | Line (linear) | 2 |
| `FTO_LINE3` | 3 | Line (parabolic) | 3 |
| `FTO_TRIA3` | 4 | Triangle (linear) | 3 |
| `FTO_TRIA6` | 5 | Triangle (parabolic) | 6 |
| `FTO_QUAD4` | 6 | Quad (linear) | 4 |
| `FTO_QUAD8` | 7 | Quad (parabolic) | 8 |
| `FTO_TETRA4` | 8 | Tetrahedron (linear) | 4 |
| `FTO_TETRA10` | 9 | Tetrahedron (parabolic) | 10 |
| `FTO_WEDGE6` | 10 | Wedge/Penta (linear) | 6 |
| `FTO_WEDGE15` | 11 | Wedge/Penta (parabolic) | 15 |
| `FTO_BRICK8` | 12 | Hex (linear) | 8 |
| `FTO_BRICK20` | 13 | Hex (parabolic) | 20 |
| `FTO_PYRAMID5` | 14 | Pyramid | 5 |
| `FTO_RIGIDLIST` | 15 | RBE2 (variable nodes) | N |
| `FTO_RIGIDLIST2` | 16 | RBE3 (variable nodes) | N |
| `FTO_CONTACT2` | 17 | Contact pair | 2 |
| `FTO_WELD2` | 18 | Weld | 2 |
| `FTO_MULTILIST2` | 19 | Multi-point list | N |

---

## Message Color Constants (FCM_*)

Used with `App.feAppMessage()`.

| Constant | Value | Color / Usage |
|---|---|---|
| `FCM_NORMAL` | 0 | Normal (black) |
| `FCM_COMMAND` | 1 | Command (blue) |
| `FCM_ENTITY` | 2 | Entity info (green) |
| `FCM_WARNING` | 3 | Warning (orange) |
| `FCM_ERROR` | 4 | Error (red) |
| `FCM_HIGHLIGHT` | 5 | Highlight (magenta) |

---

## Group Data Rule Constants (FGD_*)

Used with `Set.AddRule()`, `Set.AddSetRule()`, `Group.AddRule()`.

### Element Rules

| Constant | Description |
|---|---|
| `FGD_ELEM_BYPROP` | Elements by property ID |
| `FGD_ELEM_BYMATL` | Elements by material ID |
| `FGD_ELEM_BYTYPE` | Elements by element type (FET_*) |
| `FGD_ELEM_BYSHAPE` | Elements by shape |
| `FGD_ELEM_ATSURFACE` | Elements on surface |
| `FGD_ELEM_ATSOLID` | Elements on solid |
| `FGD_ELEM_ATCURVE` | Elements on curve |
| `FGD_ELEM_BYNODE` | Elements using node(s) in set |
| `FGD_ELEM_BYLAYER` | Elements on layer |
| `FGD_ELEM_BYCOLOR` | Elements by color |

### Node Rules

| Constant | Description |
|---|---|
| `FGD_NODE_ONELEM` | Nodes on elements in set |
| `FGD_NODE_ATSURFACE` | Nodes on surface |
| `FGD_NODE_ATCURVE` | Nodes on curve |
| `FGD_NODE_ATPOINT` | Nodes at point |
| `FGD_NODE_BYLAYER` | Nodes on layer |
| `FGD_NODE_BYCOLOR` | Nodes by color |

### Geometry Rules

| Constant | Description |
|---|---|
| `FGD_Surface_onSolid` | Surfaces on solid |
| `FGD_Curve_onSurface` | Curves on surface |
| `FGD_Point_onCurve` | Points on curve |

---

## Output Type Constants (FOT_*)

Used when creating output via Results Browsing Object.

| Constant | Value | Description |
|---|---|---|
| `FOT_DISP` | 1 | Displacement |
| `FOT_VELOC` | 2 | Velocity |
| `FOT_ACCEL` | 3 | Acceleration |
| `FOT_FORCE` | 4 | Force |
| `FOT_STRESS` | 5 | Stress |
| `FOT_STRAIN` | 6 | Strain |
| `FOT_THERMAL` | 7 | Thermal |

---

## Return Code Constants

| Constant | Value | Meaning |
|---|---|---|
| `FE_OK` | -1 | Success |
| `FE_FAIL` | 0 | General failure |
| `FE_BAD_TYPE` | 1 | Invalid type |
| `FE_BAD_DATA` | 2 | Invalid data |
| `FE_NOT_EXIST` | 3 | Entity does not exist |
| `FE_CANCEL` | -2 | User cancelled operation |
| `FE_NO_MEMORY` | 4 | Out of memory |
| `FE_SECURITY` | 5 | License/security error |

---

## Analysis Manager Constants (FAM_*)

| Constant | Value | Solver |
|---|---|---|
| `FAM_NX_NASTRAN` | 7 | NX Nastran |
| `FAM_MSC_NASTRAN` | 2 | MSC Nastran |
| `FAM_ANSYS` | 4 | ANSYS |
| `FAM_ABAQUS` | 6 | Abaqus |
| `FAM_MARC` | 1 | Marc |
| `FAM_FEMAP_STRUCTURAL` | 5 | Femap Structural |

---

## Load Type Constants (FLT_*)

Used with `LoadMesh.type`.

| Constant | Description |
|---|---|
| `FLT_NFORCE` | Nodal Force |
| `FLT_NMOMENT` | Nodal Moment |
| `FLT_NDISPLACEMENT` | Enforced Displacement |
| `FLT_NVELOCITY` | Enforced Velocity |
| `FLT_NACCELERATION` | Enforced Acceleration |
| `FLT_NBODY` | Body Load |
| `FLT_NHEATGEN` | Nodal Heat Generation |
| `FLT_EPRESSURE` | Elemental Pressure |
| `FLT_EHEATFLUX` | Elemental Heat Flux |
| `FLT_ECONVECTION` | Elemental Convection |
| `FLT_ERADIATION` | Elemental Radiation |
| `FLT_EGRAVITY` | Gravity |

---

## Results Browsing Vector ID Query Constants (VPV_*, VPT_*, VPP_*, VPL_*)

Used with `ResultsIDQuery` methods for V2 vector ID lookup.

### Value Type (VPV_*)
| Constant | Description |
|---|---|
| `VPV_STRESS` | Stress |
| `VPV_STRAIN` | Strain |
| `VPV_FORCE` | Force |

### Component Type (VPT_*)
| Constant | Description |
|---|---|
| `VPT_X` | X component |
| `VPT_Y` | Y component |
| `VPT_Z` | Z component |
| `VPT_XY` | XY component |
| `VPT_YZ` | YZ component |
| `VPT_ZX` | ZX component |
| `VPT_MAJOR_PRIN` | Major principal |
| `VPT_MINOR_PRIN` | Minor principal |
| `VPT_MAX_SHEAR` | Maximum shear |
| `VPT_VON_MISES` | Von Mises |
| `VPT_TOTAL` | Total/magnitude |

### Position (VPP_*)
| Constant | Description |
|---|---|
| `VPP_TOP` | Top fiber |
| `VPP_MID` | Mid fiber |
| `VPP_BOT` | Bottom fiber |

### Location (VPL_*)
| Constant | Description |
|---|---|
| `VPL_CENTROID` | At centroid |
| `VPL_CORNER` | At corner |

---

## Event Constants (FEVENT_*)

Used with `App.feAppEventCallback()`.

| Constant | Description |
|---|---|
| `FEVENT_RESULTSEND` | Analysis results complete |
| `FEVENT_MODELCHANGED` | Model data changed |
| `FEVENT_VIEWCHANGED` | View settings changed |
