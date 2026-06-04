@echo off
@REM vpn-use: Deprecated - use 'vpn-config use' instead
@REM This command redirects to vpn-config use for unified config
echo [!] vpn-use is deprecated. Use 'vpn-config use' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Use %1
