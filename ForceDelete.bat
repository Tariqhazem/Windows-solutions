@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  ForceDelete.bat  (v3)
::  Drag files/folders onto this file -> permanent delete.
::  No Recycle Bin. No confirmation. Window stays open.
::  Writes ForceDelete.log next to itself.
:: ============================================================

set "LOG=%~dp0ForceDelete.log"
>> "%LOG%" echo.
>> "%LOG%" echo ====== %DATE% %TIME% ======
>> "%LOG%" echo cmdline: %*

:: Re-entry marker after self-elevation
if /i "%~1"=="--forced" (
    shift
    goto :ElevatedRun
)

if "%~1"=="" (
    echo.
    echo  ForceDelete - drag files/folders onto this file.
    echo  Permanent. No Recycle Bin. No confirmation.
    echo.
    pause
    exit /b 1
)

echo.
echo  === ForceDelete v3 ===
echo  User:      %USERDOMAIN%\%USERNAME%
whoami /groups 2>nul | findstr /i "S-1-5-32-544" >nul
if errorlevel 1 (
    echo  Privilege: STANDARD USER  ^(items needing admin will fail^)
    set "AM_ADMIN=0"
) else (
    echo  Privilege: ADMINISTRATOR
    set "AM_ADMIN=1"
)
echo  Log:       %LOG%
echo.

:: --- Process args via shift loop (correct quoting for paths with spaces) ---
set "STUBBORN_COUNT=0"
set "STUBBORN_LIST="

:ArgLoop
if "%~1"=="" goto :ArgDone
call :SoftDelete "%~1"
if exist "%~1" (
    set /a STUBBORN_COUNT+=1
    set STUBBORN_LIST=!STUBBORN_LIST! "%~1"
)
shift
goto :ArgLoop
:ArgDone

if %STUBBORN_COUNT%==0 (
    echo.
    echo  All items deleted.
    >> "%LOG%" echo result: all deleted
    pause
    exit /b 0
)

echo.
echo  %STUBBORN_COUNT% item^(s^) resisted plain delete.

if "%AM_ADMIN%"=="0" (
    echo.
    echo  You are a STANDARD USER. Items owned by SYSTEM, TrustedInstaller,
    echo  or another user account cannot be deleted from this account
    echo  without an administrator password. No script can bypass this.
    echo.
    echo  Trying elevation anyway in case UAC accepts a Yes click...
)

powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '--forced %STUBBORN_LIST%' -Verb RunAs" 2>>"%LOG%"
if errorlevel 1 (
    echo.
    echo  Elevation denied or failed. Stubborn items remain.
    >> "%LOG%" echo result: elevation denied
    pause
)
exit /b 0


:ElevatedRun
echo.
echo  === Elevated pass ===
:ElevLoop
if "%~1"=="" goto :ElevDone
call :HardDelete "%~1"
shift
goto :ElevLoop
:ElevDone
echo.
echo  Done.
pause
exit /b 0


:: ============================================================
:: Subroutines
:: ============================================================

:SoftDelete
set "T=%~1"
echo.
echo  Trying: %T%
>> "%LOG%" echo trying: %T%

if not exist "%T%" (
    echo   [SKIP] not found
    >> "%LOG%" echo   skip-not-found
    exit /b 0
)

attrib -r -h -s "%T%" /s /d 2>nul

if exist "%T%\" (
    rmdir /s /q "%T%" 2>>"%LOG%"
) else (
    del /f /q "%T%" 2>>"%LOG%"
)

if exist "%T%" (
    echo   [STUCK] needs admin or has DENY ACE
    >> "%LOG%" echo   stuck
) else (
    echo   [OK]
    >> "%LOG%" echo   ok
)
exit /b 0


:HardDelete
set "T=%~1"
if not exist "%T%" exit /b 0
echo.
echo  Forcing: %T%
>> "%LOG%" echo forcing: %T%

:: Remove explicit DENY entries (DENY beats GRANT)
icacls "%T%" /remove:d *S-1-1-0 /c /q >nul 2>&1
icacls "%T%" /remove:d *S-1-5-32-545 /c /q >nul 2>&1
icacls "%T%" /remove:d *S-1-5-32-544 /c /q >nul 2>&1

if exist "%T%\" (
    takeown /f "%T%" /r /d y >nul 2>&1
) else (
    takeown /f "%T%" >nul 2>&1
)

icacls "%T%" /reset /t /c /q >nul 2>&1
icacls "%T%" /grant *S-1-5-32-544:F /t /c /q >nul 2>&1

attrib -r -h -s "%T%" /s /d 2>nul

if exist "%T%\" (
    if exist "%T%\NTUSER.DAT" (
        for /f "tokens=*" %%H in ('reg query HKU 2^>nul ^| findstr /v "DEFAULT \.DEFAULT S-1-5-18 S-1-5-19 S-1-5-20"') do (
            reg unload "%%H" >nul 2>&1
        )
    )

    powershell -NoProfile -Command ^
        "Get-ChildItem -LiteralPath '%T%' -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { try { if ($_.PSIsContainer) { [IO.Directory]::Delete($_.FullName, $false) } else { [IO.File]::Delete($_.FullName) } } catch {} }" 2>nul

    powershell -NoProfile -Command "try { Remove-Item -LiteralPath '%T%' -Recurse -Force -ErrorAction Stop } catch { }" 2>nul
    if exist "%T%" rmdir /s /q "%T%" 2>>"%LOG%"

    if exist "%T%" (
        set "EMPTY=%TEMP%\__fd_empty_%RANDOM%__"
        mkdir "!EMPTY!" 2>nul
        robocopy "!EMPTY!" "%T%" /MIR /NFL /NDL /NJH /NJS /NC /NS /NP >nul 2>&1
        rmdir /s /q "%T%" 2>nul
        rmdir /s /q "!EMPTY!" 2>nul
    )
) else (
    powershell -NoProfile -Command "try { Remove-Item -LiteralPath '%T%' -Force -ErrorAction Stop } catch { }" 2>nul
    if exist "%T%" del /f /q "%T%" 2>>"%LOG%"
)

if exist "%T%" (
    echo   [FAIL] still here. Final ACL:
    icacls "%T%" 2>&1
    >> "%LOG%" echo   FAIL
) else (
    echo   [OK]
    >> "%LOG%" echo   ok
)
exit /b 0
