@echo off
@REM qrdecode: CLI QR decoder, extracts TOTP secrets from images
@REM Usage: qrdecode screenshot.png
python "%~dp0qrdecode.py" %*
