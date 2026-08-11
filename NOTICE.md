# Provenance des données livrées

Le code de GearProof est sous licence MIT (voir `LICENSE`). Les **données** livrées avec
l'addon n'ont pas la même origine et méritent d'être nommées séparément.

## `Data/Meta.lua` — 223 Ko, relevé de 40 spécialisations

Ce fichier est **dérivé des classements publics de Warcraft Logs**, via leur API, par
l'outil Python `specanalyser`. Il ne contient aucune donnée brute copiée : ce sont des
agrégats — taux d'adoption d'un enchantement par emplacement, gemmes les plus posées,
répartition moyenne des statistiques secondaires, sur les 20 meilleurs joueurs de chaque
spécialisation.

> ⚠️ **À vérifier avant publication.** Les conditions d'utilisation de l'API Warcraft
> Logs encadrent la redistribution de données dérivées. Publier ce fichier sous licence
> MIT suppose que cette redistribution est autorisée. Cette vérification n'a pas été
> faite et **doit l'être avant la première mise en ligne** — c'est le seul point de la
> checklist de lancement qu'un correctif ultérieur ne rattrape pas, puisque les versions
> déjà téléchargées restent distribuées.
>
> Si les conditions l'interdisent, deux issues : demander une autorisation explicite, ou
> ne plus livrer le relevé et le faire télécharger par l'outil Python côté joueur — ce
> qui ramène la barrière d'entrée que la version 0.5.0 a précisément supprimée.

## `Data/Sim.lua` et `GearProofDB.sim`

Simulations Raidbots appartenant au joueur, importées par lui. Rien n'est livré : le
dépôt ne contient qu'une amorce vide. Ces données ne quittent jamais son client, sauf si
il coche explicitement le partage de guilde — et seul l'identifiant du rapport circule
alors, jamais son contenu.

## Marques

World of Warcraft est une marque de Blizzard Entertainment. GearProof n'est ni affilié
ni approuvé par Blizzard Entertainment, Warcraft Logs ou Raidbots.
