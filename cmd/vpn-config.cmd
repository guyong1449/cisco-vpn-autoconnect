@echo off
@REM vpn-config: Unified VPN configuration manager
@REM Usage: vpn-config                  Show all settings
@REM        vpn-config list             List all profiles
@REM        vpn-config add              Add new profile
@REM        vpn-config use <name>       Switch active profile
@REM        vpn-config set <key> <val>  Quick setting change
@REM        vpn-config totp             Save TOTP secret
@REM        vpn-config rm <name>        Remove a profile
@REM        vpn-config reset-all        Full reset and re-setup
set "SUB=%~1"
if "%SUB%"=="" goto show
if /I "%SUB%"=="list" goto list
if /I "%SUB%"=="add" goto add
if /I "%SUB%"=="use" goto use
if /I "%SUB%"=="set" goto set
if /I "%SUB%"=="totp" goto totp
if /I "%SUB%"=="rm" goto rm
if /I "%SUB%"=="reset-all" goto resetall
echo [!] Unknown subcommand: %SUB%
echo.
echo Usage: vpn-config [list^|add^|use^|set^|totp^|rm^|reset-all]
echo        vpn-config              Show all settings
echo        vpn-config list         List all profiles
echo        vpn-config add          Add new profile
echo        vpn-config use ^<name^>  Switch active profile
echo        vpn-config set ^<k^> ^<v^> Quick setting change
echo        vpn-config totp         Save TOTP secret
echo        vpn-config rm ^<name^>   Remove a profile
echo        vpn-config reset-all    Full reset and re-setup
exit /b 1
:show
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Config
exit /b
:list
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Config -Brief
exit /b
:add
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Add
exit /b
:use
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Use %2
exit /b
:set
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Set %2 -SetValue %3
exit /b
:totp
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -SaveTOTP
exit /b
:rm
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Rm %2
exit /b
:resetall
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Reconfigure
exit /b
