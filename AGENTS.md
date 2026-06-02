# VPN Auto-Connect Agent

Cisco Secure Client auto-connect tool with DUO 2FA support.

## Current Status

- **Multi-Profile Support**: Implemented (vpn-add/ls/use/rm/edit)
- **One-Click Settings**: Implemented (vpn-set)
- **GUI Manager**: Implemented (vpn-gui.py) with DKU preset
- **QR Tools**: Integrated (qrdecode.py + qrdecode_gui.py)
- **GitHub Ready**: .gitignore, LICENSE, README.md, git initialized

## Current Goal

GUI DKU preset simplification: Remove the "Name" field from DKU preset dialog.
Since DKU is a preset, the profile name should be auto-set to "dku" — no user input needed.
Only require: NetID, Password, Group (dropdown).

## File Structure

```
tools/vpn-auto-connect/
├── AGENTS.md                  # This file
├── README.md                  # Bilingual documentation
├── LICENSE                    # MIT License
├── .gitignore
├── vpn-auto-connect.ps1       # Core script (PowerShell)
├── vpn_auto_connect.py        # Alternative (Python + wexpect)
├── vpn-gui.bat                # GUI launcher
│
├── cmd/                       # Entry point scripts (ASCII-only @REM comments)
│   ├── vpn.cmd                # List commands
│   ├── vpn-connect.cmd        # Connect
│   ├── vpn-disconnect.cmd     # Disconnect
│   ├── vpn-status.cmd         # Show status
│   ├── vpn-setup.cmd          # First-time setup (legacy)
│   ├── vpn-totp.cmd           # Save TOTP secret
│   ├── vpn-reconfig.cmd       # Reset and reconfigure
│   ├── vpn-help.cmd           # Show help
│   ├── vpn-add.cmd            # Add new profile
│   ├── vpn-ls.cmd             # List all profiles
│   ├── vpn-use.cmd            # Switch active profile
│   ├── vpn-rm.cmd             # Remove a profile
│   ├── vpn-edit.cmd           # Edit profile settings
│   ├── vpn-set.cmd            # Quick setting change
│   └── vpn-gui.cmd            # Launch GUI
│
└── tools/                     # Auxiliary tools
    ├── qrdecode.py            # QR decoder (CLI)
    ├── qrdecode_gui.py        # QR decoder (GUI)
    ├── qrdecode.bat           # CLI launcher
    ├── qrgui.bat              # GUI launcher
    └── vpn-gui.py             # VPN GUI manager
```

## Main Interfaces

### PowerShell Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `vpn` | (none) | List all available commands |
| `vpn-connect` | `[-DuoMethod <method>]` | Connect to VPN |
| `vpn-disconnect` | (none) | Disconnect VPN |
| `vpn-status` | (none) | Show connection status (checks 10.x.x.x IP) |
| `vpn-setup` | (none) | Save credentials (requires existing config) |
| `vpn-totp` | (none) | Save TOTP secret for full-auto mode |
| `vpn-reconfig` | (none) | Clear all config, re-run full setup |
| `vpn-help` | (none) | Show detailed help |

### Profile Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `vpn-add` | (none) | Add new VPN profile |
| `vpn-ls` | (none) | List all profiles |
| `vpn-use` | `<name>` | Switch active profile |
| `vpn-rm` | `<name>` | Remove a profile |
| `vpn-edit` | `<name>` | Edit profile settings |
| `vpn-set` | `<key> <value>` | Quick setting change |
| `vpn-gui` | (none) | Launch GUI manager |

### GUI DKU Preset

When "Duke Kunshan VPN" preset is selected in GUI:
- Server: `portal.dukekunshan.edu.cn` (pre-filled, hidden)
- Port: `443` (pre-filled, hidden)
- Protocol: `ssl` (pre-filled, hidden)
- Profile name: auto-set to `dku` (no user input)
- User input required: **NetID**, **Password**, **Group** (dropdown: -Default- / Library Resources Only)

### Direct Script Usage

```powershell
# PowerShell
.\vpn-auto-connect.ps1 -Connect -DuoMethod passcode

# Python
python vpn_auto_connect.py --connect --duo-method passcode
```

## Parameters

### Connection Parameters

| Parameter | Type | Default | Values | Description |
|-----------|------|---------|--------|-------------|
| `-Connect` | switch | false | - | Initiate connection |
| `-Disconnect` | switch | false | - | Disconnect VPN |
| `-DuoMethod` | string | "push" | push, phone, sms, passcode | DUO 2FA method |
| `-Status` | switch | false | - | Show VPN status |

### Setup Parameters

| Parameter | Type | Default | Values | Description |
|-----------|------|---------|--------|-------------|
| `-SaveCredentials` | switch | false | - | Save/update credentials only |
| `-SaveTOTP` | switch | false | - | Save/update TOTP secret only |
| `-Reconfigure` | switch | false | - | Clear config, full re-setup |

### Profile Parameters

| Parameter | Type | Default | Values | Description |
|-----------|------|---------|--------|-------------|
| `-Add` | switch | false | - | Add new profile |
| `-Ls` | switch | false | - | List all profiles |
| `-Use` | string | (none) | profile name | Switch active profile |
| `-Rm` | string | (none) | profile name | Remove profile |
| `-Edit` | string | (none) | profile name | Edit profile |
| `-Set` | string | (none) | server/group/port/protocol/user/duo | Setting key |
| `-SetValue` | string | (none) | (any) | Setting value |

### Config File Schema (config.json)

```json
{
    "Server":   "portal.dukekunshan.edu.cn",
    "Group":    "-Default-",
    "Port":     "443",
    "Protocol": "ssl"
}
```

### DUO Methods

| Method | Input to vpncli | Behavior |
|--------|----------------|----------|
| `push` | `1` | Send push to phone (default) |
| `phone` | `2` | Call phone for verification |
| `sms` | `3` | Send SMS passcode |
| `passcode` | `<6-digit code>` | Auto-generate TOTP (fully automatic) |

## Setup Flow

```
vpn-reconfig (or first run)
  │
  ├─ [1/4] Server address    (e.g. portal.dukekunshan.edu.cn)
  ├─ [2/4] VPN Group         (e.g. -Default-, or blank)
  ├─ [3/4] Port              (default: 443)
  ├─ [4/4] Protocol          (default: ssl)
  │
  ├─ Save config.json
  │
  ├─ Enter username
  ├─ Enter password (SecureString → DPAPI encrypted)
  │
  ├─ Save credentials.xml
  │
  └─ (Optional) Save TOTP secret for full-auto mode
```

## Connect Flow

```
vpn-connect
  │
  ├─ Load config.json + credentials.xml
  │
  ├─ Check if GUI client (csc_ui) is running
  │   └─ Yes → Kill it (blocks CLI)
  │
  ├─ Start vpncli.exe -s
  │
  ├─ [1/6] connect <server>:<port>
  ├─ [2/6] Select group (0 = Default)
  ├─ [3/6] Accept default username (Enter)
  ├─ [4/6] Send password
  ├─ [5/6] Send DUO option (1=push, 2=phone, 3=sms, or TOTP code)
  │         └─ Wait up to 60s for user to Approve
  ├─ [6/6] Accept certificate (y)
  │
  └─ Check VPN IP (10.x.x.x = connected)
```

## Implementation Notes

### DPAPI Encryption
- Uses `System.Security.Cryptography.ProtectedData` (.NET)
- Encryption scope: `CurrentUser` (only this Windows user can decrypt)
- Works in both PowerShell 5.1 and 7+
- Does NOT use `Microsoft.PowerShell.Security` module (PS7 incompatible)

### GUI Client Conflict
- Cisco Secure Client GUI (`csc_ui.exe`) and CLI (`vpncli.exe`) cannot coexist
- Script kills GUI before connecting via CLI
- Script restarts GUI after disconnecting

### VPN Status Detection
- Checks for `10.x.x.x` IP on any active network adapter
- More reliable than `vpncli.exe status` (which has encoding issues)
- DKU VPN typically assigns `10.200.x.x` range

### DUO MFA Input
- DKU DUO shows numbered options: `1-Push to X-3808`
- Script sends `1` for push, `2` for phone, `3` for SMS
- For TOTP passcode: auto-generates 6-digit code from stored secret

### Bat/Cmd File Encoding
- All bat/cmd files MUST use ASCII-only `@REM` comments
- Chinese characters in UTF-8 bat files cause cmd.exe encoding errors
- `#` is NOT a valid batch comment character — use `@REM`
