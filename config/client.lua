-- Client-only, so nothing here is authoritative: a modified client can change any of it and
-- the server re-derives anything that matters.

OPX.Config.CLIENT = {
  -- how often the client reports its position for the autosave, in ms. The server re-reads
  -- the authoritative position before writing, so this only decides how fresh the hint is.
  POSITION_REPORT_MS = 5000,

  CHARACTER = {
    -- how often the bootstrap phase is polled while the selection screen is up, in ms
    BOOTSTRAP_POLL_MS = 250,

    -- how long to wait for the native character creator to hand back a result, in ms
    CREATOR_TIMEOUT_MS = 300000,

    -- open Cyberpunk's own character creator for a new character. Needs the
    -- `player.appearance.edit` permission; off means the default body and your own step.
    USE_NATIVE_CREATOR = true,
  },
}
