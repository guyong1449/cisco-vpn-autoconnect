@echo off
@REM vpn-rm: Deprecated - use 'vpn-config rm' instead
@REM This command redirects to vpn-config rm for unified config
echo [!] vpn-rm is deprecated. Use 'vpn-config rm' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Rm %1
