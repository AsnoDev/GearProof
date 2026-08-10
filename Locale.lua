local _, ns = ...

-- Localisation. La cle EST le texte anglais : toute chaine non traduite retombe donc
-- naturellement sur l'anglais, sans trou d'affichage.

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.L = L

local translations = {}
ns.translations = translations

translations.fr = {
    -- Chrome
    ["Equipment"] = "Equipement",
    ["Help"] = "Aide",
    ["Skin"] = "Habillage",
    ["Re-enable all"] = "Tout reactiver",
    ["Report a bug"] = "Signaler un bug",
    ["Suggest an idea"] = "Suggerer une idee",

    -- Equipement
    ["missing"] = "manque",
    ["empty"] = "vide",
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
    ["%s: %s missing"] = "%s : %s manquant",
    ["gem missing"] = "gemme manquante",
    ["Gear complete"] = "Equipement complet",
    ["Nothing to fix"] = "Rien a corriger",
    ["Everything is enchanted, socketed and in shape."] = "Tout est enchante, serti et en etat.",
    ["SECONDARY STATS"] = "STATISTIQUES SECONDAIRES",
    ["Haste"] = "Hate",
    ["Crit"] = "Critique",
    ["Mastery"] = "Maitrise",
    ["Versatility"] = "Polyvalence",
    ["no reference yet"] = "pas encore de reference",
    ["diminishing tier %d"] = "palier %d de rendement",
    ["vs top %d"] = "contre le top %d",
    ["no measure"] = "pas de releve",
    ["on target"] = "dans la cible",
    ["yours"] = "chez toi",
    ["top %d"] = "top %d",
    ["on the character sheet"] = "sur la feuille de personnage",
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
    ["as measured"] = "conforme au releve",
    ["different"] = "different",
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
    ["needs a sim"] = "demande une simulation",
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
    ["ready"] = "a jour",
    ["stale"] = "perime",
    -- Cle distincte de ["missing"] : le tableau de guilde dit qu'un MEMBRE n'a pas de
    -- droptimizer, les cartes d'equipement disent qu'il MANQUE un enchantement. Les
    -- deux partageaient la meme cle et la seconde declaration ecrasait la premiere en
    -- silence — les cartes affichaient donc "absent" au lieu de "manque".
    ["no droptimizer"] = "absent",
    ["%d of %d ready"] = "%d sur %d a jour",
    ["No droptimizer shared yet. Run the roll call, and ask members to enable sharing."] =
        "Aucun droptimizer partage. Lance la tournee, et demande aux membres d'activer le partage.",
    ["Loot per boss, ranked by the best gain in the guild. Hover an item for the ranking."] =
        "Butin par boss, classe par le meilleur gain de la guilde. Survole un objet pour le classement.",
    ["Guild ranking"] = "Classement de la guilde",
    ["ready of %d"] = "prets sur %d",
    ["Total gain on the table"] = "Gain total sur la table",
    ["Average per member"] = "Moyenne par membre",
    ["Members with fixes pending"] = "Membres avec correctifs",
    ["No shared droptimizer yet"] = "Aucun droptimizer partage",
    ["Best gain here"] = "Meilleur gain ici",
    ["the item level above is the base template, not the drop"] =
        "le niveau d'objet ci-dessus est celui du modele, pas celui du butin",
    ["%d items"] = "%d objets",
    ["%d need"] = "%d interesses",
    ["No droptimizer imported yet. Paste a report link in the Equipment tab."] =
        "Aucun droptimizer importe. Colle un lien de rapport dans l'onglet Equipement.",
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
    ["Normal"] = "Normal",
    ["Heroic"] = "Heroique",
    ["Mythic"] = "Mythique",
    ["simulated at ilvl"] = "simule en ilvl",
    ["Ctrl+A then Ctrl+C to copy"] = "Ctrl+A puis Ctrl+C pour copier",
    ["settings carried over from SpecAnalyser"] =
        "reglages repris de SpecAnalyser",
    ["Class set"] = "Ensemble",
    ["%d pieces"] = "%d pieces",
    ["GEMS"] = "GEMMES",
    ["empty → %s"] = "vide → %s",
    ["Item data not loaded yet — click again in a moment."] =
        "Donnees de l'objet pas encore chargees — reclique dans un instant.",

    -- Onglet Recommandations.
    ["Recommendations"] = "Recommandations",
    ["What the top players of your spec actually put on. Each line says where its advice comes from."] =
        "Ce que posent reellement les meilleurs joueurs de ta spe. Chaque ligne dit d'ou vient son conseil.",
    ["%d%% of the top players run two DIFFERENT weapon enchants"] =
        "%d%% du haut de tableau portent deux enchantements d'armes DIFFERENTS",
    -- Detection de builds bimodaux. La donnee existait depuis toujours et n'avait
    -- aucun lecteur : c'est le seul endroit ou l'addon peut dire qu'une moyenne ne
    -- decrit personne.
    ["Reference"] = "Reference",
    ["Two builds measured"] = "Deux builds mesures",
    ["The top players split into two groups on these stats. The average describes neither."] =
        "Le haut de tableau se separe en deux groupes sur ces statistiques. La moyenne ne decrit ni l'un ni l'autre.",
    ["you are here"] = "tu es ici",
    ["Enchants"] = "Enchantements",
    ["Gems"] = "Gemmes",
    ["Trinkets"] = "Bijoux",
    ["Fixes"] = "Correctifs",
    ["Buffs at pull"] = "Buffs au pull",
    ["General"] = "General",
    ["Missing"] = "Manquant",
    ["Optimal"] = "Optimal",
    ["Other"] = "Autre",
    ["socket"] = "chasse",
    ["unrated"] = "non chiffre",
    ["Weapons (pair)"] = "Armes (paire)",
    ["%d%% adoption"] = "%d%% d'adoption",
    ["No socket was measured for this spec."] = "Aucune chasse relevee pour cette specialisation.",
    ["measured by your droptimizer"] = "mesure par ton droptimizer",
    ["import a droptimizer that covers it"] = "importe un droptimizer qui le couvre",
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
    ["Paste the report link and GearProof gives you the address of its data. Open it, copy everything, paste it back here — no tool needed."] =
        "Colle le lien du rapport et GearProof te rend l'adresse de ses donnees. Ouvre-la, copie tout, recolle ici — aucun outil requis.",
    ["This tab lists the loot each boss can drop for you, ranked by the gain your own simulation measured. It fills up as soon as you import one report."] =
        "Cet onglet liste le butin que chaque boss peut te donner, classe par le gain que ta propre simulation a mesure. Il se remplit des qu'un rapport est importe.",
    ["Nobody has answered yet."] = "Personne n'a encore repondu.",
    ["Run the roll call: every guild member running GearProof answers with their spec, item level and pending fixes. Nothing is sent from your client unless you tick sharing."] =
        "Lance la tournee : chaque membre de la guilde equipe de GearProof repond avec sa spe, son ilvl et ses correctifs en attente. Rien ne part de ton client tant que tu n'as pas coche le partage.",
    ["weapon enchant combination"] = "combinaison d'enchantements d'armes",
    ["durability"] = "durabilite",
    ["empty socket"] = "chasse vide",
    ["Recoverable"] = "Recuperable",
    ["measured on %d of %d fixes"] = "mesure sur %d correctifs sur %d",
    ["measured on %d top players"] = "mesure sur %d joueurs du haut de tableau",
    ["Run the sweep with --with-stats to collect them."] =
        "Relance le relevé avec --with-stats pour les collecter.",
    ["Specialisation"] = "Specialisation",
    ["preview, not your active spec"] = "apercu, pas ta specialisation active",
    ["Sample"] = "Echantillon",
    ["Tertiary (top average)"] = "Tertiaires (moyenne du top)",
    ["Stat weights"] = "Poids de statistiques",
    ["out of date"] = "perimes",
    ["fresh"] = "a jour",
    ["Droptimizer"] = "Droptimizer",
    ["%d day(s) old"] = "%d jour(s)",
    ["none"] = "aucun",
    ["Every line says where its advice comes from. A verdict without an adoption rate would be an opinion; with one it is a measurement."] =
        "Chaque ligne dit d'ou vient son conseil. Un verdict sans taux d'adoption serait un avis ; avec, c'est une mesure.",

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
    ["Your own droptimizer, from raidbots.com. Copy your SimulationCraft string in the Equipment tab, run it, paste the report link back."] =
        "Ton propre droptimizer, depuis raidbots.com. Copie ta chaine SimulationCraft dans l'onglet Equipement, lance-le, recolle le lien du rapport.",
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
    ["The measured reference, on your PC:"] = "La reference mesuree, sur ton PC :",
    ["Your simulated upgrades, from a droptimizer:"] = "Tes gains simules, depuis un droptimizer :",
    ["Then, in game:"] = "Puis, en jeu :",
    ["A generated data file is only read when the interface loads. Without a reload, the new numbers stay invisible."] =
        "Un fichier de donnees genere n'est lu qu'au chargement de l'interface. Sans reload, les nouveaux chiffres restent invisibles.",
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
    ["re-enabled"] = "reactivee",
    ["Nothing to fix on this piece."] = "Rien a corriger sur cette piece.",
    ["Advice: "] = "Conseil : ",
    ["No enchant recorded for this slot yet."] = "Aucun enchantement releve pour cet emplacement.",
    ["Suggested gem: "] = "Gemme conseillee : ",
    ["No gem recorded yet."] = "Aucune gemme relevee.",
    ["Run: specanalyser wcl enchants --to-addon to fill these in."] =
        "Lance : specanalyser wcl enchants --to-addon pour les remplir.",
    ["Alert ignored - right click to re-enable."] = "Alerte ignoree — clic droit pour reactiver.",
    ["Right click the card to ignore this piece."] = "Clic droit sur la carte pour ignorer cette piece.",
    ["stat enchant"] = "enchantement de stat",
    ["leg armor"] = "renfort de jambes",
    ["weapon enchant"] = "enchantement d'arme",
    ["language: %s"] = "langue : %s",

    -- References, poids, sacs
    ["meta reference: %s (%d players)"] = "reference : %s (%d joueurs)",
    ["no meta reference loaded"] = "aucune reference chargee",
    ["the shipped reference is in format %d, this addon reads up to %d — update the addon"] =
        "la reference livree est au format %d, cet addon lit jusqu'au %d — mets l'addon a jour",
    ["reference measured %d day(s) ago"] = "reference mesuree il y a %d jour(s)",
    ["weights: %s (%d days)"] = "poids : %s (%d j)",
    ["stat weights saved (%s)"] = "poids de stats enregistres (%s)",
    ["unreadable Pawn string"] = "chaine Pawn illisible",
    ["Paste my stat weights"] = "Coller mes poids",
    ["Paste a Pawn string from your Raidbots sim"] = "Colle une chaine Pawn issue de ta sim Raidbots",
    ["IN YOUR BAGS"] = "DANS TES SACS",
    ["proc — sim required"] = "proc — sim requise",
    ["set piece — sim required"] = "piece d'ensemble — sim requise",
    ["needs a second weapon — sim required"] = "demande une seconde arme — sim requise",
    ["measured on %d top players (%s)"] = "mesure sur %d joueurs du haut de tableau (%s)",
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
    ["Droptimizer link"] = "Lien droptimizer",
    ["Droptimizer Copy"] = "Copier pour droptimizer",
    ["%d stat points"] = "%d points de statistique",
    ["click to copy the name"] = "clic pour copier le nom",
    ["Droptimizer report"] = "Rapport droptimizer",
    ["Paste droptimizer link"] = "Enregistrer mon droptimizer",
    ["This tab lists the loot each boss can drop for you, ranked by the gain your own simulation measured."] =
        "Cet onglet liste le butin que chaque boss peut te donner, classe par le gain que ta propre simulation a mesure.",
    ["An addon cannot download anything. Import the report on your PC:"] =
        "Un addon ne peut rien telecharger. Importe le rapport sur ton PC :",
    ["then /reload in game."] = "puis /reload en jeu.",
    ["Records the report id so the guild roll call can show your simulation is fresh. The loot table itself is imported on your PC."] =
        "Enregistre l'identifiant du rapport pour que la tournee de guilde montre que ta simulation est recente. La table de butin, elle, s'importe sur ton PC.",
    ["Paste the Raidbots report link, or a Pawn string"] =
        "Colle le lien du rapport Raidbots, ou une chaine Pawn",
    ["droptimizer report stored"] = "rapport droptimizer enregistre",
    ["nothing readable in that paste"] = "rien d'exploitable dans ce collage",

    -- Guilde
    ["Guild"] = "Guilde",
    ["Guild audit"] = "Audit de guilde",
    ["Members running GearProof answer the roll call. Nothing is sent unless sharing is on."] =
        "Les membres equipes de l'addon repondent a l'appel. Rien ne sort sans ton accord.",
    ["Roll call"] = "Appel",
    ["Copy for Discord"] = "Copier pour Discord",
    ["Share my data"] = "Partager mes donnees",
    ["name            spec          ilvl    fixes     last sim"] =
        "nom             spe           ilvl    corr.     derniere sim",
    ["Only you so far — ask your guild to run the roll call."] =
        "Toi seul pour l'instant — demande a la guilde de lancer l'appel.",
    ["no sim"] = "pas de sim",
    ["you are not in a guild"] = "tu n'es dans aucune guilde",
    ["Refresh"] = "Rafraichir",
    ["Copy SimC"] = "Copier SimC",
    ["nothing to recover"] = "rien a recuperer",
    ["%d fix(es) pending"] = "%d correctif(s) en attente",
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

-- Anglais et francais uniquement.
--
-- Il y avait ici trois blocs de plus — de, it, es — a 65 cles chacun contre 330 pour
-- le francais. Comme la cle EST le texte anglais, les 265 cles absentes retombaient
-- sur l'anglais : un joueur allemand obtenait une interface a 20 % allemande, ce qui
-- se lit comme un addon casse, pas comme un addon anglais. Mieux vaut deux langues
-- completes que cinq dont trois a moitie. Une langue se rajoute quand quelqu'un la
-- traduit en entier, et `tools/check_locale.py` verifie la couverture.
local CLIENT_MAP = {
    frFR = "fr",
}

ns.LANGUAGES = { "auto", "en", "fr" }

--- Langue effective : le reglage explicite, sinon celle du client, sinon l'anglais.
function ns.CurrentLanguage()
    local setting = ns.db and ns.db.language or "auto"
    if setting and setting ~= "auto" then return setting end
    return CLIENT_MAP[GetLocale()] or "en"
end

-- Widgets dont le libelle doit suivre la langue.
--
-- Tout texte pose dans un `Create()` n'etait jamais repose : onglets, boutons de
-- l'entete, titres des cartes d'aide, boutons de l'onglet Guilde. `/sa lang fr` laissait
-- donc la moitie de la fenetre en anglais jusqu'au prochain /reload, et l'appel a
-- `UI.Show()` cense regler ca ne touchait aucun de ces FontStrings.
local retranslate = {}

--- Pose un libelle traduit et retient le widget pour les changements de langue.
--- @param setter string|nil methode a appeler, `SetText` par defaut
function ns.Localize(widget, key, setter)
    if not widget or not key then return widget end
    setter = setter or "SetText"
    if type(widget[setter]) ~= "function" then return widget end

    table.insert(retranslate, { widget = widget, key = key, setter = setter })
    widget[setter](widget, L[key])
    return widget
end

--- Recharge la table de traduction active, puis repose tous les libelles enregistres.
function ns.ApplyLanguage()
    for key in pairs(L) do L[key] = nil end

    local code = ns.CurrentLanguage()
    local table_ = translations[code]
    if table_ then
        for key, value in pairs(table_) do
            L[key] = value
        end
    end

    for _, item in ipairs(retranslate) do
        -- Sous pcall : un widget detruit ou un setter disparu ne doit pas empecher les
        -- suivants d'etre retraduits.
        pcall(item.widget[item.setter], item.widget, L[item.key])
    end

    return code
end
