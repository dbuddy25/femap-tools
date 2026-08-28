# Write BDF by Group

Exports each selected group to its own Nastran bulk-data file, ready to `INCLUDE`.

**Last updated:** 2026-08-28
**Status:** In use for ~2 years. `FixFile` rewritten 2026-08-18 to fix a silently dropped GRID card — **this change is untested**, see below.

## How it works

1. Builds a throwaway **Modes** analysis set (`Solver = 36` NX Nastran) purely to minimise what gets written
2. Points `NasBulkGroupID` at each selected group in turn and calls `feFileWriteNastran(8, ...)`
3. Text-strips the executive/case control from the result so the file can be `INCLUDE`d
4. Deletes the temp file, then deletes the dummy analysis set

Step 3 exists because `sao.SkipStandard = True` would do it natively but **drops connections on NX Nastran** — noted in the script's own comment.

## The 2026-08-18 fix

**Symptom:** a GRID card was missing from an export. No error, valid-looking file.

**Cause:** `FixFile` stripped the header by *counting lines* — `For j=1 To 24` (with a comment above it saying 23), then a second loop skipping 5–10 more for EIGRL/CORD2C/CORD2S. Neither count was derived from the file. When the header length shifted, the overrun ran one line into the bulk data and swallowed a card.

**Fix:** nothing is counted any more.

- The header ends at `BEGIN BULK`, which is definitional and cannot drift
- The dummy-analysis cards are removed **by card name**, with their continuation lines
- `CORD2C`/`CORD2S` are dropped **only when CID is 1 or 2** (Femap's global cylindrical/spherical). The old positional skip would take whatever sat in those line slots — including a user coordinate system
- `FixFile` returns a status; on failure the temp file is **kept** and an error is printed, instead of deleting the only evidence

### Cards removed

| Card | Rule |
|---|---|
| `EIGRL` | Always — from the dummy Modes analysis set |
| `PARAM` | Always — solution parameters belong in the master deck, not an `INCLUDE` |
| `CORD2C` / `CORD2S` | Only when CID is 1 or 2 (Femap's globals). User systems survive. |
| `ENDDATA` | Replaced with `$` |

### Custom header comments

The options dialog has three optional free-text lines. Whatever you type lands at the very top of every exported `.bdf`, above Femap's own banner — analyst, purpose, revision, job number, whatever the job needs.

- A `$` is added automatically if you don't type one, so a stray line can never become a bad card
- A `$ Exported from group: <title>` line is always appended, so each file names its own source group
- The lines are re-evaluated per group, so the group name is right in every file

Three single-line boxes rather than one multiline box: every `TextBox` in this toolset is single-line, and this is not the script to try unproven dialog syntax on.

### Comment lines

`$` comment lines in the bulk data are **kept unconditionally** — every one, no exceptions.

Femap's labels sit above real bulk data, so there is nothing to gain by deciding which to drop. An intermediate version buffered comments and let each share the fate of the card below it; that could only ever lose text that was wanted. A stray label above a removed `PARAM` is harmless — a missing label is not.

Femap's provenance banner is **not** carried into the export. See [Header notes](#header-notes).

Every export prints a tally of what it removed:

```
Removed: 1 EIGRL, 2 global CORD2C/S, 7 PARAM   (4213 cards kept, 812 inline comments kept)
```

That tally exists because the original failure was invisible. If a card type ever starts arriving that shouldn't, the count moves and you can see it — rather than finding out when a deck won't run.


## Output folder

A checkbox on the options dialog writes the exported files into a subfolder of the model's folder. It is **off by default** — the export lands beside the model, as it always has. Tick it and the box is already filled in with **`Model`**, so the common case is one click; a group export drops one file per group and buries the model file otherwise. The folder is created if it doesn't exist, and the run aborts with a message rather than writing somewhere unexpected if it can't be. A value containing a drive letter (`D:\shared\decks`) is treated as a full path and used as-is, so the same box also handles sending the export somewhere else entirely.


## Nonstructural mass: NSM lives on a Region, not on elements

If an export comes back with an NSM section comment and no card under it, the Region is almost certainly not in the group.

Femap's group-filtered write (`NasBulkGroupID`) emits only entities that are **in the group**. A nonstructural-mass region is a *Region* entity — not an element and not a property — so a group holding all the right elements but not the region gets the comment and no card. Nothing is broken; the region simply wasn't selected.

The tool prints the raw region fields for each group, plus the NSM card counts:

```
  Regions in group 'Aft Splice Bracket': 8
    ID 3  type=0  MassType=1  MassNSM=2.500000E-04  count=112  Skin NSM
  NSM cards in Femap's output: 0, kept: 0
```

These are raw field values, deliberately **not** a verdict. An earlier version counted regions whose `MassNSM` was nonzero and called those NSM regions — but `MassNSM` is only meaningful on an NSM-type region, and read off a contact or glue region it can hold whatever was left in the slot. It reported 8 of 8 on a model whose NSM never reached the deck. The documented `type` values stop at `3=Rotor` with no NSM entry, so there is no reliable field to test; printing what is there and reading it is the honest option.

| Reading | Meaning |
|---|---|
| `NSM cards in Femap's output: 0` | Femap never wrote them for this group — nothing is being filtered out downstream. Check the `with nonstructural mass` count on the line above. |
| `N seen, N kept` | They are in the `.bdf`. The problem is elsewhere. |
| `N seen, 0 kept` | This tool dropped them — a bug here. |

Note that exporting the **whole analysis** and seeing NSM cards does not settle this: that export isn't group-filtered, so it only proves the model has NSM and Femap can write it. The numbers above are from the group-filtered write, which is the one that matters.

**Fix:** add the Region to the group — `Group → Set → <group>`, then `Group → Region`.

### Two API traps worth recording

**`FT_CONTACT` (58) is a Femap *Region*; `FT_CONNECTION` (71) is the *Connector* (contact pair).** The names read backwards from what you would guess, and the wrong one silently counts zero forever.

**The region `type` enumeration in the API guide is incomplete** — it stops at 3 despite NSM regions existing on the same object.

### Recovering the cards Femap won't write

Confirmed from Femap's own Analysis Set Manager, not just this tool: set **Bulk Data Options → Group** and the NSM regions are dropped, even though they're in the group and carry real mass. There's no analysis-set switch for it.

So the tool takes the cards from an export Femap *does* get right — one unfiltered whole-model write — and copies the ones belonging to each group across **verbatim**.

Verbatim is the point. Generating `NSM1`/`NSML1` from the region data would mean deciding which card a given `MassType` maps to, what goes in the TYPE field, and how SIDs are assigned — three things reconstructed from the Nastran spec that could be quietly wrong in a deck that still runs. Femap's own output is the specification; it's copied, not interpreted.

**Which cards belong to a group.** A card is copied only if *every* element it references is in the group, decided from the card's own ID list — so no mapping from card back to region is needed. `THRU` is expanded; a card using `BY` is skipped and reported rather than copied on an assumption about the stride.

**Partial containment is skipped, not trimmed.** For the total-mass forms (`NSML`/`NSML1`) the value is a total to distribute across the listed elements, so handing the same total to a subset silently changes the mass. A missing card is visible; a wrong mass is not.

**`NSMADD`** references SIDs rather than elements, so it's copied only when every SID it names was itself copied.

**The whole-model deck is read once, not once per group.** The first version re-read it inside the group loop — that file is the entire model, so a twenty-group export made twenty full passes over the largest file in the job and every group took visibly longer than it should have. The NSM card blocks are cached in memory before the loop starts; each group only re-runs the containment test against that cache.

**It is off by default.** The extra whole-model export is slow on a large model, and most exports don't need NSM. Tick **Recover NSM cards** when you do.

Leaving it off never fails silently: the model is still checked for NSM regions — cheap, no export — and if a selected group has one, the run says so:

```
NSM regions are in these groups, but NSM recovery is off.
Femap will not write their cards - the decks will have no NSM.
Tick 'Recover NSM cards' if you need them.
```

**Cost and guards.** With it on, the whole-model export happens once per run, and only when a selected group actually contains an NSM region — a model without NSM pays nothing. The recovered cards are written only if Femap wrote none itself, so if a future Femap starts emitting them for group exports this stays out of the way instead of duplicating. Every card added is reported, and the block is labelled in the `.bdf`:

```
$ NSM cards below were copied from a whole-model export.
$ Femap does not write them for a group-filtered export.
```

## Does the group filter drop contact too?

Unknown as of 2026-08-27 — untested. But contact regions are Regions, exactly like NSM regions, so there is every reason to expect Femap's group filter treats them the same way.

Rather than guess, every export now counts the contact cards it wrote. It costs nothing: the card loop already sees every line.

```
  Contact cards written: 14   BSURF  BGSET
  Contact cards written: none
```

`none` on a model that definitely has contact is the answer — and it arrives during an ordinary export rather than being discovered in a deck that solves without its glue.

The card list matches [`export-contact-cards`](../export-contact-cards/): `BSURF`, `BSURFS`, `BCPROP`, `BCPROPS`, `BGSET`, `BGADD`, `BCTSET`, `BCTADD`, `BGPARM`.

If it turns out they are dropped, the NSM recovery mechanism generalizes — but not for free. `BSURF`/`BSURFS` list elements and would use the containment test that already exists; `BCPROP`/`BCPROPS` reference properties and need a new one; `BGSET`/`BCTSET`/`BGADD` reference region SIDs, the same shape as `NSMADD`.

## Constraint equations (MPC)

Fixed 2026-08-28. Before that this tool **could not export a constraint equation at all**, and
said nothing about it.

The export does not run through your analysis set. It runs through the throwaway
`Dummy Set for Group Export` that step 1 builds, activates, and deletes again at the end — so
selecting constraint equations in the Analysis Set Manager has no effect on what this tool
writes. The dummy never set `BCSet[1]`, the slot that names the constraint set holding the
equations (separate from `BCSet[0]`, which names constraints), and an unset slot means Femap
writes no `MPC` cards: no warning, no empty section, nothing.

The dummy set now selects the **active constraint set** in `BCSet[1]`, and the Messages window
says which one. `BCSet[0]` is deliberately left alone — pulling constraints into a per-group
INCLUDE would duplicate SPCs the master deck already carries.

**The group filter still applies.** `NasBulkGroupID` limits the deck to the entities in that
group, and that governs equations exactly as it governs elements: an equation is written only
if the nodes it references are in the group being exported. Instrumentation that lives outside
your part groups — a relative-displacement tracking node, for example — will still be dropped
unless you add those nodes to the group.

## Header notes

Exporting a group over an existing `.bdf` keeps whatever notes were in its header and writes this run's lines **above** them, so the header reads newest-first, like a log.

The header is nothing but those notes:

```
$ Revised bracket thickness per ECO-4471          <- typed this run
$ Added CBUSH fasteners at the aft splice         <- typed a previous run
$ Initial export for the -3 config                <- typed before that
GRID           1       0  1.2345 ...
```

### The Femap banner sits AFTER `BEGIN BULK`

Not before it, which is where it looks like it should be. That one fact caused a long run of wrong fixes, so it's worth stating plainly:

- `hdr()` captures comments *before* `BEGIN BULK`, so it came back **empty**. There was never anything to match a banner against.
- The banner was therefore copied as ordinary bulk-data comment text, landing at the top of the `.bdf` right under the analyst's notes — exactly where a carried-over note sits, which is why it read as a carry-over bug for so long.
- On the next export those lines are in the leading `$` run, so they were read back as *notes* and carried forward while Femap supplied a fresh copy. That was the stacking.

It's now dropped **structurally, not by matching its text**. The block opens and closes with a rule line — `$` followed by nothing but asterisks — so the rule is: the first such block after `BEGIN BULK`, before any real card has been seen, is the banner. Restricting it to before the first card leaves an asterisk rule you write further down the deck untouched.

Files that already contain a copied-in banner get it stripped the same way on the next export, since a rule-fenced block in the leading `$` run is recognised there too.

### The Femap banner is not written

It used to carry Femap's version, the source model and the export date. That turned out not to be worth the space — and dropping it removed the only thing a re-export had to identify.

### The notes block needs an explicit end (fixed 2026-08-28)

"Every `$` line above the bulk data is a note" was still not enough, and it produced one last version of the same bug. The exported `.bdf` is an **INCLUDE**: there is no `BEGIN BULK` in it and `ENDDATA` is commented out. So the notes run *straight* into the bulk data with nothing between them, and Femap's first entity label — `$ Femap Property 1 : ...` — sat directly beneath the last note. Reading the leading `$` run back therefore swallowed that label as a note and carried it forward on every re-export.

Two changes, belt and braces:

- The notes block is closed by a written delimiter, `$=== end of notes - bulk data below ===`. A note is anything above it. That is the whole rule, and unlike the banner markers that came before, it delimits something the tool itself writes rather than trying to recognise something Femap wrote.
- A comment beginning `$ Femap ` is **never** carried over. Femap labels every entity it writes, so those are bulk-data text by definition, never an analyst note. This also cleans up files exported before the delimiter existed, which already have one baked into their header.

Files exported by an older build still contain a banner. It's stripped on the next export by comparing against Femap's output for that run — same Femap, same model, so nearly every line matches character-for-character and only the date moves. Marker scaffolding from those builds is dropped by name. After one re-export none of that applies to the file again, and the Messages line reports what it removed:

```
  Notes: 1 new, 2 carried over   [3 note(s) kept, 9 old banner line(s) stripped, 1 Femap comment(s) not carried]
```

An unmatched line is **kept**. Losing a note is unrecoverable; a stray line shows up in the Messages echo and can be deleted.

### Duplicate notes

Nothing de-duplicates. Re-running an export with the same text still in the dialog boxes stacks a second identical line. Clear the boxes on a re-export unless you want a new entry.


### The notes are listed in the Messages window every run

The file is where the notes *live*; the Messages window is where you **read** them. Every export echoes the full set, newest first, with this run's additions marked `+`:

```
  Notes in C:\work\Group_Aft Splice Bracket.bdf:
    + Revised bracket thickness per ECO-4471
      Added CBUSH fasteners at the aft splice
      Initial export for the -3 config
  Notes: 1 new, 2 carried over   [3 note(s) kept]
```

Not behind a debug flag, because carrying notes across an overwrite is exactly the kind of thing that fails silently and only gets noticed once the notes are already gone. Each run states what it did:

| Reading | Meaning |
|---|---|
| `0 carried over` on a re-export | Nothing was carried forward — the previous file's header was empty or unreadable |
| `old banner line(s) stripped` | First re-export of a file written before the banner was dropped. Expected once, then never again |

## Verifying against a real file

The strip logic was translated from the original's line counts without sight of a real output file. `PARAM` was found this way — the old fixed skip removed the PARAMs as a side effect, and the first name-filter version passed them straight through.

**To check for anything else:** comment out `DeleteTempFile`, run on a small group, and diff the temp file against the `.bdf`. Everything in the difference should be `EIGRL`, `PARAM`, the two global `CORD2i`, or header.

## Known gaps (not yet fixed)

| # | Issue | Consequence |
|---|---|---|
| 1 | Nothing verifies the export round-trips | Exactly the failure above — a valid-looking file with an entity missing. Fix: count `GRID`/`GRID*` written vs `gr.List(7)`. |
| 2 | Group titles go into filenames unsanitized | `\ / : * ? " < > \|` are legal in Femap titles and break or misdirect the write |
| 3 | Name collisions overwrite silently | "Yes" mode maps `wing.bdf` and `wing.dat` both to `wing`; Femap also allows duplicate group titles |
| 4 | `feFileWriteNastran` return code ignored | A failed write leaves `FixFile` opening a nonexistent file → unhandled error, batch dies |
| 5 | No `On Error`; `Kill` can throw | A locked temp file aborts the loop, and the dummy analysis set delete sits *after* the loop, so it leaks into the model |
