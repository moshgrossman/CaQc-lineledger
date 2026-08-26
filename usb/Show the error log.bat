@echo off
setlocal EnableExtensions
title LineLedger - error log

rem ---------------------------------------------------------------
rem  Opens LineLedger's error log in Notepad.
rem
rem  This exists for one reason: when something goes wrong the app
rem  shows a bare "500 Server Error" page, which says nothing. The
rem  real reason is written in this file, and this is how it gets
rem  read without a command line.
rem
rem  Sending the last page of this file is usually enough to fix a
rem  problem outright.
rem ---------------------------------------------------------------

set "LOG=%~dp0app\storage\logs\laravel.log"

if not exist "%LOG%" (
    echo.
    echo   There is no error log yet.
    echo.
    echo   That is good news: it means LineLedger has not recorded
    echo   a single error since it was unpacked.
    echo.
    echo   Press any key to close.
    pause >nul
    exit /b 0
)

start "" notepad.exe "%LOG%"
exit /b 0
