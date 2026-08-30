--- Operator configuration: the one file a server owner edits. Everything has
--- a working default, so an untouched checkout boots.
---
--- Ships to every client, so never put a secret here.

SynkConfig = {
  --- Language for player-facing text. Falls back to `en` for any missing key.
  locale = "fr",

  --- debug | info | warn | error | silent
  logLevel = "info",

  characters = {
    --- How many characters one account may hold.
    max = 3,
    name = { min = 2, max = 32 },
  },

  entry = {
    --- Below `gateMs` on purpose, so SYNK gives up first and can say why
    --- rather than being timed out with the player left without a puppet.
    pipelineMs = 45000,

    --- What we declare to Open77.ready.participate.
    gateMs = 60000,
  },
}

return SynkConfig
