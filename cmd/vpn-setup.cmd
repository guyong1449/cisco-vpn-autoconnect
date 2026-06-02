@echo off
@REM vpn-setup: Deprecated - use 'vpn-config add' instead
@REM This command redirects to vpn-config add for multi-profile support
echo [!] vpn-setup is deprecated. Use 'vpn-config add' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Add
