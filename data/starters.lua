-- Starter draft pool (spec §5.A): all Gen 1–3 starters, plus the optional
-- specials. Species are engine ids; the draft gives them at `level`.

return {
  level = 5,
  pool = {
    "BULBASAUR", "CHARMANDER", "SQUIRTLE",
    "CHIKORITA", "CYNDAQUIL", "TOTODILE",
    "TREECKO", "TORCHIC", "MUDKIP",
  },
  specials = { "PIKACHU", "EEVEE" },
}
