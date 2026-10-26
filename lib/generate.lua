-- Generated areas: a semantic layout painted with tiles from both games.
-- For an environment, one tileset pair per imported game is chosen; tiles,
-- classes and side-by-side rules come from every real map using those pairs;
-- FireRed and Emerald tiles may meet where their touching pixel edges match.

local R = ...
local LayoutNative = require("src.core.game3.layout_native")
local CollPermissions = require("src.core.CollPermissions")

local Generate = {}

Generate.MAP_PREFIX = "FR_RL_"
Generate.ATTEMPTS = 12
Generate.CROSS_THRESHOLD = 18 -- mean |RGB difference| across a touching edge
Generate.MIN_COUNT = 2 -- tiles seen fewer times are treated as noise

-- One pair per available game for `env`, drawn by how much of that
-- environment it covers.
function Generate.parts(env, rng)
  local parts = {}
  for _, version in ipairs(R.corpus.VERSIONS) do
    if R.sources.available(version) then
      local candidates = R.corpus.pairsFor(version, env)
      if #candidates > 0 then
        local weights, total = {}, 0
        for i, c in ipairs(candidates) do weights[i] = c.cells; total = total + c.cells end
        parts[#parts + 1] = { version = version, pair = candidates[rng:weighted(weights, total)].pair }
      end
    end
  end
  assert(#parts > 0, "roguelike_mode: no imported game has a " .. env .. " tileset")
  return parts
end

local function edges(px)
  local e = { {}, {}, {}, {} } -- right column, bottom row, left column, top row
  for i = 0, 15 do
    for ch = 1, 3 do
      e[1][#e[1] + 1] = px[(i * 16 + 15) * 4 + ch] or 0
      e[2][#e[2] + 1] = px[(15 * 16 + i) * 4 + ch] or 0
      e[3][#e[3] + 1] = px[(i * 16) * 4 + ch] or 0
      e[4][#e[4] + 1] = px[i * 4 + ch] or 0
    end
  end
  return e
end

local function distance(a, b)
  local sum = 0
  for i = 1, #a do sum = sum + math.abs(a[i] - b[i]) end
  return sum / #a
end

-- tiles[i] = { key, part, mid, class, weight, coll, elev }; adj[d][i] = { j... }
function Generate.tileset(parts, opts)
  opts = opts or {}
  local tiles, index = {}, {}
  for p, part in ipairs(parts) do
    local model = R.corpus.pairModel(part.version, part.pair)
    local total = 0
    for _, t in pairs(model.tiles) do if t.count >= Generate.MIN_COUNT then total = total + t.count end end
    local mids = {}
    for mid, t in pairs(model.tiles) do
      if t.count >= Generate.MIN_COUNT and t.class ~= "door" then mids[#mids + 1] = mid end
    end
    table.sort(mids)
    for _, mid in ipairs(mids) do
      local t = model.tiles[mid]
      local key = mid + (p - 1) * R.atlas.MID_STRIDE
      tiles[#tiles + 1] = { key = key, part = p, mid = mid, class = t.class,
        weight = t.count / total, coll = t.coll, elev = t.elev, behavior = t.behavior }
      index[key] = #tiles
    end
  end

  local sets = { {}, {}, {}, {} }
  for i = 1, #tiles do for d = 1, 4 do sets[d][i] = {} end end
  local function link(i, j, d) -- j may sit in direction d of i
    sets[d][i][j] = true
    sets[R.paint.OPP[d]][j][i] = true
  end
  local seen = 0
  for p, part in ipairs(parts) do
    local model = R.corpus.pairModel(part.version, part.pair)
    local offset = (p - 1) * R.atlas.MID_STRIDE
    for d, rel in ipairs({ model.right, model.down }) do
      for a, row in pairs(rel) do
        local i = index[a + offset]
        if i then
          for b in pairs(row) do
            local j = index[b + offset]
            if j then link(i, j, d); seen = seen + 1 end
          end
        end
      end
    end
  end

  local cross = 0
  if #parts > 1 and not opts.noCross then
    local px = {}
    for i, t in ipairs(tiles) do
      local part = parts[t.part]
      local pixels = R.atlas.tilePixels(R.atlas.decode(part.version, part.pair), t.mid)
      px[i] = pixels and edges(pixels)
    end
    local threshold = opts.crossThreshold or Generate.CROSS_THRESHOLD
    for i, a in ipairs(tiles) do
      for j, b in ipairs(tiles) do
        if a.part ~= b.part and a.class == b.class and px[i] and px[j] then
          for d = 1, 2 do -- right and down; link() adds the reverse
            if distance(px[i][d], px[j][R.paint.OPP[d]]) <= threshold then
              link(i, j, d)
              cross = cross + 1
            end
          end
        end
      end
    end
  end

  local adj = { {}, {}, {}, {} }
  for d = 1, 4 do
    for i = 1, #tiles do
      local list = {}
      for j in pairs(sets[d][i]) do list[#list + 1] = j end
      table.sort(list)
      adj[d][i] = list
    end
  end
  return tiles, adj, { learned = seen, cross = cross }
end

-- Merged pairs are named after their parts, so areas drawn from the same
-- sources share one atlas and a different draw never reuses a stale one.
function Generate.pairId(parts)
  local names = {}
  for i, part in ipairs(parts) do names[i] = part.version:sub(1, 2) .. "_" .. part.pair end
  return R.atlas.PREFIX .. table.concat(names, "__")
end

local DELTA = { { 1, 0, "right" }, { -1, 0, "left" }, { 0, 1, "down" }, { 0, -1, "up" } }

-- Cells reachable on foot from (x, y): walkable collision codes, plus hops
-- over ledges in the direction their behaviour faces. `behaviors` maps a
-- cell's metatile to its behaviour (the merged pair's table).
function Generate.reachable(cells, w, h, x, y, behaviors)
  local function cell(cx, cy)
    if cx < 0 or cy < 0 or cx >= w or cy >= h then return nil end
    return cells[cy * w + cx + 1]
  end
  local function walkable(c) return c and CollPermissions.isWalkable(c.coll) end
  local seen, queue, head = { [y * w + x] = true }, { { x, y } }, 1
  while head <= #queue do
    local cx, cy = queue[head][1], queue[head][2]
    head = head + 1
    for _, d in ipairs(DELTA) do
      local tx, ty = cx + d[1], cy + d[2]
      local c = cell(tx, ty)
      if c then
        local facing = R.corpus.LEDGE_FACING[behaviors[c.mid]]
        if facing or CollPermissions.isLedge(c.coll) then
          if facing == d[3] then tx, ty = tx + d[1], ty + d[2] else tx = nil end
          if tx and not walkable(cell(tx, ty)) then tx = nil end
        elseif not walkable(c) then
          tx = nil
        end
        if tx and not seen[ty * w + tx] then
          seen[ty * w + tx] = true
          queue[#queue + 1] = { tx, ty }
        end
      end
    end
  end
  return seen
end

local function spotsReachable(layout, cells, behaviors)
  local w, h = layout.width, layout.height
  local seen = Generate.reachable(cells, w, h, layout.entry.x, layout.entry.y, behaviors)
  local function ok(p) return seen[p.y * w + p.x] end
  if not ok(layout.exit) then return false, "exit unreachable" end
  if not ok(layout.boss) then return false, "boss spot unreachable" end
  for _, t in ipairs(layout.trainers) do
    if not ok(t) then return false, "trainer spot unreachable" end
  end
  return true
end

-- A complete generated area. Returns def, report; raises when every attempt failed.
function Generate.area(id, env, seed, opts)
  opts = opts or {}
  assert(id:sub(1, #Generate.MAP_PREFIX) == Generate.MAP_PREFIX, "generated ids start with " .. Generate.MAP_PREFIX)
  local rng = R.rng.new(seed)
  local parts = opts.parts or Generate.parts(env, rng)
  local tiles, adj, stats = Generate.tileset(parts, opts)
  local reasons = {}
  for attempt = 1, opts.attempts or Generate.ATTEMPTS do
    local layout = R.layout.outdoor(rng:fork(), opts.layout)
    local w, h = layout.width, layout.height
    -- Exact classes first; when the layout cannot be painted exactly, let
    -- wall cells beside open ground take transition tiles.
    local choice, why = R.paint.solve(tiles, adj, layout.grid, w, h, rng:fork())
    if not choice and not opts.hardClasses then
      choice, why = R.paint.solve(tiles, adj, R.paint.softClasses(layout.grid, w, h), w, h, rng:fork())
    end
    if choice then
      local cells, fromPart, behaviors = {}, {}, {}
      for c = 1, w * h do
        local t = tiles[choice[c]]
        cells[c] = { mid = t.key, coll = t.coll, elev = t.elev }
        behaviors[t.key] = t.behavior
        fromPart[t.part] = (fromPart[t.part] or 0) + 1
      end
      local ok
      ok, why = spotsReachable(layout, cells, behaviors)
      if ok then
        local pairId = Generate.pairId(parts)
        R.atlas.register(pairId, parts)
        local border = cells[1].mid
        local decoded = { width = w, height = h, trueWidth = w, trueHeight = h,
          borderWidth = 1, borderHeight = 1, borderMids = { border }, cells = cells }
        local def = {
          id = id, name = id, width = w, height = h, pair = pairId,
          kind = "route", environment = "ROUTE", mapType = 3, warps = {}, connections = {},
          showMapName = 0, floorNum = 0, weather = 0, native = true,
          midLayout = LayoutNative.fromDecoded(decoded, id, pairId),
          roguelike = { env = env, seed = seed, layout = layout, parts = parts },
        }
        return def, { attempts = attempt, reasons = reasons, tiles = #tiles, fromPart = fromPart,
          learned = stats.learned, cross = stats.cross, parts = parts }
      end
    end
    reasons[#reasons + 1] = why
  end
  error("roguelike_mode: could not generate " .. id .. ": " .. table.concat(reasons, "; "))
end

return Generate
