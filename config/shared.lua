--- @author DemiAutomatic
--- @file config/shared.lua
--- @description Configuration both halves read, shipped to every client.
--- @field SERVER_NAME {string} Shown in the launcher and in player-facing text.
--- @field LOCALE {string} Catalogue for player-facing text; server logs stay English.
--- @field MONEY {table} Money types and the default one.
--- @field MONEY.TYPES {table<string, integer>} Durable money type names, each with its starting amount.
--- @field MONEY.TYPES.EDDIES {integer} Carried on the person, losable.
--- @field MONEY.TYPES.BANK {integer} Held by a bank, not losable.
--- @field MONEY.DEFAULT {string} Type a payment falls back to when none is named.
--- @field CHARACTERS {table} Character creation bounds.
--- @field CHARACTERS.NAME {table} Bounds on each half of a character name.
--- @field CHARACTERS.NAME.MIN {integer} Fewest characters, not bytes.
--- @field CHARACTERS.NAME.MAX {integer} Most characters, not bytes.
--- @field APPEARANCE {table} Limits on a stored face.
--- @field APPEARANCE.GAME_BUILDS {table<string, boolean>} Game builds a stored face may be read back into.
--- @field APPEARANCE.MAX_JSON_BYTES {integer} Largest encoded appearance document accepted, in bytes.
--- @field DEFAULT_SPAWN {table} Where a character with no stored position is placed.
--- @field DEFAULT_SPAWN.SET {boolean} Nobody is placed there until this is true.
--- @field DEFAULT_SPAWN.X {number}
--- @field DEFAULT_SPAWN.Y {number}
--- @field DEFAULT_SPAWN.Z {number}
--- @field DEFAULT_SPAWN.HEADING {number}
--- @field NOTIFY_POSITION {string} One of the seven toast positions; unknown values warn.

OPX.Config.SHARED = {
	SERVER_NAME = 'OPX//77',

	LOCALE = 'en',

	MONEY = {
		TYPES = {
			EDDIES = 500,
			BANK = 5000,
		},

		DEFAULT = 'EDDIES',
	},

	CHARACTERS = {
		NAME = { MIN = 2, MAX = 32 },
	},

	APPEARANCE = {
		GAME_BUILDS = { ['2.31'] = true },

		MAX_JSON_BYTES = 49152,
	},

	DEFAULT_SPAWN = {
		SET = false,
		X = 0.0,
		Y = 0.0,
		Z = 0.0,
		HEADING = 0.0,
	},

	NOTIFY_POSITION = 'top_right',
}
