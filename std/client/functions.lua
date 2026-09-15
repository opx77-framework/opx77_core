---@meta

--- The mirrored PlayerData, or an empty table before a character loads. Never nil, so a caller
--- can index into it without guarding; `OPX.IsLoggedIn` is the honest question.
---@return PlayerData|table
function OPX.GetPlayerData() end

--- The live character's citizen id, or nil.
---@return CitizenId|nil
function OPX.GetCitizenId() end

--- The live character's primary job, or nil.
---@return PlayerJob|nil
function OPX.GetJobData() end

--- The live character's primary gang, or nil.
---@return PlayerGang|nil
function OPX.GetGangData() end

--- Whether the live character holds `name` as their primary job, optionally on duty and at a
--- minimum grade level.
---@param name string
---@param onDutyOnly? boolean
---@param minGrade? integer when given, the held grade level must be >= this
---@return boolean
function OPX.HasJob(name, onDutyOnly, minGrade) end

--- Whether the live character holds `name` as their primary gang. No duty parameter: a gang has
--- no shifts.
---@param name string
---@param minGrade? integer when given, the held grade level must be >= this
---@return boolean
function OPX.HasGang(name, minGrade) end

--- The primary job's grade level, or -1 when the character does not hold it (never nil, so grade
--- 0 is not mistaken for absence).
---@param name? string
---@return integer
function OPX.GetJobGrade(name) end

--- The live character's balance of one money type, 0 when unknown.
---@param moneyType MoneyType
---@return integer
function OPX.GetMoney(moneyType) end

--- One metadata value, or the whole metadata table when `key` is nil. `health`, `armor`,
--- `isDead` and `inLastStand` live here too.
---@param key? string
---@return any
function OPX.GetMetadata(key) end

--- The stored face for the live character, or nil for one never captured.
---@return AppearanceSnapshot|nil
function OPX.GetAppearance() end

--- What the live character wears as stored: a record, false for none stored, or nil when the
--- core could not read it.
---@return ClothingRecord|false|nil
function OPX.GetClothing() end

--- The local player's position as `{ x, y, z }`: `Open77.character.position()` answers three
--- numbers, and this flattens them into the shape the wire and the math helpers use.
---@return Vector3Like|nil
function OPX.GetPosition() end
