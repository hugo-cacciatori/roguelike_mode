-- Engine-path checks: the real loader, a FireRed session hydrated from the
-- player's imports, Map.load, and the engine's own collision rules.
local H = dofile(MOD_ROOT .. "/tests/harness.lua")
local check = H.check

local game = H.bootFireRed()
local Sdk = require("tests.modkit.sdk")
local Runtime = require("src.mods.Runtime")
local NativeTileset = require("src.core.game3.tileset_native")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Collision = require("src.core.game3.collision")
local Map = require("src.core.game3.map")
local MB = require("src.core.game3.mb")
local Dataset = require("src.core.game3.dataset")

local originalGet = NativeTileset.get

-- 1. Load the shipped files through the real loader.
local run = Sdk.loadMods({ "mods/roguelike_mode" },
  { fs = Sdk.memfs(MOD_FILES), generation = 3, data = game.data })
check(#run.errors == 0, "load errors: " .. table.concat(run.errors, "\n"))
local mod = run.mods.roguelike_mode
check(mod and mod.state == "loaded", "mod loaded")
local exports = run.loader.exports.roguelike_mode
check(type(exports) == "table" and exports.R, "mod exports its modules")
local R = exports.R
check(R.sources.available("firered"), "FireRed import is readable")
check(R.sources.available("emerald"), "Emerald import is readable")

Runtime.emit("game.ready", { game = game })

local DIRS = { "up", "down", "left", "right" }
local STEP = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Cells reachable on foot from (x, y) under the engine's walk and ledge rules.
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
  return seen, #queue
end

-- Walkable regions with their size and edge-touching cells (for curating entry/exit).
local function survey(def)
  local claimed, regions = {}, {}
  for y = 0, def.height - 1 do
    for x = 0, def.width - 1 do
      local k = y * def.width + x
      if not claimed[k] and Collision.isWalkable(x, y) then
        local seen, n = reachable(def, x, y)
        local top, bottom = {}, {}
        local ymin, ymax = math.huge, -1
        for key in pairs(seen) do
          claimed[key] = true
          local ey = math.floor(key / def.width)
          ymin, ymax = math.min(ymin, ey), math.max(ymax, ey)
        end
        for key in pairs(seen) do
          local ex, ey = key % def.width, math.floor(key / def.width)
          if ey == ymin then top[#top + 1] = ex end
          if ey == ymax then bottom[#bottom + 1] = ex end
        end
        table.sort(top)
        table.sort(bottom)
        regions[#regions + 1] = { n = n, ymin = ymin, ymax = ymax,
          top = table.concat(top, ","), bottom = table.concat(bottom, ",") }
      end
    end
  end
  table.sort(regions, function(a, b) return a.n > b.n end)
  for i = 1, math.min(4, #regions) do
    local r = regions[i]
    print(("      region %d: %d cells, top row %d x={%s}, bottom row %d x={%s}"):format(
      i, r.n, r.ymin, r.top, r.ymax, r.bottom))
  end
end

for _, spec in ipairs(R.data.chunks.composites) do
  local def = game.data.maps[spec.id]
  check(def ~= nil, spec.id .. " registered on game.ready")
  local ts = NativeTileset.get(def.pair)
  check(ts and ts.pair == def.pair, spec.id .. ": merged pair served by NativeTileset.get")
  check(NativeTileset.ready(def.pair), spec.id .. ": merged pair reports ready")

  -- 2. Survives the engine reloading its pairs, behaviours and encounter types.
  NativeTileset.install(Dataset.cache(), nil)
  NativeTileset._pairs[def.pair] = nil
  check(NativeTileset.get(def.pair) == ts, spec.id .. ": pair survives NativeTileset.install/trim")
  Interaction.install({ behaviors = {} })
  check(Interaction.behaviors[def.pair] ~= nil, spec.id .. ": behaviours survive InteractionScripts.install")

  -- 3. Loads like any map; every cell draws and has a behaviour.
  check(Map.load(nil, game, spec.id, { depth1Connections = false }), spec.id .. ": Map.load")
  check(Collision._mapDef == def, spec.id .. ": collision grid bound")
  local missingSlot, missingBehavior, names = 0, 0, {}
  for y = 0, def.height - 1 do
    for x = 0, def.width - 1 do
      local mid = def.midLayout:midAt(x, y)
      if ts.midToSlot[mid] == nil then missingSlot = missingSlot + 1 end
      local b = Collision.behaviorOn(def, x, y)
      if b == nil then missingBehavior = missingBehavior + 1
      else names[MB.nameOf(b) or b] = true end
    end
  end
  check(missingSlot == 0, ("%s: %d cells have no atlas slot"):format(spec.id, missingSlot))
  check(missingBehavior == 0, ("%s: %d cells have no behaviour"):format(spec.id, missingBehavior))
  check(names.TALL_GRASS, spec.id .. ": tall grass survives the splice")

  -- 4. The curated entry reaches the curated exit.
  if spec.entry.x == 0 and spec.entry.y == 0 and spec.exit.x == 0 and spec.exit.y == 0 then
    print("      " .. spec.id .. " has no curated entry/exit yet; walkable regions:")
    survey(def)
    check(false, spec.id .. ": entry/exit not curated")
  end
  check(Collision.isWalkable(spec.entry.x, spec.entry.y), spec.id .. ": entry is walkable")
  check(Collision.isWalkable(spec.exit.x, spec.exit.y), spec.id .. ": exit is walkable")
  local seen = reachable(def, spec.entry.x, spec.entry.y)
  if not seen[spec.exit.y * def.width + spec.exit.x] then survey(def) end
  check(seen[spec.exit.y * def.width + spec.exit.x], spec.id .. ": exit reachable from entry")

  write_png(spec.id .. ".png", H.render(def.midLayout, ts))
end

-- 5. Rollback restores the engine.
exports.restore()
check(NativeTileset.get == originalGet, "restore unwraps NativeTileset.get")
for _, spec in ipairs(R.data.chunks.composites) do
  check(game.data.maps[spec.id] == nil, spec.id .. " unregistered by restore")
end
run.release()

print(("PASS integration: %d assertions"):format(H.total))
