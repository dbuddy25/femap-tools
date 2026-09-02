# Check View Capture

Diagnostic. Proves the four API steps a contour-plot export tool would rest on, before any such
tool gets written.

*(file: `Check View Capture.bas`)*

**Status:** Built 2026-09-02, untested. Changes the **view**, not the model — and puts the view
back at the end.

## What it tests

| # | Step | API |
|---|---|---|
| 1 | Restrict a view to one group | `View.Group` + `Put` + `Regenerate` |
| 2 | Fit at the current orientation | `View.FitVisible` |
| 3 | **Read an orientation and write it back** | `ViewOrient.GetRotationAngles` / `SetRotationAngles` |
| 4 | Export the graphics window | `feFilePictureSave2` |

**Step 3 is the one the design rests on.** If orientation round-trips, the workflow can be
*orient by hand → click Record → repeat*, then replay every saved orientation unattended. If it
doesn't, every plot has to be posed by hand at the moment it's captured.

It rotates by a deliberately odd amount (+37, −23, +11) so a value that merely looks plausible
can't be mistaken for a real round trip, and compares on the **wrapped** angular difference —
asking for 190° and reading back −170° is a correct round trip, not a 360° error.

## Why not "orient it now, then click OK"

The API has **no modeless dialog**. `feAppMessageBox` is modal, and the only documented
persistent UI is a registered add-in pane, which needs a compiled application rather than a
`.BAS`. So a dialog cannot sit open while you rotate the model.

Recording orientations sidesteps that completely — and unlike posing by hand, a recorded
orientation is reusable across sessions and shareable with whoever else runs the tool.

## The operating limit worth knowing now

`feFilePictureSave2` captures the **screen**. The guide is explicit: if the graphics window is
partially or fully obscured by another application, the saved file is wrong. So a batch export
cannot run behind a maximised Excel, and that constrains the eventual tool's design rather than
being a footnote.

## API notes

- `feFilePictureSave2(useDlg, saveRegion, format, fName)` — `saveRegion` 0 = graphics window,
  1 = layout, 2 = desktop. `format` 12 = PNG, 4 = JPEG, 1 = bitmap. All four are inputs.
  (`feFilePictureSave`, without the 2, is marked obsolete.)
- `ViewOrient.GetRotationAngles(dX, dY, dZ)` — **all three are out-params**, degrees about the
  Basic Rectangular system, wrapped to −179.9999…180. `GetEyeDirection` returns **six**
  out-params (eye vector + right vector) describing the same orientation a different way; the
  probe prints both, since it isn't obvious which survives a round trip more faithfully.
- **`ViewOrient.Put` must come AFTER `View.Put`** when both objects are touched — the guide says
  so explicitly, and the View put would otherwise overwrite the orientation.
- `FitVisible` differs from `AutoscaleVisible` in accounting for the **current orientation** —
  it is the real "fit what I'm looking at". All the View methods only update the object; the view
  must be `Put` and regenerated before anything changes on screen.
- There is **no** App-level orientation method — no `feViewRotate`, no `feViewIsometric`.
  Standard isometric/dimetric/trimetric angles live in Preferences
  (`Pref_AngleIsometric[0..2]`) and would be fed into `SetRotationAngles`.

## Usage

Open a graphics window, run it, give it a folder and one group. It writes `viewprobe_A.png`
(group isolated and fitted) and `viewprobe_B.png` (the same, rotated), prints the angle round-trip
result, and restores the view.
