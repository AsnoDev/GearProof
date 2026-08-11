@echo off
REM Tests des fonctions pures, executes dans un vrai Lua 5.1 (lupa).
REM
REM Deja inclus dans check_addon.cmd — ce raccourci sert a iterer sur un test seul, sans
REM repayer les quatre verificateurs statiques.

setlocal
set PY=C:\Claude\python\projets\specanalyser\.venv\Scripts\python.exe

if not exist "%PY%" (
    echo [FAIL] interpreteur introuvable : %PY%
    exit /b 2
)

"%PY%" "%~dp0test_lua.py" %*
exit /b %ERRORLEVEL%
