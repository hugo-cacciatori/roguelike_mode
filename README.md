# Roguelike Layer-World Mode

A procedural, run-based Pokémon adventure using Generation 3 resources (FireRed/LeafGreen and Ruby/Sapphire/Emerald) on the Pokémon Love2D engine.

## Overview
Inspired by layer-climbing progression, the world is procedurally assembled into **8 distinct progression Layers**, followed by a **Final Wild Environment** and a randomized **Elite Four & Champion Gauntlet**:

- **8 Progression Layers:** Each layer is an interconnected ensemble of Gen 3 maps, featuring wild encounters, scaled trainers, essential facilities, and an exploration-unlocked Layer Gate.
- **Biome Splicing & Composite Chunks:** Slices and combines sections of maps sharing similar biomes (such as Viridian Forest + Petalburg Woods, or Sevii Green Path) into unique composite areas.
- **8 Randomized Gym Leaders:** Exactly 1 per layer, chosen randomly without replacement from all 16 Gen 3 Gym Leaders, scaled to layer level targets, placed outside the entry radius without blocking bottlenecks.
- **Facility Distribution:** Each layer contains at least one Pokémon Center and Poké Mart (with at most ONE survival layer across the run lacking both). The Casino, Daycare/Pension, Department Store/Mall, Fossil Lab, and Trading Club (offering reachable species trades) appear at most once per run.
- **Starters & Field Rights:** Choose any Gen 1, 2, or 3 starter at Level 5. All HM obstacles are bypassed from the start, and Fly is permitted immediately for any Pokémon that can learn it.
- **Immediate National Dex & Lv. 40 Evolutions:** National Pokédex is unlocked from the start. Trade, happiness, and day/night evolutions evolve at Level 40.
- **Endgame Gauntlet:** A final wild environment followed by 4 randomized Elite Four members and a randomized Champion (Blue, Steven, Wallace, Wally, or Lance).
- **Roguelite Lives & Save Safety:** Operates on a 3-life trial pool with Pokémon Center respawns and half-money penalties upon white-out. Entirely isolated in memory with zero mutations to your adventure save files.

## How to Play
1. Open the Start Menu (`Enter` / `Start`).
2. Select **ROGUELIKE**.
3. Choose your starter, conquer the 8 layers, and defeat the Champion!
