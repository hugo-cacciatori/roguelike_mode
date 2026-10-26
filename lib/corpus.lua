-- What both games' maps teach about tiles. Every source map is classified
-- into an environment (forest, cave, sea, route, town, interior kinds) from
-- its header; for a tileset pair, every metatile gets a class (block, walk,
-- grass, water, ledge, door), its usual collision/elevation, a frequency, and
-- the neighbours it was seen with. Generated maps are painted from this --
-- no source map is ever copied.

local R = ...
local Json = require("src.link.Json")
-- Generation-neutral collision codes plus Gen 3 behaviours: a Gen 3 mod may
-- not load the Gen 2 permission module the engine uses internally.
local CollPermissions = require("src.core.CollPermissions")
local MB = require("src.core.game3.mb")
local Collision = require("src.core.game3.collision")

local Corpus = {}

Corpus.VERSIONS = { "firered", "emerald" }
local PREFIX = { firered = "FR_", emerald = "EM_" }

local memo = { maps = {}, pairs = {} }

-- pret CamelCase ids ("PokemonCenter_1F") and manifest ids
-- ("EM_POKEMON_CENTER_1F") agree once underscores and case are dropped.
local function normalize(id) return (id:gsub("[^%w]", ""):upper()) end

local function manifestIndex(version, manifest)
  local index, prefix = {}, PREFIX[version]
  for id in pairs(manifest.layouts) do
    index[normalize(id:sub(1, #prefix) == prefix and id:sub(#prefix + 1) or id)] = id
  end
  return index
end

local INTERIOR_KINDS = {
  { "LAB", "lab" }, { "POKEMON_CENTER", "center" }, { "MART", "mart" }, { "GYM", "gym" },
}

function Corpus.environmentOf(id, header, waterShare)
  local mapType, cave = tonumber(header.mapType) or 0, tonumber(header.cave) or 0
  if id:find("FOREST") or id:find("WOODS") then return "forest" end
  if mapType == 8 or mapType == 9 then
    for _, k in ipairs(INTERIOR_KINDS) do
      if id:find(k[1]) then return "interior_" .. k[2] end
    end
    return "interior_house"
  end
  if mapType == 4 or cave == 1 then return "cave" end
  if mapType == 5 then return "underwater" end
  if mapType == 6 or (waterShare or 0) > 0.35 then return "sea" end
  if mapType == 1 or mapType == 2 then return "town" end
  if mapType == 3 then return "route" end
  return "other"
end

local GRASS = {}
for _, name in ipairs({ "TALL_GRASS", "LONG_GRASS", "ASHGRASS" }) do
  local id = MB.id(name)
  if id then GRASS[id] = true end
end

-- Ledge behaviours -> the direction a hop over them goes.
Corpus.LEDGE_FACING = {}
for name, dir in pairs({ JUMP_SOUTH = "down", JUMP_NORTH = "up", JUMP_EAST = "right", JUMP_WEST = "left" }) do
  local id = MB.id(name)
  if id then Corpus.LEDGE_FACING[id] = dir end
end

-- Class of a cell from its collision code and its tile's behaviour.
function Corpus.classOf(coll, behavior)
  if coll == nil then return "block" end
  if behavior and Collision.isWarpMetatileBehavior(behavior) then return "door" end
  if behavior and Corpus.LEDGE_FACING[behavior] then return "ledge" end
  if CollPermissions.isLedge(coll) then return "ledge" end
  if CollPermissions.isWater(coll) then return "water" end
  if not CollPermissions.isWalkable(coll) then return "block" end
  if behavior and GRASS[behavior] then return "grass" end
  return "walk"
end

-- Every source map of a version: { id, pair, env, layout = { decoded } }.
function Corpus.maps(version)
  if memo.maps[version] then return memo.maps[version] end
  local census = Json.decode(assert(R.sources.read(version, "map_tree/census.json")))
  local manifest = assert(R.sources.loadLua(version, "native/manifest.lua"))
  local index = manifestIndex(version, manifest)
  local list = {}
  for _, group in ipairs(census.groups or {}) do
    for _, entry in ipairs(group.maps or {}) do
      local id = index[normalize(entry.id)]
      local info = id and manifest.layouts[id]
      local raw = R.sources.read(version, "map_tree/maps/" .. entry.slot .. "/header.json")
      if info and raw then
        local decoded = R.catalog.layout(version, id)
        local water = 0
        for _, cell in ipairs(decoded.cells) do
          if Corpus.classOf(cell.coll) == "water" then water = water + 1 end
        end
        list[#list + 1] = { id = id, version = version, pair = info.pair, decoded = decoded, slot = entry.slot,
          env = Corpus.environmentOf(id, Json.decode(raw), water / math.max(1, #decoded.cells)) }
      end
    end
  end
  memo.maps[version] = list
  return list
end

-- Tileset pairs used by an environment in one version, with their cell counts.
function Corpus.pairsFor(version, env)
  local totals = {}
  for _, map in ipairs(Corpus.maps(version)) do
    if map.env == env then
      totals[map.pair] = (totals[map.pair] or 0) + #map.decoded.cells
    end
  end
  local list = {}
  for pair, cells in pairs(totals) do list[#list + 1] = { pair = pair, cells = cells } end
  table.sort(list, function(a, b)
    if a.cells ~= b.cells then return a.cells > b.cells end
    return a.pair < b.pair -- deterministic order: worlds are regenerated from seeds
  end)
  return list
end

local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end

local function majority(counts)
  local best, bestN
  for k, n in pairs(counts) do
    if not bestN or n > bestN or (n == bestN and tostring(k) < tostring(best)) then best, bestN = k, n end
  end
  return best
end

-- Statistics of one pair, learned from every map that uses it.
-- tiles[mid] = { count, class, coll, elev }; right[a][b] / down[a][b] = times seen.
function Corpus.pairModel(version, pair)
  local key = version .. "|" .. pair
  if memo.pairs[key] then return memo.pairs[key] end
  local stats, right, down = {}, {}, {}
  for _, map in ipairs(Corpus.maps(version)) do
    if map.pair == pair then
      local d = map.decoded
      local w, h = d.trueWidth or d.width, d.trueHeight or d.height
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local c = d.cells[y * d.width + x + 1]
          local s = stats[c.mid]
          if not s then s = { count = 0, colls = {}, elevs = {} }; stats[c.mid] = s end
          s.count = s.count + 1
          bump(s.colls, c.coll)
          bump(s.elevs, c.elev)
          if x + 1 < w then
            local r = d.cells[y * d.width + x + 2].mid
            right[c.mid] = right[c.mid] or {}
            bump(right[c.mid], r)
          end
          if y + 1 < h then
            local b = d.cells[(y + 1) * d.width + x + 1].mid
            down[c.mid] = down[c.mid] or {}
            bump(down[c.mid], b)
          end
        end
      end
    end
  end
  local behaviors = R.catalog.behaviors(version, pair)
  local tiles = {}
  for mid, s in pairs(stats) do
    local coll = majority(s.colls)
    local behavior = behaviors[mid]
    tiles[mid] = { count = s.count, coll = coll, elev = majority(s.elevs), behavior = behavior,
      class = Corpus.classOf(coll, behavior) }
  end
  local model = { version = version, pair = pair, tiles = tiles, right = right, down = down }
  memo.pairs[key] = model
  return model
end

return Corpus
