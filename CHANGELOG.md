# Changelog

All notable changes to the Roguelike Layer-World Mode mod will be documented in this file.

## [Unreleased] - 0.2.0-dev

### Changed
- Rebuilt as a FireRed-only `api` 3 mod split into `lib/` and `data/` modules. The 0.1.0 run-planning model, which never reached the game, is removed; its boss and starter tables moved to `data/`.

### Added
- Read-only access to the player's FireRed and Emerald imports.
- Merged tileset pairs that survive the engine's tileset, behaviour and encounter-type reloads.
- Generated areas: a functional layout (path, clearings, grass zones, trainer and boss spots) painted with FireRed and Emerald tiles by a backtracking constraint solver that follows tile classes and neighbours learned from both games' maps; FR and EM tiles meet where their edges match.
- Runs are generated from their seed and regenerated identically on Continue; a run starts in a generated forest.
- Generated wild encounters: each area gets a table whose species are learned from both games' wild tables for that kind of environment, whose levels follow the layer's band, and whose forms fit the level (a Lv. 30 member of the Caterpie family is a Butterfree). Fishing keeps the old, good and super rod tiers. The game's own encounter step rolls these tables.
- Headless tests through the engine's real loader, map loading and collision rules.
- Game takeover: while enabled, New Game starts a run on the first composite map, and runs save to their own "Roguelike run" slot; the adventure's slot is never written.
- Crash-safe slot switching: `options.lua` keeps the adventure active, so starting the game without the mod continues the adventure. Without an existing FireRed save, an empty "Adventure" slot is created for that purpose.
- The title screen's Continue panel is refreshed to show the run; saving a session that is not a run is refused.

## [0.1.0] - 2026-10-25

### Added
- Procedural 8-layer progression world with Gen 3 map splicing and scaled map density.
- Level 5 starter draft offering 3 randomized choices across Gen 1, Gen 2, and Gen 3.
- 8 randomized Gen 3 Gym Leaders placed per layer with monotonically scaling level targets (Lv14–Lv60).
- Option B Layer Gates: defeating the layer's Gym Leader plays a narrative cutscene and unlocks a gate to advance.
- Option B Defeat / White-out system: 3-life trial pool, Pokémon Center respawning, and 50% money penalty.
- Special facilities generation rules: at most one survival layer, and single occurrences of Casino, Daycare/Pension, Department Store, Fossil Lab, and Trading Club.
- Endgame gauntlet featuring a final wild route, 4 randomized Elite Four members, and a randomized Champion (Blue, Steven, Wallace, Wally, Lance).
- Universal field move bypass: non-egg party Pokémon can use field obstacles immediately; instant Fly granted.
- Level 40 evolution triggers for trade, happiness, and time-of-day evolutions; immediate National Dex.
- Pure in-memory session architecture with zero adventure save file mutations.
