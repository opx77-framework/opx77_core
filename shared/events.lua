--- Event names, in one place.
---
--- Both runtimes require this file, so a rename cannot leave the client
--- listening for a string the server no longer sends. Nothing in SYNK types an
--- event name inline.
---
--- Naming: `synk:<area>:<verb>`. The `synk:` prefix keeps our traffic
--- distinguishable from the platform's own `open77:` events in a log.

return {
  --- Platform events we react to. Names owned by Open2077, not by us.
  platform = {
    playerConnected = "onPlayerConnected",
    playerReady = "onPlayerReady",
    resourceStart = "onClientResourceStart",
    resourceStop = "onClientResourceStop",
    worldReady = "open77:worldReady",
  },

  --- server -> client
  toClient = {
    session = "synk:session",
    characters = "synk:characters:list",
    entered = "synk:entered",
    notify = "synk:notify",
  },

  --- client -> server. Every one of these is attacker-controlled input and is
  --- validated before use; `source` is the only trustworthy field.
  toServer = {
    ready = "synk:client:ready",
    selectCharacter = "synk:character:select",
    createCharacter = "synk:character:create",
    reportPosition = "synk:position:report",
  },

  --- Resource-local, between SYNK modules. These never cross the wire and
  --- never leave this resource's Lua state.
  internal = {
    sessionOpened = "synk:internal:sessionOpened",
    sessionClosed = "synk:internal:sessionClosed",
    characterLoaded = "synk:internal:characterLoaded",
  },
}
