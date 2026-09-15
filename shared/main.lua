--- @author DemiAutomatic
--- @file shared/main.lua
--- @description Creates the OPX namespace, its event names and operation names.

OPX = OPX or {}

--- @author DemiAutomatic
--- @type {string}
--- @description The core's version, answered by both GetVersion exports.
OPX.VERSION = '0.6.0'

--- @author DemiAutomatic
--- @type {boolean}
--- @description True in the server VM, read off a server-only global.
OPX.IsServer = rawget(_G, 'TriggerClientEvent') ~= nil

--- @author DemiAutomatic
--- @type {boolean}
--- @description True in a client VM, read off a client-only global.
OPX.IsClient = rawget(_G, 'TriggerServerEvent') ~= nil

--- @author DemiAutomatic
--- @type {table}
--- @description The configuration roots filled by the config files.
OPX.Config = OPX.Config or {}

--- @author DemiAutomatic
--- @type {table<string, table<string, string>>}
--- @description Every event name the core raises or handles, by channel.
OPX.Events = {
	Platform = {
		PLAYER_CONNECTED = 'onPlayerConnected',
		PLAYER_READY = 'onPlayerReady',
		RESOURCE_START = 'onClientResourceStart',
		RESOURCE_STOP = 'onClientResourceStop',
		WORLD_READY = 'open77:worldReady',
	},

	Client = {
		CHARACTERS = 'opx77:client:characters',
		PLAYER_LOADED = 'opx77:client:playerLoaded',
		PLAYER_UNLOADED = 'opx77:client:playerUnloaded',
		SET_PLAYER_DATA = 'opx77:client:setPlayerData',
		MONEY_CHANGE = 'opx77:client:onMoneyChange',
		JOB_UPDATE = 'opx77:client:onJobUpdate',
		GANG_UPDATE = 'opx77:client:onGangUpdate',
		APPEARANCE_UPDATE = 'opx77:client:onAppearanceUpdate',
		CLOTHING_UPDATE = 'opx77:client:onClothingUpdate',
		NOTIFY = 'opx77:client:notify',
		ANSWER = 'opx77:client:commandAnswer',
	},

	Server = {
		READY = 'opx77:server:ready',
		SELECT_CHARACTER = 'opx77:server:selectCharacter',
		CREATE_CHARACTER = 'opx77:server:createCharacter',
		DELETE_CHARACTER = 'opx77:server:deleteCharacter',
		REPORT_POSITION = 'opx77:server:reportPosition',
		SAVE_APPEARANCE = 'opx77:server:saveAppearance',
		SAVE_CLOTHING = 'opx77:server:saveClothing',
		SPAWN_VEHICLE = 'opx77:server:spawnVehicle',
		STORE_VEHICLE = 'opx77:server:storeVehicle',
	},

	Local = {
		CHARACTERS_READY = 'opx77:client:charactersReady',
		PLAYER_LOADED = 'opx77:client:onPlayerLoaded',
		PLAYER_UNLOADED = 'opx77:client:onPlayerUnloaded',
		PLAYER_DATA_CHANGED = 'opx77:client:playerDataChanged',
		MONEY_CHANGED = 'opx77:client:moneyChanged',
		JOB_CHANGED = 'opx77:client:jobChanged',
		GANG_CHANGED = 'opx77:client:gangChanged',
		APPEARANCE_SAVED = 'opx77:client:appearanceSaved',
		CLOTHING_SAVED = 'opx77:client:clothingSaved',
		REFUSED = 'opx77:client:refused',
	},

	Internal = {
		PLAYER_LOADED = 'opx77:player:loaded',
		PLAYER_UNLOADED = 'opx77:player:unloaded',
		MONEY_CHANGE = 'opx77:player:moneyChange',
		JOB_UPDATE = 'opx77:player:jobUpdate',
		GANG_UPDATE = 'opx77:player:gangUpdate',
		APPEARANCE_CHANGE = 'opx77:player:appearanceChange',
		CLOTHING_CHANGE = 'opx77:player:clothingChange',
		PAYCHECK = 'opx77:player:paycheck',
		CHARACTER_DELETED = 'opx77:player:characterDeleted',
	},
}

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description Which request a refusal answers, named after its server event.
OPX.Operations = {
	ENTRY = 'entry',
	ROSTER = 'ready',
	SELECT_CHARACTER = 'selectCharacter',
	CREATE_CHARACTER = 'createCharacter',
	DELETE_CHARACTER = 'deleteCharacter',
	SAVE_APPEARANCE = 'saveAppearance',
	SAVE_CLOTHING = 'saveClothing',
	SPAWN_VEHICLE = 'spawnVehicle',
	STORE_VEHICLE = 'storeVehicle',
}
