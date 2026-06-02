@echo off
@REM vpn-kill: Stop Cisco GUI and all vpncli (clears CLI lock). No connect attempt.
@REM Usage: vpn-kill
taskkill /IM csc_ui.exe /F /T >nul 2>&1
taskkill /IM vpnui.exe /F /T >nul 2>&1
taskkill /IM vpncli.exe /F /T >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process -Name vpncli,csc_ui,vpnui -ErrorAction SilentlyContinue | Format-Table Name,Id -AutoSize; if (-not (Get-Process vpncli -EA SilentlyContinue)) { Write-Host '[OK] No vpncli running' }"
