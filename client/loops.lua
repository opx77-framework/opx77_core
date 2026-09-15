--- @author DemiAutomatic
--- @file client/loops.lua
--- @description Reports the local player's heading while a character is loaded.

--- @author DemiAutomatic
--- @type {table}
--- @description The client configuration table.
local Config = OPX.Config.CLIENT

--- @author DemiAutomatic
--- @type {number}
--- @description Degrees the yaw must move before a new report is sent.
local HEADING_EPSILON = 2.0

CreateThread(function()
	local lastSent

	while true do
		Wait(Config.POSITION_REPORT_MS)

		if OPX.IsLoggedIn then
			local ok, err = pcall(function()
				local yaw = Open77.character.yaw()
				if not OPX.Math.isFinite(yaw) then return end
				if lastSent == nil or math.abs(yaw - lastSent) >= HEADING_EPSILON then
					lastSent = yaw
					TriggerServerEvent(OPX.Events.Server.REPORT_POSITION, { heading = yaw })
				end
			end)
			if not ok then
				Open77.log.error('[loops] heading reporting raised: ' .. tostring(err))
			end
		else
			lastSent = nil
		end
	end
end)
