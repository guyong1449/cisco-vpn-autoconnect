# VPN Auto-Connect

> **[中文](#中文)** | **[English](#english)**

---

<a id="中文"></a>

Cisco Secure Client 自动连接工具，支持 DUO 双因素认证、多配置管理、GUI 界面和二维码解码。

> 下文命令请在 **PowerShell** 或 **CMD** 中执行，目前仅在windows设备测试通过。
> 本脚本与 Cisco GUI 客户端 不能同时运行。连接时脚本会自动关闭占用的 Cisco 进程。

## 功能特性

| 功能 | 说明 |
|---|---|
| 一键连接 | `vpn-connect` 自动完成 6 步登录（定时 stdin，约 25s+DUO 审批） |
| DUO 双因素 | 支持 Push/Phone/SMS/TOTP 四种方式 |
| 多配置管理 | `vpn-config add/use/rm/list` 管理多个 VPN |
| 快速设置 | `vpn-config set <key> <value>` 单项修改 |
| GUI 界面 | `vpn-gui` 图形化管理 |
| QR 解码 | `qrgui` 解码二维码图片 |
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
git clone https://github.com/YOUR_USERNAME/vpn-auto-connect.git
cd vpn-auto-connect

# 2. 添加 cmd/ 到 PATH（全局可用）
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. 重启终端
```

### 可选依赖

**QR 工具**（`qrgui` / `qrdecode`，用于 TOTP 二维码解码）

```bash
pip install pyzbar Pillow
```

**Python VPN 脚本**（`vpn_auto_connect.py` 备选方案）

```bash
pip install wexpect
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

## Duke Kunshan VPN 配置指南

### 首次配置

```powershell
vpn-config add
```

按提示输入以下信息：

```
Name:     dku
Server:   portal.dukekunshan.edu.cn
Group:    -Default-           (或留空)
Port:     443                 (直接回车)
Protocol: ssl                 (直接回车)
```

然后输入 DKU 账号密码：

```
Username: your-netid
Password: ********
```
---

## 命令速查表

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
vpn-status       # 查看是否有 10.x.x.x VPN IP
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
| 显示 step 6 报错但已连上 | 运行 `vpn-status` 看 10.x IP；vpncli 连上后退出属正常 |
| 提示 Cisco 被占用 | 托盘右键退出 Cisco，或再运行一次 `vpn-connect` |

---

## 可选工具

### GUI 和 QR 工具

```powershell
vpn-gui          # 启动 VPN 图形界面
qrgui            # 启动 QR 解码 GUI
qrdecode img.png # 命令行解码 QR
```

### TOTP 全自动登录

> **注意**: DKU VPN 的 DUO 二维码无法被标准工具识别提取 TOTP 密钥，因此 TOTP 全自动模式暂不可用。推荐使用 **Push** 方式（手机点 Approve）。

若二维码为标准的 `otpauth://totp/...` 格式（或已从其他渠道获得 Base32 密钥），可按以下三步配置：

**步骤 1：用 QR 工具提取密钥**

```powershell
# GUI（推荐）：打开/拖入/粘贴二维码截图
qrgui
# 在输出区找到 Secret: 后的 Base32 字符串并复制

# 或命令行：
qrdecode duo-qr.png
# 输出中的「密钥:」行即为 TOTP 密钥
```

**步骤 2：保存密钥到 VPN 配置**

```powershell
vpn-config totp
# 粘贴步骤 1 复制的 Base32 密钥（仅 A-Z、2-7，不要粘贴 duo:// 链接）
# 可用 vpn-config 查看 TOTP Secret 是否已保存
```

**步骤 3：全自动连接**

```powershell
vpn-connect passcode
```

---

## 多 Profile 示例

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
vpn-auto-connect/
├── vpn-auto-connect.ps1      # 核心脚本 (PowerShell)
├── vpn_auto_connect.py       # 备选脚本 (Python + wexpect)
├── vpn-gui.bat               # GUI 启动入口
├── AGENTS.md                 # Agent 文档
├── README.md                 # 本文档
├── LICENSE                   # MIT License
├── .gitignore
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

tests/
└── Test-VpnFunctions.ps1     # 单元测试（54 项）
```

### 配置目录

```
~/.vpn-auto-connect/          # 自动生成
├── config.json               # 服务器配置（旧版）
├── credentials.xml           # 加密凭据（旧版）
├── totp.xml                  # 加密 TOTP 密钥
├── profiles.json             # Profile 索引
├── active_profile            # 当前活跃 Profile 名称
└── profiles/                 # 多配置目录
    ├── dku/
    │   ├── config.json
    │   ├── credentials.xml
    │   └── totp.xml
    └── company/
        ├── config.json
        └── credentials.xml
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

Cisco Secure Client auto-connect tool with DUO 2FA, multi-profile management, GUI, and QR decoder.

> **Note**: This script and the Cisco client GUI cannot run at the same time. The script will automatically kill conflicting Cisco processes (does not affect `vpnagent` background service).

### Features

| Feature | Description |
|---|---|
| One-click connect | `vpn-connect` auto 6-step login (timed stdin, ~25s + DUO approval) |
| One-click disconnect | `vpn-disconnect` disconnects and restarts Cisco GUI |
| DUO 2FA | Push/Phone/SMS/TOTP supported |
| Multi-profile | `vpn-config add/use/rm/list` manage multiple VPNs |
| Quick settings | `vpn-config set <key> <value>` change individual settings |
| GUI manager | `vpn-gui` visual manager |
| QR decoder | `qrgui` decode QR code images |
| Secure storage | Windows DPAPI encrypted credentials |

---

### Installation

**Prerequisites**

- Windows 10/11
- [Cisco Secure Client](https://www.cisco.com/) installed (with `vpncli.exe`)
- PowerShell 5.1+ (built-in)
- Python 3.10+ (only for QR tools and GUI)

**Setup**

```powershell
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/vpn-auto-connect.git
cd vpn-auto-connect

# 2. Add cmd/ to PATH (global access)
[Environment]::SetEnvironmentVariable(
    "PATH",
    $env:PATH + ";$(Get-Location)\cmd",
    "User"
)

# 3. Install QR dependencies (optional)
pip install pyzbar Pillow

# 4. Restart terminal
```

---

### Duke Kunshan VPN Setup

**First-time setup**

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

Then enter your DKU credentials.

**DUO Login Methods**

| Method | Command | Description |
|---|---|---|
| **Push** (recommended) | `vpn-connect` | Push to phone, tap Approve |
| **Phone** | `vpn-connect phone` | Call your phone |
| **SMS** | `vpn-connect sms` | Send SMS code |
| **Passcode** (full auto) | `vpn-connect passcode` | Auto-generate TOTP code |

---

### Command Reference

**Basic commands**

```powershell
vpn              # List all commands
vpn-connect      # Connect (DUO Push)
vpn-disconnect   # Disconnect
vpn-status       # Show connection status
```

**Configuration (vpn-config)**

```powershell
vpn-config                   # Show all settings
vpn-config list              # Compact profile list
vpn-config add               # Add new profile
vpn-config use dku           # Switch to dku profile
vpn-config set <key> <value> # Quick setting change
vpn-config totp              # Save TOTP secret
vpn-config rm <name>         # Remove a profile
vpn-config reset-all         # Full reset and re-setup
```

**Quick settings**

```powershell
vpn-config set server portal.dukekunshan.edu.cn
vpn-config set group "-Default-"
vpn-config set port 8443
vpn-config set protocol ipsec
vpn-config set user newuser         # Prompts for password
vpn-config set duo passcode         # Default DUO method
```

**Connect / Disconnect**

```powershell
vpn-connect      # Connect (kills Cisco GUI if needed; vpncli may exit after success — normal)
vpn-status       # Check for 10.x.x.x VPN IP
vpn-disconnect   # Disconnect and restart Cisco system-tray GUI
```

**Process behavior:**

- Before connect, kills **Cisco GUI** (`csc_ui`) or other **vpncli** instances if they block CLI (**never** kills `vpnagent`)
- Skips the kill loop when no blockers are present (faster)
- A `VPN>` prompt in the log after connect is expected — do not type there; use `vpn-disconnect` to disconnect

**Troubleshooting**

| Symptom | Fix |
|---------|-----|
| `登录失败` after password | Wrong/expired password: `vpn-config set user <netid>` |
| Empty MFA answer (`答：`) then fail | Retry `vpn-connect`; approve DUO push promptly |
| Step 6 error but VPN works | Run `vpn-status` for 10.x IP; vpncli exit after auth is normal |
| Cisco "another app in use" | Quit Cisco from system tray, or run `vpn-connect` again |

**GUI and QR Tools**

```powershell
vpn-gui          # Launch VPN GUI
qrgui            # Launch QR decoder GUI
qrdecode img.png # CLI QR decode
```

**TOTP Full-Auto Login**

> **Note**: DKU VPN's DUO QR code cannot be recognized by standard tools to extract the TOTP secret. TOTP full-auto mode is not available. Use **Push** (tap Approve on phone) instead.

If you obtained the TOTP secret from another source:

```powershell
# 1. Save TOTP secret
vpn-config totp

# 2. Full-auto connect
vpn-connect passcode
```

**Disconnect**

```powershell
vpn-disconnect
```

---

### Multi-Profile Examples

```powershell
# Add DKU VPN
vpn-config add
# Name: dku
# Server: portal.dukekunshan.edu.cn
# Group: -Default-
# Port: 443
# Protocol: ssl

# Add company VPN
vpn-config add
# Name: company
# Server: vpn.company.com
# Group: (blank)
# Port: 443
# Protocol: ssl

# List all profiles
vpn-config list
#   * dku       portal.dukekunshan.edu.cn:443
#     company   vpn.company.com:443

# Switch to company VPN
vpn-config use company

# Connect
vpn-connect
```

---

### File Structure

```
vpn-auto-connect/
├── vpn-auto-connect.ps1      # Core script (PowerShell)
├── vpn_auto_connect.py       # Alternative (Python + wexpect)
├── vpn-gui.bat               # GUI launcher
├── AGENTS.md                 # Agent documentation
├── README.md                 # This file
├── LICENSE                   # MIT License
├── .gitignore
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

tests/
└── Test-VpnFunctions.ps1     # Unit tests (54 cases)
```

**Config Directory**

```
~/.vpn-auto-connect/          # Auto-created
├── config.json               # Server config (legacy)
├── credentials.xml           # Encrypted credentials (legacy)
├── totp.xml                  # Encrypted TOTP secret
├── profiles.json             # Profile index
├── active_profile            # Active profile name
└── profiles/                 # Multi-profile directory
    ├── dku/
    │   ├── config.json
    │   ├── credentials.xml
    │   └── totp.xml
    └── company/
        ├── config.json
        └── credentials.xml
```

---

### Security

- **Credentials encrypted**: Uses Windows DPAPI (CurrentUser scope), only the current Windows user can decrypt
- **Config dir permissions**: Auto-restricted to current user only
- **Never commit credentials**: `.gitignore` excludes the config directory

---

### Dependencies

**Core (no extra dependencies)**

- PowerShell 5.1+ (built-in)
- Cisco Secure Client (with vpncli.exe)

**QR Tools (optional)**

```bash
pip install pyzbar Pillow
```

**Python VPN Script (optional)**

```bash
pip install wexpect
```

---

### License

[MIT](LICENSE)
