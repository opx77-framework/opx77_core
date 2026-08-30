--- Client state, in one table shared by the entry point and the export surface.
---
--- Held by reference: the handlers in `main.lua` assign to its *fields*, never
--- to the table itself. Rebinding it (`state = { ... }`) would leave every
--- export reading the table nobody updates any more, and nothing would report
--- the mistake.

return {
  --- What the server last sent. Empty until `synk:characters:list` arrives.
  characters = {},

  --- nil until the player is in the world.
  characterId = nil,
}
