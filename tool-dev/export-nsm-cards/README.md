# export-nsm-cards

Extracts the nonstructural-mass cards — `NSM`, `NSM1`, `NSML`, `NSML1`, `NSMADD` — from a full NX Nastran deck and writes them to a standalone `.bdf`.

Companion to [`export-contact-cards`](../export-contact-cards/), which does the same for contact and glue.

## Use case

You export a model group-by-group with *Write BDF by Group* and the decks come out with no nonstructural mass. Run this once, include the resulting file once from the master deck, and the NSM is back.

## Why this is a separate tool

Femap will not write NSM cards for a group-filtered export. That's confirmed from Femap's own Analysis Set Manager, not just from a script: set **Bulk Data Options → Group** and the NSM regions are dropped, even though they're in the group and carry real mass. There's no analysis-set switch for it.

The obvious fix — having the per-group exporter recover them — runs into a worse problem than it solves.

**NSM regions don't respect group boundaries.** A region straddling two groups can't be split between their files: for the total-mass forms (`NSML`/`NSML1`) the value is a total to distribute across the listed elements, so giving that same total to a subset silently changes the mass. The only safe thing a per-group tool can do is skip the region — and a silently missing region is a poor consolation prize.

Taking NSM out of the per-group split removes the problem instead of managing it. One file, every card, nothing skipped.

*Write BDF by Group* still checks whether the selected groups contain NSM regions, and says so, so a deck quietly missing its mass is never the silent outcome:

```
These groups contain NSM regions.
Femap does not write NSM cards for a group export, so these
decks will have none. Run export-nsm-cards to collect them
into one file and include it once from the master deck.
```

## Nothing is interpreted

Cards are copied **verbatim**. Generating `NSM1`/`NSML1` from the region data would mean deciding which card a given `MassType` maps to, what goes in the TYPE field, and how SIDs are assigned — three things reconstructed from the Nastran spec that could be quietly wrong in a deck that still runs. Femap's own output is the specification.

## It builds its own analysis set

`feFileWriteNastran` writes whatever the **active** analysis set says — including `NasBulkGroupID`, which filters the deck to a single group. *Write BDF by Group* leaves exactly such a set behind if it's cancelled part way through, so running this afterwards silently exported one group and then reported, honestly, that it found no NSM.

A whole-model tool must not inherit a filter it didn't set. This creates its own analysis set with `NasBulkGroupID = 0`, uses it, then deletes it and restores the previously active set.

That also makes the empty result meaningful: if it reports no NSM cards, the model genuinely has none.

## How it works

1. Creates a temporary unfiltered analysis set and writes a full NX Nastran deck to a temp file.
2. Prompts for the output `.bdf` name.
3. Copies every `NSM*` card, its continuations, and the comment labelling it.
4. Deletes the temp file and reports.

One prefix test covers the whole family — `NSM`, `NSM1`, `NSML`, `NSML1` and `NSMADD` all start `NSM`, and no other Nastran card does.

Comments are buffered and flushed only in front of an NSM card, so a label lands with the card it belongs to and nothing else comes along. A comment *inside* or trailing an NSM block is written straight out, so it isn't lost the moment a non-NSM card follows.

## Report

```
  Cards written:         9
  Lines written:         23
  Card types:            NSML1  NSMADD
```

A missing `NSMADD` is called out on its own line — it combines the NSM sets, and a deck with `NSML1` and no `NSMADD` is broken in a way a card count alone would hide.

If nothing is found, the report says so and names the two possible reasons rather than writing an empty file silently:

```
  No NSM cards in the deck.
  Either the model has no nonstructural mass, or the active
  analysis set is filtering it out - check Bulk Data Options.
```

## Known gaps

- No `On Error` handler.
- The output is not checked against the model — a card count is not proof the mass is right.
