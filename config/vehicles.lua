--- @author DemiAutomatic
--- @file config/vehicles.lua
--- @description Server-only vehicle configuration: ceiling, plates, garage and cadence.
--- @field PER_CHARACTER {integer} Most vehicles one character may own; 0 for no ceiling.
--- @field PLATE_FORMAT {string} 1 a digit, A a letter, dot either, anything else literal.
--- @field DEFAULT_GARAGE {string} Where a vehicle created with no garage belongs.
--- @field SPAWN_OFFSET {number} Metres to the side of the player a vehicle appears.
--- @field SAVE_SECONDS {integer} How often the condition of every vehicle out is written.

OPX.Config.VEHICLES = {
	PER_CHARACTER = 8,
	PLATE_FORMAT = '11AAA111',
	DEFAULT_GARAGE = 'impound',
	SPAWN_OFFSET = 3.0,
	SAVE_SECONDS = 120,
}
