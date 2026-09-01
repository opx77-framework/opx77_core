# Ce qui n'est pas tranché

Ce qui suit n'est pas documenté, ou l'est de façon contradictoire. Rien ici ne
doit être supposé dans le code : chaque entrée dit comment le core s'en
accommode en attendant.

Sources : la doc <https://open2077.net/docs> (statut pré-alpha assumé par
l'éditeur) **et** le code des ressources officielles livrées avec le serveur
(`open77-server-2.31.4+op77.11`, relu le 2026-08-31). Quand les deux se
contredisent, le code livré fait foi — il tourne.

## Résolu : l'événement de déconnexion existe

**Ancienne entrée, fausse.** La doc ne mentionne que `onPlayerConnected`, et
tout le système de sessions avait été construit autour de son absence.

Les ressources officielles utilisent **deux** événements de départ :

- `onPlayerDisconnected(playerIdStr)` — 9 usages, dont `open77_playerstate`,
  qui s'en sert pour sa sauvegarde finale.
- `playerDropped()` — 5 usages, dont `open77_appearance` et `open77_voice`,
  qui lisent `source` plutôt qu'un argument.

Aucun des deux n'est documenté. Lequel fait autorité n'est pas dit.

**Ce que fait le core.** Il écoute les deux (`server/events.lua`), et
`OPX.Logout` est idempotent — entendre un départ deux fois coûte une lecture
de table. Le filet reste la revérification du `userId` derrière l'emplacement
dans `OPX.EnsureSession` : `playerId` est recyclé, `userId` est durable et
signé, donc un départ manqué devient un non-événement au lieu d'un inconnu qui
hérite d'une session.

Ne pas retirer cette revérification sous prétexte que les événements existent.
Ils ne sont pas documentés, donc pas garantis.

## Résolu : `TriggerEvent` franchit bien les VM serveur

La doc dit « `TriggerEvent` is per-VM; only the host fans events into
resources », ce qui se lit comme une isolation totale.

`open77_appearance` la contredit explicitement, dans son propre commentaire :

> Server-owned character selection for RP resources. The client cannot choose
> another character key; **a gamemode calls this local event after authorizing
> it.**
>
> `AddEventHandler("open77:appearance:setCharacter", function(player, key)`

Personne dans les ressources livrées ne déclenche cet événement : il est prévu
pour être déclenché par un gamemode tiers. Donc l'hôte diffuse bien certains
noms dans toutes les VM serveur.

**Lecture retenue.** Le canal est **ressource → hôte → toutes ressources**,
jamais ressource → ressource, et il ne marche que pour les noms que l'hôte
connaît. Ce n'est pas un bus général.

**Non vérifié.** Qu'un nom arbitraire émis par une ressource atteigne une
autre ressource. Le core n'en dépend que pour `open77:appearance:setCharacter`,
et le seul effet d'un échec serait un personnage affiché avec le visage du
précédent — pas une perte de données.

## Résolu : `MySQL.<méthode>.await` lève, elle ne renvoie pas `nil, reason`

Contrairement à la convention « failures are values » affichée partout
ailleurs. `open77_dbtest` le dit en clair :

> `.await` raises on failure, so pcall keeps the outcome printable instead of
> killing the thread.

`MySQL.transaction.await` est l'exception : elle résout `false, reason`.

**Ce que fait le core.** `server/storage/main.lua` enveloppe chaque appel dans
un `pcall` et rend un `Result`. La transaction est traitée à part, pour cette
raison précise. Un `await` qui lève dans un `CreateThread` tue le thread en
silence — et ce thread, c'est en général la connexion d'un joueur.

## Résolu : paramètres nommés plutôt que `?`

`open77_playerstate` :

> The bridge rewrites `?` placeholders into real named parameters by scanning
> the statement, and that scan has to reason about quoting and comments to
> know which `?` is genuinely a placeholder. […] For the same reason there is
> not one comment inside any SQL string here: comments in SQL are exactly
> where that scan has been wrong before.

**Ce que fait le core.** `@nom` partout, et aucun commentaire dans une chaîne
SQL. Y compris dans les migrations, qui n'ont pourtant pas de paramètres : une
requête qui gagne un `?` plus tard ne doit pas être aussi celle qui porte un
commentaire.

## Résolu : il n'existe pas de liste des joueurs

`open77_admin` :

> There is no `Open77.players.all()`. A reload gives this VM an empty table
> while the server is still full, and `onPlayerConnected` does not re-fire for
> players who are already here.

**Ce que fait le core.** Adoption paresseuse du roster (convention n°1) :
`OPX.EnsureSession` à chaque point d'entrée, et le client se réannonce sur
`onClientResourceStart` **et** sur `open77:worldReady`, ce qui reconstruit le
roster en une seconde après un reload au lieu d'attendre que chacun fasse
quelque chose.

## `setmetatable` : présent ou retiré ?

La doc du bac à sable ne le liste pas parmi les retraits, mais **aucune** des
37 ressources officielles ne l'utilise, ni `getmetatable`.

**Ce que fait le core.** Rien n'en dépend. `OPX.Tune` est soit le proxy rendu
par `Open77.tunables.declare` (construit côté hôte, pas en Lua), soit une
table plate de valeurs par défaut — les deux répondent à `Tune.CLÉ`.

## `Open77.time.monotonic()` : secondes ou millisecondes ?

La référence d'API dit millisecondes pour le client.
`open77_playerstate` fait `math.floor(Open77.time.monotonic() * 1000)` côté
serveur, donc il rend des **secondes** là.

**Ce que fait le core.** `OPX.Now()` passe par `GetGameTimer()`, documenté
comme monotone en millisecondes et présent dans les deux runtimes. Mélanger
les deux unités produit un timer qui se déclenche mille fois trop tôt, et
c'est le genre de bug qu'on ne voit qu'en production.

## Limites non chiffrées

- Taille maximale d'un argument d'export : non documentée. Seul un « bounded
  value codec » est mentionné, qui rejette fonctions, threads, userdata,
  cycles, profondeur excessive et valeurs surdimensionnées.
- Délai d'expiration d'un appel d'export : aucun. La seule sortie documentée
  est l'invalidation par génération quand une ressource s'arrête ou recharge.
- Valeur exacte de `callError` quand la ressource cible s'arrête pendant un
  `await` déjà en vol. Seul `export_not_found` est cité, et seulement comme
  exemple de `reason` de dispatch.

**Conséquence pour le core.** `PlayerData` est envoyé entier à chaque
changement plutôt que par patch. Quelques centaines d'octets contre une
enveloppe de 48 Kio, et pas de protocole de fusion à faire diverger.

## La base de données est un terrain commun

> Every resource holding `database.access` talks to the same database, with
> the same credential. There is no per-resource schema, table prefix or
> statement filter. A resource can read and write another resource's tables.

C'est une voie d'intégration autant qu'une surface d'attaque.

**Ce que fait le core.** Toutes ses tables sont préfixées `opx77_`. Ne jamais
considérer le contenu de la base comme non falsifiable par une autre ressource
installée.

## Incohérence dans la référence d'API

`/docs/api/client/open77-exports` annonce « Returns: `whatever the export
returns` » pour `Open77.exports.call`, ce qui contredit sa propre prose
(« returns a generation-bound Promise ») et tous les exemples du site.

**Lecture retenue.** `promise, reason`, comme partout ailleurs. La fiche est
un artefact de génération.
