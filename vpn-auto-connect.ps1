# ============================================================
# Cisco Secure Client Auto-Connect Script (with DUO 2FA)
# ============================================================
# Usage:
#   .\vpn-auto-connect.ps1                          # First run: setup credentials
#   .\vpn-auto-connect.ps1 -Connect                 # Auto-connect (DUO push to phone)
#   .\vpn-auto-connect.ps1 -Connect -DuoMethod passcode  # Full auto (TOTP code)
#   .\vpn-auto-connect.ps1 -Disconnect              # Disconnect VPN
#   .\vpn-auto-connect.ps1 -SaveCredentials         # Re-save credentials
#   .\vpn-auto-connect.ps1 -SaveTOTP                # Save TOTP secret (for full auto)
#   .\vpn-auto-connect.ps1 -Status                  # Show connection status
# ============================================================

# ============================================================
# 参数说明 / Parameters
# ============================================================
# -Connect                连接 VPN / Connect to VPN
# -Disconnect             断开 VPN / Disconnect VPN
# -DuoMethod <method>     DUO 验证方式 / DUO method: push(推送), phone(电话), sms(短信), passcode(TOTP)
# -Status                 显示连接状态 / Show connection status
# -SaveCredentials        保存凭据 / Save credentials (legacy single-config)
# -SaveTOTP               保存 TOTP 密钥 / Save TOTP secret for auto passcode
# -Reconfigure            清除配置重新设置 / Clear config and re-setup
# -List                   列出所有命令 / List all commands
# -Help                   显示帮助 / Show detailed help
# -Add                    添加新 Profile / Add new VPN profile
# -Ls                     列出所有 Profile / List all profiles
# -Use <name>             切换 Profile / Switch active profile
# -Rm <name>              删除 Profile / Remove profile
# -Edit <name>            编辑 Profile / Edit profile
# -Set <key> -SetValue <v> 修改单个设置 / Change single setting (server/group/port/protocol/user/duo)
# ============================================================

param(
    [string]$VpnServer,
    [string]$VpnGroup,
    [ValidateSet("push", "phone", "sms", "passcode")]
    [string]$DuoMethod = "push",
    [switch]$Connect,
    [switch]$Disconnect,
    [switch]$SaveCredentials,
    [switch]$SaveTOTP,
    [switch]$Status,
    [switch]$Help,
    [switch]$List,
    [switch]$Reconfigure,
    # Multi-profile commands
    [switch]$Add,
    [switch]$Ls,
    [string]$Use,
    [string]$Rm,
    [string]$Edit,
    # One-click settings
    [string]$Set,
    [string]$SetValue
)

# ============================================================
# 全局配置路径 / Global config paths
# ============================================================
$VpnCliPath = "C:\Program Files (x86)\Cisco\Cisco Secure Client\vpncli.exe"
$ConfigDir  = "$env:USERPROFILE\.vpn-auto-connect"
$CredFile   = "$ConfigDir\credentials.xml"
$ConfigFile = "$ConfigDir\config.json"
$TotpFile   = "$ConfigDir\totp.xml"
$ProfilesDir      = "$ConfigDir\profiles"
$ProfilesIndex    = "$ConfigDir\profiles.json"
$ActiveProfileFile = "$ConfigDir\active_profile"

# ---------- Init Directory ----------
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    # Restrict directory permissions to current user only
    icacls $ConfigDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
}

# ============================================================
# 配置管理 / Config Management
# ============================================================
# 配置文件: ~/.vpn-auto-connect/config.json
# 格式: {"Server": "vpn.example.com", "Group": "", "Port": "443", "Protocol": "ssl"}

function Save-Config {
    # 保存 VPN 服务器配置到 config.json / Save VPN server config to config.json
    param($Server, $Group, $Port, $Protocol)
    $config = @{
        Server   = $Server
        Group    = $Group
        Port     = $Port
        Protocol = $Protocol
    }
    $config | ConvertTo-Json | Set-Content $ConfigFile -Encoding UTF8
}

function Load-Config {
    # 加载 VPN 服务器配置 / Load VPN server config from config.json
    if (Test-Path $ConfigFile) {
        return Get-Content $ConfigFile -Raw | ConvertFrom-Json
    }
    return $null
}

# ---------- Multi-Profile Management ----------
function Get-ProfilesIndex {
    if (Test-Path $ProfilesIndex) {
        return Get-Content $ProfilesIndex -Raw | ConvertFrom-Json
    }
    return @()
}

function Save-ProfilesIndex {
    param($Index)
    $Index | ConvertTo-Json -Depth 3 | Set-Content $ProfilesIndex -Encoding UTF8
}

function Get-ActiveProfile {
    if (Test-Path $ActiveProfileFile) {
        return (Get-Content $ActiveProfileFile -Raw).Trim()
    }
    return $null
}

function Set-ActiveProfile {
    param([string]$Name)
    $Name | Set-Content $ActiveProfileFile -Encoding UTF8
}

function Test-ProfileComplete {
    param($Config, $CredData)
    return (
        $Config.Server -and
        $Config.Port -and
        $Config.Protocol -and
        $CredData.Username
    )
}

function Get-ProfileDir {
    param([string]$Name)
    return "$ProfilesDir\$Name"
}

function Add-VpnProfile {
    Write-Host ""
    Write-Host "=== Add New VPN Profile ===" -ForegroundColor Yellow
    Write-Host ""

    $name = Read-Host "Profile name (e.g. dku, company, home-lab)"
    if (-not $name) { Write-Host "[!!] Name cannot be empty" -ForegroundColor Red; return }
    $name = $name -replace '[^a-zA-Z0-9_-]', ''

    # Check if profile already exists
    $existing = Get-ProfilesIndex
    if ($existing -contains $name) {
        Write-Host "[!!] Profile '$name' already exists. Use vpn-edit to modify." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "[1/4] VPN Server" -ForegroundColor Cyan
    $server = Read-Host "  Server address"
    if (-not $server) { Write-Host "[!!] Server is required" -ForegroundColor Red; return }

    Write-Host ""
    Write-Host "[2/4] VPN Group" -ForegroundColor Cyan
    $group = Read-Host "  Group (blank to skip)"

    Write-Host ""
    Write-Host "[3/4] Port" -ForegroundColor Cyan
    $port = Read-Host "  Port (Enter for 443)"
    if (-not $port) { $port = "443" }

    Write-Host ""
    Write-Host "[4/4] Protocol" -ForegroundColor Cyan
    $protocol = Read-Host "  Protocol (ssl/ipsec/any, Enter for ssl)"
    if (-not $protocol) { $protocol = "ssl" }

    Write-Host ""
    $username = Read-Host "Username"
    $securePassword = Read-Host "Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    # Create profile directory
    $profileDir = Get-ProfileDir $name
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    # Save profile config
    $config = @{
        Server   = $server
        Group    = $group
        Port     = $port
        Protocol = $protocol
    }
    $config | ConvertTo-Json | Set-Content "$profileDir\config.json" -Encoding UTF8

    # Save profile credentials
    $credObject = [PSCustomObject]@{
        Server   = $server
        Username = $username
        Password = (Encrypt-String $plainPassword)
    }
    $credObject | ConvertTo-Json | Set-Content "$profileDir\credentials.xml" -Encoding UTF8

    # Copy TOTP if exists in main config
    if (Test-Path $TotpFile) {
        Copy-Item $TotpFile "$profileDir\totp.xml" -Force
    }

    # Update index
    $index = Get-ProfilesIndex
    $index += $name
    Save-ProfilesIndex $index

    # Set as active if it's the first profile
    if ($index.Count -eq 1) {
        Set-ActiveProfile $name
    }

    Write-Host "[OK] Profile '$name' created" -ForegroundColor Green
    Write-Host "     Server: $server" -ForegroundColor Gray
    Write-Host "     Use: vpn-use $name" -ForegroundColor Gray
}

function Use-VpnProfile {
    param([string]$Name)
    if (-not $Name) {
        Write-Host "[!!] Usage: vpn-use <profile-name>" -ForegroundColor Red
        return
    }
    $index = Get-ProfilesIndex
    if ($index -notcontains $Name) {
        Write-Host "[!!] Profile '$Name' not found. Available: $($index -join ', ')" -ForegroundColor Red
        return
    }
    Set-ActiveProfile $Name
    Write-Host "[OK] Active profile: $Name" -ForegroundColor Green
}

function List-VpnProfiles {
    $index = Get-ProfilesIndex
    $active = Get-ActiveProfile

    if ($index.Count -eq 0) {
        Write-Host "[*] No profiles configured. Run: vpn-add" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "VPN Profiles:" -ForegroundColor Cyan
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    foreach ($name in $index) {
        $marker = if ($name -eq $active) { " *" } else { "  " }
        $profileDir = Get-ProfileDir $name
        $config = $null
        if (Test-Path "$profileDir\config.json") {
            $config = Get-Content "$profileDir\config.json" -Raw | ConvertFrom-Json
        }
        $serverInfo = if ($config) { "$($config.Server):$($config.Port)" } else { "(incomplete)" }
        $color = if ($name -eq $active) { "Green" } else { "Gray" }
        Write-Host "$marker$name" -NoNewline -ForegroundColor $color
        Write-Host "  $serverInfo" -ForegroundColor DarkGray
    }
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  * = active profile" -ForegroundColor Gray
    Write-Host ""
}

function Remove-VpnProfile {
    param([string]$Name)
    if (-not $Name) {
        Write-Host "[!!] Usage: vpn-rm <profile-name>" -ForegroundColor Red
        return
    }
    $index = Get-ProfilesIndex
    if ($index -notcontains $Name) {
        Write-Host "[!!] Profile '$Name' not found" -ForegroundColor Red
        return
    }

    $confirm = Read-Host "Delete profile '$Name'? (y/N)"
    if ($confirm -ne "y") { return }

    # Remove profile directory
    $profileDir = Get-ProfileDir $Name
    if (Test-Path $profileDir) {
        Remove-Item $profileDir -Recurse -Force
    }

    # Update index
    $index = $index | Where-Object { $_ -ne $Name }
    Save-ProfilesIndex $index

    # Clear active if it was the deleted one
    if ((Get-ActiveProfile) -eq $Name) {
        if ($index.Count -gt 0) {
            Set-ActiveProfile $index[0]
        } else {
            Remove-Item $ActiveProfileFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "[OK] Profile '$Name' deleted" -ForegroundColor Green
}

function Edit-VpnProfile {
    param([string]$Name)
    if (-not $Name) {
        Write-Host "[!!] Usage: vpn-edit <profile-name>" -ForegroundColor Red
        return
    }
    $index = Get-ProfilesIndex
    if ($index -notcontains $Name) {
        Write-Host "[!!] Profile '$Name' not found" -ForegroundColor Red
        return
    }

    $profileDir = Get-ProfileDir $Name
    $config = Get-Content "$profileDir\config.json" -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "=== Edit Profile: $Name ===" -ForegroundColor Yellow
    Write-Host "  Current server:   $($config.Server)" -ForegroundColor Gray
    Write-Host "  Current group:    $($config.Group)" -ForegroundColor Gray
    Write-Host "  Current port:     $($config.Port)" -ForegroundColor Gray
    Write-Host "  Current protocol: $($config.Protocol)" -ForegroundColor Gray
    Write-Host ""

    $server = Read-Host "New server (Enter to keep)"
    if ($server) { $config.Server = $server }

    $group = Read-Host "New group (Enter to keep, '-' to clear)"
    if ($group -eq "-") { $config.Group = "" }
    elseif ($group) { $config.Group = $group }

    $port = Read-Host "New port (Enter to keep)"
    if ($port) { $config.Port = $port }

    $protocol = Read-Host "New protocol (Enter to keep)"
    if ($protocol) { $config.Protocol = $protocol }

    $config | ConvertTo-Json | Set-Content "$profileDir\config.json" -Encoding UTF8

    # Update credentials if requested
    $changeCred = Read-Host "Update credentials? (y/N)"
    if ($changeCred -eq "y") {
        $username = Read-Host "New username"
        $securePassword = Read-Host "New password" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

        $credObject = [PSCustomObject]@{
            Server   = $config.Server
            Username = $username
            Password = (Encrypt-String $plainPassword)
        }
        $credObject | ConvertTo-Json | Set-Content "$profileDir\credentials.xml" -Encoding UTF8
    }

    Write-Host "[OK] Profile '$Name' updated" -ForegroundColor Green
}

function Set-VpnSetting {
    param([string]$Key, [string]$Value)

    # Determine which config to modify
    $active = Get-ActiveProfile
    if ($active) {
        $profileDir = Get-ProfileDir $active
        $configFile = "$profileDir\config.json"
        $credFile = "$profileDir\credentials.xml"
        $scope = "profile '$active'"
    } else {
        $configFile = $ConfigFile
        $credFile = $CredFile
        $scope = "global"
    }

    if (-not (Test-Path $configFile)) {
        Write-Host "[!!] No config found. Run vpn-setup or vpn-add first." -ForegroundColor Red
        return
    }

    $config = Get-Content $configFile -Raw | ConvertFrom-Json

    switch ($Key) {
        "server" {
            $config.Server = $Value
            Write-Host "[OK] Server set to: $Value ($scope)" -ForegroundColor Green
        }
        "group" {
            $config.Group = $Value
            Write-Host "[OK] Group set to: $Value ($scope)" -ForegroundColor Green
        }
        "port" {
            $config.Port = $Value
            Write-Host "[OK] Port set to: $Value ($scope)" -ForegroundColor Green
        }
        "protocol" {
            if ($Value -notin @("ssl", "ipsec", "any")) {
                Write-Host "[!!] Protocol must be: ssl, ipsec, or any" -ForegroundColor Red
                return
            }
            $config.Protocol = $Value
            Write-Host "[OK] Protocol set to: $Value ($scope)" -ForegroundColor Green
        }
        "user" {
            $username = Read-Host "New username"
            $securePassword = Read-Host "New password" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

            $credObject = [PSCustomObject]@{
                Server   = $config.Server
                Username = $username
                Password = (Encrypt-String $plainPassword)
            }
            $credObject | ConvertTo-Json | Set-Content $credFile -Encoding UTF8
            Write-Host "[OK] Credentials updated ($scope)" -ForegroundColor Green
            return
        }
        "duo" {
            if ($Value -notin @("push", "phone", "sms", "passcode")) {
                Write-Host "[!!] DUO method must be: push, phone, sms, or passcode" -ForegroundColor Red
                return
            }
            # Store default DUO method in config
            $config | Add-Member -NotePropertyName "DuoMethod" -NotePropertyValue $Value -Force
            Write-Host "[OK] Default DUO method set to: $Value ($scope)" -ForegroundColor Green
        }
        default {
            Write-Host "[!!] Unknown setting: $Key" -ForegroundColor Red
            Write-Host "     Valid keys: server, group, port, protocol, user, duo" -ForegroundColor Gray
            return
        }
    }

    $config | ConvertTo-Json | Set-Content $configFile -Encoding UTF8
}

function Load-ActiveProfileConfig {
    $active = Get-ActiveProfile
    if (-not $active) { return $null }
    $profileDir = Get-ProfileDir $active
    if (-not (Test-Path "$profileDir\config.json")) { return $null }
    return Get-Content "$profileDir\config.json" -Raw | ConvertFrom-Json
}

function Load-ActiveProfileCredentials {
    $active = Get-ActiveProfile
    if (-not $active) { return $null }
    $profileDir = Get-ProfileDir $active
    if (-not (Test-Path "$profileDir\credentials.xml")) { return $null }
    $data = Get-Content "$profileDir\credentials.xml" -Raw | ConvertFrom-Json
    return @{
        Server   = $data.Server
        Username = $data.Username
        Password = (Decrypt-String $data.Password)
    }
}

# ============================================================
# 凭据管理 (DPAPI 加密) / Credential Management (DPAPI Encrypted)
# ============================================================
# 使用 Windows DPAPI 加密，仅当前 Windows 用户可解密
# 凭据文件: ~/.vpn-auto-connect/credentials.xml (实际是 JSON 格式)
# Uses Windows DPAPI encryption - only the current Windows user can decrypt

Add-Type -AssemblyName System.Security

function Encrypt-String {
    # DPAPI 加密字符串 / Encrypt string using DPAPI (CurrentUser scope)
    param([string]$PlainText)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($encrypted)
}

function Decrypt-String {
    # DPAPI 解密字符串 / Decrypt DPAPI-encrypted string
    param([string]$EncryptedBase64)
    $encrypted = [Convert]::FromBase64String($EncryptedBase64)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Save-VpnCredentials {
    $config = Load-Config
    $server = $config.Server
    if (-not $server) {
        Write-Host "Examples: vpn.duke.edu, vpn.company.com, 10.0.0.1" -ForegroundColor Gray
        $server = Read-Host "Enter VPN server address"
        $group  = Read-Host "Enter VPN Group (leave blank to skip)"
        Save-Config -Server $server -Group $group
    }

    $username = Read-Host "Enter username"
    $securePassword = Read-Host "Enter password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    $credObject = [PSCustomObject]@{
        Server   = $server
        Username = $username
        Password = (Encrypt-String $plainPassword)
    }
    $credObject | ConvertTo-Json | Set-Content $CredFile -Encoding UTF8

    Write-Host "[OK] Credentials saved to: $CredFile" -ForegroundColor Green
}

function Load-VpnCredentials {
    if (-not (Test-Path $CredFile)) {
        Write-Host "[!!] No saved credentials found. Run: .\vpn-auto-connect.ps1 -SaveCredentials" -ForegroundColor Red
        return $null
    }
    $data = Get-Content $CredFile -Raw | ConvertFrom-Json
    return @{
        Server   = $data.Server
        Username = $data.Username
        Password = (Decrypt-String $data.Password)
    }
}

# ============================================================
# TOTP 管理 (全自动 DUO 登录) / TOTP Management (full-auto DUO login)
# ============================================================
# TOTP 密钥文件: ~/.vpn-auto-connect/totp.xml (DPAPI 加密)
# 获取密钥方式: 用 qrgui 解码 DUO 二维码，复制 Secret 字段
# TOTP secret file: ~/.vpn-auto-connect/totp.xml (DPAPI encrypted)
# How to get: use qrgui to decode DUO QR code, copy the Secret field

function Save-TOTPSecret {
    Write-Host "=== Save DUO TOTP Secret ===" -ForegroundColor Yellow
    Write-Host "Hint: The TOTP secret is the 'secret' parameter in your DUO enrollment QR code URL" -ForegroundColor Gray
    Write-Host "      Format example: otpauth://totp/...?secret=ABCDEF123456" -ForegroundColor Gray
    Write-Host "      It should be Base32 (A-Z, 2-7), NOT a duo:// link" -ForegroundColor Gray
    $secret = Read-Host "Enter TOTP secret (Base32 format)"
    if (-not $secret) { return }

    # Validate Base32 format
    if ($secret -match "^duo://") {
        Write-Host "[!!] This is a DUO activation link, not a TOTP secret." -ForegroundColor Red
        Write-Host "     You need the 'secret=' parameter from the QR code URL." -ForegroundColor Red
        return
    }
    if ($secret -notmatch "^[A-Za-z2-7=]+$") {
        Write-Host "[!!] Invalid Base32 format. Expected A-Z and 2-7 only." -ForegroundColor Red
        return
    }

    [PSCustomObject]@{ Secret = (Encrypt-String $secret) } | ConvertTo-Json | Set-Content $TotpFile -Encoding UTF8

    Write-Host "[OK] TOTP secret saved (encrypted)" -ForegroundColor Green
}

function Get-TOTPCode {
    if (-not (Test-Path $TotpFile)) { return $null }
    $data = Get-Content $TotpFile -Raw | ConvertFrom-Json
    $secret = (Decrypt-String $data.Secret)

    # Compute TOTP (RFC 6238)
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $counter = [math]::Floor($epoch / 30)

    # Base32 decode
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $secret = $secret.ToUpper().TrimEnd('=')
    $bits = ""
    foreach ($c in $secret.ToCharArray()) {
        $val = $base32Chars.IndexOf($c)
        if ($val -lt 0) { continue }
        $bits += [convert]::ToString($val, 2).PadLeft(5, '0')
    }
    $bytes = [byte[]]::new([math]::Floor($bits.Length / 8))
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [convert]::ToByte($bits.Substring($i * 8, 8), 2)
    }

    # HMAC-SHA1
    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = $bytes
    $counterBytes = [BitConverter]::GetBytes([int64]$counter)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counterBytes) }
    $hash = $hmac.ComputeHash($counterBytes)

    $offset = $hash[$hash.Length - 1] -band 0x0F
    $code = (($hash[$offset] -band 0x7F) -shl 24) -bor
            (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
            (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
            ($hash[$offset + 3] -band 0xFF)

    return ($code % 1000000).ToString().PadLeft(6, '0')
}

# ============================================================
# VPN 操作 / VPN Operations
# ============================================================

# vpn-status: 检查 10.x.x.x IP 判断是否已连接 / Check 10.x.x.x IP to detect VPN connection
function Get-VpnStatus {
    # Check by network interface (more reliable than vpncli status)
    $vpnAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } |
        Get-NetIPAddress -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -match "^10\." }

    if ($vpnAdapter) {
        Write-Host "[OK] VPN connected" -ForegroundColor Green
        Write-Host "     IP: $($vpnAdapter.IPAddress)" -ForegroundColor Gray
    } else {
        Write-Host "[!!] VPN not connected" -ForegroundColor Red
    }

    # Also show Cisco client status
    $processes = Get-Process -Name "vpncli","vpnui","csc_ui" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "[*] Cisco Secure Client is running" -ForegroundColor Gray
    }
}

# vpn-connect: 自动连接 VPN (6 步交互) / Auto-connect VPN (6-step vpncli interaction)
# 1. 连接服务器  2. 选择分组  3. 发送用户名  4. 发送密码  5. DUO 验证  6. 接受证书
function Connect-Vpn {
    # 优先使用活跃 Profile，回退到旧版配置 / Try active profile first, fall back to legacy config
    $cred = Load-ActiveProfileCredentials
    if (-not $cred) { $cred = Load-VpnCredentials }
    if (-not $cred) { return }

    $config = Load-ActiveProfileConfig
    if (-not $config) { $config = Load-Config }
    $server = $cred.Server

    # Close GUI client if running (it blocks vpncli)
    $guiProc = Get-Process -Name "csc_ui","vpnui" -ErrorAction SilentlyContinue
    if ($guiProc) {
        Write-Host "[..] Closing Cisco GUI client (blocks CLI)..." -ForegroundColor Yellow
        $guiProc | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    Write-Host "[->] Connecting to: $server" -ForegroundColor Cyan
    Write-Host "     User: $($cred.Username)" -ForegroundColor Gray
    Write-Host "     DUO method: $DuoMethod" -ForegroundColor Gray

    # Determine DUO second factor input
    # DUO MFA prompt shows numbered options (e.g. "1-Push to X-3808")
    # Default: "1" for push. Override with -DuoMethod for other options.
    $duoInput = "1"
    if ($DuoMethod -eq "phone") { $duoInput = "2" }
    elseif ($DuoMethod -eq "sms") { $duoInput = "3" }
    elseif ($DuoMethod -eq "passcode") {
        $code = Get-TOTPCode
        if ($code) {
            $duoInput = $code
            Write-Host "     TOTP code: $code" -ForegroundColor Gray
        } else {
            Write-Host "[!!] TOTP secret not found. Run: .\vpn-auto-connect.ps1 -SaveTOTP" -ForegroundColor Red
            return
        }
    }

    Write-Host "[..] Connecting..." -ForegroundColor Yellow
    if ($DuoMethod -eq "push") {
        Write-Host "[>>] Please tap 'Approve' on your DUO mobile push" -ForegroundColor Yellow
    }

    # Start vpncli with stdin redirect
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $VpnCliPath
    $psi.Arguments = "-s"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)

    try {
        # Wait for vpncli to initialize
        Start-Sleep -Seconds 4

        # Step 1: Connect to server (with port if configured)
        $connectAddr = $server
        if ($config.Port -and $config.Port -ne "443") {
            $connectAddr = "${server}:$($config.Port)"
        }
        Write-Host "[1/6] Connecting to $connectAddr..." -ForegroundColor Gray
        $proc.StandardInput.WriteLine("connect $connectAddr")
        Start-Sleep -Seconds 8

        # Step 2: Select group (0 = Default)
        Write-Host "[2/6] Selecting group..." -ForegroundColor Gray
        $groupNum = "0"
        if ($config.Group -eq "Library Resources Only") { $groupNum = "1" }
        $proc.StandardInput.WriteLine($groupNum)
        Start-Sleep -Seconds 3

        # Step 3: Username (press Enter to accept default)
        Write-Host "[3/6] Sending username..." -ForegroundColor Gray
        $proc.StandardInput.WriteLine("")
        Start-Sleep -Seconds 3

        # Step 4: Password
        Write-Host "[4/6] Sending password..." -ForegroundColor Gray
        $proc.StandardInput.WriteLine($cred.Password)
        Start-Sleep -Seconds 4

        # Step 5: DUO second factor
        Write-Host "[5/6] Sending DUO option ($duoInput)..." -ForegroundColor Gray
        $proc.StandardInput.WriteLine($duoInput)
        if ($DuoMethod -eq "passcode") {
            Start-Sleep -Seconds 5
        } else {
            Write-Host "[>>] Waiting for DUO approval (up to 60s)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 60
        }

        # Step 6: Accept certificate (if prompted)
        Write-Host "[6/6] Accepting certificate..." -ForegroundColor Gray
        $proc.StandardInput.WriteLine("y")

        # Wait and collect output (with timeout, don't block on EndOfStream)
        Start-Sleep -Seconds 5
        $output = ""
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 15) {
            if (-not $proc.StandardOutput.EndOfStream) {
                $output += [char]$proc.StandardOutput.Read()
            } else {
                Start-Sleep -Milliseconds 300
            }
        }

        Write-Host $output -ForegroundColor DarkGray

        # Check connection by looking for VPN network interface
        Start-Sleep -Seconds 3
        $vpnAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Get-NetIPAddress -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match "^10\." }

        if ($vpnAdapter) {
            Write-Host "[OK] VPN connected (IP: $($vpnAdapter.IPAddress))" -ForegroundColor Green
        } elseif ($output -match "Connected") {
            Write-Host "[OK] VPN connected" -ForegroundColor Green
        } elseif ($output -match "Login denied|failed|ʧ") {
            Write-Host "[!!] Authentication failed" -ForegroundColor Red
        } else {
            Write-Host "[??] Check output above" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!!] Error: $_" -ForegroundColor Red
    } finally {
        if (-not $proc.HasExited) {
            $proc.Kill()
        }
        $proc.Dispose()
    }
}

# vpn-disconnect: 断开 VPN 并重启 GUI 客户端 / Disconnect VPN and restart GUI client
function Disconnect-Vpn {
    Write-Host "[x] Disconnecting VPN..." -ForegroundColor Cyan
    $result = "disconnect" | & $VpnCliPath -s 2>&1
    $result | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    Write-Host "[OK] Disconnected" -ForegroundColor Green

    # Restart GUI client if it was killed during connect
    $guiPath = "C:\Program Files (x86)\Cisco\Cisco Secure Client\csc_ui.exe"
    if (Test-Path $guiPath) {
        Start-Process $guiPath
        Write-Host "[*] GUI client restarted" -ForegroundColor Gray
    }
}

# ---------- Main Logic ----------
if ($Reconfigure) {
    # Remove existing config and re-run setup
    Remove-Item $ConfigFile -Force -ErrorAction SilentlyContinue
    Remove-Item $CredFile -Force -ErrorAction SilentlyContinue
    Write-Host "[*] Configuration cleared. Running setup..." -ForegroundColor Yellow
}

# ---------- Profile Commands ----------
if ($Add) {
    Add-VpnProfile
    exit 0
}
if ($Ls) {
    List-VpnProfiles
    exit 0
}
if ($Use) {
    Use-VpnProfile $Use
    exit 0
}
if ($Rm) {
    Remove-VpnProfile $Rm
    exit 0
}
if ($Edit) {
    Edit-VpnProfile $Edit
    exit 0
}
if ($Set) {
    Set-VpnSetting $Set $SetValue
    exit 0
}

if ($List) {
    $activeProfile = Get-ActiveProfile
    Write-Host ""
    Write-Host "VPN Commands:" -ForegroundColor Cyan
    if ($activeProfile) {
        Write-Host "  Active profile: $activeProfile" -ForegroundColor Green
    }
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  vpn              " -NoNewline; Write-Host "-> Show this list" -ForegroundColor Gray
    Write-Host "  vpn-connect      " -NoNewline; Write-Host "-> Connect (DUO push)" -ForegroundColor Gray
    Write-Host "  vpn-disconnect   " -NoNewline; Write-Host "-> Disconnect" -ForegroundColor Gray
    Write-Host "  vpn-status       " -NoNewline; Write-Host "-> Show status" -ForegroundColor Gray
    Write-Host "  vpn-setup        " -NoNewline; Write-Host "-> Save credentials (legacy)" -ForegroundColor Gray
    Write-Host "  vpn-totp         " -NoNewline; Write-Host "-> Save TOTP secret" -ForegroundColor Gray
    Write-Host "  vpn-reconfig     " -NoNewline; Write-Host "-> Reset and reconfigure" -ForegroundColor Gray
    Write-Host "  vpn-help         " -NoNewline; Write-Host "-> Detailed help" -ForegroundColor Gray
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Profile Management:" -ForegroundColor Yellow
    Write-Host "  vpn-ls           " -NoNewline; Write-Host "-> List all profiles" -ForegroundColor Gray
    Write-Host "  vpn-add          " -NoNewline; Write-Host "-> Add new profile" -ForegroundColor Gray
    Write-Host "  vpn-use <name>   " -NoNewline; Write-Host "-> Switch active profile" -ForegroundColor Gray
    Write-Host "  vpn-rm <name>    " -NoNewline; Write-Host "-> Remove a profile" -ForegroundColor Gray
    Write-Host "  vpn-edit <name>  " -NoNewline; Write-Host "-> Edit profile settings" -ForegroundColor Gray
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

if ($Help) {
    Write-Host ""
    Write-Host "Cisco Secure Client Auto-Connect (with DUO 2FA)" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  .\vpn-auto-connect.ps1 [options]"
    Write-Host ""
    Write-Host "CONNECTION:" -ForegroundColor Yellow
    Write-Host "  (no args)                  First-time setup + connect"
    Write-Host "  -Connect                   Connect using saved credentials"
    Write-Host "  -Connect -DuoMethod <m>    Connect with specific DUO method"
    Write-Host "  -Disconnect                Disconnect VPN"
    Write-Host "  -Status                    Show connection status"
    Write-Host ""
    Write-Host "SETUP:" -ForegroundColor Yellow
    Write-Host "  -SaveCredentials           Save / update credentials (legacy)"
    Write-Host "  -SaveTOTP                  Save / update TOTP secret"
    Write-Host "  -Reconfigure               Reset and re-run setup"
    Write-Host ""
    Write-Host "PROFILES:" -ForegroundColor Yellow
    Write-Host "  -Add                       Add new VPN profile"
    Write-Host "  -Ls                        List all profiles"
    Write-Host "  -Use <name>                Switch active profile"
    Write-Host "  -Rm <name>                 Remove a profile"
    Write-Host "  -Edit <name>               Edit profile settings"
    Write-Host ""
    Write-Host "QUICK SETTINGS:" -ForegroundColor Yellow
    Write-Host "  -Set <key> -SetValue <val> Change a single setting"
    Write-Host "    Keys: server, group, port, protocol, user, duo"
    Write-Host ""
    Write-Host "DUO METHODS:" -ForegroundColor Yellow
    Write-Host "  push       (default) Send push notification to phone"
    Write-Host "  phone      Call your phone for verification"
    Write-Host "  sms        Send SMS passcode"
    Write-Host "  passcode   Auto-generate TOTP code (fully automatic)"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\vpn-auto-connect.ps1                          # First setup"
    Write-Host "  .\vpn-auto-connect.ps1 -Connect                 # Connect (DUO push)"
    Write-Host "  .\vpn-auto-connect.ps1 -Connect -DuoMethod passcode  # Full auto"
    Write-Host "  .\vpn-auto-connect.ps1 -Add                     # Add new profile"
    Write-Host "  .\vpn-auto-connect.ps1 -Use dku                 # Switch profile"
    Write-Host "  .\vpn-auto-connect.ps1 -Set server -SetValue vpn.company.com"
    Write-Host ""
    Write-Host "GLOBAL COMMANDS:" -ForegroundColor Yellow
    Write-Host "  vpn              List all available commands"
    Write-Host "  vpn-connect      Connect (DUO push)"
    Write-Host "  vpn-disconnect   Disconnect"
    Write-Host "  vpn-status       Show status"
    Write-Host "  vpn-setup        Save credentials (legacy)"
    Write-Host "  vpn-totp         Save TOTP secret"
    Write-Host "  vpn-reconfig     Reset and reconfigure"
    Write-Host "  vpn-ls           List all profiles"
    Write-Host "  vpn-add          Add new profile"
    Write-Host "  vpn-use <name>   Switch active profile"
    Write-Host "  vpn-rm <name>    Remove a profile"
    Write-Host "  vpn-edit <name>  Edit profile"
    Write-Host "  vpn-set <k> <v>  Quick setting change"
    Write-Host ""
    Write-Host "CONFIG DIRECTORY:" -ForegroundColor Yellow
    Write-Host "  $ConfigDir"
    Write-Host ""
    exit 0
}

if ($SaveCredentials) {
    Save-VpnCredentials
}
elseif ($SaveTOTP) {
    Save-TOTPSecret
}
elseif ($Connect) {
    Connect-Vpn
}
elseif ($Disconnect) {
    Disconnect-Vpn
}
elseif ($Status) {
    Get-VpnStatus
}
else {
    # Default: first-time setup + connect
    $config = Load-Config
    if (-not $config) {
        Write-Host ""
        Write-Host "=== First-Time Setup ===" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "[1/4] VPN Server" -ForegroundColor Cyan
        Write-Host "  Examples: portal.dukekunshan.edu.cn, vpn.company.com, 10.0.0.1" -ForegroundColor Gray
        $server = Read-Host "  Enter VPN server address"
        Write-Host ""

        Write-Host "[2/4] VPN Group" -ForegroundColor Cyan
        Write-Host "  Examples: -Default-, Library Resources Only" -ForegroundColor Gray
        Write-Host "  Leave blank if no group selection is needed" -ForegroundColor Gray
        $group = Read-Host "  Enter VPN Group"
        Write-Host ""

        Write-Host "[3/4] Port (optional)" -ForegroundColor Cyan
        Write-Host "  Default: 443 (SSL)" -ForegroundColor Gray
        Write-Host "  Examples: 443, 8443, 10443" -ForegroundColor Gray
        $port = Read-Host "  Enter port (Enter for default)"
        if (-not $port) { $port = "443" }
        Write-Host ""

        Write-Host "[4/4] Protocol" -ForegroundColor Cyan
        Write-Host "  Options:" -ForegroundColor Gray
        Write-Host "    ssl    - SSL/HTTPS (most common, default)" -ForegroundColor Gray
        Write-Host "    ipsec  - IPSec/IKEv2" -ForegroundColor Gray
        Write-Host "    any    - Let client auto-detect" -ForegroundColor Gray
        $protocol = Read-Host "  Enter protocol (Enter for ssl)"
        if (-not $protocol) { $protocol = "ssl" }
        Write-Host ""

        Save-Config -Server $server -Group $group -Port $port -Protocol $protocol
        Save-VpnCredentials
    }

    $cred = Load-VpnCredentials
    if ($cred) {
        Connect-Vpn
    }
}
