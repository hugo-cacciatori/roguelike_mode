-- Hand-curated composite maps. Each part is a real source map (read from the
-- player's import of that game); each chunk copies a rectangle of one part to
-- a position on the composite grid. `entry` and `exit` are composite cells the
-- integrity tests require to be connected by walkable ground.

return {
  composites = {
    {
      id = "FR_RL_L1_FOREST",
      width = 48, height = 60,
      parts = {
        { version = "firered", map = "FR_VIRIDIAN_FOREST" },
        { version = "emerald", map = "EM_PETALBURG_WOODS" },
      },
      chunks = {
        { part = 1, src = { x = 3, y = 32, w = 48, h = 30 }, at = { x = 0, y = 0 } },
        { part = 2, src = { x = 0, y = 14, w = 48, h = 30 }, at = { x = 0, y = 30 } },
      },
      -- top opening of the Viridian Forest chunk; southern path of the
      -- Petalburg Woods chunk (row 54, last walkable row above the arrow warps)
      entry = { x = 38, y = 0 },
      exit = { x = 16, y = 54 },
    },
  },
}
