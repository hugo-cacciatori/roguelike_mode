-- What the imports know about one source map: its decoded layout, its tileset
-- pair, and the per-pair behaviour and encounter-type tables. Behaviours from
-- both games are already in the engine's shared MB id space.

local R = ...
local NativePack = require("src.import.gba.native_pack")

local Catalog = {}

local layoutMemo = {}

local function manifest(version)
  return assert(R.sources.loadLua(version, "native/manifest.lua"),
    "roguelike_mode: " .. version .. " native manifest is missing")
end

local function objects(version)
  return R.sources.loadLua(version, "objects/pack.lua") or {}
end

-- decoded layout ({ width, height, cells, border... }) and its pair
function Catalog.layout(version, mapId)
  local key = version .. "|" .. mapId
  local hit = layoutMemo[key]
  if hit then return hit.decoded, hit.pair end
  local info = manifest(version).layouts[mapId]
  assert(info, ("roguelike_mode: %s has no layout %s"):format(version, mapId))
  local blob = assert(R.sources.read(version, "native/" .. info.file),
    "roguelike_mode: unreadable layout " .. info.file)
  local decoded = assert(NativePack.decodeMidLayout(blob))
  layoutMemo[key] = { decoded = decoded, pair = info.pair }
  return decoded, info.pair
end

function Catalog.behaviors(version, pair)
  return (objects(version).behaviors or {})[pair] or {}
end

function Catalog.encounterTypes(version, pair)
  return (objects(version).encounterTypes or {})[pair] or {}
end

function Catalog.forget()
  layoutMemo = {}
end

return Catalog
