@echo off
@REM vpn-use - 切换当前活跃的 VPN Profile / Switch active VPN profile
@REM 用法: vpn-use <profile-name>
@REM 示例: vpn-use dku
@REM        vpn-use company
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Use %1
