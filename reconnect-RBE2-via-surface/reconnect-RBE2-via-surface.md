# Reconnect RBE2 via Surface

Reconnects an RBE2 element to new mesh nodes after a surface has been remeshed. Replaces the old dependent nodes with nodes on user-selected surfaces, preserving the independent node and DOF settings.

**Last updated:** 2026-02-23

## Usage

- Run in Femap's API Programming window
- Select a single RBE2 element to reconnect
- Select one or more surfaces whose mesh nodes should become the new dependent nodes
- The tool updates the RBE2 and deletes any orphaned old nodes

## What It Does

- Reads the existing RBE2's independent node, dependent nodes, and DOF pattern
- Collects all nodes on the selected surfaces (excluding the independent node)
- Replaces the dependent node list with the new surface nodes, preserving the original DOF flags
- Checks each old dependent node — if no elements reference it anymore, deletes it

## Notes

- Only works on RBE2 elements (type `FET_L_RIGID`, topology `FTO_RIGIDLIST`)
- The DOF pattern from the first original dependent node is applied to all new nodes
- The independent node and its releases are preserved unchanged
