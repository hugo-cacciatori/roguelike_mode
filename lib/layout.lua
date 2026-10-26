-- Semantic layouts: what each cell of a generated area must be (block, walk,
-- grass, water) plus the functional spots, before any tile is chosen. The
-- painter then picks tiles whose class matches. Layouts guarantee an
-- entry-to-exit path by construction; the generator re-checks it with the
-- engine's own walk rules after painting.

local R = ...

local Layout = {}

local function grid(w, h, fill)
  local g = { w = w, h = h }
  for i = 1, w * h do g[i] = fill end
  return g
end

local function idx(g, x, y) return y * g.w + x + 1 end
local function inside(g, x, y, margin)
  margin = margin or 0
  return x >= margin and y >= margin and x < g.w - margin and y < g.h - margin
end
local function set(g, x, y, v, margin)
  if inside(g, x, y, margin) then g[idx(g, x, y)] = v end
end
local function get(g, x, y) return inside(g, x, y) and g[idx(g, x, y)] or nil end

-- Corridor from a to b (1 coarse cell = 2 metatiles wide): vertical leg,
-- then horizontal leg.
local function corridor(g, ax, ay, bx, by, cells)
  local function carve(x, y)
    if inside(g, x, y, 1) or ((y == 0 or y == g.h - 1) and inside(g, x, y)) then
      g[idx(g, x, y)] = "walk"
      cells[#cells + 1] = { x, y }
    end
  end
  local step = by >= ay and 1 or -1
  for y = ay, by, step do carve(ax, y) end
  step = bx >= ax and 1 or -1
  for x = ax, bx, step do carve(x, by) end
end

local function blob(g, cx, cy, rw, rh, value, rng)
  for y = cy - rh, cy + rh do
    for x = cx - rw, cx + rw do
      local nx, ny = (x - cx) / (rw + 0.5), (y - cy) / (rh + 0.5)
      if nx * nx + ny * ny <= 1 + rng:next() * 0.3 then set(g, x, y, value, 1) end
    end
  end
end

-- Straight 3+ cell runs of main path where a trainer can stand looking along it.
local function trainerSpots(g, path, rng, count)
  local candidates = {}
  for _, c in ipairs(path) do
    local x, y = c[1], c[2]
    local horizontal = get(g, x - 1, y) == "walk" and get(g, x + 1, y) == "walk" and get(g, x + 2, y) == "walk"
    local vertical = get(g, x, y - 1) == "walk" and get(g, x, y + 1) == "walk" and get(g, x, y + 2) == "walk"
    if horizontal or vertical then
      candidates[#candidates + 1] = { x = x, y = y, facing = vertical and "down" or "right" }
    end
  end
  local spots, used = {}, {}
  for _ = 1, count * 4 do
    if #spots >= count or #candidates == 0 then break end
    local c = rng:pick(candidates)
    local key = math.floor(c.y / 3) * 1000 + math.floor(c.x / 3)
    if not used[key] then used[key] = true; spots[#spots + 1] = c end
  end
  return spots
end

-- Double a coarse layout so every region is at least 2 metatiles wide (Gen 3
-- trees and most structures are 2x2), scaling its spots with it.
local function upscale(coarse)
  local w, h = coarse.width * 2, coarse.height * 2
  local g = grid(w, h, "block")
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      g[y * w + x + 1] = coarse.grid[math.floor(y / 2) * coarse.width + math.floor(x / 2) + 1]
    end
  end
  local function scale(p)
    if not p then return nil end
    local q = {}
    for k, v in pairs(p) do q[k] = v end
    q.x, q.y = p.x * 2, p.y * 2
    if q.rw then q.rw, q.rh = p.rw * 2 + 1, p.rh * 2 + 1 end
    return q
  end
  local out = { grid = g, width = w, height = h, entry = scale(coarse.entry), boss = scale(coarse.boss),
    gate = scale(coarse.gate), trainers = {}, zones = {} }
  out.exit = scale(coarse.exit)
  out.exit.y = h - 1
  for i, t in ipairs(coarse.trainers) do out.trainers[i] = scale(t) end
  for i, z in ipairs(coarse.zones) do out.zones[i] = scale(z) end
  return out
end

-- Forest-like outdoor area: block mass, winding path, clearings, grass. Built
-- on a half-resolution grid, then doubled.
function Layout.outdoor(rng, opts)
  opts = opts or {}
  local coarse = Layout.outdoorCoarse(rng, {
    width = math.floor((opts.width or 36) / 2), height = math.floor((opts.height or 44) / 2),
    legs = opts.legs, branches = opts.branches, grassZones = opts.grassZones,
    trainers = opts.trainers, hmGate = opts.hmGate, coarse = true,
  })
  return upscale(coarse)
end

function Layout.outdoorCoarse(rng, opts)
  local w, h = opts.width, opts.height
  local g = grid(w, h, "block")
  local path = {}

  local entry = { x = rng:int(2, w - 3), y = 0 }
  local exit = { x = rng:int(2, w - 3), y = h - 1 }
  local points = { { entry.x, 0 } }
  local legs = opts.legs or rng:int(3, 5)
  for i = 1, legs do
    points[#points + 1] = { rng:int(2, w - 3), math.floor(i * (h - 2) / (legs + 1)) }
  end
  points[#points + 1] = { exit.x, h - 1 }
  for i = 1, #points - 1 do
    corridor(g, points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], path)
  end

  -- Clearings at some waypoints, so the map is not a single corridor.
  for i = 2, #points - 1 do
    if rng:chance(0.6) then
      blob(g, points[i][1], points[i][2], rng:int(1, 2), rng:int(1, 2), "walk", rng)
    end
  end

  -- Side branches; the deepest dead end becomes the boss clearing.
  local boss, bestDist = nil, -1
  for _ = 1, opts.branches or rng:int(2, 3) do
    local from = rng:pick(path)
    local tx = from[1] < w / 2 and rng:int(math.floor(w * 0.65), w - 3) or rng:int(2, math.floor(w * 0.35))
    local ty = math.max(2, math.min(h - 3, from[2] + rng:int(-3, 3)))
    corridor(g, from[1], from[2], tx, ty, {})
    blob(g, tx, ty, 1, 1, "walk", rng)
    local d = math.abs(tx - entry.x) + math.abs(ty - entry.y)
    if d > bestDist then bestDist, boss = d, { x = tx, y = ty } end
  end

  -- Grass zones hug walkable ground but never cover the boss clearing.
  local zones = {}
  for _ = 1, opts.grassZones or rng:int(4, 6) do
    local c = rng:pick(path)
    local zx, zy = c[1] + rng:int(-2, 2), c[2] + rng:int(-1, 1)
    if math.abs(zx - boss.x) + math.abs(zy - boss.y) > 3 then
      local rw, rh = rng:int(1, 2), rng:int(0, 1)
      for y = zy - rh, zy + rh do
        for x = zx - rw, zx + rw do
          if inside(g, x, y, 1) then g[idx(g, x, y)] = "grass" end
        end
      end
      zones[#zones + 1] = { x = zx, y = zy, rw = rw, rh = rh }
    end
  end
  -- The boss clearing and the openings stay plain ground.
  set(g, boss.x, boss.y, "walk", 1)
  for _, p in ipairs({ entry, exit }) do
    for dy = -1, 1 do
      if inside(g, p.x, p.y + dy) then g[idx(g, p.x, p.y + dy)] = "walk" end
    end
  end

  -- Optional HM gate: a narrow stretch of the main path (object placed later).
  local gate
  if opts.hmGate then
    for _ = 1, 30 do
      local c = rng:pick(path)
      if c[2] > 2 and c[2] < h - 3 then gate = { x = c[1], y = c[2], hm = opts.hmGate }; break end
    end
  end

  return {
    grid = g, width = w, height = h, entry = entry, exit = exit, boss = boss,
    trainers = trainerSpots(g, path, rng, opts.trainers or 3), zones = zones, gate = gate,
  }
end

-- Space kept around a town building for roof tops and side transitions.
Layout.TOWN_MARGIN = { up = 3, side = 2 }

-- Town: a tree ring with an exit at the bottom edge, open ground inside, and
-- building footprints placed with room in front of every door. `buildings`
-- is a list of { w, h, doorDX }; placements come back in the same order.
-- Footprint cells are marked "stamp" (the painter fixes their tiles).
function Layout.town(rng, opts)
  local w, h = opts.width or 40, opts.height or 34
  local g = grid(w, h, "walk")
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if x < 2 or y < 2 or x >= w - 2 or y >= h - 2 then g[idx(g, x, y)] = "block" end
    end
  end
  local exit = { x = rng:int(4, w - 6), y = h - 1 }
  for dy = 0, 1 do
    for dx = 0, 1 do g[idx(g, exit.x + dx, h - 1 - dy)] = "walk" end
  end

  local m = Layout.TOWN_MARGIN
  local taken = {}
  local function free(x0, y0, bw, bh)
    -- the footprint, room for roof and side transitions, 2 rows in front of the door
    for y = y0 - m.up, y0 + bh + 2 do
      for x = x0 - m.side, x0 + bw - 1 + m.side do
        if x < 0 or y < 0 or x >= w or y >= h - 3 or taken[y * w + x] then return false end
      end
    end
    return true
  end
  local placed = {}
  for i, b in ipairs(opts.buildings) do
    for _ = 1, 200 do
      local x0, y0 = rng:int(2 + m.side, w - 2 - m.side - b.w), rng:int(2 + m.up, h - 6 - b.h)
      if free(x0, y0, b.w, b.h) then
        for y = y0 - m.up, y0 + b.h + 2 do
          for x = x0 - m.side, x0 + b.w - 1 + m.side do taken[y * w + x] = true end
        end
        for y = y0, y0 + b.h - 1 do
          for x = x0, x0 + b.w - 1 do g[idx(g, x, y)] = "stamp" end
        end
        placed[i] = { x = x0, y = y0, door = { x = x0 + b.doorDX, y = y0 + b.h - 1 } }
        break
      end
    end
    if not placed[i] then return nil, "no room for building " .. i end
  end

  -- Start: open ground in front of the first building (the Pokémon Center).
  local d = placed[1].door
  return { grid = g, width = w, height = h, exit = exit, start = { x = d.x, y = d.y + 2 },
    buildings = placed }
end

-- Interior: walls along the top (2 rows) and sides, floor, an exit mat on the
-- bottom wall, and an aisle from the mat to the room's functional spot.
function Layout.interior(rng, w, h)
  local g = grid(w, h, "walk")
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if y < 2 or x == 0 or x == w - 1 or y == h - 1 then g[idx(g, x, y)] = "block" end
    end
  end
  local exit = { x = rng:int(2, w - 3), y = h - 1 }
  g[idx(g, exit.x, exit.y)] = "door"
  local spot = { x = math.floor(w / 2), y = 2 }
  local aisle = {}
  for y = spot.y, h - 2 do aisle[#aisle + 1] = { x = exit.x, y = y } end
  local step = spot.x >= exit.x and 1 or -1
  for x = exit.x, spot.x, step do aisle[#aisle + 1] = { x = x, y = spot.y + 1 } end
  return { grid = g, width = w, height = h, exit = exit, spot = spot, aisle = aisle }
end

return Layout
