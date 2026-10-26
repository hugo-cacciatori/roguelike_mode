-- Generated encounters, through the real loader and the engine's own
-- encounter step (Encounters.onStep) on a generated area.
local H = dofile(MOD_ROOT .. "/tests/harness.lua")
local check = H.check

local game = H.bootFireRed()
local Sdk = require("tests.modkit.sdk")
local Runtime = require("src.mods.Runtime")
local Pokemon = require("src.core.game3.pokemon")
local Encounters = require("src.core.game3.encounters")
local EngineRng = require("src.core.game3.rng")
local Map = require("src.core.game3.map")

local run = Sdk.loadMods({ "mods/roguelike_mode" },
  { fs = Sdk.memfs(MOD_FILES), generation = 3, data = game.data })
check(#run.errors == 0, "load errors: " .. table.concat(run.errors, "\n"))
local exports = run.loader.exports.roguelike_mode
local R = exports.R
local Wild = R.wild
Runtime.emit("game.ready", { game = game })

-- Gen 3 type ids (pokefirered/include/constants/pokemon.h).
local T = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }
local FIT = {
  forest = { T.BUG, T.GRASS, T.NORMAL, T.FLYING, T.POISON, T.ELECTRIC, T.DARK },
  cave = { T.ROCK, T.GROUND, T.POISON, T.FIGHTING, T.GHOST, T.DARK, T.STEEL, T.FIRE, T.ICE, T.PSYCHIC },
  sea = { T.WATER },
}
local function fits(species, env)
  local types = Pokemon.types(species) or {}
  for _, t in ipairs(types) do
    for _, ok in ipairs(FIT[env]) do if tonumber(t) == ok then return true end end
  end
  return false
end

-- 1. Learned pools match their environment's types.
local pools = Wild.pools()
for env, kinds in pairs({ forest = { "land" }, cave = { "land" }, sea = { "water", "fishing" } }) do
  for _, kind in ipairs(kinds) do
    local pool = pools[env] and pools[env][kind]
    check(pool and #pool.list >= 3, ("%s %s pool learned from both games"):format(env, kind))
    local fit, total = 0, 0
    for _, f in ipairs(pool.list) do
      total = total + f.weight
      if fits(f.base, env) then fit = fit + f.weight end
    end
    check(fit / total >= 0.8, ("%s %s pool fits the environment (%.0f%%)"):format(env, kind, 100 * fit / total))
  end
end

-- 2. Stage model agrees with known evolutions.
local function id(name) return Pokemon.speciesFromName(name) end
check(Wild.baseOf(id("METAPOD")) == id("CATERPIE"), "Metapod folds into the Caterpie family")
check(Wild.baseOf(id("PIKACHU")) == id("PIKACHU"), "Pikachu is its own wild base (Pichu is never wild)")
check(Wild.minLevel(id("METAPOD")) == 7 and Wild.minLevel(id("GOLBAT")) == 22, "level evolutions set the minimum")
check(Wild.minLevel(id("CROBAT")) >= 40, "friendship evolutions follow the Lv. 40 rule")
check(Wild.cap(id("CATERPIE")) <= 11, "Caterpie is capped near its evolution level")
check(Wild.formAt(id("CATERPIE"), 30) == id("BUTTERFREE"), "a Lv. 30 Caterpie family member is Butterfree")
check(Wild.formAt(id("ZUBAT"), 10) == id("ZUBAT"), "a Lv. 10 Zubat stays Zubat")

-- 3. Generated tables: in band, stage-coherent, fitting their environment.
for _, env in ipairs({ "forest", "cave", "sea", "route" }) do
  for layer = 1, #Wild.BANDS do
    for seed = 1, 3 do
      local band = Wild.BANDS[layer]
      local t = Wild.table(env, layer, R.rng.new(seed * 97 + layer))
      local label = ("%s L%d seed %d"):format(env, layer, seed)
      check(next(t) ~= nil, label .. ": has a table")
      for kind, k in pairs(t) do
        check(k.rate >= 1, label .. " " .. kind .. ": positive rate")
        local expected = kind == "land" and 12 or kind == "water" and 5 or 10
        check(#k.slots == expected, ("%s %s: %d slots"):format(label, kind, expected))
        for i, slot in ipairs(k.slots) do
          local where = ("%s %s slot %d (%s %d-%d)"):format(label, kind, i, Pokemon.name(slot.species),
            slot.minLevel, slot.maxLevel)
          check(slot.minLevel >= band[1] and slot.maxLevel <= band[2] and slot.minLevel <= slot.maxLevel,
            where .. ": inside the layer band")
          check(Wild.coherent(slot.species, slot.minLevel) and Wild.coherent(slot.species, slot.maxLevel),
            where .. ": evolution stage fits the level")
        end
      end
    end
  end
end
local a, b = Wild.table("forest", 3, R.rng.new(5)), Wild.table("forest", 3, R.rng.new(5))
local same = true
for i, slot in ipairs(a.land.slots) do
  same = same and slot.species == b.land.slots[i].species and slot.minLevel == b.land.slots[i].minLevel
end
check(same, "tables are deterministic per seed")

-- 4. The engine's own encounter step rolls a generated area's table.
local def = R.world.build({ version = 2, seed = 4242, layer = 2 }, game)[1]
local tbl = def.roguelike.encounters
check(tbl and tbl.land, "generated area carries a land table")
check(Encounters.tableFor(def.id) ~= nil, "engine resolves the area's table")
Encounters.loadFromMod(nil) -- the engine reloading its tables
check(Encounters.tableFor(def.id) ~= nil, "table survives Encounters.loadFromMod")
check(Map.load(nil, game, def.id, { depth1Connections = false }), "area loads")
local cell
for y = 0, def.height - 1 do
  for x = 0, def.width - 1 do
    if not cell and Encounters.terrainAt(x, y) == "land" then cell = { x = x, y = y } end
  end
end
check(cell ~= nil, "painted grass is encounter ground")
local allowed = {}
for _, slot in ipairs(tbl.land.slots) do
  allowed[slot.species] = allowed[slot.species] or {}
  for l = slot.minLevel, slot.maxLevel do allowed[slot.species][l] = true end
end
EngineRng.seedNewGame({ seed = 12345 })
local seen, outside = 0, 0
for _ = 1, 30000 do
  Encounters.resetRateModifiers()
  local enc = Encounters.onStep(def.id, nil, { x = cell.x, y = cell.y, enterFromOther = true })
  if enc then
    seen = seen + 1
    if not (allowed[enc.species] and allowed[enc.species][enc.level] and Wild.coherent(enc.species, enc.level)) then
      outside = outside + 1
    end
  end
end
check(seen >= 50, ("real encounters happened (%d)"):format(seen))
check(outside == 0, ("every rolled encounter is from the table and coherent (%d outside)"):format(outside))

-- 5. Rollback removes the tables and the reload guard.
exports.restore()
check(Encounters.tableFor(def.id) == nil, "restore removes generated tables")
run.release()

print(("PASS wild: %d assertions (%d real encounters)"):format(H.total, seen))
