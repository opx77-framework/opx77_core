---@meta

--- Announces this client to the server with `opx77:server:ready`. The server answers with the
--- roster, or with `playerLoaded` when a character is already in; it is what refills the roster
--- after a core reload, since `onPlayerConnected` does not fire again.
function OPX.Announce() end
