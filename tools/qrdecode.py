#!/usr/bin/env python3
"""QR Code Decoder - 从图片中解码二维码并提取 TOTP 密钥"""

import sys
import re
from urllib.parse import urlparse, parse_qs, unquote

try:
    from pyzbar.pyzbar import decode
    from PIL import Image
except ImportError:
    print("缺少依赖，请安装:")
    print("  pip install pyzbar Pillow")
    sys.exit(1)


def decode_qr(image_path: str) -> list[str]:
    """解码图片中的所有二维码，返回内容列表"""
    img = Image.open(image_path)
    results = decode(img)
    if not results:
        return []
    return [r.data.decode("utf-8") for r in results]


def parse_totp_url(url: str) -> dict | None:
    """解析 otpauth://totp/... 格式的 URL，提取关键信息"""
    if not url.startswith("otpauth://"):
        return None
    parsed = urlparse(url)
    params = parse_qs(parsed.query)
    account = unquote(parsed.path.lstrip("/totp/"))
    return {
        "account": account,
        "secret": params.get("secret", [""])[0],
        "issuer": params.get("issuer", [""])[0],
    }


def main():
    if len(sys.argv) < 2:
        print("用法: qrdecode <图片路径>")
        print("示例: qrdecode screenshot.png")
        sys.exit(1)

    image_path = sys.argv[1]
    try:
        contents = decode_qr(image_path)
    except FileNotFoundError:
        print(f"文件不存在: {image_path}")
        sys.exit(1)
    except Exception as e:
        print(f"解码失败: {e}")
        sys.exit(1)

    if not contents:
        print("未检测到二维码")
        sys.exit(1)

    for i, content in enumerate(contents):
        if len(contents) > 1:
            print(f"\n--- 二维码 {i + 1} ---")
        print(f"内容: {content}")

        totp = parse_totp_url(content)
        if totp:
            print(f"账号: {totp['account']}")
            print(f"密钥: {totp['secret']}")
            print(f"发行: {totp['issuer']}")


if __name__ == "__main__":
    main()
