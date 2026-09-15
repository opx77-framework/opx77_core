---@meta

OPX.Lifecycle = {}

--- Declares the core's participation in the readiness gate with `ENTRY.GATE_MS` as liveness
--- interval, so every later connection arrives with a hold in the core's name. Called once,
--- at load. Warns when no resource emits `open77:session:gameplayReady`.
function OPX.Lifecycle.participate() end

--- Takes the gate hold for one player and records the gate session on their Session, which is
--- what keeps a later release from clearing somebody else's hold on a recycled id.
---@param source Source
---@param reason? string
function OPX.Lifecycle.hold(source, reason) end

--- Releases a player's gate hold. Idempotent and safe for a player who never had one; the note
--- reaches every running resource as the `detail` of `onPlayerReady`.
---@param source Source
---@param note? string
function OPX.Lifecycle.release(source, note) end

--- Whether the gate has opened for this player this session. An id the host raises on reads
--- as open.
---@param source Source
---@return boolean
function OPX.Lifecycle.isReady(source) end

--- Everything the core does for a player who has just connected: hold the gate, isolate them in
--- their selection bucket, send the roster and start the selection watch. Every failure path
--- releases the gate.
---@param source Source
function OPX.Lifecycle.beginEntry(source) end

--- Starts the thread that releases the gate for a player who never chooses a character within
--- the `SELECTION_MS` tunable. It exits once the gate is released or the slot changes hands.
---@param source Source
function OPX.Lifecycle.watch(source) end
