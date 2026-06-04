@echo off
@REM vpn-help: Show detailed help
@REM Usage: vpn-help
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Help
