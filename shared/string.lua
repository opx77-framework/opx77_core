--- @author DemiAutomatic
--- @file shared/string.lua
--- @description String helpers: length, trim, placeholders and random templates.

OPX.String = {}

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The utf8 library, where the runtime installs one.
local utf8lib = rawget(_G, 'utf8')

--- @author DemiAutomatic
--- @method OPX.String.length
--- @description Measures text in characters, nil when it is not UTF-8.
--- @param text {string}
--- @returns {integer|nil}
function OPX.String.length(text)
	if utf8lib and utf8lib.len then return utf8lib.len(text) end
	return #text
end

--- @author DemiAutomatic
--- @method OPX.String.trim
--- @description Removes leading and trailing whitespace in linear time.
--- @param text {string}
--- @returns {string}
function OPX.String.trim(text)
	local from = text:match('^%s*()')
	if from > #text then return '' end
	return text:match('.*%S', from)
end

--- @author DemiAutomatic
--- @method OPX.String.interpolate
--- @description Fills named placeholders, leaving unknown names in place.
--- @param text {string}
--- @param params {table<string, any>|nil}
--- @returns {string}
function OPX.String.interpolate(text, params)
	if not params then return text end
	return (text:gsub('{(%w+)}', function(name)
		local value = params[name]
		return value ~= nil and tostring(value) or ('{' .. name .. '}')
	end))
end

--- @author DemiAutomatic
--- @type {string}
--- @description The letters a template's A draws from.
local RANDOM_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

--- @author DemiAutomatic
--- @type {string}
--- @description The digits a template's 1 draws from.
local RANDOM_DIGITS = '0123456789'

--- @author DemiAutomatic
--- @method OPX.String.random
--- @description Builds a string from a letter and digit template.
--- @param template {string} A letter, 1 digit, dot either.
--- @returns {string}
function OPX.String.random(template)
	local out = {}
	for i = 1, #template do
		local token = template:sub(i, i)
		if token == 'A' then
			local at = math.random(#RANDOM_LETTERS)
			out[i] = RANDOM_LETTERS:sub(at, at)
		elseif token == '1' then
			local at = math.random(#RANDOM_DIGITS)
			out[i] = RANDOM_DIGITS:sub(at, at)
		elseif token == '.' then
			local pool = math.random(2) == 1 and RANDOM_LETTERS or RANDOM_DIGITS
			local at = math.random(#pool)
			out[i] = pool:sub(at, at)
		else
			out[i] = token
		end
	end
	return table.concat(out)
end
