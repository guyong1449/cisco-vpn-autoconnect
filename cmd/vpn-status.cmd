@echo off
@REM vpn-status - 显示 VPN 连接状态 (检查 10.x.x.x IP) / Show VPN connection status
@REM 用法: vpn-status
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Status
