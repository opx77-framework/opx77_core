---@meta

--- Citizen IDs, e.g. "H7K-M4X3": 23 unambiguous symbols, six payload and one check.
OPX.CitizenId = {}

--- The 23 symbols a citizen id is written with.
---@type string
OPX.CitizenId.ALPHABET = '34679ACDEFGHJKMNPRTWXYZ'

--- Builds an id from six payload values, in a single pass.
---@param values integer[]
---@return CitizenId
function OPX.CitizenId.build(values) end

--- Draws a new id.
---@param rng? fun(low: integer, high: integer): integer injectable, for deterministic generation
---@return CitizenId
function OPX.CitizenId.generate(rng) end

--- Parses player input: forgiving about case and separators, strict about content. The ok value
--- is the id in its grouped form.
---@param input any
---@return Result
function OPX.CitizenId.parse(input) end

--- For guarding an internal call site. Use `parse` on input, so the caller learns why.
---@param value any
---@return boolean
function OPX.CitizenId.isValid(value) end
