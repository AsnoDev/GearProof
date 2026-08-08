# SpecAnalyser — addon (contexte)

Partie in-game du projet SpecAnalyser. Le contexte complet, les décisions d'architecture et
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

| Fichier | Rôle |
|---|---|
| `Core.lua` | Namespace `ns`, SavedVariables `SpecAnalyserDB`, dispatch d'événements, `/sa` |
| `Locale.lua` | Traductions ; la **clé est le texte anglais**, donc rien ne manque jamais |
| `Theme.lua` | Trois habillages (`dark` par défaut, `minimal`, `blizzard`) + registre de cadres |
| `Copy.lua` | Fenêtre de copie partagée (WoW n'accède pas au presse-papier) |
| `Spec.lua` | Spés de la classe, spé active, spé regardée (aperçu) |
| `Meta.lua` | Lecture du relevé : enchants, gemmes par châsse, paires d'armes, stats, auras |
| `Sim.lua` | Gains simulés, regroupement par rencontre, liens de butin du journal |
| `Recommendations.lua` | Façade : table éditable, sinon le relevé |
| `Weights.lua` | Poids de statistiques depuis une chaîne Pawn — **aucun repli dérivé** |
| `Gear.lua` | Audit d'équipement : enchants, gemmes, durabilité, set, paire d'armes |
| `Bags.lua` | Comparaison sacs/équipé, en trois unités jamais mélangées |
| `SimC.lua` | Export SimulationCraft, délégué à l'addon officiel quand il est présent |
| `Guild.lua` | Tournée de guilde sur le canal de données, fraîcheur, gains par rencontre |
| `Armory.lua` | Grille : modèle 3D + cases d'équipement colorées par état |
| `Gauge.lua` | Jauge circulaire — **compte** les correctifs, ne note pas |
| `GearView.lua` | Onglet Équipement : cartes, gemmes, détail d'objet, barres de stats |
| `RaidView.lua` | Onglet Raid : rencontres et table de butin, façon journal des aventures |
| `GuildView.lua` | Onglet Guilde : roster et sous-vue Raid |
| `HelpView.lua` | Onglet Aide : six cartes |
| `UI.lua` | Coquille : entête, onglets, déroulant de spé |
| `Minimap.lua` | Icône de minicarte maison, sans librairie externe |
| `Tooltip.lua` | Intégration dans les infobulles d'objets : sacs, HdV, butin |
| `Alerts.lua` | Audit automatique à l'entrée en donjon ou raid |
| `Data/Meta.lua` | **Généré et livré** : relevé des 40 spés — ne jamais éditer à la main |
| `Data/Sim.lua` | **Généré** depuis tes droptimizers — ne jamais éditer à la main |

L'ordre de chargement du `.toc` compte : `Data/*` → `Spec.lua` → `Meta.lua`/`Sim.lua` →
`Gear.lua` → les vues → `UI.lua`. `Meta.lua` dépend de `Spec.lua` pour savoir quelle spé
regarder ; `UI.lua` instancie les vues.

## Interface

Fenêtre 1040×660, quatre onglets : Équipement, Raid, Guilde, Aide.

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
  les underscores à la main a déjà produit un décalage de deux positions. `Gear.itemInfo`
  indexe désormais une table de résultats, avec les positions nommées en constantes.
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
  (c'était le cas de `SpecAnalyserCopyPopup` et `SpecAnalyserGearInfo`). `Theme.Apply`
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

## Vérification syntaxique

Aucun interpréteur Lua n'est installé sur la machine. Pour valider avant de copier dans le
dossier de jeu :

```bash
C:/Claude/python/projets/specanalyser/.venv/Scripts/python.exe -c "from luaparser import ast; from pathlib import Path; [ast.parse(p.read_text(encoding='utf-8')) for p in Path(r'C:/Claude/lua/projets/SpecAnalyser').rglob('*.lua')]; print('ok')"
```

## Conventions

- Interface `120007` (12.0.7) — mettre à jour à chaque patch majeur.
- Tout appel d'API susceptible de disparaître passe par `pcall` : une API supprimée ne
  doit jamais empêcher la journalisation de démarrer.
- Pas de dépendance externe (pas d'Ace3) : l'addon reste minimal par choix.
