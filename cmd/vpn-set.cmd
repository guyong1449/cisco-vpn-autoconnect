@echo off
@REM vpn-set: Deprecated - use 'vpn-config set' instead
@REM This command redirects to vpn-config set for unified config
echo [!] vpn-set is deprecated. Use 'vpn-config set' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Set %1 -SetValue %2
