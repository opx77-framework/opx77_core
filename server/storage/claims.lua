--- One-per-account claims: a reward an account may take exactly once.

local Result = OPX.Result
local Storage = OPX.Storage

local Claims = {}
OPX.Storage.Claims = Claims

--- Take a claim, or say it was already taken.
---
--- The INSERT decides, not a SELECT beforehand. Two connections of the same account -- or one
--- player pressing twice -- both pass a read-then-write check and both get paid; the primary
--- key is the only thing that can arbitrate, because it is the only thing that is atomic.
---@param userId string
---@param code string
---@param citizenId string|nil  who was loaded at the time, for the record only
---@return table result  ok when this is the first time, `claim.taken` when it is not
function Claims.take(userId, code, citizenId)
  local written = Storage.execute([[
INSERT INTO opx77_claims (user_id, code, citizen_id) VALUES (@user, @code, @citizen)
  ]], { user = userId, code = code, citizen = citizenId })

  if written.ok then return Result.ok(true) end

  -- A duplicate key is the ordinary answer here, not a failure: it means somebody already
  -- has it. Anything else is the database being unavailable, and must not read as "claimed".
  local detail = tostring(written.detail or "")
  if detail:find("Duplicate", 1, true) or detail:find("1062", 1, true) then
    return Result.err("claim.taken", code)
  end
  return written
end
