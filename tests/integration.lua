package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local Sdk = require("tests.modkit.sdk")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Logger = require("src.core.Logger")
if Logger.warn then Logger.warn = function() end end

local total = 0
local function check(value, message)
  total = total + 1
  assert(value, message)
end

local PROFILES = {
  { version = "firered", gen = 3 },
  { version = "leafgreen", gen = 3 },
  { version = "ruby", gen = 3 },
  { version = "sapphire", gen = 3 },
  { version = "emerald", gen = 3 },
}

for _, p in ipairs(PROFILES) do
  GameVersion.set(p.version)
  Runtime.reset()

  local opts = {
    version = p.version,
    generation = p.gen,
    data = Sdk.gen3Data(),
  }

  local run = Sdk.loadMod(MOD_PATH, opts)
  check(#run.errors == 0, p.version .. ": load error: " .. table.concat(run.errors, "\n"))
  check(run.mod and run.mod.state == "loaded", p.version .. ": mod loaded")

  local loader = run.loader
  local exports = loader.exports.roguelike_mode or (run.mod and run.mod.exports)
  check(exports ~= nil, p.version .. ": exports available")

  -- 1. Test ui.start_menu.items hook integration
  local initialItems = { { id = "pokedex", label = "POKéDEX" }, { id = "pokemon", label = "POKéMON" } }
  local fakeGame = { generation = p.gen, save = { party = {}, inventory = {} } }
  local hooked = loader.hooks:call("ui.start_menu.items", function(_, items) return items end, fakeGame, initialItems)

  check(#hooked == #initialItems + 1, p.version .. ": ROGUELIKE appended to start menu")
  local foundRoguelike = nil
  for _, item in ipairs(hooked) do
    if item.id == "roguelike" then foundRoguelike = item; break end
  end
  check(foundRoguelike ~= nil and foundRoguelike.label == "ROGUELIKE", p.version .. ": ROGUELIKE entry valid")

  -- 2. Test Procedural 8-Layer World Generation
  local session = exports.newRun({ seed = 12345 + p.gen })
  check(#session.layers == 8, p.version .. ": exactly 8 progression layers generated")

  -- Verify Layer 1 restrictions: cannot be solely cave or water route
  local l1 = session.layers[1]
  check(#l1.maps >= 2, p.version .. ": layer 1 has at least 2 maps")
  check(l1.maps[1]:find("Town") or l1.maps[1]:find("City"), p.version .. ": layer 1 starts with a town/city")

  -- Verify map density curve: later layers have more maps than early layers
  check(#session.layers[8].maps > #session.layers[1].maps, p.version .. ": layer 8 has more maps than layer 1")

  -- Verify 8 unique Gym Leaders (no duplicates)
  local leaderNames = {}
  for i = 1, 8 do
    local leader = session.layers[i].gymLeader
    check(not leaderNames[leader.id], p.version .. ": gym leader " .. leader.name .. " is unique")
    leaderNames[leader.id] = true
  end

  -- Verify Boss Level Curve Scaling
  check(session.layers[1].gymLeader.level == 14, p.version .. ": layer 1 boss is level 14")
  check(session.layers[8].gymLeader.level == 60, p.version .. ": layer 8 boss is level 60")
  for i = 2, 8 do
    check(session.layers[i].gymLeader.level > session.layers[i - 1].gymLeader.level, p.version .. ": boss levels scale monotonically")
  end

  -- Verify Facilities Rules:
  local survivalCount = 0
  local facilityCounts = {}
  for i = 1, 8 do
    local l = session.layers[i]
    if l.isSurvival then survivalCount = survivalCount + 1 end
    if l.specialFacility then
      facilityCounts[l.specialFacility] = (facilityCounts[l.specialFacility] or 0) + 1
    end
  end
  check(survivalCount <= 1, p.version .. ": at most 1 survival layer in the run")
  for fac, count in pairs(facilityCounts) do
    check(count <= 1, p.version .. ": special facility " .. fac .. " appears at most once")
  end

  -- 3. Test Starter Draft (Choice of 3 across Gen 1-3)
  check(session.runState == "draft", p.version .. ": run starts in draft state")
  local starterChoices = session:getStarterChoices()
  check(#starterChoices == 3, p.version .. ": offers 3 starter choices")
  for _, st in ipairs(starterChoices) do
    check(st.level == 5, p.version .. ": starter is level 5")
  end

  local okDraft, pickedStarter = session:draftStarter(1)
  check(okDraft and session.runState == "exploring", p.version .. ": drafted starter and entered exploration")
  check(#session.party == 1, p.version .. ": party contains drafted starter")

  -- 4. Test Layer Progression & Option B Layer Gate
  check(not session.currentLayer.layerGateUnlocked, p.version .. ": layer gate initially locked")
  local okGateEarly, _ = session:useLayerGate()
  check(not okGateEarly, p.version .. ": cannot use layer gate before defeating gym leader")

  -- Defeat Layer 1 Gym Leader
  local okBoss, bossDefeated = session:defeatGymLeader()
  check(okBoss and session.currentLayer.layerGateUnlocked, p.version .. ": defeating gym leader unlocks layer gate (Option B)")
  check(session.runState == "layer_clear_cutscene", p.version .. ": cutscene triggered upon layer clear")

  session:dismissCutscene()
  check(session.runState == "exploring", p.version .. ": exploring resumed after cutscene")

  -- Use Layer Gate to advance to Layer 2
  local okAdvance, newLayer = session:useLayerGate()
  check(okAdvance and newLayer == 2 and session.currentLayerIndex == 2, p.version .. ": advanced to layer 2 via gate")

  -- Fast-forward layers 2 through 8
  for l = 2, 8 do
    session:defeatGymLeader()
    session:dismissCutscene()
    session:useLayerGate()
  end
  check(session.runState == "endgame", p.version .. ": reached endgame gauntlet after layer 8")

  -- 5. Test Elite Four & Champion Gauntlet
  check(#session.eliteFour == 4, p.version .. ": 4 elite four members randomized")
  check(session.champion ~= nil, p.version .. ": champion randomized")

  for e4 = 1, 4 do
    local okE4, member = session:defeatEliteFourMember(e4)
    check(okE4 and member ~= nil, p.version .. ": defeated elite four member " .. e4)
  end

  local okChamp, champMsg = session:defeatChampion()
  check(okChamp and session.runState == "victory", p.version .. ": defeated champion, run victory achieved")

  -- 6. Test White-Out / Defeat Rule (Option B — 3 Lives Pool & Center Respawn)
  local failSession = exports.newRun({ seed = 9999 })
  failSession:draftStarter(1)
  check(failSession.lives == 3, p.version .. ": initial lives pool is 3")
  check(failSession.money == 3000, p.version .. ": initial money is 3000")

  -- First whiteout:
  local okRespawn1, _ = failSession:handleWhiteout()
  check(okRespawn1 and failSession.lives == 2, p.version .. ": whiteout decrements life to 2")
  check(failSession.money == 1500, p.version .. ": whiteout halves money")
  check(failSession.runState == "exploring", p.version .. ": respawned in exploring state")

  -- Second whiteout:
  local okRespawn2, _ = failSession:handleWhiteout()
  check(okRespawn2 and failSession.lives == 1, p.version .. ": whiteout decrements life to 1")

  -- Third whiteout:
  local okGameOver, _ = failSession:handleWhiteout()
  check(not okGameOver and failSession.runState == "game_over", p.version .. ": exhausting lives ends run with game_over")

  -- 7. Test Field Move HM Bypass Hook
  local fakeParty = { { species = 16, hp = 30, isEgg = false } } -- Pidgey
  local dummyCtx = { party = fakeParty }
  local surfPerformer = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", dummyCtx)
  check(surfPerformer == fakeParty[1], p.version .. ": HM Surf bypassed and granted to non-egg party member")

  -- 8. Test Level 40 Evolution Adjustments
  local kadabra = { species = 64, level = 40 }
  local evoTrade = loader.hooks:call("pokemon.evolution_check", function() return false end, kadabra, "trade")
  check(evoTrade == true, p.version .. ": trade evolution triggered at level 40")

  local golbat = { species = 42, level = 40 }
  local evoHappiness = loader.hooks:call("pokemon.evolution_check", function() return false end, golbat, "happiness")
  check(evoHappiness == true, p.version .. ": happiness evolution triggered at level 40")

  local eevee = { species = 133, level = 40 }
  local evoDay = loader.hooks:call("pokemon.evolution_check", function() return false end, eevee, "day")
  check(evoDay == true, p.version .. ": day evolution triggered at level 40")

  -- 9. Check Adventure Save Isolation & Clean Rollback
  check(#fakeGame.save.party == 0, p.version .. ": adventure party was never modified")
  check(next(fakeGame.save.inventory) == nil, p.version .. ": adventure inventory was never modified")

  exports.restore()
  local unhooked = loader.hooks:call("ui.start_menu.items", function(_, items) return items end, fakeGame, initialItems)
  check(#unhooked == #initialItems, p.version .. ": ROGUELIKE removed from start menu after rollback")
end

print(string.format("Integration suite passed: %d assertions across %d profiles", total, #PROFILES))
