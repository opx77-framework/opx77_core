--- Client helpers: the read side, answered from the mirrored PlayerData. None of it is
--- authoritative -- the server checks again before anything happens.

--- The mirrored PlayerData, or an empty table. Never nil, so a caller can index into it
--- without guarding; the honest question is `OPX.IsLoggedIn`.
---@return PlayerData|table
function OPX.GetPlayerData()
  return OPX.PlayerData
end

---@return CitizenId|nil
function OPX.GetCitizenId()
  return OPX.PlayerData.citizenId
end

---@return PlayerJob|nil
function OPX.GetJobData()
  return OPX.PlayerData.job
end

---@return PlayerGang|nil
function OPX.GetGangData()
  return OPX.PlayerData.gang
end

---@param name string
---@param onDutyOnly? boolean
---@return boolean
function OPX.HasJob(name, onDutyOnly)
  local job = OPX.PlayerData.job
  if not job or job.name ~= name then return false end
  return not onDutyOnly or job.onDuty == true
end

---@param name string
---@return boolean
function OPX.HasGang(name)
  local gang = OPX.PlayerData.gang
  return gang ~= nil and gang.name == name
end

--- Job grade level, or -1 when the character does not hold it. Minus one rather than nil so
--- grade 0 -- a real, common grade -- is never mistaken for absence.
---@param name? string
---@return integer
function OPX.GetJobGrade(name)
  local job = OPX.PlayerData.job
  if not job or (name and job.name ~= name) then return -1 end
  return job.grade and job.grade.level or -1
end

---@param moneyType MoneyType
---@return integer
function OPX.GetMoney(moneyType)
  local money = OPX.PlayerData.money
  if not money then return 0 end
  return money[moneyType] or 0
end

---@param key? string nil returns the whole metadata table
---@return any
function OPX.GetMetadata(key)
  local metadata = OPX.PlayerData.metadata
  if not metadata then return nil end
  if key == nil then return metadata end
  return metadata[key]
end

--- The local player's position, flattened out of the vector-shaped value so the wire format
--- and the shared math helpers see one shape.
---@return Vector3Like|nil
function OPX.GetPosition()
  local position = Open77.character.position()
  if not position then return nil end
  return { x = position.x, y = position.y, z = position.z }
end
