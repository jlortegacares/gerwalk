# Pad panel: the controls table leaves the menu

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** The controls table lives in `ui/menu/pad_panel.gd`
(`class_name PadPanel extends RefCounted`): its rows, its button styling
arguments, the listening state, the remap write and the factory reset.

**S2.** `main_menu.gd` keeps the panel router: the scene changes, the save cards,
the pilot panel, the display toggle, the livery picker, `refresh()` and the input
routing. It creates the panel, hands it the three nodes it draws into
(`%ControlGrid`, `%ControlHint`, `%PadResetButton`), the settings path and the
menu's compacted button style, and it keeps `_input` because that is where the
press has to be read before the GUI gets it.

**S3.** The dependency stays downward and the panel owns no scene graph. `PadPanel`
is a `RefCounted`, like `MissileRadar`: a table plus one piece of state needs no
place in the tree. It never names `MainMenu`; the style arrives as a `Callable`,
the same shape as the effects node's pose and the director's placer.

**S4.** No behaviour change. The rows are the same eleven, the factory pad is still
applied before the first run, a press still swaps and saves immediately, Escape
still cancels without binding, the factory reset still writes, closing the panel
still drops the waiting bind, and the focused row still takes focus back.

**S5.** The suite keeps every line it had. `MainMenu.ROWS`, `MainMenu.IDLE_HINT`,
`MainMenu.PALETTE` and `menu._input(event)` still resolve; the constants are
aliases to the panel's and `_input` forwards to it.

**S6.** The suite is green on the final tree: 775 PASS, 0 FAIL, exit 0.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `ui/menu/pad_panel.gd`, 231 lines: `ROWS`, four constants, `build`, `handle_input`, `cancel` and nine internals |
| T2 | S2, S3 | done | `main_menu.gd` 832 → 676 lines; `_pad`, `_binding_style`, `_input` forwarding, `_close_options` calling `cancel()` |
| T3 | S4 | done | moved verbatim apart from `_control_grid` → `_grid`, `_control_hint` → `_hint`, `_bindings` → `bindings`, and `get_viewport().set_input_as_handled()` moving to the caller that has a viewport |
| T4 | S5 | done | zero test edits; constants aliased in `main_menu.gd` |
| T5 | S6 | done | one clean run: 775 PASS, 0 FAIL, one boot, exit 0; only three timing numbers drift from the baseline |

## Log

**L1.** Request, verbatim: "sigue" — continuing the P1 movements after the player
effects split.

**L2.** The pad panel goes first because it is the only panel with state of its
own: the bindings dictionary, the button table and the action waiting for a press.
The livery panel is mostly a view, and the save panel is mostly `SaveSlots` calls;
both are thinner seams and can follow.

**L3.** A `RefCounted`, not a node. The panel draws into nodes the menu owns and
owns none itself, so it is a table and an editor state, not a scene. Same call as
`MissileRadar` in the arsenal split.

**L4.** `_input` stays on the menu. The suite drives a bind with
`menu._input(press)`, and the reason the handler lives there is a real one: GUI
input runs between `_input` and `_unhandled_input`, so a focused binding button
would swallow its own bind. The panel answers whether it consumed the press and
the menu marks it handled, which keeps the viewport call on the node that has one.

**L5.** The constants are aliased instead of moved outright. The suite reads
`MainMenu.ROWS` and `MainMenu.IDLE_HINT` to describe the panel it is testing, and
the names cost two lines; the same alias pattern the player uses for the wing
sweep.

**L6.** `_compact_style` stays in the menu: the save cards use it too, so the panel
receives it through `_binding_style(slot)` rather than duplicating the padding
maths.

**L7.** The green run was blocked by a pre-existing harness bug, not by this panel:
a stray death reloaded the scene mid-suite and the suite booted twice, so the
second boot's clean tail hid the old run's failures. Fixed separately in
`odd/tasks/suite-respawn-guard.md`; with it, the run is 775 PASS, 0 FAIL, one boot.
