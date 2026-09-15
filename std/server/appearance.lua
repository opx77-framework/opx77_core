---@meta

OPX.Appearance = {}

--- The schema version written into every stored snapshot.
---@type integer
OPX.Appearance.VERSION = 1

--- Whether a game build is one the core will read a stored face back into: a key of
--- `OPX.Config.SHARED.APPEARANCE.GAME_BUILDS`.
---@param value any
---@return boolean
function OPX.Appearance.buildAccepted(value) end

--- A snapshot in canonical form (dense options, lower-cased names, every field of the expected
--- type), or nil and a code naming what was wrong with it.
---@param value any
---@return AppearanceSnapshot|nil canonical
---@return string|nil error
function OPX.Appearance.canonical(value) end

--- Whether two canonical snapshots are the same face, for skipping a write that changes nothing.
---@param left AppearanceSnapshot|nil
---@param right AppearanceSnapshot|nil
---@return boolean
function OPX.Appearance.same(left, right) end

--- Validates a captured snapshot, puts it on `PlayerData.appearance`, writes it to
--- `opx77_characters.appearance` (restoring the previous face if the write fails) and publishes
--- it to the client only while that Player is still the one loaded on its source. Coroutine only.
---@param identifier Player|Source|CitizenId
---@param snapshot any straight off the wire
---@return Result ok value is the canonical snapshot
function OPX.SaveAppearance(identifier, snapshot) end

--- The stored face for a character, online or not. Coroutine only when offline.
--- The ok value is an AppearanceSnapshot, or nil for a character with no face.
--- The client half defines its own `OPX.GetAppearance`; this field describes the server one.
---@type fun(identifier: Player|Source|CitizenId): Result
OPX.GetAppearance = OPX.GetAppearance
