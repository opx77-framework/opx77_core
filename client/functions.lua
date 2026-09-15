--- @author DemiAutomatic
--- @file client/functions.lua
--- @description Client read helpers answered from the mirrored PlayerData.

--- @author DemiAutomatic
--- @method OPX.GetPlayerData
--- @description Answers the mirrored PlayerData, an empty table before login.
--- @returns {PlayerData|table}
function OPX.GetPlayerData()
	return OPX.PlayerData
end

--- @author DemiAutomatic
--- @method OPX.GetCitizenId
--- @description Answers the live character's citizen id, or nil.
--- @returns {string|nil}
function OPX.GetCitizenId()
	return OPX.PlayerData.citizenId
end

--- @author DemiAutomatic
--- @method OPX.GetJobData
--- @description Answers the live character's primary job, or nil.
--- @returns {PlayerJob|nil}
function OPX.GetJobData()
	return OPX.PlayerData.job
end

--- @author DemiAutomatic
--- @method OPX.GetGangData
--- @description Answers the live character's primary gang, or nil.
--- @returns {PlayerGang|nil}
function OPX.GetGangData()
	return OPX.PlayerData.gang
end

--- @author DemiAutomatic
--- @method OPX.HasJob
--- @description Answers whether the live character holds a job as primary.
--- @param name {string}
--- @param onDutyOnly {boolean|nil}
--- @param minGrade {integer|nil} Lowest grade level accepted.
--- @returns {boolean}
function OPX.HasJob(name, onDutyOnly, minGrade)
	local job = OPX.PlayerData.job
	if not job or job.name ~= name then return false end
	if onDutyOnly and job.onDuty ~= true then return false end
	if minGrade ~= nil then
		local level = job.grade and job.grade.level
		if type(level) ~= 'number' or level < minGrade then return false end
	end
	return true
end

--- @author DemiAutomatic
--- @method OPX.HasGang
--- @description Answers whether the live character holds a gang as primary.
--- @param name {string}
--- @param minGrade {integer|nil} Lowest grade level accepted.
--- @returns {boolean}
function OPX.HasGang(name, minGrade)
	local gang = OPX.PlayerData.gang
	if not gang or gang.name ~= name then return false end
	if minGrade ~= nil then
		local level = gang.grade and gang.grade.level
		if type(level) ~= 'number' or level < minGrade then return false end
	end
	return true
end

--- @author DemiAutomatic
--- @method OPX.GetJobGrade
--- @description Answers the primary job's grade level, or -1 when not held.
--- @param name {string|nil}
--- @returns {integer}
function OPX.GetJobGrade(name)
	local job = OPX.PlayerData.job
	if not job or (name and job.name ~= name) then return -1 end
	return job.grade and job.grade.level or -1
end

--- @author DemiAutomatic
--- @method OPX.GetMoney
--- @description Answers the live character's balance of one money type.
--- @param moneyType {string}
--- @returns {integer}
function OPX.GetMoney(moneyType)
	local money = OPX.PlayerData.money
	if not money then return 0 end
	return money[moneyType] or 0
end

--- @author DemiAutomatic
--- @method OPX.GetMetadata
--- @description Answers one metadata value, or the whole metadata table.
--- @param key {string|nil}
--- @returns {any}
function OPX.GetMetadata(key)
	local metadata = OPX.PlayerData.metadata
	if not metadata then return nil end
	if key == nil then return metadata end
	return metadata[key]
end

--- @author DemiAutomatic
--- @method OPX.GetAppearance
--- @description Answers the live character's stored face, or nil.
--- @returns {AppearanceSnapshot|nil}
function OPX.GetAppearance()
	return OPX.PlayerData.appearance
end

--- @author DemiAutomatic
--- @method OPX.GetClothing
--- @description Answers the live character's stored clothing, false, or nil.
--- @returns {ClothingRecord|false|nil}
function OPX.GetClothing()
	return OPX.PlayerData.clothing
end

--- @author DemiAutomatic
--- @method OPX.GetPosition
--- @description Answers the local player's position as an x, y, z table.
--- @returns {Vector3Like|nil}
function OPX.GetPosition()
	local x, y, z = Open77.character.position()
	if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
	return { x = x, y = y, z = z }
end
