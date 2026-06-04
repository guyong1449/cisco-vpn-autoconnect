@echo off
@REM vpn: List all available VPN commands
@REM Usage: vpn
@REM        vpn -h    (detailed help)
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -List %*
