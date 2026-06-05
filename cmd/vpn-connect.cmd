@echo off
@REM vpn-connect: Connect to VPN with DUO 2FA
@REM Usage: vpn-connect              (default: DUO push)
@REM        vpn-connect push         (DUO push)
@REM        vpn-connect passcode     (auto TOTP, fully automatic)
@REM        vpn-connect -Preset dku
@REM        vpn-connect -Preset duke -DuoMethod push
@if "%~1"=="" (
    powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect
    goto :eof
)
@if /I "%~1"=="push" (
    powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect -DuoMethod push
    goto :eof
)
@if /I "%~1"=="passcode" (
    powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect -DuoMethod passcode
    goto :eof
)
@powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect %*
