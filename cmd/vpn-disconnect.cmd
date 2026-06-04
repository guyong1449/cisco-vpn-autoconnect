@echo off
@REM vpn-disconnect: Disconnect VPN
@REM Usage: vpn-disconnect
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Disconnect
