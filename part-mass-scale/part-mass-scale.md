# Part Mass Scale

Scales the mass of user-selected elements by modifying material densities, CONM2 mass values, and non-structural mass. Includes a verification step that compares recalculated mass against the expected scaled mass.

**Last updated:** 2026-02-23

## Usage

- Run in Femap's API Programming window
- Select the elements whose mass you want to scale
- Enter a scale factor in the dialog (e.g. 1.5 = 150% of original mass)
- The tool applies the factor to material densities, CONM2 properties, and NSM values

## What It Scales

- Material densities for all materials referenced by selected elements
- CONM2 mass properties (Mx, My, Mz and all inertia terms)
- Non-structural mass (NSM) on shell, beam, rod, and laminate properties
- PCOMP ply material densities via the Layup object

## Warnings

- Detects shared materials/properties used by elements outside your selection and prompts before proceeding
- Reports Connection Region NSM if present (not auto-scaled)

## Verification

- Recalculates mass after scaling and reports PASS/MARGINAL/FAIL based on % difference
- Reports per-category breakdown (structural vs non-structural) and CG shift
