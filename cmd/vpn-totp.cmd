@echo off
@REM vpn-totp: Deprecated - use 'vpn-config totp' instead
@REM This command redirects to vpn-config totp for unified config
echo [!] vpn-totp is deprecated. Use 'vpn-config totp' instead.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -SaveTOTP
