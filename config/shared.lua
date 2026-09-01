-- Shipped to every client in the signed resource set: everything here is public. Credentials,
-- webhooks and admin identifiers belong in config/server.lua.

OPX.Config.SHARED = {
  SERVER_NAME = "OPX//77", -- shown in the launcher and in player-facing text

  LOCALE = "fr", -- language for player-facing text; server logs stay in English
  LOG_LEVEL = "info", -- "debug" | "info" | "warn" | "error" | "silent"

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

  -- where a character with no stored position is placed. The zeros are not a real Night City
  -- coordinate; run `opx77.here` in game to print your own in this exact shape. Nobody is
  -- placed until SET is true.
  DEFAULT_SPAWN = {
    SET = false,
    X = 0.0,
    Y = 0.0,
    Z = 0.0,
    HEADING = 0.0,
  },

  -- "top" | "top-right" | "top-left" | "bottom" | "bottom-right" | "bottom-left"
  NOTIFY_POSITION = "top-right",
}
