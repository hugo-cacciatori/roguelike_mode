-- Constraint painter (wave-function-collapse, simple tiled model with AC-4
-- support counting). Each cell may only take tiles of the class its layout
-- cell demands; neighbours must have been seen side by side in real maps (or
-- be judged compatible across games); tiles are drawn by how common they are.

local Paint = {}

-- directions: 1 right (+x), 2 down (+y), 3 left, 4 up
local DX, DY = { 1, 0, -1, 0 }, { 0, 1, 0, -1 }
local OPP = { 3, 4, 1, 2 }
Paint.DIRS, Paint.OPP = { DX = DX, DY = DY }, OPP

-- tiles[i] = { class, weight }; adj[d][i] = array of j allowed in direction d.
-- classes[c] = allowed class (string) or classes (array) per cell, row-major.
-- limits.backtracks caps how many decisions may be undone.
-- Returns choice[c] = tile index, or nil, reason.
function Paint.solve(tiles, adj, classes, w, h, rng, limits)
  local N, C = #tiles, w * h
  local byClass = {}
  for i, t in ipairs(tiles) do
    byClass[t.class] = byClass[t.class] or {}
    byClass[t.class][#byClass[t.class] + 1] = i
  end
  local function domainList(allowed)
    if type(allowed) == "string" then return byClass[allowed] end
    if allowed.tiles then return #allowed.tiles > 0 and allowed.tiles or nil end -- explicit tile indices
    local list = {}
    for _, class in ipairs(allowed) do
      for _, i in ipairs(byClass[class] or {}) do list[#list + 1] = i end
    end
    return #list > 0 and list or nil
  end

  local function nb(c, d)
    local x, y = (c - 1) % w + DX[d], math.floor((c - 1) / w) + DY[d]
    if x < 0 or y < 0 or x >= w or y >= h then return nil end
    return y * w + x + 1
  end

  local dom, size = {}, {}
  for c = 1, C do
    local list = domainList(classes[c])
    if not list then return nil, ("no tiles of the allowed classes for cell %d"):format(c) end
    local d = {}
    for _, i in ipairs(list) do d[i] = true end
    dom[c], size[c] = d, #list
  end

  local sup = {}
  local function key(c, t, d) return ((c - 1) * N + (t - 1)) * 4 + d end
  local stack, top = {}, 0
  -- Undo trail: positive entries are removals (c * (N + 1) + t), negative
  -- entries are support decrements (-key). Backtracking rewinds it.
  local trail, tlen = {}, 0
  local function remove(c, t)
    if not dom[c][t] then return true end
    dom[c][t] = nil
    size[c] = size[c] - 1
    top = top + 1
    stack[top] = c * (N + 1) + t
    tlen = tlen + 1
    trail[tlen] = c * (N + 1) + t
    return size[c] > 0
  end
  local function rewind(to)
    while tlen > to do
      local e = trail[tlen]
      trail[tlen] = nil
      tlen = tlen - 1
      if e > 0 then
        local c, t = math.floor(e / (N + 1)), e % (N + 1)
        dom[c][t] = true
        size[c] = size[c] + 1
      else
        sup[-e] = sup[-e] + 1
      end
    end
    top = 0
  end

  for c = 1, C do
    for t in pairs(dom[c]) do
      for d = 1, 4 do
        local n = nb(c, d)
        local count = 1e9
        if n then
          count = 0
          local dn = dom[n]
          for _, u in ipairs(adj[d][t]) do if dn[u] then count = count + 1 end end
        end
        sup[key(c, t, d)] = count
      end
    end
  end
  local pending = {}
  for c = 1, C do
    for t in pairs(dom[c]) do
      for d = 1, 4 do
        if sup[key(c, t, d)] == 0 then pending[#pending + 1] = { c, t }; break end
      end
    end
  end

  local function propagate()
    while top > 0 do
      local packed = stack[top]
      top = top - 1
      local n, u = math.floor(packed / (N + 1)), packed % (N + 1)
      for d = 1, 4 do
        local c = nb(n, d)
        if c then
          local back = OPP[d]
          local dc = dom[c]
          for _, t in ipairs(adj[d][u]) do
            local k = key(c, t, back)
            local s = sup[k]
            if s then
              s = s - 1
              sup[k] = s
              tlen = tlen + 1
              trail[tlen] = -k
              if s == 0 and dc[t] then
                if not remove(c, t) then return false, c end
              end
            end
          end
        end
      end
    end
    return true
  end

  for _, p in ipairs(pending) do
    if not remove(p[1], p[2]) then return nil, "contradiction at start, cell " .. p[1] end
  end
  local ok, bad = propagate()
  if not ok then return nil, "contradiction at start, cell " .. bad end
  tlen = 0 -- the starting state is never undone

  -- Decisions taken (cell, tile, trail length before it). On a contradiction,
  -- rewind to the latest decision and ban its tile there instead.
  local decisions, budget = {}, limits and limits.backtracks or 4000
  local function backtrack()
    while true do
      local d = table.remove(decisions)
      if not d or budget <= 0 then return false end
      budget = budget - 1
      rewind(d.mark)
      local alive = remove(d.cell, d.tile)
      if alive then
        local good = propagate()
        if good then return true end
      end
    end
  end

  while true do
    local best, bestScore
    for c = 1, C do
      local s = size[c]
      if s > 1 then
        local score = s + rng:next() * 0.5
        if not bestScore or score < bestScore then best, bestScore = c, score end
      end
    end
    if not best then break end
    local total, opts = 0, {}
    for t in pairs(dom[best]) do
      opts[#opts + 1] = t
      total = total + tiles[t].weight
    end
    table.sort(opts)
    local r, pick = rng:next() * total, opts[#opts]
    for _, t in ipairs(opts) do
      r = r - tiles[t].weight
      if r <= 0 then pick = t; break end
    end
    decisions[#decisions + 1] = { cell = best, tile = pick, mark = tlen }
    for _, t in ipairs(opts) do
      if t ~= pick then remove(best, t) end
    end
    ok, bad = propagate()
    if not ok and not backtrack() then
      return nil, "contradiction at cell " .. tostring(bad) .. " (backtracking exhausted)"
    end
  end

  local choice = {}
  for c = 1, C do choice[c] = next(dom[c]) end
  return choice
end

-- Allowed classes per cell for a semantic grid: open cells keep their class
-- (walk and grass may swap at their shared edge), and wall cells touching open
-- ground may also open up, giving the painter room for transition tiles while
-- never closing the path.
function Paint.softClasses(grid, w, h)
  local out = {}
  for c = 1, w * h do
    local x, y = (c - 1) % w, math.floor((c - 1) / w)
    local own, near = grid[c], {}
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if (dx ~= 0 or dy ~= 0) and nx >= 0 and ny >= 0 and nx < w and ny < h then
          near[grid[ny * w + nx + 1]] = true
        end
      end
    end
    if own == "block" and (near.walk or near.grass) then
      out[c] = { "block", "walk", near.grass and "grass" or nil }
    elseif own == "walk" and near.grass then
      out[c] = { "walk", "grass" }
    elseif own == "grass" and near.walk then
      out[c] = { "grass", "walk" }
    else
      out[c] = own
    end
  end
  return out
end

return Paint
