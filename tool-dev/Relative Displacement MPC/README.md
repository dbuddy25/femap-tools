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
   set the equations go in (existing, or a new one created for you), whether to show the
   confirm arrows, and a report-only mode.
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

So the tool gates: **A and B must share an output CSys, and it must be rectangular.** The
measurement node is then created with that same `outCSys`, so all three agree.

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

## Known gaps

- **The dependent-term order has not been confirmed on a real export yet.** Until it is, treat
  results as provisional.
- Rotational relative DOFs (R1–R3) are out of scope.
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
