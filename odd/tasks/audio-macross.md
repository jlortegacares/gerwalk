# Macross sound design

Branch: `feature/fighter-vfx`. Delivery: `single-pr`. Tests:
`./run.sh --headless tests/smoke_test.tscn`.

Objective: give the prototype a voice inspired by the Macross anime — the VF-1
turbine whine, the gunpod, the missile salvo, the anime lock tone and the
transformation servos — without shipping any copyrighted audio.

## Specs

S1. **The game has sound.** Requested verbatim: "quiero que agregues sonidos al
juego inspirados en macross". Every audible event in the game plays a sound: no
weapon fires, missile launches, hull takes damage, ship transforms, boost ignites,
bomb detonates or contact locks in silence.

S2. **The palette is Macross, the assets are ours.** No sampled or ripped Macross
audio is used. Every sound is synthesized by `tools/generate_sfx.gd` into
`audio/sfx/*.wav`, committed with the generator, so the palette is reproducible,
tweakable and license-free. "Inspired by" means the character of the sounds: a
turbine whine for the ship, a hard dry gunpod burst, the airy whoosh of a missile
leaving the rail, a rising two-pip lock tone, servo and hydraulic noise for the
transformation, and a two-tone alarm for an incoming guided shot.

S3. **Weapons speak with one voice per weapon.** Vulcan, plasma and laser each have
their own shot sound, and the missile launch is the loudest of the three. Rapid fire
must not stack into noise: the vulcan is short and dry, and the voice pool caps how
many copies can overlap.

S4. **The lock is audible.** A contact acquiring a reticle plays the rising lock
tone. An enemy missile launch plays the two-tone alarm, because the warning window is
the moment the player has to act.

S5. **The ship is audible.** The transformation plays servos and a clunk, the
afterburner plays ignition, the dash plays a short whoosh, and a hover engine hum
runs continuously with a pitch that follows the ship's speed and stops when the ship
is dead or the game is in the menu.

S6. **Space is respected.** The player's own weapons, the HUD and the menu are
non-positional. World events (explosions, enemy fire, missile launches, the bomb)
are positional 3D players at the event's position, so a distant turret is quieter
than one on the nose.

S7. **Mixing is bounded.** A `SFX` bus under `Master` carries every effect, and a
hard limiter on `Master` keeps a full salvo plus an explosion from clipping. The
voice pool is fixed: a new sound steals the oldest voice instead of allocating a node
per shot.

S8. **Headless stays honest.** The smoke test runs without an audio device. The
`Sfx` autoload must load and play there without errors, and it keeps a per-key play
counter so the test can assert the wiring (which sound an event asked for) instead of
pretending to hear it.

S9. **Enemy explosions are heard.** Requested verbatim: "agrega sonido a las
explosiones de los enemigos". A dying enemy plays the explosion cue, and that cue has
to be audible on a laptop speaker: most of its energy lives above 300 Hz, with at
least 30% above 1 kHz. The ship's death blast uses the same builder and meets the
same floor.

## Tasks

| ID | Spec | Route | Status |
|----|------|-------|--------|
| T1 | S2 | inline | done |
| T2 | S6, S7, S8 | inline | done |
| T3 | S1, S3 | inline | done |
| T4 | S4 | inline | done |
| T5 | S1, S6 | inline | done |
| T6 | S5 | inline | done |
| T7 | S1, S5 | inline | done |
| T8 | S8 | inline | done |
| T9 | all | inline | done |
| T10 | S9 | inline | done |

## Log

L1 (verbatim): "quiero que agregues sonidos al juego inspirados en macross"

L2: The project had no audio at all: no `AudioStreamPlayer`, no asset, no bus, no
autoload. This is a from-scratch audio layer, not a wiring pass.

L3: Chose procedural synthesis over downloaded assets. Two reasons: Macross audio is
copyrighted and must not be shipped, and a generator keeps the palette tunable in
code next to the rest of the tuning constants. `AudioStreamWAV.save_to_wav()` writes
the files, so the generator is plain GDScript with no extra toolchain.

L4: T1 — `tools/generate_sfx.gd` writes 17 keys (`vulcan`, `plasma`, `laser`,
`missile_launch`, `lock_tone`, `missile_warning`, `enemy_fire`, `explosion`,
`player_death`, `hit`, `transform`, `afterburner`, `dash`, `bomb`, `decoy`,
`ui_select`, `engine_loop`) into `audio/sfx/`, plus their `.import` files. The noise
source is a fixed-seed LCG, so a re-run reproduces every WAV byte for byte. The
`engine_loop` partials are integer multiples of 1 Hz and its attack is a sustain
(`attack <= 0.0` means "no ramp"), so the loop point does not click.

L5: T2 — `common/sfx.gd` autoloaded as `Sfx`. It builds the `SFX` bus under `Master`
and a `AudioEffectHardLimiter` on `Master` at runtime (no `.tres`), keeps a 16-voice
flat pool that steals the oldest, creates capped `AudioStreamPlayer3D` nodes for
`play_at`, and owns the single engine loop. `_counts` per key is the test's
observable; `has()` and `engine_active()` were added for the same reason.

L6: T3/T4 — weapon cues. `vulcan` fires once per shot (not per pellet), `plasma`
once per bolt, `laser` once per trigger pull via `_laser_sounding`, `missile_launch`
once per missile with pitch `1.0 + index * 0.04`, `bomb` and `decoy` positional,
`lock_tone` once per acquisition frame (not per contact), and `missile_warning` once
per enemy salvo at the launch (interceptor and launcher).

L7: T5 — world cues. `enemy_fire` on `turret._fire_pattern`, `explosion` on
`Enemy._spawn_explosion`, `player_death` on `Player._spawn_explosion`. The player's
own death blast is deliberately flat, not positional: the camera is on the wreck.

L8: T6/T7 — ship cues. `transform` in `_start_transform`, `dash` in `_start_dash`
and `_start_barrel_roll`, `hit` in `take_damage`, `afterburner` on the rising edge of
`heat` with hysteresis (0.08 in, 0.02 out), `Sfx.engine()` every frame with
`velocity.length() / BOOST_SPEED`, and `engine(false)` in `_die` and `_exit_tree`.
`ui_select` on start, options, back and every livery swatch.

L9: T8 — evidence. `tests/smoke_test.gd` gained `_test_audio` plus assertions in
`_test_main_menu` and `_test_death`. RED observed first: with the six wiring files
stashed, 18 audio assertions failed exactly as expected (palette and autoload still
passed, every `Sfx.played(...)` was 0, and `engine_active()` was false). With the
wiring in place the suite is **394 PASS / 0 FAIL**, up from 369.

L10: T9 — `docs/combat-prototype.md` gained an `## Audio` section (palette, the three
calls, bus and limiter, cue discipline, headless observability), five tuning rows,
three architecture lines and three known gaps (synthesized not recorded, one engine
voice, 24-voice positional cap). The generator command is in `## Checks`.

L11: The stash used for the RED run reverted the wiring, not just the sound calls, and
in that deliberately broken state the suite never finished: `_test_damage_and_iframes`
reported `hp 6` (its `take_damage` was a no-op there) and `_test_death` then looped
waiting for health to drain. The working tree was restored with `git stash pop` and the
green suite was re-run afterwards; it passes. No change to the shipped code came out of
this: the RED evidence is the 18 audio failures, and the hang is an artifact of running
tests against half-reverted files.

L12 (verbatim): "agrega sonido a las explosiones de los enemigos"

L12: The cue was already wired — `Enemy._spawn_explosion` calls
`Sfx.play_at(&"explosion", global_position)` — and a runtime probe with a real audio
device confirmed the 3D voice is created, plays for its full 1.15 s and frees itself.
The defect was spectral, not wiring: `explosion.wav` carried 61% of its energy below
300 Hz and only 18.6% above 1 kHz (`player_death` 66.9% / 14.9%), and a laptop speaker
cannot reproduce that band at any volume. `_explosion` was rebuilt around a bright
crack (~6.5 kHz) over a mid body (~2.3 kHz), with the sub reduced to weight
underneath; it now measures 52.0% / 48.6% above 1 kHz. The generator also seeds its
LCG per sound from the sound's name, so editing one builder no longer rewrites the
effects listed after it (the WAVs were regenerated once with the new seeds). The
suite gained a spectral assertion that reads the committed WAVs from disk — the
imported resource is QOA, so its `data` is not the PCM that ships — and requires at
least 30% above 1 kHz. RED observed first at 18.6% / 14.9%, then GREEN at **396
PASS / 0 FAIL**. One test-isolation fix came out of the same pass: `_test_audio` now
heals the ship before its `take_damage(1)` probe, because a run that reached it on the
last hull point killed the player and left `_test_damage_and_iframes` reporting
`hp 6` with no health event.
