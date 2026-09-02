# Ce qui n'est pas tranché

Ce qui suit n'est pas documenté, ou l'est de façon contradictoire. Rien ici ne
doit être supposé dans le code : chaque entrée dit comment le core s'en
accommode en attendant.

Les entrées marquées **Tranché** ou **RÉFUTÉ** ne sont plus des inconnues :
elles restent ici parce que la doc publique dit toujours autre chose, et que
quelqu'un finira par la relire et « corriger » le core dans le mauvais sens.
Une entrée qui dit « l'ancienne version de ce paragraphe avait tort » est là
exprès.

Sources, par autorité décroissante :

1. **Le bootstrap Lua serveur de la plateforme**, extrait octet pour octet de
   `Open77.Server.Scripting.dll` (commentaires compris), et l'IL des assemblies
   `Open77.Server*.dll` / `Open77.Platform.so`. C'est le code qui tourne.
2. Le code des 37 ressources officielles livrées avec le serveur
   (`open77-server-2.31.4+op77.11`, relu le 2026-08-31).
3. La doc <https://open2077.net/docs> (statut pré-alpha assumé par l'éditeur).

Quand ils se contredisent, le binaire tranche — y compris contre les
commentaires du bootstrap lui-même, qui sont faux en au moins un endroit
(`Open77.ready.hold`, plus bas).

## Tranché : il y a un seul événement de déconnexion, et `playerDropped` n'existe pas

**Deux entrées fausses successives.** La doc ne mentionne que
`onPlayerConnected`, et tout le système de sessions avait d'abord été construit
autour de l'absence d'un départ. On avait ensuite conclu qu'il en existait
deux, parce que les ressources officielles écoutent bien les deux noms.

Le binaire tranche : **seul `onPlayerDisconnected(playerId)` est émis.** Il
vient de `NotifyPlayerDisconnected`, avant que la fiche de la barrière d'entrée
soit détruite. Le jeton `playerDropped` n'apparaît dans aucune assembly ailleurs
que dans le littéral du bootstrap lui-même — c'est le texte de son propre
`AddEventHandler("playerDropped", …)`, qui n'est donc jamais appelé. Que cinq
ressources officielles l'écoutent ne prouve rien : elles écoutent toutes
`onPlayerDisconnected` en plus, donc rien ne casse chez elles non plus.

**Ce que fait le core.** Il écoute les deux (`server/events.lua`). Le
gestionnaire `playerDropped` est du code mort et doit être retiré ; c'est
`onPlayerDisconnected` qu'il ne faut jamais retirer. `OPX.Logout` reste
idempotent — entendre un départ deux fois coûte une lecture de table.

Le filet reste la revérification du `userId` derrière l'emplacement dans
`OPX.EnsureSession` : `playerId` est recyclé, `userId` est durable et signé,
donc un départ manqué devient un non-événement au lieu d'un inconnu qui hérite
d'une session. Ne pas la retirer sous prétexte que l'événement est maintenant
identifié : il n'est toujours pas documenté, donc pas garanti.

## RÉFUTÉ : `TriggerEvent` **ne** franchit **pas** les VM serveur

**L'entrée précédente disait le contraire, et elle avait tort.** Elle
s'appuyait sur un commentaire d'`open77_appearance` :

> Server-owned character selection for RP resources. The client cannot choose
> another character key; **a gamemode calls this local event after authorizing
> it.**
>
> `AddEventHandler("open77:appearance:setCharacter", function(player, key)`

et en déduisait que l'hôte diffusait ce nom dans toutes les VM. La lecture du
binaire dit non. Côté serveur, `TriggerEvent` parcourt la seule table de
gestionnaires de **sa propre VM**. La diffusion vers toutes les ressources est
un chemin distinct (`ServerResourceHost::Emit`), réservé à l'ensemble fermé des
événements de l'hôte : `onPlayerConnected`, `onPlayerDisconnected`,
`onPlayerReady`, `onResourceStart`/`Stop`, `onTunableChanged`, les événements
PNJ, etc.

Donc **`open77:appearance:setCharacter` n'est éventé par personne.** Le
commentaire d'`open77_appearance` décrit une intention, pas un mécanisme : un
gamemode ne peut appeler ce gestionnaire que s'il tourne dans la même VM, c'est-
à-dire s'il est `open77_appearance`. Un `TriggerEvent` de ce nom depuis le core
n'atteint rien et n'échoue pas non plus : il ne fait rien, en silence.

**Conséquence pour le core.** Ne rien bâtir sur ce canal côté serveur. Le seul
effet d'un échec ici est un personnage affiché avec le visage du précédent —
pas une perte de données — mais ce n'est plus « non vérifié », c'est acquis, et
il faut cesser de compter dessus.

**Attention à la dissymétrie : côté client, c'est l'inverse.** Le bus local
client est bien à l'échelle de l'hôte : `open77_zones` déclenche un nom
d'événement fourni par l'appelant et `pursuit` le reçoit avec un
`AddEventHandler` nu, dans une autre ressource. C'est ce qui rend le canal
`OPX.Events.Local` (`shared/main.lua`) utilisable par un satellite sans aucune
permission.

## Tranché : un `TriggerEvent` atteint aussi les `RegisterNetEvent` du même nom

Le répartiteur du bootstrap compare le **nom** de l'événement et ne regarde
jamais le drapeau `network` de l'entrée ; seul le chemin d'émission réseau
(`__open77_emit_network`) filtre là-dessus.

Donc un `RegisterNetEvent("x", …)` dont le corps fait `TriggerEvent("x", …)`
se rappelle lui-même. Ce n'est pas une récursion de pile : l'émission passe par
la file de tâches, donc la boucle est cadencée au tick. Elle ne déborde pas,
elle ne journalise rien, elle ne s'arrête jamais.

**Ce que fait le core.** Les deux vocabulaires sont disjoints par construction
(`OPX.Events.Client` pour le fil, `OPX.Events.Local` pour le bus local), et
`shared/main.lua` le dit à l'endroit où quelqu'un serait tenté d'ajouter un
nom. `opx77:client:playerLoaded` et `opx77:client:playerUnloaded` étaient
exactement dans ce cas et ont été renommés en `opx77:client:onPlayerLoaded` et
`opx77:client:onPlayerUnloaded` côté local.

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

## Tranché : `Open77.time.monotonic()` rend des **secondes**

Plus de doute et pas de contradiction : le bootstrap définit
`time = { monotonic = function() return now / 1000 end }`, où `now` est
l'horloge de l'ordonnanceur en millisecondes — celle-là même que rend
`GetGameTimer()`. La référence d'API dit la même chose (« Monotonic clock, in
seconds… Multiply by 1000 only when an API explicitly expects milliseconds »).
Le `math.floor(Open77.time.monotonic() * 1000)` d'`open77_playerstate` est
donc correct, et l'ancienne entrée accusait la doc à tort.

**Ce que fait le core.** `OPX.Now()` passe par `GetGameTimer()`, installé par
le bootstrap dans chaque VM serveur et documenté comme monotone en
millisecondes. Le repli, quand ce global manque, multiplie `monotonic()` par
1000 plutôt que de rendre `0` : un zéro constant ferait comparer deux nombres
égaux à chaque délai de garde du framework, ce qui se lit comme « le délai
n'expire jamais » et ne se voit nulle part.

Mélanger les deux unités produit un timer qui se déclenche mille fois trop
tôt, et c'est le genre de bug qu'on ne voit qu'en production.

## Tranché : `Open77.ready.hold` rend **une** valeur, pas deux

Le commentaire du bootstrap lui-même écrit
`Open77.ready.hold(playerId, reason)  -- I need them; returns ok, session`.
**Il est faux**, et c'est le site officiel qui a raison ici : l'IL rend un seul
entier, le numéro de session, ou `nil, reason` en cas d'échec. Il n'y a pas de
booléen.

Écrire `local ok, session = Open77.ready.hold(id)` lie donc `ok` au numéro de
session et `session` à `nil`. Le test de vérité passe quand même, donc le bug
est silencieux et ne mord qu'au moment où la session est réutilisée dans le
`release` — c'est-à-dire précisément quand un `playerId` a été recyclé.

Autres précisions du binaire, non documentées : `hold`, `release`, `isReady` et
`status` **lèvent** une erreur Lua (`id must be positive`) pour un `playerId`
nul ou négatif, au lieu de rendre une raison. Une ressource qui n'a jamais
appelé `participate` peut quand même poser un verrou, avec un intervalle de
liveness de 30 000 ms par défaut.

## Tranché : le détail est `liveness_lost:`, et `timeout:` n'existe nulle part

L'ensemble fermé des `detail` que peut porter `onPlayerReady(playerId, detail)`
est : la `note` passée à `release` (nettoyée, tronquée à 64 caractères),
`cleared`, `incarnated`, `resource_stopped`, `resource_reloaded`, et
`liveness_lost:<ressource>[,<ressource>…]`.

Le site annonce `no_holds` et `timeout:<resource>`. **Aucun des deux
n'existe** : recherche octet par octet, ASCII et UTF-16LE, dans toutes les
assemblies du serveur — zéro occurrence. Le site oublie par ailleurs
`incarnated`.

Le sens change aussi : `livenessIntervalMs` (ancien nom `timeoutMs`, c'est le
même champ) est un chien de garde **sur la ressource qui détient le verrou**,
pas une limite imposée au joueur. Un joueur peut passer une heure dans un
créateur de personnage sans que rien ne s'ouvre, tant que le détenteur bat le
rappel. La barrière ne s'ouvre de force que sur la preuve que le détenteur a
disparu.

**Conséquence pour le core.** `server/events.lua` teste
`detail:sub(1, 8) == "timeout:"` : cette branche est morte sur cette build, et
l'avertissement « ce verrou était le nôtre : le joueur est peut-être dans le
monde sans personnage » ne peut jamais se déclencher. Le préfixe à tester est
`liveness_lost:`.

## Tranché : la plateforme pose son propre verrou, et il n'a pas d'échéance

Chaque joueur qui se connecte arrive avec un verrou nommé `__platform`, posé
avant tout verrou de ressource, avec une échéance de liveness à `+Infinity`.
Aucun Lua ne peut le prendre ni le relâcher : `hold` et `release` refusent ce
nom (`reserved_resource`).

Il ne tombe que sur la **preuve** que le joueur est réellement incarné : le
client a annoncé `open77:session:gameplayReady`, ce qu'`open77_appearance`
n'émet qu'après avoir vu que l'attachement au monde est celui du gameplay (et
non le menu vanilla dans lequel tourne le créateur de personnage) et que le
pantin local est attaché, vivant et au-dessus de zéro point de vie. Le
`detail` correspondant est `incarnated`.

C'est ce qui donne son sens à une barrière ouverte : elle veut dire « ce joueur
est incarné et peut être téléporté, réanimé ou tué », pas « les autres
ressources ont fini ».

**Le revers, que le site nie.** `readiness-gate.md` affirme « A server where
nothing participates is a server where the gate is always open ». C'est vrai
des verrous de ressources, pas de celui-là. Sur un serveur dont l'ensemble de
ressources ne contient rien qui émette `open77:session:gameplayReady` — en
pratique `open77_appearance` — **la barrière de chaque joueur reste fermée pour
toujours**, `Open77.ready.isReady` reste `false`, `onPlayerReady` n'est jamais
émis, et le serveur journalise un `WRN` nommant `__platform` toutes les 60
secondes. Il n'y a ni délai, ni repli, ni sonde de substitution.

## Tranché : `Open77.state` existe, et la page « complète » l'ignore

`Open77.state.save(valeur)` / `.load()` / `.clear()` conservent un état
autoritaire à travers un **reload** de la ressource. Absent de
`server-api.md`, qui se présente pourtant comme l'inventaire complet ; décrit
sur `resource-runtime.md`, correctement pour l'essentiel.

Ce que le binaire ajoute et que la doc n'a pas :

- Une valeur dont le JSON dépasse **64 Kio lève** une erreur Lua ; elle ne rend
  pas `false`.
- Un `save` depuis un gestionnaire d'arrêt rend un `false` **nu**, sans
  seconde valeur : l'hôte prépare le successeur *avant* d'arrêter cette VM,
  donc il faut sauvegarder au moment du changement d'état, jamais au `stop`.
- L'hôte ne rend jamais de raison ; le seul retour à deux valeurs est le
  `unserialisable_state` de l'enveloppe Lua.
- L'état survit à un `reload` et **pas** à un `stop`/`restart`/`refresh` :
  c'est délibéré, pour qu'un opérateur garde un moyen de dire « remonte comme
  au démarrage ».

La valeur fait un aller-retour par JSON : ni fonction, ni coroutine, ni
métatable, ni cycle. Elle doit être traitée comme une entrée non fiable venant
d'une **version antérieure de son propre code** — c'est tout l'intérêt du
reload, la forme a pu changer.

**Ce que fait le core.** Rien pour l'instant. C'est le bon outil si le core
gagne un jour un état autoritaire qui ne vit pas en base.

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
