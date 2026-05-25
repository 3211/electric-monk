@echo off
cd /d "%~dp0\.."
echo.
echo ==============================================
echo      ELECTRIC MONK -- Player Wipe Tool
echo ==============================================
echo.

set /p USERNAME="Enter username to wipe: "

IF "%USERNAME%"=="" (
    echo No username entered. Aborting.
    pause
    exit /b 1
)

echo.
echo Mode:
echo   [1] FULL wipe (auth + all game data)
echo   [2] SOFT wipe (game data only, keep auth user)
echo   [L] List all players
echo.
set /p MODE="Choose [1/2/L]: "

IF /I "%MODE%"=="L" (
    node admin/wipe-player.js --list
    echo.
    pause
    exit /b 0
)

IF "%MODE%"=="2" (
    node admin/wipe-player.js %USERNAME% --soft
) ELSE (
    node admin/wipe-player.js %USERNAME%
)

echo.
pause