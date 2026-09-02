--- Player-facing text. Server logs stay in English whatever the configured locale is.
--- Publishes the global `locale(key, params)` as well as `OPX.Locale`.

local catalogs = {}
local active = "en"
local FALLBACK = "en"

local Locale = {}

--- Merges `strings` into the catalogue for `code`.
---@param code string
---@param strings table<string, string>
function Locale.register(code, strings)
  local catalog = catalogs[code]
  if not catalog then
    catalog = {}
    catalogs[code] = catalog
  end
  for key, text in pairs(strings) do catalog[key] = text end
end

--- Selects the catalogue player-facing text is read from. An unknown code is accepted and
--- falls back: catalogues register after this file loads.
---@param code string
---@return boolean applied
function Locale.set(code)
  if type(code) ~= "string" or code == "" then return false end
  active = code
  return true
end

---@return string
function Locale.current()
  return active
end

---@param key string
---@return boolean
function Locale.exists(key)
  return (catalogs[active] and catalogs[active][key] ~= nil)
    or (catalogs[FALLBACK] and catalogs[FALLBACK][key] ~= nil)
end

--- Never returns nil: a missing translation falls back to `en` and then to the key itself.
---@param key string
---@param params? table<string, string|number>
---@return string
function Locale.t(key, params)
  local catalog = catalogs[active]
  local text = (catalog and catalog[key])
    or (catalogs[FALLBACK] and catalogs[FALLBACK][key])
    or key
  return OPX.String.interpolate(text, params)
end

OPX.Locale = Locale

--- The shorthand every gameplay file uses.
---@type fun(key: string, params?: table<string, string|number>): string
locale = Locale.t

-- applied at load, or LOCALE in config/shared.lua is inert
Locale.set(OPX.Config.SHARED and OPX.Config.SHARED.LOCALE)
