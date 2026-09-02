--- Client helpers: the read side, answered from the mirrored PlayerData. None of it is
--- authoritative; the server checks again before anything happens.

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

--- Whether the live character holds `name` as their primary job.
---@param name string
---@param onDutyOnly? boolean
---@param minGrade? integer when given, the held grade level must be >= this
---@return boolean
function OPX.HasJob(name, onDutyOnly, minGrade)
  local job = OPX.PlayerData.job
  if not job or job.name ~= name then return false end
  if onDutyOnly and job.onDuty ~= true then return false end
  if minGrade ~= nil then
    local level = job.grade and job.grade.level
    if type(level) ~= "number" or level < minGrade then return false end
  end
  return true
end

--- Whether the live character holds `name` as their primary gang. No duty parameter: a gang
--- has no shifts.
---@param name string
---@param minGrade? integer when given, the held grade level must be >= this
---@return boolean
function OPX.HasGang(name, minGrade)
  local gang = OPX.PlayerData.gang
  if not gang or gang.name ~= name then return false end
  if minGrade ~= nil then
    local level = gang.grade and gang.grade.level
    if type(level) ~= "number" or level < minGrade then return false end
  end
  return true
end

--- Job grade level, or -1 when the character does not hold it. Minus one rather than nil, so
--- grade 0 is never mistaken for absence.
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

--- Free-form character state; `health`, `armor`, `isDead` and `inLastStand` live here too.
---@param key? string nil returns the whole metadata table
---@return any
function OPX.GetMetadata(key)
  local metadata = OPX.PlayerData.metadata
  if not metadata then return nil end
  if key == nil then return metadata end
  return metadata[key]
end

--- The stored face for the live character, or nil for one that has never been captured.
---@return AppearanceSnapshot|nil
function OPX.GetAppearance()
  return OPX.PlayerData.appearance
end

--- The local player's position, flattened so the wire format and the shared math helpers see
--- one shape. `Open77.character.position()` answers three numbers, not a table.
---@return Vector3Like|nil
function OPX.GetPosition()
  local x, y, z = Open77.character.position()
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
  return { x = x, y = y, z = z }
end
