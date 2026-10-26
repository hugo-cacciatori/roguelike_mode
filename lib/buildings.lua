-- Building stamps learned from both games' towns (spec §9.F, fallback row 1:
-- generating buildings tile by tile failed -- single-tile neighbour rules
-- cannot assemble roofs, walls and doors). A building is placed whole, like
-- a 2x2 tree; the painter generates everything around it. Every door tile
-- with a warp anchors one; its kind comes from where the warp leads.

local R = ...
local Collision = require("src.core.game3.collision")

local Buildings = {}

Buildings.KINDS = { center = true, mart = true, lab = true, house = true }
Buildings.MAX_W, Buildings.MAX_H, Buildings.MIN_W, Buildings.MIN_H = 8, 6, 3, 3
Buildings.MAX_HOUSE_W = 6 -- wider "houses" are department stores, condos and halls
Buildings.SHARE = 0.5 -- a tile is a building tile when at least this share of it sits in door rectangles
Buildings.FILL = 0.8 -- a stamp must be at least this much building tiles

local KIND_NAMES = { { "POKEMON_CENTER", "center" }, { "MART", "mart" }, { "LAB", "lab" }, { "GYM", "gym" } }

function Buildings.kindOf(destMap)
  local id = tostring(destMap or ""):upper()
  for _, k in ipairs(KIND_NAMES) do
    if id:find(k[1], 1, true) then return k[2] end
  end
  return "house"
end

local memo

-- Raw rectangle above a door: the door row spread left/right over walls,
-- then rows upward while the door column stays wall.
local function rawRect(map, behaviors, x, y)
  local d = map.decoded
  local function wall(cx, cy)
    if cx < 0 or cy < 0 or cx >= d.width or cy >= d.height then return false end
    local c = d.cells[cy * d.width + cx + 1]
    return R.corpus.classOf(c.coll, behaviors[c.mid]) == "block"
  end
  local x0, x1, y0 = x, x, y
  while wall(x0 - 1, y) and x - x0 < 6 do x0 = x0 - 1 end
  while wall(x1 + 1, y) and x1 - x < 6 do x1 = x1 + 1 end
  while wall(x, y0 - 1) and y - y0 < 7 do y0 = y0 - 1 end
  return { x0 = x0, x1 = x1, y0 = y0, y1 = y }
end

local function candidates()
  local list = {}
  for _, version in ipairs(R.corpus.VERSIONS) do
    if R.sources.available(version) then
      local warps = R.sources.loadLua(version, "warps.lua") or {}
      for _, map in ipairs(R.corpus.maps(version)) do
        if map.env == "town" or map.env == "route" then
          local d, behaviors = map.decoded, R.catalog.behaviors(version, map.pair)
          for _, w in ipairs(warps[map.id] or {}) do
            local x, y = tonumber(w.x), tonumber(w.y)
            if x and y and y > 0 and x < d.width and y < d.height then
              local doorMid = d.cells[y * d.width + x + 1].mid
              if Collision.isWarpDoor(behaviors[doorMid]) then
                list[#list + 1] = { version = version, map = map, x = x, y = y, doorMid = doorMid,
                  kind = Buildings.kindOf(w.destMap), rect = rawRect(map, behaviors, x, y) }
              end
            end
          end
        end
      end
    end
  end
  return list
end

-- Learned stamps: { version, pair, kind, w, h, doorDX, mids[row][col], source }.
function Buildings.stamps()
  if memo then return memo end
  local list = candidates()

  -- Which tiles are building tiles (per version|pair|mid).
  local inside, total = {}, {}
  for _, c in ipairs(list) do
    local d = c.map.decoded
    for y = c.rect.y0, c.rect.y1 do
      for x = c.rect.x0, c.rect.x1 do
        local key = c.version .. "|" .. c.map.pair .. "|" .. d.cells[y * d.width + x + 1].mid
        inside[key] = (inside[key] or 0) + 1
      end
    end
  end
  local function isBuilding(c, x, y)
    local mid = c.map.decoded.cells[y * c.map.decoded.width + x + 1].mid
    local key = c.version .. "|" .. c.map.pair .. "|" .. mid
    if total[key] == nil then
      local t = R.corpus.pairModel(c.version, c.map.pair).tiles[mid]
      total[key] = t and t.count or inside[key] or 1
    end
    return (inside[key] or 0) / total[key] >= Buildings.SHARE
  end

  local stamps, seen = {}, {}
  for _, c in ipairs(list) do
    if Buildings.KINDS[c.kind] then
      local r = { x0 = c.rect.x0, x1 = c.rect.x1, y0 = c.rect.y0, y1 = c.rect.y1 }
      local function colShare(x)
        local n = 0
        for y = r.y0, r.y1 do if isBuilding(c, x, y) then n = n + 1 end end
        return n / (r.y1 - r.y0 + 1)
      end
      local function rowShare(y)
        local n = 0
        for x = r.x0, r.x1 do if isBuilding(c, x, y) then n = n + 1 end end
        return n / (r.x1 - r.x0 + 1)
      end
      while r.x0 < c.x and colShare(r.x0) < Buildings.SHARE do r.x0 = r.x0 + 1 end
      while r.x1 > c.x and colShare(r.x1) < Buildings.SHARE do r.x1 = r.x1 - 1 end
      while r.y0 < c.y and rowShare(r.y0) < Buildings.SHARE do r.y0 = r.y0 + 1 end
      local w, h = r.x1 - r.x0 + 1, r.y1 - r.y0 + 1
      local d = c.map.decoded
      local mids, built, keyParts = {}, 0, {}
      for y = r.y0, r.y1 do
        local row = {}
        for x = r.x0, r.x1 do
          local mid = d.cells[y * d.width + x + 1].mid
          row[#row + 1] = mid
          keyParts[#keyParts + 1] = mid
          if isBuilding(c, x, y) or (x == c.x and y == c.y) then built = built + 1 end
        end
        mids[#mids + 1] = row
      end
      -- one building per stamp: a second door means neighbours were merged in
      local behaviors, doors = R.catalog.behaviors(c.version, c.map.pair), 0
      for _, row in ipairs(mids) do
        for _, mid in ipairs(row) do
          if Collision.isWarpDoor(behaviors[mid]) then doors = doors + 1 end
        end
      end
      local maxW = c.kind == "house" and Buildings.MAX_HOUSE_W or Buildings.MAX_W
      local key = c.version .. "|" .. c.map.pair .. "|" .. w .. "x" .. h .. "|" .. table.concat(keyParts, ",")
      if w >= Buildings.MIN_W and w <= maxW and h >= Buildings.MIN_H and h <= Buildings.MAX_H
          and doors == 1 and built / (w * h) >= Buildings.FILL and not seen[key] then
        seen[key] = true
        stamps[#stamps + 1] = { version = c.version, pair = c.map.pair, kind = c.kind, w = w, h = h,
          doorDX = c.x - r.x0, mids = mids, source = c.map.id }
      end
    end
  end
  table.sort(stamps, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    if a.version ~= b.version then return a.version < b.version end
    return a.source .. a.doorDX < b.source .. b.doorDX
  end)
  memo = stamps
  return stamps
end

-- Stamps of a kind at that kind's most common size in each game: the
-- recognisable standard building, without leftovers of merged neighbours.
function Buildings.typical(kind)
  local bySize = {}
  for _, s in ipairs(Buildings.stamps()) do
    if s.kind == kind then
      local key = s.version .. "|" .. s.w .. "x" .. s.h
      bySize[key] = bySize[key] or { version = s.version, list = {} }
      table.insert(bySize[key].list, s)
    end
  end
  local best = {}
  for key, group in pairs(bySize) do
    local cur = best[group.version]
    if not cur or #group.list > #cur.list or (#group.list == #cur.list and key < cur.key) then
      best[group.version] = { key = key, list = group.list }
    end
  end
  local out = {}
  for _, version in ipairs(R.corpus.VERSIONS) do
    for _, s in ipairs(best[version] and best[version].list or {}) do out[#out + 1] = s end
  end
  return out
end

function Buildings.ofKind(kind)
  local out = {}
  for _, s in ipairs(Buildings.stamps()) do if s.kind == kind then out[#out + 1] = s end end
  return out
end

return Buildings
