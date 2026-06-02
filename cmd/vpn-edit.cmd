@echo off
@REM vpn-edit - 编辑已有 VPN Profile 设置 / Edit existing VPN profile settings
@REM 用法: vpn-edit <profile-name>
@REM 示例: vpn-edit dku  ->  交互修改服务器、分组、端口、协议、凭据
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Edit %1
