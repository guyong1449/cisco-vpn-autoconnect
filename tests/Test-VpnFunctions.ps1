# Test-VpnFunctions.ps1 - Standalone unit tests for vpn-auto-connect.ps1
# Usage: powershell -ExecutionPolicy Bypass -File tests\Test-VpnFunctions.ps1
# No external dependencies required.

$script:Pass = 0
$script:Fail = 0
$script:Tests = @()

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -eq $Expected) {
        $script:Pass++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  [FAIL] $Name - Expected: '$Expected', Got: '$Actual'" -ForegroundColor Red
    }
}

function Assert-True {
    param($Condition, [string]$Name)
    if ($Condition) {
        $script:Pass++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  [FAIL] $Name - Condition was false" -ForegroundColor Red
    }
}

function Assert-Match {
    param([string]$Actual, [string]$Pattern, [string]$Name)
    if ($Actual -match $Pattern) {
        $script:Pass++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  [FAIL] $Name - '$Actual' does not match '$Pattern'" -ForegroundColor Red
    }
}

# ============================================================
Write-Host "`n=== TOTP Code Generation ===" -ForegroundColor Cyan
# ============================================================

$base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
$secret = "JBSWY3DPEHPK3PXP".ToUpper().TrimEnd('=')
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

$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$counter = [math]::Floor($epoch / 30)

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
$totp = ($code % 1000000).ToString().PadLeft(6, '0')

Assert-Match $totp '^\d{6}$' "TOTP is 6 digits"
Assert-Equal $totp.Length 6 "TOTP length is 6"

# Consistency check
$hmac2 = New-Object System.Security.Cryptography.HMACSHA1
$hmac2.Key = $bytes
$counterBytes2 = [BitConverter]::GetBytes([int64]$counter)
if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counterBytes2) }
$hash2 = $hmac2.ComputeHash($counterBytes2)
$offset2 = $hash2[$hash2.Length - 1] -band 0x0F
$code2 = (($hash2[$offset2] -band 0x7F) -shl 24) -bor
         (($hash2[$offset2 + 1] -band 0xFF) -shl 16) -bor
         (($hash2[$offset2 + 2] -band 0xFF) -shl 8) -bor
         ($hash2[$offset2 + 3] -band 0xFF)
$totp2 = ($code2 % 1000000).ToString().PadLeft(6, '0')

Assert-Equal $totp $totp2 "TOTP consistent within same time window"

# ============================================================
Write-Host "`n=== DuoMethod Resolution ===" -ForegroundColor Cyan
# ============================================================

# Test 1: Explicit param overrides config
$DuoMethod = "passcode"
$PSBoundParameters = @{ DuoMethod = "passcode" }
$config = @{ DuoMethod = "phone" }
$effectiveDuo = $DuoMethod
if (-not $PSBoundParameters.ContainsKey('DuoMethod') -and $config.DuoMethod) {
    $effectiveDuo = $config.DuoMethod
}
Assert-Equal $effectiveDuo "passcode" "Explicit param overrides config"

# Test 2: Config value used when no explicit param
$DuoMethod = "push"
$PSBoundParameters = @{}
$config = @{ DuoMethod = "phone" }
$effectiveDuo = $DuoMethod
if (-not $PSBoundParameters.ContainsKey('DuoMethod') -and $config.DuoMethod) {
    $effectiveDuo = $config.DuoMethod
}
Assert-Equal $effectiveDuo "phone" "Config value used when no explicit param"

# Test 3: Default push when no config and no param
$DuoMethod = "push"
$PSBoundParameters = @{}
$config = @{}
$effectiveDuo = $DuoMethod
if (-not $PSBoundParameters.ContainsKey('DuoMethod') -and $config.DuoMethod) {
    $effectiveDuo = $config.DuoMethod
}
Assert-Equal $effectiveDuo "push" "Default push when no config and no param"

# Test 4: Method to vpncli input mapping
$map = @{ "push" = "1"; "phone" = "2"; "sms" = "3" }
foreach ($method in $map.Keys) {
    $duoInput = "1"
    if ($method -eq "phone") { $duoInput = "2" }
    elseif ($method -eq "sms") { $duoInput = "3" }
    Assert-Equal $duoInput $map[$method] "Method '$method' maps to vpncli input '$($map[$method])'"
}

# ============================================================
Write-Host "`n=== Legacy Migration Logic ===" -ForegroundColor Cyan
# ============================================================

$testDir = Join-Path $env:TEMP "vpn-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

try {
    # Test: migration should happen when legacy exists and no profiles
    $configFile = Join-Path $testDir "config.json"
    $credFile = Join-Path $testDir "credentials.xml"
    @{ Server = "test.vpn.com"; Group = "Default"; Port = "443"; Protocol = "ssl" } |
        ConvertTo-Json | Set-Content $configFile
    @{ Server = "test.vpn.com"; Username = "testuser"; Password = "encrypted" } |
        ConvertTo-Json | Set-Content $credFile

    $hasLegacy = (Test-Path $configFile) -or (Test-Path $credFile)
    Assert-True $hasLegacy "Legacy files detected"

    # Simulate migration
    $profileDir = Join-Path $testDir "profiles\default"
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Copy-Item $configFile "$profileDir\config.json" -Force
    Copy-Item $credFile "$profileDir\credentials.xml" -Force

    Assert-True (Test-Path "$profileDir\config.json") "Config migrated to profiles/default"
    Assert-True (Test-Path "$profileDir\credentials.xml") "Credentials migrated to profiles/default"
    $migratedConfig = Get-Content "$profileDir\config.json" -Raw | ConvertFrom-Json
    Assert-Equal $migratedConfig.Server "test.vpn.com" "Migrated server matches"

    # Test: migration should NOT happen when profiles exist
    $testDir2 = Join-Path $env:TEMP "vpn-test2-$(Get-Random)"
    New-Item -ItemType Directory -Path $testDir2 -Force | Out-Null
    @{ Server = "test.vpn.com" } | ConvertTo-Json | Set-Content (Join-Path $testDir2 "config.json")
    @("existing") | ConvertTo-Json | Set-Content (Join-Path $testDir2 "profiles.json")

    $index = Get-Content (Join-Path $testDir2 "profiles.json") -Raw | ConvertFrom-Json
    $hasLegacy2 = (Test-Path (Join-Path $testDir2 "config.json"))
    $shouldMigrate = $index.Count -eq 0 -and $hasLegacy2
    Assert-True (-not $shouldMigrate) "Should NOT migrate when profiles exist"
    Remove-Item $testDir2 -Recurse -Force -ErrorAction SilentlyContinue

} finally {
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
Write-Host "`n=== vpn-connect.cmd Parameter Binding ===" -ForegroundColor Cyan
# ============================================================

$cmdPath = Join-Path $PSScriptRoot "..\cmd\vpn-connect.cmd"
if (Test-Path $cmdPath) {
    $cmdContent = Get-Content $cmdPath -Raw
    Assert-Match $cmdContent '-DuoMethod %1' "vpn-connect.cmd forwards DuoMethod"
    Assert-Match $cmdContent 'if.*%~1.*==' "vpn-connect.cmd checks for empty arg"
} else {
    Write-Host "  [SKIP] vpn-connect.cmd not found" -ForegroundColor Yellow
}

# ============================================================
Write-Host "`n=== Command Consolidation ===" -ForegroundColor Cyan
# ============================================================

$cmdDir = Join-Path $PSScriptRoot "..\cmd"

# vpn-config.cmd should be a subcommand router
$configCmd = Get-Content (Join-Path $cmdDir "vpn-config.cmd") -Raw
Assert-Match $configCmd 'list' "vpn-config.cmd has 'list' subcommand"
Assert-Match $configCmd 'add' "vpn-config.cmd has 'add' subcommand"
Assert-Match $configCmd 'reset-all' "vpn-config.cmd has 'reset-all' subcommand"
Assert-Match $configCmd '-Brief' "vpn-config.cmd routes 'list' to -Brief"
Assert-Match $configCmd '-Reconfigure' "vpn-config.cmd routes 'reset-all' to -Reconfigure"
Assert-Match $configCmd 'Unknown subcommand' "vpn-config.cmd rejects unknown subcommands"

# All deprecated cmds should show deprecation and reference vpn-config
$deprecatedCmds = @(
    @{ File = "vpn-setup.cmd";   NewCmd = "vpn-config add" }
    @{ File = "vpn-add.cmd";     NewCmd = "vpn-config add" }
    @{ File = "vpn-ls.cmd";      NewCmd = "vpn-config list" }
    @{ File = "vpn-reconfig.cmd";NewCmd = "vpn-config reset-all" }
    @{ File = "vpn-totp.cmd";    NewCmd = "vpn-config totp" }
    @{ File = "vpn-use.cmd";     NewCmd = "vpn-config use" }
    @{ File = "vpn-rm.cmd";      NewCmd = "vpn-config rm" }
    @{ File = "vpn-set.cmd";     NewCmd = "vpn-config set" }
    @{ File = "vpn-edit.cmd";    NewCmd = "vpn-config set" }
)
foreach ($dep in $deprecatedCmds) {
    $filePath = Join-Path $cmdDir $dep.File
    if (Test-Path $filePath) {
        $content = Get-Content $filePath -Raw
        Assert-Match $content 'deprecated' "$($dep.File) shows deprecation message"
        Assert-Match $content $dep.NewCmd "$($dep.File) references $($dep.NewCmd)"
    } else {
        Write-Host "  [SKIP] $($dep.File) not found" -ForegroundColor Yellow
    }
}

# ============================================================
Write-Host "`n=== TOTP Per-Profile Read ===" -ForegroundColor Cyan
# ============================================================

$testDir3 = Join-Path $env:TEMP "vpn-totp-test-$(Get-Random)"
New-Item -ItemType Directory -Path $testDir3 -Force | Out-Null

try {
    # Test: profile TOTP preferred over global
    $profileDir3 = Join-Path $testDir3 "profiles\dku"
    New-Item -ItemType Directory -Path $profileDir3 -Force | Out-Null
    $profileTotp = Join-Path $profileDir3 "totp.xml"
    $globalTotp = Join-Path $testDir3 "totp.xml"
    @{ Secret = "profile-secret" } | ConvertTo-Json | Set-Content $profileTotp
    @{ Secret = "global-secret" } | ConvertTo-Json | Set-Content $globalTotp

    $active = "dku"
    $totpPath = $null
    if ($active) {
        $profileTotpPath = Join-Path $testDir3 "profiles\$active\totp.xml"
        if (Test-Path $profileTotpPath) { $totpPath = $profileTotpPath }
    }
    if (-not $totpPath -and (Test-Path $globalTotp)) { $totpPath = $globalTotp }

    Assert-Equal $totpPath $profileTotp "Profile TOTP preferred over global"
    $data = Get-Content $totpPath -Raw | ConvertFrom-Json
    Assert-Equal $data.Secret "profile-secret" "Profile TOTP secret correct"

    # Test: global TOTP used as fallback
    Remove-Item $profileTotp -Force
    $totpPath = $null
    if ($active) {
        $profileTotpPath = Join-Path $testDir3 "profiles\$active\totp.xml"
        if (Test-Path $profileTotpPath) { $totpPath = $profileTotpPath }
    }
    if (-not $totpPath -and (Test-Path $globalTotp)) { $totpPath = $globalTotp }

    Assert-Equal $totpPath $globalTotp "Global TOTP used as fallback"

} finally {
    Remove-Item $testDir3 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
Write-Host "`n=== Prompt-Driven Connect Helpers ===" -ForegroundColor Cyan
# ============================================================

$ps1Path = Join-Path $PSScriptRoot "..\vpn-auto-connect.ps1"
. $ps1Path -LoadFunctionsOnly

# Get-DuoCliInput
Assert-Equal (Get-DuoCliInput -EffectiveDuo "push" -TotpCode "") "1" "Get-DuoCliInput push -> 1"
Assert-Equal (Get-DuoCliInput -EffectiveDuo "phone" -TotpCode "") "2" "Get-DuoCliInput phone -> 2"
Assert-Equal (Get-DuoCliInput -EffectiveDuo "sms" -TotpCode "") "3" "Get-DuoCliInput sms -> 3"
Assert-Equal (Get-DuoCliInput -EffectiveDuo "passcode" -TotpCode "123456") "123456" "Get-DuoCliInput passcode -> TOTP"

# GUI result markers
Assert-Equal (Get-VpnResultMarker -State "CONNECTED") "VPN_RESULT=CONNECTED" "Connected marker format"
Assert-Equal (Get-VpnResultMarker -State "FAILED") "VPN_RESULT=FAILED" "Failed marker format"
Assert-Equal (Get-VpnResultMarker -State "TIMEOUT") "VPN_RESULT=TIMEOUT" "Timeout marker format"

# Get-VpnGroupSelection
$cfgDku = @{ Group = "-Default-" }
Assert-Equal (Get-VpnGroupSelection -Config $cfgDku) "0" "Default group maps to menu index 0"
$cfgLib = @{ Group = "Library Resources Only" }
Assert-Equal (Get-VpnGroupSelection -Config $cfgLib) "1" "Library group maps to 1"
$cfgEmpty = @{ Group = "" }
Assert-Equal (Get-VpnGroupSelection -Config $cfgEmpty) "0" "Empty group -> 0"

# Session status helpers
Assert-Equal (Format-VpnSessionTimeSpan -TimeSpan ([TimeSpan]::FromSeconds(3661))) "1:01:01" "Session timespan formatting is stable"

$mockStatsOutput = @"
Connection State: Connected
Duration: 1:23:45
Remaining Session Time: 22:36:15
Server Address: portal.dukekunshan.edu.cn
Client Address (IPv4): 10.200.1.20
"@
Assert-Equal (Get-VpnSessionStatLine -Output $mockStatsOutput -Patterns @('Connection State:\s*(.+)')) "Connected" "Session stat parser reads state"
Assert-Equal (Get-VpnSessionStatLine -Output $mockStatsOutput -Patterns @('Duration:\s*([0-9:]+)')) "1:23:45" "Session stat parser reads duration"

$origVpnCliPath = $script:VpnCliPath
$origStateFiles = $script:CiscoVpnStateFiles
$stateTestDir = Join-Path $env:TEMP "vpn-state-test-$(Get-Random)"
New-Item -ItemType Directory -Path $stateTestDir -Force | Out-Null
try {
    $stateFile = Join-Path $stateTestDir "ConfigParam.bin"
    Set-Content -Path $stateFile -Value "x"
    (Get-Item $stateFile).LastWriteTime = (Get-Date).AddHours(-2).AddMinutes(-3).AddSeconds(-4)
    $script:VpnCliPath = Join-Path $stateTestDir "missing-vpncli.exe"
    $script:CiscoVpnStateFiles = @($stateFile)
    $fallbackStats = Get-VpnSessionStats
    Assert-Match $fallbackStats.Duration '^2:03:0[4-6]$' "Session stats fall back to state file duration"
    Assert-Match $fallbackStats.Remaining '^21:56:5[4-6]$' "Session stats fall back to remaining time"
} finally {
    $script:VpnCliPath = $origVpnCliPath
    $script:CiscoVpnStateFiles = $origStateFiles
    Remove-Item $stateTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

$origGetCimInstance = $null
if (Test-Path function:Get-CimInstance) {
    $origGetCimInstance = (Get-Item function:Get-CimInstance).ScriptBlock
}
$origGetProcess = $null
if (Test-Path function:Get-Process) {
    $origGetProcess = (Get-Item function:Get-Process).ScriptBlock
}
function Get-CimInstance {
    param([string]$ClassName)
    return @([pscustomobject]@{
        Name = "vpnagent"
        DisplayName = "Cisco Secure Client VPN Agent"
        State = "Running"
        PathName = "C:\Program Files (x86)\Cisco\Cisco Secure Client\vpnagent.exe"
    })
}
function Get-Process {
    param([string]$Name)
    return @()
}
Assert-True (Test-VpnAgentRunning) "vpnagent check passes when service is running"

function Get-CimInstance {
    param([string]$ClassName)
    return @([pscustomobject]@{
        Name = "vpnagent"
        DisplayName = "Cisco Secure Client VPN Agent"
        State = "Stopped"
        PathName = "C:\Program Files (x86)\Cisco\Cisco Secure Client\vpnagent.exe"
    })
}
Assert-True (-not (Test-VpnAgentRunning)) "vpnagent check fails when detected service is stopped"

function Get-CimInstance {
    param([string]$ClassName)
    return @()
}
function Get-Process {
    param([string]$Name)
    return @([pscustomobject]@{ Name = "vpnagent" })
}
Assert-True (Test-VpnAgentRunning) "vpnagent check passes when process is running"

function Get-Process {
    param([string]$Name)
    return @()
}
Assert-True (Test-VpnAgentRunning) "vpnagent check allows unknown installs to continue"

if ($null -ne $origGetCimInstance) {
    Set-Item -Path function:Get-CimInstance -Value $origGetCimInstance
} else {
    Remove-Item function:Get-CimInstance -ErrorAction SilentlyContinue
}
if ($null -ne $origGetProcess) {
    Set-Item -Path function:Get-Process -Value $origGetProcess
} else {
    Remove-Item function:Get-Process -ErrorAction SilentlyContinue
}

# Wait-ForVpnPrompt (mock buffer)
$mockBuf = New-Object System.Text.StringBuilder
$mockSync = New-Object object
$found = Wait-ForVpnPrompt -Buffer $mockBuf -SyncRoot $mockSync -Pattern 'VPN>' -TimeoutSeconds 1 -Optional
Assert-True (-not $found) "Wait-ForVpnPrompt returns false when pattern absent"

[void]$mockBuf.AppendLine("Cisco AnyConnect")
[void]$mockBuf.AppendLine("VPN> ")
$found = Wait-ForVpnPrompt -Buffer $mockBuf -SyncRoot $mockSync -Pattern 'VPN>' -TimeoutSeconds 2
Assert-True $found "Wait-ForVpnPrompt matches VPN> in buffer"

[void]$mockBuf.AppendLine("Password: ")
$found = Wait-ForVpnPrompt -Buffer $mockBuf -SyncRoot $mockSync -Pattern '[Pp]assword:' -TimeoutSeconds 2
Assert-True $found "Wait-ForVpnPrompt matches Password prompt"

$mockSession = @{ Buffer = $mockBuf; Sync = $mockSync }
Wait-VpnStepOrDelay -Session $mockSession -Pattern 'DUO' -MaxSeconds 1
Assert-True $true "Wait-VpnStepOrDelay completes (timed fallback when pattern absent)"

# Wait-ForVpnIpAfterExit
$origTestVpnConnectedByIp = ${function:Test-VpnConnectedByIp}
$script:IpCheckCount = 0
function Test-VpnConnectedByIp {
    $script:IpCheckCount++
    return ($script:IpCheckCount -ge 3)
}
$graceConnected = Wait-ForVpnIpAfterExit -MaxSeconds 1 -PollMilliseconds 10
Assert-True $graceConnected "Wait-ForVpnIpAfterExit keeps polling until IP appears"
Set-Item -Path function:Test-VpnConnectedByIp -Value $origTestVpnConnectedByIp

# DUO wait timing and tunnel diagnostics
$scriptText = Get-Content $ps1Path -Raw
Assert-Match $scriptText 'Waiting for DUO approval \(up to 50s\)' "DUO wait message uses 50s"
Assert-Match $scriptText 'Wait-ForVpnTunnelAfterMfa[\s\S]*MaxSeconds = 50' "Post-MFA tunnel wait uses 50s"
Assert-Match $scriptText 'BannerFirstSendSeconds = 4' "Post-MFA banner confirmation starts after 4s"
Assert-Match $scriptText "StepLabel 'banner-certificate'" "Post-MFA banner/certificate y retry exists"
Assert-True ($scriptText -notmatch "duo-retry") "Live connect path does not retry DUO input"
Assert-Match $scriptText 'Stop-VpnCliForFailureAndDrain' "Failure path drains vpncli output after stopping process"

$diagNoAdapter = (& { Write-VpnTunnelDiagnostics -CiscoAdapters @() -CiscoAddresses @() -TenAddresses @() } *>&1 | Out-String)
Assert-Match $diagNoAdapter 'vpncli: unavailable' "Diagnostics show missing vpncli"
Assert-Match $diagNoAdapter 'Cisco adapter: not found' "Diagnostics show no Cisco adapter"
Assert-Match $diagNoAdapter '10\.x IPv4: none' "Diagnostics show no 10.x address"

$disabledAdapter = [pscustomobject]@{
    Name = "以太网 2"
    Status = "Disabled"
    InterfaceDescription = "Cisco AnyConnect Virtual Miniport Adapter for Windows x64"
}
$diagDisabled = (& { Write-VpnTunnelDiagnostics -CiscoAdapters @($disabledAdapter) -CiscoAddresses @() -TenAddresses @() } *>&1 | Out-String)
Assert-Match $diagDisabled 'Cisco adapter: .*Disabled.*Cisco AnyConnect' "Diagnostics show disabled Cisco adapter"
Assert-Match $diagDisabled 'Cisco IPv4: none' "Diagnostics show disabled adapter has no IPv4"

$upAdapter = [pscustomobject]@{
    Name = "Cisco VPN"
    Status = "Up"
    InterfaceDescription = "Cisco Secure Client Virtual Adapter"
}
$ciscoAddr = [pscustomobject]@{ IPAddress = "10.200.1.20" }
$diagUp = (& { Write-VpnTunnelDiagnostics -CiscoAdapters @($upAdapter) -CiscoAddresses @($ciscoAddr) -TenAddresses @($ciscoAddr) } *>&1 | Out-String)
Assert-Match $diagUp 'Cisco adapter: .*Up.*Cisco Secure Client' "Diagnostics show up Cisco adapter"
Assert-Match $diagUp 'Cisco IPv4: 10\.200\.1\.20' "Diagnostics show Cisco IPv4"

# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Results: $script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail -eq 0) { "Green" } else { "Red" })
Write-Host "========================================`n" -ForegroundColor Cyan

if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
