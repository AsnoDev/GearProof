-- Fichier genere par : tools\deploy.cmd
--
-- Il porte la date et l'heure de la COPIE vers le dossier de jeu, et l'entete de la
-- fenetre l'affiche. C'est la reponse a « je n'ai aucun changement en jeu » : on lit le
-- tampon, et on sait immediatement si le client a charge la derniere copie ou si le
-- /reload a precede le deploiement.
--
-- Sans lui, repondre a cette question demandait de comparer des horodatages de fichiers
-- et des SavedVariables a la main.

GearProofBuild = GearProofBuild or "dev"
