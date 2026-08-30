---@meta
--- SYNK's own types. Never loaded at runtime; it exists so the editor knows
--- the shapes SYNK passes around. Open2077's API is not described here.
---
--- Keep this in step with the code: a drifted annotation is worse than none,
--- because it silences the mistake it should have caught.

--- Wraps a success. `value` is whatever the call produced.
---@class SynkOk
---@field ok true
---@field value any

--- `error` is a stable code meant for branching; `detail` is for logs only and
--- is never shown to a player.
---@class SynkErr
---@field ok false
---@field error string
---@field detail string|nil

---@alias SynkResult SynkOk|SynkErr

--- A connected player, between joining and leaving. `playerId` is recycled and
--- `userId` is not, so only the second is an identity.
---@class SynkSession
---@field playerId integer
---@field userId string
---@field displayName string|nil
---@field characterId integer|nil  nil while the player is still choosing
---@field openedAt integer         GetGameTimer() when the session opened

---@class SynkCharacter
---@field id integer
---@field publicCode string        grouped form, e.g. "H7K-M4X3"
---@field firstName string
---@field lastName string
---@field lastPlayedAt string|nil

--- What a module declares. `requires` drives boot order, so a module never
--- sees a half-built dependency. `setup` returns the public table that
--- `ctx.use(id)` hands to a dependent.
---@class SynkModuleDefinition
---@field requires string[]|nil
---@field setup fun(ctx: SynkModuleContext): table|nil
---@field teardown fun()|nil       run in reverse boot order

--- What a module receives: services, never the kernel.
---@class SynkModuleContext
---@field id string
---@field log SynkLogger
---@field db SynkDb
---@field sessions SynkSessionStore
---@field entryStep fun(name: string, fn: fun(session: SynkSession): SynkResult)
---@field use fun(id: string): table  raises if `id` is not in `requires`

---@class SynkLogger
---@field debug fun(...)
---@field info fun(...)
---@field warn fun(...)
---@field error fun(...)

--- Every call blocks the calling coroutine, so all of these are only valid
--- inside a CreateThread.
---@class SynkDb
---@field query fun(sql: string, params?: any[]): SynkResult
---@field single fun(sql: string, params?: any[]): SynkResult
---@field scalar fun(sql: string, params?: any[]): SynkResult
---@field insert fun(sql: string, params?: any[]): SynkResult
---@field update fun(sql: string, params?: any[]): SynkResult
---@field transaction fun(statements: table[]): SynkResult
---@field migrate fun(migrations: SynkMigration[]): SynkResult

--- Append-only. Never edit one that has shipped: the runner keys on the name
--- and it has already run on live databases.
---@class SynkMigration
---@field name string
---@field statements string[]

--- `get` is the only accessor, so the recycling check cannot be skipped.
---@class SynkSessionStore
---@field open fun(self, playerId: integer, userId: string, displayName?: string): SynkResult
---@field get fun(self, playerId: integer): SynkResult
---@field attachCharacter fun(self, playerId: integer, characterId: integer): SynkResult
---@field findByCharacter fun(self, characterId: integer): SynkResult
---@field close fun(self, playerId: integer): SynkSession|nil
---@field all fun(self): SynkSession[]
---@field now fun(self): integer

--- Built by shared/init.lua, present in both runtimes.
---@class Synk
---@field VERSION string
---@field config SynkConfig
---@field result table
---@field class fun(name: string, parent?: table): table
---@field validate table
---@field log table
---@field events table
---@field code table
---@field locale table
---@field t fun(key: string, params?: table<string, string|number>): string
---@field module fun(id: string, definition: SynkModuleDefinition): SynkModuleDefinition
Synk = {}

--- config.lua. Ships to every client: never put a secret in it.
---@class SynkConfig
---@field locale string
---@field logLevel "debug"|"info"|"warn"|"error"|"silent"
---@field characters { max: integer, name: { min: integer, max: integer } }
---@field entry { pipelineMs: integer, gateMs: integer }
SynkConfig = {}
