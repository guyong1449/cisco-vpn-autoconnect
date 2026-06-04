@echo off
@REM vpn-add: Deprecated - use 'vpn-config add' instead
@REM This command redirects to vpn-config add for unified config
echo [!] vpn-add is deprecated. Use 'vpn-config add' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Add
