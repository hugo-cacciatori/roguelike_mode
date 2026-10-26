-- Pure-logic checks that need neither imports nor a FireRed session.
local H = dofile(MOD_ROOT .. "/tests/harness.lua")
local check = H.check

local R = { atlas = { MID_STRIDE = 4096, PREFIX = "rl_" }, data = {} }
local function module(name)
  local source = assert(io.open(MOD_ROOT .. "/lib/" .. name .. ".lua", "rb")):read("*a")
  R[name] = assert(load(source, "@lib/" .. name .. ".lua"))(R)
  return R[name]
end
local Rng, Layout, Paint, Corpus = module("rng"), module("layout"), module("paint"), module("corpus")

-- Rng: reproducible and in range.
local a, b = Rng.new(42), Rng.new(42)
local same, inRange = true, true
for _ = 1, 200 do
  local x, y = a:int(3, 9), b:int(3, 9)
  same = same and x == y
  inRange = inRange and x >= 3 and x <= 9
end
check(same, "same seed, same sequence")
check(inRange, "int stays in range")

-- Layout: openings, spots and grass are where the painter needs them.
for seed = 1, 10 do
  local l = Layout.outdoor(Rng.new(seed), { width = 36, height = 44 })
  local function at(p) return l.grid[p.y * l.width + p.x + 1] end
  check(l.width == 36 and l.height == 44, "layout keeps the requested size")
  check(at(l.entry) == "walk" and l.entry.y == 0, "entry opens the top edge")
  check(at(l.exit) == "walk" and l.exit.y == l.height - 1, "exit opens the bottom edge")
  check(at(l.boss) == "walk", "boss spot is plain ground")
  check(#l.trainers >= 1, "trainer spots exist")
  local grass = 0
  for _, v in ipairs(l.grid) do if v == "grass" then grass = grass + 1 end end
  check(grass > 0, "grass zones exist")
  -- every region is 2 wide: the grid is a doubled coarse grid
  local aligned = true
  for y = 0, l.height - 1, 2 do
    for x = 0, l.width - 1, 2 do
      local v = l.grid[y * l.width + x + 1]
      aligned = aligned and l.grid[y * l.width + x + 2] == v and l.grid[(y + 1) * l.width + x + 1] == v
    end
  end
  check(aligned, "layout is built from 2x2 blocks")
end

-- Paint: a toy tileset where "A" and "B" must alternate horizontally and
-- vertically; any 2x2 window then contains both, and the solver must honour it.
local tiles = { { class = "walk", weight = 1 }, { class = "walk", weight = 1 }, { class = "block", weight = 1 } }
local adj = { {}, {}, {}, {} }
for d = 1, 4 do adj[d] = { { 2 }, { 1 }, { 3 } } end
local classes = {}
for i = 1, 6 * 4 do classes[i] = "walk" end
local choice = assert(Paint.solve(tiles, adj, classes, 6, 4, Rng.new(1)))
local checker = true
for y = 0, 3 do
  for x = 0, 5 do
    local t = choice[y * 6 + x + 1]
    if x > 0 then checker = checker and t ~= choice[y * 6 + x] end
    if y > 0 then checker = checker and t ~= choice[(y - 1) * 6 + x + 1] end
  end
end
check(checker, "solver respects learned adjacency (checkerboard)")
classes[1] = "block"
check(Paint.solve(tiles, adj, classes, 6, 4, Rng.new(1)) == nil, "impossible class mix is reported, not painted")

-- Soft classes never close open ground.
local grid = { "block", "block", "walk", "grass" }
local soft = Paint.softClasses(grid, 4, 1)
check(type(soft[2]) == "table" and soft[1] == "block", "only walls beside open ground soften")
local opens = true
for _, c in ipairs(type(soft[3]) == "table" and soft[3] or { soft[3] }) do opens = opens and c ~= "block" end
check(opens, "open cells never become walls")

-- Environment classification from map headers.
check(Corpus.environmentOf("FR_VIRIDIAN_FOREST", { mapType = 3 }) == "forest", "forest by name")
check(Corpus.environmentOf("EM_GRANITE_CAVE_1F", { mapType = 4 }) == "cave", "cave by map type")
check(Corpus.environmentOf("EM_ROUTE105", { mapType = 6 }) == "sea", "ocean route")
check(Corpus.environmentOf("EM_ROUTE101", { mapType = 3 }, 0.1) == "route", "land route")
check(Corpus.environmentOf("FR_PALLET_TOWN_PROFESSOR_OAKS_LAB", { mapType = 8 }) == "interior_lab", "lab interior")
check(Corpus.environmentOf("EM_OLDALE_TOWN_POKEMON_CENTER_1F", { mapType = 8 }) == "interior_center", "center interior")
check(Corpus.environmentOf("EM_LITTLEROOT_TOWN", { mapType = 1 }) == "town", "town")
check(Corpus.environmentOf("EM_SECRET_BASE_BLUE_CAVE1", { mapType = 9 }) == "secret_base", "secret bases are not houses")

print(("PASS unit: %d assertions"):format(H.total))
