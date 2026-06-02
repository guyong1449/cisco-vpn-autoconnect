@echo off
@REM vpn-ls: Deprecated - use 'vpn-config list' instead
@REM This command redirects to vpn-config list for unified config
echo [!] vpn-ls is deprecated. Use 'vpn-config list' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Config -Brief
