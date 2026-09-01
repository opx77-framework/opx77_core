--- Client state: presentation and intent only. Anything reported from here is a hint the
--- server re-derives. This half draws nothing -- pixels belong in satellite client resources
--- reaching it through `Open77.exports.call("opx77_core", ...)`.

local log = OPX.Log.scope("client")

--- The server's copy, mirrored. Empty until a character is loaded.
--- Nothing captures this into a local: a handler replaces the table wholesale on login.
---@type PlayerData|table
OPX.PlayerData = {}

--- The selection roster: what the server last sent.
OPX.Characters = {
  ---@type CharacterSummary[]
  list = {},
  ---@type integer
  slots = 0,
  ---@type table<string, table>
  origins = {},
}

--- True between `playerLoaded` and `playerUnloaded`.
OPX.IsLoggedIn = false

--- Announces this client to the server. Called on resource start, which is what makes a core
--- reload survivable: the server's roster is empty and `onPlayerConnected` does not re-fire.
function OPX.Announce()
  TriggerServerEvent(OPX.Events.Server.READY)
end

AddEventHandler(OPX.Events.Platform.RESOURCE_START, function(name)
  if name ~= GetCurrentResourceName() then return end
  OPX.Log.setLevel(OPX.Config.SHARED.LOG_LEVEL)
  log.info(("opx77_core %s client ready"):format(OPX.VERSION))
  OPX.Announce()
end)

AddEventHandler(OPX.Events.Platform.WORLD_READY, function()
  -- announced again: a client can start before the world is up, and the server throttles this
  OPX.Announce()
end)
