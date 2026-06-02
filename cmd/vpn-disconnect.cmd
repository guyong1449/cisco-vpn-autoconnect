@echo off
@REM vpn-disconnect - 断开 VPN 连接 / Disconnect VPN
@REM 用法: vpn-disconnect
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Disconnect
