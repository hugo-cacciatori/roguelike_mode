-- Read-only access to the player's own imports. Every byte the mod uses comes
-- from <version>/data/generated/gba/ under the save directory, read through
-- the engine's CacheFs so portable installs resolve the same way. Nothing in
-- this module writes.

local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")

local Sources = {}

local GBA = "data/generated/gba/"
local luaMemo = {}

local function prefix(version)
  local p = GameVersion.cachePrefix(version)
  assert(type(p) == "string" and p ~= "", "roguelike_mode: no cache prefix for " .. tostring(version))
  return p
end

-- Bytes of `rel` (relative to the version's gba cache), decoded, or nil.
function Sources.read(version, rel)
  return (CacheFs.readAt(prefix(version) .. GBA .. rel))
end

function Sources.exists(version, rel)
  return Sources.read(version, rel) ~= nil
end

-- A generated Lua table, evaluated without an environment and memoized.
function Sources.loadLua(version, rel)
  local key = version .. "|" .. rel
  local hit = luaMemo[key]
  if hit ~= nil then return hit or nil end
  local value = false
  local src = Sources.read(version, rel)
  if src then
    local chunk = load(src, "@" .. version .. "/" .. rel, "t", {})
    local ok, result = pcall(chunk)
    if ok and result ~= nil then value = result end
  end
  luaMemo[key] = value
  return value or nil
end

-- Whether a version has been imported (its cache metadata is readable).
function Sources.available(version)
  return Sources.exists(version, "meta.json")
end

-- A cache object in the shape the engine's asset decoders expect, rooted at
-- the version's gba cache. It never writes.
function Sources.cacheFor(version)
  return {
    read = function(_, rel) return Sources.read(version, rel) end,
    exists = function(_, rel) return Sources.exists(version, rel) end,
  }
end

function Sources.forget()
  luaMemo = {}
end

return Sources
