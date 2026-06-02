@echo off
@REM vpn-setup - 保存/更新 VPN 凭据 (旧版单配置) / Save or update VPN credentials (legacy)
@REM 用法: vpn-setup
@REM 提示: 推荐使用 vpn-add 创建多配置 Profile
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -SaveCredentials
