-- Pure-logic checks that need neither imports nor a FireRed session.
local H = dofile(MOD_ROOT .. "/tests/harness.lua")
local check = H.check

local R = { atlas = { MID_STRIDE = 4096, PREFIX = "rl_" } }
local source = assert(io.open(MOD_ROOT .. "/lib/splice.lua", "rb")):read("*a")
local Splice = assert(load(source, "@lib/splice.lua"))(R)

local function layout(w, h, base)
  local cells = {}
  for i = 1, w * h do cells[i] = { mid = base + i, coll = 0, elev = 3 } end
  return { width = w, height = h, cells = cells }
end

local spec = {
  id = "FR_RL_UNIT", width = 5, height = 4,
  chunks = {
    { part = 1, src = { x = 1, y = 1, w = 2, h = 2 }, at = { x = 0, y = 0 } },
    { part = 2, src = { x = 0, y = 0, w = 3, h = 1 }, at = { x = 2, y = 3 } },
  },
}
local cells = Splice.cells(spec, { layout(4, 4, 100), layout(3, 2, 200) }, { 0, 4096 }, 7)
local function at(x, y) return cells[y * spec.width + x + 1] end

check(#cells == 20, "composite has width*height cells")
check(at(0, 0).mid == 100 + (1 * 4 + 1) + 1, "chunk 1 copies its source origin")
check(at(1, 1).mid == 100 + (2 * 4 + 2) + 1, "chunk 1 copies row-major")
check(at(2, 3).mid == 4096 + 201 and at(4, 3).mid == 4096 + 203, "part 2 mids are offset")
check(at(4, 0).mid == 7 and at(4, 0).coll == 1, "uncovered cells are impassable filler")
check(at(0, 0).elev == 3, "elevation survives the copy")
check(Splice.pairId(spec) == "rl_unit", "merged pair id derives from the map id")

local bad = { id = "FR_RL_BAD", width = 2, height = 2,
  chunks = { { part = 1, src = { x = 3, y = 3, w = 2, h = 2 }, at = { x = 0, y = 0 } } } }
check(not pcall(Splice.cells, bad, { layout(4, 4, 0) }, { 0 }, 0), "out-of-source chunks are refused")

print(("PASS unit: %d assertions"):format(H.total))
