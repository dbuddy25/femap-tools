# Export Contact Cards

Extracts all contact bulk data cards from a full NX Nastran deck export, preserving Femap's native contact representation (property-based, element-based, etc.).

**Last updated:** 2026-02-27

## Usage

1. Ensure an NX Nastran analysis set is configured in the model
2. Run the tool — it writes a full NX Nastran deck to a temp file
3. Choose a save location for the output .bdf file
4. The tool extracts contact cards from the temp deck and writes them to the .bdf
5. A summary of card counts prints to the message pane

## Cards Extracted

| Card | Purpose |
|------|---------|
| **BSURF** | Element-based contact body definition |
| **BSURFS** | Element face-based contact body definition |
| **BCPROP** | Shell property-based contact body definition |
| **BCPROPS** | Solid property-based contact body definition |
| **BGSET** | Glued contact set (pairs two bodies) |
| **BGADD** | Combines multiple BGSETs |
| **BCTSET** | Sliding/friction contact set |
| **BCTADD** | Combines multiple BCTSETs |

## How It Works

Instead of manually building cards from Femap's internal objects, the tool lets Femap write a complete NX Nastran deck (which already translates contact definitions correctly), then parses out only the contact-related cards. This preserves the exact representation Femap uses — BCPROP for shell properties, BCPROPS for solid properties, BSURF for element-based, etc.

## Edge Cases

- **No analysis set configured** — `feFileWriteNastran` may show dialogs or fail; error message shown
- **No contact in model** — warning "No contact cards found", empty output file
- **User cancels file dialog** — exits, temp file cleaned up
- **Large-field format** — handled (`*BSURF` etc. recognized as contact cards)
- **Comment lines** — `$` comment lines immediately preceding a contact card are included for context
