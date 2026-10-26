# Roguelike Layer-World Mode

A run-based Pokémon adventure for the Pokémon Love2D engine. Every area of a
run is **generated**: no map from either game is used, whole or in pieces.
Each area is laid out for play first (a path, grass, spots for trainers and the
layer boss), then painted with tiles from FireRed and Emerald, using what the
two games' own maps show about which tiles belong together. Buildings are the
one thing placed whole: each is a real building's design, learned from the
games' towns, set into a generated town.

> **Status: in development (`0.2.0-dev`).** New Game starts a run in a
> generated town whose buildings (Pokémon Center, Mart, lab, houses) lead into
> generated interiors, with a generated forest and its wild encounters past the
> town's exit. Starter draft, NPCs, trainers, caves and sea routes are not in
> yet.

## Your adventure is safe
While the mod is enabled, the game *is* the roguelike: New Game starts a run,
and runs save to their own **"Roguelike run"** save slot. Your FireRed
adventure's slot is never written. Disable the mod and Continue resumes your
adventure, even if the game closed unexpectedly while the mod was enabled.

## Requirements
- Engine `0.3.96`, playing **Pokémon FireRed** (the mod runs in FireRed only).
- FireRed imported in the launcher. With Emerald imported too, generated maps
  mix tiles from both games. The mod reads your imports from your own save
  directory and ships no game data.

## How it works
- `lib/sources.lua` reads your imports (read-only); `lib/catalog.lua` decodes
  their layouts, tile behaviours and encounter types.
- `lib/corpus.lua` classifies every source map (forest, cave, sea, route, town,
  building interiors) and learns, per tileset, what each tile is (wall, ground,
  grass, water, ledge, door) and which tiles sit next to which.
- `lib/layout.lua` plans an area: entry and exit, a winding path, clearings,
  grass zones, trainer spots and the boss spot; or a town with room for its
  buildings; or a room with an exit mat.
- `lib/buildings.lua` learns buildings from the doors in both games' towns:
  their shape and what they are (Pokémon Center, Mart, lab, house).
- `lib/paint.lua` paints the plan with a constraint solver that only places
  tiles of the right kind next to tiles they were seen with; `lib/generate.lua`
  lets FireRed and Emerald tiles meet where their edges match, and checks the
  path, boss and trainer spots stay reachable.
- `lib/wild.lua` generates each area's wild encounters: species that live in
  that kind of place in either game, at the layer's levels, in the evolution
  stage that fits the level.
- `lib/atlas.lua` merges the chosen tilesets into one; `lib/world.lua` builds a
  run's layer from its seed (town, interiors, forest, joined by doors and a map
  connection), so a save stores only the seed.
- `lib/run.lua` turns New Game into a run; `lib/saves.lua` keeps runs in their
  own save slot.

## Development
Tests run headlessly against the engine checkout and your imports, which they
read without ever writing:

```sh
python -I tools/test.py --engine path/to/gen1recomp-0.3.96
```

Renders of generated areas are written to `tests/out/` for review and are not
committed.
