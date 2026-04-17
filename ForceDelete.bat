@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  ForceDelete.bat
::  ----------------------------------------------------------
::  Drag any file or folder onto this batch file to delete it.
::  Bypasses Recycle Bin. Designed to recover from malware that
::  corrupted ACLs or ownership on your own files.
::
::  Layered strategy (does as much as your privileges allow):
::    1) Strip read-only/hidden/system attributes, plain delete.
::    2) If anything stubborn remains, relaunch elevated.
::    3) Elevated pass: takeown + icacls (SID-based, language
::       independent) + robocopy /MIR empty-dir trick for stuck
::       folders and >260-char paths.
::
::  Honest limit: a true standard user with no admin password
::  cannot pass UAC. Layer 1 still runs; layers 2-3 require
::  clicking "Yes" or providing admin credentials.
:: ============================================================

:: Re-entry marker after self-elevation
if /i "%~1"=="--forced" (
    shift
    goto :ElevatedRun
)

if "%~1"=="" (
    echo.
    echo  ForceDelete - drag files or folders onto this file.
    echo  WARNING: deletion is PERMANENT (no Recycle Bin).
    echo.
    pause
    exit /b 1
)

echo.
echo  Items to PERMANENTLY DELETE:
echo  ----------------------------
for %%I in (%*) do echo    %%~fI
echo  ----------------------------
choice /C YN /N /M "Proceed? [Y/N]: "
if errorlevel 2 (
    echo Cancelled.
    timeout /t 1 >nul
    exit /b 0
)

:: --- LAYER 1: try plain delete (no admin needed) ---
set "STUBBORN="
for %%I in (%*) do (
    call :SoftDelete "%%~fI"
    if exist "%%~fI" set STUBBORN=!STUBBORN! "%%~fI"
)

if not defined STUBBORN (
    echo.
    echo All items deleted.
    timeout /t 2 >nul
    exit /b 0
)

:: --- LAYER 2: relaunch elevated for the stubborn ones ---
echo.
echo Some items resisted. Requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '--forced %STUBBORN%' -Verb RunAs"
exit /b 0


:ElevatedRun
:: Now running with admin rights (layer 3)
echo.
echo Running with administrator rights.
for %%I in (%*) do call :HardDelete "%%~fI"
echo.
echo Done.
pause
exit /b 0


:: ----- Subroutines -----

:SoftDelete
set "T=%~1"
if not exist "%T%" exit /b 0
attrib -r -h -s "%T%" /s /d 2>nul
if exist "%T%\" (
    rmdir /s /q "%T%" 2>nul
) else (
    del /f /q "%T%" 2>nul
)
exit /b 0


:HardDelete
set "T=%~1"
if not exist "%T%" exit /b 0
echo.
echo Forcing: %T%

if exist "%T%\" (
    takeown /f "%T%" /r /d y >nul 2>&1
    icacls "%T%" /grant *S-1-5-32-544:F /t /c /q >nul 2>&1
    icacls "%T%" /reset /t /c /q >nul 2>&1
    attrib -r -h -s "%T%" /s /d 2>nul
    rmdir /s /q "%T%" 2>nul
    if exist "%T%" (
        set "EMPTY=%TEMP%\__fd_empty_%RANDOM%__"
        mkdir "!EMPTY!" 2>nul
        robocopy "!EMPTY!" "%T%" /MIR /NFL /NDL /NJH /NJS /NC /NS /NP >nul 2>&1
        rmdir /s /q "%T%" 2>nul
        rmdir /s /q "!EMPTY!" 2>nul
    )
) else (
    takeown /f "%T%" >nul 2>&1
    icacls "%T%" /grant *S-1-5-32-544:F /c /q >nul 2>&1
    attrib -r -h -s "%T%" 2>nul
    del /f /q "%T%" 2>nul
)

if exist "%T%" (
    echo   [FAIL] Could not delete - may be locked, in use, or owned by TrustedInstaller.
) else (
    echo   [OK] Deleted.
)
exit /b 0
