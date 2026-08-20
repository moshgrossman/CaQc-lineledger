@echo off
setlocal EnableExtensions EnableDelayedExpansion
title LineLedger

rem ---------------------------------------------------------------
rem  LineLedger portable launcher.
rem
rem  Everything runs from this folder. Nothing is installed on the PC,
rem  no admin rights are needed, and no internet connection is used.
rem
rem  Closing this window shuts LineLedger down.
rem
rem  Called with the argument "demo" it opens the practice books
rem  instead of yours - see "Try the demo.bat" next to this file.
rem ---------------------------------------------------------------

set "BOOKS=%~1"
if /i "%BOOKS%"=="demo" (
    set "DBFILE=demo-books.sqlite"
    set "PORT=8778"
    set "LABEL=LineLedger - PRACTICE BOOKS"
) else (
    set "DBFILE=database.sqlite"
    set "PORT=8777"
    set "LABEL=LineLedger"
)
title %LABEL%

rem %~dp0 is the folder this file sits in, with a trailing backslash.
rem Quoted everywhere below, because a stick can be mounted under a
rem path containing spaces.
set "HERE=%~dp0"
set "APPDIR=%HERE%app"
set "PHPDIR=%HERE%php"
set "DATADIR=%HERE%Data"
set "PHPEXE=%PHPDIR%\php.exe"
set "PHPINI=%PHPDIR%\php.ini"

echo.
echo   %LABEL%
echo   --------------------------------
echo.

rem --- 1. Is the bundle intact? -----------------------------------
if not exist "%PHPEXE%" (
    echo   PROBLEM: php.exe is missing.
    echo.
    echo   The folder is incomplete. Unzip the download again and keep
    echo   all three folders together:  app, php, Data.
    goto :fail
)
if not exist "%APPDIR%\artisan" (
    echo   PROBLEM: the application files are missing.
    echo.
    echo   Unzip the download again, keeping all folders together.
    goto :fail
)
if not exist "%DATADIR%\%DBFILE%" (
    echo   PROBLEM: the books file %DBFILE% is missing from Data.
    echo.
    echo   Unzip the download again, keeping all folders together.
    goto :fail
)

rem --- 2. Can we write here? --------------------------------------
rem A write-protected stick fails here, rather than halfway through
rem saving an invoice.
set "PROBE=%DATADIR%\.writetest"
>"%PROBE%" echo test 2>nul
if not exist "%PROBE%" (
    echo   PROBLEM: this folder is read-only.
    echo.
    echo   LineLedger must be able to save your books. Either the stick
    echo   has its write-protect switch on, or the folder sits somewhere
    echo   Windows protects.
    echo.
    echo   Move the LineLedger folder to the top level of the stick.
    goto :fail
)
del "%PROBE%" >nul 2>&1

rem --- 3. First run: write the settings file -----------------------
rem The drive letter changes from PC to PC, so the settings file is
rem written the first time it runs here and then left alone. The work
rem is done by first-run.php, because a security key is base64 and a
rem Windows path is full of backslashes - both awkward to handle safely
rem in a .bat, and both easy in PHP.
if not exist "%APPDIR%\.env" (
    echo   First run - setting up. A few seconds.
    echo.

    "%PHPEXE%" -c "%PHPINI%" "%HERE%first-run.php" "%DATADIR%" "%APPDIR%"
    if errorlevel 1 (
        echo.
        echo   Setup did not finish. The line above says why.
        echo.
        echo   If it mentions php.exe not running at all, Windows or the
        echo   antivirus has blocked it - see "If Windows blocks it" in
        echo   README-USB.txt.
        goto :fail
    )

    echo   Setup finished.
    echo.
)

rem --- 4. Start the web server ------------------------------------
rem artisan serve is used rather than PHP's bare built-in server
rem because Laravel needs a router to serve its files correctly.
echo   Starting...

rem The books file is handed over as an environment variable. Laravel
rem keeps a real environment variable in preference to the settings
rem file, so the practice books can share one settings file with the
rem real ones and never collide.
set "DB_DATABASE=%DATADIR%\%DBFILE%"

pushd "%APPDIR%"
start "LineLedger server %PORT%" /min "%PHPEXE%" -c "%PHPINI%" artisan serve --host=127.0.0.1 --port=%PORT%
popd

rem A USB stick is slow on its first read, so this waits patiently.
set /a TRIES=0
:waitloop
set /a TRIES+=1
"%PHPEXE%" -c "%PHPINI%" -r "exit(@fsockopen('127.0.0.1',%PORT%,$e,$s,1)?0:1);" >nul 2>&1
if not errorlevel 1 goto :ready
if !TRIES! GEQ 40 (
    echo.
    echo   PROBLEM: LineLedger did not start within 40 seconds.
    echo.
    echo   There is a minimised window on the taskbar called
    echo   "LineLedger server %PORT%". Open it - it says what went
    echo   wrong. A screenshot of that window is exactly what is
    echo   needed to fix this.
    goto :fail
)
ping -n 2 127.0.0.1 >nul
goto :waitloop

:ready
echo   Ready.
echo.

rem --- 5. Open as its own window, not a browser tab ----------------
rem --app= gives a clean window with no tabs and no address bar, so it
rem looks like a program. Chrome first, then Edge, which is on every
rem Windows machine.
set "URL=http://127.0.0.1:%PORT%"
set "OPENED="
for %%B in (
    "%ProgramFiles%\Google\Chrome\Application\chrome.exe"
    "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
    "%LocalAppData%\Google\Chrome\Application\chrome.exe"
    "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
    "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
) do (
    if not defined OPENED if exist %%B (
        start "" %%B --app=%URL% --window-size=1400,900
        set "OPENED=1"
    )
)
if not defined OPENED start "" "%URL%"

echo   LineLedger is open.
echo.
if /i "%BOOKS%"=="demo" (
    echo   These are PRACTICE books with a made-up company in them.
    echo   Nothing you type here touches your real books.
) else (
    echo   Your books are in the Data folder next to this file.
    echo   To back up: copy that folder somewhere safe.
)
echo.
echo   ---------------------------------------------------------
echo   KEEP THIS WINDOW OPEN while you work.
echo   Close it when finished - that shuts LineLedger down and
echo   makes it safe to unplug the stick.
echo   ---------------------------------------------------------
echo.
pause >nul

rem --- 6. Shut down cleanly ---------------------------------------
echo   Stopping...
taskkill /FI "WINDOWTITLE eq LineLedger server %PORT%*" /T /F >nul 2>&1
echo   Stopped. Safe to unplug.
timeout /t 2 >nul
endlocal
exit /b 0

:fail
echo.
echo   Press any key to close.
pause >nul
endlocal
exit /b 1
