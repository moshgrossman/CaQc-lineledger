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

rem Replaced with the real number when the bundle is built, so the
rem window always says which build is running.
set "BUNDLEVER=__BUNDLE_VERSION__"

echo.
echo   %LABEL%   (USB build %BUNDLEVER%)
echo   --------------------------------
echo.

rem --- 0. First time on this stick: unpack the program ------------
rem The download carries the application as ONE file, program.tar.gz,
rem rather than fifteen thousand loose ones. Windows Explorer copies a
rem single big file to a stick in a couple of minutes; unzipping
rem thousands of small ones took over half an hour on the test machine.
rem
rem tar.exe does the unpacking here. It has been part of Windows since
rem 2018 and writes files directly, without the shell overhead that
rem makes Explorer so slow. If it is missing, php.exe does the same job
rem more slowly - php.exe is not inside the archive, precisely so that
rem it is available at this point.
rem
rem This runs once, and then program.tar.gz is deleted.
if not exist "%APPDIR%\artisan" if exist "%HERE%program.tar.gz" (
    echo   First time on this stick - unpacking LineLedger.
    echo.
    echo   This happens ONCE, and it takes a few minutes. The screen
    echo   will look like nothing is happening. Do not unplug the
    echo   stick and do not close this window.
    echo.

    pushd "%HERE%"
    set "UNPACKED="
    where tar.exe >nul 2>&1
    if not errorlevel 1 (
        tar -xf "program.tar.gz"
        set "UNPACKED=1"
    )
    if not defined UNPACKED (
        echo   Windows has no unpacker here, so PHP is doing it. This
        echo   is slower. Nothing is wrong.
        "%PHPEXE%" -c "%PHPINI%" -r "$p=new PharData('program.tar.gz'); $p->decompress(); $t=new PharData('program.tar'); $t->extractTo('.', null, true); @unlink('program.tar');"
    )
    popd

    if not exist "%APPDIR%\artisan" (
        echo.
        echo   PROBLEM: unpacking did not finish.
        echo.
        echo   The most likely reason is space: LineLedger needs about
        echo   1 GB free on the stick while it unpacks. Free some space
        echo   and start it again.
        echo.
        echo   If the stick has plenty of room, the antivirus may have
        echo   stopped it - see "If Windows blocks it" in README-USB.txt.
        goto :fail
    )

    rem No longer needed, and it is the largest file on the stick.
    del "%HERE%program.tar.gz" >nul 2>&1
    echo   Unpacked. This will not happen again.
    echo.
)

rem --- 1. Is the bundle intact? -----------------------------------
if not exist "%PHPEXE%" (
    echo   PROBLEM: php.exe is missing.
    echo.
    echo   The folder is incomplete. Unzip the download again, and
    echo   keep everything inside the LineLedger folder together.
    goto :fail
)
if not exist "%APPDIR%\artisan" (
    echo   PROBLEM: the application files are missing, and so is the
    echo   program.tar.gz they are unpacked from.
    echo.
    echo   Unzip the download again, keeping everything inside the
    echo   LineLedger folder together.
    goto :fail
)
if not exist "%DATADIR%\%DBFILE%" (
    echo   PROBLEM: the books file %DBFILE% is missing from Data.
    echo.
    echo   Unzip the download again, keeping everything inside the
    echo   LineLedger folder together.
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

rem --- 3b. Compile the screens, once -------------------------------
rem LineLedger's 400-odd screens are templates that PHP has to compile
rem before it can show them. Left alone, that happens the first time
rem each screen is opened - reading from the stick, while the user
rem waits. Doing them all here, once, is the difference between a slow
rem first hour and a slow first minute.
rem
rem This is deliberately NOT done when the bundle is built: the compiled
rem name depends on the path separator, so a cache built on the build
rem machine would be silently ignored here and every screen would
rem compile again anyway.
if not exist "%APPDIR%\storage\framework\views\*.php" (
    echo   Preparing the screens. About a minute, once.
    pushd "%APPDIR%"
    "%PHPEXE%" -c "%PHPINI%" artisan view:cache >nul 2>&1
    rem Routes too. If this ever fails the app must still run, so the
    rem half-built cache is thrown away rather than left in place.
    "%PHPEXE%" -c "%PHPINI%" artisan route:cache >nul 2>&1
    if errorlevel 1 "%PHPEXE%" -c "%PHPINI%" artisan route:clear >nul 2>&1
    popd
    echo   Ready to go.
    echo.
)

rem --- 3c. Room to work --------------------------------------------
rem SQLite writes a small working file beside the books during every save.
rem If the stick is full it cannot, and the save fails with an error that
rem says nothing useful. Checked here, where it can be said plainly.
rem PHP reports the number into a file, because quoting a path with
rem spaces inside a for /f command line is a well-known way to get a
rem launcher that works everywhere except the one PC that matters.
set "FREEMB="
pushd "%HERE%"
"%PHPEXE%" -c "%PHPINI%" -r "file_put_contents('free.tmp', (int) floor(@disk_free_space(getcwd()) / 1048576));" >nul 2>&1
if exist "free.tmp" for /f "usebackq delims=" %%F in ("free.tmp") do set "FREEMB=%%F"
del "free.tmp" >nul 2>&1
popd
if defined FREEMB if %FREEMB% LSS 300 (
    echo   WARNING: only %FREEMB% MB free on this stick.
    echo.
    echo   LineLedger needs room to save. Below about 300 MB, saving can
    echo   fail in the middle of an entry. Free some space when you can.
    echo.
)

rem --- 3d. Somewhere to put temporary files -------------------------
rem While saving, SQLite may also open a scratch file in the system
rem temporary folder. On a locked-down PC that folder can be off limits,
rem and the save then fails with "unable to open database file" - which
rem is exactly what his error log showed. So: use the PC's temporary
rem folder if it will take a file, and the stick if it will not.
set "SCRATCH=%TEMP%\LineLedger-temp"
mkdir "%SCRATCH%" >nul 2>&1
>"%SCRATCH%\.writetest" echo test 2>nul
if exist "%SCRATCH%\.writetest" (
    del "%SCRATCH%\.writetest" >nul 2>&1
) else (
    set "SCRATCH=%DATADIR%\temp"
    mkdir "%DATADIR%\temp" >nul 2>&1
    echo   Using the stick for temporary files - this PC's own folder
    echo   is not writable.
)
set "TEMP=%SCRATCH%"
set "TMP=%SCRATCH%"

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
rem Show progress: on a USB stick the first start reads ~200 MB, and a
rem silent "Starting..." is indistinguishable from a hang.
set /a SHOWN=TRIES %% 5
if !SHOWN! EQU 0 echo      still starting... !TRIES! seconds
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

echo   LineLedger is open at %URL%
echo.
if /i "%BOOKS%"=="demo" (
    echo   These are PRACTICE books with a made-up company in them.
    echo   Nothing you type here touches your real books.
    echo.
    echo   LOG IN WITH:
    echo       Email     test@example.com
    echo       Password  password
) else (
    echo   These are YOUR books, and they start empty.
    echo.
    echo   FIRST TIME: there is no account yet. Click "Sign up" on the
    echo   login page and create one. The first account you make is the
    echo   owner. Nothing is sent anywhere - the account lives on this
    echo   stick, in the Data folder.
    echo.
    echo   To back up: copy the Data folder somewhere safe.
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
