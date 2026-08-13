# GearProof — addon (contexte)

Partie in-game du projet GearProof. Le contexte complet, les décisions d'architecture et
le journal de sessions sont dans **`C:\Claude\python\projets\specanalyser\CLAUDE.md`** et
**`JOURNAL.md`** du même dossier — les lire avant toute modification ici.

## Règle absolue

Depuis Midnight (12.0), cet addon **ne lit aucune donnée de combat**. Interdits :

- `COMBAT_LOG_EVENT` / `COMBAT_LOG_EVENT_UNFILTERED` (lèvent une erreur à l'enregistrement)
- toute logique basée sur une *secret value* : PV, ressources, cooldowns, auras en combat

Autorisé **et utilisé ici** : équipement, châsses, enchantements, ilvl, durabilité, spé,
talents, sacs, infobulles, journal des aventures, canal de données de guilde. Rien de tout
cela n'a jamais été une donnée de combat — la contrainte Midnight coûte donc très peu à ce
produit précis, et il ne faut pas s'en servir pour expliquer une limite qu'elle n'impose pas.

Autorisé mais **plus utilisé** : `LoggingCombat` et la CVar `advancedCombatLogging`. Ils
servaient à la moitié « analyse de gameplay » du produit, retirée le 2026-08-03 ; le
journal fichier reste la source de vérité de l'outil Python, pas de l'addon.

## Fichiers

### Socle

| Fichier | Rôle |
|---|---|
| `Core.lua` | Namespace `ns`, SavedVariables, dispatch d'événements sous `pcall`, `/sa` |
| `Locale.lua` | **Mécanisme** de traduction : la table `L`, `ns.Localize` (retient les libellés posés une fois, pour le changement de langue à chaud), `ns.ApplyLanguage` |
| `Locale/fr.lua` | **Données** de traduction. La clé EST le texte anglais, donc l'anglais n'a pas de fichier. Une langue de plus = un fichier, une ligne dans `CLIENT_MAP`, une dans `ns.LANGUAGES`, une dans le `.toc` |
| `Theme.lua` | Trois habillages (`dark` par défaut, `minimal`, `blizzard`), registre de cadres + `Theme.Track` pour les cartes hors cadre enregistré |
| `Copy.lua` | Fenêtre de copie partagée (WoW n'accède pas au presse-papier) |
| `ItemInfo.lua` | **Lecteur unique** de `GetItemInfo` : les 17 positions nommées, une fois |
| `ItemLink.lua` | Découpage de chaîne d'objet : enchant, gemmes, bonus, modificateurs |
| `Pool.lua` | Pool de widgets partagé par les vues, avec remise à neuf |
| `Journal.lua` | **Seul** accès au journal des aventures : pose, lit, restaure la sélection |
| `Options.lua` | Panneau de réglages dans les Options d'interface du client |

### Données

| Fichier | Rôle |
|---|---|
| `Spec.lua` | Spés de la classe, spé active, spé regardée (aperçu) |
| `Stats.lua` | Statistiques secondaires et paliers de rendement décroissant |
| `Meta.lua` | Lecture du relevé + contrôle de version du format |
| `Sim.lua` | Gains simulés, regroupement par rencontre, liens de butin |
| `Recommendations.lua` | Façade : table éditable, sinon le relevé |
| `Weights.lua` | Poids de statistiques depuis une chaîne Pawn — **aucun repli dérivé** |
| `Data/Meta.lua` | **Généré et livré** : relevé des 40 spés — ne jamais éditer à la main |
| `Data/Sim.lua` | **Généré** depuis tes droptimizers — ne jamais éditer à la main |

### Métier

| Fichier | Rôle |
|---|---|
| `Gear.lua` | Audit d'équipement, **mémoïsé** (TTL 2 s + invalidation par événement) |
| `Bags.lua` | Comparaison sacs/équipé en trois unités, filtrage d'utilisabilité, **mémoïsé** |
| `SimC.lua` | Export SimulationCraft, délégué à l'addon officiel quand il est présent |
| `Guild.lua` | Tournée de guilde : canal authentifié, throttle en réponse, file d'envoi |

### Présentation

| Fichier | Rôle |
|---|---|
| `Armory.lua` | Grille : modèle 3D + 16 cases colorées par état |
| `Gauge.lua` | Jauge circulaire — **compte** les correctifs, ne note pas |
| `GearView.lua` | Onglet Équipement, colonnes gauche et centre : grille, verdict, cartes de correctif (une ligne de 28 px), gemmes, détail, sacs |
| `GearSide.lua` | Onglet Équipement, colonne droite : jauge, barres de stats, priorité, ensemble de classe, bloc droptimizer. Interface réduite à `Create(parent)` / `Refresh(summary)`, pool de lignes propre |
| `RaidView.lua` | Onglet Raid : rencontres et table de butin |
| `GuildView.lua` | Onglet Guilde : roster et sous-vue Raid |
| `RecoView.lua` | Onglet Recommandations : ce qu'il faut POSER, par categorie |
| `HelpView.lua` | Onglet Aide : six cartes |
| `UI.lua` | Coquille : entête, onglets, déroulant de spé, position/taille persistantes |
| `Minimap.lua` | Icône de minicarte maison, sans librairie externe |
| `Tooltip.lua` | Intégration dans les infobulles d'objets : sacs, HdV, butin |
| `Alerts.lua` | Audit automatique à l'entrée en donjon ou raid |

L'ordre de chargement du `.toc` compte : socle → `Data/*` → `Spec.lua` → `Stats.lua` →
`Meta.lua`/`Sim.lua` → `Gear.lua` → `Bags.lua` → les vues → `UI.lua`. `Meta.lua` dépend de
`Spec.lua` pour savoir quelle spé regarder ; `UI.lua` instancie les vues.

## Deux écoles dans une même spé

`RecoView.lua` → catégorie **Général** lit `modes`, la seule donnée du relevé qui dise
qu'une **moyenne ne décrit personne**.

Le générateur teste si la répartition d'une statistique est bimodale : deux groupes
séparés plutôt qu'un nuage autour d'une moyenne. Une spé dont la maîtrise se joue soit
à 21 % (13 joueurs) soit à 38 % (7 joueurs) n'a pas de cible à 27 % — viser la moyenne,
c'est ne jouer aucun des deux builds. `Meta.Modes()` filtre sur un écart ≥ 8 points et
≥ 3 joueurs par groupe : des seuils d'**affichage**, en dessous desquels deux groupes
proches ne racontent rien de plus qu'une moyenne. Il dit aussi de quel côté tu es, sans
verdict.

Aucun concurrent n'a l'équivalent, et pour cause : il faut le relevé brut pour le
calculer. C'est le différenciant qu'il ne faut pas perdre une seconde fois.

Reste non lu dans les données : `p25` / `p75` / `spread` — la dispersion. Une piste, pas
une dette : ils diraient si le top 20 est resserré ou dispersé sur une statistique.

Les ~66 clés de locale encore orphelines sont d'anciens libellés de cet onglet non
repris par la reconstruction. `tools/check_locale.py` les signale : c'est attendu tant
que la mise en page n'est pas figée.

## Validation

```bash
tools\check_addon.cmd
```

Quatre vérificateurs qui **lisent** le code — syntaxe (luaparser), encodage (UTF-8 strict,
mojibake, CRLF), cohérence des traductions (doublons, clés manquantes, orphelines),
références croisées — puis deux suites qui l'**exécutent**.

`check_refs.py` porte trois constats, et le troisième vient d'une panne réelle : une
constante en majuscules **lue** mais déclarée nulle part. Le contrôle des globales ne
regardait que les *écritures*, donc `SetSize(ROSTER_WIDTH, 1)` a survécu au retrait de
`ROSTER_WIDTH` — lire une globale absente ne lève rien en Lua, c'est l'API du client qui
refuse, bien plus tard, en avortant la construction de la fenêtre entière.

`tools/test_lua.py` charge les fichiers dans **Lua 5.1** via `lupa` : la version exacte du
client, `unpack` global et `table.unpack` absent. Deux familles de tests :

- **Chargement de tout le `.toc`**, dans l'ordre du client. C'est le test le plus rentable
  du dépôt : trois des pires pannes étaient des erreurs de chargement, dont un retour à la
  ligne littéral dans une chaîne que `luaparser` acceptait et que WoW refusait — l'onglet
  Raid est resté noir deux commits.
- **Fonctions pures** dont une erreur ne lève rien : `ItemLink.Parse`, `Weights.ParsePawn`,
  `Meta.WeaponPairAdvice`, `Guild.chunkPayload`, `SimC.itemLine`, `Core.migrateSchema`,
  `Sim.pruneReports`.

Aucune entrée de test n'existe dans le code livré : `tools/luaenv.py` exploite le fait
qu'un `local` de portée fichier est encore visible à la fin du chunk, et concatène un
`return { ... }` avant de compiler.

`tools/strictload.py` rejoue le **démarrage complet** sous `tools/wowstrict.lua`, un stub
d'API qui connaît les méthodes de chaque type de widget, lève sur une méthode appartenant
à un autre type, et **vérifie les arguments** de `SetSize`/`SetWidth`/`SetPoint`. Trois
conditions sans lesquelles il ne trouve rien, chacune apprise d'un bug qui est passé :

| Condition | Ce qu'elle attrape |
|---|---|
| Rejouer les **événements** (`ADDON_LOADED`, `PLAYER_LOGIN`) | `ns.db` n'existe qu'après — sans ça tout échoue pour la mauvaise raison |
| Rafraîchir **deux fois** | La remise à neuf d'un pool ne tourne jamais au premier rendu |
| **Trois** états d'équipement (incomplet, complet, nu) | Un équipement parfait emprunte une branche entièrement différente |

Toute modification d'un vérificateur se teste **dans les deux sens** : zéro erreur sur
l'arbre propre, exactement l'erreur attendue quand le bug est réintroduit.

```bash
tools\package.cmd
```

Fabrique le zip CurseForge dans `../_dist`, racine `GearProof/`. Il refuse de produire
quoi que ce soit si la validation échoue, si `LICENSE`/`CHANGELOG.md` manquent, ou si
`## X-Website` porte encore son gabarit.

## Interface

Fenêtre 1040×660 redimensionnable, cinq onglets : Équipement, Recommandations, Raid,
Guilde, Aide.

`Armory` (191 de large) : `PlayerModel` de 236 px surmontant une grille de 4×4 cases de 44 px.
La bordure de chaque case est une texture pleine sous l'icône : vert `ok`, orange `manque`,
gris `vide`, avec une pastille `!` ou `*` — la couleur seule ne porte jamais l'information.

Les vues reconstruisent leur contenu à chaque affichage depuis des pools de widgets : rien
n'est détruit, tout est masqué puis réutilisé. La mise en page est un empilement vertical qui
accumule un `top` négatif.

Deux pièges de mise en page, tous deux rencontrés :

- **La largeur d'un cadre ancré n'est pas résolue à la création.** Tout dimensionnement de
  texte se fait dans `Refresh()`, jamais dans `Create()`.
- **Les décalages en pixels codés en dur se propagent.** Un bloc ajouté dans la colonne
  droite décale tout ce qui suit ; le bouton de spé a un jour recouvert l'origine de la jauge
  et le titre d'une carte de l'onglet Aide parce que tous les hôtes commencent au même `y`.

## Pièges d'API rencontrés

- `GetItemInfo` renvoie **17 valeurs** : `equipLoc` est la 9ᵉ et `setID` la 16ᵉ. Compter
  les underscores à la main a déjà produit un décalage de deux positions. Il y a
  désormais **un seul lecteur**, `ItemInfo.lua`, avec les 17 positions nommées : ne
  jamais rappeler `GetItemInfo` directement ailleurs.
- `pcall` renvoie son booléen en première position : indexer `results[1 + N]` plutôt que
  de retirer l'élément, sinon un `nil` au milieu crée un trou et décale tout.
- **Chaîne d'objet : le compteur de bonus est le 13ᵉ champ**, pas le 14ᵉ. Ordre complet
  (`warcraft.wiki.gg/wiki/ItemString`) : `itemID`, `enchantID`, 4 gemmes, `suffixID`,
  `uniqueID`, `linkLevel`, `specializationID`, `modifiersMask`, `itemContext`,
  `numBonusIDs`, les bonus, `numModifiers`, puis des paires (type, valeur). Lu au 14ᵉ, le
  compteur valait le premier identifiant de bonus (12214 au lieu de 9) : l'export SimC
  perdait son premier bonus et récupérait à la place le bloc de modificateurs. C'est la
  cause du « le SimC ne fonctionne pas » du 2026-08-03. Vérifié depuis contre un export
  officiel, 5 emplacements sur 5 identiques au caractère près.
- **`C_Item.GetItemStats` ignore les champs de décoration de la chaîne d'objet** : ni
  l'enchantement (champ 2), ni les gemmes (champs 3-6). Elle dérive les statistiques de
  l'itemID et des bonusIDs. Conséquence : comparer `GetItemStats(nu)` à
  `GetItemStats(enchanté)` renvoie **zéro par construction**, jamais une valeur d'enchant.
  La preuve était déjà dans le dépôt : `socketCount` fonctionne précisément parce que
  l'API rend le nombre *total* de châssis même quand des gemmes sont serties. La seule
  source in-game qui voit un enchantement est **le rendu d'infobulle** du client — voir
  `Meta.EnchantTooltipLines`, qui diffe l'infobulle de l'objet nu et celle du lien forgé.
  Comparer par **texte de ligne**, jamais par index de ligne.
- **Habillage** : `Theme.Apply(frame)` enregistre le cadre ; `Theme.Toggle`/`Theme.Set`
  rejouent l'habillage sur tout le registre via `Theme.Refresh`. Toute nouvelle fenêtre
  doit appeler `Theme.Apply` une fois à sa création — sinon elle garde le cadre du client
  (c'était le cas de `GearProofCopyPopup` et `SpecAnalyserGearInfo`). `Theme.Apply`
  masque **toutes** les textures directes du cadre et de `frame.Inset` : une zone qui
  comptait sur le fond de l'inset doit se donner son propre cadre et le déclarer dans
  `frame.themeCards`. Ne jamais appeler `Theme.Apply` sur une carte issue des pools de
  `GearView` : ces cartes passent par `Theme.ApplyCard`.
- Modificateurs utiles à SimulationCraft : **28** = `content_tuning`, **29/30** =
  `crafted_stats`, **38** = `crafting_quality` (palier 1 à 5 ; hors plage, on n'écrit rien
  plutôt que d'inventer).
- `GetProfessionInfo` : le **7ᵉ** retour est la ligne de métier. Passer par cet identifiant
  et non par le nom affiché, qui est traduit.
- `GetSpecializationInfo` : la **6ᵉ** valeur est la statistique principale. C'est ce qui
  donne `role=` sans coder de table de spés en dur (Intelligence → `spell`, sinon
  `attack`, `TANK` → `tank`). Devourer est une spé d'Intelligence.
- L'addon ne peut pas écrire dans le presse-papier : toute « copie » passe par un `EditBox`
  présélectionné (`Copy.lua`).

## Analyse d'équipement

`Gear.Scan()` lit la chaîne de chaque objet équipé : champ 2 = enchantement, champs 3 à 6
= gemmes. Le nombre de châssis vient de `C_Item.GetItemStats` (clés `EMPTY_SOCKET_*`), qui
retourne le total de l'objet — les châssis vides se déduisent par différence avec le nombre
de gemmes serties. La liste des emplacements enchantables est en haut du fichier, en dur et
commentée : c'est une donnée de patch, pas une déduction possible depuis l'API.

## Conventions

- Interface `120007` (12.0.7) — mettre à jour à chaque patch majeur.
- Tout appel d'API susceptible de disparaître passe par `pcall`, y compris
  `RegisterEvent` : un événement retiré par Blizzard doit coûter sa fonctionnalité, pas
  le chargement du fichier entier.
- Toute table dont le contenu dépend du patch porte un commentaire `DONNEE DE PATCH`
  avec la version vérifiée. `grep "DONNEE DE PATCH"` liste ce qu'un patch peut casser.
- Pas de dépendance externe (pas d'Ace3) : l'addon reste minimal par choix.
- Fins de ligne **LF** partout, encodage UTF-8 sans BOM. Vérifié automatiquement : deux
  chaînes ont déjà été livrées en double encodage et s'affichaient cassées en jeu.
- Toute chaîne vue par le joueur passe par `ns.L` ou `ns.Localize`. Cinq fichiers
  sortaient du français codé en dur dans un addon annoncé en anglais.
