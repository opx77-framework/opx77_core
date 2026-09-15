--- @author DemiAutomatic
--- @file config/server.lua
--- @description Server-only configuration, never distributed to a client.
--- @field AUTOSAVE_SECONDS {integer} How often a loaded character is written back.
--- @field MONEY {table} Negative balances and paychecks.
--- @field MONEY.ALLOW_NEGATIVE {table<string, boolean>} Money types that may go below zero.
--- @field MONEY.ALLOW_NEGATIVE.BANK {boolean}
--- @field MONEY.PAYCHECK_MINUTES {integer} Minutes between paychecks; 0 disables them.
--- @field MONEY.PAYCHECK_REQUIRES_DUTY {boolean} Pay only a player who is on duty.
--- @field MONEY.PAYCHECK_TYPE {string} Money type a salary lands in; unknown falls back to SHARED.MONEY.DEFAULT.
--- @field CHARACTERS {table} Slots, row ceiling and extra cascades.
--- @field CHARACTERS.DEFAULT_SLOTS {integer} How many characters one account may hold.
--- @field CHARACTERS.SLOTS_BY_USER {table<string, integer>} Per-account slot overrides, keyed by userId.
--- @field CHARACTERS.ROW_CEILING {integer} Lifetime character rows per account; keep well above DEFAULT_SLOTS.
--- @field CHARACTERS.CASCADE_TABLES {table[]} Extra { TABLE, COLUMN } pairs deleted with a character.
--- @field ENTRY {table} The readiness gate and the selection bucket.
--- @field ENTRY.GATE_MS {integer} Liveness interval declared to the gate, clamped 1000..600000.
--- @field ENTRY.PIPELINE_MS {integer} Selection deadline, below GATE_MS; ceiling of SELECTION_MS.
--- @field ENTRY.BUCKET {table} The routing bucket a player without a character waits in.
--- @field ENTRY.BUCKET.ISOLATE {boolean} One bucket per player; false moves nobody.
--- @field ENTRY.BUCKET.BASE {integer} A player's bucket is BASE plus their id, up to BASE+65535.
--- @field ENTRY.BUCKET.WORLD {integer} The shared world bucket characters are placed in.
--- @field ENTRY.BUCKET.POPULATION {boolean} Ambient population in a selection bucket.
--- @field ENTRY.BUCKET.LOCKDOWN {string|false} inactive, relaxed, strict or full; false leaves it alone.
--- @field PLAYER {table} Starting metadata and default groups.
--- @field PLAYER.STARTING_METADATA {table} Initial metadata; the core reads health, armor, isDead, inLastStand.
--- @field PLAYER.DEFAULT_JOB {string} Must exist in data/jobs.lua.
--- @field PLAYER.DEFAULT_GANG {string} Must exist in data/gangs.lua.
--- @field CONFLICTING_PLACERS {string[]} Resources that also place players, warned about at boot.
--- @field EXPORTS {table} Who may call the server exports.
--- @field EXPORTS.READ {string|table<string, boolean>} "*" for every server resource, or a set of names.
--- @field EXPORTS.CALLERS {table<string, table>} Resources granted scopes for the write exports.
--- @field EXPORTS.MAX_RESULT_BYTES {integer} Heaviest encoded answer, in bytes, under the host's 48 KiB.
--- @field INVENTORY {table} Bounds on what the inventory storage exports accept.
--- @field INVENTORY.MAX_SLOTS {integer} Slots one container may have.
--- @field INVENTORY.MAX_WEIGHT {integer} Grams; the column is INT UNSIGNED.
--- @field INVENTORY.MAX_METADATA_BYTES {integer} One stack's encoded metadata, in bytes.
--- @field INVENTORY.PAGE_ROWS {integer} Stacks one read answers at most.
--- @field INVENTORY.LINKED_KINDS {table<string, string>} Kinds owned by a citizen id or a plate.

OPX.Config.SERVER = {
	AUTOSAVE_SECONDS = 300,

	MONEY = {
		ALLOW_NEGATIVE = { BANK = true },

		PAYCHECK_MINUTES = 10,
		PAYCHECK_REQUIRES_DUTY = true,

		PAYCHECK_TYPE = 'BANK',
	},

	CHARACTERS = {
		DEFAULT_SLOTS = 3,

		SLOTS_BY_USER = {},

		ROW_CEILING = 60,

		CASCADE_TABLES = {},
	},

	ENTRY = {
		GATE_MS = 300000,

		PIPELINE_MS = 240000,

		BUCKET = {
			ISOLATE = true,

			BASE = 77000,

			WORLD = 0,

			POPULATION = false,
			LOCKDOWN = 'relaxed',
		},
	},

	PLAYER = {
		STARTING_METADATA = {
			health = 100,
			armor = 0,
			isDead = false,
			inLastStand = false,
		},

		DEFAULT_JOB = 'unemployed',
		DEFAULT_GANG = 'none',
	},

	CONFLICTING_PLACERS = { 'open77_playerstate', 'freeroam', 'pursuit', 'race' },

	EXPORTS = {
		READ = '*',

		CALLERS = {
			opx77_inventory = { scopes = { inventory = true } },
		},

		MAX_RESULT_BYTES = 32768,
	},

	INVENTORY = {
		MAX_SLOTS = 1000,
		MAX_WEIGHT = 4000000000,
		MAX_METADATA_BYTES = 4096,
		PAGE_ROWS = 64,

		LINKED_KINDS = { character = 'citizen', trunk = 'plate', glovebox = 'plate' },
	},
}
