@echo off
@REM vpn-reconfig - 清除所有配置并重新设置 / Clear all config and re-run full setup
@REM 用法: vpn-reconfig
@REM 注意: 会删除 config.json 和 credentials.xml，但不影响 Profile 配置
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Reconfigure
