@echo off
@REM vpn-ls - 列出所有 VPN 配置 Profile / List all VPN profiles
@REM 用法: vpn-ls
@REM 显示: 每个 Profile 的名称、服务器地址，* 标记当前活跃配置
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Ls
