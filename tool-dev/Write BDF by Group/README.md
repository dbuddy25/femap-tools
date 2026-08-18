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

### Femap comments

The **Femap provenance banner** — Femap version, source model, export date — is carried over to the top of the `.bdf`. It sits before `BEGIN BULK`, so the header skip would otherwise discard it, and it is exactly the information an include file should state about its own origin.

**Every** comment line before `BEGIN BULK` is taken. A first attempt kept only the leading contiguous `$` block, assuming the banner sat at the very top — it doesn't, and nothing was captured at all. Femap wraps executive control (`ID` / `SOL` / `CEND`) around the comments, so the only reliable rule is "a comment in the header is header text". If that pulls in a line you don't want, it's a filter on a known string, not a positional guess.

`$` comment lines in the bulk data are **kept unconditionally** — every one, no exceptions.

Femap's labels sit above real bulk data, so there is nothing to gain by deciding which to drop. An intermediate version buffered comments and let each share the fate of the card below it; that could only ever lose text that was wanted. A stray label above a removed `PARAM` is harmless — a missing label is not.

Every export prints a tally of what it removed:

```
Removed: 1 EIGRL, 2 global CORD2C/S, 7 PARAM   (4213 cards kept, 6 header + 812 inline comments kept)
```

That tally exists because the original failure was invisible. If a card type ever starts arriving that shouldn't, the count moves and you can see it — rather than finding out when a deck won't run.

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
