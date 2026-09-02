--- The one client-side loop. Heading only: the server reads position authoritatively, and
--- `Open77.players.position` is the one thing that answers no facing direction.

local Config = OPX.Config.CLIENT

--- Degrees. Below this the change is not worth an event: a standing player's yaw drifts as
--- the animation settles.
local HEADING_EPSILON = 2.0

CreateThread(function()
  local lastSent

  while true do
    Wait(Config.POSITION_REPORT_MS)

    if OPX.IsLoggedIn then
      -- pcall: a raise here would end heading reporting for the rest of the session
      local ok, err = pcall(function()
        local yaw = Open77.character.yaw()
        if not OPX.Math.isFinite(yaw) then return end
        if lastSent == nil or math.abs(yaw - lastSent) >= HEADING_EPSILON then
          lastSent = yaw
          TriggerServerEvent(OPX.Events.Server.REPORT_POSITION, { heading = yaw })
        end
      end)
      if not ok then
        Open77.log.error("[loops] heading reporting raised: " .. tostring(err))
      end
    else
      -- forgotten on logout, so the next character's first report is always sent
      lastSent = nil
    end
  end
end)
