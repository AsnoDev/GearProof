@echo off
REM Valide puis fabrique le zip a deposer sur CurseForge, dans ..\_dist.
REM
REM Le zip porte un dossier racine GearProof\ : un zip a plat s'extrait en vrac dans
REM Interface\AddOns et casse toutes les installations qui l'appliquent.
REM
REM Un echec de validation, une licence absente ou une ## X-Website non renseignee
REM interdisent la production du zip.

setlocal
set PY=C:\Claude\python\projets\specanalyser\.venv\Scripts\python.exe

if not exist "%PY%" (
    echo [FAIL] interpreteur introuvable : %PY%
    exit /b 2
)

"%PY%" "%~dp0package.py" %*
exit /b %ERRORLEVEL%
