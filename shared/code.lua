--- Public character codes, e.g. "H7K-M4X3".
---
--- Players read these aloud and type them from memory, so the format is built
--- to survive being read wrong: 23 unambiguous symbols (no 0/O, 1/I/L, 5/S),
--- six payload symbols and one check symbol.
---
--- The check symbol is a weighted sum mod 23. The modulus is prime, which is
--- what makes it catch every single-symbol substitution and every swap of two
--- neighbours. Without it a typo can produce a *valid* code belonging to
--- someone else, and a transfer reaches a stranger with no error shown.
--- Do not change the alphabet size or the weights.

local Result = require("shared.result")

local Code = {}

Code.ALPHABET = "34679ACDEFGHJKMNPRTWXYZ"

local BASE = #Code.ALPHABET
local PAYLOAD = 6
local WEIGHTS = { 2, 3, 4, 5, 6, 7 }

local valueOf, symbolOf = {}, {}
for i = 1, BASE do
  local symbol = Code.ALPHABET:sub(i, i)
  valueOf[symbol] = i - 1
  symbolOf[i - 1] = symbol
end

local function checkSymbolFor(weightedSum)
  return symbolOf[(BASE - weightedSum % BASE) % BASE]
end

local function grouped(raw)
  return raw:sub(1, 3) .. "-" .. raw:sub(4)
end

--- Builds a code from six payload values, in a single pass.
function Code.build(values)
  local symbols, sum = {}, 0
  for i = 1, PAYLOAD do
    local value = values[i] % BASE
    symbols[i] = symbolOf[value]
    sum = sum + WEIGHTS[i] * value
  end
  symbols[PAYLOAD + 1] = checkSymbolFor(sum)
  return grouped(table.concat(symbols))
end

--- `rng` is injectable so a caller can make generation deterministic.
function Code.generate(rng)
  rng = rng or math.random
  local values = {}
  for i = 1, PAYLOAD do values[i] = rng(0, BASE - 1) end
  return Code.build(values)
end

--- Parses user input. Forgiving about case and separators, strict about
--- content: an unknown symbol is rejected, never dropped. Dropping is how
--- "AO2C-D3F" quietly becomes a different, valid code.
function Code.parse(input)
  if type(input) ~= "string" then
    return Result.err("type", "expected string")
  end

  local cleaned = input:upper():gsub("[%s%-_]", "")
  if #cleaned ~= PAYLOAD + 1 then
    return Result.err("length", ("expected %d symbols, got %d"):format(PAYLOAD + 1, #cleaned))
  end

  local sum = 0
  for i = 1, PAYLOAD do
    local symbol = cleaned:sub(i, i)
    local value = valueOf[symbol]
    if value == nil then
      return Result.err("alphabet", ("%q is not a code symbol"):format(symbol))
    end
    sum = sum + WEIGHTS[i] * value
  end

  local check = cleaned:sub(PAYLOAD + 1)
  if valueOf[check] == nil then
    return Result.err("alphabet", ("%q is not a code symbol"):format(check))
  end
  if checkSymbolFor(sum) ~= check then
    return Result.err("checksum", "this is not a valid code")
  end

  return Result.ok(grouped(cleaned))
end

return Code
