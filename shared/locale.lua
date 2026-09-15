--- @author DemiAutomatic
--- @file shared/locale.lua
--- @description Locale catalogues, lookup with fallback and the global locale shorthand.

--- @author DemiAutomatic
--- @type {table<string, table<string, string>>}
--- @description Registered catalogues, keyed by language code then key.
local catalogs = {}

--- @author DemiAutomatic
--- @type {string}
--- @description The language player-facing text is currently read from.
local active = 'en'

--- @author DemiAutomatic
--- @type {string}
--- @description The language every lookup falls back to.
local FALLBACK = 'en'

OPX.Locale = {}
local Locale = OPX.Locale

--- @author DemiAutomatic
--- @method OPX.Locale.register
--- @description Merges a language's strings into its catalogue.
--- @param code {string}
--- @param strings {table<string, string>}
function OPX.Locale.register(code, strings)
	local catalog = catalogs[code]
	if not catalog then
		catalog = {}
		catalogs[code] = catalog
	end
	for key, text in pairs(strings) do catalog[key] = text end
end

--- @author DemiAutomatic
--- @method OPX.Locale.set
--- @description Selects the catalogue player-facing text is read from.
--- @param code {string}
--- @returns {boolean}
function OPX.Locale.set(code)
	if type(code) ~= 'string' or code == '' then return false end
	active = code
	return true
end

--- @author DemiAutomatic
--- @method OPX.Locale.current
--- @description Answers the language code currently in force.
--- @returns {string}
function OPX.Locale.current()
	return active
end

--- @author DemiAutomatic
--- @method OPX.Locale.exists
--- @description Whether the active or fallback catalogue carries a key.
--- @param key {string}
--- @returns {boolean}
function OPX.Locale.exists(key)
	return (catalogs[active] and catalogs[active][key] ~= nil)
		or (catalogs[FALLBACK] and catalogs[FALLBACK][key] ~= nil)
end

--- @author DemiAutomatic
--- @method OPX.Locale.t
--- @description Resolves a key through the active catalogue, the fallback, then itself.
--- @param key {string}
--- @param params {table<string, string|number>|nil}
--- @returns {string}
function OPX.Locale.t(key, params)
	local catalog = catalogs[active]
	local text = (catalog and catalog[key])
		or (catalogs[FALLBACK] and catalogs[FALLBACK][key])
		or key
	return OPX.String.interpolate(text, params)
end

--- @author DemiAutomatic
--- @type {fun(key: string, params: table|nil): string}
--- @description Global shorthand every gameplay file calls.
locale = Locale.t

Locale.set(OPX.Config.SHARED and OPX.Config.SHARED.LOCALE)
