# Cisco VPN AutoConnect

> **[English](#english)** | **[中文](#中文)**

---

<a id="中文"></a>

Cisco Secure Client 自动连接工具，支持 DUO 2FA、多配置管理、GUI 界面和命令行。
用户配置通过 Windows DPAPI 加密存储。

> 该工具只适用于windows设备， 命令行请在 **PowerShell** 或 **CMD** 内执行， GUI 界面也是基于 powershell 脚本运行的。
> 脚本与 Cisco GUI 客户端 不能同时运行, 连接时会自动关闭已有的 Cisco 进程。

## 功能特性

| 功能 | 说明 |
|---|---|
| 一键连接 | `vpn-connect` 自动完成登录（约 40s+DUO 审批） |
| 快速设置 | `vpn-config set <key> <value>` 单项修改 |
| GUI 界面 | `vpn-gui` / .bat 支持图形化操作 |
| DUO 双因素 | 支持 Push/Phone/SMS/TOTP 四种方式 |
| 多配置管理 | `vpn-config add/use/rm/list` 管理多个 VPN 配置 |
| QR 解码 | 配置TOTP可通过 `qrgui` 解码二维码图片， 全自动连接 |
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
git clone https://github.com/YOUR_USERNAME/cisco-vpn-autoconnect.git
cd cisco-vpn-autoconnect

# 2. 添加 cmd/ 到 PATH（全局可用）
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. 重启终端 / 点击 .bat 脚本启用图形化配置
```

---

### DUO 登录方式

| 方式 | 命令 | 说明 |
|---|---|---|
| **Push**（推荐） | `vpn-connect` | 发送推送通知到手机，点「Approve」通过 |
| **Phone** | `vpn-connect phone` | 打电话验证 |
| **SMS** | `vpn-connect sms` | 发送短信验证码 |
| **Passcode**（全自动） | `vpn-connect passcode` | 自动生成 TOTP 验证码 |

---

## DKU VPN 配置指南

### GUI 配置

```powershell
vpn-gui              # 或双击 vpn-gui.bat
```

1. 点 `[+]` 添加配置，选 **DKU VPN** 预设（Server / Port / Protocol 已自动填好）
2. 填写 NetID 和 Password；Group 默认 `-Default-`
3. 保存后点 **Connect** 开始连接；**Configs** 按钮查看所有配置的凭据和状态

### 命令行配置

```powershell
vpn-config add
```

按提示输入以下信息：

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
vpn-connect      # 连接 VPN (DUO Push)
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

### 连接与断开

```powershell
vpn-connect      # 连接（自动关闭 Cisco GUI，连上后 vpncli 可能自行退出，正常）
vpn-status       # 查看 Cisco 隧道网卡 / 10.x.x.x VPN IP
vpn-disconnect   # 断开 VPN，并重新启动 Cisco 系统托盘 GUI
```

**进程说明：**

- 连接前若检测到 **Cisco GUI**（`csc_ui`）或其它 **vpncli** 占用，脚本会结束这些进程
- 连接成功后， 新开窗口用 `vpn-disconnect` 即可断开

### 常见问题

| 现象 | 处理 |
|------|------|
| 密码后 `登录失败` | 密码过期或错误：`vpn-config set user <netid>` 重新保存 |
| MFA 处 `答：` 为空后失败 | 重试 `vpn-connect`，DUO push 尽快点 Approve |
| 显示 step 6 报错但已连上 | 运行 `vpn-status` 看 Cisco 隧道网卡 / 10.x IP；vpncli 连上后退出属正常 |
| 提示 Cisco 被占用 | 托盘右键退出 Cisco，或再运行一次 `vpn-connect` |

---

## 可选工具

### GUI 和 QR 工具

VPN 图形界面的首次配置方法见上文「GUI 配置」。

```powershell
vpn-gui          # 启动 VPN 图形界面
qrgui            # 启动 QR 解码 GUI
qrdecode img.png # 命令行解码 QR
```

### TOTP 全自动登录

TOTP（Time-based One-Time Password）是基于时间的 6 位动态验证码，和 Google Authenticator / DUO 应用里显示的码属于同一类协议（RFC 6238，每 30 秒刷新）。本工具用 `vpn-config totp` 把 Base32 密钥保存到本地，DPAPI 加密。

Push / Phone / SMS 都需要你在手机上操作。`vpn-connect passcode` 时，脚本在本地用保存的密钥算出当前 6 位码，MFA 步骤自动发给 `vpncli`，全程不需要碰手机，所以叫「全自动」。

> DKU VPN 的 DUO 二维码通常是 `duo://` 激活链接，标准 QR 工具提取不到 TOTP 密钥。DKU 上推荐用 **Push**（手机点 Approve）。

如果二维码是标准的 `otpauth://totp/...` 格式，或者你已从其他渠道拿到 Base32 密钥，按以下三步操作。

**第 1 步：提取密钥**

```powershell
# GUI：打开/拖入/粘贴二维码截图，复制输出中 Secret: 后的 Base32 字符串
qrgui

# 或命令行：
qrdecode duo-qr.png
```

**第 2 步：保存密钥**

```powershell
vpn-config totp
# 粘贴 Base32 密钥（仅 A-Z、2-7，不要粘贴 duo:// 链接）
# vpn-config 可查看 TOTP 是否已保存
```

**第 3 步：全自动连接**

```powershell
vpn-connect passcode
```

---

## 多 VPN 配置示例

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

---

## 文件结构

```
cisco-vpn-autoconnect/
├── vpn-auto-connect.ps1      # 核心脚本 (PowerShell)
├── vpn-gui.bat               # GUI 启动入口
├── README.md                 # 本文档
├── LICENSE                   # MIT License
├── .gitignore
│
├── assets/
│   └── vpn-auto-connect.ico  # GUI / taskbar icon
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
    ├── qrgui.bat             # GUI 入口
    └── vpn-gui.py            # VPN GUI 管理器
```

---

## 安全说明

- **凭据加密**: 使用 Windows DPAPI (`CurrentUser` scope)，仅当前 Windows 用户可解密
- **配置目录权限**: 自动设置为仅当前用户可访问
- **不要提交凭据**: `.gitignore` 已排除配置目录

---

## License

[MIT](LICENSE)

---

<a id="english"></a>

## English

Cisco Secure Client auto-connect tool with DUO 2FA, multi-profile management, a GUI, and QR decoding for TOTP full-auto setup.
Handles MFA timing and retry for Windows `vpncli`; user configuration encrypted with DPAPI.

> Run commands below in **PowerShell** or **CMD**. Windows only.
> This script and the Cisco GUI client cannot run at the same time. The script closes conflicting Cisco processes when connecting.

## Features

| Feature | Description |
|---|---|
| One-click connect | `vpn-connect` completes login (~25s + DUO approval) |
| DUO 2FA | Push / Phone / SMS / TOTP |
| Multi-profile | `vpn-config add/use/rm/list` manage multiple VPNs |
| Quick settings | `vpn-config set <key> <value>` change one setting |
| GUI | `vpn-gui` graphical manager |
| QR decode | `qrgui` decode QR images |
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
git clone https://github.com/YOUR_USERNAME/cisco-vpn-autoconnect.git
cd cisco-vpn-autoconnect

# 2. Add cmd/ to PATH (global access)
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. Restart terminal
```

### Optional dependencies

**QR tools** (`qrgui` / `qrdecode`, for TOTP QR decoding)

```bash
pip install pyzbar Pillow
```

---

### DUO login methods

| Method | Command | Description |
|---|---|---|
| **Push** (recommended) | `vpn-connect` | Push to phone; tap Approve |
| **Phone** | `vpn-connect phone` | Phone call verification |
| **SMS** | `vpn-connect sms` | SMS passcode |
| **Passcode** (full auto) | `vpn-connect passcode` | Auto-generate TOTP code |

---

## Duke Kunshan VPN setup

### First-time setup

```powershell
vpn-config add
```

Enter when prompted:

```
Name:     dku
Server:   portal.dukekunshan.edu.cn
Group:    -Default-           (or leave blank)
Port:     443                 (Enter for default)
Protocol: ssl                 (Enter for default)
```

Then enter your DKU credentials:

```
Username: your-netid
Password: ********
```

---

## Command reference

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

### Connect and disconnect

```powershell
vpn-connect      # Connect (closes Cisco GUI if needed; vpncli may exit after success — normal)
vpn-status       # Check Cisco tunnel adapter / 10.x.x.x VPN IP
vpn-disconnect   # Disconnect and restart Cisco system-tray GUI
```

**Process notes:**

- Before connect, if **Cisco GUI** (`csc_ui`) or another **vpncli** is blocking, the script ends those processes
- After a successful connect, use `vpn-disconnect` in a new window to disconnect

### Troubleshooting

| Symptom | Action |
|------|------|
| `登录失败` after password | Wrong or expired password: `vpn-config set user <netid>` |
| Empty MFA (`答：`) then failure | Retry `vpn-connect`; approve DUO push promptly |
| Step 6 error but VPN works | Run `vpn-status` for Cisco tunnel adapter / 10.x IP; vpncli exit after connect is normal |
| Cisco "another app in use" | Quit Cisco from system tray, or run `vpn-connect` again |

---

## Optional tools

### GUI and QR tools

```powershell
vpn-gui          # Launch VPN GUI
qrgui            # Launch QR decoder GUI
qrdecode img.png # Decode QR from CLI
```

### TOTP full-auto login

> **Note**: DKU VPN's DUO QR code cannot be read by standard tools to extract a TOTP secret, so full-auto TOTP is not available. Use **Push** (tap Approve on your phone).

If the QR is standard `otpauth://totp/...` (or you have a Base32 secret from elsewhere), configure in three steps:

**Step 1: Extract secret with QR tools**

```powershell
# GUI (recommended): open, drag, or paste a QR screenshot
qrgui
# Copy the Base32 string after Secret: in the output

# Or CLI:
qrdecode duo-qr.png
# Use the secret line in the output
```

**Step 2: Save secret to VPN config**

```powershell
vpn-config totp
# Paste the Base32 secret from step 1 (A–Z, 2–7 only; not a duo:// link)
# Run vpn-config to confirm TOTP is saved
```

**Step 3: Full-auto connect**

```powershell
vpn-connect passcode
```

---

## Multi-profile example

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

---

## File structure

```
cisco-vpn-autoconnect/
├── vpn-auto-connect.ps1      # Core script (PowerShell)
├── vpn-gui.bat               # GUI launcher
├── AGENTS.md                 # Agent docs
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
    ├── qrgui.bat             # GUI launcher
    └── vpn-gui.py            # VPN GUI manager
```

---

## Security

- **Credential encryption**: Windows DPAPI (`CurrentUser` scope); only the current Windows user can decrypt
- **Config directory permissions**: Restricted to the current user
- **Do not commit credentials**: `.gitignore` excludes the config directory

---

## License

[MIT](LICENSE)
