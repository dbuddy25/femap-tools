# Remove From Groups

Pick entities once, see every group that currently contains them, and remove them from the groups you choose — in one pass.

## Why

Femap's `Group → <entity> → Remove` operates on the **active group only**. Stripping one node out of a dozen groups means activating and re-picking a dozen times, and there's no way to even *see* which groups hold a given entity without opening each one. This tool inverts the selection: the entity is picked once, and the groups become the thing you select.

The read-only half is useful on its own — tick **Report only** to answer "which groups is this node in?" without touching the model.

## Use case

You deleted or re-meshed part of a model and a stale node/element is still referenced by several groups; or an entity was swept into groups it doesn't belong in by a generous selection rule, and you need it out of some of them but not others.

## How it works

1. Choose an entity type (Node, Element, Point, Curve, Surface, Solid, Volume, Property, Material, CSys).
2. Pick the entities with the standard Femap selector.
3. The tool evaluates every group and reports each one containing part of your selection, with a count (`3 of 8`).
4. Femap's own group-selection dialog opens **pre-loaded with exactly those groups** — deselect any you want to keep rather than hunting for the ones to strip.
5. Confirm, then each chosen group gets a Remove rule and is re-evaluated.

Nothing is written before the confirm dialog.

## The one thing to know: removal is a *rule*, not a deletion

A Femap group is not a stored list of IDs — it's an ordered list of selection **rules** that Femap evaluates to produce the contents. Rules are either explicit ID ranges (`elements 100 to 250`) or generative (`all elements on surface 5`).

So there's nothing to "delete." The tool appends a Remove rule:

```basic
gp.SetAddOpt( entityType, setID, 0 )    ' 0 = Remove, 1 = Add, -1 = Exclude
```

`SetAddOpt` appends to the **end** of the rule list and Femap evaluates in order, so a trailing Remove beats every Add before it. That's what makes this work even when the entity entered the group through a generative rule — the rule still selects it, and the Remove then takes it back out.

**The existing rules are left untouched.** The tool does not edit or narrow a generative rule — it appends after it. A group whose rule is `all elements on surface 5` keeps that rule verbatim and gains a trailing `Remove element 1234`. Correct today, but the generative rule keeps generating: remesh surface 5 and it re-picks up whatever is there now, while the stale Remove still runs last. After a renumber, that ID may belong to a *different* element, which then gets silently stripped. Femap's own UI behaves the same way — there is no API to carve one entity out of a generative rule. The only residue-free alternative applies to groups built purely from explicit ID ranges: walk the rules with `RangeNext`/`RangeDelete` and rebuild the ranges without that ID. Not implemented.

**The consequence:** the Remove rule is permanent and stays last. If you later add that entity back to the group by hand, the next `Group → Operations → Evaluate` will strip it out again. To genuinely undo, open `Group → Operations → Edit Rules` and delete the Remove range — re-adding the entity is not enough. The summary reprints this warning on every run that modifies something.

## Implementation notes

**Two entity-type numbering schemes.** Femap has `FT_` (Entity Types) and `FGR_` (Group List Types) and they disagree:

| | `FT_` | `FGR_` |
|---|---|---|
| Point | 3 | 1 |
| Surface | 5 | 3 |
| Node | 7 | 7 |
| Elem | 8 | 8 |
| Solid | 39 | 21 |

Node and Elem matching is a coincidence — and it's the coincidence that lets this bug survive testing, since code written with `FT_` constants against `Group.List()` works fine on nodes and elements and silently reads the wrong list the moment someone picks surfaces. This tool never calls `Group.List()`; it reads group contents with `Set.AddGroup(entityTYPE, groupID)`, which takes `FT_` types — the same constants `SetAddOpt` takes. One scheme end to end.

**Get before Put.** `gp.Get(id)` loads the existing rule list onto the object, `SetAddOpt` appends to it, `gp.Put(id)` writes the whole list back. Skipping the `Get` would write a group whose only rule is the Remove — an empty group.

**Stale groups.** Each group is evaluated with `forceEval=False` before scanning. That's cheap (it only touches groups Femap already flagged as stale) but without it a rule-based group can report out-of-date contents, and the tool would miss a group or offer one that no longer holds the entity.

**No live cursors across model calls.** Group IDs are harvested into arrays before any `feGroupEvaluate` / `Set.AddGroup` / `Get` / `Put` runs, so no enumerator or Set cursor is ever live across a call that reaches into group data.

**Tight rules.** The intersection is recomputed per group so each Remove rule covers only the entities that group actually holds, rather than littering every rule list with removals for entities that were never there.

## Known gaps

- No `On Error` handler — a Femap-level failure aborts rather than reporting.
- Entities are matched by ID only. If IDs were renumbered between picking and applying (not possible within one run), results would be wrong.
- Groups containing the entity only via **clipping** (plane/box clip rather than a rule) are not distinguished; the Remove rule still applies, which is correct, but the reported count reflects the evaluated contents.
- One entity type per run. Removing nodes *and* elements means two passes.
