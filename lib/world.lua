-- The run's world: every area is generated from the run seed, so a save only
-- stores the seed and the areas are rebuilt identically on Continue. Areas
-- are registered against the live game's map table before the field loads.

local R = ...

local World = {}

local cache = {}      -- [areaId] = { def, report }
local registered = {} -- [areaId] = { game, def }

-- The areas of a layer (this slice: one forest area for layer 1).
function World.plan(state)
  return {
    { id = ("FR_RL_L%d_A"):format(state.layer or 1), env = "forest",
      seed = (state.seed * 31 + (state.layer or 1) * 7919) % 2147483647 },
  }
end

function World.area(spec)
  local hit = cache[spec.id]
  if hit and hit.seed == spec.seed then return hit.def, hit.report end
  local def, report = R.generate.area(spec.id, spec.env, spec.seed)
  cache[spec.id] = { seed = spec.seed, def = def, report = report }
  return def, report
end

-- Generate (or reuse) a run's areas; register them when a game is known.
function World.build(state, game)
  local defs = {}
  for i, spec in ipairs(World.plan(state)) do
    defs[i] = World.area(spec)
    if game then World.register(game, defs[i]) end
  end
  return defs
end

function World.register(game, def)
  if not (type(game) == "table" and type(game.data) == "table" and type(game.data.maps) == "table") then return end
  game.data.maps[def.id] = def
  registered[def.id] = { game = game, def = def }
end

function World.unregisterAll()
  for id, entry in pairs(registered) do
    local maps = entry.game.data and entry.game.data.maps
    if maps and maps[id] == entry.def then maps[id] = nil end
  end
  registered = {}
end

-- Drop generated areas entirely (the state of a freshly started process).
function World.forget()
  World.unregisterAll()
  cache = {}
end

return World
