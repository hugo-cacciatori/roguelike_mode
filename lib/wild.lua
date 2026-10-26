-- Generated wild encounter tables (spec §9.D). Which species live in which
-- environment is learned from both games' wild tables; which form of a
-- family appears at a level follows its evolution rules; levels follow the
-- layer band. Tables are installed where the engine's own encounter step
-- reads them.

local R = ...
local Pokemon = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local EngineEncounters = require("src.core.game3.encounters")

local Wild = {}

-- Gen 3 slot probabilities (pokefirered/src/wild_encounter.c).
Wild.LAND_RATES = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
Wild.WATER_RATES = { 60, 30, 5, 4, 1 }
Wild.FISHING_RATES = { 70, 30, 60, 20, 20, 40, 40, 15, 4, 1 }

-- Wild level bands per layer (spec §4.A).
Wild.BANDS = {
  { 5, 12 }, { 13, 19 }, { 20, 26 }, { 27, 33 }, { 34, 40 }, { 41, 46 }, { 47, 52 }, { 53, 58 },
}
Wild.CAP_SLACK = 4      -- levels a form may exceed its evolution threshold
Wild.LATE_LEVEL = 40    -- friendship / trade evolutions (the mod's Lv. 40 rule)
Wild.STONE_MIN = 30
Wild.STONE_GAP = 15
Wild.MAX_SPECIES = 411

-- Which table kinds an environment's encounters come from.
Wild.KINDS = { forest = { "land" }, route = { "land" }, cave = { "land" }, sea = { "water", "fishing" } }

local LEVEL_METHODS = {
  [Evolution.EVO_LEVEL] = true, [Evolution.EVO_LEVEL_ATK_GT_DEF] = true,
  [Evolution.EVO_LEVEL_ATK_EQ_DEF] = true, [Evolution.EVO_LEVEL_ATK_LT_DEF] = true,
  [Evolution.EVO_LEVEL_SILCOON] = true, [Evolution.EVO_LEVEL_CASCOON] = true,
  [Evolution.EVO_LEVEL_NINJASK] = true, [Evolution.EVO_LEVEL_SHEDINJA] = true,
}

local function evoRow(e)
  return tonumber(e.method or e[1]) or 0, tonumber(e.param or e[2]) or 0, tonumber(e.target or e[3]) or 0
end

local memo = {}

function Wild.valid(species)
  local name = species and species > 0 and species <= Wild.MAX_SPECIES and Pokemon.name(species)
  return type(name) == "string" and name ~= "?" and name ~= ""
end

-- Evolution rows of every species, and the reverse (pre-evolution) links.
local function graph()
  if memo.graph then return memo.graph end
  local forward, pre = {}, {}
  for s = 1, Wild.MAX_SPECIES do
    if Wild.valid(s) then
      forward[s] = {}
      for _, e in ipairs(Pokemon.evolutions(s) or {}) do
        local method, param, target = evoRow(e)
        if Wild.valid(target) then
          forward[s][#forward[s] + 1] = { method = method, param = param, target = target }
          pre[target] = pre[target] or { from = s, method = method, param = param }
        end
      end
    end
  end
  memo.graph = { forward = forward, pre = pre }
  return memo.graph
end

-- Every species seen in any wild table of either game, with its levels.
local function sources()
  if memo.sources then return memo.sources end
  local list = {}
  for _, version in ipairs(R.corpus.VERSIONS) do
    if R.sources.available(version) then
      local tables = R.sources.loadLua(version, "encounters.lua") or {}
      for _, map in ipairs(R.corpus.maps(version)) do
        local t = tables[(map.slot or ""):gsub("_", ":")]
        if t then list[#list + 1] = { env = map.env, tables = t } end
      end
    end
  end
  local seenWild = {}
  for _, entry in ipairs(list) do
    for _, kind in pairs(entry.tables) do
      if type(kind) == "table" and kind.slots then
        for _, slot in ipairs(kind.slots) do seenWild[slot.species] = true end
      end
    end
  end
  memo.sources = { list = list, seenWild = seenWild }
  return memo.sources
end

-- The family a species belongs to for wild purposes: its earliest ancestor
-- that appears in some wild table (Pikachu, not Pichu), else its root.
function Wild.baseOf(species)
  local g, seen = graph(), sources().seenWild
  local s, best = species, species
  local guard = 0
  while g.pre[s] and guard < 8 do
    s = g.pre[s].from
    guard = guard + 1
    if seen[s] then best = s end
  end
  if not seen[best] then best = s end
  return best
end

-- Lowest level at which a form is coherent in the wild.
function Wild.minLevel(species)
  memo.min = memo.min or {}
  if memo.min[species] then return memo.min[species] end
  local g = graph()
  local level = 1
  local link = g.pre[species]
  if link and Wild.baseOf(species) ~= species then
    local parent = Wild.minLevel(link.from)
    if LEVEL_METHODS[link.method] then
      level = math.max(parent, link.param)
    elseif link.method == Evolution.EVO_ITEM then
      level = math.max(parent + Wild.STONE_GAP, Wild.STONE_MIN)
    else
      level = math.max(parent, Wild.LATE_LEVEL)
    end
  end
  memo.min[species] = level
  return level
end

-- Highest level at which a form is still coherent (it should have evolved).
function Wild.cap(species)
  local cap = 100
  for _, e in ipairs(graph().forward[species] or {}) do
    local threshold = LEVEL_METHODS[e.method] and e.param or Wild.minLevel(e.target)
    cap = math.min(cap, threshold + Wild.CAP_SLACK)
  end
  return cap
end

function Wild.coherent(species, level)
  return Wild.valid(species) and level >= Wild.minLevel(species) and level <= Wild.cap(species)
end

-- The family's form at `level`, walking evolutions forward (branches drawn).
function Wild.formAt(base, level, rng)
  local s, guard = base, 0
  while guard < 8 do
    guard = guard + 1
    local options = {}
    for _, e in ipairs(graph().forward[s] or {}) do
      if Wild.minLevel(e.target) <= level then options[#options + 1] = e.target end
    end
    if #options == 0 then break end
    table.sort(options)
    s = rng and rng:pick(options) or options[1]
  end
  return s
end

-- Learned families per environment and table kind: pools[env][kind] =
-- { list = { { base, weight } ... }, rate = average encounter rate }.
function Wild.pools()
  if memo.pools then return memo.pools end
  local acc = {}
  for _, entry in ipairs(sources().list) do
    for kind, t in pairs(entry.tables) do
      if type(t) == "table" and t.slots then
        local rates = kind == "land" and Wild.LAND_RATES or kind == "water" and Wild.WATER_RATES
          or kind == "fishing" and Wild.FISHING_RATES or nil
        if rates then
          acc[entry.env] = acc[entry.env] or {}
          local a = acc[entry.env][kind] or { weights = {}, rates = 0, n = 0 }
          acc[entry.env][kind] = a
          a.rates, a.n = a.rates + (tonumber(t.rate) or 0), a.n + 1
          for i, slot in ipairs(t.slots) do
            if Wild.valid(slot.species) then
              local base = Wild.baseOf(slot.species)
              a.weights[base] = (a.weights[base] or 0) + (rates[i] or 1)
            end
          end
        end
      end
    end
  end
  local pools = {}
  for env, kinds in pairs(acc) do
    pools[env] = {}
    for kind, a in pairs(kinds) do
      local list = {}
      for base, w in pairs(a.weights) do list[#list + 1] = { base = base, weight = w } end
      table.sort(list, function(x, y)
        if x.weight ~= y.weight then return x.weight > y.weight end
        return x.base < y.base
      end)
      pools[env][kind] = { list = list, rate = math.floor(a.rates / math.max(1, a.n) + 0.5) }
    end
  end
  memo.pools = pools
  return pools
end

local function drawFamilies(pool, count, rng)
  local chosen, left = {}, {}
  for i, f in ipairs(pool.list) do left[i] = f end
  while #chosen < count and #left > 0 do
    local weights, total = {}, 0
    for i, f in ipairs(left) do weights[i] = f.weight; total = total + f.weight end
    local i = rng:weighted(weights, total)
    chosen[#chosen + 1] = table.remove(left, i).base
  end
  return chosen
end

-- Slot groups sharing one level sub-band: land and surf are one group; the
-- fishing table is three rods (old 1-2, good 3-5, super 6-10) climbing the band.
local GROUPS = {
  land = { { first = 1, last = 12, from = 0, to = 1 } },
  water = { { first = 1, last = 5, from = 0, to = 1 } },
  fishing = { { first = 1, last = 2, from = 0, to = 0.35 }, { first = 3, last = 5, from = 0.3, to = 0.7 },
    { first = 6, last = 10, from = 0.6, to = 1 } },
}

-- One table kind for an area: slots with coherent forms and levels.
local function slotsFor(kind, pool, band, rng)
  local rates = kind == "land" and Wild.LAND_RATES or kind == "water" and Wild.WATER_RATES or Wild.FISHING_RATES
  local families = drawFamilies(pool, math.min(#pool.list, kind == "land" and rng:int(4, 6) or rng:int(2, 4)), rng)
  local slots = {}
  for _, group in ipairs(GROUPS[kind]) do
    local lo = math.floor(band[1] + (band[2] - band[1]) * group.from + 0.5)
    local hi = math.floor(band[1] + (band[2] - band[1]) * group.to + 0.5)
    local order = {}
    for i = group.first, group.last do order[#order + 1] = i end
    table.sort(order, function(a, b) return rates[a] > rates[b] or (rates[a] == rates[b] and a < b) end)
    for rank, i in ipairs(order) do
      -- common slots sit low in the (sub-)band, rare ones high
      local f = (rank - 1) / math.max(1, #order - 1)
      local mid = math.floor(lo + (hi - lo) * f + 0.5)
      local min = math.max(lo, mid - rng:int(0, 1))
      local max = math.min(hi, mid + rng:int(0, 2))
      local base = families[((rank - 1) % #families) + 1]
      local species = Wild.formAt(base, min, rng)
      min = math.max(min, Wild.minLevel(species))
      max = math.max(min, math.min(max, Wild.cap(species)))
      slots[i] = { species = species, minLevel = min, maxLevel = max }
    end
  end
  return slots
end

-- A complete encounter table for an area of `env` on `layer`.
function Wild.table(env, layer, rng)
  local band = Wild.BANDS[math.max(1, math.min(#Wild.BANDS, layer or 1))]
  local pools = Wild.pools()[env]
  local out = {}
  for _, kind in ipairs(Wild.KINDS[env] or { "land" }) do
    local pool = pools and pools[kind]
    if pool and #pool.list > 0 then
      out[kind] = { rate = math.max(1, pool.rate), slots = slotsFor(kind, pool, band, rng) }
    end
  end
  return out
end

-- Installed tables survive the engine reloading its own.
local installed, original = {}, nil

function Wild.register(mapId, tbl)
  installed[mapId] = tbl
  EngineEncounters.ensureLoaded()
  EngineEncounters._tables[mapId] = tbl
end

function Wild.unregisterAll()
  for mapId, tbl in pairs(installed) do
    if EngineEncounters._tables and EngineEncounters._tables[mapId] == tbl then
      EngineEncounters._tables[mapId] = nil
    end
  end
  installed = {}
end

function Wild.install()
  if original then return end
  original = EngineEncounters.loadFromMod
  EngineEncounters.loadFromMod = function(...)
    local result = original(...)
    for mapId, tbl in pairs(installed) do EngineEncounters._tables[mapId] = tbl end
    return result
  end
end

function Wild.uninstall()
  Wild.unregisterAll()
  if original then EngineEncounters.loadFromMod = original; original = nil end
end

return Wild
