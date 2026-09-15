---@meta

--- Player-facing text. Server logs stay in English whatever the configured locale is.
OPX.Locale = {}

--- Merges `strings` into the catalogue for `code`. Operators' own `locales/<code>.lua` files call
--- it, so the name stays lowercase.
---@param code string
---@param strings table<string, string>
function OPX.Locale.register(code, strings) end

--- Selects the catalogue player-facing text is read from. An unknown code is accepted and falls
--- back to en, because catalogues register after the locale module loads.
---@param code string
---@return boolean applied
function OPX.Locale.set(code) end

--- The language code in force.
---@return string
function OPX.Locale.current() end

--- Whether the active or the fallback catalogue carries `key`.
---@param key string
---@return boolean
function OPX.Locale.exists(key) end

--- Never returns nil: a missing translation falls back to `en` and then to the key itself.
---@param key string
---@param params? table<string, string|number>
---@return string
function OPX.Locale.t(key, params) end

--- The shorthand every gameplay file uses.
---@type fun(key: string, params?: table<string, string|number>): string
locale = OPX.Locale.t
