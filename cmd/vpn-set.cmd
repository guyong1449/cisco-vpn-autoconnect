@echo off
@REM vpn-set - 快速修改单个设置项 / Quick-change a single VPN setting
@REM 用法: vpn-set <key> <value>
@REM 示例: vpn-set server portal.dukekunshan.edu.cn
@REM        vpn-set port 8443
@REM        vpn-set protocol ipsec
@REM        vpn-set duo passcode
@REM        vpn-set user newuser    (会提示输入密码)
@REM 可用 key: server, group, port, protocol, user, duo
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Set %1 -SetValue %2
