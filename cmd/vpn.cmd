@echo off
@REM vpn - 显示所有可用 VPN 命令列表 / List all available VPN commands
@REM 用法: vpn
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -List
