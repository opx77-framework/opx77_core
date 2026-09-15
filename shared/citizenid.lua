--- @author DemiAutomatic
--- @file shared/citizenid.lua
--- @description Citizen ids: seven unambiguous symbols with a prime-modulus check.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors, read through a local.
local Result = OPX.Result

OPX.CitizenId = {}
local CitizenId = OPX.CitizenId

--- @author DemiAutomatic
--- @type {string}
--- @description The 23 symbols a citizen id is written with.
CitizenId.ALPHABET = '34679ACDEFGHJKMNPRTWXYZ'

--- @author DemiAutomatic
--- @type {integer}
--- @description The alphabet size, which is also the check modulus.
local BASE = #CitizenId.ALPHABET

--- @author DemiAutomatic
--- @type {integer}
--- @description How many symbols carry the payload before the check.
local PAYLOAD = 6

--- @author DemiAutomatic
--- @type {integer[]}
--- @description The weight of each payload position in the check sum.
local WEIGHTS = { 2, 3, 4, 5, 6, 7 }

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Symbol to value and value to symbol lookups.
local valueOf, symbolOf = {}, {}
for i = 1, BASE do
	local symbol = CitizenId.ALPHABET:sub(i, i)
	valueOf[symbol] = i - 1
	symbolOf[i - 1] = symbol
end

--- @author DemiAutomatic
--- @method checkSymbolFor
--- @description Answers the check symbol that completes a weighted sum.
--- @param weightedSum {integer}
--- @returns {string}
local function checkSymbolFor(weightedSum)
	return symbolOf[(BASE - weightedSum % BASE) % BASE]
end

--- @author DemiAutomatic
--- @method grouped
--- @description Writes seven raw symbols in their three-dash-four display form.
--- @param raw {string}
--- @returns {string}
local function grouped(raw)
	return raw:sub(1, 3) .. '-' .. raw:sub(4)
end

--- @author DemiAutomatic
--- @method OPX.CitizenId.build
--- @description Builds an id from six payload values in one pass.
--- @param values {integer[]}
--- @returns {CitizenId}
function OPX.CitizenId.build(values)
	local symbols, sum = {}, 0
	for i = 1, PAYLOAD do
		local value = values[i] % BASE
		symbols[i] = symbolOf[value]
		sum = sum + WEIGHTS[i] * value
	end
	symbols[PAYLOAD + 1] = checkSymbolFor(sum)
	return grouped(table.concat(symbols))
end

--- @author DemiAutomatic
--- @method OPX.CitizenId.generate
--- @description Draws a new random citizen id.
--- @param rng {fun(low: integer, high: integer): integer|nil} Injectable for deterministic generation.
--- @returns {CitizenId}
function OPX.CitizenId.generate(rng)
	rng = rng or math.random
	local values = {}
	for i = 1, PAYLOAD do values[i] = rng(0, BASE - 1) end
	return CitizenId.build(values)
end

--- @author DemiAutomatic
--- @method OPX.CitizenId.parse
--- @description Reads typed input, forgiving on case and separators, strict on symbols.
--- @param input {any}
--- @returns {Result}
function OPX.CitizenId.parse(input)
	if type(input) ~= 'string' then
		return Result.err('type', 'expected string')
	end

	if #input > 32 then
		return Result.err('length', ('expected %d symbols, got %d'):format(PAYLOAD + 1, #input))
	end

	local cleaned = input:upper():gsub('[%s%-_]', '')
	if #cleaned ~= PAYLOAD + 1 then
		return Result.err('length', ('expected %d symbols, got %d'):format(PAYLOAD + 1, #cleaned))
	end

	local sum = 0
	for i = 1, PAYLOAD do
		local symbol = cleaned:sub(i, i)
		local value = valueOf[symbol]
		if value == nil then
			return Result.err('alphabet', ('%q is not a citizen id symbol'):format(symbol))
		end
		sum = sum + WEIGHTS[i] * value
	end

	local check = cleaned:sub(PAYLOAD + 1)
	if valueOf[check] == nil then
		return Result.err('alphabet', ('%q is not a citizen id symbol'):format(check))
	end
	if checkSymbolFor(sum) ~= check then
		return Result.err('checksum', 'this is not a valid citizen id')
	end

	return Result.ok(grouped(cleaned))
end

--- @author DemiAutomatic
--- @method OPX.CitizenId.isValid
--- @description Whether a value is a valid citizen id, for internal guards.
--- @param value {any}
--- @returns {boolean}
function OPX.CitizenId.isValid(value)
	return CitizenId.parse(value).ok
end
