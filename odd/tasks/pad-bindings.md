# Pad button bindings

Branch: `main`. Delivery: `single-pr`. Tests:
`/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`.

Objective: let the player move a gamepad button to another button and keep that
choice across launches, without a keyboard or mouse binding moving with it.

## Specs

S1. **The pad can be reconfigured.** Requested verbatim: "ahora necesito que
permitas configurar el mando (los distintos botones) al gusto del jugador". The
player opens a controls panel from the boot menu, picks an action, presses the
button they want, and the action reads that button for the rest of the run.

S2. **Nine actions, no more.** Scope answered verbatim: "Solo botones del pad
(Recomendado)". The movable actions are exactly `fire`, `dash`, `transform`,
`bomb`, `missile`, `decoy`, `weapon_prev`, `weapon_next` and `restart`. The
movement and aim sticks, the boost trigger, every keyboard key and every mouse
button stay fixed: they are the shape of the ship's control, not a preference, and
moving them would mean capturing axes and duplicating every action across devices.

S3. **A bind is one press.** Picking an action starts listening; the next gamepad
button pressed becomes that action's button and listening ends. Escape cancels
while listening and closes the panel when not listening. A press is captured
before the focused button sees it, so the button under the cursor cannot swallow
the press meant for the binding.

S4. **One button, one action, always.** Assigning a button that another action
already holds swaps the two: the displaced action inherits the button the edited
action had. No action is ever left with no button, so no control can be lost by
remapping.

S5. **The choice survives a restart, and a broken file does not brick the pad.**
Bindings live in a `[pad]` section of `user://settings.cfg`, next to the display
and livery sections the file already holds. A missing section means factory
bindings; an out-of-range button means that action keeps its factory button; a
file that puts two actions on the same button is not trusted at all and the pad
comes back factory.

S6. **Only pad events are rewritten.** Applying a binding replaces the
`InputEventJoypadButton` events of that action and re-adds every other event it
had, so `fire` keeps its mouse button, `missile` keeps its mouse button and `F`,
`dash` keeps Space and `transform` keeps Q. Factory bindings are the ones
`project.godot` ships.

S7. **The reference matches the bindings.** The pad column of the controls table
in the boot menu and the in-run hint line name the buttons the pad is actually on,
so a remap does not leave the player reading a promise the ship no longer keeps.

S8. **The editor is the reference.** Requested verbatim: "la opción de edición de
control debe estar dentro de la opcion \"options\" del menu y agrega la opcion
quit al menu principal". OPTIONS holds one three-column table -- action, keys or
mouse button, pad button -- so there is no separate controls screen to drift from
it. Every pad button is focusable, focus moves with the d-pad, and the listening
state is announced in words and in the warning colour rather than only by an
outline. The panel measures no taller than the viewport at the 1280x720 design
size.

S9. **QUIT leaves the build.** The main menu ends with QUIT, after a spacer that
separates it from the destinations, and it closes the tree rather than opening
anything.

## Tasks

| ID | Spec | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S2, S4, S5, S6 | inline | done | `common/pad_bindings.gd` + unit checks in `tests/smoke_test.gd` |
| T2 | S1, S3, S8 | inline | done | `ui/menu/main_menu.tscn` `%ControlGrid`, `%PadResetButton` |
| T3 | S1, S3, S4, S5, S7 | inline | done | `ui/menu/main_menu.gd` listening flow, `_unhandled_input` Escape |
| T4 | S7 | inline | done | `ui/hud/hud.gd` hint line built from `PadBindings` |
| T5 | S1–S8 | inline | done | smoke suite: 719 PASS / 0 FAIL |
| T6 | — | inline | done | `docs/combat-prototype.md` controls section |
| T7 | S8, S9 | inline | done | `%QuitButton`; editor moved into OPTIONS, separate `%Controls` panel deleted |

## Log

L1. User request, verbatim: "ahora necesito que permitas configurar el mando
(los distintos botones) al gusto del jugador".

L2. Scope answer, verbatim: "Solo botones del pad (Recomendado)".

L3. Default pad map read from `project.godot`: `fire`=10 (RB), `dash`=9 (LB),
`transform`=4 (Back), `restart`=6 (Start), `bomb`=3 (Y), `decoy`=5 (Guide),
`missile`=2 (X), `weapon_next`=14 (D-pad right), `weapon_prev`=13 (D-pad left).

L4. Conflict policy chosen: swap. The alternative — dropping the displaced action
to no button — can leave the player without a way to fire or transform, which is
a worse outcome than an unexpected exchange they can immediately re-edit.

L5. Godot 4.7.2 reports `JOY_BUTTON_MAX = 128`, so the range check is
`0 <= button < 128`; the sixteen named buttons the build uses are 0–14.

L6. `InputMap.action_erase_events` wipes keyboard and mouse events too, so
`PadBindings.apply` collects the non-pad events first and re-adds them before the
new pad button.

L7. Labels follow the pad's face layout, not the printed symbols: Godot names the
bottom face button A, the right one B, the left one X and the top one Y, which is
the same physical arrangement a Switch pad calls B/A/Y/X. The panel prints
Godot's names so the mapping cannot drift from what the engine reads.

L8. Escape is read as a key, not through `ui_cancel`. Godot's `ui_cancel` also
holds the pad's B button, so listening on the action would make B unbindable.
The listening state lives in `_input` because GUI input runs before
`_unhandled_input`, and a focused binding row would otherwise eat its own press.

L9. The OPTIONS legend and the in-run hint line are rebuilt from the bindings
(`_refresh_legend`, `Hud._refresh_controls_hint`). While wiring them, the shipped
legend turned out to name the wrong buttons for decoy (right bumper, actually
Guide), dash (left stick click, actually LB) and transform (left bumper, actually
Back); the dynamic rebuild fixed those as a side effect.

L10. The smoke suite ends `_test_pad_bindings` on the factory pad, because every
later test drives the ship through `InputMap`. A remap left applied would make the
rest of the suite test a pad nobody ships.

L11. `ERROR: 1 resources still in use at exit` appears intermittently in the
headless run. Checked against a worktree at `210f77f`: it reproduces there 2 out of
3 runs, so it predates this change.

L12. The panel was rendered before being called done (`/tmp/gerwalk_controls.png`
and `/tmp/gerwalk_controls_listen.png`, 1600x1000 through a scratch settings file).
The first shot showed the listening row white: a focused `Button` draws its label
with `font_focus_color`, not `font_color`, so `_set_binding_color` overrides both.

L13. The editor moved inside OPTIONS and the stand-alone `%Controls` panel is gone
(S8). The panel already measured 934x726 at the 1280x720 design viewport, so the
editor could not add rows of full-height menu buttons: the table reuses the
existing legend rows, the third cell carries the pad button, and `_compact_style`
squeezes the shared button style from 12 px to 4 px of vertical padding. The two
weapon halves share one row with a pair of narrower buttons. The right column
settled at 495 px, which widened the panel to 965, and the vertical margins went
from 32 to 28 so the panel finally fits the 720 px window (718 px) instead of
being clipped top and bottom.

L14. `_refresh_legend` is gone with the legend: the pad column of the table is the
reference now, and the keyboard half of each row is static text because those
inputs cannot be remapped. The row table lives in `MainMenu.ROWS` and a single
action row takes its name from `PadBindings.action_label`, so the table and the
listening hint cannot call the same control two different things.

L15. Closing OPTIONS now cancels a listening row (`_close_options` clears
`_listening`); without that, a listener that outlived the panel would eat the next
pad press in the main menu. The smoke suite covers it.

L16. Rendered and measured: `/tmp/gerwalk_main_720.png`,
`/tmp/gerwalk_options_720.png`, `/tmp/gerwalk_options_listen.png`, all 1280x720.
Measured `min = size = (965, 718)` for the OPTIONS panel and `(320, 584)` for the
main menu column, so both fit the window.
