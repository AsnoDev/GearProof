@echo off
REM Regenere le releve du haut de tableau et le depose dans le DEPOT.
REM
REM Rien a taper, rien a decider : la zone du raid de la saison en cours est deduite de
REM l'API (`--zone latest`), la zone de repli aussi. Un numero de zone ecrit ici serait a
REM reediter a chaque saison, donc redeviendrait une intervention manuelle.
REM
REM SPECANALYSER_ADDON_DIR n'est pas facultatif : sans lui l'outil ecrit dans le dossier de
REM JEU, alors que tools\deploy.cmd copie depot -> jeu. Le releve neuf se ferait ecraser au
REM deploiement suivant, en silence.
REM
REM A LIRE UNE FOIS : un addon WoW ne peut faire AUCUNE requete reseau. Le releve ne peut
REM donc pas se rafraichir depuis le jeu. Il voyage avec l'addon, et c'est ce script qui le
REM met a jour — depuis une tache planifiee, pour que personne n'ait a le lancer.
REM
REM Planifier (a executer UNE fois, dans un terminal administrateur) :
REM
REM   schtasks /create /tn "GearProof - releve hebdo" /tr "C:\Claude\lua\projets\GearProof\tools\refresh_meta.cmd" /sc weekly /d WED /st 06:00
REM
REM Quota Warcraft Logs : 3600 points par heure, ~80 par specialisation. Une passe
REM complete des 40 tient, deux non — d'ou l'hebdomadaire et non le quotidien.

setlocal
set PY=C:\Claude\python\projets\specanalyser\.venv\Scripts\python.exe
set TOOL=C:\Claude\python\projets\specanalyser
set REPO=%~dp0..
set LOG=%TEMP%\gearproof_meta.log

if not exist "%PY%" (
    echo [FAIL] interpreteur introuvable : %PY%
    exit /b 2
)

set SPECANALYSER_ADDON_DIR=%REPO%

echo [%date% %time%] regeneration du releve>> "%LOG%"
pushd "%TOOL%"
"%PY%" -m specanalyser wcl meta --zone latest --all --with-stats --to-addon>> "%LOG%" 2>&1
set CODE=%ERRORLEVEL%
popd

if not "%CODE%"=="0" (
    echo [FAIL] regeneration en echec, code %CODE% — voir %LOG%
    echo [%date% %time%] ECHEC %CODE%>> "%LOG%"
    exit /b %CODE%
)

REM La validation decide si le releve neuf est deployable. Un fichier genere qui ne se
REM charge pas remplacerait un addon qui marche par un addon casse.
call "%~dp0check_addon.cmd"
if not "%ERRORLEVEL%"=="0" (
    echo [FAIL] validation en echec — le releve n'est PAS deploye
    echo [%date% %time%] VALIDATION KO>> "%LOG%"
    exit /b 1
)

REM Le releve neuf vaut-il une PUBLICATION ?
REM
REM Deux releves different toujours, ne serait-ce que par leur date. Ce qui compte est de
REM savoir si un JOUEUR verrait la difference : enchantement recommande, gemme, ordre de
REM priorite des stats, paire d'armes, build. Au milieu d'un palier la meta converge et
REM plus rien ne bouge — publier quand meme ferait telecharger 338 Ko a tout le monde pour
REM un chiffre que personne ne lit.
REM
REM La comparaison se fait contre HEAD, donc contre le releve LIVRE : la regeneration a
REM ecrit dans l'arbre de travail, pas dans l'historique.
echo.>> "%LOG%"
call "%~dp0meta_diff.cmd" --against-git HEAD>> "%LOG%" 2>&1
call "%~dp0meta_diff.cmd" --against-git HEAD

call "%~dp0deploy.cmd"
echo [%date% %time%] OK>> "%LOG%"
exit /b 0
