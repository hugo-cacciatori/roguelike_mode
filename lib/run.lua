-- Run state. A run is a FireRed session carrying `modData.roguelike`; New
-- Game creates one (the vanilla adventure cannot be started while the mod is
-- enabled) and places the player at the first composite map's entry.

local R = ...

local Run = {}

Run.STATE_VERSION = 1

function Run.state(session)
  local data = type(session) == "table" and session.modData
  local state = type(data) == "table" and data.roguelike
  return type(state) == "table" and state or nil
end

function Run.isRun(session)
  return Run.state(session) ~= nil
end

-- Where a new run starts: the first composite's curated entry.
function Run.start()
  local first = R.data.chunks.composites[1]
  return { map = first.id, x = first.entry.x, y = first.entry.y }
end

local function seedFor(session)
  local tid = tonumber(session.trainerId) or 0
  local sid = tonumber(session.secretId) or 0
  return (tid * 65536 + sid + os.time()) % 2147483647
end

function Run.begin(session)
  local start = Run.start()
  session.modData = type(session.modData) == "table" and session.modData or {}
  session.modData.roguelike = { version = Run.STATE_VERSION, seed = seedFor(session), layer = 1 }
  session.map, session.x, session.y = start.map, start.x, start.y
  session.facing = "down"
  return session
end

function Run.install(mod)
  mod.hooks:wrap("save.new_game", function(next, session)
    session = next(session)
    if type(session) ~= "table" then return session end
    return Run.begin(session)
  end)
end

return Run
