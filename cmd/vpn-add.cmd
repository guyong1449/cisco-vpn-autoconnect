@echo off
@REM vpn-add - 添加新 VPN 配置 Profile / Add a new VPN profile
@REM 用法: vpn-add
@REM 交互输入: 名称、服务器、分组、端口、协议、用户名、密码
@REM 示例: vpn-add  ->  输入名称 "dku" ->  输入 portal.dukekunshan.edu.cn
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Add
