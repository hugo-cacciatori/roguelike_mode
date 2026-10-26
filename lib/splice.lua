-- Composite maps: rectangles cut from source layouts, pasted onto one grid
-- that binds a merged pair. Map ids carry the FR_ prefix because FireRed's
-- MapIds.isGame3Map only accepts the active profile's prefixes; anything else
-- would be refused by Map.load and would hide Continue.

local R = ...
local LayoutNative = require("src.core.game3.layout_native")

local Splice = {}

Splice.MAP_PREFIX = "FR_RL_"
local FILL = { coll = 1, elev = 0 } -- impassable filler around chunks

local registered = {} -- [mapId] = { game = game, def = def }

-- Pure assembly, no imports: `sources[i]` is a decoded layout, `offsets[i]`
-- the mid offset for part i, `fillMid` the (offset) metatile behind chunks.
-- Returns the cell array (1-based, row-major).
function Splice.cells(spec, sources, offsets, fillMid)
  local w, h = spec.width, spec.height
  local cells = {}
  for i = 1, w * h do cells[i] = { mid = fillMid, coll = FILL.coll, elev = FILL.elev } end
  for _, chunk in ipairs(spec.chunks) do
    local src, off = sources[chunk.part], offsets[chunk.part]
    local r = chunk.src
    assert(r.x >= 0 and r.y >= 0 and r.x + r.w <= src.width and r.y + r.h <= src.height,
      ("roguelike_mode: chunk outside part %d of %s"):format(chunk.part, spec.id))
    assert(chunk.at.x >= 0 and chunk.at.y >= 0 and chunk.at.x + r.w <= w and chunk.at.y + r.h <= h,
      "roguelike_mode: chunk outside composite " .. spec.id)
    for dy = 0, r.h - 1 do
      for dx = 0, r.w - 1 do
        local s = src.cells[(r.y + dy) * src.width + (r.x + dx) + 1]
        cells[(chunk.at.y + dy) * w + (chunk.at.x + dx) + 1] =
          { mid = s.mid + off, coll = s.coll, elev = s.elev }
      end
    end
  end
  return cells
end

function Splice.pairId(spec)
  return R.atlas.PREFIX .. spec.id:sub(#Splice.MAP_PREFIX + 1):lower()
end

-- Map definition for one composite spec (registers its merged pair).
function Splice.build(spec)
  assert(spec.id:sub(1, #Splice.MAP_PREFIX) == Splice.MAP_PREFIX,
    "roguelike_mode: composite ids start with " .. Splice.MAP_PREFIX)
  local sources, offsets, parts = {}, {}, {}
  for i, part in ipairs(spec.parts) do
    local decoded, pair = R.catalog.layout(part.version, part.map)
    sources[i], offsets[i] = decoded, (i - 1) * R.atlas.MID_STRIDE
    parts[i] = { version = part.version, pair = pair }
  end
  local pairId = Splice.pairId(spec)
  R.atlas.register(pairId, parts)

  local borderPart = spec.border or 1
  local border = sources[borderPart]
  local borderMids = {}
  for i, mid in ipairs(border.borderMids or { 0 }) do
    borderMids[i] = mid + offsets[borderPart]
  end
  local decoded = {
    width = spec.width, height = spec.height, trueWidth = spec.width, trueHeight = spec.height,
    borderWidth = border.borderWidth or 1, borderHeight = border.borderHeight or 1,
    borderMids = borderMids, cells = Splice.cells(spec, sources, offsets, borderMids[1]),
  }
  return {
    id = spec.id, name = spec.id, width = spec.width, height = spec.height, pair = pairId,
    kind = spec.kind or "route", environment = spec.environment or "ROUTE",
    mapType = spec.mapType or 3, warps = {}, connections = {},
    regionMapSectionId = spec.regionMapSectionId, showMapName = 0, floorNum = 0,
    weather = 0, music = spec.music, native = true,
    midLayout = LayoutNative.fromDecoded(decoded, spec.id, pairId),
    roguelike = { spec = spec },
  }
end

function Splice.register(game, spec)
  local entry = registered[spec.id]
  if not entry or entry.game ~= game then
    entry = { game = game, def = entry and entry.def or Splice.build(spec) }
    registered[spec.id] = entry
  end
  game.data.maps[spec.id] = entry.def
  return entry.def
end

function Splice.registerAll(game)
  for _, spec in ipairs(R.data.chunks.composites) do Splice.register(game, spec) end
end

function Splice.unregisterAll()
  for id, entry in pairs(registered) do
    local maps = entry.game and entry.game.data and entry.game.data.maps
    if maps and maps[id] == entry.def then maps[id] = nil end
  end
  registered = {}
end

return Splice
