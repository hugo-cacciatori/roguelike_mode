-- Virtual tileset pairs for composite maps. A Gen 3 map binds one pair, so a
-- map spliced from several source pairs gets one merged pair: the parts'
-- atlases stacked vertically, part i's metatile ids shifted by (i-1)*MID_STRIDE,
-- and their behaviour and encounter-type tables merged under the same ids.
--
-- The engine reloads pairs, behaviours and encounter types on its own
-- schedule (NativeTileset.install/trim, InteractionScripts.install,
-- Encounters.installEncounterTypes), so merged entries are served through
-- wrappers that put them back instead of being written once.

local R = ...
local Decode = require("src.core.game3.asset_decode")
local NativeTileset = require("src.core.game3.tileset_native")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Encounters = require("src.core.game3.encounters")

local Atlas = {}

Atlas.MID_STRIDE = 4096 -- above every FRLG (<1024) and RSE (<1024) metatile id
Atlas.PREFIX = "rl_"

local LAYERS = {
  { image = "image", data = "imageData" },
  { image = "midImage", data = "midImageData" },
  { image = "overImage", data = "overImageData" },
}

local registry = {} -- [pairId] = { ts, behaviors, encounterTypes }
local originals

function Atlas.isOurs(pair)
  return type(pair) == "string" and registry[pair] ~= nil
end

local function newImage(data)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local image = love.graphics.newImage(data)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

local decodeMemo = {}

-- One source pair decoded by the engine's own decoder (memoized).
function Atlas.decode(version, pair)
  local key = version .. "|" .. pair
  if not decodeMemo[key] then
    decodeMemo[key] = assert(Decode.pair(R.sources.cacheFor(version), "native", pair))
  end
  return decodeMemo[key]
end

-- 16x16 RGBA of one metatile as drawn (under, mid and over layers composited),
-- as a flat 1-based byte array; nil when the pair has no slot for `mid`.
function Atlas.tilePixels(data, mid)
  local slot = data.midToSlot[mid]
  if not slot then return nil end
  local aw = data.cols * 16
  local sx, sy = (slot % data.cols) * 16, math.floor(slot / data.cols) * 16
  local out = {}
  for li, key in ipairs({ "imageData", "midImageData", "overImageData" }) do
    local layer
    for _, l in ipairs(data.layers) do if l.dataKey == key then layer = l.data end end
    local rgba = layer and layer.getString and layer:getString()
    if rgba then
      for py = 0, 15 do
        for px = 0, 15 do
          local si = ((sy + py) * aw + sx + px) * 4
          if li == 1 or rgba:byte(si + 4) > 0 then
            local di = (py * 16 + px) * 4
            out[di + 1], out[di + 2], out[di + 3], out[di + 4] =
              rgba:byte(si + 1), rgba:byte(si + 2), rgba:byte(si + 3), 255
          end
        end
      end
    end
  end
  return out
end

-- parts: { { version = "firered", pair = "..." }, ... } -> merged tileset
function Atlas.build(pairId, parts)
  assert(pairId:sub(1, #Atlas.PREFIX) == Atlas.PREFIX, "merged pair ids start with " .. Atlas.PREFIX)
  local decoded, cols, rows, midCount = {}, nil, 0, 0
  for i, part in ipairs(parts) do
    local data = Atlas.decode(part.version, part.pair)
    cols = cols or data.cols
    assert(data.cols == cols, "roguelike_mode: atlas widths differ for " .. part.pair)
    decoded[i] = { data = data, rowOffset = rows, midOffset = (i - 1) * Atlas.MID_STRIDE }
    rows = rows + data.rows
    midCount = midCount + data.midCount
  end

  local ts = { pair = pairId, cols = cols, rows = rows, midCount = midCount, layered = false,
    midToSlot = {}, quads = {}, overQuads = {}, slotPix = {}, bgr = decoded[1].data.bgr }
  for _, d in ipairs(decoded) do
    local slotOffset = d.rowOffset * cols
    for mid, slot in pairs(d.data.midToSlot) do ts.midToSlot[mid + d.midOffset] = slot + slotOffset end
    ts.layered = ts.layered or d.data.layered or false
  end
  for _, layer in ipairs(LAYERS) do
    local merged
    for _, d in ipairs(decoded) do
      for _, src in ipairs(d.data.layers) do
        if src.dataKey == layer.data then
          merged = merged or love.image.newImageData(cols * 16, rows * 16)
          merged:paste(src.data, 0, d.rowOffset * 16, 0, 0, cols * 16, d.data.rows * 16)
        end
      end
    end
    if merged then
      ts[layer.data] = merged
      ts[layer.image] = newImage(merged)
    end
  end

  local behaviors, encounterTypes = {}, {}
  for i, part in ipairs(parts) do
    local offset = decoded[i].midOffset
    for mid, b in pairs(R.catalog.behaviors(part.version, part.pair)) do behaviors[mid + offset] = b end
    for mid, e in pairs(R.catalog.encounterTypes(part.version, part.pair)) do encounterTypes[mid + offset] = e end
  end
  return ts, behaviors, encounterTypes
end

local function applyTables(pairId)
  local entry = registry[pairId]
  if not entry then return end
  if type(Interaction.behaviors) == "table" then Interaction.behaviors[pairId] = entry.behaviors end
  if type(Encounters._encounterTypes) == "table" then
    Encounters._encounterTypes[pairId] = entry.encounterTypes
  end
end

function Atlas.register(pairId, parts)
  if not registry[pairId] then
    local ts, behaviors, encounterTypes = Atlas.build(pairId, parts)
    registry[pairId] = { ts = ts, behaviors = behaviors, encounterTypes = encounterTypes }
  end
  NativeTileset._pairs[pairId] = registry[pairId].ts
  applyTables(pairId)
  return registry[pairId].ts
end

-- Behaviour per merged metatile id of a registered pair.
function Atlas.behaviorsOf(pairId)
  return registry[pairId] and registry[pairId].behaviors or {}
end

function Atlas.unregister(pairId)
  if not registry[pairId] then return end
  NativeTileset._pairs[pairId] = nil
  if type(Interaction.behaviors) == "table" then Interaction.behaviors[pairId] = nil end
  if type(Encounters._encounterTypes) == "table" then Encounters._encounterTypes[pairId] = nil end
  registry[pairId] = nil
end

function Atlas.install()
  if originals then return end
  originals = {
    get = NativeTileset.get, ready = NativeTileset.ready, prefetch = NativeTileset.prefetch,
    interactionInstall = Interaction.install,
    installEncounterTypes = Encounters.installEncounterTypes,
  }
  NativeTileset.get = function(pair, ...)
    local entry = registry[pair]
    if entry then
      NativeTileset._pairs[pair] = entry.ts -- trim/install may have dropped it
      return entry.ts
    end
    return originals.get(pair, ...)
  end
  NativeTileset.ready = function(pair, ...)
    if registry[pair] then return true end
    return originals.ready(pair, ...)
  end
  NativeTileset.prefetch = function(pair, ...)
    if registry[pair] then return end -- nothing on disk to stream
    return originals.prefetch(pair, ...)
  end
  Interaction.install = function(...)
    local result = originals.interactionInstall(...)
    for pairId in pairs(registry) do applyTables(pairId) end
    return result
  end
  Encounters.installEncounterTypes = function(...)
    local result = originals.installEncounterTypes(...)
    for pairId in pairs(registry) do applyTables(pairId) end
    return result
  end
end

function Atlas.uninstall()
  for pairId in pairs(registry) do Atlas.unregister(pairId) end
  if not originals then return end
  NativeTileset.get, NativeTileset.ready, NativeTileset.prefetch =
    originals.get, originals.ready, originals.prefetch
  Interaction.install = originals.interactionInstall
  Encounters.installEncounterTypes = originals.installEncounterTypes
  originals = nil
end

return Atlas
