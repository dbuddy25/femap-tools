# Relative Displacement MPC

Instrument the relative displacement between two grids so it comes out of the solve as an
output quantity — no hand-subtracting two result vectors afterwards.

*(file: `Relative Displacement MPC.bas`)*

**Status:** Built, UNTESTED in Femap.

## Why

Relative displacement across a joint, a gap, or a fastener is normally recovered by pulling
two displacement vectors out of the results and subtracting them by hand — per direction,
per load case, per mode. That is tedious in statics and genuinely painful in modal and
frequency response, where there are hundreds of output sets.

An MPC constraint equation moves the subtraction into the solve. The solver produces the
relative displacement as a nodal result, so it plots, contours, animates and tabulates like
any other displacement, in every solution type.

## Use case

Bolted joint slip, gap closure between two parts, deflection of a bracket relative to the
structure it mounts to, or any "how far did A move with respect to B" question that has to be
answered across a lot of load cases.

## How it works

1. One options dialog, asked once: which translations to measure (T1/T2/T3), which constraint
   set the MPC equations go in (existing, or a new one created for you), the tracking node's
   output CSys (defaults to following the picked nodes), whether to show the confirm arrows,
   and a report-only mode.
2. Pick node **A** (measured *from*) and node **B**. Cancel at A to finish.
3. The pair is gated — see below. A pair that fails the gate is reported and skipped; the loop
   keeps going.
4. A colour-coded axis triad is drawn at both nodes and a confirm dialog restates the pair, the
   coordinate system and the sign convention.
5. On OK, the tool creates one **measurement node** at the midpoint of A and B and writes one
   constraint equation per requested direction:

   ```
   1.0*u_M(dof)  -  1.0*u_A(dof)  +  1.0*u_B(dof)  =  0     ->     u_M = u_A - u_B
   ```

6. The three nodes go into a group named `RelDisp <A>-<B>`.
7. Loop back to step 2 for the next pair. Everything already created survives quitting.

After the solve, the measurement node's T1/T2/T3 **are** the relative displacement of A with
respect to B, read directly off the node.

## The sign convention is A minus B

Node A is the one you measure *from*. Swap the picks and every number changes sign. The
confirm dialog restates this on every pair, and the summary repeats it, because it is
invisible in the results — a sign-flipped answer looks exactly as plausible as a correct one.

## The output coordinate system is the whole thing

A nodal DOF is expressed in that node's **output** coordinate system, not in global. So
`u_A(T1) - u_B(T1)` is only a meaningful subtraction when A and B share one output CSys.
Otherwise it subtracts motion along one direction from motion along a different one and
returns a number that means nothing.

So the tool gates: **both output systems must be rectangular and must have the same
orientation.** The measurement node takes node A's by default, so all three agree.

The test is on **orientation, not CSys ID**. Two systems with different IDs — and different
origins — but parallel axes resolve T1/T2/T3 along the same physical directions, so
subtracting them is perfectly valid and the pair is accepted, with a note in the Messages
window saying the tool checked. A DOF direction depends only on how a system is turned, never
on where it sits, which is why origins are ignored entirely. Comparing IDs would reject
correct work.

Orientation is compared by transforming each system's origin and unit points into global and
differencing, then matching the three axis vectors component-wise to 1e-6 (about 0.00006°).
Aligned systems agree to rounding, so anything looser than that really is a different
orientation, while the tolerance is still slack enough to survive a CSys built by picking
geometry.

**Overriding the tracking node's output CSys relabels the answer — it does not rotate it.**
The MPC equates DOF *numbers*: `u_M(T1) = u_A(T1) - u_B(T1)`, and those A and B terms resolve
in *their* output system. Giving the tracking node a different one transforms nothing: the
value it reports is still the relative displacement along the picked nodes' first axis, while
the node now calls that direction by another system's name. That is useful when the two
systems are parallel and you only want the label to match a reporting CSys, and silently wrong
when they are not — so every pair that overrides is warned about in the confirm dialog and
counted in the summary.

Cylindrical and spherical systems are refused rather than handled. Their directions depend on
position — the radial direction at A does not point the same way as the radial direction at B
even though both nodes name the same CSys ID — so the subtraction mixes directions. That is an
analysis question, not a coding one.

## Two things that look wrong and aren't

**The measurement node is deliberately unconstrained.** It has no elements, no mass and no
property. Its rotations — and any translation you did not instrument — are attached to nothing
and are singular by construction. They are left to `PARAM,AUTOSPC`. The summary reprints that
warning on every run that writes anything, because a shared copy of this tool must not let
somebody else's deck fail on a singularity nobody can explain.

**A grid node, not a SPOINT.** A scalar point carries only DOF 1, so three are needed for three
directions and every reading then lives in some SPOINT's T1 column, interpretable only next to
a lookup table. One grid node carries all three at once in the directions they are named. The
price is the free rotations above; the return is a result that explains itself to somebody who
did not run the tool.

## Implementation notes

**The dependent term order is not documented.** `api.pdf` specifies every argument of
`BCEqn.PutAll` except which term is the dependent DOF. Nastran convention is that the first
term is dependent, and the tool writes the measurement node first on that basis. The three
terms are built in one clearly marked block so that if a BDF export ever shows Femap
reordering them, the fix is one edit. **Verify this before trusting a model:** export the deck
and read the `MPC` card.

**Equation IDs are proved free, not assumed.** BCEqn IDs run 1..N *within a constraint set*, and
`SetID` must be assigned before `NextEmptyID` or `CountSet` — both are set-scoped and meaningless
without it. `PutAll` documents no duplicate-ID error, which almost certainly means it silently
overwrites, so each candidate ID is confirmed empty with a `Get` before use.

**DOF indexing differs between objects.** `BCEqn.dof` is 1-based (1..6). `BCNode.dof` is 0-based
(0..5). An index carried between the two is off by one and silently constrains the wrong
direction.

**The confirm arrows are real erasable annotation,** not created-and-deleted geometry —
Femap's User Graphics (`feGFXArrow`). Their axis directions come from `feCoordTransform` on the
three unit points rather than from the CSys direction-cosine matrix, because the doc does not
say whether the matrix rows are the axes or their transpose, and a transposed triad would point
confidently in the wrong directions. The erase order is not interchangeable: delete the data,
*then* reset the display, *then* regenerate — deleting alone leaves the arrows on screen.

**The constraint set is created lazily,** on the first pair that actually writes, so a
report-only run or a run where every confirm is cancelled leaves no empty set behind.

**The bookkeeping group is the only persistent record.** Femap nodes have no title, so without
`RelDisp <A>-<B>` the mapping from measurement node to the pair it measures exists only in the
Messages window and is gone when that scrolls.

## The equations existing is not the same as the deck containing them

An analysis case selects constraint equations through **its own slot** —
`AnalysisCase.BCSet[1]` — which is *separate* from `BCSet[0]`, the one that selects
constraints. If that slot names a different constraint set from the one the equations went
into, Femap writes **no MPC cards at all**: no warning, no empty section, just a deck that
quietly lacks them. Toggling constraint-equation output in the analysis set does not help,
because the slot, not the toggle, decides which set is written.

So before exporting: **Analysis Set Manager → Boundary Conditions → Constraint Equations →
select the set the tool reported.** The summary prints the set ID and this reminder on every
run that writes anything.

The set dropdown therefore defaults to the **active constraint set**, not to "create new" — a
brand-new set is the choice most likely to produce a deck with no MPCs in it, since a set that
did not exist when the analysis case was built cannot already be named in its slot.

A second, independent filter applies to group exports: `NasBulkGroupID` limits the deck to
*the entities in that group*, so an equation referencing a tracking node outside the exported
group will not be written either. If you export by group, add the `RelDisp` nodes to the group
being exported.

## Known gaps

- **The dependent-term order has not been confirmed on a real export yet.** Until it is, treat
  results as provisional.
- Rotational relative DOFs (R1–R3) are out of scope.
- Node A and node B are picked in two separate prompts, not one. A single multi-pick returns a
  Set ordered by node ID rather than by pick order, which would lose which node was A — and
  A-minus-B is the entire sign convention.
- Rectangular output CSys only. Cylindrical and spherical are gated out, not handled.
- The measurement node sits at the midpoint of A and B and could land on an existing node. If A
  and B are themselves coincident it lands exactly on both — the summary counts and flags those
  pairs. A coincident-node merge would destroy it.
- Group Automatic Add is not suppressed, so if it is on, the measurement nodes also land in the
  active group.
- No `On Error` around the Femap calls, consistent with the rest of the toolset.
- Re-running on the same pair is warned about, not blocked: it produces a second group with
  the same title and a second set of equations measuring the same thing.
- 500 pairs per run.
