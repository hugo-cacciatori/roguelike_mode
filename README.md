# Roguelike Layer-World Mode

A run-based Pokémon adventure for the Pokémon Love2D engine. Each run climbs
layers built from real Kanto and Hoenn maps that are cut into chunks and
spliced together into new composite maps.

> **Status: in development (`0.2.0-dev`).** `0.1.0` only planned a run and did
> not change the game. The current build loads its first composite map
> (Viridian Forest spliced onto Petalburg Woods) and starts runs from New Game,
> but has no starter draft, encounters or exits yet.

## Your adventure is safe
While the mod is enabled, the game *is* the roguelike: New Game starts a run,
and runs save to their own **"Roguelike run"** save slot. Your FireRed
adventure's slot is never written. Disable the mod and Continue resumes your
adventure, even if the game closed unexpectedly while the mod was enabled.

## Requirements
- Engine `0.3.96`, playing **Pokémon FireRed** (the mod runs in FireRed only).
- FireRed imported in the launcher. Emerald must also be imported for Hoenn
  chunks: the mod reads both imports from your own save directory and ships no
  game data.

## How it works
- `lib/sources.lua` reads your imports (read-only).
- `lib/catalog.lua` decodes source layouts, behaviours and encounter types.
- `lib/atlas.lua` merges the tilesets of several source maps into one.
- `lib/splice.lua` cuts rectangles from source maps into a composite map.
- `lib/run.lua` turns New Game into a run that starts on the first composite.
- `lib/saves.lua` keeps runs in their own save slot.
- `data/chunks.lua` lists the composite maps and the chunks they are made of.

## Development
Tests run headlessly against the engine checkout and your imports, which they
read without ever writing:

```sh
python -I tools/test.py --engine path/to/gen1recomp-0.3.96
```

Composite renders are written to `tests/out/` for review and are not committed.
