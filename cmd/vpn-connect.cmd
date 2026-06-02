@echo off
@REM vpn-connect - 连接 VPN (默认 DUO Push) / Connect to VPN with DUO 2FA
@REM 用法: vpn-connect
@REM        vpn-connect push        # 发送手机推送通知
@REM        vpn-connect phone       # 电话验证
@REM        vpn-connect sms         # 短信验证码
@REM        vpn-connect passcode    # 自动生成 TOTP 验证码 (全自动)
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect %*
