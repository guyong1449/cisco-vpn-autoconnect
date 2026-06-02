@echo off
@REM vpn-totp - 保存 DUO TOTP 密钥 (用于全自动登录) / Save DUO TOTP secret for full-auto login
@REM 用法: vpn-totp
@REM 密钥格式: Base32 (A-Z, 2-7)，从 DUO 二维码 URL 中的 secret= 参数获取
@REM 获取方式: 用 qrgui 解码 DUO 二维码，复制 Secret 字段
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -SaveTOTP
