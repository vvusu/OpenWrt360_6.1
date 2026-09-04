@echo off
setlocal EnableDelayedExpansion
title JDCloud AX1800 Pro - Overlay Expansion (one-click)

echo ============================================================
echo  JDCloud AX1800 Pro (RE-SS-01) /overlay expansion to 111GB
echo  ------------------------------------------------------------
echo  Prerequisites:
echo   [1] Router already flashed with LibWrt firmware
echo   [2] Root password already set via LuCI first-boot wizard
echo   [3] PC plugged into any router LAN port (3 black ports)
echo  A backup of old p27 data is saved next to this script.
echo  Whole process: about 4-6 minutes. Do NOT unplug power.
echo ============================================================
echo.

cd /d "%~dp0"
set "OUT=%TEMP%\jd_extroot_out.txt"

REM ================= SSH tool =================
set "PLINK="
where plink.exe >nul 2>nul && set "PLINK=plink.exe"
if not defined PLINK if exist "%~dp0plink.exe" set "PLINK=%~dp0plink.exe"
if not defined PLINK (
    echo [SETUP] plink.exe not found, downloading official build...
    curl -fSL -o "%~dp0plink.exe" "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe"
    if errorlevel 1 (
        echo [ERROR] Download failed. Install PuTTY manually, put plink.exe
        echo         next to this script, then run again.
        goto :fail
    )
    set "PLINK=%~dp0plink.exe"
)
echo [OK] SSH tool ready.
echo.

REM ================= Parameters =================
set "IP="
set "PW="
if not "%~1"=="" set "IP=%~1"
if not "%~2"=="" set "PW=%~2"
if not defined IP set /p "IP=Router IP [Enter = 192.168.1.1 fresh-flash default]: "
if not defined IP set "IP=192.168.1.1"
if not defined PW set /p "PW=root SSH password [Enter = ubuntu2024]: "
if not defined PW set "PW=ubuntu2024"

REM ================= Connect (auto-try known IPs) =================
set "OKIP="
call :probe "%IP%"
if not defined OKIP if /i not "%IP%"=="192.168.2.1" call :probe "192.168.2.1"
if not defined OKIP if /i not "%IP%"=="192.168.1.1" call :probe "192.168.1.1"
if not defined OKIP (
    echo [ERROR] Cannot SSH into the router.
    echo         Check: LAN cable / router IP / root password.
    goto :fail
)
set "IP=%OKIP%"
echo [OK] Connected: root@%IP%
echo.

REM ================= Upload payload script =================
set "SHFILE=%TEMP%\jd_extroot_%RANDOM%.sh"
(for /f "usebackq tokens=1,* delims=:" %%a in (`findstr /b /c:"SHPAYLOAD:" "%~f0"`) do echo(%%b) > "%SHFILE%"
"%PLINK%" -batch -ssh -pw "%PW%" root@%IP% "cat > /tmp/jd-extroot.sh" < "%SHFILE%"
if errorlevel 1 (
    echo [ERROR] Failed to upload payload to router.
    goto :fail
)
echo [OK] Payload uploaded.
echo.

REM ================= Stage 1: device checks =================
echo [1/4] Checking device...
"%PLINK%" -batch -ssh -pw "%PW%" root@%IP% "sh /tmp/jd-extroot.sh stage1" > "%OUT%" 2>nul
type "%OUT%"
find "STAGE1_OK" < "%OUT%" >nul || goto :fail
echo.

REM ================= Stage 2: backup old p27 =================
set "BK=p27_backup_%RANDOM%%RANDOM%.tar.gz"
echo [2/4] Backing up old p27 data to %BK% ...
"%PLINK%" -batch -ssh -pw "%PW%" root@%IP% "tar czf - -C /mnt/mmcblk0p27 . 2>/dev/null" > "%BK%" 2>nul
if errorlevel 1 (
    echo [WARN] Backup stream returned an error.
    set "CONT="
    set /p "CONT=Continue WITHOUT backup? [y/N]: "
    if /i not "!CONT!"=="y" goto :fail
) else (
    for %%Z in ("%BK%") do if %%~zZ EQU 0 (
        echo [WARN] Backup file is empty - old p27 was probably unmountable.
        set "CONT="
        set /p "CONT=Continue anyway? [y/N]: "
        if /i not "!CONT!"=="y" goto :fail
    )
)
echo [OK] Backup done.
echo.

REM ================= Stage 3: format + fstab-first + copy =================
echo [3/4] Formatting p27 and configuring extroot - 1 to 3 minutes...
echo        fstab is edited BEFORE copying so future sysupgrade keeps it.
"%PLINK%" -batch -ssh -pw "%PW%" root@%IP% "sh /tmp/jd-extroot.sh stage2" > "%OUT%" 2>nul
type "%OUT%"
find "STAGE2_OK" < "%OUT%" >nul || goto :fail
echo.

REM ================= Stage 4: reboot + verify =================
echo [4/4] Rebooting router, verifying - up to 3 minutes...
"%PLINK%" -batch -ssh -pw "%PW%" root@%IP% "reboot" >nul 2>&1
set /a TRIES=0
:waitloop
set /a TRIES+=1
if %TRIES% GTR 15 goto :verifyfail
timeout /t 12 /nobreak >nul 2>&1
"%PLINK%" -batch -ssh -pw "%PW%" root@%IP% "df -h /overlay 2>/dev/null | tail -1" > "%OUT%" 2>nul
find "mmcblk0p27" < "%OUT%" >nul && goto :verified
goto :waitloop

:verified
echo.
type "%OUT%"
echo.
echo ============================================================
echo  SUCCESS - /overlay is now on mmcblk0p27 ^(111GB^).
echo  ------------------------------------------------------------
echo  After a fresh flash remember to:
echo   - add the homeproxy node in LuCI, Services, HomeProxy
echo   - proxy auto-starts about 90s after WAN comes up, by design
echo   - iStore is preinstalled, apps install into the 111GB
echo ============================================================
goto :done

:verifyfail
echo.
echo [WARN] Could not auto-confirm after reboot.
echo        Log into LuCI and run "df -h /overlay" to check.
echo        If it does not show mmcblk0p27, inspect /etc/config/fstab.
goto :done

:fail
echo.
echo ------------------------------------------------------------
echo  ABORTED - nothing changed after the last [OK] line above.
echo ------------------------------------------------------------

:done
echo.
pause
exit /b 0

:probe
echo [..] Trying %~1 ...
echo y | "%PLINK%" -ssh -pw "%PW%" root@%~1 "echo PROBE_OK" 2>nul | find "PROBE_OK" >nul && set "OKIP=%~1"
goto :eof

REM ============================================================
REM  Router-side payload below. Extracted and uploaded at runtime.
REM  Each line is prefixed with SHPAYLOAD: (stripped on upload).
REM ============================================================
SHPAYLOAD:#!/bin/sh
SHPAYLOAD:# JDCloud AX1800 Pro - overlay expansion payload (runs on router)
SHPAYLOAD:# Usage: jd-extroot.sh stage1|stage2
SHPAYLOAD:
SHPAYLOAD:stage="$1"
SHPAYLOAD:fail(){ echo "FAIL:$1"; exit 1; }
SHPAYLOAD:
SHPAYLOAD:if [ "$stage" = "stage1" ]; then
SHPAYLOAD:    grep -q LibWrt /etc/openwrt_release || fail not-libwrt
SHPAYLOAD:    bn=$(cat /tmp/sysinfo/board_name 2>/dev/null)
SHPAYLOAD:    echo "BOARD:$bn"
SHPAYLOAD:    case "$bn" in *re-ss-01*|*ax1800*) ;; *) fail not-jdcloud ;; esac
SHPAYLOAD:    [ -b /dev/mmcblk0p27 ] || fail no-p27-128GB-model-required
SHPAYLOAD:    mount | grep -q 'mmcblk0p27 on /overlay' && fail already-expanded
SHPAYLOAD:    mkdir -p /mnt/mmcblk0p27
SHPAYLOAD:    mountpoint -q /mnt/mmcblk0p27 2>/dev/null || mount /dev/mmcblk0p27 /mnt/mmcblk0p27 2>/dev/null
SHPAYLOAD:    echo STAGE1_OK
SHPAYLOAD:    exit 0
SHPAYLOAD:fi
SHPAYLOAD:
SHPAYLOAD:if [ "$stage" = "stage2" ]; then
SHPAYLOAD:    umount /mnt/mmcblk0p27 2>/dev/null
SHPAYLOAD:    umount -l /mnt/mmcblk0p27 2>/dev/null
SHPAYLOAD:    mountpoint -q /mnt/mmcblk0p27 && fail still-mounted
SHPAYLOAD:    echo "FORMATTING p27, 1-3 minutes, do not power off..."
SHPAYLOAD:    mkfs.ext4 -F /dev/mmcblk0p27 >/dev/null 2>&1 || fail mkfs
SHPAYLOAD:    echo FORMAT_OK
SHPAYLOAD:    mount /dev/mmcblk0p27 /mnt/mmcblk0p27 || fail mount-p27
SHPAYLOAD:    touch /etc/config/fstab
SHPAYLOAD:    s=$(uci show fstab 2>/dev/null | grep "target='/mnt/mmcblk0p27'" | head -n1 | cut -d. -f1-2)
SHPAYLOAD:    if [ -z "$s" ]; then
SHPAYLOAD:        n=$(uci add fstab mount)
SHPAYLOAD:        s="fstab.$n"
SHPAYLOAD:    fi
SHPAYLOAD:    uci set "$s.device=/dev/mmcblk0p27"
SHPAYLOAD:    uci -q delete "$s.uuid"
SHPAYLOAD:    uci set "$s.target=/overlay"
SHPAYLOAD:    uci set "$s.enabled=1"
SHPAYLOAD:    uci commit fstab || fail fstab-commit
SHPAYLOAD:    echo FSTAB_OK
SHPAYLOAD:    cp -a /overlay/. /mnt/mmcblk0p27/ || fail copy-overlay
SHPAYLOAD:    grep -q 'mmcblk0p27' /mnt/mmcblk0p27/upper/etc/config/fstab || fail copy-verify
SHPAYLOAD:    echo COPY_OK
SHPAYLOAD:    echo STAGE2_OK
SHPAYLOAD:    exit 0
SHPAYLOAD:fi
SHPAYLOAD:
SHPAYLOAD:fail bad-stage
