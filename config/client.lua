-- Client-only, so nothing here is authoritative: a modified client can change any of it and
-- the server re-derives anything that matters.

OPX.Config.CLIENT = {
  -- how often the client reports its position for the autosave, in ms. The server re-reads
  -- the authoritative position before writing, so this only decides how fresh the hint is.
  POSITION_REPORT_MS = 5000,
}
