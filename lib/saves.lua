-- Runs live in their own engine save slot ("Roguelike run"), so in-game
-- saving and Continue go through the normal paths and never touch the
-- adventure's slot.
--
-- Crash safety: SaveData.setActiveSlot persists its choice to options.lua.
-- Right after switching, options.lua is pointed back at the adventure's slot
-- while this process keeps using the run slot, so a restart without the mod
-- continues the adventure even if restore() never ran.

local R = ...
local SaveData = require("src.core.SaveData")

local Saves = {}

Saves.VERSION = "firered"
Saves.RUN_LABEL = "Roguelike run"
Saves.ADVENTURE_LABEL = "Adventure"

local state -- { previous = slotId, run = slotId }

local function findSlot(label)
  for _, slot in ipairs(SaveData.listSlots(Saves.VERSION)) do
    if slot.label == label then return slot.id end
  end
end

local function createSlot(label)
  local id = assert(SaveData.createSlot(Saves.VERSION), "roguelike_mode: could not create a save slot")
  SaveData.renameSlot(Saves.VERSION, id, label)
  return id
end

-- Keep options.lua's active slot on the adventure.
local function persistAdventure()
  local opts = SaveData.loadOptions()
  local reg = opts.saveSlots and opts.saveSlots[Saves.VERSION]
  if type(reg) == "table" and reg.active ~= state.previous then
    reg.active = state.previous
    SaveData.saveOptions(opts)
  end
end

-- Point this process at the run slot (again, if something re-resolved it).
function Saves.activateRun()
  if SaveData.activeSlot(Saves.VERSION) ~= state.run then
    SaveData.setActiveSlot(Saves.VERSION, state.run)
  end
  persistAdventure()
end

function Saves.slots()
  return state and { previous = state.previous, run = state.run } or nil
end

function Saves.install()
  if state then return end
  local previous = SaveData.activeSlot(Saves.VERSION)
  local run = findSlot(Saves.RUN_LABEL)
  if previous == run then previous = nil end -- left over from an earlier crash
  if not previous then
    -- Without an adventure slot, a restart without the mod would fall back to
    -- the run's slot. An empty adventure slot keeps that restart on New Game.
    previous = findSlot(Saves.ADVENTURE_LABEL) or createSlot(Saves.ADVENTURE_LABEL)
  end
  state = { previous = previous, run = run or createSlot(Saves.RUN_LABEL) }
  Saves.activateRun()
end

function Saves.restore()
  if not state then return end
  SaveData.setActiveSlot(Saves.VERSION, state.previous)
  state = nil
end

-- The title screen's Continue panel is read before mods load; refresh it from
-- the run slot once the boot screen exists.
function Saves.refreshTitle(game)
  if not (state and type(game) == "table" and game.boot) then return end
  local Boot = require("src.ui.game3.boot")
  local ok, save = pcall(SaveData.load)
  save = ok and type(save) == "table" and save or nil
  local hasContinue = save ~= nil and type(game._hasContinueSave) == "function" and game:_hasContinueSave()
  Boot.setHasContinue(game.boot, hasContinue and true or false)
  if hasContinue then Boot.setContinueInfo(game.boot, Boot.continueInfoFromSave(save)) end
end

function Saves.installHooks(mod)
  -- Safety net: only run sessions are written, and only into the run slot.
  mod.hooks:wrap("save.write", function(next, game)
    if not (state and R.run.isRun(game and game.session)) then
      if mod.log and mod.log.warn then mod.log:warn("refused to save a session that is not a run") end
      return false
    end
    Saves.activateRun()
    return next(game)
  end)
end

return Saves
