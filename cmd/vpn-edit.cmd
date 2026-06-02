@echo off
@REM vpn-edit: Deprecated - use 'vpn-config set' instead
@REM This command redirects to vpn-config set for unified config
echo [!] vpn-edit is deprecated. Use 'vpn-config set' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Edit %1
