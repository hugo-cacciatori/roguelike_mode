-- Roguelike Layer-World Mode
-- Layers are composite maps spliced from real FireRed and Emerald maps, read
-- from the player's own imports. Modules live in lib/ and data/ and share the
-- table `R`, loaded through mod:read so the mod ships as plain source files.

local MODULES = { "lib/sources", "lib/catalog", "lib/atlas", "lib/splice" }

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

  -- Composite maps are registered against the live game's map table. Every
  -- entry point that can reach a map calls ensure, which is idempotent.
  local function ensure(payload)
    local game = type(payload) == "table" and (payload.game or payload) or nil
    if type(game) == "table" and type(game.data) == "table" then
      R.splice.registerAll(game)
    end
  end
  mod.events:on("game.ready", ensure)

  mod.exports = {
    R = R,
    ensure = ensure,
    restore = function()
      R.splice.unregisterAll()
      R.atlas.uninstall()
    end,
  }
end
