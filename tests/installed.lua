package.path = "./?.lua;./?/init.lua;" .. package.path
love = {
  data = {
    compress = function(_, _, bytes, level) return deflate(bytes, level) end,
    decompress = function(_, _, bytes) return inflate(bytes) end,
  },
  graphics = {
    newQuad = function() return {} end,
    newImage = function() return { getDimensions = function() return 256, 256 end } end,
  },
}
local GameVersion = require("src.core.GameVersion")
GameVersion.set(TEST_VERSION)
assert(require("src.core.Version").engine == "0.3.96", "wrong installed engine")

local fs, overlay = {}, {}
function fs.read(p) return overlay[p] or fs_read(p) end
function fs.getInfo(p) return overlay[p] and { type = "file" } or fs_info(p) end
function fs.getDirectoryItems(p) return fs_list(p) end
function fs.load(p)
  local bytes = fs.read(p)
  return bytes and loadstring(bytes, "@" .. p)
end
function fs.write(p, bytes) overlay[p] = bytes return true end
function fs.createDirectory() return true end
fs.root = "."

local generation = GameVersion.generation()
local Loader = require("src.mods.Loader")
local game = { data = {}, save = { party = {}, inventory = {} } }

if generation == 3 then
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = CACHE_ROOT
  assert(Dataset.hydrate(game), "installed dataset did not hydrate")
else
  error("roguelike_mode requires Gen 3")
end

local loader = Loader.new({ fs = fs, generation = generation })
loader:load(game.data)
assert(#loader.errors == 0, table.concat(loader.errors, "\n"))
local mod = loader.mods.roguelike_mode
assert(mod and mod.state == "loaded", "installed mod did not load for " .. TEST_VERSION)

local exports = loader.exports.roguelike_mode or mod.exports
assert(exports ~= nil, "roguelike_mode exports missing")

-- 1. Start menu hook test
local menuItems = { { id = "pokedex", label = "POKéDEX" } }
local hookedMenu = loader.hooks:call("ui.start_menu.items", function(_, items) return items end, game, menuItems)
local found = false
for _, it in ipairs(hookedMenu) do
  if it.id == "roguelike" and it.label == "ROGUELIKE" then found = true break end
end
assert(found, "ROGUELIKE not injected into start menu")

-- 2. Procedural Layer Generation & Facilities Rules
local session = exports.newRun({ seed = 4242 })
assert(#session.layers == 8, "must have 8 layers")

local survivalCount = 0
local seenFacilities = {}
local seenLeaders = {}
for i = 1, 8 do
  local layer = session.layers[i]
  if layer.isSurvival then survivalCount = survivalCount + 1 end
  if layer.specialFacility then
    assert(not seenFacilities[layer.specialFacility], "duplicate special facility: " .. layer.specialFacility)
    seenFacilities[layer.specialFacility] = true
  end
  assert(not seenLeaders[layer.gymLeader.id], "duplicate gym leader: " .. layer.gymLeader.id)
  seenLeaders[layer.gymLeader.id] = true
end
assert(survivalCount <= 1, "too many survival layers: " .. survivalCount)

-- 3. Starter drafting (Choice of 3 across Gen 1-3 at Level 5)
local choices = session:getStarterChoices()
assert(#choices == 3, "expected 3 starter choices")
assert(choices[1].level == 5, "starter level must be 5")
local okDraft = session:draftStarter(1)
assert(okDraft and session.runState == "exploring", "failed to draft starter")
assert(#session.party == 1, "party must have 1 mon")

-- 4. Option B: Layer Gate unlocking
assert(not session.currentLayer.layerGateUnlocked, "gate should be locked initially")
local okGateBefore, _ = session:useLayerGate()
assert(not okGateBefore, "layer gate should not open before defeating gym leader")

local okDefeat, _ = session:defeatGymLeader()
assert(okDefeat and session.currentLayer.layerGateUnlocked, "defeating gym leader must unlock layer gate (Option B)")
assert(session.runState == "layer_clear_cutscene", "must trigger layer clear cutscene")
session:dismissCutscene()
assert(session.runState == "exploring", "exploring should resume after dismissing cutscene")

local okGateAfter, nextLayerIdx = session:useLayerGate()
assert(okGateAfter and nextLayerIdx == 2, "must advance to layer 2 via unlocked gate")

-- 5. Option B White-out Rule: 3-life pool, money penalty, center respawn
local failSession = exports.newRun({ seed = 9000 })
failSession:draftStarter(1)
assert(failSession.lives == 3, "initial lives must be 3")
assert(failSession.money == 3000, "initial money must be 3000")
local okRespawn, _ = failSession:handleWhiteout()
assert(okRespawn and failSession.lives == 2 and failSession.money == 1500, "whiteout life/money decrement failed")
failSession:handleWhiteout() -- life 1
local okDead, _ = failSession:handleWhiteout() -- life 0 -> game over
assert(not okDead and failSession.runState == "game_over", "exhausting lives must end run")

-- 6. Field Move HM Bypass
local testParty = { { species = 25, hp = 30, isEgg = false } }
local eligibility = loader.hooks:call("fieldmove.eligibility", function() return nil end, "FLY", { party = testParty })
assert(eligibility == testParty[1], "universal HM bypass failed")

-- 7. Evolution checks at level 40
local tradeMon = { species = 67, level = 40 }
assert(loader.hooks:call("pokemon.evolution_check", function() return false end, tradeMon, "trade") == true, "trade evo at 40 failed")
local hapMon = { species = 42, level = 40 }
assert(loader.hooks:call("pokemon.evolution_check", function() return false end, hapMon, "happiness") == true, "happiness evo at 40 failed")

-- 8. Rollback restoration
exports.restore()
local restoredMenu = loader.hooks:call("ui.start_menu.items", function(_, items) return items end, game, menuItems)
assert(#restoredMenu == 1, "menu item not removed after rollback")

print(string.format("PASS installed %s: roguelike_mode layers, gates, rules, and rollback verified", TEST_VERSION))
