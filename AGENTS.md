# VPN Auto-Connect Agent

Cisco Secure Client auto-connect tool with DUO 2FA support.

## Current Status

- **CLI Connect (vpn-connect)**: Verified on DKU VPN — timed stdin flow, DUO push, banner/cert, IP detection
- **Multi-Profile Support**: Implemented (vpn-config add/use/rm/set)
- **Unified Config View**: `vpn-config` shows all profiles; `vpn-config list` for compact list
- **One-Click Settings**: `vpn-config set` (server/group/port/protocol/user/duo)
- **Disconnect**: `vpn-disconnect` — vpncli disconnect + restart Cisco GUI
- **GUI Manager**: Implemented (vpn-gui.py) with DKU VPN preset, password toggle, right-click copy
- **Config Viewer**: `vpn-config` — all profiles, credentials status, TOTP status
- **QR Tools**: Integrated (qrdecode.py + qrdecode_gui.py)
- **Unit Tests**: `tests/Test-VpnFunctions.ps1` (54 tests)
- **Window Suppression**: BAT/CMD launchers use .vbs wrappers to avoid CMD window flash
- **Legacy Migration**: Auto-migrates root config files to `profiles/default` on first run
- **DUO Method Resolution**: explicit param > config.DuoMethod > default `push`

## Current Goal

**Maintain CLI connect reliability.** Key areas:

1. **CLI connect/disconnect**: `vpn-connect` / `vpn-disconnect` / `vpn-status` on DKU profile
2. **GUI Connect**: Verify GUI connect button log output and authentication
3. **Profile Management**: add/switch/delete; display name mapping (dku ↔ DKU VPN)
4. **vpn-config**: All settings display correctly

## Recent Changes

- **Timed connect (`Invoke-VpnConnectTimed`)**: Fixed delays + DUO retry; no mid-connect stdout read (blocks on Windows)
- **MFA timing**: Wait ~8s after password before DUO `1`; retry `1` at +10s if needed; banner `y` at +20s (not during MFA)
- **Early success exit**: Stop when `10.x.x.x` IP detected — skip step 6 sleep
- **Blocker skip**: `Stop-CiscoClientBlockers` returns immediately when no `csc_ui`/`vpnui`/`vpncli` (saves ~3–7s)
- **Post-DUO exit**: vpncli often exits with code -1 after connect — treat as success if VPN IP is up
- **CLI merge**: Config/profile commands under `vpn-config <subcommand>`; old commands are deprecation redirects
- **Legacy migration**, **TOTP per-profile**, **DuoMethod resolution**, **vpn-connect passcode param fix**
- **GUI**: DKU preset, password toggle, group free text, right-click copy, profile display mapping

## File Structure

```
tools/vpn-auto-connect/
├── AGENTS.md                  # This file
├── README.md                  # Bilingual documentation
├── LICENSE                    # MIT License
├── .gitignore
├── vpn-auto-connect.ps1       # Core script (PowerShell)
├── vpn_auto_connect.py        # Alternative (Python + wexpect)
├── vpn-gui.bat                # GUI launcher (calls vpn-gui.vbs)
├── vpn-gui.vbs                # VBS silent launcher for GUI
│
├── cmd/                       # Entry point scripts (ASCII-only @REM comments)
│   ├── vpn.cmd                # List commands
│   ├── vpn-connect.cmd        # Connect
│   ├── vpn-disconnect.cmd     # Disconnect
│   ├── vpn-status.cmd         # Show status
│   ├── vpn-config.cmd         # Config manager (list/add/use/set/totp/rm/reset-all)
│   ├── vpn-gui.cmd            # Launch GUI (calls vpn-gui.vbs)
│   ├── vpn-setup.cmd          # (deprecated) -> vpn-config add
│   ├── vpn-totp.cmd           # (deprecated) -> vpn-config totp
│   ├── vpn-reconfig.cmd       # (deprecated) -> vpn-config reset-all
│   ├── vpn-help.cmd           # (deprecated) -> vpn -Help
│   ├── vpn-add.cmd            # (deprecated) -> vpn-config add
│   ├── vpn-ls.cmd             # (deprecated) -> vpn-config list
│   ├── vpn-use.cmd            # (deprecated) -> vpn-config use
│   ├── vpn-rm.cmd             # (deprecated) -> vpn-config rm
│   ├── vpn-edit.cmd           # (deprecated) -> vpn-config set
│   └── vpn-set.cmd            # (deprecated) -> vpn-config set
│
└── tools/                     # Auxiliary tools
    ├── qrdecode.py            # QR decoder (CLI)
    ├── qrdecode_gui.py        # QR decoder (GUI)
    ├── qrdecode.bat           # CLI launcher
    ├── qrgui.bat              # GUI launcher (calls qrgui.vbs)
    ├── qrgui.vbs              # VBS silent launcher for QR GUI
    └── vpn-gui.py             # VPN GUI manager
│
└── tests/                     # Unit tests
    └── Test-VpnFunctions.ps1    # 54 tests (run: powershell -File tests/Test-VpnFunctions.ps1)
```

## Main Interfaces

### PowerShell Commands

| Command | Parameters | Description |
|---------|-----------|-------------|
| `vpn` | (none) | List all available commands |
| `vpn-connect` | `[push\|phone\|sms\|passcode]` | Connect to VPN (DUO method as positional arg) |
| `vpn-disconnect` | (none) | Disconnect VPN |
| `vpn-status` | (none) | Show connection status (checks 10.x.x.x IP) |
| `vpn-gui` | (none) | Launch GUI manager |

### Config Commands (unified via vpn-config)

| Command | Parameters | Description |
|---------|-----------|-------------|
| `vpn-config` | (none) | Show all settings |
| `vpn-config list` | (none) | Compact profile list |
| `vpn-config add` | (none) | Add new VPN profile |
| `vpn-config use` | `<name>` | Switch active profile |
| `vpn-config set` | `<key> <value>` | Quick setting change (server/group/port/protocol/user/duo) |
| `vpn-config totp` | (none) | Save TOTP secret for full-auto mode |
| `vpn-config rm` | `<name>` | Remove a profile |
| `vpn-config reset-all` | (none) | Full reset (all profiles + legacy + TOTP) and re-setup |

### Deprecated (still work, redirect with deprecation notice)

| Command | Redirects to |
|---------|-------------|
| `vpn-setup` | `vpn-config add` |
| `vpn-add` | `vpn-config add` |
| `vpn-use` | `vpn-config use` |
| `vpn-rm` | `vpn-config rm` |
| `vpn-edit` | `vpn-config set` |
| `vpn-set` | `vpn-config set` |
| `vpn-totp` | `vpn-config totp` |
| `vpn-reconfig` | `vpn-config reset-all` |
| `vpn-ls` | `vpn-config list` |
| `vpn-help` | `vpn -Help` |

### GUI Features

- **DKU VPN preset**: Server/Port/Protocol pre-filled, only NetID + Password + Group needed
- **Custom / Other preset**: Full form - Name, Username, Password, Server, Port, Protocol, Group
- **Password toggle**: [Show]/[Hide] button on password fields
- **Group field**: Free text input with placeholder `-Default-`
- **Configs button**: View all profiles with credentials and settings
- **Right-click menu**: Copy / Copy All / Select All on Log and Configs text areas
- **Profile display**: Internal name `dku` shown as "DKU VPN" in dropdown

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
| `-SaveTOTP` | switch | false | - | Save/update TOTP secret only |
| `-Reconfigure` | switch | false | - | Full reset (all profiles + legacy + TOTP), re-setup |
| `-Reset` | switch | false | - | Full reset only (no re-setup) |
| `-Config` | switch | false | - | Show all settings |
| `-Brief` | switch | false | - | Compact profile list (used with -Config) |

### Profile Parameters

| Parameter | Type | Default | Values | Description |
|-----------|------|---------|--------|-------------|
| `-Add` | switch | false | - | Add new profile |
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

| Method | CLI Usage | Input to vpncli | Behavior |
|--------|-----------|----------------|----------|
| `push` | `vpn-connect` | `1` | Send push to phone (default) |
| `phone` | `vpn-connect phone` | `2` | Call phone for verification |
| `sms` | `vpn-connect sms` | `3` | Send SMS passcode |
| `passcode` | `vpn-connect passcode` | `<6-digit code>` | Auto-generate TOTP (fully automatic) |

**Note**: Default DUO method can be saved via `vpn-config set duo push|phone|sms|passcode`.

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
vpn-connect [duo-method]
  │
  ├─ Load active profile config + credentials (fallback to legacy)
  ├─ Resolve DUO method: explicit param > config.DuoMethod > default "push"
  ├─ Stop-CiscoClientBlockers (only if csc_ui / vpnui / vpncli present; never kills vpnagent)
  ├─ Start vpncli.exe -s (stdin redirected; stdout read only at end)
  │
  ├─ [1/6] connect <server>[:port]     (wait 5s)
  ├─ [2/6] group index (0 = -Default-) (wait 2s)
  ├─ [3/6] username                    (wait 2s)
  ├─ [4/6] password                    (wait 6s)
  ├─ [5/6] wait for MFA prompt (8s) → send 1/2/3 or TOTP
  │         ├─ Poll 10.x IP up to 90s; retry DUO input once at +10s if needed
  │         ├─ Send banner/cert `y` at +20s (after MFA, not before)
  │         └─ Push: user taps Approve on phone
  ├─ If 10.x IP detected → success (skip step 6)
  ├─ [6/6] send `y` if vpncli still running
  └─ Read stdout buffer; confirm 10.x.x.x = connected
```

**Windows vpncli I/O**: Do **not** read stdout while vpncli waits at interactive prompts (group/username/password/MFA) — `ReadLine()` blocks. Use **timed stdin writes**; collect output in `Read-VpnCliOutputFinal` after steps complete.

**Debug**: `$env:VPN_DEBUG=1` — vpncli log prints at end of connect (not live during steps).

## Disconnect Flow

```
vpn-disconnect
  ├─ Invoke-VpnCliDisconnectQuiet (spawn vpncli -s → disconnect → exit)
  ├─ taskkill vpncli.exe (cleanup stray CLI)
  └─ Restart csc_ui.exe (GUI killed during connect)
```

## Implementation Notes

### DPAPI Encryption
- Uses `System.Security.Cryptography.ProtectedData` (.NET)
- Encryption scope: `CurrentUser` (only this Windows user can decrypt)
- Works in both PowerShell 5.1 and 7+
- Does NOT use `Microsoft.PowerShell.Security` module (PS7 incompatible)

### GUI Client Conflict
- Cisco Secure Client GUI (`csc_ui.exe`) and CLI (`vpncli.exe`) cannot coexist for connect
- Error text: *连接功能不可用。另一个 Cisco Secure Client 应用程序已在使用功能*
- `Stop-CiscoClientBlockers` kills only `csc_ui`, `vpnui`, `vpncli` (never `vpnagent`)
- If no blockers detected, skip kill loop entirely (fast path)
- `vpn-disconnect` restarts `csc_ui.exe` after disconnect

### VPN Status Detection
- Checks for `10.x.x.x` IP on any active network adapter
- More reliable than `vpncli.exe status` (encoding issues)
- DKU VPN typically assigns `10.200.x.x` range

### DUO MFA Input (Timed Mode)
- DKU DUO prompt: `1-Push to X-3808` — script sends `1` / `2` / `3` or TOTP passcode
- **Do not send DUO too early** — empty `答：` + `登录失败` means MFA input missed
- Flow: password → wait 8s → send DUO → optional retry at +10s → banner `y` at +20s
- Push: approve on phone during 90s IP poll loop
- TOTP: `Get-TOTPCode` from active profile `totp.xml`, then global fallback

### Connect Implementation (PowerShell)
- Primary path: `Invoke-VpnConnectTimed` + `Complete-VpnConnectTimed`
- `Get-VpnGroupSelection`: `-Default-` → `0`, `Library Resources Only` → `1`
- `Send-VpnCliLineIfAlive`: non-throwing stdin for cert/banner when process may have exited
- On success with live vpncli: `Stop-VpnCliSession` sends `exit`; on failure: `Kill()`
- `Wait-ForVpnPrompt` / `Wait-VpnStepOrDelay` exist for tests only — not used in connect (stdout blocks)

### Troubleshooting CLI Connect

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `登录失败` right after Password | Wrong saved password | `vpn-config set user <netid>` (re-enter password) |
| `答：` empty + `登录失败` | DUO `1` sent before MFA prompt | Fixed by MFA wait + retry; retry `vpn-connect`, approve push quickly |
| Error at step 6, but VPN works | vpncli exited after auth (normal) | Use `vpn-status`; script now treats 10.x IP as success |
| Connect blocked at start | GUI still running | Quit Cisco tray app or let script kill blockers |
| Slow connect | Fixed delays + DUO approval + tunnel setup | Approve push promptly; unavoidable network time |

### Bat/Cmd File Encoding
- All bat/cmd files MUST use ASCII-only `@REM` comments
- Chinese characters in UTF-8 bat files cause cmd.exe encoding errors
- `#` is NOT a valid batch comment character — use `@REM`

### Window Suppression
- GUI subprocess calls use `subprocess.STARTUPINFO` with `SW_HIDE` to hide console windows
- BAT/CMD GUI launchers delegate to `.vbs` files (WshShell.Run with window style 0)
- CLI commands (vpn-connect etc.) run in user's terminal - no suppression needed

### Legacy Migration
- On first run, if root `config.json`/`credentials.xml` exist but no profiles, auto-migrates to `profiles/default`
- Preserves all data (config, credentials, TOTP) during migration
- `vpn-reconfig` now does full reset: clears legacy + all profiles + TOTP

### DUO Method Resolution
- Priority: explicit `-DuoMethod` param > `config.DuoMethod` (saved via `vpn-config set duo`) > default "push"
- `vpn-connect passcode` correctly binds to `-DuoMethod` (not positional `$VpnServer`)

### Profile Name Mapping
- Internal storage name: `dku` (used in file paths and active_profile)
- GUI display name: `DKU VPN` (shown in dropdown and Configs dialog)
- `_display_name()` / `_internal_name()` handle the mapping
