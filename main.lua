-- Roguelike Layer-World Mode
-- ---------------------------------------------------------------------------
-- Procedural Gen 3 Layer-World Adventure:
-- 8 layers + Final Wild + Randomized Elite 4 & Champion gauntlet.
-- Biome splicing, scaled Gym Leaders, facility constraints, starter draft,
-- HM bypass, Level 40 evolutions, and 3-life trial pool.
-- ---------------------------------------------------------------------------

local Roguelike = {}
Roguelike.__index = Roguelike

-- Candidate Starters (Level 5) across Generations 1, 2, and 3
local STARTERS = {
  { id = 1, name = "Bulbasaur", gen = 1 },
  { id = 4, name = "Charmander", gen = 1 },
  { id = 7, name = "Squirtle", gen = 1 },
  { id = 25, name = "Pikachu", gen = 1 },
  { id = 133, name = "Eevee", gen = 1 },
  { id = 152, name = "Chikorita", gen = 2 },
  { id = 155, name = "Cyndaquil", gen = 2 },
  { id = 158, name = "Totodile", gen = 2 },
  { id = 252, name = "Treecko", gen = 3 },
  { id = 255, name = "Torchic", gen = 3 },
  { id = 258, name = "Mudkip", gen = 3 },
}

-- All 16 Gen 3 Gym Leaders
local GYM_LEADERS = {
  { id = "brock", name = "Brock", type = "Rock", ace = 95 },
  { id = "misty", name = "Misty", type = "Water", ace = 121 },
  { id = "surge", name = "Lt. Surge", type = "Electric", ace = 26 },
  { id = "erika", name = "Erika", type = "Grass", ace = 45 },
  { id = "koga", name = "Koga", type = "Poison", ace = 110 },
  { id = "sabrina", name = "Sabrina", type = "Psychic", ace = 65 },
  { id = "blaine", name = "Blaine", type = "Fire", ace = 78 },
  { id = "giovanni", name = "Giovanni", type = "Ground", ace = 31 },
  { id = "roxanne", name = "Roxanne", type = "Rock", ace = 299 },
  { id = "brawly", name = "Brawly", type = "Fighting", ace = 297 },
  { id = "wattson", name = "Wattson", type = "Electric", ace = 310 },
  { id = "flannery", name = "Flannery", type = "Fire", ace = 323 },
  { id = "norman", name = "Norman", type = "Normal", ace = 289 },
  { id = "winona", name = "Winona", type = "Flying", ace = 334 },
  { id = "tate_liza", name = "Tate & Liza", type = "Psychic", ace = 338 },
  { id = "wallace", name = "Wallace", type = "Water", ace = 350 },
}

-- Elite Four pool (Kanto + Hoenn)
local ELITE_FOUR = {
  { id = "lorelei", name = "Lorelei", type = "Ice" },
  { id = "bruno", name = "Bruno", type = "Fighting" },
  { id = "agatha", name = "Agatha", type = "Ghost" },
  { id = "lance_e4", name = "Lance", type = "Dragon" },
  { id = "sidney", name = "Sidney", type = "Dark" },
  { id = "phoebe", name = "Phoebe", type = "Ghost" },
  { id = "glacia", name = "Glacia", type = "Ice" },
  { id = "drake", name = "Drake", type = "Dragon" },
}

-- Champion candidates
local CHAMPIONS = {
  { id = "blue", name = "Blue", title = "Champion Blue" },
  { id = "steven", name = "Steven", title = "Champion Steven" },
  { id = "wallace_champ", name = "Wallace", title = "Champion Wallace" },
  { id = "wally", name = "Wally", title = "Champion Wally" },
  { id = "lance", name = "Lance", title = "Champion Lance" }, -- "Peter"
}

-- Biome Map Pool for Layers
local BIOMES = {
  towns = { "Pallet Town", "Viridian City", "Pewter City", "Cerulean City", "Vermilion City", "Oldale Town", "Petalburg City", "Rustboro City", "Dewford Town", "Slateport City", "Fallarbor Town", "Fortree City" },
  routes = { "Route 1", "Route 2", "Route 3", "Route 4", "Route 24", "Route 101", "Route 102", "Route 104", "Route 110", "Route 116", "Route 119" },
  forests = { "Viridian Forest", "Petalburg Woods", "Green Path" },
  caves = { "Mt. Moon", "Rock Tunnel", "Granite Cave", "Fiery Path", "Meteor Falls" },
  water = { "Route 19", "Route 20", "Route 105", "Route 106", "Route 124" },
}

-- Composite Biome Splicing Chunks
local COMPOSITE_CHUNKS = {
  { id = "forest_spliced", name = "Viridian-Petalburg Spliced Canopy", biomes = { "Viridian Forest", "Petalburg Woods" } },
  { id = "sevi_path_spliced", name = "Green Path Meadow", biomes = { "Green Path", "Route 119" } },
  { id = "cave_spliced", name = "Granite Moon Cavern", biomes = { "Mt. Moon", "Granite Cave" } },
}

-- Target Level & Party Size Progression per Layer
local LAYER_TARGETS = {
  [1] = { wildMin = 5, wildMax = 12, bossLv = 14, bossTeam = 2 },
  [2] = { wildMin = 13, wildMax = 19, bossLv = 21, bossTeam = 3 },
  [3] = { wildMin = 20, wildMax = 26, bossLv = 28, bossTeam = 3 },
  [4] = { wildMin = 27, wildMax = 33, bossLv = 35, bossTeam = 4 },
  [5] = { wildMin = 34, wildMax = 40, bossLv = 42, bossTeam = 4 },
  [6] = { wildMin = 41, wildMax = 46, bossLv = 48, bossTeam = 5 },
  [7] = { wildMin = 47, wildMax = 52, bossLv = 54, bossTeam = 5 },
  [8] = { wildMin = 53, wildMax = 58, bossLv = 60, bossTeam = 6 },
}

function Roguelike.newRun(opts)
  opts = opts or {}
  local seed = opts.seed or os.time()
  local rngState = seed

  local function random(m, n)
    rngState = (rngState * 1103515245 + 12345) % 2147483648
    local val = rngState / 2147483648
    if not m then return val end
    if not n then return math.floor(val * m) + 1 end
    return math.floor(val * (n - m + 1)) + m
  end

  local function shuffle(tbl)
    local copy = {}
    for i, v in ipairs(tbl) do copy[i] = v end
    for i = #copy, 2, -1 do
      local j = random(1, i)
      copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
  end

  -- 1. Select 8 unique Gym Leaders
  local shuffledLeaders = shuffle(GYM_LEADERS)
  local gymLeaders = {}
  for i = 1, 8 do gymLeaders[i] = shuffledLeaders[i] end

  -- 2. Distribute Unique Facilities (at most once across all 8 layers)
  local specialPool = { "casino", "daycare", "mall", "fossil_lab", "trading_club" }
  specialPool = shuffle(specialPool)
  local specialAssignments = {}
  -- Assign up to 4-5 unique facilities randomly to layers 2-7
  local eligibleLayers = shuffle({ 2, 3, 4, 5, 6, 7 })
  for i, facility in ipairs(specialPool) do
    if eligibleLayers[i] then
      specialAssignments[eligibleLayers[i]] = facility
    end
  end

  -- 3. Select at most ONE Survival Layer (no Center, no Mart)
  local survivalLayer = (random(1, 100) <= 70) and eligibleLayers[#eligibleLayers] or nil

  -- 4. Select Elite 4 (4 unique) and Champion
  local shuffledE4 = shuffle(ELITE_FOUR)
  local eliteFour = { shuffledE4[1], shuffledE4[2], shuffledE4[3], shuffledE4[4] }
  local champion = CHAMPIONS[random(1, #CHAMPIONS)]

  -- 5. Build the 8 Layers
  local layers = {}
  for layerNum = 1, 8 do
    local targets = LAYER_TARGETS[layerNum]
    local leader = gymLeaders[layerNum]

    -- Map count scaling: earlier layers have fewer maps, later layers have more
    local mapCount = (layerNum == 1 and 2) or (layerNum <= 3 and 3) or (layerNum <= 5 and 4) or (layerNum <= 7 and 5) or 6

    local isSurvival = (layerNum == survivalLayer)
    local special = specialAssignments[layerNum]

    -- Layer 1 restriction: cannot be solely cave or water route
    local townMap = BIOMES.towns[random(1, #BIOMES.towns)]
    local wildMap = (layerNum == 1) and BIOMES.routes[random(1, #BIOMES.routes)] or
      ((random(1, 100) <= 30 and COMPOSITE_CHUNKS[random(1, #COMPOSITE_CHUNKS)].name) or BIOMES.routes[random(1, #BIOMES.routes)])

    local layerMaps = { townMap, wildMap }
    while #layerMaps < mapCount do
      local category = (random(1, 100) <= 40 and "caves") or (random(1, 100) <= 60 and "forests") or "routes"
      local pool = BIOMES[category]
      local added = pool[random(1, #pool)]
      table.insert(layerMaps, added)
    end

    layers[layerNum] = {
      layer = layerNum,
      maps = layerMaps,
      gymLeader = {
        id = leader.id,
        name = leader.name,
        type = leader.type,
        level = targets.bossLv,
        teamSize = targets.bossTeam,
        ace = leader.ace,
        defeated = false,
      },
      wildMin = targets.wildMin,
      wildMax = targets.wildMax,
      hasCenter = not isSurvival,
      hasShop = not isSurvival,
      isSurvival = isSurvival,
      specialFacility = special,
      layerGateUnlocked = false,
    }
  end

  local self = setmetatable({
    seed = seed,
    random = random,
    layers = layers,
    currentLayerIndex = 1,
    currentLayer = layers[1],
    party = {},
    money = 3000,
    lives = 3, -- 3 lives trial pool
    runState = "draft", -- draft | exploring | layer_clear_cutscene | endgame | victory | game_over
    eliteFour = eliteFour,
    champion = champion,
    endgame = {
      victoryRoad = { minLv = 59, maxLv = 62 },
      e4Index = 1,
      e4Defeated = { false, false, false, false },
      championDefeated = false,
    },
    history = {},
  }, Roguelike)

  return self
end

function Roguelike:getStarterChoices()
  local choices = {}
  local used = {}
  while #choices < 3 do
    local idx = self.random(1, #STARTERS)
    if not used[idx] then
      used[idx] = true
      local s = STARTERS[idx]
      choices[#choices + 1] = {
        species = s.id,
        name = s.name,
        level = 5,
        gen = s.gen,
        hp = 20,
        maxHp = 20,
      }
    end
  end
  return choices
end

function Roguelike:draftStarter(choiceIndex)
  if self.runState ~= "draft" then return false, "Not in draft state" end
  local choices = self:getStarterChoices()
  local picked = choices[choiceIndex] or choices[1]
  self.party = { picked }
  self.runState = "exploring"
  self.history[#self.history + 1] = { event = "starter_chosen", starter = picked }
  return true, picked
end

function Roguelike:defeatGymLeader()
  local layer = self.currentLayer
  if not layer or layer.gymLeader.defeated then return false, "Gym leader already defeated" end

  layer.gymLeader.defeated = true
  layer.layerGateUnlocked = true -- Option B: Unlocks the physical Layer Gate on the map
  self.history[#self.history + 1] = { event = "layer_boss_defeated", layer = layer.layer, leader = layer.gymLeader.name }

  -- Trigger milestone narrative cutscene
  self.runState = "layer_clear_cutscene"
  return true, layer.gymLeader
end

function Roguelike:dismissCutscene()
  if self.runState == "layer_clear_cutscene" then
    self.runState = "exploring"
    return true
  end
  return false
end

function Roguelike:useLayerGate()
  local layer = self.currentLayer
  if not layer.layerGateUnlocked then
    return false, "Layer Gate is locked! Defeat the Gym Leader first."
  end

  if self.currentLayerIndex < 8 then
    self.currentLayerIndex = self.currentLayerIndex + 1
    self.currentLayer = self.layers[self.currentLayerIndex]
    self.runState = "exploring"
    self.history[#self.history + 1] = { event = "advanced_layer", layer = self.currentLayerIndex }
    return true, self.currentLayerIndex
  else
    -- After Layer 8: advance to Endgame Gauntlet (Final Wild + E4)
    self.runState = "endgame"
    self.history[#self.history + 1] = { event = "reached_endgame" }
    return true, "endgame"
  end
end

function Roguelike:handleWhiteout()
  self.lives = self.lives - 1
  self.money = math.floor(self.money / 2)

  -- Revive party to full HP
  for _, mon in ipairs(self.party) do
    mon.hp = mon.maxHp or 20
  end

  if self.lives <= 0 then
    self.runState = "game_over"
    self.history[#self.history + 1] = { event = "run_failed_game_over" }
    return false, "Game Over: All trial lives exhausted"
  end

  self.runState = "exploring"
  self.history[#self.history + 1] = { event = "whiteout_respawn", remainingLives = self.lives }
  return true, string.format("Respawned at Center. Lives remaining: %d", self.lives)
end

function Roguelike:defeatEliteFourMember(index)
  if self.runState ~= "endgame" then return false, "Not in endgame" end
  self.endgame.e4Defeated[index] = true
  self.endgame.e4Index = index + 1
  return true, self.eliteFour[index]
end

function Roguelike:defeatChampion()
  if self.runState ~= "endgame" then return false, "Not in endgame" end
  for i = 1, 4 do
    if not self.endgame.e4Defeated[i] then return false, "Must defeat Elite Four first" end
  end
  self.endgame.championDefeated = true
  self.runState = "victory"
  self.history[#self.history + 1] = { event = "run_victory", champion = self.champion.name }
  return true, "Run Victory! Champion " .. self.champion.name .. " defeated!"
end

-- ---------------------------------------------------------------------------
-- Mod Entry Point & Unified Hooks
-- ---------------------------------------------------------------------------
return function(mod)
  if not (mod and mod.hooks) then return end

  local enabled = true
  local activeRun = nil

  -- 1. In-game Start Menu Entry: ROGUELIKE
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    items = (type(nextFn) == "function" and nextFn(game, items)) or items or {}
    if not enabled then return items end

    local modified = {}
    for i, itm in ipairs(items) do modified[i] = itm end

    modified[#modified + 1] = {
      id = "roguelike",
      label = "ROGUELIKE",
      onSelect = function()
        activeRun = Roguelike.newRun({
          seed = os.time(),
          game = game,
        })
        return activeRun
      end,
    }
    return modified
  end)

  -- 2. Universal Field Privileges & HM Bypass
  mod.hooks:wrap("fieldmove.eligibility", function(nextFn, moveId, ctx)
    if not enabled then return nextFn(moveId, ctx) end
    -- All HMs bypassed: any non-egg party member qualifies
    local party = (ctx and ctx.party) or (ctx and ctx.player and ctx.player.party)
    if type(party) == "table" then
      for _, mon in ipairs(party) do
        if not mon.isEgg and (tonumber(mon.hp) or 1) > 0 then return mon end
      end
    end
    return nextFn(moveId, ctx)
  end)

  -- 3. Level 40 Evolution Adjustments (Trade, Happiness, Day/Night)
  mod.hooks:wrap("pokemon.evolution_check", function(nextFn, mon, method, param)
    if not enabled then return nextFn(mon, method, param) end
    local level = tonumber(mon and mon.level) or 1
    if method == "trade" or method == "happiness" or method == "day" or method == "night" then
      if level >= 40 then return true end
    end
    return nextFn(mon, method, param)
  end)

  mod.exports = {
    Roguelike = Roguelike,
    newRun = function(opts)
      activeRun = Roguelike.newRun(opts)
      return activeRun
    end,
    getActiveRun = function() return activeRun end,
    restore = function()
      enabled = false
      activeRun = nil
    end,
  }

  if mod.log and mod.log.info then
    mod.log:info("Loaded Roguelike Layer-World Mode (Gen 3)")
  end
end
