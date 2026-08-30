--- Player-facing text. Server logs stay in English; only what a player reads
--- goes through here.

local Locale = {}

local catalogs = {}
local active = "en"
local FALLBACK = "en"

--- Modules call this with their own strings, so translations sit next to the
--- code that uses them.
function Locale.register(locale, strings)
  local catalog = catalogs[locale]
  if not catalog then
    catalog = {}
    catalogs[locale] = catalog
  end
  for key, text in pairs(strings) do catalog[key] = text end
end

function Locale.setLocale(locale)
  active = locale
end

function Locale.currentLocale()
  return active
end

--- Falls back to the fallback locale, then to the key itself. Never returns
--- nil: a missing translation should show an ugly string in one place, not
--- break the screen rendering it.
function Locale.t(key, params)
  local catalog = catalogs[active]
  local text = (catalog and catalog[key])
    or (catalogs[FALLBACK] and catalogs[FALLBACK][key])
    or key

  if not params then return text end
  return (text:gsub("{(%w+)}", function(name)
    local value = params[name]
    return value ~= nil and tostring(value) or ("{" .. name .. "}")
  end))
end

function Locale.exists(key)
  local catalog = catalogs[active]
  return (catalog and catalog[key] ~= nil)
    or (catalogs[FALLBACK] and catalogs[FALLBACK][key] ~= nil)
end

return Locale
