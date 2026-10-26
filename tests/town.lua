-- Towns, interiors, door warps and the town -> forest connection, through
-- the engine's own map loading, warp tables and walk rules.
local H = dofile(MOD_ROOT .. "/tests/harness.lua")
local check = H.check

local game = H.bootFireRed()
local Sdk = require("tests.modkit.sdk")
local Runtime = require("src.mods.Runtime")
local NativeTileset = require("src.core.game3.tileset_native")
local Collision = require("src.core.game3.collision")
local Map = require("src.core.game3.map")

local run = Sdk.loadMods({ "mods/roguelike_mode" },
  { fs = Sdk.memfs(MOD_FILES), generation = 3, data = game.data })
check(#run.errors == 0, "load errors: " .. table.concat(run.errors, "\n"))
local exports = run.loader.exports.roguelike_mode
local R = exports.R
Runtime.emit("game.ready", { game = game })

local DIRS = { "up", "down", "left", "right" }
local STEP = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
-- Reachable cells under the engine's walk and ledge rules (map must be loaded).
local function reachable(def, x, y)
  local seen, queue, head = { [y * def.width + x] = true }, { { x, y } }, 1
  while head <= #queue do
    local cx, cy = queue[head][1], queue[head][2]
    head = head + 1
    for _, dir in ipairs(DIRS) do
      local tx, ty = Collision.ledgeLanding(game, cx, cy, dir)
      if not tx then
        tx, ty = cx + STEP[dir][1], cy + STEP[dir][2]
        if not (Collision.inBounds(tx, ty) and Collision.isWalkable(tx, ty)
            and not Collision.directionallyImpassable(cx, cy, tx, ty, dir)) then
          tx = nil
        end
      end
      if tx and not seen[ty * def.width + tx] then
        seen[ty * def.width + tx] = true
        queue[#queue + 1] = { tx, ty }
      end
    end
  end
  return seen
end
local function at(seen, def, p) return seen[p.y * def.width + p.x] end

local baseIds = {}
for _, v in ipairs(R.corpus.VERSIONS) do
  for _, m in ipairs(R.corpus.maps(v)) do baseIds[m.id] = true end
end

local animated, stepDoors = 0, 0
for _, seed in ipairs({ 5, 77 }) do
  local areas, layer = R.world.build({ version = 2, seed = seed, layer = 1 }, game)
  local town, forest = layer.town, layer.forest
  local label = "seed " .. seed
  for _, def in ipairs(areas) do
    check(def.id:sub(1, 6) == "FR_RL_" and not baseIds[def.id] and game.data.maps[def.id] == def,
      label .. ": " .. def.id .. " is a registered generated area")
  end
  local kinds = {}
  for _, b in ipairs(town.roguelike.layout.buildings) do kinds[b.kind] = true end
  check(kinds.center and kinds.mart, label .. ": town has a Pokémon Center and a Mart")
  check(#layer.interiors == #town.roguelike.layout.buildings, label .. ": every building has an interior")

  -- 1. Town: loads, doors are active warps to their interiors, all reachable.
  check(Map.load(nil, game, town.id), label .. ": town loads")
  check(Collision._mapDef == town, label .. ": town collision bound")
  local tl = town.roguelike.layout
  local seen = reachable(town, tl.start.x, tl.start.y)
  check(at(seen, town, tl.exit), label .. ": town exit reachable from the start")
  for i, b in ipairs(tl.buildings) do
    local where = ("%s building %d (%s)"):format(label, i, b.kind)
    local w = Collision.warpAt(b.door.x, b.door.y)
    check(w ~= nil, where .. ": door is an active warp")
    local dest, dx, dy = Collision.resolveWarpDestination(game, w)
    local inside = layer.interiors[i]
    check(dest == inside.id, where .. ": door leads to its interior")
    local exit = inside.roguelike.layout.exit
    check(dx == exit.x and dy == exit.y, where .. ": arrival is the interior's exit mat")
    check(at(seen, town, { x = b.door.x, y = b.door.y + 1 }), where .. ": door reachable from the start")
    if Collision.isDoorWarp(game, b.door.x, b.door.y) then
      animated = animated + 1
    elseif Collision.isStepWarpBehavior(Collision.behavior(b.door.x, b.door.y)) then
      stepDoors = stepDoors + 1
    else
      check(false, where .. ": door is neither an animated door nor a step warp")
    end
  end
  write_png(("town_%d.png"):format(seed), H.render(town.midLayout, NativeTileset.get(town.pair)))

  -- 2. Interiors: exit mats lead back to their own door; the spot is reachable.
  for i, inside in ipairs(layer.interiors) do
    local where = ("%s interior %d (%s)"):format(label, i, inside.roguelike.kind)
    check(Map.load(nil, game, inside.id), where .. ": loads")
    local il = inside.roguelike.layout
    local w = Collision.warpAt(il.exit.x, il.exit.y)
    check(w ~= nil, where .. ": exit mat is an active warp")
    local dest, dx, dy = Collision.resolveWarpDestination(game, w)
    local door = tl.buildings[i].door
    check(dest == town.id and dx == door.x and dy == door.y, where .. ": exit returns to its door")
    local inner = reachable(inside, il.exit.x, il.exit.y - 1)
    check(at(inner, inside, il.spot), where .. ": spot reachable from the exit")
    if seed == 5 then
      write_png(("interior_%d_%s.png"):format(i, inside.roguelike.kind),
        H.render(inside.midLayout, NativeTileset.get(inside.pair)))
    end
  end

  -- 3. Town -> forest connection lines the exit up with the forest entry.
  check(Map.load(nil, game, town.id), label .. ": town reloads with its neighbours")
  local entry = forest.roguelike.layout.entry
  local below, belowPair = Map.worldMidAt(tl.exit.x, town.height, town)
  check(belowPair == forest.pair and below == forest.midLayout:midAt(entry.x, 0),
    label .. ": stepping south of the town exit is the forest entry")
  check(Map.load(nil, game, forest.id), label .. ": forest loads")
  local above, abovePair = Map.worldMidAt(entry.x, -1, forest)
  check(abovePair == town.pair and above == town.midLayout:midAt(tl.exit.x, town.height - 1),
    label .. ": stepping north of the forest entry is the town exit")

  -- 4. Deterministic: a fresh process rebuilds the same town.
  local cells = town.midLayout.cells
  R.world.forget()
  local again = select(2, R.world.build({ version = 2, seed = seed, layer = 1 }, game)).town
  local same = again ~= town
  for c, cell in ipairs(again.midLayout.cells) do same = same and cell.mid == cells[c].mid end
  check(same, label .. ": town regenerates identically")
  R.world.forget()
end
check(animated + stepDoors > 0, "doors were checked")

exports.restore()
run.release()
print(("PASS town: %d assertions (%d animated doors, %d step-warp doors)"):format(H.total, animated, stepDoors))
