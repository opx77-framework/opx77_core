resource "synk"
version "0.1.0"
auto_start true

-- Only entry points are listed. Everything else is pulled in with require()
-- from inside them, which keeps the manifest short and the load order in one
-- place: the require chain, not this file.
--
-- shared/init.lua requires config.lua and locales/, so a server owner editing
-- config.lua does not have to touch the manifest.
shared_script "shared/init.lua"
server_script "server/main.lua"
client_script "client/main.lua"

-- network.events    RegisterNetEvent, TriggerClientEvent, and client exports
-- database.access   Open77.database: every durable record
-- players.life.read identity reads, and the life-state check before placement
permissions {
  "network.events",
  "database.access",
  "players.life.read",
}
