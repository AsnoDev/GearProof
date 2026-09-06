@echo off
REM Compare le releve livre au releve courant et dit si un JOUEUR verrait la difference.
REM
REM Sert a decider s'il faut publier. Deux releves different toujours, ne serait-ce que par
REM leur date : ce script ne regarde que ce sur quoi un joueur AGIT.
REM
REM   tools\meta_diff.cmd --against-git HEAD~1
REM   tools\meta_diff.cmd ancien.lua nouveau.lua

setlocal
set PY=C:\Claude\python\projets\specanalyser\.venv\Scripts\python.exe
if not exist "%PY%" (
    echo [FAIL] interpreteur introuvable : %PY%
    exit /b 2
)
"%PY%" "%~dp0meta_diff.py" %*
exit /b %ERRORLEVEL%
