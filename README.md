# GearProof

**Ton équipement, confronté à ce que portent réellement les meilleurs joueurs de ta
spécialisation.** Pas un guide recopié : une mesure.

WoW Retail — Midnight, Interface `120007`. Aucune dépendance externe, rien à installer
à côté, rien à configurer.

---

## Ce qu'il fait

**Audit d'équipement.** Enchantements manquants, châsses vides, emplacements oubliés,
pièces abîmées, combinaison d'enchantements d'armes. Lu en direct sur tes objets.

**Comparaison à une référence mesurée.** Pour chaque emplacement, l'enchantement que
portent les 20 joueurs les mieux classés de ta spé, **avec leur taux d'adoption**. Un
conseil sans taux d'adoption serait un avis ; avec, c'est une mesure.

**Deux écoles quand il y en a deux.** Quand le haut de tableau se sépare en deux groupes
sur une statistique — la maîtrise à 21 % pour treize joueurs, à 38 % pour sept — la ligne
de priorité le dit au lieu d'afficher une moyenne à 27 % que personne ne joue.

**Ce qui dort dans tes sacs.** Les pièces que tu transportes et qui valent mieux que
celles que tu portes — en trois listes qui ne se mélangent jamais :

| Liste | Unité | Source |
|---|---|---|
| Simulé | % de DPS | un droptimizer Raidbots que tu as importé |
| Estimé | points de statistique pondérés | tes poids Pawn, estimation linéaire |
| Non chiffrable | niveau d'objet seulement | bijou (proc), pièce d'ensemble (bonus 2p/4p) |

Un bijou vaut par son proc, pas par ses points de statistique. Il reste **non chiffré**
tant qu'une simulation ne le couvre pas, plutôt que chiffré à tort.

**Table de butin par boss.** Les objets de chaque rencontre, lus dans le journal des
aventures du client et **filtrés sur ta spé**, avec l'écart de niveau d'objet contre ce
que tu portes. Importe un droptimizer et les estimations sont remplacées par du gain
mesuré, sur les objets qu'il couvre.

**Export SimulationCraft.** Chaîne prête à coller sur Raidbots. Quand l'addon officiel
SimulationCraft est installé, c'est **sa** chaîne qui est utilisée — elle fait autorité.

**Tournée de guilde.** Qui a un droptimizer à jour, qui a des correctifs en attente, et
quel boss couvre le plus de besoins. Passe par le canal de **données** de la guilde :
rien n'apparaît dans le chat, et **rien ne sort tant que tu n'as pas coché le partage**.

**Rappel à l'entrée en instance.** Donjon ou raid avec de l'équipement incomplet →
message dans le chat et avertissement central. Mieux vaut l'apprendre avant le pull.

---

## D'où viennent les chiffres

Aucune API du jeu n'expose « le meilleur enchantement du patch ». Le classement, lui,
est mesurable : on regarde ce qui est posé sur les personnages du haut de tableau.

Le relevé est produit **hors du jeu**, depuis l'API Warcraft Logs, et **livré avec
l'addon** — 40 spécialisations. Pour chacune : les enchantements par emplacement avec
leur part, les gemmes par rang de châsse, les combinaisons d'enchantements d'armes, la
répartition des statistiques secondaires. Chaque version apporte un relevé neuf ;
l'onglet Aide affiche l'âge de celui qui est installé.

**Trois règles tenues partout dans l'interface :**

- Rien n'est recopié d'un guide.
- Rien n'est inventé. Une valeur non mesurée est affichée comme non mesurée.
- Chaque ligne dit d'où vient son conseil.

C'est aussi pourquoi la jauge **compte** au lieu de noter : elle affiche le nombre de
correctifs en attente et combien d'emplacements vérifiés sont propres. Il n'y a pas de
score sur 100 — ce seraient quatre pénalités arbitraires déguisées en mesure.

---

## Installation

Par ton gestionnaire d'addons, ou à la main : décompresser dans

```
World of Warcraft\_retail_\Interface\AddOns\
```

Puis **redémarrer complètement le client** — WoW ne détecte un nouvel addon qu'au
démarrage, jamais sur `/reload`.

Rien à configurer. À la première connexion, la fenêtre s'ouvre seule sur l'onglet Aide.

### Tu viens de SpecAnalyser

GearProof reprend tes réglages — emplacements ignorés, poids de statistiques, lien de
droptimizer, habillage — mais il ne peut les lire **que si l'ancien addon est encore
activé** au moment où le nouveau démarre : WoW ne donne à un addon que ses propres
SavedVariables.

1. Installer `GearProof` **sans toucher** à `SpecAnalyser`.
2. Redémarrer le client, laisser les deux cochés, se connecter une fois. Un message
   confirme la reprise. Les deux addons tournent en parallèle le temps de cette
   connexion : deux icônes de minicarte, c'est normal.
3. Décocher `SpecAnalyser`, puis supprimer son dossier.

Sauter l'étape 2 ne casse rien — GearProof repart simplement d'une configuration neuve.

---

## L'interface

Fenêtre unique de 1040×660, redimensionnable, cinq onglets.

```
┌────────────────────────────────────────────────────────────────────────────┐
│ GearProof              [ Havoc · ta spécialisation ▾ ]   référence : …     │
│ Asnodh · Havoc · ilvl 662                                   poids : 3 j    │
│                                                                [Rafraîchir]│
│  [ Équipement ] [ Recommandations ] [ Raid ] [ Guilde ] [ Aide ]           │
├──────────────┬──────────────────────────────────┬──────────────────────────┤
│              │ 2 enchantements manquants · …    │          ╭───╮           │
│   mannequin  │                                  │         │  3  │  ← jauge │
│      3D      │ [!] Cape : Glissement du Void    │          ╰───╯           │
│              │     enchantement manquant        │   3 correctifs en attente│
│  ┌──┬──┬──┬─┐│     clic gauche : copier le nom  │   13 / 16 propres        │
│  │  │  │ !│  ││                                  │                          │
│  ├──┼──┼──┼─┤│ [!] Anneau 2 : 1 châssis vide    │  STATISTIQUES SECONDAIRES│
│  │  │ *│  │  ││                                  │  Hâte    ████████  18.7 %│
│  └──┴──┴──┴─┘│ GEMMES                           │  Critique ██████   12.4 %│
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

### Les cinq onglets

| Onglet | Contenu |
|---|---|
| **Équipement** | Grille, cartes de correctifs, gemmage par châsse, contenu des sacs, jauge, statistiques secondaires, priorité mesurée |
| **Recommandations** | Ce qu'il faut **poser** : l'enchantement de chaque emplacement avec son taux d'adoption, puis les gemmes les plus posées de ta spé — classées globalement, parce que le choix du châssis t'appartient |
| **Raid** | Rencontres et table de butin, filtrées sur ta spé. Un droptimizer remplace l'estimation par du gain mesuré |
| **Guilde** | Combien de membres sont prêts, quel gain la guilde a devant elle, et qui a besoin de quoi sur chaque boss |
| **Aide** | D'où vient la référence, comment lire l'onglet Équipement, questions fréquentes, signalement |

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
1.  /gp                      → ce qui manque, tout de suite
2.  Corriger enchants et gemmes
3.  Onglet Raid              → quel boss vaut le coup, objet par objet
```

Et si tu veux du gain **mesuré** plutôt qu'un écart de niveau d'objet :

```
4.  "Copier pour droptimizer" → coller sur raidbots.com/simbot/droptimizer
5.  "Coller le lien droptimizer" → coller le lien du rapport
6.  GearProof te rend l'adresse de ses données : l'ouvrir, tout copier, recoller
```

Neuf kilo-octets de texte, aucun outil à installer, pas de `/reload`. Les étapes 4 à 6
sont facultatives : sans elles l'audit fonctionne entièrement — il se contente de ne pas
chiffrer ce qu'il ne peut pas mesurer.

---

## Commandes

| Commande | Effet |
|---|---|
| `/gp` | Ouvre ou ferme la fenêtre |
| `/gp gear` | Onglet Équipement, et le résumé dans le chat |
| `/gp reco` | Onglet Recommandations |
| `/gp simc` | Copie la chaîne SimulationCraft |
| `/gp droptimizer` | Lien du droptimizer, et collage du rapport |
| `/gp weights <chaîne Pawn>` | Enregistre tes poids de statistiques |
| `/gp guild` | Onglet Guilde et tournée de guilde |
| `/gp options` | Panneau de réglages |
| `/gp theme` | Bascule l'habillage : sombre → minimal → Blizzard |
| `/gp lang <auto\|en\|fr>` | Langue de l'interface |
| `/gp alerts` | Active ou coupe le rappel à l'entrée en instance |
| `/gp minimap` | Affiche ou masque l'icône de minicarte |
| `/gp help` | Onglet Aide et liste des commandes |

`/gearproof` et `/sa` font la même chose que `/gp`.

---

## Poids de statistiques

Pour classer les objets de tes sacs en points de statistique, l'addon a besoin de tes
poids — ceux de **ta** simulation, pas d'une moyenne.

```
/gp weights ( Pawn: v1: "Havoc": Agility=1, CriticalStrike=0.81, Haste=0.94, ... )
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

## Signaler un bug, proposer une idée

Onglet **Aide**, carte du bas : les deux boutons préparent un texte prêt à coller, avec
la version, le build du client, ta classe, ton ilvl et ta langue déjà remplis — c'est
exactement ce qu'on demanderait sinon.

Licence MIT — voir [`LICENSE`](LICENSE). Provenance des données livrées :
[`NOTICE.md`](NOTICE.md). Historique des versions : [`CHANGELOG.md`](CHANGELOG.md).
