-- Seeded generator (xorshift32) so a run's world is reproducible from its seed
-- and never consumes the game's own RNG.

local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
  local s = math.floor(tonumber(seed) or 1) % 4294967296
  if s == 0 then s = 2463534242 end
  return setmetatable({ s = s }, Rng)
end

local bxor, lshift, rshift = bit.bxor, bit.lshift, bit.rshift

function Rng:next()
  local s = self.s
  s = bxor(s, lshift(s, 13))
  s = bxor(s, rshift(s, 17))
  s = bxor(s, lshift(s, 5))
  s = s % 4294967296
  self.s = s
  return s / 4294967296
end

-- integer in [a, b]
function Rng:int(a, b)
  return a + math.floor(self:next() * (b - a + 1))
end

function Rng:chance(p) return self:next() < p end

function Rng:pick(list) return list[self:int(1, #list)] end

-- index into `weights` drawn proportionally
function Rng:weighted(weights, total)
  local r = self:next() * total
  for i, w in ipairs(weights) do
    r = r - w
    if r <= 0 then return i end
  end
  return #weights
end

function Rng:fork() return Rng.new(self:int(1, 2147483646)) end

return Rng
