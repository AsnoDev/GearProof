@echo off
REM Validation complete avant copie dans le dossier de jeu.
REM A lancer apres toute modification : syntaxe, encodage, locale, references, tests.
REM
REM Les quatre premiers verificateurs LISENT le code. Le dernier l'EXECUTE, dans un vrai
REM Lua 5.1 — la version du client. C'est la seule etape capable d'attraper une fonction
REM qui se charge parfaitement et rend une valeur fausse.
REM
REM Le venv de l'outil Python fournit luaparser et lupa. Aucune autre dependance.

setlocal
set PY=C:\Claude\python\projets\specanalyser\.venv\Scripts\python.exe
set TOOLS=%~dp0

if not exist "%PY%" (
    echo [FAIL] interpreteur introuvable : %PY%
    exit /b 2
)

set FAILED=0

"%PY%" "%TOOLS%check_syntax.py"   || set FAILED=1
"%PY%" "%TOOLS%check_encoding.py" || set FAILED=1
"%PY%" "%TOOLS%check_locale.py"   || set FAILED=1
"%PY%" "%TOOLS%check_refs.py"     || set FAILED=1
"%PY%" "%TOOLS%test_lua.py"       || set FAILED=1

echo.
if "%FAILED%"=="1" (
    echo ================  ADDON NON VALIDE  ================
    exit /b 1
)
echo ================  ADDON VALIDE  ================
exit /b 0
