# Write BDF by Group

Exports each selected group to its own Nastran bulk-data file, ready to `INCLUDE`.

**Last updated:** 2026-08-18
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

## Header notes

Exporting a group over an existing `.bdf` keeps whatever notes were in its header and writes this run's lines **above** them, so the header reads newest-first, like a log.

The header is nothing but those notes:

```
$ Revised bracket thickness per ECO-4471          <- typed this run
$ Added CBUSH fasteners at the aft splice         <- typed a previous run
$ Initial export for the -3 config                <- typed before that
GRID           1       0  1.2345 ...
```

### The Femap banner is not written

It used to carry Femap's version, the source model and the export date. That turned out not to be worth the space — and dropping it removed the only thing a re-export had to identify.

With no banner, every `$` line in the header is a note. No boundary to find, no marker line, no pattern matching. Every bug this area produced came from trying to tell the two apart; there is now nothing to tell apart.

Files exported by an older build still contain a banner. It's stripped on the next export by comparing against Femap's output for that run — same Femap, same model, so nearly every line matches character-for-character and only the date moves. Marker scaffolding from those builds is dropped by name. After one re-export none of that applies to the file again, and the Messages line reports what it removed:

```
  Notes: 1 new, 2 carried over   [3 note(s) kept, 9 old banner line(s) stripped]
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
