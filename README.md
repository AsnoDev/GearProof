# SpecAnalyser — addon (partie in-game)

Addon WoW Retail (Midnight, Interface `120007`). Il fait quatre choses, et **rien** de ce
que Blizzard a interdit depuis le patch 12.0 :

1. **Journalisation automatique** — active `advancedCombatLogging` puis `/combatlog` en
   entrant en raid, donjon ou clé mythique+, et l'arrête en sortant.
2. **Snapshot de session** — écrit dans les SavedVariables : spé, chaîne de talents,
   ilvl, équipement, niveau de clé, liste des rencontres et leur résultat.
3. **Analyse d'équipement** — enchantements et gemmes manquants, en direct, sans outil
   externe.
4. **Affichage des rapports** — lit `Data/Reports.lua`, généré par l'outil Python.

## Ce que l'addon ne fait pas (et ne peut pas faire)

Depuis Midnight, `COMBAT_LOG_EVENT_UNFILTERED` lève une erreur à l'enregistrement et les
données de combat sont des *secret values* : un addon peut les afficher, pas les lire.
L'analyse de gameplay est donc faite hors-jeu à partir de `WoWCombatLog.txt`. L'équipement,
lui, n'est pas une donnée de combat : il est lu directement en jeu.

## Installation

Copier le dossier `SpecAnalyser` dans :

```
World of Warcraft\_retail_\Interface\AddOns\
```

Puis **redémarrer complètement le client** — WoW ne détecte un nouvel addon qu'au
démarrage — et cocher `SpecAnalyser` dans la liste des addons.

## L'interface

Fenêtre unique de 940×640, construite comme une armurerie :

```
┌──────────────────────────────────────────────────────────────────────┐
│ SpecAnalyser                              [x] Log automatique        │
│ Asnodh · Devourer · ilvl 662                     log en cours        │
├──────────────────────┬───────────────────────────────────────────────┤
│  [tête]      [gants] │ Equipement │ Analyse │ Historique │ Aide      │
│  [cou]       [ceint] │                                               │
│  [épaul]  ▟  [jambe] │ Equipement                                    │
│  [cape]  ▐█▌ [bottes]│ 2 enchantements manquants · 1 châssis vide    │
│  [torse]  ▜  [ann 1] │                                               │
│  [bracl]     [ann 2] │ A CORRIGER                                    │
│              [bij 1] │   Cape    enchantement manquant               │
│              [bij 2] │   Anneau 2  1 châssis vide                    │
│    [arme] [m.gauche] │                                               │
│  ok  manque  vide    │ DETAIL COMPLET …                              │
└──────────────────────┴───────────────────────────────────────────────┘
```

**À gauche** : ton personnage en 3D (rotation à la souris), encadré par ses emplacements
d'équipement. Chaque case est bordée de vert (ok), d'orange (il manque quelque chose) ou de
gris (vide), avec un `!` sur les cases à problème. Survole une case pour l'infobulle de
l'objet suivie de ce qui lui manque.

**À droite**, trois onglets dans l'entête (plus `Aide` en bas à droite) :

| Onglet | Contenu |
|---|---|
| **ÉQUIPEMENT** | Résumé, liste des pièces à corriger, puis le détail emplacement par emplacement |
| **ANALYSE** | Entête du run, carte *statistiques clés*, *chronologie des cooldowns*, les trois choses à travailler, le reste, les points forts |
| **HISTORIQUE** | Menu déroulant à deux groupes — **Donjons** et **Raids** — qui ouvre l'analyse du run choisi |

### L'onglet Analyse

- **Statistiques clés** : score sur 100 avec jauge colorée et verdict (SOLIDE / CORRECT /
  MOYEN / FRAGILE), puis les neuf mesures du run avec leur icône.
- **Chronologie des cooldowns** : une ligne par sort suivi. Meta en segments continus,
  Void Ray, Collapsing Star, Blur et les morts en repères. Uptime Meta affiché à droite.
- **Les trois choses à travailler** : une carte par constat, bordée par sa sévérité, avec
  le détail et les **horodatages cliquables**. Cliquer `[16:43]` ouvre la séquence de casts
  autour de cet instant — l'instant lui-même surligné.
- **Partager** : ouvre un résumé texte sélectionnable (Ctrl+A, Ctrl+C).

### L'historique

Un bouton ouvre un menu déroulant à deux groupes :

```
[ Choisir un run                                            ▾ ]
┌──────────────────────────────────────────────────────────────┐
│ DONJONS                                            4 run(s)  │
│   02/08 21:04  Ara-Kara +12        analyse   dans les temps  │
│   01/08 15:11  Pit of Saron +11    analyse   2/3 boss        │
│ RAIDS                                              2 run(s)  │
│   28/07 21:30  Sporefall (Mythic)            3/8 boss        │
└──────────────────────────────────────────────────────────────┘
```

Choisir une ligne marquée `analyse` **bascule directement sur l'onglet Analyse, sur ce run
précis**. Une ligne sans marqueur n'a pas encore été analysée — le détail rappelle alors la
commande à lancer.

Le rapprochement session ↔ analyse se fait sur le nom d'instance puis sur l'écart de date.
Les analyses sans session correspondante (import Warcraft Logs, run joué avant
l'installation de l'addon) restent listées, marquées `analyse seule`.

**En haut à droite** : l'interrupteur `Log automatique`. Coché, l'addon lance `/combatlog`
en entrant en instance et l'arrête en sortant. Décoché, il ne touche à rien. La ligne
au-dessous dit l'état réel : *log en cours*, *en attente : Ara-Kara +12*, ou *inactif*.

L'icône de minicarte : clic gauche pour ouvrir, clic droit pour l'équipement, glisser pour
la déplacer. Son infobulle résume l'état sans ouvrir la fenêtre. À la toute première
connexion, la fenêtre s'ouvre seule sur l'onglet explicatif.

## L'onglet Équipement

- **Cartes d'action** : *Priorité absolue* (rouge — arme non enchantée, emplacement vide,
  pièce abîmée), *Optimisations* (orange — le reste), puis un *Détail complet* repliable.
- **Survol d'une ligne** → la case correspondante s'illumine sur le mannequin.
  **Clic gauche** → fiche de la pièce et conseils. **Clic droit** → ignorer l'alerte.
- **Statistiques secondaires** : quatre jauges avec valeur brute, pourcentage et palier de
  rendement décroissant atteint.
- **Ensemble et bijoux** : nombre de pièces d'ensemble et état des bonus 2p/4p.
- **Copier SimC** : chaîne SimulationCraft prête à coller sur Raidbots.

Sur le mannequin, chaque case porte son niveau d'objet coloré par la qualité, un `!` rouge
si l'enchantement manque et une icône de châssis si une gemme manque.

## Alertes et habillage

- Entrée en donjon ou raid avec de l'équipement incomplet → message dans le chat et
  avertissement central. `/sa alerts` pour désactiver.
- La pastille de la minicarte passe verte, orange ou rouge selon l'état.
- `/sa theme` bascule entre le cadre Blizzard et un fond sombre à bordure fine.

## Analyse d'équipement

Lit la chaîne de chaque objet équipé et compare :

- **Enchantement** : absent ou présent, sur cape, torse, bracelets, jambes, bottes, les
  deux anneaux, l'arme, et la main gauche si c'en est une.
- **Gemmes** : nombre de châssis de l'objet contre nombre de gemmes serties.
- **Emplacement vide** : une pièce oubliée après un changement de stuff.

La liste des emplacements enchantables est en haut de `Gear.lua` — une ligne à ajouter si
un patch en introduit un nouveau. L'addon dit **ce qui manque**, pas quel produit acheter :
le meilleur enchantement dépend du patch et de ta spé.

## Commandes

| Commande | Effet |
|---|---|
| `/sa` | Ouvre la fenêtre |
| `/sa gear` | Équipement : ce qui manque, aussi dans le chat |
| `/sa help` | Onglet explicatif + liste des commandes |
| `/sa status` | État de la journalisation |
| `/sa log on\|off` | Force la journalisation |
| `/sa auto` | Bascule la journalisation automatique |
| `/sa sessions` | Liste les sessions enregistrées |
| `/sa minimap` | Affiche ou masque l'icône de minicarte |
| `/sa purge` | Vide l'historique |
| `/sa debug` | Messages de debug |

## Boucle d'utilisation

```
1. Jouer une clé / un raid              → l'addon logge tout seul
2. specanalyser analyze --last --to-addon → l'outil Python écrit Data/Reports.lua
3. /reload puis /sa                      → le rapport s'affiche en jeu
```

L'outil Python vit dans `C:\Claude\python\projets\specanalyser`.
