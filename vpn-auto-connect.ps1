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
# -DuoMethod <method>     DUO 验证方式 / DUO method: push(推送), phone(电话), passcode(TOTP)
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

[CmdletBinding()]
param(
    [string]$VpnServer,
    [string]$VpnGroup,
    [ValidateSet("push", "phone", "passcode")]
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
    [string]$SetValue,
    [switch]$Config,
    [switch]$Brief,
    [switch]$Reset,
    [switch]$NonInteractiveMfa,
    [switch]$LoadFunctionsOnly
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
$CiscoVpnStateFiles = @(
    "$env:ProgramData\Cisco\Cisco Secure Client\VPN\ConfigParam.bin",
    "$env:ProgramData\Cisco\Cisco Secure Client\VPN\routechangesv4.bin",
    "$env:ProgramData\Cisco\Cisco Secure Client\VPN\routechangesv6.bin"
)
$CiscoVpnLogSearchPaths = @(
    "$env:ProgramData\Cisco\Cisco Secure Client\Logs",
    "$env:ProgramData\Cisco\Cisco Secure Client\Log",
    "$env:ProgramData\Cisco\Cisco Secure Client\VPN\Logs",
    "$env:ProgramData\Cisco\Cisco Secure Client\VPN",
    "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Logs",
    "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\VPN\Logs"
)
$VpnSessionLimitSeconds = 24 * 60 * 60

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

function Migrate-LegacyConfigIfNeeded {
    # One-time migration: move legacy root files into profiles/default
    $index = Get-ProfilesIndex
    $hasLegacy = (Test-Path $ConfigFile) -or (Test-Path $CredFile)
    if ($index.Count -gt 0 -or -not $hasLegacy) { return }

    Write-Host "[..] Migrating legacy config to profiles/default..." -ForegroundColor Yellow
    $profileDir = Get-ProfileDir "default"
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    if (Test-Path $ConfigFile) { Copy-Item $ConfigFile "$profileDir\config.json" -Force }
    if (Test-Path $CredFile)  { Copy-Item $CredFile  "$profileDir\credentials.xml" -Force }
    if (Test-Path $TotpFile)  { Copy-Item $TotpFile  "$profileDir\totp.xml" -Force }

    Save-ProfilesIndex @("default")
    Set-ActiveProfile "default"
    Write-Host "[OK] Migrated to profile 'default'" -ForegroundColor Green
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
        Write-Host "[!!] Profile '$name' already exists. Use 'vpn-config set' to modify." -ForegroundColor Red
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
    Write-Host "[*] Optional: DUO Push target menu number" -ForegroundColor Gray
    Write-Host "    Mainly needed when your DUO account has multiple phone numbers." -ForegroundColor DarkGray
    Write-Host "    Enter the Cisco DUO menu number you prefer, such as 1 or 2." -ForegroundColor DarkGray
    Write-Host "    If you only have one approved phone, leave blank and skip it." -ForegroundColor DarkGray
    $duoPushTarget = Read-Host "  Push target number (optional, e.g. 2)"
    if ($duoPushTarget) { $duoPushTarget = Normalize-DuoPushTarget -Value $duoPushTarget.Trim() }

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
    if ($duoPushTarget) {
        $config.DuoPushTarget = $duoPushTarget
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
    Write-Host "     Use: vpn-config use $name" -ForegroundColor Gray
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

function Show-Config {
    param([switch]$Brief)

    $index = Get-ProfilesIndex
    $active = Get-ActiveProfile

    if ($Brief) {
        # Compact profile list (replaces vpn-ls)
        if ($index.Count -eq 0) {
            Write-Host "[!!] No profiles configured. Run: vpn-config add" -ForegroundColor Yellow
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
        return
    }

    Write-Host ""
    Write-Host "=== VPN Configuration ===" -ForegroundColor Cyan
    Write-Host ""

    # Active profile
    if ($active) {
        Write-Host "Active Profile: $active" -ForegroundColor Green
    } else {
        Write-Host "Active Profile: (none)" -ForegroundColor Yellow
    }

    # TOTP status (check profile first, then global)
    $hasTotp = $false
    if ($active) { $hasTotp = Test-Path "$(Get-ProfileDir $active)\totp.xml" }
    if (-not $hasTotp) { $hasTotp = Test-Path $TotpFile }
    $totpStatus = if ($hasTotp) { "saved" } else { "not set" }
    Write-Host "TOTP Secret:    $totpStatus" -ForegroundColor $(if ($hasTotp) { "Green" } else { "Yellow" })
    Write-Host "Push Target:    optional DUO menu number for multiple-phone accounts" -ForegroundColor DarkGray

    Write-Host ""

    # Profiles
    if ($index.Count -eq 0) {
        Write-Host "[!!] No profiles configured. Run: vpn-config add" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host "Profiles ($($index.Count)):" -ForegroundColor Cyan
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray

    foreach ($name in $index) {
        $marker = if ($name -eq $active) { " *" } else { "  " }
        $color = if ($name -eq $active) { "Green" } else { "White" }
        Write-Host "$marker$name" -ForegroundColor $color

        $profileDir = Get-ProfileDir $name

        # Config
        if (Test-Path "$profileDir\config.json") {
            $cfg = Get-Content "$profileDir\config.json" -Raw | ConvertFrom-Json
            Write-Host "    Server:   $($cfg.Server)" -ForegroundColor Gray
            Write-Host "    Port:     $($cfg.Port)" -ForegroundColor Gray
            Write-Host "    Protocol: $($cfg.Protocol)" -ForegroundColor Gray
            Write-Host "    Group:    $($cfg.Group)" -ForegroundColor Gray
            $pushTarget = if ($cfg.PSObject.Properties.Name -contains 'DuoPushTarget' -and $cfg.DuoPushTarget) { $cfg.DuoPushTarget } else { "(blank, auto)" }
            Write-Host "    PushTo:   $pushTarget" -ForegroundColor Gray
            Write-Host "              optional menu number; leave blank if only one DUO phone is enrolled" -ForegroundColor DarkGray
        } else {
            Write-Host "    (no config)" -ForegroundColor DarkGray
        }

        # Credentials
        if (Test-Path "$profileDir\credentials.xml") {
            try {
                $credData = Get-Content "$profileDir\credentials.xml" -Raw | ConvertFrom-Json
                Write-Host "    NetID:    $($credData.Username)" -ForegroundColor Gray
                Write-Host "    Password: (saved)" -ForegroundColor Gray
            } catch {
                Write-Host "    Credentials: (read error)" -ForegroundColor Red
            }
        } else {
            Write-Host "    Credentials: (none)" -ForegroundColor DarkGray
        }

        # Per-profile TOTP
        if (Test-Path "$profileDir\totp.xml") {
            Write-Host "    TOTP:     (saved)" -ForegroundColor Gray
        }

        Write-Host ""
    }

    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  * = active profile" -ForegroundColor Gray
    Write-Host "  PushTo = optional DUO menu number (1/2/3...); leave blank if only one phone is enrolled" -ForegroundColor Gray
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
    Write-Host "  Current PushTo:   $($config.DuoPushTarget)" -ForegroundColor Gray
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

    Write-Host "Optional: DUO push target menu number, mainly for multiple-phone accounts." -ForegroundColor DarkGray
    Write-Host "          Enter the Cisco DUO menu number you want, such as 1 or 2." -ForegroundColor DarkGray
    $pushTarget = Read-Host "New push target number (Enter to keep, '-' to clear)"
    if ($pushTarget -eq "-") {
        if ($config.PSObject.Properties.Name -contains 'DuoPushTarget') {
            $config.PSObject.Properties.Remove('DuoPushTarget')
        }
    } elseif ($pushTarget) {
        $normalizedTarget = Normalize-DuoPushTarget -Value $pushTarget.Trim()
        if (-not $normalizedTarget) {
            Write-Host "[!!] Push target must be a Cisco DUO menu number such as 1 or 2" -ForegroundColor Red
            return
        }
        $config | Add-Member -NotePropertyName "DuoPushTarget" -NotePropertyValue $normalizedTarget -Force
    }

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
        Write-Host "[!!] No config found. Run 'vpn-config add' or 'vpn-config reset-all' first." -ForegroundColor Red
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
            if ($Value -notin @("push", "phone", "passcode")) {
                Write-Host "[!!] DUO method must be: push, phone, or passcode" -ForegroundColor Red
                return
            }
            # Store default DUO method in config
            $config | Add-Member -NotePropertyName "DuoMethod" -NotePropertyValue $Value -Force
            Write-Host "[OK] Default DUO method set to: $Value ($scope)" -ForegroundColor Green
        }
        "push-target" {
            if (-not $Value -or $Value -in @("-", "clear", "none")) {
                if ($config.PSObject.Properties.Name -contains 'DuoPushTarget') {
                    $config.PSObject.Properties.Remove('DuoPushTarget')
                }
                Write-Host "[OK] DUO push target cleared ($scope)" -ForegroundColor Green
            } else {
                $targetNumber = Normalize-DuoPushTarget -Value $Value
                if (-not $targetNumber) {
                    Write-Host "[!!] Push target must be a Cisco DUO menu number such as 1 or 2" -ForegroundColor Red
                    return
                }
                $config | Add-Member -NotePropertyName "DuoPushTarget" -NotePropertyValue $targetNumber -Force
                Write-Host "[OK] DUO push target set to: $targetNumber ($scope)" -ForegroundColor Green
                Write-Host "     Optional; mainly for accounts with multiple DUO phone numbers." -ForegroundColor Gray
                Write-Host "     This is the Cisco DUO menu number (1/2/3...), not the phone suffix." -ForegroundColor Gray
                Write-Host "     If only one phone is enrolled, you can leave it blank." -ForegroundColor Gray
            }
        }
        default {
            Write-Host "[!!] Unknown setting: $Key" -ForegroundColor Red
            Write-Host "     Valid keys: server, group, port, protocol, user, duo, push-target" -ForegroundColor Gray
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
    # Read TOTP from active profile first, fall back to global
    $active = Get-ActiveProfile
    $totpPath = $null
    if ($active) {
        $profileTotp = "$(Get-ProfileDir $active)\totp.xml"
        if (Test-Path $profileTotp) { $totpPath = $profileTotp }
    }
    if (-not $totpPath -and (Test-Path $TotpFile)) { $totpPath = $TotpFile }
    if (-not $totpPath) { return $null }

    $data = Get-Content $totpPath -Raw | ConvertFrom-Json
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

# Processes that must not hold the VPN lock before vpncli connect (never kill vpnagent).
$script:CiscoVpnKillNames = @('csc_ui', 'vpnui', 'vpncli')

function Get-CiscoVpnBlockerProcesses {
    $ciscoDir = Split-Path $VpnCliPath -Parent
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        if ($p.Name -eq 'vpnagent') { continue }
        if ($script:CiscoVpnKillNames -contains $p.Name) {
            $list.Add($p) | Out-Null
            continue
        }
        try {
            if ($p.Path -and $p.Path.StartsWith($ciscoDir, [StringComparison]::OrdinalIgnoreCase)) {
                if ($p.Name -ne 'vpnagent') { $list.Add($p) | Out-Null }
            }
        } catch { }
    }
    return $list
}

function Write-CiscoVpnBlockerReport {
    $blockers = Get-CiscoVpnBlockerProcesses
    if ($blockers.Count -eq 0) {
        Write-Host "[*] No GUI/vpncli blockers (vpnagent may still be running; that is OK)" -ForegroundColor Gray
        return
    }
    Write-Host "[*] Processes that block CLI connect (close these first):" -ForegroundColor Yellow
    foreach ($p in $blockers) {
        $path = try { $p.Path } catch { "" }
        $parentHint = ""
        try {
            $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction Stop
            $parent = Get-Process -Id $wmi.ParentProcessId -ErrorAction SilentlyContinue
            if ($parent) { $parentHint = "  parent: $($parent.ProcessName) (PID $($parent.Id))" }
        } catch { }
        Write-Host "     $($p.Name) (PID $($p.Id))$parentHint" -ForegroundColor Gray
        if ($path) { Write-Host "       $path" -ForegroundColor DarkGray }
    }
}

function Invoke-VpnCliDisconnectQuiet {
    # Do not use "disconnect | vpncli -s" — that spawns a vpncli that often stays running.
    if (-not (Test-Path $VpnCliPath)) { return }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $VpnCliPath
    $psi.Arguments = "-s"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Seconds 2
        $proc.StandardInput.WriteLine("disconnect")
        $proc.StandardInput.WriteLine("exit")
        $proc.StandardInput.Flush()
        if (-not $proc.WaitForExit(5000)) { $proc.Kill() }
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        if ($env:VPN_DEBUG -eq '1') {
            $disconnectOutput = @($stdout, $stderr) -join "`n"
            if ($disconnectOutput.Trim()) {
                Write-Host "--- vpncli disconnect output ---" -ForegroundColor DarkGray
                Write-Host $disconnectOutput -ForegroundColor DarkGray
            }
        }
    } catch {
        if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    }
}

# Cisco GUI or another vpncli holds the VPN subsystem; CLI connect fails until they are closed.
function Stop-CiscoClientBlockers {
    $blockers = Get-CiscoVpnBlockerProcesses
    if ($blockers.Count -eq 0) {
        return $true
    }

    Write-Host "[..] Closing Cisco GUI / vpncli (required for CLI)..." -ForegroundColor Yellow
    Write-CiscoVpnBlockerReport

    $ciscoDir = Split-Path $VpnCliPath -Parent
    for ($round = 0; $round -lt 3; $round++) {
        foreach ($name in $script:CiscoVpnKillNames) {
            & taskkill.exe /IM "$name.exe" /F /T 2>$null | Out-Null
        }
        foreach ($p in Get-Process -Name 'vpncli','csc_ui','vpnui' -ErrorAction SilentlyContinue) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
        foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
            if ($p.Name -eq 'vpnagent') { continue }
            try {
                if ($p.Path -and $p.Path.StartsWith($ciscoDir, [StringComparison]::OrdinalIgnoreCase)) {
                    if ($script:CiscoVpnKillNames -contains $p.Name) {
                        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch { }
        }
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Name 'vpncli','csc_ui','vpnui' -ErrorAction SilentlyContinue)) { break }
    }

  # Final sweep (do not spawn vpncli here — that leaves a blocker process)
    & taskkill.exe /IM vpncli.exe /F /T 2>$null | Out-Null
    Start-Sleep -Seconds 1

    $still = Get-CiscoVpnBlockerProcesses
    if ($still.Count -gt 0) {
        Write-Host "[!!] Cisco Secure Client is still using the VPN." -ForegroundColor Red
        Write-CiscoVpnBlockerReport
        foreach ($p in $still) {
            try {
                $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction Stop
                if ($wmi.ParentProcessId -ne $PID) {
                    Write-Host "     Close parent window or run: Stop-Process -Id $($wmi.ParentProcessId) -Force" -ForegroundColor Yellow
                }
            } catch { }
        }
        Write-Host "     Right-click the Cisco icon in the system tray -> Quit / Exit." -ForegroundColor Red
        return $false
    }
    return $true
}

function Test-VpnAgentRunning {
    $serviceCandidates = @()
    try {
        $serviceCandidates = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
            ($_.Name -match 'vpnagent') -or
            ($_.DisplayName -match 'Cisco.*VPN Agent|Cisco Secure Client.*VPN Agent|AnyConnect.*VPN Agent') -or
            ($_.PathName -match 'vpnagent(d)?\.exe')
        })
    } catch {
        $serviceCandidates = @()
    }

    if ($serviceCandidates.Count -gt 0) {
        $runningService = $serviceCandidates | Where-Object { $_.State -eq 'Running' } | Select-Object -First 1
        if ($runningService) {
            return $true
        }
        $serviceNames = ($serviceCandidates | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName } else { $_.Name }
        }) -join ', '
        Write-Host "[!!] Cisco vpnagent service is not running. Start it or reinstall Cisco Secure Client." -ForegroundColor Red
        if ($serviceNames) {
            Write-Host "     Detected agent service(s): $serviceNames" -ForegroundColor Yellow
        }
        return $false
    }

    if (Get-Process -Name 'vpnagent' -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Host "[*] Could not verify Cisco vpnagent service by name; continuing." -ForegroundColor DarkGray
    return $true
}

# vpn-status: 优先检查 Cisco 隧道网卡，回退到 10.x.x.x IP / Cisco tunnel adapter first, then 10.x.x.x fallback
function Get-VpnStatus {
    if (Get-VpnTunnelAddress) {
        Write-Host "[OK] VPN connected" -ForegroundColor Green
        Show-VpnConnectionStatus
    } else {
        Write-Host "[!!] VPN not connected" -ForegroundColor Red
    }

    Write-Host ""
    Write-CiscoVpnBlockerReport
}

# vpn-connect helpers: prompt-driven vpncli session (reads stdout, responds to prompts)
function Get-VpnGroupSelection {
    param($Config)
    if ($Config.Group -eq "Library Resources Only") { return "1" }
    # Timed mode: numbered menu usually expects index; -Default- -> 0
    if ($Config.Group -eq "-Default-" -or [string]::IsNullOrWhiteSpace($Config.Group)) { return "0" }
    if ($Config.Group) { return [string]$Config.Group }
    return "0"
}

function Get-DuoCliInput {
    param(
        [string]$EffectiveDuo,
        [string]$TotpCode
    )
    switch ($EffectiveDuo) {
        "phone" { return "2" }
        "passcode" { return $TotpCode }
        default { return "1" }
    }
}

function Test-SupportedDuoMethod {
    param([string]$Method)
    return $Method -in @("push", "phone", "passcode")
}

function Normalize-DuoPushTarget {
    param([string]$Value)
    if (-not $Value) { return "" }
    $digits = ($Value -replace '\D', '')
    if (-not $digits) { return "" }
    $normalized = [int]$digits
    if ($normalized -le 0) { return "" }
    return [string]$normalized
}

function Get-DuoPushOptions {
    param([string]$Text)
    $options = @()
    if (-not $Text) { return $options }
    $normalized = $Text -replace "`r", ""
    $seenNumbers = @{}
    $patterns = @(
        '(?im)(?:^|\n)\s*([0-9]+)\s*[-.):]\s*([^\n]*(?:Push|push|Approve|approve|Duo Push|DUO Push)[^\n]*)',
        '(?im)(?:^|\n)\s*([0-9]+)\s+([^\n]*(?:Push|push|Approve|approve|Duo Push|DUO Push)[^\n]*)'
    )
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($normalized, $pattern)) {
            $number = $match.Groups[1].Value.Trim()
            $label = $match.Groups[2].Value.Trim()
            if (-not $number -or -not $label) { continue }
            if ($seenNumbers.ContainsKey($number)) { continue }
            $suffix = ""
            $digitMatches = [regex]::Matches($label, '[0-9]{4}')
            if ($digitMatches.Count -gt 0) {
                $suffix = $digitMatches[$digitMatches.Count - 1].Value
            }
            $options += [pscustomobject]@{
                Number = $number
                Label = $label
                Suffix = $suffix
            }
            $seenNumbers[$number] = $true
        }
    }
    return $options
}

function Write-DuoPushOptions {
    param($Options)
    if (-not $Options) { return }
    Write-Host "[*] Detected DUO push options:" -ForegroundColor Yellow
    foreach ($option in $Options) {
        Write-Host ("     [{0}] {1}" -f $option.Number, $option.Label) -ForegroundColor Gray
    }
}

function Get-DuoPromptDiagnostics {
    param(
        [string]$Text,
        [int]$MaxLines = 12,
        [string[]]$MaskValues = @()
    )
    if (-not $Text) { return "" }

    $lines = [regex]::Split($Text, "\r?\n") | Where-Object { $_ -and $_.Trim() }
    if (-not $lines -or $lines.Count -eq 0) { return "" }

    $interesting = @()
    foreach ($line in $lines) {
        if ($line -match 'Push|Phone|Passcode|Duo|DUO|MFA|Answer|答：|Approve|Call|push to|phone call|certificate|banner') {
            $interesting += $line.Trim()
        }
    }

    if ($interesting.Count -eq 0) {
        $interesting = @($lines | Select-Object -Last $MaxLines)
    } elseif ($interesting.Count -gt $MaxLines) {
        $interesting = @($interesting | Select-Object -Last $MaxLines)
    }

    return (Protect-VpnDiagnosticText -Text ($interesting -join "`n") -MaskValues $MaskValues)
}

function Write-DuoPromptDiagnostics {
    param(
        [string]$Text,
        [string[]]$MaskValues = @()
    )
    $diag = Get-DuoPromptDiagnostics -Text $Text -MaskValues $MaskValues
    if (-not $diag) { return }
    Write-Host "--- DUO prompt diagnostics ---" -ForegroundColor DarkGray
    Write-Host $diag -ForegroundColor DarkGray
}

function Get-VpnDiagnosticMaskValues {
    param(
        $Cred = $null,
        [string[]]$ExtraValues = @()
    )
    $values = @()
    if ($Cred) {
        if ($Cred.Username) { $values += [string]$Cred.Username }
        if ($Cred.Password) { $values += [string]$Cred.Password }
    }
    foreach ($value in @($ExtraValues)) {
        if ($value) { $values += [string]$value }
    }
    return @($values | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)
}

function Protect-VpnDiagnosticText {
    param(
        [string]$Text,
        [string[]]$MaskValues = @()
    )
    if (-not $Text) { return "" }

    $sanitized = [string]$Text
    foreach ($value in @($MaskValues)) {
        if (-not $value) { continue }
        $textValue = [string]$value
        if (-not $textValue.Trim()) { continue }
        $escaped = [regex]::Escape($textValue)
        $sanitized = [regex]::Replace(
            $sanitized,
            $escaped,
            '<masked>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    $fullWidthColon = [regex]::Escape([string][char]0xFF1A)
    $labelPattern = "(?im)^(\s*(?:username|user|password|passcode|otp|token|code)\s*(?::|$fullWidthColon)\s*)(.+)$"
    $sanitized = [regex]::Replace($sanitized, $labelPattern, '$1<masked>')
    $sanitized = [regex]::Replace(
        $sanitized,
        '(?<![A-Za-z0-9+/=_-])([A-Za-z0-9+/=_-]{24,})(?![A-Za-z0-9+/=_-])',
        '<masked-token>'
    )
    return $sanitized
}

function Get-RecentVpnMfaBuffer {
    param(
        [string]$Text,
        [int]$MaxLines = 0,
        [string[]]$MaskValues = @()
    )
    if (-not $Text) { return "" }

    if ($MaxLines -le 0) {
        $MaxLines = if ($env:VPN_DEBUG -eq '1') { 30 } else { 16 }
    }

    $lines = [regex]::Split($Text, "\r?\n") | Where-Object { $_ -ne $null -and $_.Trim() -ne "" }
    if (-not $lines -or $lines.Count -eq 0) { return "" }

    $recentLines = @($lines | Select-Object -Last $MaxLines)
    return (Protect-VpnDiagnosticText -Text ($recentLines -join "`n") -MaskValues $MaskValues)
}

function Write-RecentVpnMfaBuffer {
    param(
        [string]$Text,
        [int]$MaxLines = 0,
        [string[]]$MaskValues = @()
    )
    $recent = Get-RecentVpnMfaBuffer -Text $Text -MaxLines $MaxLines -MaskValues $MaskValues
    if (-not $recent) { return }
    Write-Host "--- recent vpncli MFA buffer ---" -ForegroundColor DarkGray
    Write-Host $recent -ForegroundColor DarkGray
}

function Get-CiscoLogDiagnostics {
    param(
        [string[]]$SearchPaths = $CiscoVpnLogSearchPaths,
        [int]$MaxFiles = 3,
        [int]$TailLines = 12,
        [string[]]$MaskValues = @()
    )

    $keywordPattern = '(?i)(mfa|duo|push|auth|login|certificate|failure|success|phone)'
    $existingPaths = @($SearchPaths | Where-Object { $_ -and (Test-Path $_ -PathType Container) } | Select-Object -Unique)
    if (-not $existingPaths -or $existingPaths.Count -eq 0) {
        return [pscustomobject]@{
            Status      = 'not-found'
            SearchPaths = @($SearchPaths)
            Files       = @()
            Lines       = @('No Cisco text log paths found.')
        }
    }

    $allFiles = @()
    foreach ($path in $existingPaths) {
        $allFiles += Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(log|txt)$' }
    }

    $recentFiles = @($allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxFiles)
    if (-not $recentFiles -or $recentFiles.Count -eq 0) {
        return [pscustomobject]@{
            Status      = 'no-files'
            SearchPaths = $existingPaths
            Files       = @()
            Lines       = @('Cisco log directories exist, but no recent .log/.txt files were found.')
        }
    }

    $lines = @()
    $foundKeyword = $false
    foreach ($file in $recentFiles) {
        $tail = @()
        try {
            $tail = @(Get-Content -Path $file.FullName -Tail $TailLines -ErrorAction Stop)
        } catch {
            $lines += ("{0} :: unreadable ({1})" -f $file.FullName, $_.Exception.Message)
            continue
        }

        $hits = @($tail | Where-Object { $_ -match $keywordPattern })
        if ($hits.Count -gt 0) {
            $foundKeyword = $true
            $lines += ("{0} :: matched MFA/auth keywords" -f $file.FullName)
            foreach ($hit in @($hits | Select-Object -Last ([Math]::Min($hits.Count, 8)))) {
                $lines += ("  {0}" -f $hit.Trim())
            }
        } else {
            $lines += ("{0} :: no obvious MFA keywords in last {1} lines" -f $file.FullName, $TailLines)
            foreach ($tailLine in $tail) {
                if ($tailLine -and $tailLine.Trim()) {
                    $lines += ("  {0}" -f $tailLine.Trim())
                }
            }
        }
    }

    return [pscustomobject]@{
        Status      = if ($foundKeyword) { 'hits' } else { 'tail' }
        SearchPaths = $existingPaths
        Files       = @($recentFiles | ForEach-Object {
            [pscustomobject]@{
                FullName      = $_.FullName
                LastWriteTime = $_.LastWriteTime
            }
        })
        Lines       = @((Protect-VpnDiagnosticText -Text ($lines -join "`n") -MaskValues $MaskValues) -split "\r?\n")
    }
}

function Write-CiscoLogDiagnostics {
    param(
        [string[]]$SearchPaths = $CiscoVpnLogSearchPaths,
        [string[]]$MaskValues = @(),
        [int]$MaxFiles = 3,
        [int]$TailLines = 12
    )
    $diag = Get-CiscoLogDiagnostics -SearchPaths $SearchPaths -MaskValues $MaskValues -MaxFiles $MaxFiles -TailLines $TailLines
    if (-not $diag) { return }

    Write-Host "--- Cisco log diagnostics ---" -ForegroundColor DarkGray
    if ($env:VPN_DEBUG -eq '1') {
        foreach ($path in @($diag.SearchPaths)) {
            if ($path) {
                Write-Host ("scan path: {0}" -f $path) -ForegroundColor DarkGray
            }
        }
        foreach ($file in @($diag.Files)) {
            if ($file.FullName) {
                Write-Host ("recent file: {0} ({1:yyyy-MM-dd HH:mm:ss})" -f $file.FullName, $file.LastWriteTime) -ForegroundColor DarkGray
            }
        }
    }
    foreach ($line in @($diag.Lines)) {
        if ($line -and $line.Trim()) {
            Write-Host $line -ForegroundColor DarkGray
        }
    }
}

function Select-DuoPushOption {
    param(
        $Options,
        [string]$ConfiguredTarget,
        [switch]$NonInteractive
    )
    if (-not $Options -or $Options.Count -eq 0) {
        return $null
    }
    if ($Options.Count -eq 1) {
        return $Options[0]
    }

    $normalizedTarget = Normalize-DuoPushTarget -Value $ConfiguredTarget
    if ($normalizedTarget) {
        $matched = @($Options | Where-Object { $_.Number -eq $normalizedTarget })
        if ($matched.Count -eq 1) {
            return $matched[0]
        }
        Write-Host "[!!] Configured DUO push target number $normalizedTarget did not match the current MFA menu." -ForegroundColor Red
        Write-DuoPushOptions -Options $Options
        return $null
    }

    Write-DuoPushOptions -Options $Options
    if ($NonInteractive) {
        Write-Host "[!!] Multiple DUO push targets detected. Set one with: vpn-config set push-target <menu-number>" -ForegroundColor Red
        return $null
    }

    Write-Host "[*] Multiple DUO push targets detected." -ForegroundColor Yellow
    Write-Host "    Optional setting: vpn-config set push-target <menu-number>" -ForegroundColor Gray
    Write-Host "    Use the Cisco DUO menu number, such as 1 for the first phone or 2 for the second." -ForegroundColor Gray
    Write-Host "    If you only have one approved phone on your account, you can leave this setting blank." -ForegroundColor Gray
    while ($true) {
        $choice = (Read-Host "Choose DUO push option number").Trim()
        if (-not $choice) { continue }
        $selected = @($Options | Where-Object { $_.Number -eq $choice })
        if ($selected.Count -eq 1) {
            return $selected[0]
        }
        $validNumbers = @($Options | ForEach-Object { $_.Number }) -join ", "
        Write-Host ("[!!] Invalid choice. Please enter one of: {0}" -f $validNumbers) -ForegroundColor Red
    }
}

function Get-VpnTunnelAddress {
    $ciscoAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq "Up" -and (
            $_.InterfaceDescription -match 'Cisco AnyConnect|Cisco Secure Client' -or
            $_.Name -match 'Cisco|AnyConnect'
        )
    }

    if ($ciscoAdapters) {
        $addr = $ciscoAdapters |
            Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -and
                $_.IPAddress -notmatch '^169\.254\.' -and
                $_.IPAddress -notmatch '^127\.'
            } |
            Select-Object -First 1
        if ($addr) { return $addr }
    }

    return Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Up" } |
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -match '^10\.' -and
            $_.IPAddress -notmatch '^169\.254\.'
        } |
        Select-Object -First 1
}

function Format-VpnSessionTimeSpan {
    param([TimeSpan]$TimeSpan)
    return "{0}:{1:00}:{2:00}" -f [int][Math]::Floor($TimeSpan.TotalHours), $TimeSpan.Minutes, $TimeSpan.Seconds
}

function Get-VpnSessionStatLine {
    param(
        [string]$Output,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Output, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ""
}

function Get-VpnSessionStats {
    $timing = @{
        Duration = ""
        Remaining = ""
        State = ""
        Server = ""
        ClientIP = ""
    }

    $latestStateFile = $CiscoVpnStateFiles |
        Where-Object { Test-Path $_ } |
        Get-Item -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestStateFile) {
        $durationSpan = (Get-Date) - $latestStateFile.LastWriteTime
        if ($durationSpan.TotalSeconds -lt 0) {
            $durationSpan = [TimeSpan]::Zero
        }
        $remainingSpan = [TimeSpan]::FromSeconds([Math]::Max(0, $VpnSessionLimitSeconds - [int][Math]::Floor($durationSpan.TotalSeconds)))
        $timing.Duration = Format-VpnSessionTimeSpan -TimeSpan $durationSpan
        $timing.Remaining = Format-VpnSessionTimeSpan -TimeSpan $remainingSpan
    }

    if (-not (Test-Path $VpnCliPath)) {
        return $timing
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $VpnCliPath
    $psi.Arguments = "-s"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $null
        $stderr = $null
        $proc.StandardInput.WriteLine("stats")
        $proc.StandardInput.WriteLine("exit")
        $proc.StandardInput.Flush()
        if (-not $proc.WaitForExit(10000)) {
            try { $proc.Kill() } catch { }
        }
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $output = "$stdout`n$stderr"

        $stats = @{
            Duration = Get-VpnSessionStatLine -Output $output -Patterns @(
                '持续时间：\s*([0-9:]+)',
                'Duration:\s*([0-9:]+)'
            )
            Remaining = Get-VpnSessionStatLine -Output $output -Patterns @(
                '剩余会话时间：\s*(.+)',
                '剩余时间：\s*(.+)',
                '剩余时长：\s*(.+)',
                '时间剩余：\s*(.+)',
                '时长剩余：\s*(.+)',
                'Remaining Session Time:\s*(.+)',
                'Remaining Time:\s*(.+)',
                'Session Time Remaining:\s*(.+)',
                'Time Remaining:\s*(.+)'
            )
            State = Get-VpnSessionStatLine -Output $output -Patterns @(
                '连接状态：\s*(.+)',
                'Connection State:\s*(.+)',
                '>>\s*state:\s*(.+)'
            )
            Server = Get-VpnSessionStatLine -Output $output -Patterns @(
                'Server Address：\s*(.+)',
                'Server Address:\s*(.+)'
            )
            ClientIP = Get-VpnSessionStatLine -Output $output -Patterns @(
                '客户端地址 \(IPv4\)：\s*(.+)',
                'Client Address \(IPv4\):\s*(.+)'
            )
        }

        foreach ($key in $stats.Keys) {
            if ($stats[$key]) {
                $timing[$key] = $stats[$key]
            }
        }
    } catch {
    } finally {
        if ($proc) {
            try { $proc.Dispose() } catch { }
        }
    }

    return $timing
}

function Show-VpnConnectionStatus {
    $vpnAdapter = Get-VpnTunnelAddress
    $stats = Get-VpnSessionStats
    $displayState = Resolve-VpnDisplayState -Stats $stats -Tunnel $vpnAdapter

    if ($vpnAdapter) {
        Write-Host "     IP: $($vpnAdapter.IPAddress)" -ForegroundColor Gray
        if ($vpnAdapter.InterfaceAlias) {
            Write-Host "     Adapter: $($vpnAdapter.InterfaceAlias)" -ForegroundColor Gray
        }
    } elseif ($stats.ClientIP) {
        Write-Host "     IP: $($stats.ClientIP)" -ForegroundColor Gray
    }
    if ($stats.Server) {
        Write-Host "     Server: $($stats.Server)" -ForegroundColor Gray
    }
    if ($stats.Duration) {
        Write-Host "     Duration: $($stats.Duration)" -ForegroundColor Gray
    }
    if ($stats.Remaining) {
        Write-Host "     Remaining: $($stats.Remaining)" -ForegroundColor Gray
    }
    if ($displayState) {
        Write-Host "     Connection State: $displayState" -ForegroundColor Gray
    }
}

function Resolve-VpnDisplayState {
    param(
        $Stats,
        $Tunnel = $null
    )

    $state = ""
    if ($Stats -and $Stats.State) {
        $state = [string]$Stats.State
    }
    if ($state -and $state -notmatch '^\s*Unknown\s*$') {
        return $state
    }

    $hasClientIp = $Stats -and $Stats.ClientIP -and $Stats.ClientIP -notmatch '^0\.0\.0\.0\s*$|^\s*$'
    if ($Tunnel -or $hasClientIp) {
        return "Connected"
    }
    return $state
}

function Test-VpnSessionConnected {
    $stats = Get-VpnSessionStats
    if (-not $stats) { return $false }

    if ($stats.State -match "(^|[^A-Za-z])(Connected|Established)($|[^A-Za-z])|已连接|已連線") {
        return $true
    }
    if ($stats.ClientIP -and $stats.ClientIP -notmatch "^0\.0\.0\.0\s*$|^\s*$") {
        return $true
    }
    return $false
}

function Test-VpnConnectedByIp {
    if (Get-VpnTunnelAddress) { return $true }
    return (Test-VpnSessionConnected)
}

function Write-VpnTunnelDiagnostics {
    param(
        $Session = $null,
        $CiscoAdapters = $null,
        $CiscoAddresses = $null,
        $TenAddresses = $null
    )

    Write-Host "--- VPN tunnel diagnostics ---" -ForegroundColor DarkGray

    $proc = $null
    if ($Session -and $Session.Process) { $proc = $Session.Process }
    if ($proc) {
        if ($proc.HasExited) {
            Write-Host "vpncli: exited (PID $($proc.Id), exit $($proc.ExitCode))" -ForegroundColor DarkGray
        } else {
            Write-Host "vpncli: running (PID $($proc.Id))" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "vpncli: unavailable" -ForegroundColor DarkGray
    }

    if ($null -eq $CiscoAdapters) {
        $CiscoAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.InterfaceDescription -match 'Cisco AnyConnect|Cisco Secure Client' -or
            $_.Name -match 'Cisco|AnyConnect'
        }
    }
    if ($null -eq $CiscoAddresses) {
        $CiscoAddresses = @()
        foreach ($adapter in @($CiscoAdapters)) {
            if ($adapter.ifIndex) {
                $CiscoAddresses += Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.IPAddress -and
                        $_.IPAddress -notmatch '^169\.254\.' -and
                        $_.IPAddress -notmatch '^127\.'
                    }
            }
        }
    }
    if ($null -eq $TenAddresses) {
        $TenAddresses = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" } |
            Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^10\.' -and $_.IPAddress -notmatch '^169\.254\.' }
    }

    if ($CiscoAdapters) {
        foreach ($adapter in @($CiscoAdapters)) {
            Write-Host "Cisco adapter: $($adapter.Name) | $($adapter.Status) | $($adapter.InterfaceDescription)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "Cisco adapter: not found" -ForegroundColor DarkGray
    }

    if ($CiscoAddresses) {
        foreach ($addr in @($CiscoAddresses)) {
            Write-Host "Cisco IPv4: $($addr.IPAddress)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "Cisco IPv4: none" -ForegroundColor DarkGray
    }

    if ($TenAddresses) {
        foreach ($addr in @($TenAddresses)) {
            Write-Host "10.x IPv4: $($addr.IPAddress)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "10.x IPv4: none" -ForegroundColor DarkGray
    }
}

function Get-VpnCliBufferText {
    param([System.Text.StringBuilder]$Buffer, $SyncRoot)
    [System.Threading.Monitor]::Enter($SyncRoot)
    try { return $Buffer.ToString() } finally { [System.Threading.Monitor]::Exit($SyncRoot) }
}

function Write-VpnCliTail {
    param([string]$Output, [switch]$Force)
    if (-not $Output) { return }
    if (-not $Force -and ($VerbosePreference -eq 'Continue' -or $env:VPN_DEBUG -eq '1')) { return }
    Write-Host "--- vpncli output ---" -ForegroundColor DarkGray
    Write-Host $Output -ForegroundColor DarkGray
}

function Test-VpnCliAuthFailed {
    param([string]$Text)
    if ($Text -match '答：\s*\n\s*>>\s*登录失败') {
        return $true
    }
    return $Text -match '登录失败|Login denied|Authentication failed|[Aa]ccess denied|invalid credentials'
}

function Wait-ForVpnPrompt {
    param(
        [System.Text.StringBuilder]$Buffer,
        $SyncRoot,
        [string]$Pattern,
        [int]$TimeoutSeconds = 30,
        [switch]$Optional
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $text = Get-VpnCliBufferText -Buffer $Buffer -SyncRoot $SyncRoot
        if ($text -match $Pattern) { return $true }
        Start-Sleep -Milliseconds 200
    }
    if ($Optional) { return $false }
    Write-Host "[!!] Timeout waiting for vpncli prompt (pattern: $Pattern)" -ForegroundColor Red
    if ($text) { Write-Host $text -ForegroundColor DarkGray }
    return $false
}

function Send-VpnCliLine {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Line,
        $Session = $null,
        [string]$StepLabel = ""
    )
    if ($Process.HasExited) {
        $tail = ""
        if ($Session -and $Session.Buffer) { $tail = $Session.Buffer.ToString() }
        $label = if ($StepLabel) { " ($StepLabel)" } else { "" }
        throw "vpncli exited before stdin write$label (exit $($Process.ExitCode)).`n$tail"
    }
    try {
        $Process.StandardInput.WriteLine($Line)
        $Process.StandardInput.Flush()
    } catch {
        $tail = ""
        if ($Session -and $Session.Buffer) { $tail = $Session.Buffer.ToString() }
        $stepSuffix = if ($StepLabel) { " ($StepLabel)" } else { "" }
        throw "stdin write failed${stepSuffix}: $_`n$tail"
    }
}

function Send-VpnCliLineIfAlive {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Line,
        $Session = $null,
        [string]$StepLabel = ""
    )
    if ($Process.HasExited) { return $false }
    try {
        Send-VpnCliLine -Process $Process -Line $Line -Session $Session -StepLabel $StepLabel
        return $true
    } catch {
        return $false
    }
}

# vpncli on Windows: stdout often only drains when read synchronously on the main thread (not background ReadLine).
function Get-VpnSessionText {
    param($Session)
    if ($Session.Sync) {
        return Get-VpnCliBufferText -Buffer $Session.Buffer -SyncRoot $Session.Sync
    }
    return $Session.Buffer.ToString()
}

# Read redirected pipes only after vpncli has exited. Reading while the process is
# still interactive can block on Windows even when no complete line is available.
function Drain-VpnCliOutputAfterExit {
    param($Session)
    $proc = $Session.Process
    if (-not $proc -or -not $proc.StandardOutput) { return }
    if (-not $proc.HasExited) { return }
    if ($Session.OutputDrained) { return }
    $buf = $Session.Buffer
    $echo = $Session.ShowOutput
    $readAny = $false
    foreach ($stream in @($proc.StandardOutput, $proc.StandardError)) {
        if (-not $stream) { continue }
        try {
            $text = $stream.ReadToEnd()
            if ($text) {
                [void]$buf.Append($text)
                if ($echo) { Write-Host -NoNewline $text }
                $readAny = $true
            }
        } catch { }
    }
    $Session.OutputDrained = $true
    if ($echo -and $readAny) { Write-Host "" }
}

function New-VpnCliSession {
    param([string]$CliPath, [bool]$ShowOutput)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CliPath
    $psi.Arguments = "-s"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $sync = New-Object object
    $buffer = New-Object System.Text.StringBuilder
    $outputTask = [System.Threading.Tasks.Task]::Run([Action]{
        try {
            while (-not $proc.HasExited) {
                $line = $proc.StandardOutput.ReadLine()
                if ($null -eq $line) { break }
                [System.Threading.Monitor]::Enter($sync)
                try { [void]$buffer.AppendLine($line) } finally { [System.Threading.Monitor]::Exit($sync) }
                if ($ShowOutput) { Write-Host $line }
            }
        } catch { }
    })
    $errorTask = [System.Threading.Tasks.Task]::Run([Action]{
        try {
            while (-not $proc.HasExited) {
                $line = $proc.StandardError.ReadLine()
                if ($null -eq $line) { break }
                [System.Threading.Monitor]::Enter($sync)
                try { [void]$buffer.AppendLine($line) } finally { [System.Threading.Monitor]::Exit($sync) }
                if ($ShowOutput) { Write-Host $line }
            }
        } catch { }
    })
    return @{
        Process    = $proc
        Buffer     = $buffer
        Sync       = $sync
        ShowOutput = $ShowOutput
        Tasks      = @($outputTask, $errorTask)
        OutputDrained = $false
    }
}

# Prompt-driven path disabled: vpncli does not write to redirected pipes on Windows.
# function Test-VpnCliBufferHasOutput { ... }

function Write-VpnConnectResult {
    param(
        [bool]$Connected,
        [string]$Output,
        [bool]$ShowCliOutput
    )
    if (-not $ShowCliOutput -and $Output) {
        Write-Host $Output -ForegroundColor DarkGray
    }
    $vpnAdapter = Get-VpnTunnelAddress

    if ($vpnAdapter) {
        Write-Host "[OK] VPN connected (IP: $($vpnAdapter.IPAddress))" -ForegroundColor Green
        return $true
    }
    if ($Connected -or ($Output -match 'Connected')) {
        Write-Host "[OK] VPN connected" -ForegroundColor Green
        return $true
    }
    if ($Output -match 'Login denied|Authentication failed|[Aa]ccess denied|登录失败|failed|ʧ') {
        Write-Host "[!!] Authentication failed" -ForegroundColor Red
        return $false
    }
    Write-Host "[??] Check output above (no VPN tunnel IP detected)" -ForegroundColor Yellow
    return $false
}

function Get-VpnResultMarker {
    param(
        [ValidateSet("CONNECTED", "DISCONNECTED", "FAILED", "TIMEOUT")]
        [string]$State
    )
    return "VPN_RESULT=$State"
}

function Write-VpnResultMarker {
    param(
        [ValidateSet("CONNECTED", "DISCONNECTED", "FAILED", "TIMEOUT")]
        [string]$State
    )
    Write-Host (Get-VpnResultMarker -State $State) -ForegroundColor DarkGray
}

function Wait-VpnStepOrDelay {
    param(
        $Session,
        [string]$Pattern,
        [int]$MaxSeconds,
        [switch]$WatchAuthFailure
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
        $text = Get-VpnSessionText -Session $Session
        if ($WatchAuthFailure -and (Test-VpnCliAuthFailed -Text $text)) { return 'auth-failed' }
        if ($text -match $Pattern) { return 'ok' }
        if ($Session.Process -and $Session.Process.HasExited) { return 'exited' }
        Start-Sleep -Milliseconds 200
    }
    return 'timeout'
}

function Wait-ForDuoPushOptions {
    param(
        $Session,
        [int]$MaxSeconds = 18
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
        $text = Get-VpnSessionText -Session $Session
        $options = @(Get-DuoPushOptions -Text $text)
        if ($options.Count -gt 0) {
            return $options
        }
        if ($Session.Process -and $Session.Process.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    return @()
}

function Wait-ForVpnIpAfterExit {
    param(
        [int]$MaxSeconds = 20,
        [int]$PollMilliseconds = 300
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
        if (Test-VpnConnectedByIp) { return $true }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    return (Test-VpnConnectedByIp)
}

function Wait-ForVpnTunnelAfterMfa {
    param(
        $Session,
        [int]$MaxSeconds = 50,
        [int]$PollMilliseconds = 300,
        [int]$BannerFirstSendSeconds = 4,
        [int]$ResendSeconds = 5
    )
    $proc = $Session.Process
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastSendSecond = -1
    $acceptLogWritten = $false
    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
        if (Test-VpnConnectedByIp) { return $true }
        if ($proc -and $proc.HasExited) {
            Write-Host "[..] vpncli exited after MFA/banner wait; checking tunnel IP for 20s..." -ForegroundColor DarkGray
            return (Wait-ForVpnIpAfterExit -MaxSeconds 20 -PollMilliseconds $PollMilliseconds)
        }
        $elapsedWholeSeconds = [int][Math]::Floor($sw.Elapsed.TotalSeconds)
        if ($elapsedWholeSeconds -ge $BannerFirstSendSeconds -and
            ($lastSendSecond -lt 0 -or ($elapsedWholeSeconds - $lastSendSecond) -ge $ResendSeconds)) {
            if (-not $acceptLogWritten) {
                Write-Host "[6/6] Accepting banner/certificate (if prompted)..." -ForegroundColor Gray
                $acceptLogWritten = $true
            }
            [void](Send-VpnCliLineIfAlive -Process $proc -Line "y" -Session $Session -StepLabel 'banner-certificate')
            $lastSendSecond = $elapsedWholeSeconds
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    return (Test-VpnConnectedByIp)
}

# Read stdout only AFTER all stdin sent (reading during vpncli prompts blocks on Windows).
function Read-VpnCliOutputFinal {
    param(
        $Session,
        [int]$MaxSeconds = 15
    )
    $proc = $Session.Process
    if (-not $proc) { return }
    if (-not $proc.HasExited) {
        [void]$proc.WaitForExit($MaxSeconds * 1000)
    }
    Drain-VpnCliOutputAfterExit -Session $Session
}

function Stop-VpnCliForFailureAndDrain {
    param($Session)
    $proc = $Session.Process
    if (-not $proc) { return }
    if (-not $proc.HasExited) {
        Write-Host "[..] vpncli still running after tunnel wait; stopping it to capture final output..." -ForegroundColor DarkGray
        try { $proc.Kill() } catch { }
        try { [void]$proc.WaitForExit(3000) } catch { }
    }
    Drain-VpnCliOutputAfterExit -Session $Session
}

function Complete-VpnConnectTimed {
    param(
        $Session,
        [bool]$Connected,
        [bool]$ShowCliOutput,
        [int]$ReadSeconds = 15,
        [switch]$PushPath,
        [string[]]$DiagnosticMaskValues = @()
    )
    Read-VpnCliOutputFinal -Session $Session -MaxSeconds $ReadSeconds
    $output = Get-VpnSessionText -Session $Session
    if (Test-VpnCliAuthFailed -Text $output) {
        if ($output -match '答：\s*\r?\n\s*>>\s*登录失败|MFA option field') {
            Write-Host "[!!] DUO/MFA input missed (empty answer). Retry vpn-connect and approve push promptly." -ForegroundColor Red
        } else {
            Write-Host "[!!] Login failed. Update credentials: vpn-config set user <netid>" -ForegroundColor Red
        }
        if ($PushPath) {
            Write-DuoPromptDiagnostics -Text $output -MaskValues $DiagnosticMaskValues
            Write-RecentVpnMfaBuffer -Text $output -MaskValues $DiagnosticMaskValues
        }
        Write-CiscoLogDiagnostics -MaskValues $DiagnosticMaskValues
        Write-VpnCliTail -Output $output -Force
        return @{ Connected = $false; CertAccepted = $false; AuthFailed = $true }
    }
    if (Test-VpnConnectedByIp) { $Connected = $true }
    $Connected = Write-VpnConnectResult -Connected $Connected -Output $output -ShowCliOutput $ShowCliOutput
    if (-not $Connected) {
        Stop-VpnCliForFailureAndDrain -Session $Session
        $output = Get-VpnSessionText -Session $Session
        if ($PushPath) {
            Write-DuoPromptDiagnostics -Text $output -MaskValues $DiagnosticMaskValues
            Write-RecentVpnMfaBuffer -Text $output -MaskValues $DiagnosticMaskValues
        }
        Write-VpnTunnelDiagnostics -Session $Session
        Write-CiscoLogDiagnostics -MaskValues $DiagnosticMaskValues
        Write-VpnCliTail -Output $output -Force
    }
    return @{ Connected = $Connected; CertAccepted = $true; AuthFailed = $false }
}

# Timed stdin only between steps; collect vpncli text once at the end (initial-release pattern).
function Invoke-VpnConnectTimed {
    param(
        $Session,
        [string]$ConnectAddr,
        $Cred,
        $Config,
        [string]$DuoInputFallback,
        [string]$EffectiveDuo,
        [string]$ConfiguredPushTarget,
        [switch]$NonInteractiveMfa,
        [bool]$ShowCliOutput
    )
    $proc = $Session.Process
    $connected = $false
    $diagnosticMaskValues = Get-VpnDiagnosticMaskValues -Cred $Cred

    # Fixed delays between stdin writes (vpncli on Windows does not expose prompts on stdout).
    # After MFA input, keep banner/cert acceptance active while polling for the tunnel.
    Start-Sleep -Seconds 2

    Write-Host "[1/6] Connecting to $ConnectAddr..." -ForegroundColor Gray
    Send-VpnCliLine -Process $proc -Line "connect $ConnectAddr" -Session $Session -StepLabel 'connect'
    Start-Sleep -Seconds 5

    $groupSel = Get-VpnGroupSelection -Config $Config
    Write-Host "[2/6] Selecting group ($groupSel)..." -ForegroundColor Gray
    Send-VpnCliLine -Process $proc -Line $groupSel -Session $Session -StepLabel 'group'
    Start-Sleep -Seconds 2

    Write-Host "[3/6] Sending username ($($Cred.Username))..." -ForegroundColor Gray
    Send-VpnCliLine -Process $proc -Line $Cred.Username -Session $Session -StepLabel 'username'
    Start-Sleep -Seconds 2

    Write-Host "[4/6] Sending password..." -ForegroundColor Gray
    Send-VpnCliLine -Process $proc -Line $Cred.Password -Session $Session -StepLabel 'password'
    Start-Sleep -Seconds 6

    if ($proc.HasExited) {
        Read-VpnCliOutputFinal -Session $Session -MaxSeconds 8
        $outputAfterPwd = Get-VpnSessionText -Session $Session
        Write-Host "[!!] vpncli exited after password (exit $($proc.ExitCode))." -ForegroundColor Red
        Write-DuoPromptDiagnostics -Text $outputAfterPwd -MaskValues $diagnosticMaskValues
        Write-RecentVpnMfaBuffer -Text $outputAfterPwd -MaskValues $diagnosticMaskValues
        Write-CiscoLogDiagnostics -MaskValues $diagnosticMaskValues
        Write-VpnCliTail -Output $outputAfterPwd -Force
        return @{ Connected = $false; CertAccepted = $false; AuthFailed = $true }
    }

    Write-Host "[5/6] Waiting for MFA prompt..." -ForegroundColor Gray
    Start-Sleep -Seconds 8

    $duoInput = $null
    if ($EffectiveDuo -eq "push") {
        $pushOptions = @(Wait-ForDuoPushOptions -Session $Session -MaxSeconds 12)
        if ($pushOptions.Count -gt 0) {
            $selectedPush = Select-DuoPushOption -Options $pushOptions -ConfiguredTarget $ConfiguredPushTarget -NonInteractive:$NonInteractiveMfa
            if (-not $selectedPush) {
                $selectionDiag = Get-VpnSessionText -Session $Session
                Write-DuoPromptDiagnostics -Text $selectionDiag -MaskValues $diagnosticMaskValues
                Write-RecentVpnMfaBuffer -Text $selectionDiag -MaskValues $diagnosticMaskValues
                Write-CiscoLogDiagnostics -MaskValues $diagnosticMaskValues
                return @{ Connected = $false; CertAccepted = $false; AuthFailed = $false }
            }
            $duoInput = $selectedPush.Number
            Write-Host "[*] Selected DUO push option [$($selectedPush.Number)]" -ForegroundColor Gray
        } else {
            $duoDiagText = Get-VpnSessionText -Session $Session
            if ($ConfiguredPushTarget) {
                Write-Host "[!!] Could not detect the DUO push menu, so the configured push target '$ConfiguredPushTarget' could not be matched." -ForegroundColor Yellow
                if ($duoDiagText -and $duoDiagText.Trim()) {
                    Write-DuoPromptDiagnostics -Text $duoDiagText -MaskValues $diagnosticMaskValues
                    Write-RecentVpnMfaBuffer -Text $duoDiagText -MaskValues $diagnosticMaskValues
                } else {
                    Write-Host "[..] No vpncli MFA menu text was captured before fallback; vpncli may not expose the menu on this machine." -ForegroundColor DarkGray
                }
                Write-Host "[..] Falling back to the default DUO push option (1)." -ForegroundColor Yellow
            } elseif ($duoDiagText) {
                Write-DuoPromptDiagnostics -Text $duoDiagText -MaskValues $diagnosticMaskValues
            }
            Write-Host "[..] No explicit DUO push menu detected; defaulting to option 1." -ForegroundColor DarkGray
            $duoInput = Get-DuoCliInput -EffectiveDuo $EffectiveDuo
        }
    } else {
        $duoInput = $DuoInputFallback
    }

    Write-Host "[5/6] Sending DUO option ($DuoInput)..." -ForegroundColor Gray
    Send-VpnCliLine -Process $proc -Line $DuoInput -Session $Session -StepLabel 'duo'

    if ($EffectiveDuo -ne "passcode") {
        Write-Host "[>>] Waiting for DUO approval (up to 50s)..." -ForegroundColor Yellow
    }

    if ($connected -or (Test-VpnConnectedByIp)) {
        return Complete-VpnConnectTimed -Session $Session -Connected $true -ShowCliOutput $ShowCliOutput -ReadSeconds 6 -PushPath:($EffectiveDuo -eq "push") -DiagnosticMaskValues $diagnosticMaskValues
    }

    if ($proc.HasExited) {
        return Complete-VpnConnectTimed -Session $Session -Connected $connected -ShowCliOutput $ShowCliOutput -ReadSeconds 8 -PushPath:($EffectiveDuo -eq "push") -DiagnosticMaskValues $diagnosticMaskValues
    }

    $connected = Wait-ForVpnTunnelAfterMfa -Session $Session -MaxSeconds 50 -PollMilliseconds 300 -BannerFirstSendSeconds 4 -ResendSeconds 5

    return Complete-VpnConnectTimed -Session $Session -Connected $connected -ShowCliOutput $ShowCliOutput -ReadSeconds 10 -PushPath:($EffectiveDuo -eq "push") -DiagnosticMaskValues $diagnosticMaskValues
}

# Invoke-VpnConnectPrompted removed: vpncli does not expose prompts on redirected stdout (Windows).

function Stop-VpnCliSession {
    param($Session, [bool]$Connected)
    $proc = $Session.Process
    if (-not $proc -or $proc.HasExited) { return }
    try {
        if ($Connected) {
            try { Send-VpnCliLine -Process $proc -Line "exit" -Session $Session -StepLabel 'exit' } catch { }
            if (-not $proc.WaitForExit(3000)) { $proc.Kill() }
        } else {
            $proc.Kill()
        }
    } catch { }
    finally {
        try { $proc.Dispose() } catch { }
    }
}

# vpn-connect: 自动连接 VPN (6 步交互) / Auto-connect VPN (prompt-driven vpncli interaction)
# 1. 连接服务器  2. 选择分组  3. 发送用户名  4. 发送密码  5. DUO 验证  6. 接受证书
function Connect-Vpn {
    # 优先使用活跃 Profile，回退到旧版配置 / Try active profile first, fall back to legacy config
    $cred = Load-ActiveProfileCredentials
    if (-not $cred) { $cred = Load-VpnCredentials }
    if (-not $cred) {
        Write-VpnResultMarker -State FAILED
        return
    }

    $config = Load-ActiveProfileConfig
    if (-not $config) { $config = Load-Config }
    $server = $cred.Server

    $existingTunnel = Get-VpnTunnelAddress
    if ($existingTunnel) {
        Write-Host "[OK] VPN already connected" -ForegroundColor Green
        Show-VpnConnectionStatus
        Write-VpnResultMarker -State CONNECTED
        return
    }

    if (-not (Test-VpnAgentRunning)) {
        Write-VpnResultMarker -State FAILED
        return
    }

    if (-not (Stop-CiscoClientBlockers)) {
        Write-VpnResultMarker -State FAILED
        return
    }

    # Resolve DUO method: explicit param > config saved value > default "push"
    $effectiveDuo = $DuoMethod
    if (-not $PSBoundParameters.ContainsKey('DuoMethod') -and $config.DuoMethod) {
        $effectiveDuo = $config.DuoMethod
    }
    if (-not (Test-SupportedDuoMethod -Method $effectiveDuo)) {
        Write-Host "[!!] Unsupported DUO method '$effectiveDuo'. Supported methods: push, phone, passcode" -ForegroundColor Red
        Write-Host "     If this came from saved config, run: vpn-config set duo push" -ForegroundColor Yellow
        Write-VpnResultMarker -State FAILED
        return
    }

    Write-Host "[->] Connecting to: $server" -ForegroundColor Cyan
    Write-Host "     User: $($cred.Username)" -ForegroundColor Gray
    Write-Host "     DUO method: $effectiveDuo" -ForegroundColor Gray
    $configuredPushTarget = Normalize-DuoPushTarget -Value $config.DuoPushTarget
    if ($configuredPushTarget) {
        Write-Host "     Push target: menu $configuredPushTarget" -ForegroundColor Gray
    } elseif ($effectiveDuo -eq "push") {
        Write-Host "     Push target: (blank, auto; optional if only one DUO phone)" -ForegroundColor DarkGray
    }

    # Determine DUO second factor input (push is resolved from the live MFA menu if needed).
    $totpForDuo = $null
    if ($effectiveDuo -eq "passcode") {
        $totpForDuo = Get-TOTPCode
        if ($totpForDuo) {
            Write-Host "     TOTP code: $totpForDuo" -ForegroundColor Gray
        } else {
            Write-Host "[!!] TOTP secret not found. Run: vpn-config totp" -ForegroundColor Red
            Write-VpnResultMarker -State FAILED
            return
        }
    }
    $duoInput = Get-DuoCliInput -EffectiveDuo $effectiveDuo -TotpCode $totpForDuo

    $showCliOutput = ($VerbosePreference -eq 'Continue') -or ($env:VPN_DEBUG -eq '1')

    if (-not (Test-Path $VpnCliPath)) {
        Write-Host "[!!] vpncli not found: $VpnCliPath" -ForegroundColor Red
        Write-VpnResultMarker -State FAILED
        return
    }

    Write-Host "[..] Connecting..." -ForegroundColor Yellow
    Write-Host "[*] Automated mode: do not type here; script sends all vpncli input." -ForegroundColor DarkGray
    if ($showCliOutput) {
        Write-Host "[*] VPN_DEBUG: vpncli log prints after steps complete (mid-connect read would block)." -ForegroundColor DarkGray
    }

    $connectAddr = $server
    if ($config.Port -and $config.Port -ne "443") {
        $connectAddr = "${server}:$($config.Port)"
    }

    $session = $null
    $connected = $false
    $resultMarkerWritten = $false

    try {
        $session = New-VpnCliSession -CliPath $VpnCliPath -ShowOutput $showCliOutput
        $connectParams = @{
            Session       = $session
            ConnectAddr   = $connectAddr
            Cred          = $cred
            Config        = $config
            DuoInputFallback = $duoInput
            EffectiveDuo  = $effectiveDuo
            ConfiguredPushTarget = $configuredPushTarget
            NonInteractiveMfa = $NonInteractiveMfa
            ShowCliOutput = $showCliOutput
        }
        $result = Invoke-VpnConnectTimed @connectParams
        $connected = $result.Connected
    } catch {
        $errorText = $_.Exception.Message
        if (-not $errorText) { $errorText = "$_" }
        $diagnosticMaskValues = Get-VpnDiagnosticMaskValues -Cred $cred
        if ($session -and $errorText -match 'vpncli exited before stdin write \(group\)') {
            Read-VpnCliOutputFinal -Session $session -MaxSeconds 3
            $earlyOutput = Get-VpnSessionText -Session $session
            Write-DuoPromptDiagnostics -Text $earlyOutput -MaskValues $diagnosticMaskValues
            Write-RecentVpnMfaBuffer -Text $earlyOutput -MaskValues $diagnosticMaskValues
            Write-CiscoLogDiagnostics -MaskValues $diagnosticMaskValues
            Write-VpnCliTail -Output $earlyOutput -Force
            Write-Host "[!!] vpncli could not reach the server. Check: network, DNS, vpnagent service." -ForegroundColor Red
        }
        Write-Host "[!!] Error: $errorText" -ForegroundColor Red
        Write-VpnResultMarker -State FAILED
        $resultMarkerWritten = $true
    } finally {
        if ($session) {
            Stop-VpnCliSession -Session $session -Connected $connected
        }
    }
    if (-not $resultMarkerWritten) {
        if ($connected) {
            Write-VpnResultMarker -State CONNECTED
        } else {
            Write-VpnResultMarker -State FAILED
        }
    }
}

# vpn-disconnect: 断开 VPN 并重启 GUI 客户端 / Disconnect VPN and restart GUI client
function Disconnect-Vpn {
    Write-Host "[x] Disconnecting VPN..." -ForegroundColor Cyan
    Invoke-VpnCliDisconnectQuiet
    & taskkill.exe /IM vpncli.exe /F /T 2>$null | Out-Null
    Write-Host "[OK] Disconnected" -ForegroundColor Green
    Write-VpnResultMarker -State DISCONNECTED

    # Restart GUI client if it was killed during connect
    $guiPath = "C:\Program Files (x86)\Cisco\Cisco Secure Client\csc_ui.exe"
    if (Test-Path $guiPath) {
        Start-Process $guiPath
        if ($env:VPN_DEBUG -eq '1') {
            Write-Host "[*] GUI client restarted" -ForegroundColor Gray
        }
    }
}

# ---------- Main Logic ----------

if ($LoadFunctionsOnly) { return }

# One-time legacy migration (root files -> profiles/default)
Migrate-LegacyConfigIfNeeded

if ($Reconfigure -or $Reset) {
    # Full reset: clear legacy + all profiles + TOTP
    Remove-Item $ConfigFile -Force -ErrorAction SilentlyContinue
    Remove-Item $CredFile -Force -ErrorAction SilentlyContinue
    Remove-Item $TotpFile -Force -ErrorAction SilentlyContinue
    if (Test-Path $ProfilesDir) { Remove-Item $ProfilesDir -Recurse -Force }
    Remove-Item $ProfilesIndex -Force -ErrorAction SilentlyContinue
    Remove-Item $ActiveProfileFile -Force -ErrorAction SilentlyContinue
    Write-Host "[*] All configuration cleared." -ForegroundColor Yellow
    if ($Reset) { exit 0 }
    # $Reconfigure continues to interactive setup
}

# ---------- Profile Commands ----------
if ($Add) {
    Add-VpnProfile
    exit 0
}
if ($Ls) {
    # Alias: vpn-ls -> vpn-config -Brief
    Show-Config -Brief
    exit 0
}
if ($Config) {
    if ($Brief) {
        Show-Config -Brief
    } else {
        Show-Config
    }
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
    Write-Host "  vpn-gui          " -NoNewline; Write-Host "-> Launch GUI manager" -ForegroundColor Gray
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Configuration (vpn-config):" -ForegroundColor Yellow
    Write-Host "  vpn-config              " -NoNewline; Write-Host "-> Show all settings" -ForegroundColor Gray
    Write-Host "  vpn-config list         " -NoNewline; Write-Host "-> List all profiles" -ForegroundColor Gray
    Write-Host "  vpn-config add          " -NoNewline; Write-Host "-> Add new profile" -ForegroundColor Gray
    Write-Host "  vpn-config use <name>   " -NoNewline; Write-Host "-> Switch active profile" -ForegroundColor Gray
    Write-Host "  vpn-config set <k> <v>  " -NoNewline; Write-Host "-> Quick setting change" -ForegroundColor Gray
    Write-Host "  vpn-config totp         " -NoNewline; Write-Host "-> Save TOTP secret" -ForegroundColor Gray
    Write-Host "  vpn-config rm <name>    " -NoNewline; Write-Host "-> Remove a profile" -ForegroundColor Gray
    Write-Host "  vpn-config reset-all    " -NoNewline; Write-Host "-> Full reset and reconfigure" -ForegroundColor Gray
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
    Write-Host "CONFIGURATION (vpn-config subcommands):" -ForegroundColor Yellow
    Write-Host "  vpn-config                 Show all settings"
    Write-Host "  vpn-config list            List all profiles"
    Write-Host "  vpn-config add             Add new VPN profile"
    Write-Host "  vpn-config use <name>      Switch active profile"
    Write-Host "  vpn-config set <k> <v>     Change a single setting"
    Write-Host "    Keys: server, group, port, protocol, user, duo, push-target"
    Write-Host "  vpn-config totp            Save / update TOTP secret"
    Write-Host "  vpn-config rm <name>       Remove a profile"
    Write-Host "  vpn-config reset-all       Full reset and re-setup"
    Write-Host ""
    Write-Host "DUO METHODS:" -ForegroundColor Yellow
    Write-Host "  push       (default) Send push notification to phone"
    Write-Host "  phone      Call your phone for verification"
    Write-Host "  passcode   Auto-generate TOTP code (fully automatic)"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\vpn-auto-connect.ps1                          # First setup"
    Write-Host "  .\vpn-auto-connect.ps1 -Connect                 # Connect (DUO push)"
    Write-Host "  .\vpn-auto-connect.ps1 -Connect -DuoMethod passcode  # Full auto"
    Write-Host ""
    Write-Host "GLOBAL COMMANDS:" -ForegroundColor Yellow
    Write-Host "  vpn              List all available commands"
    Write-Host "  vpn-connect      Connect (DUO push)"
    Write-Host "  vpn-disconnect   Disconnect"
    Write-Host "  vpn-status       Show status"
    Write-Host "  vpn-gui          Launch GUI manager"
    Write-Host ""
    Write-Host "CONFIGURATION (vpn-config):" -ForegroundColor Yellow
    Write-Host "  vpn-config                 Show all settings"
    Write-Host "  vpn-config list            List all profiles"
    Write-Host "  vpn-config add             Add new profile"
    Write-Host "  vpn-config use <name>      Switch active profile"
    Write-Host "  vpn-config set <k> <v>     Quick setting change"
    Write-Host "  vpn-config totp            Save TOTP secret"
    Write-Host "  vpn-config rm <name>       Remove a profile"
    Write-Host "  vpn-config reset-all       Full reset and reconfigure"
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
