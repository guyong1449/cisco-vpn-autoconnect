@echo off
@REM vpn-help - 显示详细帮助信息 / Show detailed help
@REM 用法: vpn-help
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Help
