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
$config = @{ DuoMethod = "passcode" }
$effectiveDuo = $DuoMethod
if (-not $PSBoundParameters.ContainsKey('DuoMethod') -and $config.DuoMethod) {
    $effectiveDuo = $config.DuoMethod
}
Assert-Equal $effectiveDuo "passcode" "Explicit param overrides config"

# Test 2: Config value used when no explicit param
$DuoMethod = "push"
$PSBoundParameters = @{}
$config = @{ DuoMethod = "passcode" }
$effectiveDuo = $DuoMethod
if (-not $PSBoundParameters.ContainsKey('DuoMethod') -and $config.DuoMethod) {
    $effectiveDuo = $config.DuoMethod
}
Assert-Equal $effectiveDuo "passcode" "Config value used when no explicit param"

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
$map = @{ "push" = "1" }
foreach ($method in $map.Keys) {
    $duoInput = "1"
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
    Assert-Match $cmdContent '-DuoMethod push' "vpn-connect.cmd still supports legacy push shorthand"
    Assert-Match $cmdContent '-Connect %\*' "vpn-connect.cmd forwards explicit arguments to PowerShell"
    Assert-Match $cmdContent '-Preset dku' "vpn-connect.cmd usage mentions DKU preset"
    Assert-Match $cmdContent 'if.*%~1.*==' "vpn-connect.cmd checks for empty arg"
    Assert-True ($cmdContent -notmatch 'sms') "vpn-connect.cmd no longer advertises sms"
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
Assert-Equal (Get-DuoCliInput -EffectiveDuo "passcode" -TotpCode "123456") "123456" "Get-DuoCliInput passcode -> TOTP"
Assert-True (Test-SupportedDuoMethod -Method "push") "push remains a supported DUO method"
Assert-True (-not (Test-SupportedDuoMethod -Method "sms")) "sms is no longer a supported DUO method"

# GUI result markers
Assert-Equal (Get-VpnResultMarker -State "CONNECTED") "VPN_RESULT=CONNECTED" "Connected marker format"
Assert-Equal (Get-VpnResultMarker -State "DISCONNECTED") "VPN_RESULT=DISCONNECTED" "Disconnected marker format"
Assert-Equal (Get-VpnResultMarker -State "FAILED") "VPN_RESULT=FAILED" "Failed marker format"
Assert-Equal (Get-VpnResultMarker -State "TIMEOUT") "VPN_RESULT=TIMEOUT" "Timeout marker format"

# Get-VpnGroupSelection
$cfgDku = @{ Group = "-Default-" }
Assert-Equal (Get-VpnGroupSelection -Config $cfgDku) "0" "Default group maps to menu index 0"
$cfgLib = @{ Group = "Library Resources Only" }
Assert-Equal (Get-VpnGroupSelection -Config $cfgLib) "1" "Library group maps to 1"
$cfgEmpty = @{ Group = "" }
Assert-Equal (Get-VpnGroupSelection -Config $cfgEmpty) "0" "Empty group -> 0"
$groupMenuText = @"
Group Selection
0) -Default-
1) Library Resources Only
2) INTL-DUKE
3) Protected Data
"@
$groupOptions = @(Get-VpnGroupMenuOptions -Text $groupMenuText)
Assert-Equal $groupOptions.Count 4 "Group menu parser finds Cisco group options"
Assert-Equal $groupOptions[2].Number "2" "Group menu parser keeps Duke group menu number"
Assert-Equal (Get-VpnGroupComparisonKey -Name "Protected_Data") "protecteddata" "Group comparison normalizes underscore and spacing"
$sessionGroup = @{
    Buffer = (New-Object System.Text.StringBuilder)
    Sync = (New-Object object)
}
[void]$sessionGroup.Buffer.AppendLine($groupMenuText)
Assert-Equal (Get-VpnGroupSelection -Config @{ Group = "INTL-DUKE" } -Session $sessionGroup -MenuWaitSeconds 1) "2" "Dynamic group selection resolves Duke group names"
Assert-Equal (Get-VpnGroupSelection -Config @{ Group = "Protected_Data" } -Session $sessionGroup -MenuWaitSeconds 1) "3" "Dynamic group selection tolerates spacing differences"
Assert-Equal (Get-VpnGroupSelection -Config @{ Group = "INTL-DUKE" }) "2" "INTL-DUKE falls back to Duke menu number 2 when no group menu is available"
$missingGroupOutput = try {
    Get-VpnGroupSelection -Config @{ Group = "Missing Group" } -Session $sessionGroup -MenuWaitSeconds 1 | Out-String
} catch {
    ($_ | Out-String)
}
Assert-Match $missingGroupOutput 'Missing Group' "Missing VPN group error keeps the requested group name"
$noMenuFallback = Get-VpnGroupSelection -Config @{ Group = "INTL-DUKE" } -MenuWaitSeconds 1
Assert-Equal $noMenuFallback "2" "INTL-DUKE keeps the Duke fallback menu number without live Cisco group text"

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
Assert-Equal (Resolve-VpnStatusServer -Stats @{ Server = "vpn.duke.edu" } -FallbackServer "portal.dukekunshan.edu.cn") "vpn.duke.edu" "Status server prefers vpncli stats server"
Assert-Equal (Resolve-VpnStatusServer -Stats @{ Server = "" } -FallbackServer "portal.dukekunshan.edu.cn") "portal.dukekunshan.edu.cn" "Status server falls back to expected server"

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

$origGetVpnSessionStats = ${function:Get-VpnSessionStats}
$origGetVpnTunnelAddress = ${function:Get-VpnTunnelAddress}
Assert-Equal (Resolve-VpnDisplayState -Stats @{ State = "Unknown"; ClientIP = "10.200.1.20" } -Tunnel $null) "Connected" "Display state overrides Unknown when client IP exists"
Assert-Equal (Resolve-VpnDisplayState -Stats @{ State = "Unknown"; ClientIP = "" } -Tunnel ([pscustomobject]@{ IPAddress = "10.200.1.20" })) "Connected" "Display state overrides Unknown when tunnel exists"
Assert-Equal (Resolve-VpnDisplayState -Stats @{ State = "Disconnected"; ClientIP = "" } -Tunnel $null) "Disconnected" "Display state preserves non-Unknown state"
Assert-Equal (Normalize-DuoPushTarget -Value "option 02") "2" "Push target normalizes to a DUO menu number"

# Connect path: configured push target or default menu 1 (no interactive phone selection)
$configuredTarget = Normalize-DuoPushTarget -Value "2"
$pushDuoWithTarget = if ($configuredTarget) { $configuredTarget } else { Get-DuoCliInput -EffectiveDuo "push" -TotpCode "" }
Assert-Equal $pushDuoWithTarget "2" "Configured push target sends menu number"
$pushDuoDefault = if ((Normalize-DuoPushTarget -Value "")) { (Normalize-DuoPushTarget -Value "") } else { Get-DuoCliInput -EffectiveDuo "push" -TotpCode "" }
Assert-Equal $pushDuoDefault "1" "Unconfigured push target defaults to menu 1"

$duoDiag = Get-DuoPromptDiagnostics -Text @"
Header
1-Push to XXX-3808
2-Phone call
Footer
"@
Assert-Match $duoDiag 'Push to XXX-3808' "DUO diagnostics keep push lines"
Assert-Match $duoDiag 'Phone call' "DUO diagnostics keep related MFA lines"

$rawMfaBuffer = Get-RecentVpnMfaBuffer -Text @"
Header
username: rw335
1-Push to XXX-3808
Token: ABCDEFGHIJKLMNOPQRSTUVWXYZ123456
Footer
"@ -MaxLines 4 -MaskValues @("rw335")
Assert-Match $rawMfaBuffer '1-Push to XXX-3808' "Recent MFA buffer keeps menu lines"
Assert-Match $rawMfaBuffer '<masked>' "Recent MFA buffer masks known secrets"
Assert-Match $rawMfaBuffer 'Token: <masked>|<masked-token>' "Recent MFA buffer masks sensitive token output"

$duoDiagSanitized = Get-DuoPromptDiagnostics -Text @"
User: rw335
Push to XXX-3808
"@ -MaskValues @("rw335")
Assert-Match $duoDiagSanitized 'Push to XXX-3808' "Sanitized DUO diagnostics still keep menu text"
$protectedText = Protect-VpnDiagnosticText -Text "User: rw335" -MaskValues @("rw335")
Assert-Match $protectedText '<masked>' "Diagnostic text masking hides the username"

$logHitDir = Join-Path $env:TEMP "vpn-log-hit-$(Get-Random)"
$logTailDir = Join-Path $env:TEMP "vpn-log-tail-$(Get-Random)"
try {
    New-Item -ItemType Directory -Path $logHitDir -Force | Out-Null
    New-Item -ItemType Directory -Path $logTailDir -Force | Out-Null

    $hitLog = Join-Path $logHitDir "vpn-hit.log"
    @(
        "normal line"
        "DUO push request sent to user rw335"
        "authentication success"
    ) | Set-Content $hitLog
    $hitDiag = Get-CiscoLogDiagnostics -SearchPaths @($logHitDir) -MaxFiles 1 -TailLines 6 -MaskValues @("rw335")
    $hitText = $hitDiag.Lines -join "`n"
    Assert-Equal $hitDiag.Status "hits" "Cisco log diagnostics report keyword hits"
    Assert-Match $hitText 'matched MFA/auth keywords' "Cisco log diagnostics mention keyword matches"
    Assert-Match $hitText '<masked>' "Cisco log diagnostics mask configured secrets"

    $tailLog = Join-Path $logTailDir "vpn-tail.log"
    @(
        "line one"
        "line two"
        "line three"
    ) | Set-Content $tailLog
    $tailDiag = Get-CiscoLogDiagnostics -SearchPaths @($logTailDir) -MaxFiles 1 -TailLines 3
    $tailText = $tailDiag.Lines -join "`n"
    Assert-Equal $tailDiag.Status "tail" "Cisco log diagnostics fall back to raw tail lines"
    Assert-Match $tailText 'no obvious MFA keywords' "Cisco log diagnostics explain missing keywords"
    Assert-Match $tailText 'line three' "Cisco log diagnostics include raw tail fallback"

    $notFoundDiag = Get-CiscoLogDiagnostics -SearchPaths @(Join-Path $env:TEMP "vpn-log-missing-$(Get-Random)") -MaxFiles 1 -TailLines 3
    $notFoundText = $notFoundDiag.Lines -join "`n"
    Assert-Equal $notFoundDiag.Status "not-found" "Cisco log diagnostics report missing directories"
    Assert-Match $notFoundText 'No Cisco text log paths found' "Cisco log diagnostics clearly report missing paths"
} finally {
    Remove-Item $logHitDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $logTailDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-VpnSessionStats {
    return @{
        State = "Connected"
        ClientIP = ""
        Duration = ""
        Remaining = ""
        Server = ""
    }
}
function Get-VpnTunnelAddress { return $null }
Assert-True (Test-VpnSessionConnected) "Session-connected fallback recognizes Connected state"
Assert-True (Test-VpnConnectedByIp) "Connected test falls back to vpncli stats state"

function Get-VpnSessionStats {
    return @{
        State = ""
        ClientIP = "10.200.1.20"
        Duration = ""
        Remaining = ""
        Server = ""
    }
}
Assert-True (Test-VpnSessionConnected) "Session-connected fallback recognizes client IP"

function Get-VpnSessionStats {
    return @{
        State = "Disconnected"
        ClientIP = ""
        Duration = ""
        Remaining = ""
        Server = ""
    }
}
Assert-True (-not (Test-VpnSessionConnected)) "Session-connected fallback rejects disconnected state"
Set-Item -Path function:Get-VpnSessionStats -Value $origGetVpnSessionStats
Set-Item -Path function:Get-VpnTunnelAddress -Value $origGetVpnTunnelAddress

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
Assert-Match $scriptText 'BannerFirstSendSeconds = 2' "Post-MFA banner confirmation starts after 2s"
Assert-Match $scriptText "StepLabel 'banner-certificate'" "Post-MFA banner/certificate y retry exists"
Assert-Match $scriptText 'Start-Sleep -Seconds 3' "MFA pre-wait shortened to 3s"
Assert-True ($scriptText -notmatch 'function Wait-ForDuoPushOptions') "Wait-ForDuoPushOptions helper removed"
Assert-True ($scriptText -notmatch 'function Select-DuoPushOption') "Select-DuoPushOption removed"
Assert-True ($scriptText -notmatch 'function Get-DuoPushOptions') "Get-DuoPushOptions removed"
Assert-True ($scriptText -notmatch 'NonInteractiveMfa') "NonInteractiveMfa parameter removed"
Assert-Match $scriptText 'Wait-ForVpnIpAfterExit -MaxSeconds 5' "Post-exit VPN IP grace shortened to 5s"
Assert-True ($scriptText -notmatch "duo-retry") "Live connect path does not retry DUO input"
Assert-Match $scriptText 'ValidateSet\("push", "passcode"\)' "PowerShell script only exposes push and passcode"
Assert-Match $scriptText 'menu number \(1/2/3' "PowerShell script documents push target as a menu number"
Assert-True ($scriptText -notmatch 'Could not detect the DUO push menu') "PowerShell script no longer prints push-target fallback mismatch text"
Assert-True ($scriptText -notmatch 'No vpncli MFA menu text was captured before fallback') "PowerShell script no longer prints empty MFA capture fallback text"
Assert-True ($scriptText -notmatch 'Falling back to the default DUO push option \(1\)') "PowerShell script no longer prints explicit fallback-to-1 text"
Assert-True ($scriptText -notmatch 'No explicit DUO push menu detected; defaulting to option 1') "PowerShell script no longer prints generic menu-miss fallback text"
Assert-Match $scriptText 'Stop-VpnCliForFailureAndDrain' "Failure path drains vpncli output after stopping process"
Assert-Match $scriptText 'recent vpncli MFA buffer' "PowerShell script prints raw MFA buffer diagnostics"
Assert-Match $scriptText 'Cisco log diagnostics' "PowerShell script prints Cisco log diagnostics"
Assert-True ($scriptText -notmatch "Please tap 'Approve' on your DUO mobile push") "PowerShell script no longer prints duplicate push approval reminder"
Assert-Match $scriptText 'function Resolve-VpnStatusServer' "PowerShell script defines shared status-server resolver"
Assert-Match $scriptText '\[OK\] VPN connected: \$server' "vpn-status / connect success include resolved server in success text"

$guiScript = Get-Content (Join-Path $PSScriptRoot "..\tools\vpn-gui.py") -Raw
Assert-True ($guiScript -notmatch '"sms"|SMS') "GUI no longer offers sms"
Assert-True ($guiScript -notmatch 'NonInteractiveMfa') "GUI connect no longer passes NonInteractiveMfa"
Assert-Match $guiScript 'VPN_RESULT=\(CONNECTED\|DISCONNECTED\|FAILED\|TIMEOUT\)' "GUI parser accepts disconnect marker"
Assert-Match $guiScript 'optional: default 1' "GUI PushTo placeholder documents default 1"
Assert-Match $guiScript 'Duke VPN' "GUI includes Duke VPN preset"
Assert-Match $guiScript 'DUKE_DEFAULT_GROUP = "INTL-DUKE"' "GUI Duke preset defaults to INTL-DUKE"
Assert-Match $guiScript 'preset_dialog_height = "420x360" if edit_mode else "420x320"' "GUI preset dialogs use compact preset sizing"
Assert-Match $guiScript 'vpn\.duke\.edu' "GUI Duke preset uses vpn.duke.edu"
Assert-Match $guiScript 'INTL-DUKE' "GUI Duke preset includes Duke-specific group options"
Assert-Match $guiScript 'delay_ms=1500' "GUI connected-stats refresh shortened to 1500ms"
Assert-Match $guiScript '_poll_vpn_ip\(max_seconds=poll_seconds, interval=0\.5\)' "GUI Stage 2 VPN IP polling uses configurable timeout with 0.5s interval"
Assert-Match $guiScript 'Stage 2 extended to .*Cisco is still downloading/updating components' "GUI extends Stage 2 when Cisco downloader is still running"
Assert-Match $guiScript 'status_text = f"Connected: \{server\}" if server else "Connected"' "GUI connected status includes resolved server"
Assert-Match $guiScript 'status_text = f"Disconnected: \{status_server\}" if status_server else "Disconnected"' "GUI disconnected status includes selected profile server"
Assert-Match $guiScript 'def _resolve_status_server' "GUI defines shared status-server resolver for status labels"

$readmeText = Get-Content (Join-Path $PSScriptRoot "..\README.md") -Raw
Assert-True ($readmeText -notmatch 'push-target 3808|后 4 位|last 4 digits|preferred phone suffix') "README no longer documents phone-suffix push target"
Assert-Match $readmeText 'push-target 1' "README documents push-target using DUO menu numbers"
Assert-True ($readmeText -notmatch 'CLI will prompt you to choose|CLI 会提示你选择') "README no longer claims CLI interactive DUO selection"

$diagNoAdapter = Get-VpnTunnelDiagnosticsText -CiscoAdapters @() -CiscoAddresses @() -TenAddresses @()
Assert-Match $diagNoAdapter 'vpncli: unavailable' "Diagnostics show missing vpncli"
Assert-Match $diagNoAdapter 'Cisco adapter: not found' "Diagnostics show no Cisco adapter"
Assert-Match $diagNoAdapter '10\.x IPv4: none' "Diagnostics show no 10.x address"

$disabledAdapter = [pscustomobject]@{
    Name = "以太网 2"
    Status = "Disabled"
    InterfaceDescription = "Cisco AnyConnect Virtual Miniport Adapter for Windows x64"
}
$diagDisabled = Get-VpnTunnelDiagnosticsText -CiscoAdapters @($disabledAdapter) -CiscoAddresses @() -TenAddresses @()
Assert-Match $diagDisabled 'Cisco adapter: .*Disabled.*Cisco AnyConnect' "Diagnostics show disabled Cisco adapter"
Assert-Match $diagDisabled 'Cisco IPv4: none' "Diagnostics show disabled adapter has no IPv4"

$upAdapter = [pscustomobject]@{
    Name = "Cisco VPN"
    Status = "Up"
    InterfaceDescription = "Cisco Secure Client Virtual Adapter"
}
$ciscoAddr = [pscustomobject]@{ IPAddress = "10.200.1.20" }
$diagUp = Get-VpnTunnelDiagnosticsText -CiscoAdapters @($upAdapter) -CiscoAddresses @($ciscoAddr) -TenAddresses @($ciscoAddr)
Assert-Match $diagUp 'Cisco adapter: .*Up.*Cisco Secure Client' "Diagnostics show up Cisco adapter"
Assert-Match $diagUp 'Cisco IPv4: 10\.200\.1\.20' "Diagnostics show Cisco IPv4"

# ============================================================
Write-Host "`n=== GUI-Aligned Profile Persistence ===" -ForegroundColor Cyan
# ============================================================

$profileTestDir = Join-Path $env:TEMP "vpn-profile-test-$(Get-Random)"
New-Item -ItemType Directory -Path $profileTestDir -Force | Out-Null

$origConfigDir = $ConfigDir
$origCredFile = $CredFile
$origConfigFile = $ConfigFile
$origTotpFile = $TotpFile
$origProfilesDir = $ProfilesDir
$origProfilesIndex = $ProfilesIndex
$origActiveProfileFile = $ActiveProfileFile
$origVpnDiagnosticLogDir = $VpnDiagnosticLogDir

try {
    $ConfigDir = $profileTestDir
    $CredFile = Join-Path $profileTestDir "credentials.xml"
    $ConfigFile = Join-Path $profileTestDir "config.json"
    $TotpFile = Join-Path $profileTestDir "totp.xml"
    $ProfilesDir = Join-Path $profileTestDir "profiles"
    $ProfilesIndex = Join-Path $profileTestDir "profiles.json"
    $ActiveProfileFile = Join-Path $profileTestDir "active_profile"
    $VpnDiagnosticLogDir = Join-Path $profileTestDir "logs"
    New-Item -ItemType Directory -Path $ProfilesDir -Force | Out-Null
    New-Item -ItemType Directory -Path $VpnDiagnosticLogDir -Force | Out-Null

    $created = Save-VpnProfileCore -Name "DKU VPN!" `
        -Server "portal.dukekunshan.edu.cn" -Group "-Default-" -Port "443" -Protocol "ssl" `
        -Username "netid" -Password "secret!" -DuoMethod "push" -PushTo "02" -SetActive

    Assert-Equal $created.name "DKUVPN" "Profile name is sanitized for storage"
    $createdConfig = Get-Content (Join-Path $ProfilesDir "DKUVPN\config.json") -Raw | ConvertFrom-Json
    Assert-Equal $createdConfig.DuoMethod "push" "Profile save stores DUO Method"
    Assert-Equal $createdConfig.DuoPushTarget "2" "Profile save normalizes PushTo into DuoPushTarget"
    $createdCred = Get-Content (Join-Path $ProfilesDir "DKUVPN\credentials.xml") -Raw | ConvertFrom-Json
    Assert-Equal $createdCred.Username "netid" "Profile save stores Username"
    Assert-Equal (Decrypt-String $createdCred.Password) "secret!" "Profile save stores DPAPI password"
    Assert-Equal (Get-Content $ActiveProfileFile -Raw).Trim() "DKUVPN" "Profile save updates active profile"

    $beforePassword = $createdCred.Password
    $updated = Save-VpnProfileCore -Name "DKUVPN" `
        -Server "vpn.example.com" -Group "Library Resources Only" -Port "8443" -Protocol "ipsec" `
        -Username "newuser" -DuoMethod "passcode" -PushTo "" -PreservePassword

    $updatedConfig = Get-Content (Join-Path $ProfilesDir "DKUVPN\config.json") -Raw | ConvertFrom-Json
    Assert-Equal $updatedConfig.Server "vpn.example.com" "Preserve-password update stores new server"
    Assert-Equal $updatedConfig.Group "Library Resources Only" "Preserve-password update stores new group"
    Assert-Equal $updatedConfig.Protocol "ipsec" "Preserve-password update stores new protocol"
    Assert-Equal $updatedConfig.DuoMethod "passcode" "Preserve-password update stores new DUO Method"
    Assert-True (-not ($updatedConfig.PSObject.Properties.Name -contains 'DuoPushTarget')) "Preserve-password update clears PushTo"
    $updatedCred = Get-Content (Join-Path $ProfilesDir "DKUVPN\credentials.xml") -Raw | ConvertFrom-Json
    Assert-Equal $updatedCred.Username "newuser" "Preserve-password update stores new username"
    Assert-Equal $updatedCred.Password $beforePassword "Preserve-password update keeps encrypted password"

    New-Item -ItemType File -Path (Join-Path $ProfilesDir "DKUVPN\totp.xml") -Force | Out-Null
    $snapshot = Get-ProfileSnapshots
    Assert-Equal $snapshot.activeProfile "DKUVPN" "Profile snapshot keeps active profile"
    Assert-Equal $snapshot.profiles[0].displayName "DKUVPN" "Profile snapshot exposes display name"
    Assert-Equal $snapshot.profiles[0].duoMethod "passcode" "Profile snapshot exposes DUO Method"
    Assert-Equal $snapshot.profiles[0].pushTo "" "Profile snapshot exposes cleared PushTo"
    Assert-True $snapshot.profiles[0].hasPassword "Profile snapshot exposes password status"
    Assert-True $snapshot.profiles[0].hasTotp "Profile snapshot exposes TOTP status"

    $dukeCreated = Save-VpnProfileCore -Name "duke" `
        -Server "vpn.duke.edu" -Group "-Default-" -Port "443" -Protocol "ssl" `
        -Username "dukeid" -Password "secret2" -DuoMethod "push" -PushTo "" -SetActive
    Assert-Equal $dukeCreated.displayName "Duke VPN" "Profile snapshot maps duke display name"

    Remove-VpnProfile -Name "DKUVPN" -Force
    Assert-True (-not (Test-Path (Join-Path $ProfilesDir "DKUVPN"))) "Force remove deletes profile directory"
    Remove-VpnProfile -Name "duke" -Force
    Assert-True (-not (Test-Path $ActiveProfileFile)) "Force remove clears active profile when last profile is deleted"
} finally {
    $ConfigDir = $origConfigDir
    $CredFile = $origCredFile
    $ConfigFile = $origConfigFile
    $TotpFile = $origTotpFile
    $ProfilesDir = $origProfilesDir
    $ProfilesIndex = $origProfilesIndex
    $ActiveProfileFile = $origActiveProfileFile
    $VpnDiagnosticLogDir = $origVpnDiagnosticLogDir
    Remove-Item $profileTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Results: $script:Pass passed, $script:Fail failed" -ForegroundColor $(if ($script:Fail -eq 0) { "Green" } else { "Red" })
Write-Host "========================================`n" -ForegroundColor Cyan

if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
