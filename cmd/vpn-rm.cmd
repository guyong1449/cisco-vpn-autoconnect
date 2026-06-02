@echo off
@REM vpn-rm - 删除指定 VPN Profile / Remove a VPN profile
@REM 用法: vpn-rm <profile-name>
@REM 示例: vpn-rm old-config
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Rm %1
