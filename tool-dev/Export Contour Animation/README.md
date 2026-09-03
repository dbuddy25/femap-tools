# Export Contour Animation

Saves the **currently displayed** contour animation in the active view as an animated GIF, named
from the model title and the output set on screen — no Save dialog, no manual typing.

*(file: `Export Contour Animation.bas`)*

**Status:** Built 2026-09-03, untested. Writes one file to disk; nothing in the model changes.

## Usage

Have a graphics window open with the animation you want, run the tool. That's the whole
interaction — no dialog for the normal case.

## Filename

`<ModelTitle>_<OutputSetTitle>.gif`, saved next to the model file. Both pieces are sanitized —
characters Windows won't allow in a filename become `_`, and trailing spaces/periods are trimmed
(Windows silently drops them, so an output set titled `"Case 1."` would otherwise ask for a file
Windows refuses to create).

**Never overwrites.** If the target name exists, `_2`, `_3`, … is appended until one doesn't.
Re-running after nudging the animation gets a new file, not a silently clobbered old one.

If the model has never been saved, there's no path to derive a folder or title from — the tool
asks for a folder and falls back to `UntitledModel` for the title.

## What this tool cannot verify

The API guide's entire remark on animated export is one line in the format table: Animated GIF
is "only available for animating windows." **There is no documented property or method anywhere
in the guide that reports whether a view is currently playing an animation.** Searched
exhaustively — nothing.

So the tool checks the one thing that *is* documented and real: `View.Deformed`, the display-style
**setting** (`2=Animate`, `3=Animate Multi-Case`) — and asks before proceeding if it isn't one of
those. That's necessary, not sufficient: the setting can be right while playback is paused or
stopped, and there's no way to tell from the API. If the exported GIF comes back as a single
frame, that's what happened, and there's nothing further to check programmatically.

## Which output set

Read from `View.OutputSet` on the **active view** (`feAppGetActiveView` + a fresh `View.Get`), not
from `Info_ActiveID(FT_OUT_CASE)`. The `FT_OUT_CASE` route is undocumented — the guide gives no
statement either way about whether it reflects what's on screen or a stale UI selection.
`Info_ActiveID(FT_VIEW)` already turned out to always return 0 despite looking like the obvious
call — see [[reference_femap_active_view]] — so the same shape of risk isn't worth taking again
when a properly documented, view-scoped property does the same job.

## API notes

- `feFilePictureSave2(useDlg, saveRegion, format, fName)` — `saveRegion=0` (graphics window),
  `format=10` (Animated GIF). Same call `Check View Capture` uses for a static PNG.
- `App.ModelName` is the **full path**, including the `.modfem`/`.mod` extension, or blank if the
  model was never saved — confirmed via the guide's remark on `feAppSetModelByName`. Split by hand
  from the end (`LastIndexOf` helper): WinWrap offers no documented `InStrRev`.
- File-existence check uses `Scripting.FileSystemObject` (`fso.FileExists`), the same COM pattern
  `Check MPC Export` already uses — not an undocumented WinWrap built-in.

## Possible extensions

- Report `View.AnimationFrames` / `View.AnimationDelay` in the run summary, so the GIF's frame
  count and timing are visible without opening Femap's own dialog.
- A folder override for a saved model, instead of always writing beside the `.modfem`.
