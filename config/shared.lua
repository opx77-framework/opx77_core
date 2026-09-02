-- Shipped to every client in the signed resource set: everything here is public. Credentials,
-- webhooks and admin identifiers belong in config/server.lua.

OPX.Config.SHARED = {
  SERVER_NAME = "OPX//77", -- shown in the launcher and in player-facing text

  LOCALE = "en", -- language for player-facing text; server logs stay in English

  MONEY = {
    -- durable names: they become keys in the `money` JSON column, so adding one is free and
    -- renaming one orphans every balance already stored under the old name
    TYPES = {
      EDDIES = 500,   -- carried on the person, losable
      BANK = 5000,    -- held by a bank, not losable
    },

    DEFAULT = "EDDIES", -- the type a payment falls back to when a caller does not name one
  },

  CHARACTERS = {
    NAME = { MIN = 2, MAX = 32 }, -- counted in characters, not bytes
  },

  APPEARANCE = {
    -- Which catalogue a stored face may be read back into. A snapshot captured on another
    -- build is refused; widening this does not make an old one fit.
    GAME_BUILDS = { ["2.31"] = true },

    -- The largest appearance document the core will accept, in bytes, measured on the
    -- encoded JSON. A canonical snapshot of 256 options is far below it.
    MAX_JSON_BYTES = 49152,
  },

  -- where a character with no stored position is placed. Nobody is placed until SET is true;
  -- run `opx77.here` in game to print your own coordinate in this exact shape.
  DEFAULT_SPAWN = {
    SET = false,
    X = 0.0,
    Y = 0.0,
    Z = 0.0,
    HEADING = 0.0,
  },

  -- middle_left | top_left | top_center | top_right | bottom_left | bottom_center |
  -- bottom_right. An unknown value is warned about and still sent.
  NOTIFY_POSITION = "top_right",
}
