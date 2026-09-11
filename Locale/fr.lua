local _, ns = ...

-- Traduction francaise. La cle EST le texte anglais : une chaine absente d'ici retombe
-- donc sur l'anglais, sans trou d'affichage.
--
-- Ce fichier ne contient QUE des donnees. Le mecanisme — la table `L`, `ns.Localize`,
-- `ns.ApplyLanguage` — vit dans Locale.lua, charge avant celui-ci par le .toc.
--
-- Ajouter une langue : copier ce fichier, traduire, declarer le code dans `CLIENT_MAP` et
-- `ns.LANGUAGES` de Locale.lua, et l'ajouter au .toc. `tools/check_locale.py` verifie
-- ensuite la couverture — une langue incomplete se lit comme un addon casse, pas comme un
-- addon anglais.

ns.translations.fr = {
    -- Chrome
    ["Equipment"] = "Equipement",
    ["Help"] = "Aide",
    ["Skin"] = "Habillage",
    ["Re-enable all"] = "Tout reactiver",
    ["Report a bug"] = "Signaler un bug",
    ["Suggest an idea"] = "Suggerer une idee",

    -- Equipement
    ["missing"] = "manque",
    ["enchant"] = "enchant",
    ["gem"] = "gemme",
    ["ignored"] = "ignore",
    ["Head"] = "Tete",
    ["Neck"] = "Collier",
    ["Shoulders"] = "Epaules",
    ["Cloak"] = "Cape",
    ["Chest"] = "Torse",
    ["Wrists"] = "Bracelets",
    ["Hands"] = "Gants",
    ["Waist"] = "Ceinture",
    ["Legs"] = "Jambes",
    ["Feet"] = "Bottes",
    ["Ring 1"] = "Anneau 1",
    ["Ring 2"] = "Anneau 2",
    ["Trinket 1"] = "Bijou 1",
    ["Trinket 2"] = "Bijou 2",
    ["Weapon"] = "Arme",
    ["Off hand"] = "Main gauche",
    ["missing enchant"] = "enchantement manquant",
    ["empty slot"] = "emplacement vide",
    ["%d empty socket"] = "%d chassis vide",
    ["%d empty sockets"] = "%d chassis vides",
    ["durability %d%%"] = "durabilite %d%%",
    ["%s: empty slot"] = "%s : emplacement vide",
    ["%s: damaged"] = "%s : piece abimee",
    ["Gear complete"] = "Equipement complet",

    -- Onglet Recommandations : sections Builds et Statistiques.
    ["Builds"] = "Builds",

    -- Section CRAFTS. Rien en jeu ne distingue un objet fabrique d'un butin sans ouvrir
    -- sa recette : c'est le seul bloc qui dise quoi faire hors du combat.
    ["Crafted"] = "Artisanat",
    ["Made, not dropped. These are the recipes worth ordering."] =
        "Fabrique, pas ramasse. Voici les recettes qui valent la commande.",
    ["ilvl %d"] = "ilvl %d",
    ["worn at ilvl"] = "porte au niveau",

    -- Onglets neufs.
    ["Talents: the tree your spec's top players actually play, in raid or in Mythic+."] =
        "Talents : l'arbre que jouent reellement les meilleurs de ta spe, en raid ou en mythique+.",
    ["Items: which trinkets they wear and where those drop, plus the recipes worth ordering."] =
        "Objets : quels bijoux ils portent et ou ils tombent, plus les recettes qui valent la commande.",
    ["Talents"] = "Talents",

    -- Section BIJOUX. Aucun chiffre ne classe un bijou de tank ou de soigneur : le
    -- droptimizer mesure des degats, Warcraft Logs n'a pas de classement de survie. On dit
    -- ce que les meilleurs PORTENT, et on dit que c'est un usage.
    --
    -- La separation se fait sur la PROVENANCE, pas sur la population observee : un raideur
    -- porte son bijou de raid en donjon, il figurait donc dans une liste « mythique+ » sans
    -- y etre obtenable.
    ["No number ranks a trinket for a tank or a healer: a droptimizer measures damage, and Warcraft Logs has no survival ranking. This is what the top players wear."] =
        "Aucun chiffre ne classe un bijou de tank ou de soigneur : un droptimizer mesure les degats, et Warcraft Logs n'a pas de classement de survie. Voici ce que portent les meilleurs.",
    ["Drops in the raid"] = "Tombe en raid",
    -- Le niveau vient du JOURNAL, a une difficulte precise, pas du mode observe
    -- chez vingt joueurs qui melangent des pieces surclassees de plusieurs crans.
    ["mythic raid"] = "raid mythique",
    ["mythic dungeon"] = "donjon mythique",
    ["Drops in Mythic+ dungeons"] = "Tombe en donjon mythique+",
    ["Obtainable without setting foot in the raid."] =
        "Obtenables sans mettre un pied en raid.",
    ["Source unknown for now: the adventure guide has not answered yet. Reopen this tab."] =
        "Provenance inconnue pour l'instant : le journal des aventures n'a pas encore repondu. Rouvre cet onglet.",
    ["Full lists, and the crafted gear, are on the Items tab."] =
        "Les listes completes, et l'artisanat, sont dans l'onglet Objets.",

    -- Onglet Talents : le meme releve, pris en raid et en donjon. Ce ne sont pas les memes
    -- arbres, et personne ne publie la comparaison.
    ["Talent trees played on raid bosses."] = "Arbres joues sur les boss de raid.",
    ["Talent trees played in Mythic+ dungeons."] = "Arbres joues en donjon mythique+.",
    ["No build recorded for this content."] = "Aucun build releve pour ce contenu.",

    -- L'ARBRE, et les trois raisons de ne pas pouvoir le dessiner — dites au joueur
    -- plutot que masquees derriere une page vide.
    ["Talent tree"] = "Arbre de talents",
    ["Hero talents"] = "Talents de heros",
    ["Top build: %d%% of the top players. Hover a node for its adoption."] =
        "Build de tete : %d %% du haut de tableau. Survole un noeud pour son taux de prise.",
    ["taken by the top build"] = "pris par le build de tete",
    ["not taken by the top build"] = "pas pris par le build de tete",
    ["taken by"] = "pris par",
    ["The reference does not carry a full tree for this content."] =
        "Le releve ne porte pas d'arbre complet pour ce contenu.",
    ["The tree can only be drawn for the spec you are playing."] =
        "L'arbre ne peut etre dessine que pour la spe que tu joues.",
    ["The client did not return a talent tree."] =
        "Le client n'a pas rendu d'arbre de talents.",
    ["The reference talent ids do not match this client's tree."] =
        "Les identifiants de talent du releve ne correspondent pas a l'arbre de ce client.",

    -- L'EXPORT. Il ne s'affiche que si notre serialiseur reproduit celui du client : une
    -- chaine fausse ferait coller un arbre qui n'est pas celui qu'on regarde.
    ["Copy import string"] = "Copier la chaine d'import",
    ["Talent import string"] = "Chaine d'import des talents",
    ["import string refused: %s"] = "chaine d'import refusee : %s",
    ["This client's format is not the one GearProof writes. Send these two lines to the author."] =
        "Le format de ce client n'est pas celui qu'ecrit GearProof. Envoie ces deux lignes a l'auteur.",

    -- Fenetre Droptimizer : le parcours en trois etapes, dans une seule fenetre.
    ["optional"] = "facultatif",
    ["Validate"] = "Valider",
    -- L'ADRESSE d'abord, la chaine ensuite : c'est l'ordre des gestes. Le presse-papier
    -- ne garde qu'une chose a la fois, donc copier avant de savoir ou coller oblige a
    -- revenir chercher.
    -- Onglet Raid : d'ou viennent les chiffres, et de quand. Un rapport de la saison
    -- precedente ne se voit pas autrement — les boss ont l'air normaux.
    ["simulated %d day(s) ago"] = "simule il y a %d jour(s)",
    ["date unknown, generated file"] = "date inconnue, fichier genere",

    ["Open this address"] = "Ouvre cette adresse",
    ["Paste this string there, then run the simulation"] =
        "Colle cette chaine dedans, puis lance la simulation",
    ["Select everything there (Ctrl+A), copy, and paste it below"] =
        "Selectionne tout la-bas (Ctrl+A), copie, et colle ci-dessous",
    ["Report link received. Open this address:"] =
        "Lien du rapport recu. Ouvre cette adresse :",
    -- Le parcours par defaut : le joueur repart de Raidbots avec le CSV. L'adresse du
    -- fichier se DEVINE (adresse du rapport + /data.csv) et la page la donne en un clic,
    -- donc rien ne justifie de le faire revenir chercher une adresse.
    ["On the report page: ... menu > Raw Files > data.csv (or add /data.csv to its address)"] =
        "Sur la page du rapport : menu ... > Raw Files > data.csv (ou ajoute /data.csv a l'adresse)",
    ["A report link pasted here works too: GearProof then gives you the address."] =
        "Un lien de rapport colle ici marche aussi : GearProof te rend alors l'adresse.",
    ["Without a droptimizer the Raid tab still works: it compares item levels. A droptimizer replaces that estimate with measured gain."] =
        "Sans droptimizer, l'onglet Raid fonctionne : il compare les niveaux d'objet. Un droptimizer remplace cette estimation par du gain mesure.",
    ["Optional. Without one the Raid tab compares item levels; with one it shows measured gain."] =
        "Facultatif. Sans lui l'onglet Raid compare les niveaux d'objet ; avec lui il montre du gain mesure.",
    ["reference measured %d day(s) ago — update the addon to refresh it"] =
        "releve mesure il y a %d jour(s) — mets l'addon a jour pour le rafraichir",
    ["ranked on damage"] = "classes sur les degats",
    ["ranked on healing"] = "classes sur les soins",
    ["top %d of your spec"] = "top %d de ta specialisation",
    -- Survie, colonne de droite, tanks uniquement.
    ["Stamina"] = "Endurance",
    ["Armor"] = "Armure",
    ["Secondary stats"] = "Statistiques secondaires",
    ["closest to yours"] = "le plus proche de toi",
    ["stats not measured for this group"] = "statistiques non mesurees pour ce groupe",
    ["%d players grouped by identical talent tree"] =
        "%d joueurs regroupes par arbre de talents identique",
    ["The band is where the top players sit, the mark is you. A wide band means the choice is open."] =
        "La bande est la ou se tient le haut de tableau, le repere c'est toi. Une bande large veut dire que le choix est ouvert.",

    -- Bloc gemmes de l'onglet Equipement. Il repond a « quelle gemme je pose » : le nom
    -- d'abord, puis combien de chasses et lesquelles. Il listait auparavant chaque chasse
    -- de chaque piece par rang, avec une legende de trois glyphes.
    ["to socket in %d slot(s)"] = "a poser dans %d chasse(s)",
    ["every socket is filled"] = "toutes les chasses sont serties",
    ["other than measured"] = "autre que le releve",
    ["of gems on %d top players"] = "des gemmes chez %d joueurs du haut de tableau",
    ["Nothing to fix"] = "Rien a corriger",
    ["Everything is enchanted, socketed and in shape."] = "Tout est enchante, serti et en etat.",
    ["SECONDARY STATS"] = "STATISTIQUES SECONDAIRES",
    ["Haste"] = "Hate",
    ["Crit"] = "Critique",
    ["Mastery"] = "Maitrise",
    ["Versatility"] = "Polyvalence",
    ["diminishing tier %d"] = "palier %d de rendement",
    ["no measure"] = "pas de releve",
    ["yours"] = "chez toi",
    ["top %d"] = "top %d",
    ["PRIORITY"] = "PRIORITE",
    ["no top-build reference for this spec yet"] = "pas encore de releve pour cette specialisation",
    ["weapon enchant combination not in the top %d"] = "combinaison d'enchantements d'armes absente du top %d",
    ["no stat weights — paste a Pawn string to rank bag items"] =
        "pas de poids de statistiques — colle une chaine Pawn pour classer les objets des sacs",
    ["using the SimulationCraft addon's own export"] =
        "export de l'addon SimulationCraft officiel",
    ["install the SimulationCraft addon for an authoritative export"] =
        "installe l'addon SimulationCraft pour un export autoritatif",
    ["incomplete SimC export — the simulation will be wrong:"] =
        "export SimC incomplet — la simulation sera fausse :",
    ["SimulationCraft string — paste it on raidbots.com"] =
        "Chaine SimulationCraft — a coller sur raidbots.com",
    ["ilvl vs equipped"] = "ilvl contre l'equipe",
    ["left-click: copy the enchant name"] = "clic gauche : copier le nom de l'enchantement",
    ["left-click: details"] = "clic gauche : detail",
    ["right-click: ignore"] = "clic droit : ignorer",
    ["right-click: un-ignore"] = "clic droit : reactiver",
    ["top players measured"] = "joueurs du haut de tableau releves",
    ["specs in the shipped reference"] = "specialisations dans la reference embarquee",
    ["of their budget"] = "de leur budget",
    ["of yours"] = "du tien",
    ["simulated (% DPS)"] = "simule (% DPS)",
    ["estimated (stat points)"] = "estime (points de stats)",
    ["fix pending"] = "correctif en attente",
    ["fixes pending"] = "correctifs en attente",
    ["slots clean"] = "emplacements propres",
    ["The gauge"] = "La jauge",
    ["It counts, it does not grade: fixes pending, and how many checked slots are clean. There is no score out of 100 — it would be four arbitrary penalties dressed up as a measurement."] =
        "Elle compte, elle ne note pas : correctifs en attente, et combien d'emplacements verifies sont propres. Pas de score sur 100 — ce seraient quatre penalites arbitraires deguisees en mesure.",
    ["The bar shows this stat's share of your own secondary budget, and the number on the right is the percentage from your character sheet. Hover for the points and the top-20 share."] =
        "La barre montre la part de cette statistique dans ton propre budget secondaire, et le nombre a droite est le pourcentage de ta feuille de personnage. Survole pour les points et la part du top 20.",
    ["Raid"] = "Raid",
    ["Roster"] = "Roster",
    ["stale"] = "perime",
    -- Cle distincte de ["missing"] : le tableau de guilde dit qu'un MEMBRE n'a pas de
    -- droptimizer, les cartes d'equipement disent qu'il MANQUE un enchantement. Les
    -- deux partageaient la meme cle et la seconde declaration ecrasait la premiere en
    -- silence — les cartes affichaient donc "absent" au lieu de "manque".
    ["No droptimizer shared yet. Run the roll call, and ask members to enable sharing."] =
        "Aucun droptimizer partage. Lance la tournee, et demande aux membres d'activer le partage.",
    ["Guild ranking"] = "Classement de la guilde",
    ["Best gain here"] = "Meilleur gain ici",
    ["the item level above is the base template, not the drop"] =
        "le niveau d'objet ci-dessus est celui du modele, pas celui du butin",
    ["%d items"] = "%d objets",
    ["Each boss shows the items your droptimizer actually simulated, best gain first."] =
        "Chaque boss montre les objets que ton droptimizer a reellement simules, meilleur gain d'abord.",
    ["encounter %d"] = "rencontre %d",
    ["%d items simulated"] = "%d objets simules",
    ["%d items simulated by your droptimizer"] = "%d objets simules par ton droptimizer",
    ["%d items this boss can drop for you"] = "%d objets que ce boss peut te donner",
    ["Loot tables read from the adventure guide, filtered to your spec. Import a droptimizer to replace the estimates with measured gains."] =
        "Tables de butin lues dans le journal des aventures, filtrees sur ta specialisation. Importe un droptimizer pour remplacer les estimations par des gains mesures.",
    ["Raid difficulty"] = "Difficulte de raid",
    ["The journal lists different item levels per difficulty."] =
        "Le journal donne des niveaux d'objet differents selon la difficulte.",
    ["simulated at ilvl"] = "simule en ilvl",
    ["Ctrl+A then Ctrl+C to copy"] = "Ctrl+A puis Ctrl+C pour copier",
    ["settings carried over from SpecAnalyser"] =
        "reglages repris de SpecAnalyser",
    ["Class set"] = "Ensemble",
    ["%d pieces"] = "%d pieces",
    ["GEMS"] = "GEMMES",
    ["Item data not loaded yet — click again in a moment."] =
        "Donnees de l'objet pas encore chargees — reclique dans un instant.",

    -- Onglet Recommandations.
    ["%d%% of the top players run two DIFFERENT weapon enchants"] =
        "%d%% du haut de tableau portent deux enchantements d'armes DIFFERENTS",
    -- Detection de builds bimodaux. La donnee existait depuis toujours et n'avait
    -- aucun lecteur : c'est le seul endroit ou l'addon peut dire qu'une moyenne ne
    -- decrit personne.
    ["Two builds measured"] = "Deux builds mesures",
    ["Enchants"] = "Enchantements",
    ["Gems"] = "Gemmes",
    ["Trinkets"] = "Bijoux",
    ["Weapons (pair)"] = "Armes (paire)",
    ["No droptimizer imported yet."] = "Aucun droptimizer importe.",
    ["Import a droptimizer"] = "Importer un droptimizer",
    ["droptimizer imported: %d items"] = "droptimizer importe : %d objets",
    ["Paste the Raidbots report link, or the report data"] =
        "Colle le lien de ton rapport Raidbots, ou les donnees du rapport",
    ["Open this address, select everything, copy — then replace this text with what you copied and validate"] =
        "Ouvre cette adresse, selectionne tout, copie — puis remplace ce texte par ce que tu as copie et valide",
    ["Paste your Raidbots report link below."] = "Colle le lien de ton rapport Raidbots.",
    ["GearProof gives you an address: open it, select everything, copy."] =
        "GearProof te rend une adresse : ouvre-la, selectionne tout, copie.",
    ["Paste that back here. No tool, no reload."] =
        "Recolle ici. Aucun outil, aucun rechargement.",
    ["Nobody has answered yet."] = "Personne n'a encore repondu.",
    ["Run the roll call: every guild member running GearProof answers with their spec, item level and pending fixes. Nothing is sent from your client unless you tick sharing."] =
        "Lance la tournee : chaque membre de la guilde equipe de GearProof repond avec sa spe, son ilvl et ses correctifs en attente. Rien ne part de ton client tant que tu n'as pas coche le partage.",
    ["weapon enchant combination"] = "combinaison d'enchantements d'armes",
    ["measured on %d top players"] = "mesure sur %d joueurs du haut de tableau",
    ["fresh"] = "a jour",
    ["Droptimizer"] = "Droptimizer",
    ["%d day(s) old"] = "%d jour(s)",
    ["none"] = "aucun",

    -- Onglet Aide, reecrit sur l'outil reel (audit d'equipement, plus d'analyse de jeu).
    ["Where the reference comes from"] = "D'ou vient la reference",
    ["Keeping the reference fresh"] = "Garder la reference a jour",
    ["What ships with the addon"] = "Ce qui est livre avec l'addon",
    ["The measured reference for %d specialisations."] =
        "La reference mesuree pour %d specialisations.",
    ["Measured %d day(s) ago. A new one ships with each release."] =
        "Mesuree il y a %d jour(s). Une nouvelle arrive a chaque version.",
    ["A new one ships with each release."] = "Une nouvelle arrive a chaque version.",
    ["What you add yourself"] = "Ce que tu ajoutes toi-meme",
    ["Your own droptimizer, from raidbots.com. The Droptimizer button carries the whole sequence: copy, simulate, paste the results back."] =
        "Ton propre droptimizer, depuis raidbots.com. Le bouton Droptimizer porte toute la sequence : copier, simuler, recoller les resultats.",
    ["That is the only step that needs you. Without it the audit still works — it simply refuses to put a number on what it cannot measure."] =
        "C'est la seule etape qui demande quelque chose. Sans elle l'audit fonctionne quand meme — il refuse simplement de chiffrer ce qu'il ne peut pas mesurer.",
    ["Reading the equipment tab"] = "Lire l'onglet Equipement",
    ["GearProof audits your gear against what the best players of your spec actually wear."] =
        "GearProof confronte ton equipement a ce que portent reellement les meilleurs joueurs de ta specialisation.",
    ["Read live in game: enchants, gems, sockets, durability, class set."] =
        "Lu en direct dans le jeu : enchantements, gemmes, chasses, durabilite, ensemble de classe.",
    ["Compared to a measured reference: the top ranked players of your spec, enchant by enchant, with their adoption rate."] =
        "Compare a une reference mesuree : le haut de tableau de ta specialisation, enchantement par enchantement, avec son taux d'adoption.",
    ["Nothing here is copied from a guide, and nothing is invented. A value that is not measured is shown as unmeasured."] =
        "Rien n'est recopie d'un guide, rien n'est invente. Une valeur non mesuree est affichee comme non mesuree.",
    ["The reference is taken from Warcraft Logs: the top 20 of your spec on the most recent encounters, and their real equipment."] =
        "La reference vient de Warcraft Logs : le top 20 de ta specialisation sur les rencontres les plus recentes, et leur equipement reel.",
    ["The most recent encounters come first. Older ones are only used when the new ones do not have enough ranked players yet."] =
        "Les rencontres les plus recentes passent d'abord. Les anciennes ne servent que si les nouvelles n'ont pas encore assez de classements.",
    ["The reference is per spec. Pick another spec of your class in the header to see what the audit would say."] =
        "La reference est par specialisation. Choisis-en une autre dans l'entete pour voir ce que l'audit dirait.",
    ["The stat bars"] = "Les barres de statistiques",
    ["The priority line"] = "La ligne de priorite",
    ["The order the top players actually run, with each share. Read once, not repeated on every row."] =
        "L'ordre reellement joue par le haut de tableau, avec la part de chacune. Lu une fois, pas repete sur chaque ligne.",
    ["Why does it not analyse my play?"] = "Pourquoi il n'analyse pas mon jeu ?",
    ["Since Midnight, combat events are secret values: displayable but unreadable by an addon. No addon can do it any more, so this one does not pretend to."] =
        "Depuis Midnight, les evenements de combat sont des valeurs secretes : affichables, illisibles par un addon. Aucun addon ne peut plus le faire, donc celui-ci ne fait pas semblant.",
    ["Why two different weapon enchants?"] = "Pourquoi deux enchantements d'armes differents ?",
    ["Because that is what the measurement says. Counting each hand separately hides the pairing: most of the top players run one of each, and the audit checks the combination, not each hand alone."] =
        "Parce que c'est ce que dit la mesure. Compter chaque main separement cache l'appariement : la majorite du haut de tableau en porte un de chaque, et l'audit verifie la combinaison, pas chaque main isolee.",
    ["Why is a trinket shown as unrated?"] = "Pourquoi un bijou est-il non chiffre ?",
    ["A trinket is worth its proc, not its stat points. It stays unrated until one of your droptimizers covers it."] =
        "Un bijou vaut par son proc, pas par ses points de statistique. Il reste non chiffre jusqu'a ce qu'un de tes droptimizers le couvre.",
    ["No reference for my spec?"] = "Pas de reference pour ma specialisation ?",
    ["That spec was not in the last sweep. It will be in a future release — the audit still checks what it can read on your gear."] =
        "Cette specialisation n'etait pas dans le dernier releve. Elle le sera dans une prochaine version — l'audit verifie quand meme tout ce qu'il lit sur ton equipement.",
    ["Reference measured from Warcraft Logs rankings, outside the game, and shipped with the addon"] =
        "Reference mesuree sur les classements Warcraft Logs, hors du jeu, et livree avec l'addon",
    ["Preview: %s"] = "Apercu : %s",
    ["your spec"] = "ta specialisation",
    ["Preview another spec"] = "Apercu d'une autre specialisation",
    ["The audit recomputes enchants, gems and stat targets for the spec you pick. Your gear does not change."] =
        "L'audit recalcule enchantements, gemmes et cibles de statistiques pour la specialisation choisie. Ton equipement ne change pas.",

    -- Analyse

    -- Historique

    -- Aide
    ["Welcome"] = "Bienvenue",
    ["Frequent questions"] = "Questions frequentes",
    ["Report something"] = "Signaler quelque chose",

    -- Infobulles et fiches
    ["Alert ignored for this piece"] = "Alerte ignoree pour cette piece",
    ["Enchant and gems: ok"] = "Enchantement et gemmes : ok",
    ["Right click: ignore or re-enable the alert"] = "Clic droit : ignorer ou reactiver l'alerte",
    ["No gem recorded yet."] = "Aucune gemme relevee.",
    ["stat enchant"] = "enchantement de stat",
    ["leg armor"] = "renfort de jambes",
    ["weapon enchant"] = "enchantement d'arme",
    ["language: %s"] = "langue : %s",

    -- References, poids, sacs
    ["meta reference: %s (%d players)"] = "reference : %s (%d joueurs)",
    ["no meta reference loaded"] = "aucune reference chargee",
    ["the shipped reference is in format %d, this addon reads up to %d — update the addon"] =
        "la reference livree est au format %d, cet addon lit jusqu'au %d — mets l'addon a jour",
    ["weights: %s (%d days)"] = "poids : %s (%d j)",
    ["stat weights saved (%s)"] = "poids de stats enregistres (%s)",
    ["unreadable Pawn string"] = "chaine Pawn illisible",
    ["IN YOUR BAGS"] = "DANS TES SACS",
    ["proc — sim required"] = "proc — sim requise",
    ["set piece — sim required"] = "piece d'ensemble — sim requise",
    ["needs a second weapon — sim required"] = "demande une seconde arme — sim requise",
    ["skin: %s"] = "habillage : %s",
    ["gear grid"] = "grille d'equipement",
    ["gear audit"] = "audit d'equipement",
    ["%d gear issue(s)"] = "%d probleme(s) d'equipement",
    ["Left click: open"] = "Clic gauche : ouvrir",
    ["Right click: gear"] = "Clic droit : equipement",
    ["Drag: move the icon"] = "Glisser : deplacer l'icone",
    ["gear complete: %d pieces, everything enchanted and socketed"] =
        "equipement complet : %d pieces, tout est enchante et serti",
    ["%d gear problem(s):"] = "%d probleme(s) d'equipement :",
    ["In your bags"] = "Dans tes sacs",
    ["Search this in the auction house"] = "A chercher a l'hotel des ventes",
    ["%d stat points"] = "%d points de statistique",
    ["click to copy the name"] = "clic pour copier le nom",
    ["Droptimizer report"] = "Rapport droptimizer",
    ["This tab lists the loot each boss can drop for you, ranked by the gain your own simulation measured."] =
        "Cet onglet liste le butin que chaque boss peut te donner, classe par le gain que ta propre simulation a mesure.",
    ["droptimizer report stored"] = "rapport droptimizer enregistre",
    ["nothing readable in that paste"] = "rien d'exploitable dans ce collage",

    -- Guilde
    ["Guild"] = "Guilde",
    ["Guild audit"] = "Audit de guilde",

    -- Onglet Guilde, refonte. Le mot « pret » n'y figure plus : il designait a la fois une
    -- simulation fraiche et « rien a corriger », et l'ecran affichait les deux sous le
    -- meme nom. « frais » parle du droptimizer, « rien a signaler » de la ligne entiere.
    ["Loot"] = "Butin",
    ["EQUIPMENT"] = "EQUIPEMENT",
    ["DROPTIMIZER"] = "DROPTIMIZER",
    ["MEMBER"] = "MEMBRE",
    ["SPEC"] = "SPE",
    ["ILVL"] = "ILVL",
    ["FIXES"] = "CORRECTIFS",
    ["TO FIX"] = "A CORRIGER",
    ["NOTHING TO REPORT"] = "RIEN A SIGNALER",
    ["of %d"] = "sur %d",
    ["no fix"] = "sans correctif",
    ["expand"] = "deplier",
    ["collapse"] = "replier",
    -- Abrege de « jours », dans une colonne de 84 px : « 12 j » et non « 12 jours ».
    ["%d d"] = "%d j",
    ["%d concerned"] = "%d concernes",
    ["Fixes pending"] = "Correctifs en attente",
    ["not shared"] = "non partage",
    ["click to copy the report link"] = "clic : copier le lien du rapport",
    ["Sorted by the best gain in the guild. Hover an item for the full ranking."] =
        "Classe par meilleur gain dans la guilde. Survole un objet pour le classement complet.",
    ["Members running GearProof answer the roll call. Nothing is sent unless sharing is on."] =
        "Les membres equipes de l'addon repondent a l'appel. Rien ne sort sans ton accord.",
    ["Roll call"] = "Appel",
    ["Copy for Discord"] = "Copier pour Discord",
    ["Share my data"] = "Partager mes donnees",
    -- Libelles de colonnes du tableau de guilde. Ils remplacent une chaine unique bourree
    -- d'espaces, qui devait tomber en face de colonnes qu'elle ne pouvait pas connaitre.
    ["you are not in a guild"] = "tu n'es dans aucune guilde",
    ["Refresh"] = "Rafraichir",
    ["nothing to recover"] = "rien a recuperer",
    ["%d fix(es) pending"] = "%d correctif(s) en attente",
    ["%d slots checked, nothing to fix"] = "%d emplacements verifies, rien a corriger",
    ["stat"] = "stat",
    ["to fix"] = "a corriger",
    ["/sa to open  ·  minimap icon  ·  right click a tile to mute its alert"] =
        "/sa pour ouvrir  ·  icone de minicarte  ·  clic droit sur une case pour ignorer son alerte",
    ["your stat weights are out of date — re-run a droptimizer"] =
        "tes poids de stats datent — relance un droptimizer",

    -- Panneau d'options
    ["Nothing needs configuring: the measured reference ships with the addon."] =
        "Rien a configurer : la reference mesuree est livree avec l'addon.",
    ["Language"] = "Langue",
    ["Warn me when I enter a dungeon or raid with incomplete gear"] =
        "M'avertir a l'entree en donjon ou raid si l'equipement est incomplet",
    ["Checks enchants, sockets, empty slots and durability a few seconds after the loading screen."] =
        "Verifie enchantements, chasses, emplacements vides et durabilite quelques secondes apres l'ecran de chargement.",
    ["Add measured lines to item tooltips"] = "Ajouter les lignes mesurees aux infobulles d'objets",
    ["Simulated gain, item level against what you wear, and the enchant measured for that slot. Nothing estimated."] =
        "Gain simule, niveau d'objet contre ce que tu portes, et l'enchantement releve pour cet emplacement. Rien d'estime.",
    ["Show the minimap icon"] = "Afficher l'icone de minicarte",
    ["Share my data with the guild"] = "Partager mes donnees avec la guilde",
    ["Answer the roll call with your spec, item level, pending fixes and droptimizer id. Nothing leaves your client while this is off."] =
        "Repondre a l'appel avec ta spe, ton ilvl, tes correctifs en attente et l'identifiant de ton droptimizer. Rien ne sort tant que c'est decoche.",
    ["Debug messages"] = "Messages de debug",
    ["Settings"] = "Reglages",

    -- Rechargement
    ["Reload UI"] = "Recharger",
    ["A freshly generated analysis is only read at load."] =
        "Une analyse fraichement generee n'est lue qu'au chargement.",

    -- Aide
    ["Both buttons prepare a ready to paste text, with the technical details already filled in."] =
        "Les deux boutons preparent un texte pret a coller, avec les informations techniques deja remplies.",
    ["Bug report"] = "Rapport de bug",
    ["Suggestion"] = "Suggestion",

    -- Alertes
    ["%d missing enchant(s)"] = "%d enchantement(s) manquant(s)",
    ["%d empty socket(s)"] = "%d chassis vide(s)",
    ["%d empty slot(s)"] = "%d emplacement(s) vide(s)",
    ["%d damaged piece(s)"] = "%d piece(s) abimee(s)",
}
