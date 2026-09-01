--- The one client-side loop. Heading only: position is read authoritatively on the server,
--- and `Open77.players.position` is the one thing that answers no facing direction.

local Config = OPX.Config.CLIENT

--- Degrees. Below this the change is not worth an event: a standing player's yaw drifts as
--- the animation settles.
local HEADING_EPSILON = 2.0

CreateThread(function()
  local lastSent

  while true do
    Wait(Config.POSITION_REPORT_MS)

    if OPX.IsLoggedIn then
      local yaw = Open77.character.yaw()
      if type(yaw) == "number" then
        if lastSent == nil or math.abs(yaw - lastSent) >= HEADING_EPSILON then
          lastSent = yaw
          TriggerServerEvent(OPX.Events.Server.REPORT_POSITION, { heading = yaw })
        end
      end
    else
      -- forgotten on logout, so the next character's first report is always sent
      lastSent = nil
    end
  end
end)
