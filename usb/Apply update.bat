@echo off
setlocal EnableExtensions
title LineLedger - apply update

rem ---------------------------------------------------------------
rem  Applies a LineLedger update pack to the copy on this stick.
rem
rem  Put this file (and the "files" folder next to it) inside the
rem  LineLedger folder on the stick, then double-click it.
rem
rem  It only touches the program. Your books, in Data, are never
rem  read, written or moved by this.
rem ---------------------------------------------------------------

set "HERE=%~dp0"
cd /d "%HERE%"

echo.
echo   LineLedger - applying update
echo   --------------------------------
echo.

if not exist "Start LineLedger.bat" (
    echo   PROBLEM: this is not the LineLedger folder.
    echo.
    echo   Move this file and the "files" folder next to it into the
    echo   LineLedger folder on the stick - the one that has
    echo   "Start LineLedger.bat" in it - and try again.
    goto :fail
)

if not exist "files" (
    echo   PROBLEM: the "files" folder is missing.
    echo.
    echo   Unzip the whole update pack, not just this one file.
    goto :fail
)

if exist "full-bundle-required.flag" (
    echo   STOP: this update cannot be applied to an existing stick.
    echo.
    echo   It changes the structure of the books themselves, and the
    echo   books on this stick were built the old way. Applying it
    echo   would leave you with a program and a set of books that do
    echo   not match.
    echo.
    echo   Use the full download for this one. UPDATE-INSTRUCTIONS.txt
    echo   next to this file says the same thing with more detail.
    goto :fail
)

echo   Copying the changed files...
xcopy "files\*" "." /E /I /Y /Q >nul
if errorlevel 1 (
    echo   PROBLEM: copying failed. The stick may be full or read-only.
    goto :fail
)

if exist "removed.txt" (
    echo   Removing files this version no longer uses...
    for /f "usebackq delims=" %%R in ("removed.txt") do (
        if exist "%%R" del /q "%%R" >nul 2>&1
    )
)

if exist "recompile-screens.flag" (
    echo   Clearing the prepared screens so the new ones are used...
    del /q "app\storage\framework\views\*.php" >nul 2>&1
    del /q "app\bootstrap\cache\*.php" >nul 2>&1
    echo   ^(The next start will take about a minute longer, once.^)
)

if exist "apply-env-updates.php" if exist "php\php.exe" (
    echo   Checking for new settings...
    "php\php.exe" -c "php\php.ini" "apply-env-updates.php" "Data\env.template" "app\.env"
)

echo   Tidying up...
rmdir /s /q "files" >nul 2>&1
del /q "removed.txt" "recompile-screens.flag" "full-bundle-required.flag" >nul 2>&1
del /q "apply-env-updates.php" >nul 2>&1

echo.
echo   Done. Start LineLedger the usual way.
echo.
echo   The black window will show the new build number at the top -
echo   that is how you know the update took.
echo.
echo   Press any key to close.
pause >nul
endlocal
exit /b 0

:fail
echo.
echo   Nothing was changed.
echo.
echo   Press any key to close.
pause >nul
endlocal
exit /b 1
