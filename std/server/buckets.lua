---@meta

OPX.Buckets = {}

--- A player's own selection bucket, BASE + id, or nil when isolation is off or the id cannot
--- have one.
---@param source Source
---@return integer|nil
function OPX.Buckets.selectionOf(source) end

--- Whether a bucket id is in the selection range, answered even with isolation off.
---@param bucket any
---@return boolean
function OPX.Buckets.isSelection(bucket) end

--- The bucket a player is in, or nil where the host cannot say.
---@param source Source
---@return integer|nil
function OPX.Buckets.current(source) end

--- Where a stored position puts a character: the bucket it names, unless that is a selection
--- bucket or not a bucket id, which read as the world bucket.
---@param stored any the `bucket` of a stored Position
---@return integer
function OPX.Buckets.placementOf(stored) end

--- Moves one player, logged at debug; a refusal is also logged at warn.
---@param source Source
---@param bucket integer
---@param why string
---@return boolean moved
function OPX.Buckets.move(source, bucket, why) end

--- Puts a player with no character in their own selection bucket, preparing its policy once.
--- Refused for a player with a character loaded or leaving.
---@param source Source
---@param why string
---@return boolean isolated
function OPX.Buckets.isolate(source, why) end

--- Takes a player out of their selection bucket into the world one; a player in any other
--- bucket is left alone.
---@param source Source
---@param why string
---@return boolean released true also when there was nothing to release
---@return boolean moved whether a move was made
function OPX.Buckets.release(source, why) end
