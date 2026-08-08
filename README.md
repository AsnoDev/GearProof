# SpecAnalyser

**Ton équipement, confronté à ce que portent réellement les meilleurs joueurs de ta
spécialisation.** Pas un guide recopié : une mesure.

WoW Retail — Midnight, Interface `120007`. Aucune dépendance externe.

---

## Ce qu'il fait

**Audit d'équipement.** Enchantements manquants, châsses vides, emplacements oubliés,
pièces abîmées, combinaison d'enchantements d'armes. Lu en direct sur tes objets.

**Comparaison à une référence mesurée.** Pour chaque emplacement, l'enchantement que
portent les 20 joueurs les mieux classés de ta spé, **avec leur taux d'adoption**. Un
conseil sans taux d'adoption serait un avis ; avec, c'est une mesure.

**Ce qui dort dans tes sacs.** Les pièces que tu transportes et qui valent mieux que
celles que tu portes — en trois listes qui ne se mélangent jamais :

| Liste | Unité | Source |
|---|---|---|
| Simulé | % de DPS | un droptimizer Raidbots que tu as importé |
| Estimé | points de statistique pondérés | tes poids Pawn, estimation linéaire |
| Non chiffrable | niveau d'objet seulement | bijou (proc), pièce d'ensemble (bonus 2p/4p) |

Un bijou vaut par son proc, pas par ses points de statistique. Il reste **non chiffré**
tant qu'une simulation ne le couvre pas, plutôt que chiffré à tort.

**Export SimulationCraft.** Chaîne prête à coller sur Raidbots. Quand l'addon officiel
SimulationCraft est installé, c'est **sa** chaîne qui est utilisée — elle fait autorité.

**Table de butin par boss.** Les objets que ton droptimizer a réellement simulés,
regroupés par rencontre, meilleur gain d'abord. Rien n'est fabriqué : la table de butin
affichée est celle que Raidbots a vue.

**Tournée de guilde.** Qui a un droptimizer à jour, qui a des correctifs en attente, et
quel boss couvre le plus de besoins. Passe par le canal de **données** de la guilde :
rien n'apparaît dans le chat, et **rien ne sort tant que tu n'as pas coché le partage**.

**Rappel à l'entrée en instance.** Donjon ou raid avec de l'équipement incomplet →
message dans le chat et avertissement central. Mieux vaut l'apprendre avant le pull.

---

## D'où viennent les chiffres

Aucune API du jeu n'expose « le meilleur enchantement du patch ». Le classement, lui,
est mesurable : on regarde ce qui est posé sur les personnages du haut de tableau.

Le relevé est produit **hors du jeu** par l'outil Python `specanalyser`, depuis l'API
Warcraft Logs, et livré avec l'addon dans `Data/Meta.lua` — 40 spécialisations. Pour
chacune : les enchantements par emplacement avec leur part, les gemmes par rang de
châsse, les combinaisons d'enchantements d'armes, la répartition des statistiques
secondaires.

**Trois règles tenues partout dans l'interface :**

- Rien n'est recopié d'un guide.
- Rien n'est inventé. Une valeur non mesurée est affichée comme non mesurée.
- Chaque ligne dit d'où vient son conseil.

C'est aussi pourquoi la jauge **compte** au lieu de noter : elle affiche le nombre de
correctifs en attente et combien d'emplacements vérifiés sont propres. Il n'y a pas de
score sur 100 — ce seraient quatre pénalités arbitraires déguisées en mesure.

---

## Installation

Copier le dossier `SpecAnalyser` dans :

```
World of Warcraft\_retail_\Interface\AddOns\
```

Puis **redémarrer complètement le client** — WoW ne détecte un nouvel addon qu'au
démarrage — et cocher `SpecAnalyser` dans la liste des addons.

Rien à configurer : la référence mesurée est livrée avec l'addon. À la première
connexion, la fenêtre s'ouvre seule sur l'onglet Aide.

---

## L'interface

Fenêtre unique de 1040×660, quatre onglets.

```
┌────────────────────────────────────────────────────────────────────────────┐
│ SpecAnalyser              [ Havoc · ta spécialisation ▾ ]   référence : …  │
│ Asnodh · Havoc · ilvl 662                                   poids : 3 j    │
│                                                                [Rafraîchir]│
│      [ Équipement ] [ Raid ] [ Guilde ] [ Aide ]                           │
├──────────────┬──────────────────────────────────┬──────────────────────────┤
│              │ 2 enchantements manquants · …    │          ╭───╮           │
│   mannequin  │                                  │         │  3  │  ← jauge │
│      3D      │ [!] Cape : Glissement du Void    │          ╰───╯           │
│              │     enchantement manquant        │   3 correctifs en attente│
│  ┌──┬──┬──┬─┐│     clic gauche : copier le nom  │   13 / 16 propres        │
│  │  │  │ !│  ││                                  │                          │
│  ├──┼──┼──┼─┤│ [!] Anneau 2 : 1 châssis vide    │  STATISTIQUES SECONDAIRES│
│  │  │ *│  │  ││                                  │  Hâte    ████████  18.7 %│
│  └──┴──┴──┴─┘│ GEMS                             │  Critique ██████    12.4 %│
│              │   Tête  + Éclat de Vide          │  …                       │
│  3 correctifs│   Cou   ! vide → Éclat de Vide   │  PRIORITÉ                │
│  ≥ 4 812 stat│                                  │  Hâte (40%) → Crit (29%) │
│              │ DANS TES SACS                    │                          │
│              │   simulé (% DPS)                 │  [ Lien droptimizer    ] │
│              │   +1,24 %  Gants  [objet] i275   │  [ Copier pour droptim.] │
└──────────────┴──────────────────────────────────┴──────────────────────────┘
```

**La grille**, à gauche : 16 cases de 44 px sous le mannequin. La bordure porte l'état
— vert `ok`, orange `manque quelque chose`, gris `vide` — et une pastille porte la
même information par un **glyphe** : `!` rouge si un enchantement ou une gemme manque,
`*` or si une meilleure pièce dort dans tes sacs. La couleur seule ne porte jamais
l'information : un daltonien deutan lit les mêmes états.

**Clic gauche** sur une case → la pièce s'ouvre dans un panneau de détail qui **reste
affiché**. **Clic droit** → ignorer l'alerte de cette pièce.

**Le total récupérable**, sous la grille : combien de points de statistique tu laisses
sur la table. C'est le chiffre qui décide si tu passes chez l'enchanteur maintenant.

### Les quatre onglets

| Onglet | Contenu |
|---|---|
| **Équipement** | Grille, cartes de correctifs, gemmage par châsse, contenu des sacs, jauge, statistiques secondaires, priorité mesurée |
| **Raid** | Rencontres et table de butin, façon journal des aventures. Alimenté par tes droptimizers |
| **Guilde** | Roster et couverture droptimizer, plus une sous-vue Raid : qui a besoin de quoi |
| **Aide** | Six cartes : d'où vient la référence, comment la garder à jour, comment lire l'onglet Équipement, questions fréquentes, signalement |

### Intégration aux infobulles

Sur un objet — sacs, hôtel des ventes, butin, marchand — l'addon ajoute uniquement ce
qui est **mesuré** : le gain simulé si un droptimizer le couvre, l'écart de niveau
d'objet contre la pièce portée, et l'enchantement relevé pour cet emplacement avec son
taux d'adoption. Rien d'estimé : une infobulle se lit en une seconde, sans le contexte
qui permettrait de relativiser une approximation.

### Icône de minicarte

Clic gauche : ouvrir. Clic droit : onglet Équipement. Glisser : déplacer. La pastille
passe verte, orange ou rouge selon l'état, sans avoir à ouvrir la fenêtre.

---

## La boucle d'utilisation

```
1.  /sa                      → ce qui manque, tout de suite
2.  Corriger enchants et gemmes
3.  "Copier pour droptimizer" → coller sur raidbots.com/simbot/droptimizer
4.  "Coller le lien droptimizer" → le lien du rapport revient dans l'addon
5.  Onglet Raid              → quel boss vaut le coup, objet par objet
```

Les étapes 3 à 5 sont facultatives. Sans droptimizer, l'addon fait déjà tout l'audit
d'équipement — il se contente de ne pas chiffrer ce qu'il ne peut pas mesurer.

---

## Commandes

| Commande | Effet |
|---|---|
| `/sa` | Ouvre ou ferme la fenêtre |
| `/sa gear` | Onglet Équipement, et le résumé dans le chat |
| `/sa bags` | Alias de `/sa gear` |
| `/sa guild` | Onglet Guilde et tournée de guilde |
| `/sa simc` | Copie la chaîne SimulationCraft |
| `/sa droptimizer` | Lien du droptimizer, prêt à copier |
| `/sa weights <chaîne Pawn>` | Enregistre tes poids de statistiques |
| `/sa lang <auto\|en\|fr>` | Langue de l'interface |
| `/sa theme` | Bascule l'habillage : sombre → minimal → Blizzard |
| `/sa alerts` | Active ou coupe le rappel à l'entrée en instance |
| `/sa minimap` | Affiche ou masque l'icône de minicarte |
| `/sa help` | Onglet Aide et liste des commandes |
| `/sa simcdiag` | Diagnostic de l'export SimulationCraft |
| `/sa debug` | Messages de debug |

`/specanalyser` fonctionne partout à la place de `/sa`.

---

## Poids de statistiques

Pour classer les objets de tes sacs, l'addon a besoin de tes poids — ceux de **ta**
simulation, pas d'une moyenne.

```
/sa weights ( Pawn: v1: "Havoc": Agility=1, CriticalStrike=0.81, Haste=0.94, ... )
```

Sans poids, une pièce se classe par niveau d'objet et porte la mention « demande une
simulation ». C'est délibéré : il y avait auparavant un repli qui dérivait les poids de
la répartition moyenne du haut de tableau, et il était **anti-corrélé** avec ce qu'il
prétendait mesurer — plus tu accumules une statistique, plus sa part grossit et moins
son point suivant vaut. Il poussait donc vers la statistique déjà saturée. Mieux vaut
ne rien classer que mal classer.

---

## Ce que l'addon ne fait pas

**Il n'analyse pas ton gameplay.** Depuis Midnight (patch 12.0), les événements de
combat sont des *secret values* : un addon peut les afficher, pas les lire, et
`COMBAT_LOG_EVENT_UNFILTERED` lève une erreur à l'enregistrement. Aucun addon ne peut
plus le faire — celui-ci ne fait pas semblant.

L'équipement, lui, n'a jamais été une donnée de combat : il est lu directement en jeu.

**Il n'équipe rien à ta place** et ne classe pas les bijoux par tier list. Un bijou vaut
par son proc ; un classement serait inventé.

**Il ne copie rien dans ton presse-papier** — WoW n'y a pas accès. Toute « copie » passe
par un champ de saisie déjà sélectionné : `Ctrl+A` puis `Ctrl+C`.

---

## Garder la référence à jour

Le relevé est livré avec l'addon et daté. Pour le régénérer toi-même, avec l'outil
Python `specanalyser` :

```bash
specanalyser wcl meta --zone <id> --all --to-addon      # le relevé du haut de tableau
specanalyser raidbots <lien du rapport> --to-addon      # tes propres gains simulés
```

Puis `/reload` en jeu : un fichier de données généré n'est lu qu'au chargement de
l'interface.

L'outil Python vit dans `C:\Claude\python\projets\specanalyser`.

---

## Développement

```bash
tools\check_addon.cmd
```

Syntaxe, encodage, cohérence des traductions, références croisées entre modules. À
lancer après toute modification, avant de copier dans le dossier de jeu — aucun
interpréteur Lua n'est installé sur la machine de développement.

L'architecture, les décisions techniques et les pièges d'API rencontrés sont dans
[`CLAUDE.md`](CLAUDE.md).
