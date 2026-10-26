-- Takeover through the engine's real save paths (SaveData slots, the FireRed
-- save schema's save.new_game call, Game3:saveGame, Game3:_hasContinueSave,
-- the boot screen's Continue state). Saves and options.lua live on the
-- harness's in-memory disk; FireRed data comes from the imports.
--
-- SCENARIO = "adventure": an existing FireRed adventure is on disk.
-- SCENARIO = "fresh": no FireRed save exists yet.
local H = dofile(MOD_ROOT .. "/tests/harness.lua")
local check = H.check
local scenario = SCENARIO or "adventure"

local game = H.bootFireRed()
local Sdk = require("tests.modkit.sdk")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local Schema = require("src.core.game3.save_schema_firered")
local Game3 = require("src.core.Game3")
local Map = require("src.core.game3.map")

local function newSession(name)
  return Schema.newGame({ name = name, gender = 0, start = { map = "FR_PALLET_TOWN", x = 5, y = 5 } })
end
local function save(session) return Game3.saveGame({ session = session, phase = "field" }) end
local function loadedName()
  local raw = SaveData.load()
  return raw and raw.name
end
local function snapshot(prefix)
  local out = {}
  for key, body in pairs(H.disk) do
    if key:sub(1, #prefix) == prefix then out[key] = body end
  end
  return out
end
local function unchanged(before, prefix)
  local after = snapshot(prefix)
  for key, body in pairs(before) do if after[key] ~= body then return false end end
  for key in pairs(after) do if before[key] == nil then return false end end
  return true
end

-- 0. Before the mod: the player's own adventure (or nothing).
local adventure
if scenario == "adventure" then
  check(save(newSession("HUGO")), "vanilla save written without the mod")
  SaveData.resetSlotState() -- next launch: the engine migrates the flat save into slot1
  check(SaveData.activeSlot("firered") == "slot1", "adventure lives in slot1 after migration")
  adventure = snapshot("saves/firered/slot1")
  check(next(adventure) ~= nil, "adventure slot has files")
end
local rawBeforeMods = SaveData.load() -- Game3:init reads the title panel save before _loadMods

-- 1. Enabling the mod switches this process to the run slot.
local run = Sdk.loadMods({ "mods/roguelike_mode" },
  { fs = Sdk.memfs(MOD_FILES), generation = 3, data = game.data })
check(#run.errors == 0, "load errors: " .. table.concat(run.errors, "\n"))
local exports = run.loader.exports.roguelike_mode
local R = exports.R
local slots = R.saves.slots()
check(slots and slots.run and slots.previous and slots.run ~= slots.previous, "run and adventure slots differ")
if scenario == "adventure" then check(slots.previous == "slot1", "the adventure slot is remembered") end
check(SaveData.activeSlot("firered") == slots.run, "this process uses the run slot")

-- 2. Crash safety: options.lua keeps the adventure active.
local opts = SaveData.loadOptions()
check(opts.saveSlots.firered.active == slots.previous, "options.lua still points at the adventure")
SaveData.resetSlotState() -- a restart without the mod
check(SaveData.activeSlot("firered") == slots.previous, "restart without the mod resumes the adventure slot")
if scenario == "adventure" then check(loadedName() == "HUGO", "restart without the mod loads the adventure") end
R.saves.activateRun()
check(SaveData.activeSlot("firered") == slots.run, "activateRun returns to the run slot")

-- 3. Title screen before any run: no Continue, and the panel is refreshed.
check(not Game3._hasContinueSave({}), "no Continue while the run slot is empty")
local boot = { continueInfo = rawBeforeMods and { name = rawBeforeMods.name } }
local fakeGame = { data = game.data, boot = boot, _hasContinueSave = Game3._hasContinueSave }
Runtime.emit("game.ready", { game = fakeGame })
check(boot.hasContinue == false, "title hides Continue with no run")

-- 4. New Game starts a run: the first area is generated from the run seed,
--    registered, and the player stands at its entry.
local session = newSession("RUNNER")
local state = R.run.state(session)
check(state and state.layer == 1 and type(state.seed) == "number", "New Game carries run state")
local first = game.data.maps[session.map]
check(first and first.roguelike and first.roguelike.env, "New Game registered a generated area")
local entry = first.roguelike.layout.entry
check(session.x == entry.x and session.y == entry.y, "New Game starts at the generated entry")
check(Map.load(nil, game, session.map, { depth1Connections = false }), "the run's start map loads")
local firstCells = first.midLayout.cells

-- 5. Saving writes the run slot only.
check(save(session), "run save written")
check(H.disk["saves/firered/" .. slots.run .. ".lua"] ~= nil, "run slot file exists")
if scenario == "adventure" then check(unchanged(adventure, "saves/firered/slot1"), "adventure bytes unchanged") end

-- 6. Continue resumes the run; the title panel shows it.
check(loadedName() == "RUNNER", "Continue loads the run")
local resumed = Schema.fromSaveTable(SaveData.load())
check(R.run.isRun(resumed) and resumed.map == session.map, "resumed session is the run on its map")
-- A fresh process has no generated maps: Continue's save.loading rebuilds
-- them from the saved seed, identically.
R.world.forget()
check(game.data.maps[session.map] == nil, "maps gone, as after a restart")
Runtime.emit("save.loading", { raw = SaveData.load() })
local rebuilt = game.data.maps[session.map]
local same = rebuilt ~= nil
for i, cell in ipairs(rebuilt and rebuilt.midLayout.cells or {}) do
  same = same and cell.mid == firstCells[i].mid and cell.coll == firstCells[i].coll
end
check(same and rebuilt ~= first, "Continue regenerates the same area from the saved seed")
check(Game3._hasContinueSave({}), "Continue is offered for the run")
Runtime.emit("game.ready", { game = fakeGame })
check(boot.hasContinue == true and boot.continueInfo and boot.continueInfo.name == "RUNNER",
  "title panel refreshed to the run")

-- 7. Safety net: a session that is not a run is refused, nothing written.
local before = snapshot("saves/")
local stray = newSession("STRAY") -- New Game itself always makes a run now
stray.modData.roguelike = nil
check(save(stray) == false, "non-run session refused by save.write")
check(unchanged(before, "saves/"), "refused save wrote nothing")

-- 8. Something re-resolves slots mid-session: the run still lands in its slot.
SaveData.refreshSlotResolution("firered")
check(SaveData.activeSlot("firered") == slots.previous, "re-resolution falls back to the adventure")
session.x = session.x + 1
check(save(session), "run save after re-resolution")
check(SaveData.activeSlot("firered") == slots.run, "save.write re-activated the run slot")
if scenario == "adventure" then check(unchanged(adventure, "saves/firered/slot1"), "adventure still unchanged") end

-- 9. Disabling the mod hands Continue back to the adventure.
exports.restore()
check(SaveData.activeSlot("firered") == slots.previous, "restore re-activates the adventure slot")
if scenario == "adventure" then
  check(loadedName() == "HUGO", "Continue loads the adventure after restore")
else
  check(SaveData.load() == nil, "fresh install: Continue is empty after restore")
end
run.release()

print(("PASS takeover (%s): %d assertions"):format(scenario, H.total))
