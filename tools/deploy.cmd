@echo off
REM Valide puis copie l'addon dans le dossier AddOns du jeu.
REM
REM C'est l'etape qui manquait entre le depot et le client : on pouvait valider,
REM committer et croire avoir livre, alors que le jeu chargeait toujours l'ancienne
REM version. Un echec de validation interdit la copie.
REM
REM   tools\deploy.cmd                 detecte l'installation
REM   tools\deploy.cmd "D:\...\AddOns" chemin explicite

setlocal
set PY=C:\Claude\python\projets\specanalyser\.venv\Scripts\python.exe

if not exist "%PY%" (
    echo [FAIL] interpreteur introuvable : %PY%
    exit /b 2
)

"%PY%" "%~dp0deploy.py" %*
exit /b %ERRORLEVEL%
