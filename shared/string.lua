--- String helpers. Lua patterns are byte-oriented, so anything here that measures or slices
--- text says which unit it works in.

local String = {}

local utf8lib = rawget(_G, "utf8")

--- Length in characters, or nil when the bytes are not valid UTF-8.
---@param text string
---@return integer?
function String.length(text)
  if utf8lib and utf8lib.len then return utf8lib.len(text) end
  return #text
end

---@param text string
---@return string
function String.trim(text)
  -- not `^%s*(.-)%s*$`: that backtracks once per trailing position, which is quadratic on a
  -- long run of spaces and uninterruptible at C level
  local from = text:match("^%s*()")
  if from > #text then return "" end
  return text:match(".*%S", from)
end

--- Substitutes `{name}` placeholders; an unknown name is left in place so a typo shows.
---@param text string
---@param params? table<string, any>
---@return string
function String.interpolate(text, params)
  if not params then return text end
  return (text:gsub("{(%w+)}", function(name)
    local value = params[name]
    return value ~= nil and tostring(value) or ("{" .. name .. "}")
  end))
end

local RANDOM_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local RANDOM_DIGITS = "0123456789"

--- Builds a string from a template. Not for anything a player must not guess: `math.random`
--- is not secure.
---@param template string `A` a letter, `1` a digit, `.` either, anything else copied
---        through: "AA-1111" -> "KP-8302"
---@return string
function String.random(template)
  local out = {}
  for i = 1, #template do
    local token = template:sub(i, i)
    if token == "A" then
      local at = math.random(#RANDOM_LETTERS)
      out[i] = RANDOM_LETTERS:sub(at, at)
    elseif token == "1" then
      local at = math.random(#RANDOM_DIGITS)
      out[i] = RANDOM_DIGITS:sub(at, at)
    elseif token == "." then
      local pool = math.random(2) == 1 and RANDOM_LETTERS or RANDOM_DIGITS
      local at = math.random(#pool)
      out[i] = pool:sub(at, at)
    else
      out[i] = token
    end
  end
  return table.concat(out)
end

OPX.String = String
