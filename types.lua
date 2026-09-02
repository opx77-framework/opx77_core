---@meta
--- Type annotations for opx77_core. Never loaded at runtime; keep it in step with the code.

---@alias Source integer  a session-scoped, recycled player id
---@alias UserId string   the Master-signed durable account id (a GUID)
---@alias CitizenId string  "H7K-M4X3" -- also the character key a satellite addresses
---@alias MoneyType string  a key of OPX.Config.SHARED.MONEY.TYPES
---@alias GroupType "job"|"gang"
---@alias Origin "nomad"|"streetkid"|"corpo"
---@alias Gender "female"|"male"

--- Any `{ x, y, z }` point. Vectors are a client concept, so both runtimes use plain tables.
---@class Vector3Like
---@field x number
---@field y number
---@field z number|nil

--- Wraps a success. `value` may be nil -- an empty answer is a success.
---@class LibOk
---@field ok true
---@field value any

--- `error` is a stable code, and doubles as a locale key wherever the failure is shown to a
--- player. `detail` is for logs only.
---@class LibErr
---@field ok false
---@field error string
---@field detail string|nil

---@alias Result LibOk|LibErr

--- Everything the core knows about one character. The client mirrors this whole table, so do
--- not put a server-side secret in it.
---@class PlayerData
---@field source Source|nil        nil for an offline Player
---@field userId UserId
---@field citizenId CitizenId
---@field cid integer              slot number within the account, 1-based
---@field name string              the account display name at last login
---@field charInfo CharInfo
---@field money table<MoneyType, integer>
---@field job PlayerJob            the primary job
---@field gang PlayerGang          the primary gang
---@field jobs table<string, integer>   every job membership, name -> grade
---@field gangs table<string, integer>  every gang membership, name -> grade
---@field position Position|nil    nil until the character has been somewhere
---@field metadata PlayerMetadata
---@field appearance AppearanceSnapshot|nil  nil until a face has been captured
---@field lastLoggedOut string|nil
---@field reportedHeading number|nil  the client's hint, never authoritative

---@class CharInfo
---@field firstName string
---@field lastName string
---@field birthDate string  "YYYY-MM-DD", flavour rather than a fact
---@field origin Origin     the lifepath
---@field gender Gender     the body family; the engine's own hash is in the snapshot
---@field phone string

--- Free-form: a gameplay file adds its own keys and they survive every save.
---@class PlayerMetadata
---@field health number      0-100, restored on the respawn transaction
---@field armor number       0-100, applied after the respawn settles
---@field isDead boolean
---@field inLastStand boolean
---@field [string] any

--- A captured face, `opx77_characters.appearance`. Canonical form only: server/appearance.lua
--- refuses anything else.
---@class AppearanceSnapshot
---@field schemaVersion integer  1
---@field gameBuild string       must be a key of Config.SHARED.APPEARANCE.GAME_BUILDS
---@field catalogDigest string   64 lower-case hex characters
---@field gender string          the engine's body-family hash, "0x" and 16 hex digits
---@field options AppearanceOption[]  dense, 1 to 256 entries

---@class AppearanceOption
---@field part "head"|"body"|"arms"
---@field name string   an option hash, "0x" and 16 lower-case hex digits, never zero
---@field value integer the chosen index, 0 to 511 and below `choices` when that is non-zero
---@field choices integer  how many the catalogue offers, 0 to 512

--- x, y and z come from `Open77.players.position`; `heading` is the one client-supplied field.
---@class Position
---@field x number
---@field y number
---@field z number
---@field heading number
---@field bucket integer

---@class PlayerJob
---@field name string
---@field label string
---@field type string|nil
---@field payment integer
---@field onDuty boolean
---@field isBoss boolean
---@field bankAuth boolean
---@field grade { name: string, level: integer }

---@class PlayerGang
---@field name string
---@field label string
---@field isBoss boolean
---@field bankAuth boolean
---@field grade { name: string, level: integer }

--- What a caller holds while a character is loaded. `Functions` and the module-level `OPX.*`
--- mutators are the same code, so a rule added to one is a rule both obey.
---@class Player
---@field PlayerData PlayerData
---@field Functions PlayerFunctions
---@field Offline boolean
---@field Revision integer   bumped by every change, never reset; the autosave's dirty flag
---@field MaySample boolean  true once OPX.PlaceCharacter has put the body where the row says

---@class PlayerFunctions
---@field UpdatePlayerData fun()
---@field SetPlayerData fun(key: string, value: any)
---@field SetMetaData fun(key: string, value: any)
---@field GetMetaData fun(key?: string): any
---@field SetCharInfo fun(key: string, value: any)
---@field AddMoney fun(moneyType: MoneyType, amount: number, reason?: string): boolean, string?
---@field RemoveMoney fun(moneyType: MoneyType, amount: number, reason?: string): boolean, string?
---@field SetMoney fun(moneyType: MoneyType, amount: number, reason?: string): boolean, string?
---@field GetMoney fun(moneyType?: MoneyType): integer|table
---@field SetJob fun(name: string, grade: integer): Result
---@field SetGang fun(name: string, grade: integer): Result
---@field SetJobDuty fun(onDuty: boolean): Result
---@field Save fun(): Result
---@field Logout fun()

--- A connected machine, not a loaded character: somebody in the selection screen has one of
--- these and no Player.
---@class Session
---@field source Source
---@field userId UserId
---@field displayName string
---@field connectedAt integer
---@field gateSession any|nil     the readiness-gate session while a hold is held
---@field citizenId CitizenId|nil set once a character is loaded
---@field charactersSent boolean
---@field released boolean|nil

--- The trimmed shape sent to a client for the selection screen. Money, metadata, appearance
--- and stored position are deliberately absent.
---@class CharacterSummary
---@field citizenId CitizenId
---@field cid integer
---@field firstName string
---@field lastName string
---@field origin Origin
---@field gender Gender
---@field job string|nil
---@field gang string|nil
---@field lastLoggedOut string|nil

---@class JobDefinition
---@field label string
---@field type string|nil
---@field defaultDuty boolean  true for a job with no shift to clock into
---@field offDutyPay boolean   pays whether or not its holder is clocked in
---@field grades table<integer, JobGrade>  contiguous from 0

---@class JobGrade
---@field name string
---@field payment integer
---@field isBoss boolean|nil
---@field bankAuth boolean|nil

---@class GangDefinition
---@field label string
---@field grades table<integer, GangGrade>

---@class GangGrade
---@field name string
---@field isBoss boolean|nil
---@field bankAuth boolean|nil

--- One schema migration. Append-only: the runner keys on the name, and an entry that has
--- shipped has already run on live databases.
---@class Migration
---@field name string
---@field file string       the `sql/` file carrying the same statements, for an operator
---@field statements string[]

--- Returning false from a hook vetoes the operation; returning nothing allows it. Points the
--- core triggers: money:beforeAdd, money:beforeRemove, money:beforeSet, paycheck:before.
---@class HookPayload
---@field player Player
---@field moneyType MoneyType|nil
---@field amount number|nil
---@field reason string|nil
