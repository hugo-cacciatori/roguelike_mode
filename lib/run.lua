-- Run state. A run is a FireRed session carrying `modData.roguelike`; New
-- Game creates one (the vanilla adventure cannot be started while the mod is
-- enabled), generates the first layer from the run seed, and places the
-- player at its first area's entry.

local R = ...

local Run = {}

Run.STATE_VERSION = 2

function Run.state(session)
  local data = type(session) == "table" and session.modData
  local state = type(data) == "table" and data.roguelike
  return type(state) == "table" and state or nil
end

function Run.isRun(session)
  return Run.state(session) ~= nil
end

local function seedFor(session)
  local tid = tonumber(session.trainerId) or 0
  local sid = tonumber(session.secretId) or 0
  return (tid * 65536 + sid + os.time()) % 2147483647
end

function Run.begin(session, game)
  local state = { version = Run.STATE_VERSION, seed = seedFor(session), layer = 1 }
  session.modData = type(session.modData) == "table" and session.modData or {}
  session.modData.roguelike = state
  local first = R.world.build(state, game)[1]
  local entry = first.roguelike.layout.entry
  session.map, session.x, session.y = first.id, entry.x, entry.y
  session.facing = "down"
  return session
end

-- The live game, learned from game.ready (hooks receive only the session).
Run.game = nil

function Run.install(mod)
  mod.hooks:wrap("save.new_game", function(next, session)
    session = next(session)
    if type(session) ~= "table" then return session end
    return Run.begin(session, Run.game)
  end)
  -- Continue: rebuild the saved run's areas before the field loads them.
  mod.events:on("save.loading", function(payload)
    local raw = type(payload) == "table" and (payload.raw or payload.save) or nil
    local state = Run.state(raw)
    if state then R.world.build(state, Run.game) end
  end)
end

return Run
