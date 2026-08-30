--- Shared entry point, loaded in both runtimes. Pure Lua only: no server API,
--- no game world.

Synk = Synk or {}

Synk.VERSION = "0.1.0"

Synk.result = require("shared.result")
Synk.class = require("shared.class")
Synk.validate = require("shared.validate")
Synk.log = require("shared.log")
Synk.events = require("shared.events")
Synk.code = require("shared.code")
Synk.locale = require("shared.locale")

local config = require("config")
Synk.config = config

Synk.locale.register("en", require("locales.en"))
Synk.locale.register("fr", require("locales.fr"))
Synk.locale.setLocale(config.locale or "en")

--- Shorthand: translating is the most common thing a module does.
Synk.t = Synk.locale.t

return Synk
