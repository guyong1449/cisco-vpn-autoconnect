@echo off
@REM vpn-reconfig: Deprecated - use 'vpn-config reset-all' instead
@REM This command redirects to vpn-config reset-all for unified config
echo [!] vpn-reconfig is deprecated. Use 'vpn-config reset-all' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Reconfigure
