-- Roguelike Layer-World Mode
-- Layers are composite maps spliced from real FireRed and Emerald maps, read
-- from the player's own imports. Modules live in lib/ and data/ and share the
-- table `R`, loaded through mod:read so the mod ships as plain source files.

local MODULES = { "lib/sources", "lib/catalog", "lib/atlas", "lib/splice", "lib/run", "lib/saves" }

return function(mod)
  local R = { mod = mod, data = {} }

  local function loadFile(rel)
    local source = assert(mod:read(rel .. ".lua"), "roguelike_mode: missing " .. rel .. ".lua")
    local chunk = assert(load(source, "@" .. mod.path .. "/" .. rel .. ".lua"))
    return chunk(R)
  end

  for _, name in ipairs({ "chunks", "starters", "bosses" }) do
    R.data[name] = loadFile("data/" .. name)
  end
  for _, rel in ipairs(MODULES) do
    R[rel:match("[^/]+$")] = loadFile(rel)
  end

  R.atlas.install()
  -- While enabled the mod owns the game: New Game starts a run and saves go
  -- to the run's own slot (spec §7.E). Switch slots now, before Game3 checks
  -- whether Continue exists.
  R.run.install(mod)
  R.saves.install()
  R.saves.installHooks(mod)

  local function gameOf(payload)
    local game = type(payload) == "table" and (payload.game or payload) or nil
    return type(game) == "table" and type(game.data) == "table" and game or nil
  end

  -- Composite maps are registered against the live game's map table. Every
  -- entry point that can reach a map calls ensure, which is idempotent.
  local function ensure(payload)
    local game = gameOf(payload)
    if game then R.splice.registerAll(game) end
  end
  mod.events:on("game.ready", function(payload)
    ensure(payload)
    local game = gameOf(payload)
    if game then R.saves.refreshTitle(game) end
  end)

  mod.exports = {
    R = R,
    ensure = ensure,
    restore = function()
      R.saves.restore()
      R.splice.unregisterAll()
      R.atlas.uninstall()
    end,
  }
end
