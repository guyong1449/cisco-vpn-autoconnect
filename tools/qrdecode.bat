@echo off
# QR Decode CLI - 命令行二维码解码
# 用法: qrdecode <图片路径>
# 示例: qrdecode screenshot.png
#        qrdecode duo-qr-code.jpg
python "%~dp0qrdecode.py" %*
