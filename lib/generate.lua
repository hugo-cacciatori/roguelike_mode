-- Generated areas: a semantic layout painted with tiles from both games.
-- For an environment, one tileset pair per imported game is chosen; tiles,
-- classes and side-by-side rules come from every real map using those pairs;
-- FireRed and Emerald tiles may meet where their touching pixel edges match.

local R = ...
local LayoutNative = require("src.core.game3.layout_native")
local CollPermissions = require("src.core.CollPermissions")
local Collision = require("src.core.game3.collision")

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
      if env:sub(1, 9) == "interior_" then
        -- rooms come from building tilesets (not facilities or caves reused indoors)
        local rooms = {}
        for _, c in ipairs(candidates) do if c.pair:sub(1, 10) == "building__" then rooms[#rooms + 1] = c end end
        if #rooms > 0 then candidates = rooms end
      end
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
    local minCount = opts.minCount or Generate.MIN_COUNT
    for _, t in pairs(model.tiles) do if t.count >= minCount then total = total + t.count end end
    local mids = {}
    for mid, t in pairs(model.tiles) do
      if (t.count >= minCount or opts.keep and opts.keep(p, mid)) and (t.class ~= "door" or opts.includeDoors) then mids[#mids + 1] = mid end
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

local function materialize(tiles, choice, w, h)
  local cells, fromPart, behaviors = {}, {}, {}
  for c = 1, w * h do
    local t = tiles[choice[c]]
    cells[c] = { mid = t.key, coll = t.coll, elev = t.elev }
    behaviors[t.key] = t.behavior
    fromPart[t.part] = (fromPart[t.part] or 0) + 1
  end
  return cells, behaviors, fromPart
end

-- Map kinds as the engine knows them (pokeemerald/include/constants/map_types.h).
local MAP_KIND = {
  route = { kind = "route", environment = "ROUTE", mapType = 3 },
  town = { kind = "town", environment = "TOWN", mapType = 1 },
  indoor = { kind = "indoor", environment = "INDOOR", mapType = 8 },
}

local function makeDef(id, parts, cells, w, h, mapKind, meta)
  local pairId = Generate.pairId(parts)
  R.atlas.register(pairId, parts)
  local decoded = { width = w, height = h, trueWidth = w, trueHeight = h,
    borderWidth = 1, borderHeight = 1, borderMids = { cells[1].mid }, cells = cells }
  local k = MAP_KIND[mapKind]
  return {
    id = id, name = id, width = w, height = h, pair = pairId,
    kind = k.kind, environment = k.environment, mapType = k.mapType, warps = {}, connections = {},
    showMapName = 0, floorNum = 0, weather = 0, native = true,
    midLayout = LayoutNative.fromDecoded(decoded, id, pairId),
    roguelike = meta,
  }
end

local function checkId(id)
  assert(id:sub(1, #Generate.MAP_PREFIX) == Generate.MAP_PREFIX, "generated ids start with " .. Generate.MAP_PREFIX)
end

-- Paint `classes`, exact first, then with `soft` classes when given.
local function paint(tiles, adj, classes, soft, w, h, rng)
  local choice, why = R.paint.solve(tiles, adj, classes, w, h, rng:fork())
  if not choice and soft then choice, why = R.paint.solve(tiles, adj, soft, w, h, rng:fork()) end
  return choice, why
end

-- A complete generated outdoor area. Returns def, report; raises when every attempt failed.
function Generate.area(id, env, seed, opts)
  opts = opts or {}
  checkId(id)
  local rng = R.rng.new(seed)
  local parts = opts.parts or Generate.parts(env, rng)
  local tiles, adj, stats = Generate.tileset(parts, opts)
  local reasons = {}
  for attempt = 1, opts.attempts or Generate.ATTEMPTS do
    local layout = R.layout.outdoor(rng:fork(), opts.layout)
    local w, h = layout.width, layout.height
    -- Exact classes first; when the layout cannot be painted exactly, let
    -- wall cells beside open ground take transition tiles.
    local choice, why = paint(tiles, adj, layout.grid,
      not opts.hardClasses and R.paint.softClasses(layout.grid, w, h), w, h, rng)
    if choice then
      local cells, behaviors, fromPart = materialize(tiles, choice, w, h)
      local ok
      ok, why = spotsReachable(layout, cells, behaviors)
      if ok then
        local def = makeDef(id, parts, cells, w, h, "route", { env = env, seed = seed, layout = layout, parts = parts })
        return def, { attempts = attempt, reasons = reasons, tiles = #tiles, fromPart = fromPart,
          learned = stats.learned, cross = stats.cross, parts = parts }
      end
    end
    reasons[#reasons + 1] = why
  end
  error("roguelike_mode: could not generate " .. id .. ": " .. table.concat(reasons, "; "))
end

local function indexOf(tiles)
  local index = {}
  for i, t in ipairs(tiles) do index[t.key] = i end
  return index
end

-- Parts for a set of stamps: one per distinct source pair, FireRed first so
-- FireRed door tiles keep their own metatile ids (FRLG door animations are
-- looked up by id).
local function stampParts(stamps)
  local seen, parts = {}, {}
  for _, s in ipairs(stamps) do
    local key = s.version .. "|" .. s.pair
    if not seen[key] then seen[key] = true; parts[#parts + 1] = { version = s.version, pair = s.pair } end
  end
  table.sort(parts, function(a, b)
    if a.version ~= b.version then return a.version == "firered" end
    return a.pair < b.pair
  end)
  return parts
end

local function partOf(parts, stamp)
  for i, p in ipairs(parts) do
    if p.version == stamp.version and p.pair == stamp.pair then return i end
  end
end

Generate.TOWN_BUILDINGS = { "center", "mart", "lab", "house", "house" }
Generate.FOREIGN_GROUND = 0.05 -- weight of ground tiles from tilesets other than the town's base

-- A town: generated ground and trees around learned building stamps.
-- def.roguelike.layout.buildings[i] = { x, y, door, kind }.
function Generate.town(id, seed, opts)
  opts = opts or {}
  checkId(id)
  local rng = R.rng.new(seed)
  -- Few source tilesets per town: after the first building, prefer stamps
  -- from tilesets already in use (coherent ground, smaller tile sets).
  local stamps, used = {}, {}
  for _, kind in ipairs(opts.buildings or Generate.TOWN_BUILDINGS) do
    local list = R.buildings.typical(kind)
    local same = {}
    for _, st in ipairs(list) do if used[st.version .. "|" .. st.pair] then same[#same + 1] = st end end
    local pick = #same > 0 and rng:pick(same) or (#list > 0 and rng:pick(list)) or nil
    if pick then
      stamps[#stamps + 1] = pick
      used[pick.version .. "|" .. pick.pair] = true
    end
  end
  assert(#stamps > 0, "roguelike_mode: no building stamps learned")
  local parts = stampParts(stamps)
  local keep = {}
  for _, s in ipairs(stamps) do
    local p = partOf(parts, s)
    keep[p] = keep[p] or {}
    for _, row in ipairs(s.mids) do for _, mid in ipairs(row) do keep[p][mid] = true end end
  end
  -- Buildings stand in few places, so what surrounds them is rare: keep
  -- every observed tile (rare ones still carry tiny weights).
  local tiles, adj, stats = Generate.tileset(parts, { includeDoors = true, minCount = 1,
    keep = function(p, mid) return keep[p] and keep[p][mid] end })
  local index = indexOf(tiles)

  -- Roof and wall tiles of buildings belong to buildings: a separate class
  -- keeps them out of free ground and tree cells (stamp cells name tiles directly).
  for _, s in ipairs(stamps) do
    local off = (partOf(parts, s) - 1) * R.atlas.MID_STRIDE
    for _, row in ipairs(s.mids) do
      for _, mid in ipairs(row) do
        local t = tiles[index[mid + off]]
        if t and t.class == "block" then t.class = "building" end
      end
    end
  end

  -- The first building's (the Pokémon Center's) tileset sets the ground style.
  local basePart = partOf(parts, stamps[1])
  for _, t in ipairs(tiles) do
    if t.part ~= basePart and (t.class == "walk" or t.class == "grass") then t.weight = t.weight * Generate.FOREIGN_GROUND end
  end

  -- A building stands on ground: each outer edge tile of a stamp may touch
  -- any ground tile on its outer side (its few real neighbours are too rare
  -- to paint a whole town around).
  local ground = {}
  for i, t in ipairs(tiles) do if t.class == "walk" then ground[#ground + 1] = i end end
  local function allow(i, d)
    local have = {}
    for _, j in ipairs(adj[d][i]) do have[j] = true end
    for _, j in ipairs(ground) do
      if not have[j] then
        adj[d][i][#adj[d][i] + 1] = j
        local back = adj[R.paint.OPP[d]][j]
        back[#back + 1] = i
      end
    end
  end
  for _, s in ipairs(stamps) do
    local off = (partOf(parts, s) - 1) * R.atlas.MID_STRIDE
    for dx = 1, s.w do
      allow(index[s.mids[1][dx] + off], 4)        -- roof row: up
      allow(index[s.mids[s.h][dx] + off], 2)      -- door row: down
    end
    for dy = 1, s.h do
      allow(index[s.mids[dy][1] + off], 3)        -- left column: left
      allow(index[s.mids[dy][s.w] + off], 1)      -- right column: right
    end
  end

  local reasons = {}
  for attempt = 1, opts.attempts or Generate.ATTEMPTS do
    local layout, why = R.layout.town(rng:fork(), { buildings = stamps })
    if layout then
      local w, h = layout.width, layout.height
      local classes = {}
      for c = 1, w * h do classes[c] = layout.grid[c] end
      for i, s in ipairs(stamps) do
        local b, off = layout.buildings[i], (partOf(parts, s) - 1) * R.atlas.MID_STRIDE
        b.kind = s.kind
        for dy = 0, s.h - 1 do
          for dx = 0, s.w - 1 do
            classes[(b.y + dy) * w + b.x + dx + 1] = { tiles = { index[s.mids[dy + 1][dx + 1] + off] } }
          end
        end
      end
      -- Ground beside and above buildings may take whatever the source towns
      -- put there (trees, fences, roof shadows); the 2 rows in front of every
      -- door and the cells along the tree ring stay as planned.
      local soft = {}
      for c = 1, w * h do soft[c] = classes[c] end
      for i, b in ipairs(layout.buildings) do
        local s = stamps[i]
        for y = b.y - R.layout.TOWN_MARGIN.up, b.y + s.h - 1 do
          for x = b.x - R.layout.TOWN_MARGIN.side, b.x + s.w - 1 + R.layout.TOWN_MARGIN.side do
            local c = y * w + x + 1
            if x >= 0 and y >= 0 and x < w and y < h and layout.grid[c] == "walk" then soft[c] = { "walk", "block", "grass", "ledge" } end
          end
        end
      end
      for c = 1, w * h do
        if soft[c] == "block" then soft[c] = { "block", "walk" } end
      end
      local choice
      choice, why = paint(tiles, adj, classes, soft, w, h, rng)
      if choice then
        local cells, behaviors, fromPart = materialize(tiles, choice, w, h)
        local seen = Generate.reachable(cells, w, h, layout.start.x, layout.start.y, behaviors)
        local ok = seen[layout.exit.y * w + layout.exit.x]
        for _, b in ipairs(layout.buildings) do ok = ok and seen[(b.door.y + 1) * w + b.door.x] end
        if ok then
          local def = makeDef(id, parts, cells, w, h, "town",
            { env = "town", seed = seed, layout = layout, parts = parts, stamps = stamps })
          return def, { attempts = attempt, reasons = reasons, tiles = #tiles, fromPart = fromPart,
            cross = stats.cross, parts = parts }
        end
        why = "a door or the exit is unreachable"
      end
    end
    reasons[#reasons + 1] = why
  end
  error("roguelike_mode: could not generate town " .. id .. ": " .. table.concat(reasons, "; "))
end

-- Exit mats: door-class tiles whose behaviour is an exit (south arrow,
-- non-animated door or warp door).
local function isExitBehavior(beh)
  return beh ~= nil and (Collision.arrowWarpDir(beh) == "down" or Collision.isNonAnimDoor(beh)
    or Collision.isWarpDoor(beh))
end

-- A building interior of `kind` (center, mart, lab, house).
function Generate.interior(id, kind, seed, opts)
  opts = opts or {}
  checkId(id)
  local env = "interior_" .. kind
  local rng = R.rng.new(seed)
  local parts = opts.parts or Generate.parts(env, rng)
  -- an interior's exit mat may be unique to it: always keep exit tiles
  local tiles, adj = Generate.tileset(parts, { includeDoors = true, minCount = 1, keep = function(p, mid)
    return isExitBehavior(R.catalog.behaviors(parts[p].version, parts[p].pair)[mid])
  end })
  local exits = {}
  for i, t in ipairs(tiles) do
    if t.class == "door" and isExitBehavior(t.behavior) then exits[#exits + 1] = i end
  end
  assert(#exits > 0, "roguelike_mode: no exit mats learned for " .. env)

  -- Room proportions come from that kind's real interiors.
  local sizes = {}
  for _, version in ipairs(R.corpus.VERSIONS) do
    if R.sources.available(version) then
      for _, map in ipairs(R.corpus.maps(version)) do
        if map.env == env then sizes[#sizes + 1] = { map.decoded.trueWidth or map.decoded.width,
          map.decoded.trueHeight or map.decoded.height } end
      end
    end
  end
  table.sort(sizes, function(a, b) return a[1] * 100 + a[2] < b[1] * 100 + b[2] end)

  local reasons = {}
  for attempt = 1, opts.attempts or Generate.ATTEMPTS do
    local size = sizes[rng:int(1, #sizes)] or { 11, 8 }
    local w = math.max(8, math.min(15, size[1]))
    local h = math.max(7, math.min(11, size[2]))
    local layout = R.layout.interior(rng:fork(), w, h)
    local classes = {}
    for c = 1, w * h do classes[c] = layout.grid[c] end
    classes[layout.exit.y * w + layout.exit.x + 1] = { tiles = exits }
    local soft = R.paint.softClasses(layout.grid, w, h)
    for c = 1, w * h do
      if layout.grid[c] == "walk" then soft[c] = { "walk", "block" } end -- furniture may stand on the floor
    end
    -- Some rooms have floor beside the exit mat, and Emerald's mats are two
    -- tiles wide: the bottom row may open, and the exit's neighbours may hold
    -- the other half of a mat.
    local floorOrWall = {}
    for i, t in ipairs(tiles) do if t.class == "block" or t.class == "walk" then floorOrWall[#floorOrWall + 1] = i end end
    for x = 1, w - 2 do
      if x ~= layout.exit.x then
        local domain = { tiles = {} }
        for _, i in ipairs(floorOrWall) do domain.tiles[#domain.tiles + 1] = i end
        if math.abs(x - layout.exit.x) == 1 then
          for _, i in ipairs(exits) do domain.tiles[#domain.tiles + 1] = i end
        end
        soft[(h - 1) * w + x + 1] = domain
      end
    end
    for _, p in ipairs(layout.aisle) do soft[p.y * w + p.x + 1] = "walk" end
    soft[layout.exit.y * w + layout.exit.x + 1] = { tiles = exits }
    local choice, why = paint(tiles, adj, classes, soft, w, h, rng)
    if choice then
      local cells, behaviors = materialize(tiles, choice, w, h)
      -- the other half of a two-tile mat becomes an exit too
      layout.exitTwins = {}
      for _, dx in ipairs({ -1, 1 }) do
        local c = choice[layout.exit.y * w + layout.exit.x + dx + 1]
        if tiles[c].class == "door" then layout.exitTwins[#layout.exitTwins + 1] = { x = layout.exit.x + dx, y = layout.exit.y } end
      end
      local seen = Generate.reachable(cells, w, h, layout.exit.x, layout.exit.y - 1, behaviors)
      if seen[layout.spot.y * w + layout.spot.x] then
        return makeDef(id, parts, cells, w, h, "indoor",
          { env = env, kind = kind, seed = seed, layout = layout, parts = parts })
      end
      why = "spot unreachable from the exit"
    end
    reasons[#reasons + 1] = why
  end
  error("roguelike_mode: could not generate interior " .. id .. ": " .. table.concat(reasons, "; "))
end

return Generate
