# Journal des versions

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Versionnement sémantique — `MAJEUR.MINEUR.CORRECTIF`.

- **MAJEUR** : le format de `Data/Meta.lua` change, ou les SavedVariables ne sont plus
  lisibles par la version précédente.
- **MINEUR** : un onglet, une source de données, une langue.
- **CORRECTIF** : correction sans changement de forme des données.

## [Non publié]

### Modifié

- **Import d'un droptimizer : un aller-retour au lieu de deux.** L'adresse du fichier de
  résultats est simplement celle du rapport suivie de `/data.csv` — Raidbots le documente,
  et la page du rapport y mène en un clic par son menu `⋯ Raw Files`. L'addon affirmait le
  contraire et faisait donc revenir le joueur une fois pour rien : la fenêtre le dit
  maintenant **avant** qu'il ne parte. Coller le lien du rapport reste accepté, en repli.
- **L'adresse Raidbots vient avant la chaîne à copier.** C'est l'ordre des gestes : on
  ouvre la page, puis on colle dedans. Le presse-papier ne garde qu'une chose à la fois,
  donc copier avant de savoir où coller obligeait à revenir chercher.
- L'adresse du CSV utilise la forme documentée `raidbots.com/simbot/report/<id>/data.csv`
  au lieu d'une forme que le site ne construit jamais lui-même.

### Corrigé

- **Le collage du CSV répondait « nothing readable in that paste » sur une donnée
  valide.** La fenêtre Droptimizer posait des champs de saisie d''**une seule ligne**, là
  où les deux textes qui y transitent en font des dizaines : la chaîne SimulationCraft et
  le CSV du rapport. Un champ d''une ligne perd les retours à la ligne, le CSV arrivait
  donc en un bloc, et l''analyseur n''y trouvait plus sa ligne de référence. Les deux
  zones sont maintenant multi-lignes avec ascenseur, comme la fenêtre de copie.
- **Un droptimizer importé en collant directement le CSV comptait comme absent** dans
  l'appel de guilde et n'avait aucune date de fraîcheur : seul le collage d'un *lien*
  enregistrait quelque chose. Les gains, eux, s'affichaient — rien ne signalait l'écart.
  La colonne Droptimizer mesure désormais une fraîcheur, pas la possession d'un lien.

## [0.5.0] — 2026-08-10

Première version sous le nom GearProof. L'addon s'appelait SpecAnalyser, un nom qui
promettait une analyse de spécialisation qu'il ne fait plus depuis que Midnight a fermé
l'accès aux événements de combat.

### Ajouté

- **Onglet Raid sans outil externe.** Les tables de butin sont lues dans le journal des
  aventures du client, filtrées sur ta spécialisation, avec l'écart de niveau d'objet
  contre ce que tu portes. Un droptimizer remplace ensuite l'estimation par du gain
  mesuré, sur les objets qu'il couvre.
- **Import d'un droptimizer sans rien installer.** Colle le lien du rapport, GearProof
  te rend l'adresse de ses données, tu la copies, tu la recolles. Neuf kilo-octets.
- **Onglet Recommandations** — enchantements par emplacement avec taux d'adoption, et
  les gemmes les plus posées de ta spécialisation, classées globalement.
- **Détection de deux builds.** Quand le relevé montre que le haut de tableau se sépare
  en deux groupes sur une statistique, la ligne de priorité le dit : viser la moyenne,
  c'est ne jouer aucun des deux.
- **Bande de chiffres de guilde** — combien de membres sont prêts, quel gain la guilde a
  devant elle, combien ont encore des correctifs.
- Panneau de réglages dans les Options d'interface du client.
- État de l'ensemble de classe (2p/4p) sur l'onglet Équipement.
- Fenêtre redimensionnable, position et taille conservées.
- Tampon de déploiement dans la barre de titre.

### Modifié

- Interface en **anglais et français uniquement**. Les traductions allemande, italienne
  et espagnole couvraient 20 % des chaînes : une interface à moitié traduite se lit
  comme un addon cassé, pas comme un addon anglais.
- La fenêtre est opaque. Les 4 % de transparence laissaient passer l'interface du joueur
  au milieu des données.
- L'onglet Recommandations passe de six catégories à deux sections. Quatre d'entre elles
  redisaient d'autres onglets ou n'étaient pas actionnables.

### Corrigé

- Deux chaînes affichées en jeu portaient un double encodage UTF-8 et s'affichaient
  cassées.
- L'audit d'équipement était recalculé cinq fois par affichage d'onglet et une fois par
  infobulle d'objet survolée. Il est mémoïsé.
- Une tournée de guilde à trente membres produisait quatre-vingt-dix redessins.
- Le canal de guilde n'authentifiait ni l'expéditeur ni le canal : n'importe qui pouvait
  écraser la fiche de n'importe quel membre.
- Un plastron de plaques dans les sacs d'un mage était proposé comme amélioration.
- Les armes à distance n'étaient jamais détectées dans les sacs.
- Une deux mains était comparée à la seule main droite, en ignorant la perte de la main
  gauche.
- Les portraits de boss et les niveaux d'objet du butin restaient absents : un échec de
  lecture du journal, temporaire par nature, était mis en cache définitivement.

### Migration depuis SpecAnalyser

Tes réglages sont repris automatiquement, **à condition que l'ancien addon soit encore
activé** au premier démarrage du nouveau : WoW ne donne à un addon que ses propres
SavedVariables. Voir la section « Tu viens de SpecAnalyser » du README.
