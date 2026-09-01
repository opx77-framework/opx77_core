--- Citizen IDs, e.g. "H7K-M4X3": 23 unambiguous symbols, six payload and one check. The
--- check is a weighted sum modulo 23, and the modulus being prime is what catches every
--- single-symbol substitution and every neighbour transposition -- do not change the alphabet
--- size or the weights. The grouped form is also the open77_appearance `character_key`, whose
--- validator accepts only `^[%w_.:%-]+$`.

local Result = OPX.Result

local CitizenId = {}

CitizenId.ALPHABET = "34679ACDEFGHJKMNPRTWXYZ"

local BASE = #CitizenId.ALPHABET
local PAYLOAD = 6
local WEIGHTS = { 2, 3, 4, 5, 6, 7 }

local valueOf, symbolOf = {}, {}
for i = 1, BASE do
  local symbol = CitizenId.ALPHABET:sub(i, i)
  valueOf[symbol] = i - 1
  symbolOf[i - 1] = symbol
end

local function checkSymbolFor(weightedSum)
  return symbolOf[(BASE - weightedSum % BASE) % BASE]
end

local function grouped(raw)
  return raw:sub(1, 3) .. "-" .. raw:sub(4)
end

--- Builds an id from six payload values, in a single pass.
---@param values integer[]
---@return CitizenId
function CitizenId.build(values)
  local symbols, sum = {}, 0
  for i = 1, PAYLOAD do
    local value = values[i] % BASE
    symbols[i] = symbolOf[value]
    sum = sum + WEIGHTS[i] * value
  end
  symbols[PAYLOAD + 1] = checkSymbolFor(sum)
  return grouped(table.concat(symbols))
end

---@param rng? fun(low: integer, high: integer): integer injectable so generation can be
---           made deterministic
---@return CitizenId
function CitizenId.generate(rng)
  rng = rng or math.random
  local values = {}
  for i = 1, PAYLOAD do values[i] = rng(0, BASE - 1) end
  return CitizenId.build(values)
end

--- Parses player input: forgiving about case and separators, strict about content. An unknown
--- symbol is rejected, never dropped -- dropping turns "AO2C-D3F" into somebody else's id.
---@param input any
---@return Result
function CitizenId.parse(input)
  if type(input) ~= "string" then
    return Result.err("type", "expected string")
  end

  -- checked before upper() and gsub() copy the string twice, so a refusal has a fixed cost
  if #input > 32 then
    return Result.err("length", ("expected %d symbols, got %d"):format(PAYLOAD + 1, #input))
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
      return Result.err("alphabet", ("%q is not a citizen id symbol"):format(symbol))
    end
    sum = sum + WEIGHTS[i] * value
  end

  local check = cleaned:sub(PAYLOAD + 1)
  if valueOf[check] == nil then
    return Result.err("alphabet", ("%q is not a citizen id symbol"):format(check))
  end
  if checkSymbolFor(sum) ~= check then
    return Result.err("checksum", "this is not a valid citizen id")
  end

  return Result.ok(grouped(cleaned))
end

--- For guarding an internal call site. Use `parse` on input, so the caller learns why.
---@param value any
---@return boolean
function CitizenId.isValid(value)
  return CitizenId.parse(value).ok
end

OPX.CitizenId = CitizenId
