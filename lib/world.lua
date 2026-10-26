-- The run's world: every area is generated from the run seed, so a save only
-- stores the seed and the areas are rebuilt identically on Continue. Areas
-- are registered against the live game's map table before the field loads.
--
-- A layer (this slice): a town whose buildings lead to generated interiors,
-- and a forest joined to the town's exit by a map connection.

local R = ...

local World = {}

local cache = {}      -- [areaId] = { seed, def }
local registered = {} -- [areaId] = { game, def }

local function cached(id, seed, build)
  local hit = cache[id]
  if hit and hit.seed == seed then return hit.def end
  local def = build()
  cache[id] = { seed = seed, def = def }
  return def
end

function World.layerSeed(state)
  return (state.seed * 31 + (state.layer or 1) * 7919) % 2147483647
end

-- Generate (or reuse) a layer's areas and link them. Returns the layer:
-- { town, forest, interiors = { ... }, all = { town, forest, interiors... } }.
function World.layer(state)
  local n, base = state.layer or 1, World.layerSeed(state)
  local town = cached(("FR_RL_L%d_TOWN"):format(n), base + 1, function()
    return (R.generate.town(("FR_RL_L%d_TOWN"):format(n), base + 1))
  end)
  local forest = cached(("FR_RL_L%d_A"):format(n), base, function()
    local def = R.generate.area(("FR_RL_L%d_A"):format(n), "forest", base)
    -- the encounter table has its own stream so map tweaks never reshuffle it
    def.roguelike.encounters = R.wild.table("forest", n, R.rng.new(base * 3 + 101))
    return def
  end)

  local interiors = {}
  town.warps = {}
  for i, b in ipairs(town.roguelike.layout.buildings) do
    local id = ("FR_RL_L%d_B%d"):format(n, i)
    local inside = cached(id, base + 100 + i, function()
      return R.generate.interior(id, b.kind, base + 100 + i)
    end)
    local exit = inside.roguelike.layout.exit
    town.warps[i] = { x = b.door.x, y = b.door.y, destMap = id, destWarp = 1 }
    inside.warps = { { x = exit.x, y = exit.y, destMap = town.id, destWarp = i } }
    for _, twin in ipairs(inside.roguelike.layout.exitTwins or {}) do
      inside.warps[#inside.warps + 1] = { x = twin.x, y = twin.y, destMap = town.id, destWarp = i }
    end
    interiors[i] = inside
  end

  -- The town's bottom exit continues into the forest's top entry.
  local townExit, forestEntry = town.roguelike.layout.exit, forest.roguelike.layout.entry
  town.connections = { { dir = "south", map = forest.id, offset = townExit.x - forestEntry.x } }
  forest.connections = { { dir = "north", map = town.id, offset = forestEntry.x - townExit.x } }

  local all = { town, forest }
  for _, d in ipairs(interiors) do all[#all + 1] = d end
  return { town = town, forest = forest, interiors = interiors, all = all }
end

-- Generate a run's current layer and register it when a game is known.
-- Returns its area list, the town (where a run starts) first.
function World.build(state, game)
  local layer = World.layer(state)
  if game then
    for _, def in ipairs(layer.all) do World.register(game, def) end
  end
  return layer.all, layer
end

function World.register(game, def)
  if not (type(game) == "table" and type(game.data) == "table" and type(game.data.maps) == "table") then return end
  game.data.maps[def.id] = def
  if def.roguelike and def.roguelike.encounters then R.wild.register(def.id, def.roguelike.encounters) end
  registered[def.id] = { game = game, def = def }
end

function World.unregisterAll()
  for id, entry in pairs(registered) do
    local maps = entry.game.data and entry.game.data.maps
    if maps and maps[id] == entry.def then maps[id] = nil end
  end
  registered = {}
  R.wild.unregisterAll()
end

-- Drop generated areas entirely (the state of a freshly started process).
function World.forget()
  World.unregisterAll()
  cache = {}
end

return World
