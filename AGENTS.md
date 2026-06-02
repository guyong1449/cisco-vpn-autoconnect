# VPN Auto-Connect Agent

Cisco Secure Client auto-connect tool with DUO 2FA support.

## File Structure

```
tools/vpn-auto-connect/        # Project folder
├── AGENTS.md                  # This file
├── vpn-auto-connect.ps1       # Core script (PowerShell 7+)
├── vpn_auto_connect.py        # Alternative (Python + wexpect)
└── cmd/                       # Entry point scripts
    ├── vpn.cmd                # List commands
    ├── vpn-connect.cmd        # Connect
    ├── vpn-disconnect.cmd     # Disconnect
    ├── vpn-status.cmd         # Show status
    ├── vpn-setup.cmd          # First-time setup (legacy)
    ├── vpn-totp.cmd           # Save TOTP secret
    ├── vpn-reconfig.cmd       # Reset and reconfigure
    ├── vpn-help.cmd           # Show help
    ├── vpn-add.cmd            # Add new profile
    ├── vpn-ls.cmd             # List all profiles
    ├── vpn-use.cmd            # Switch active profile
    ├── vpn-rm.cmd             # Remove a profile
    ├── vpn-edit.cmd           # Edit profile settings
    └── vpn-set.cmd            # Quick setting change

Config: ~/.vpn-auto-connect/
├── config.json                # Server, Group, Port, Protocol (legacy)
├── credentials.xml            # DPAPI encrypted username/password (legacy)
├── totp.xml                   # DPAPI encrypted TOTP secret
├── profiles.json              # Index of all profiles
├── active_profile             # Current active profile name
└── profiles/                  # Multi-profile storage
    ├── dku/
    │   ├── config.json
    │   ├── credentials.xml
    │   └── totp.xml
    └── company/
        ├── config.json
        ├── credentials.xml
        └── totp.xml
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

### PowerShell Short Aliases (profile)

| Alias | Target |
|-------|--------|
| `vpnc` | vpn-connect |
| `vpnd` | vpn-disconnect |
| `vpns` | vpn-status |
| `vpn-rcfg` | vpn-reconfig |

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

### Utility Parameters

| Parameter | Type | Default | Values | Description |
|-----------|------|---------|--------|-------------|
| `-Help` | switch | false | - | Show help text |
| `-List` | switch | false | - | Show command list |

### Config File Schema (config.json)

```json
{
    "Server":   "portal.dukekunshan.edu.cn",
    "Group":    "",
    "Port":     "443",
    "Protocol": "ssl"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| Server | string | (required) | VPN gateway FQDN or IP |
| Group | string | "" | VPN group name (empty = skip) |
| Port | string | "443" | VPN server port |
| Protocol | string | "ssl" | ssl, ipsec, any |

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

## TODO / Planned Features

### 1. Multi-Profile Support (Priority: High) ✅ IMPLEMENTED

**Goal:** After setup is complete, allow adding new server profiles without overwriting existing ones.

**Design:**
```
~/.vpn-auto-connect/
├── profiles/
│   ├── dku/
│   │   ├── config.json
│   │   ├── credentials.xml
│   │   └── totp.xml
│   ├── company/
│   │   ├── config.json
│   │   ├── credentials.xml
│   │   └── totp.xml
│   └── home-lab/
│       ├── config.json
│       ├── credentials.xml
│       └── totp.xml
├── active_profile           # contains current profile name
└── profiles.json            # index of all profiles
```

**Rules:**
- `vpn-reconfig` clears ALL profiles, starts fresh
- `vpn-setup` after initial setup adds NEW profile (does not overwrite)
- New profile requires ALL 4 fields (Server, Group, Port, Protocol) to be set
- If setup is incomplete (missing fields), do NOT create profile
- `vpn-use <profile>` switches active profile
- `vpn-ls` lists all profiles

**Commands:**
```powershell
vpn-add              # Add new profile (prompts for all fields)
vpn-use <name>       # Switch active profile
vpn-ls               # List all profiles
vpn-rm <name>        # Remove a profile
vpn-edit <name>      # Edit existing profile settings
```

**Validation before saving:**
```powershell
function Test-ProfileComplete {
    param($Config)
    return (
        $Config.Server -and
        $Config.Port -and
        $Config.Protocol -and
        $Config.Username   # credentials must exist
    )
}
# Only save profile if ALL fields are present
```

### 2. One-Click Settings Change (Priority: Medium) ✅ IMPLEMENTED

**Goal:** Quick toggle/change individual settings without full re-setup.

**Commands:**
```powershell
vpn-set server <value>      # Change server
vpn-set group <value>       # Change group
vpn-set port <value>        # Change port
vpn-set protocol <value>    # Change protocol
vpn-set user <value>        # Change username (re-prompts password)
vpn-set duo <method>        # Change default DUO method
```

**Implementation:**
```powershell
# vpn-set is a wrapper that modifies config.json in-place
function vpn-set {
    param([string]$Key, [string]$Value)
    $config = Load-Config
    switch ($Key) {
        "server"   { $config.Server = $Value }
        "group"    { $config.Group = $Value }
        "port"     { $config.Port = $Value }
        "protocol" { $config.Protocol = $Value }
        "duo"      { $config.DuoMethod = $Value }
        "user"     {
            # Username change requires re-entering password
            Save-VpnCredentials
            return
        }
    }
    $config | ConvertTo-Json | Set-Content $ConfigFile
    Write-Host "[OK] $Key updated to: $Value"
}
```

### 3. Connection History & Auto-Reconnect (Priority: Low)

**Goal:** Log connections and auto-reconnect on disconnect.

```powershell
vpn-history              # Show connection log
vpn-monitor              # Watch connection, auto-reconnect if dropped
```

### 4. GUI Tray Application (Priority: Low)

**Goal:** System tray icon with connect/disconnect/status.

- PowerShell-based tray app using Windows Forms
- Shows connected/disconnected icon
- Right-click menu: Connect, Disconnect, Status, Settings
- Auto-start with Windows (optional)

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
