#!/usr/bin/env python3
"""
Cisco Secure Client Auto-Connect Script (with DUO 2FA)
=====================================================
Usage:
  python vpn_auto_connect.py                  # First-time setup + connect
  python vpn_auto_connect.py --connect        # Auto-connect (DUO push)
  python vpn_auto_connect.py --connect --duo-method passcode  # Full auto (TOTP)
  python vpn_auto_connect.py --disconnect     # Disconnect VPN
  python vpn_auto_connect.py --save-totp      # Save TOTP secret
  python vpn_auto_connect.py --status         # Show connection status
"""

import argparse
import json
import os
import sys
import time
import base64
import hmac
import hashlib
import struct
from pathlib import Path

# ---------- Config ----------
VPNCLI_PATH = r"C:\Program Files (x86)\Cisco\Cisco Secure Client\vpncli.exe"
CONFIG_DIR = Path.home() / ".vpn-auto-connect"
CRED_FILE = CONFIG_DIR / "credentials.json"
CONFIG_FILE = CONFIG_DIR / "config.json"
TOTP_FILE = CONFIG_DIR / "totp.json"


def ensure_config_dir():
    """Create config directory and restrict permissions."""
    CONFIG_DIR.mkdir(exist_ok=True)
    if sys.platform == "win32":
        import subprocess
        subprocess.run(
            ["icacls", str(CONFIG_DIR), "/inheritance:r",
             "/grant:r", f"{os.getenv('USERNAME')}:(OI)(CI)F"],
            capture_output=True
        )


def save_config(server: str, group: str = ""):
    """Save VPN config."""
    ensure_config_dir()
    config = {"server": server, "group": group}
    CONFIG_FILE.write_text(json.dumps(config, indent=2), encoding="utf-8")


def load_config() -> dict | None:
    """Load VPN config."""
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    return None


def save_credentials(server: str, username: str, password: str):
    """Save credentials (Base64 encoded, not plaintext)."""
    ensure_config_dir()
    cred = {
        "server": server,
        "username": username,
        "password": base64.b64encode(password.encode()).decode()
    }
    CRED_FILE.write_text(json.dumps(cred, indent=2), encoding="utf-8")
    print(f"[OK] Credentials saved to: {CRED_FILE}")


def load_credentials() -> dict | None:
    """Load credentials."""
    if not CRED_FILE.exists():
        print("[!!] No saved credentials found. Run setup first.")
        return None
    cred = json.loads(CRED_FILE.read_text(encoding="utf-8"))
    cred["password"] = base64.b64decode(cred["password"]).decode()
    return cred


def save_totp_secret(secret: str):
    """Save TOTP secret."""
    ensure_config_dir()
    TOTP_FILE.write_text(json.dumps({"secret": secret.upper().strip()}), encoding="utf-8")
    print("[OK] TOTP secret saved")


def load_totp_secret() -> str | None:
    """Load TOTP secret."""
    if not TOTP_FILE.exists():
        return None
    data = json.loads(TOTP_FILE.read_text(encoding="utf-8"))
    return data.get("secret")


def generate_totp(secret: str, time_step: int = 30, digits: int = 6) -> str:
    """Generate TOTP code (RFC 6238)."""
    secret = secret.upper().strip().rstrip("=")
    padding = (8 - len(secret) % 8) % 8
    secret += "=" * padding
    key = base64.b32decode(secret)

    counter = int(time.time()) // time_step

    counter_bytes = struct.pack(">Q", counter)
    hmac_hash = hmac.new(key, counter_bytes, hashlib.sha1).digest()

    offset = hmac_hash[-1] & 0x0F
    code = (
        ((hmac_hash[offset] & 0x7F) << 24)
        | ((hmac_hash[offset + 1] & 0xFF) << 16)
        | ((hmac_hash[offset + 2] & 0xFF) << 8)
        | (hmac_hash[offset + 3] & 0xFF)
    )

    return str(code % (10 ** digits)).zfill(digits)


def connect_vpn(duo_method: str = "push"):
    """Connect to VPN (with DUO 2FA)."""
    try:
        import wexpect
    except ImportError:
        print("[!!] Missing 'wexpect' library. Run: pip install wexpect")
        print("     Or use the PowerShell version: .\\vpn-auto-connect.ps1 -Connect")
        return False

    cred = load_credentials()
    if not cred:
        return False

    config = load_config()
    server = cred["server"]

    # Determine DUO input
    if duo_method == "passcode":
        secret = load_totp_secret()
        if not secret:
            print("[!!] TOTP secret not found. Run: python vpn_auto_connect.py --save-totp")
            return False
        duo_input = generate_totp(secret)
        print(f"[>>] TOTP code: {duo_input}")
    else:
        duo_input = duo_method
        if duo_method == "push":
            print("[>>] Please tap 'Approve' on your DUO mobile push")

    # Close GUI client if running (it blocks vpncli)
    import subprocess
    try:
        result = subprocess.run(["tasklist", "/FI", "IMAGENAME eq csc_ui.exe"], capture_output=True, text=True)
        if "csc_ui" in result.stdout:
            print("[..] Closing Cisco GUI client (blocks CLI)...")
            subprocess.run(["taskkill", "/F", "/IM", "csc_ui.exe"], capture_output=True)
            time.sleep(2)
    except Exception:
        pass

    print(f"[->] Connecting to: {server}")
    print(f"     User: {cred['username']}")
    print(f"     DUO method: {duo_method}")

    # Launch vpncli
    child = wexpect.spawn(f'"{VPNCLI_PATH}" -s', encoding="utf-8", timeout=60)

    try:
        child.expect(r"VPN>")
        child.sendline(f"connect {server}")

        if config and config.get("group"):
            child.expect(r"Group:")
            child.sendline(config["group"])

        child.expect(r"[Uu]sername:|[Ll]ogin:")
        child.sendline(cred["username"])

        child.expect(r"[Pp]assword:")
        child.sendline(cred["password"])

        # DUO second factor
        duo_prompts = [
            r"[Dd]uo.*:",
            r"[Ss]econd [Pp]assword:",
            r"[Pp]asscode:",
            r"[Ff]actor:",
            r"push|phone|sms|passcode",
        ]
        child.expect("|".join(duo_prompts), timeout=15)
        child.sendline(duo_input)

        # Accept certificate (if prompted)
        try:
            child.expect(r"[Aa]ccept\?.*\[y/n\]|certificate", timeout=10)
            child.sendline("y")
        except wexpect.TIMEOUT:
            pass

        # Wait for result
        child.expect(r"[Cc]onnected|[Ll]ogin denied|[Aa]uthentication failed", timeout=30)

        if "onnected" in (child.after or ""):
            print("[OK] VPN connected!")
            return True
        elif "denied" in (child.after or "").lower() or "failed" in (child.after or "").lower():
            print("[!!] Authentication failed. Check credentials or DUO settings.")
            return False
        else:
            print("[??] Connection status uncertain. Check output above.")
            return False

    except wexpect.TIMEOUT:
        print("[!!] Connection timed out. Check network or VPN server.")
        return False
    except Exception as e:
        print(f"[!!] Error: {e}")
        return False
    finally:
        try:
            child.close()
        except Exception:
            pass


def disconnect_vpn():
    """Disconnect VPN."""
    try:
        import wexpect
        child = wexpect.spawn(f'"{VPNCLI_PATH}" -s', encoding="utf-8", timeout=15)
        child.expect(r"VPN>")
        child.sendline("disconnect")
        time.sleep(2)
        child.close()
        print("[OK] VPN disconnected")
    except ImportError:
        import subprocess
        subprocess.run([VPNCLI_PATH, "-s"], input="disconnect\n", text=True)
        print("[OK] VPN disconnected")


def show_status():
    """Show connection status."""
    import subprocess
    try:
        result = subprocess.run(
            [VPNCLI_PATH, "-s", "status"],
            capture_output=True, text=True, timeout=10
        )
        output = result.stdout
        if "Connected" in output:
            print("[*] Status: Connected")
        else:
            print("[!!] Status: Disconnected")
        print(output)
    except FileNotFoundError:
        print("[!!] vpncli.exe not found")
    except Exception as e:
        print(f"[!!] Error: {e}")


def interactive_setup():
    """Interactive first-time setup."""
    print("=== Cisco Secure Client Auto-Connect - First-Time Setup ===\n")
    print("Examples: vpn.duke.edu, vpn.company.com, 10.0.0.1")
    print("          Use FQDN (domain name) or IP address\n")

    server = input("Enter VPN server address: ").strip()
    group = input("Enter VPN Group (leave blank to skip): ").strip()

    save_config(server, group)

    username = input("Enter username: ").strip()
    password = input("Enter password: ").strip()

    save_credentials(server, username, password)

    save_totp = input("Save DUO TOTP secret? (y/N): ").strip().lower()
    if save_totp == "y":
        secret = input("Enter TOTP secret (Base32 format): ").strip()
        if secret:
            save_totp_secret(secret)

    print("\n[OK] Setup complete!")
    print(f"     Config dir: {CONFIG_DIR}")
    print(f"\n     Connect command: python {__file__} --connect")
    print(f"     Full auto (TOTP): python {__file__} --connect --duo-method passcode")


def main():
    parser = argparse.ArgumentParser(description="Cisco Secure Client Auto-Connect Tool (with DUO 2FA)")
    parser.add_argument("--connect", action="store_true", help="Auto-connect to VPN")
    parser.add_argument("--disconnect", action="store_true", help="Disconnect VPN")
    parser.add_argument("--status", action="store_true", help="Show connection status")
    parser.add_argument("--save-credentials", action="store_true", help="Save credentials")
    parser.add_argument("--save-totp", action="store_true", help="Save TOTP secret")
    parser.add_argument("--duo-method", choices=["push", "phone", "sms", "passcode"],
                        default="push", help="DUO method (default: push)")
    parser.add_argument("--server", help="VPN server address (FQDN or IP, e.g. vpn.duke.edu)")
    parser.add_argument("--username", help="Username")
    parser.add_argument("--password", help="Password")
    parser.add_argument("--totp-secret", help="TOTP secret")

    args = parser.parse_args()

    # Save credentials via CLI args
    if args.save_credentials:
        if args.server and args.username and args.password:
            save_config(args.server)
            save_credentials(args.server, args.username, args.password)
        else:
            print("[!!] Requires --server, --username, --password")
        return

    if args.save_totp:
        if args.totp_secret:
            save_totp_secret(args.totp_secret)
        else:
            secret = input("Enter TOTP secret: ").strip()
            if secret:
                save_totp_secret(secret)
        return

    if args.connect:
        connect_vpn(args.duo_method)
    elif args.disconnect:
        disconnect_vpn()
    elif args.status:
        show_status()
    else:
        # Default: first-time setup or auto-connect
        config = load_config()
        if not config:
            interactive_setup()
        else:
            connect_vpn(args.duo_method)


if __name__ == "__main__":
    main()
