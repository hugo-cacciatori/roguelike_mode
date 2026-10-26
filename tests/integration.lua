-- Engine-path checks on generated areas: the real loader, a FireRed session
-- hydrated from the player's imports, Map.load, and the engine's own
-- collision rules.
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
check(run.mods.roguelike_mode and run.mods.roguelike_mode.state == "loaded", "mod loaded")
local exports = run.loader.exports.roguelike_mode
local R = exports.R
check(R.sources.available("firered") and R.sources.available("emerald"), "both imports readable")
Runtime.emit("game.ready", { game = game })

-- No generated map may reuse a base-game layout: every cell comes from the painter.
local function sourceIds()
  local ids = {}
  for _, v in ipairs(R.corpus.VERSIONS) do
    for _, m in ipairs(R.corpus.maps(v)) do ids[m.id] = true end
  end
  return ids
end
local baseIds = sourceIds()

local DIRS = { "up", "down", "left", "right" }
local STEP = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local function engineReachable(def, x, y)
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

local seeds = { 11, 222, 3333 }
for _, seed in ipairs(seeds) do
  local state = { version = 2, seed = seed, layer = 1 }
  local _, layer = R.world.build(state, game)
  local def = layer.forest
  local label = def.id .. " seed " .. seed
  local layout = def.roguelike.layout
  check(game.data.maps[def.id] == def, label .. ": registered on the session game")
  check(not baseIds[def.id], label .. ": id is not a base-game map")

  -- 2. Merged pair served and kept through engine reloads.
  local ts = NativeTileset.get(def.pair)
  check(ts and ts.pair == def.pair and NativeTileset.ready(def.pair), label .. ": generated pair served")
  NativeTileset.install(Dataset.cache(), nil)
  NativeTileset._pairs[def.pair] = nil
  check(NativeTileset.get(def.pair) == ts, label .. ": pair survives NativeTileset.install/trim")
  Interaction.install({ behaviors = {} })
  check(Interaction.behaviors[def.pair] ~= nil, label .. ": behaviours survive InteractionScripts.install")

  -- 3. The engine loads it; every cell draws and has a behaviour; grass exists.
  check(Map.load(nil, game, def.id, { depth1Connections = false }), label .. ": Map.load")
  check(Collision._mapDef == def, label .. ": collision grid bound")
  local missing, grass = 0, 0
  for y = 0, def.height - 1 do
    for x = 0, def.width - 1 do
      if ts.midToSlot[def.midLayout:midAt(x, y)] == nil or Collision.behaviorOn(def, x, y) == nil then
        missing = missing + 1
      end
      if MB.nameOf(Collision.behaviorOn(def, x, y) or -1) == "TALL_GRASS" then grass = grass + 1 end
    end
  end
  check(missing == 0, ("%s: %d cells without slot or behaviour"):format(label, missing))
  check(grass > 0, label .. ": wild grass painted")

  -- 4. Functional spots are reachable under the engine's walk rules, and the
  --    mod's own reachability (used at generation time) agrees.
  local seen = engineReachable(def, layout.entry.x, layout.entry.y)
  local own = R.generate.reachable(def.midLayout.cells, def.width, def.height, layout.entry.x, layout.entry.y,
    R.atlas.behaviorsOf(def.pair))
  local function both(p) return seen[p.y * def.width + p.x] and own[p.y * def.width + p.x] end
  check(both(layout.exit), label .. ": exit reachable")
  check(both(layout.boss), label .. ": boss spot reachable")
  for i, t in ipairs(layout.trainers) do check(both(t), label .. ": trainer spot " .. i .. " reachable") end

  -- 5. Deterministic: the same seed paints the same map (Continue rebuilds it).
  local again = R.generate.area(def.id .. "_AGAIN", "forest", def.roguelike.seed)
  local identical = true
  for i, cell in ipairs(def.midLayout.cells) do
    local other = again.midLayout.cells[i]
    identical = identical and other.mid == cell.mid and other.coll == cell.coll
  end
  check(identical, label .. ": regeneration is identical")

  write_png(("generated_forest_%d.png"):format(seed), H.render(def.midLayout, ts))
  R.world.unregisterAll()
end

-- 6. Rollback restores the engine.
exports.restore()
check(NativeTileset.get == originalGet, "restore unwraps NativeTileset.get")
run.release()

print(("PASS integration: %d assertions"):format(H.total))
