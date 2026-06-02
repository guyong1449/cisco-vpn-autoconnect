@echo off
@REM vpn-connect: Connect to VPN with DUO 2FA
@REM Usage: vpn-connect              (default: DUO push)
@REM        vpn-connect push         (phone notification)
@REM        vpn-connect phone        (call verification)
@REM        vpn-connect sms          (SMS code)
@REM        vpn-connect passcode     (auto TOTP, fully automatic)
@if "%~1"=="" (
    powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect -DuoMethod %1
)
