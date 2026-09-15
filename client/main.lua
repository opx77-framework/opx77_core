--- @author DemiAutomatic
--- @file client/main.lua
--- @description Client mirror of the server's state, and the announce to it.

--- @author DemiAutomatic
--- @type {PlayerData|table}
--- @description The server's PlayerData, mirrored; empty until a character loads.
OPX.PlayerData = {}

--- @author DemiAutomatic
--- @type {table}
--- @description The roster the server last sent: list, slots and origins.
OPX.Characters = {
	list = {},
	slots = 0,
	origins = {},
}

--- @author DemiAutomatic
--- @type {boolean}
--- @description True between playerLoaded and playerUnloaded.
OPX.IsLoggedIn = false

--- @author DemiAutomatic
--- @method OPX.Announce
--- @description Announces this client to the server so it resends the roster.
function OPX.Announce()
	TriggerServerEvent(OPX.Events.Server.READY)
end

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Announces the client once the core's client half has started.
--- @param name {string}
AddEventHandler(OPX.Events.Platform.RESOURCE_START, function(name)
	if name ~= GetCurrentResourceName() then return end
	Open77.log.info(('[client] opx77_core %s client ready'):format(OPX.VERSION))
	OPX.Announce()
end)

--- @author DemiAutomatic
--- @event open77:worldReady
--- @description Announces the client again once the world is up.
AddEventHandler(OPX.Events.Platform.WORLD_READY, function()
	OPX.Announce()
end)
