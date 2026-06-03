# Cisco VPN AutoConnect

> **[English](#english)** | **[中文](#中文)**

---

<a id="中文"></a>

Cisco Secure Client 自动连接工具，支持 DUO 2FA、多配置管理、GUI 和命令行。
用户配置通过 Windows DPAPI 加密存储。

> 仅适用于 **Windows**，命令行请在 **PowerShell** 或 **CMD** 里执行。
> GUI 是 Python 图形界面，连接、断开和配置仍由 PowerShell 核心脚本完成。
> 连接前若 Cisco GUI（`csc_ui`）或其它 `vpncli` 占用了连接功能，脚本会结束这些进程。

## 功能特性

| 功能 | 说明 |
|---|---|
| 一键连接 | `vpn-connect` 自动完成登录（约 40s + DUO 审批） |
| 快速设置 | `vpn-config set <key> <value>` 单项修改 |
| GUI 界面 | `vpn-gui` 或双击 `vpn-gui.bat` |
| DUO 双因素 | Push / Phone / TOTP（passcode）三种方式 |
| 多配置管理 | `vpn-config add/use/rm/list` 管理多个 VPN 配置 |
| TOTP 全自动 | `vpn-config totp` + `vpn-connect passcode`，MFA 无需手动操作 |
| QR 提取密钥 | `qrgui` / `qrdecode` 从图片提取 TOTP 密钥，供 TOTP 配置使用（需 `otpauth://` 格式） |
| 安全存储 | Windows DPAPI 加密凭据 |

---

## 安装

### 前置条件

- Windows 10/11
- [Cisco Secure Client](https://www.cisco.com/) 已安装（含 `vpncli.exe`）
- PowerShell 5.1+（Windows 自带）
- Python 3.10+（仅 QR 工具和 GUI 需要）

### 安装步骤

```powershell
# 1. 克隆仓库
git clone https://github.com/guyong1449/cisco-vpn-autoconnect.git
cd cisco-vpn-autoconnect

# 2. 添加 cmd/ 到 PATH（全局可用）
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. 重启终端使 PATH 生效，也可直接双击 vpn-gui.bat 启动 GUI（无需 PATH）
```

---

## DUO 登录方式

| 方式 | 命令 | 说明 |
|---|---|---|
| **Push**（推荐） | `vpn-connect` | 推送通知到手机，点「Approve」通过 |
| **Phone** | `vpn-connect phone` | 电话验证 |
| **Passcode**（全自动） | `vpn-connect passcode` | 用本地 TOTP 密钥自动生成 6 位验证码 |

---

## DKU VPN 配置指南

### GUI 配置

```powershell
vpn-gui              # 或双击 vpn-gui.bat
```

1. 点 `[+]` 添加配置，选 **DKU VPN** 预设（Server / Port / Protocol 已填好）
2. 填写 NetID 和 Password，Group 默认 `-Default-`
3. 保存后点 **Connect**，用 **Configs** 查看各配置的凭据和状态

### 命令行配置

```powershell
vpn-config add
```

按提示输入：

```
Name:     dku
Server:   portal.dukekunshan.edu.cn
Group:    -Default-           (直接回车)
Port:     443                 (直接回车)
Protocol: ssl                 (直接回车)
```

然后输入 DKU 账号密码：

```
Username: your-netid
Password: ********
```

---

## 配置与命令速查

| 方式 | 适合 | 入口 |
|------|------|------|
| GUI | 日常连接、改密码、看状态 | `vpn-gui` |
| 命令行 | 脚本、远程、批量改配置 | `vpn-config` / `vpn-connect` |

### 基础命令

```powershell
vpn              # 显示所有命令
vpn-connect      # 连接 VPN（DUO Push）
vpn-disconnect   # 断开 VPN
vpn-status       # 显示连接状态
```

### 配置管理（统一入口 vpn-config）

```powershell
vpn-config                   # 查看所有配置和状态
vpn-config list              # 简洁列出所有 Profile
vpn-config add               # 添加新配置
vpn-config use dku           # 切换到 dku 配置
vpn-config set <key> <value> # 快速修改单项设置
vpn-config totp              # 保存 TOTP 密钥
vpn-config rm <name>         # 删除指定配置
vpn-config reset-all         # 完全重置并重新设置
```

### 快速设置示例

```powershell
vpn-config set server portal.dukekunshan.edu.cn   # 修改服务器
vpn-config set group "-Default-"                   # 修改分组
vpn-config set port 8443                           # 修改端口
vpn-config set protocol ipsec                      # 修改协议
vpn-config set user newuser                        # 修改用户名和密码（会提示输入）
vpn-config set duo passcode                        # 修改默认 DUO 方式
```

### 多 VPN 配置示例

```powershell
# 添加其他 VPN
vpn-config add
# Name: company
# Server: vpn.company.com
# Group: (留空)
# Port: 443
# Protocol: ssl

# 查看所有配置
vpn-config list
#   * dku       portal.dukekunshan.edu.cn:443
#     company   vpn.company.com:443

# 切换到其他 VPN
vpn-config use company

# 连接
vpn-connect
```

**进程说明：**

- 连接前若 **Cisco GUI**（`csc_ui`）、`vpnui` 或其它 **vpncli** 占用连接功能，脚本会结束这些进程
- 连接结束后执行 `vpn-disconnect` 即可断开，断开后会重启 Cisco 托盘 GUI

---

## TOTP 全自动登录

TOTP 是 6 位动态验证码，和 Google Authenticator 里那种一样（RFC 6238，每 30 秒换一组）。`vpn-config totp` 把 Base32 密钥存到本地，DPAPI 加密。

Push 和 Phone 要在手机上操作。`vpn-connect passcode` 则用本地密钥算出当前验证码，MFA 这一步可以全自动发给 `vpncli`。

> DKU VPN 的 DUO 二维码多半是 `duo://` 激活链接，提不出 TOTP 密钥，一般只能用 **DUO Push**。

二维码是标准 `otpauth://totp/...`，或者你已有 Base32 密钥，按下面三步来。

**第 1 步：提取密钥**

```powershell
# 安装 QR 工具依赖（qrgui / qrdecode 共用）
pip install pyzbar Pillow

# 在仓库根目录：把 tools/ 加入 PATH（一次即可，与 cmd/ 同理，改完后重启终端）
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\tools",
    "User"
)

# 方式 A — GUI（推荐）：Ctrl+V 粘贴、拖入图片，或点击选文件
qrgui
# GUI 输出为英文标签 Secret:，复制后面的 Base32（仅 A–Z、2–7）

# 方式 B — CLI：已知图片路径时用命令行
qrdecode screenshot.png

```

**第 2 步：保存密钥**

```powershell
vpn-config totp
# 粘贴 Base32 密钥（仅 A-Z、2-7，不要粘贴 duo:// 链接）
# 运行 vpn-config 可查看 TOTP 是否已保存
```

**第 3 步：全自动连接**

```powershell
vpn-connect passcode
```

---

## 文件结构

```
cisco-vpn-autoconnect/
├── vpn-auto-connect.ps1      # 核心脚本 (PowerShell)
├── vpn-gui.bat               # GUI 启动入口（调用 vpn-gui.vbs）
├── vpn-gui.vbs               # 无窗口启动 GUI
├── README.md                 # 本文档
├── LICENSE                   # MIT License
├── .gitignore
│
├── assets/
│   └── vpn-auto-connect.ico  # GUI / 任务栏图标
│
├── cmd/                      # 命令入口
│   ├── vpn.cmd               # 显示命令列表
│   ├── vpn-connect.cmd       # 连接
│   ├── vpn-disconnect.cmd    # 断开
│   ├── vpn-status.cmd        # 状态
│   ├── vpn-config.cmd        # 配置管理
│   └── vpn-gui.cmd           # 启动 GUI
│
└── tools/                    # 辅助工具
    ├── qrdecode.py           # QR 解码 (CLI)
    ├── qrdecode_gui.py       # QR 解码 (GUI)
    ├── qrdecode.bat          # CLI 入口
    ├── qrgui.bat             # GUI 入口（调用 qrgui.vbs）
    ├── qrgui.vbs             # 无窗口启动 QR GUI
    └── vpn-gui.py            # VPN GUI 管理器
```

---

## 安全说明

- **凭据加密**：使用 Windows DPAPI（`CurrentUser` scope），仅当前 Windows 用户可解密
- **配置目录权限**：自动设置为仅当前用户可访问
- **不要提交凭据**：`.gitignore` 已排除配置目录

---

## License

[MIT](LICENSE)

---

<a id="english"></a>

## English

Cisco Secure Client auto-connect tool with DUO 2FA, multi-profile management, a GUI, and a command line.
User configuration is encrypted with Windows DPAPI.

> **Windows only.** Run commands in **PowerShell** or **CMD**.
> The GUI is a Python app. Connect, disconnect, and config still go through the PowerShell core script.
> Before connecting, if Cisco GUI (`csc_ui`) or another `vpncli` holds the connection lock, the script ends those processes.

## Features

| Feature | Description |
|---|---|
| One-click connect | `vpn-connect` completes login (~40s + DUO approval) |
| Quick settings | `vpn-config set <key> <value>` change one field |
| GUI | `vpn-gui` or double-click `vpn-gui.bat` |
| DUO 2FA | Push, Phone, or TOTP (passcode) |
| Multi-profile | `vpn-config add/use/rm/list` manage multiple VPNs |
| TOTP full-auto | `vpn-config totp` + `vpn-connect passcode`, MFA without manual input |
| QR secret extract | `qrgui` / `qrdecode` extract TOTP secret from images for TOTP setup (`otpauth://` QR only) |
| Secure storage | Windows DPAPI encrypted credentials |

---

## Installation

### Prerequisites

- Windows 10/11
- [Cisco Secure Client](https://www.cisco.com/) installed (with `vpncli.exe`)
- PowerShell 5.1+ (built-in)
- Python 3.10+ (QR tools and GUI only)

### Setup

```powershell
# 1. Clone repository
git clone https://github.com/guyong1449/cisco-vpn-autoconnect.git
cd cisco-vpn-autoconnect

# 2. Add cmd/ to PATH (global access)
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. Restart the terminal for PATH, or double-click vpn-gui.bat (no PATH needed)
```

---

## DUO login methods

| Method | Command | Description |
|---|---|---|
| **Push** (recommended) | `vpn-connect` | Push to phone, tap Approve |
| **Phone** | `vpn-connect phone` | Phone call verification |
| **Passcode** (full auto) | `vpn-connect passcode` | Auto-generate 6-digit TOTP from saved secret |

---

## Duke Kunshan VPN setup

### GUI setup

```powershell
vpn-gui              # or double-click vpn-gui.bat
```

1. Click `[+]` to add a profile, choose **DKU VPN** preset (Server / Port / Protocol prefilled)
2. Enter NetID and Password, Group defaults to `-Default-`
3. Save, click **Connect**, use **Configs** to view credentials and status

### CLI setup

```powershell
vpn-config add
```

Enter when prompted:

```
Name:     dku
Server:   portal.dukekunshan.edu.cn
Group:    -Default-           (press Enter)
Port:     443                 (press Enter)
Protocol: ssl                 (press Enter)
```

Then enter DKU credentials:

```
Username: your-netid
Password: ********
```

---

## Command reference

| Mode | Best for | Entry |
|------|----------|-------|
| GUI | Daily connect, password changes, status | `vpn-gui` |
| CLI | Scripts, remote use, batch config | `vpn-config` / `vpn-connect` |

### Basic commands

```powershell
vpn              # List all commands
vpn-connect      # Connect VPN (DUO Push)
vpn-disconnect   # Disconnect VPN
vpn-status       # Show connection status
```

### Configuration (`vpn-config`)

```powershell
vpn-config                   # Show all settings and status
vpn-config list              # Compact profile list
vpn-config add               # Add new profile
vpn-config use dku           # Switch to dku profile
vpn-config set <key> <value> # Quick setting change
vpn-config totp              # Save TOTP secret
vpn-config rm <name>         # Remove a profile
vpn-config reset-all         # Full reset and re-setup
```

### Quick settings examples

```powershell
vpn-config set server portal.dukekunshan.edu.cn   # Server
vpn-config set group "-Default-"                   # Group
vpn-config set port 8443                           # Port
vpn-config set protocol ipsec                      # Protocol
vpn-config set user newuser                        # Username and password (prompted)
vpn-config set duo passcode                        # Default DUO method
```

### Multi-profile example

```powershell

# Add another VPN
vpn-config add
# Name: company
# Server: vpn.company.com
# Group: (blank)
# Port: 443
# Protocol: ssl

# List profiles
vpn-config list
#   * dku       portal.dukekunshan.edu.cn:443
#     company   vpn.company.com:443

# Switch profile
vpn-config use company

# Connect
vpn-connect
```

**Process notes:**

- Before connect, if **Cisco GUI** (`csc_ui`), `vpnui`, or another **vpncli** blocks the session, the script ends those processes
- After connect, run `vpn-disconnect` to disconnect, the Cisco system-tray GUI restarts when done

---

## TOTP full-auto login

TOTP is a 6-digit code that rotates every 30 seconds, same as Google Authenticator (RFC 6238). `vpn-config totp` saves the Base32 secret locally, DPAPI encrypted.

Push and Phone need action on your phone. `vpn-connect passcode` uses the saved secret to fill MFA automatically via `vpncli`.

> DKU VPN DUO QR codes are usually `duo://` activation links, not TOTP secrets. For DKU, use **DUO Push**.

If the QR is standard `otpauth://totp/...`, or you already have a Base32 secret, follow these three steps.

**Step 1: Extract secret**

```powershell
# QR tool dependencies (shared by qrgui / qrdecode)
pip install pyzbar Pillow

# From repo root, add tools/ to PATH (once, like cmd/, then restart terminal)
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\tools",
    "User"
)

# Option A — GUI (recommended): Ctrl+V paste, drag image, or pick a file
qrgui
# GUI prints English label Secret:, copy the Base32 after it (A–Z, 2–7 only)

# Option B — CLI: when you have the image path
qrdecode screenshot.png

```

**Step 2: Save secret**

```powershell
vpn-config totp
# Paste Base32 secret (A-Z, 2-7 only, not a duo:// link)
# Run vpn-config to confirm TOTP is saved
```

**Step 3: Full-auto connect**

```powershell
vpn-connect passcode
```

---

## File structure

```
cisco-vpn-autoconnect/
├── vpn-auto-connect.ps1      # Core script (PowerShell)
├── vpn-gui.bat               # GUI launcher (calls vpn-gui.vbs)
├── vpn-gui.vbs               # Silent GUI launcher
├── README.md                 # This file
├── LICENSE                   # MIT License
├── .gitignore
│
├── assets/
│   └── vpn-auto-connect.ico  # GUI / taskbar icon
│
├── cmd/                      # Command entry points
│   ├── vpn.cmd               # List commands
│   ├── vpn-connect.cmd       # Connect
│   ├── vpn-disconnect.cmd    # Disconnect
│   ├── vpn-status.cmd        # Status
│   ├── vpn-config.cmd        # Config manager
│   └── vpn-gui.cmd           # Launch GUI
│
└── tools/                    # Auxiliary tools
    ├── qrdecode.py           # QR decoder (CLI)
    ├── qrdecode_gui.py       # QR decoder (GUI)
    ├── qrdecode.bat          # CLI launcher
    ├── qrgui.bat             # GUI launcher (calls qrgui.vbs)
    ├── qrgui.vbs             # Silent QR GUI launcher
    └── vpn-gui.py            # VPN GUI manager
```

---

## Security

- **Credential encryption**: Windows DPAPI (`CurrentUser` scope), only the current Windows user can decrypt
- **Config directory permissions**: Restricted to the current user
- **Do not commit credentials**: `.gitignore` excludes the config directory

---

## License

[MIT](LICENSE)
