# Gerwalk

Top-down twin-stick shooter (360°) in a real-time 3D scenario, built in Godot.
The player flies over a planet's surface, stays locked to the screen centre, and
fights bullet-hell patterns with a segmented HP bar instead of one-hit death.

- **Engine:** Godot 4.7.2 stable, Forward+ (pinned)
- **Requirements:** [docs/requirements.md](docs/requirements.md)
- **Combat feel prototype:** [docs/combat-prototype.md](docs/combat-prototype.md)

## Run

```sh
./run.sh            # run the game
./run.sh --editor   # open the editor on this project
./run.sh --headless # no window (CI)
```

The script locates the engine on its own (`PATH`, `GODOT_BIN`, then the macOS
app bundle). Override it with `GODOT_BIN=/path/to/godot ./run.sh`.

## Layout

```
common/          event bus, shared VFX
combat/          projectiles
entities/        player, enemy
levels/arena/    main scene
ui/hud/          HP bar and overlays
tests/           headless gameplay smoke test
tools/           input map generator, frame capture
docs/            requirements and prototype notes
```
