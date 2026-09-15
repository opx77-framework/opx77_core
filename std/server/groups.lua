---@meta

--- Makes a job at a grade the primary one, joining it if needed; duty comes from the job's
--- `defaultDuty`. Yields when the character is offline.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result ok value is the new PlayerJob
function OPX.SetJob(identifier, name, grade) end

--- Clocks a character in or out of their primary job; refused for a job with no shifts.
---@param identifier Player|Source|CitizenId
---@param onDuty boolean
---@return Result
function OPX.SetJobDuty(identifier, onDuty) end

--- Adds a job membership without changing which job is primary.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result
function OPX.AddPlayerToJob(identifier, name, grade) end

--- Removes a job membership; the primary job falls back to `PLAYER.DEFAULT_JOB`.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.RemovePlayerFromJob(identifier, name) end

--- Makes one of a character's existing jobs primary; refuses a job they do not hold.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.SetPlayerPrimaryJob(identifier, name) end

--- Makes a gang at a grade the primary one, joining it if needed.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result ok value is the new PlayerGang
function OPX.SetGang(identifier, name, grade) end

--- Adds a gang membership without changing which gang is primary.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result
function OPX.AddPlayerToGang(identifier, name, grade) end

--- Removes a gang membership; the primary gang falls back to `PLAYER.DEFAULT_GANG`.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.RemovePlayerFromGang(identifier, name) end

--- Makes one of a character's existing gangs primary; refuses a gang they are not in.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.SetPlayerPrimaryGang(identifier, name) end

--- Everyone in a job or gang, online or not, at most 200. Coroutine only.
---@param groupType GroupType
---@param name string
---@return Result
function OPX.GetGroupMembers(groupType, name) end

--- Loaded characters whose primary job is `name`, optionally on duty only. Does not yield.
---@param name string
---@param onDutyOnly? boolean
---@return Player[]
function OPX.GetPlayersByJob(name, onDutyOnly) end

--- Loaded characters whose primary gang is `name`. Does not yield.
---@param name string
---@return Player[]
function OPX.GetPlayersByGang(name) end
