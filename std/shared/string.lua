---@meta

--- String helpers. Lua patterns are byte-oriented, so anything here that measures or slices
--- text says which unit it works in.
OPX.String = {}

--- Length in characters, or nil when the bytes are not valid UTF-8.
---@param text string
---@return integer?
function OPX.String.length(text) end

--- Removes leading and trailing whitespace, in linear time.
---@param text string
---@return string
function OPX.String.trim(text) end

--- Substitutes `{name}` placeholders; an unknown name is left in place so a typo shows.
---@param text string
---@param params? table<string, any>
---@return string
function OPX.String.interpolate(text, params) end

--- Builds a string from a template: `A` a letter, `1` a digit, `.` either, anything else copied
--- through ("AA-1111" -> "KP-8302"). Not for anything a player must not guess.
---@param template string
---@return string
function OPX.String.random(template) end
