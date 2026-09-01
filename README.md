# opx77_core

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

The core resource of **Opx77**, providing the essential systems and APIs required to build resources and gameplay for Open77.

Opx77 core is designed to provide a **simple, flexible, and reliable foundation** for developers. It handles the core functionality that resources can build upon while keeping the framework lightweight and easy to extend.

## Features

- Character creation, selection and deletion, with a per-account slot limit
- Multi-job and multi-gang membership, with grades and duty state
- Money, metadata and stored position, autosaved and written on departure
- Readiness-gate integration, so nothing places a player before the core has chosen where
- Live tunables, editable from the operator panel without a restart
- Export-based API to read core data from any resource
- Locales, with every refusal answered as a key a satellite can render

## Exports

Client-side, because the Open77 server runtime installs no export mechanism. A server resource that needs core data sends a net event to its own client half, which calls these.

| Export | Answers |
|---|---|
| `GetPlayerData` | the whole loaded character |
| `IsLoggedIn` | whether a character is loaded |
| `HasJob` / `HasGang` | membership, with an optional minimum grade and duty flag |
| `GetSharedConfig` | jobs, gangs, origins and the shared surface |
| `Locale` | one rendered line for a refusal code |
| `GetCharacters` | the roster last sent to this client |
| `RequestCharacters` | ask for it again |
| `SelectCharacter` / `CreateCharacter` / `DeleteCharacter` | the character screen |

Everything else is one field of `GetPlayerData` or one key of `GetSharedConfig`.

## Configuration

Three files, split by who may read them:

| File | Scope |
|---|---|
| `config/shared.lua` | values both sides need |
| `config/server.lua` | slots, autosave, paychecks, entry deadlines |
| `config/client.lua` | client cadences — **never loaded by the server VM** |

Anything an operator may want to change mid-session is a tunable instead, and lives in `server/tunables.lua`.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_core is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_core is an independent community project and is not affiliated with or endorsed by CD PROJEKT RED.</sub>
</p>
