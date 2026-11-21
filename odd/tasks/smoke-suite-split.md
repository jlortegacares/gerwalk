# Smoke suite: split the monolith, keep the run identical

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** The run is identical. `tests/smoke_test.tscn` still boots the same world in
the same order and prints the same assertions in the same sequence. The split may
not add, drop, reorder or reword a single check.

**S2.** No assertion is rewritten. Every `_test_` function moves verbatim into the
suite that owns its domain; the 65 functions are byte-identical to the pre-split
file.

**S3.** The shared harness is one class. `tests/smoke_suite.gd` holds the world
references, `_check`, the spawn and scan helpers and the scratch paths; both the
runner and every domain suite extend it.

**S4.** A suite is a node in the tree. It is added as a child of the runner so it
inherits `PROCESS_MODE_ALWAYS` and keeps running while the pause menu has the tree
stopped.

**S5.** The world is shared, not re-booted. Each suite receives the same arena, the
same ship and the same `_failures` array, so `_report` sees every failure and the
suite still drives one mutable run.

**S6.** Nothing that used `add_child` or `get_children()` from the old scene-root
position changes meaning. Projectiles and effects remain parented to
`get_tree().current_scene`; the scans keep looking there.

**S7.** The suite is green on the final tree: 775 PASS, 0 FAIL, exit 0.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1, S2 | done | `/tmp/split_smoke.py` moves blocks by declaration order; verified 65/65 moved, 0 differ, 0 helpers lost |
| T2 | S3, S4, S5 | done | new `tests/smoke_suite.gd` (702 lines) + `_install_suite()` |
| T3 | S1 | done | `tests/smoke_test.gd` 6,115 → 147 lines: `_ready` order + `_report` only |
| T4 | S6 | done | 17 `add_child` and 5 `get_children()` call sites made explicit to `current_scene` |
| T5 | S7 | done | 775 PASS / 0 FAIL / exit 0 |
| T6 | — | done | `docs/architecture.md` §2.4, §5.3, §6 updated; `docs/combat-prototype.md` untouched (paths unchanged) |

## Log

**L1.** Request, verbatim: "sigue" — continuing the architecture plan after P0,
with the orchestrator's recommendation that P2 (split the suite) runs before P1
(split `player.gd`).

**L2.** Route: `direct inline` for the split script and the wiring, because the
mechanic is understood and the whole change is mechanical. No writer trigger held.

**L3.** Method. The suite was never edited by hand: a throwaway script
(`/tmp/split_smoke.py`) parses top-level declarations, keeps every non-`_test_`
block in the harness, distributes the 65 `_test_` blocks by an explicit map, and
rewrites the `_ready` call sites to `_suite._test_x()`. The result was then diffed
against `/tmp/smoke_test.orig.gd` block by block.

**L4.** Trap found: the original block splitter attributed a trailing comment block
to the *next* declaration, because a declaration's slice ended at the next
declaration's comment header. The verifier had to compute block starts first and
slice to the next *start*, not to the next declaration line. Without that, 20 tests
reported as "changed" and were cleanly identical.

**L5.** Trap found: `class_name SmokeSuite` followed by a second `extends Node` in
the generated harness — the preamble carried the old file's `extends`. Parse error
`Could not resolve super class inheritance from "SmokeSuite"`. Fixed by dropping
the duplicate.

**L6.** Trap found: the harness used to *be* the scene root. `add_child(governor)`,
`for child in get_children()` and friends meant the arena scene. As a child node
they mean the harness node, so 22 call sites were made explicit to
`get_tree().current_scene`, which is where gameplay actually parents those nodes.

**L7.** `_died_count` is per-suite now: the base `_ready()` connects the bus itself,
so each suite counts its own run. The one assertion that reads it lives in the
movement suite, which observes its own counter.

**L8.** Deliberately left for later: the hidden world hacks (`_run_kills = -1000`,
`_spawn_timer = 1e9`) are still written from the outside. Turning them into fixture
API (`park_stream()`) needs `EncounterDirector` (P1) to have a name to park.
