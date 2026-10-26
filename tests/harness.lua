-- Headless harness shared by the suites. The engine runs from its checkout;
-- love.filesystem reads resolve against IMPORTS_ROOT (the player's save
-- directory or a staged copy) exactly as the game's save-dir lookups would.
-- Nothing may be written there: io.open in write mode, love.filesystem.write,
-- io.popen and os.execute all fail loudly.

package.path = "./?.lua;./?/init.lua;" .. package.path

local realOpen = io.open
io.open = function(path, mode)
  mode = mode or "r"
  if not mode:find("^r") then error("headless suite is read-only: " .. tostring(path), 2) end
  return realOpen(path, mode)
end
io.popen = function() return nil end
os.execute = function() return false end

local H = { total = 0 }

function H.check(value, message)
  H.total = H.total + 1
  if not value then error("FAIL: " .. message, 2) end
end

-- import_read / import_info come from tools/test.py: read-only and confined
-- to IMPORTS_ROOT.
local function readImport(path) return import_read(tostring(path)) end

-- Headless ImageData: raw RGBA string plus the paste the atlas merge uses.
local function imageData(w, h, _format, rgba)
  local d = { w = w, h = h, rgba = rgba or string.rep("\0", w * h * 4) }
  function d:getWidth() return self.w end
  function d:getHeight() return self.h end
  function d:getDimensions() return self.w, self.h end
  function d:getString() return self.rgba end
  function d:setPixel() end
  function d:paste(src, dx, dy, sx, sy, sw, sh)
    local rows = {}
    for y = 0, self.h - 1 do rows[y] = self.rgba:sub(y * self.w * 4 + 1, (y + 1) * self.w * 4) end
    for y = 0, sh - 1 do
      local line = src.rgba:sub(((sy + y) * src.w + sx) * 4 + 1, ((sy + y) * src.w + sx + sw) * 4)
      local row = rows[dy + y]
      rows[dy + y] = row:sub(1, dx * 4) .. line .. row:sub((dx + sw) * 4 + 1)
    end
    local out = {}
    for y = 0, self.h - 1 do out[#out + 1] = rows[y] end
    self.rgba = table.concat(out)
  end
  return d
end

love = {
  data = {
    compress = function(_, _, bytes, level) return deflate(bytes, level) end,
    decompress = function(_, _, bytes) return inflate(bytes) end,
  },
  image = { newImageData = imageData },
  graphics = {
    newQuad = function(...) return { quad = { ... } } end,
    newImage = function(data)
      return { data = data, setFilter = function() end,
        getDimensions = function() return data.w, data.h end,
        getWidth = function() return data.w end, getHeight = function() return data.h end }
    end,
  },
  filesystem = {
    read = function(path) return readImport(path) end,
    getInfo = function(path)
      local kind, size = import_info(tostring(path))
      if kind then return { type = kind, size = size } end
      return nil
    end,
    write = function(path) error("headless suite is read-only: " .. tostring(path), 2) end,
    getSaveDirectory = function() return IMPORTS_ROOT end,
  },
}

-- Engine warnings are noise here, except the loader explaining a skipped mod.
local Logger = require("src.core.Logger")
if Logger.warn then
  Logger.warn = function(fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    text = ok and text or tostring(fmt)
    if text:find("^mod ") then print("      [warn] " .. text) end
  end
end

-- A FireRed session hydrated from the imports through the engine's own paths.
function H.bootFireRed()
  require("src.core.GameVersion").set("firered")
  local Dataset = require("src.core.game3.dataset")
  local game = { data = {} }
  assert(Dataset.hydrate(game), "FireRed dataset did not hydrate from the imports")
  return game, Dataset
end

-- Render a layout through its tileset's layers to an RGBA table for write_png.
function H.render(layout, ts)
  local W, H2 = layout.width * 16, layout.height * 16
  local out = {}
  for i = 1, W * H2 * 4 do out[i] = 0 end
  local aw = ts.cols * 16
  for cy = 0, layout.height - 1 do
    for cx = 0, layout.width - 1 do
      local slot = ts.midToSlot[layout:midAt(cx, cy)] or 0
      local sx, sy = (slot % ts.cols) * 16, math.floor(slot / ts.cols) * 16
      for li, key in ipairs({ "imageData", "midImageData", "overImageData" }) do
        local data = ts[key]
        if data then
          for py = 0, 15 do
            for px = 0, 15 do
              local si = ((sy + py) * aw + (sx + px)) * 4
              if li == 1 or data.rgba:byte(si + 4) > 0 then
                local di = ((cy * 16 + py) * W + (cx * 16 + px)) * 4
                out[di + 1], out[di + 2], out[di + 3], out[di + 4] =
                  data.rgba:byte(si + 1), data.rgba:byte(si + 2), data.rgba:byte(si + 3), 255
              end
            end
          end
        end
      end
    end
  end
  return W, H2, out
end

return H
