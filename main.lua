-- Roguelike Layer-World Mode
-- Every area of a run is generated: a functional layout painted with tiles
-- from FireRed and Emerald, whose classes and side-by-side rules are learned
-- from the player's own imports. No base-game map is used. Modules live in
-- lib/ and data/ and share the table `R`, loaded through mod:read.

local MODULES = {
  "lib/sources", "lib/catalog", "lib/atlas", "lib/rng", "lib/corpus",
  "lib/layout", "lib/paint", "lib/generate", "lib/wild", "lib/world", "lib/run", "lib/saves",
}

return function(mod)
  local R = { mod = mod, data = {} }

  local function loadFile(rel)
    local source = assert(mod:read(rel .. ".lua"), "roguelike_mode: missing " .. rel .. ".lua")
    local chunk = assert(load(source, "@" .. mod.path .. "/" .. rel .. ".lua"))
    return chunk(R)
  end

  for _, name in ipairs({ "starters", "bosses" }) do
    R.data[name] = loadFile("data/" .. name)
  end
  for _, rel in ipairs(MODULES) do
    R[rel:match("[^/]+$")] = loadFile(rel)
  end

  R.atlas.install()
  R.wild.install()
  -- While enabled the mod owns the game: New Game starts a run and saves go
  -- to the run's own slot (spec §7.E). Switch slots now, before Game3 checks
  -- whether Continue exists.
  R.run.install(mod)
  R.saves.install()
  R.saves.installHooks(mod)

  mod.events:on("game.ready", function(payload)
    local game = type(payload) == "table" and (payload.game or payload) or nil
    if type(game) == "table" and type(game.data) == "table" then
      R.run.game = game
      R.saves.refreshTitle(game)
    end
  end)

  mod.exports = {
    R = R,
    restore = function()
      R.saves.restore()
      R.world.unregisterAll()
      R.wild.uninstall()
      R.atlas.uninstall()
      R.run.game = nil
    end,
  }
end
