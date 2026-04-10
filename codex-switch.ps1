#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '1.0.0'
$CodexDefaultHome = Join-Path $HOME '.codex'
$ProfilePrefix = Join-Path $HOME '.codex-'
$ProfileMarker = '.profile-name'
$SharedItems = @('rules', 'skills', 'AGENTS.md')
$AutoStateFile = Join-Path $HOME '.codex-switch-auto'

function Write-Success([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-ErrorMsg([string]$Message) { Write-Host "  [ERR] $Message" -ForegroundColor Red }
function Write-Warn([string]$Message) { Write-Host "  [!] $Message" -ForegroundColor Yellow }
function Write-Info([string]$Message) { Write-Host "  [>] $Message" -ForegroundColor Cyan }
function Write-Dim([string]$Message) { Write-Host "      $Message" -ForegroundColor DarkGray }

function Ensure-Codex {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg 'Codex CLI not found in PATH.'
        Write-Dim 'Install it first: https://github.com/openai/codex'
        exit 1
    }
}

function Validate-ProfileName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-ErrorMsg 'Profile name cannot be empty.'
        return $false
    }
    if ($Name -eq 'default') {
        Write-ErrorMsg "'default' is reserved for the primary ~/.codex/ profile."
        return $false
    }
    if ($Name.Length -gt 32) {
        Write-ErrorMsg 'Profile name must be 32 characters or fewer.'
        return $false
    }
    if ($Name -notmatch '^[a-zA-Z][a-zA-Z0-9_-]*$') {
        Write-ErrorMsg 'Invalid name. Use letters, numbers, hyphens, underscores. Must start with a letter.'
        return $false
    }
    return $true
}

function Get-ProfileDir([string]$Name) {
    return "$ProfilePrefix$Name"
}

function Test-ProfileExists([string]$Name) {
    $dir = Get-ProfileDir $Name
    return (Test-Path $dir) -and (Test-Path (Join-Path $dir $ProfileMarker))
}

function Get-AllProfiles {
    if (-not (Test-Path $HOME)) { return @() }
    $dirs = Get-ChildItem -Path $HOME -Directory -Filter '.codex-*' -ErrorAction SilentlyContinue
    $profiles = @()
    foreach ($dir in $dirs) {
        if (Test-Path (Join-Path $dir.FullName $ProfileMarker)) {
            $profiles += $dir.Name.Substring(7)
        }
    }
    return $profiles | Sort-Object
}

function Invoke-CodexWithHome([string]$ConfigDir, [string[]]$Args) {
    $oldHome = $env:CODEX_HOME
    try {
        if ($ConfigDir -eq $CodexDefaultHome) {
            if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
        } else {
            $env:CODEX_HOME = $ConfigDir
        }
        & codex @Args
        return $LASTEXITCODE
    }
    finally {
        if ([string]::IsNullOrEmpty($oldHome)) {
            if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
        } else {
            $env:CODEX_HOME = $oldHome
        }
    }
}

function Get-AuthStatus([string]$ConfigDir) {
    $oldHome = $env:CODEX_HOME
    try {
        if ($ConfigDir -eq $CodexDefaultHome) {
            if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
        } else {
            $env:CODEX_HOME = $ConfigDir
        }
        $output = (& codex login status 2>&1 | Out-String)
    }
    catch {
        $output = ''
    }
    finally {
        if ([string]::IsNullOrEmpty($oldHome)) {
            if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
        } else {
            $env:CODEX_HOME = $oldHome
        }
    }

    if ($output -match 'Logged in') {
        return ($output -replace 'Logged in\s*', '').Trim()
    }
    return ''
}

function Get-RotationList {
    $list = @('default')
    $list += Get-AllProfiles
    return $list
}

function Get-RotationIndex {
    if (Test-Path $AutoStateFile) {
        $val = (Get-Content -Path $AutoStateFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($val -match '^[0-9]+$') {
            return [int]$val
        }
    }
    return 0
}

function Set-RotationIndex([int]$Index) {
    Set-Content -Path $AutoStateFile -Value $Index -NoNewline
}

function Test-QuotaError([string]$Text) {
    return $Text -match '(?i)429|rate.?limit.?exceed|too many request|quota.?exceed|exceed.*quota|insufficient.?quota|usage.?limit|usage_limit_exceeded|capacity.?exceeded|overloaded'
}

function Select-Profile([string]$Action) {
    $profiles = Get-AllProfiles
    if ($profiles.Count -eq 0) {
        Write-Warn 'No profiles found. Create one first.'
        return $null
    }

    Write-Host ""
    Write-Host "Select a profile to $Action:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $profiles[$i])
    }

    $choice = Read-Host 'Enter number'
    if ($choice -notmatch '^[0-9]+$') { return $null }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $profiles.Count) { return $null }
    return $profiles[$idx]
}

function Ensure-Parent([string]$Path) {
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Link-SharedItem([string]$Source, [string]$Destination) {
    if (-not (Test-Path $Source)) {
        Write-Dim "~ $(Split-Path -Leaf $Source) (not found, will link when created)"
        return
    }

    if (Test-Path $Destination) {
        Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }

    $sourceIsDir = (Get-Item $Source).PSIsContainer

    if ($sourceIsDir) {
        try {
            New-Item -ItemType Junction -Path $Destination -Target $Source -Force | Out-Null
            Write-Dim "-> $(Split-Path -Leaf $Source)"
            return
        }
        catch {}

        try {
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
            Write-Dim "-> $(Split-Path -Leaf $Source)"
            return
        }
        catch {}

        Copy-Item -Path $Source -Destination $Destination -Recurse -Force
        Write-Dim "~ $(Split-Path -Leaf $Source) (copied; no link support)"
        return
    }

    try {
        New-Item -ItemType HardLink -Path $Destination -Target $Source -Force | Out-Null
        Write-Dim "-> $(Split-Path -Leaf $Source)"
        return
    }
    catch {}

    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
        Write-Dim "-> $(Split-Path -Leaf $Source)"
        return
    }
    catch {}

    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Dim "~ $(Split-Path -Leaf $Source) (copied; no link support)"
}

function Get-PowerShellProfilePath {
    if (-not $PROFILE) {
        return (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
    }
    return $PROFILE
}

function Ensure-ProfileAlias([string]$Name, [string]$Dir) {
    $profilePath = Get-PowerShellProfilePath
    Ensure-Parent $profilePath
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath | Out-Null
    }

    $aliasLine = "function codex-$Name { `$env:CODEX_HOME = '$Dir'; codex @args }"
    $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
    if ($content -match [Regex]::Escape("function codex-$Name")) {
        Write-Info "Alias 'codex-$Name' already in PowerShell profile"
        return
    }

    Add-Content -Path $profilePath -Value "`n# Codex profile: $Name`n$aliasLine`n"
    Write-Success "Added alias codex-$Name to PowerShell profile"
}

function Remove-ProfileAlias([string]$Name) {
    $profilePath = Get-PowerShellProfilePath
    if (-not (Test-Path $profilePath)) { return }

    $lines = Get-Content -Path $profilePath
    $filtered = $lines | Where-Object {
        ($_ -notmatch "^# Codex profile: $([Regex]::Escape($Name))$") -and
        ($_ -notmatch "^function codex-$([Regex]::Escape($Name))\\b")
    }

    if ($filtered.Count -ne $lines.Count) {
        Set-Content -Path $profilePath -Value $filtered
        Write-Success 'Removed alias from PowerShell profile'
    }
}

function Cmd-Create([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Read-Host 'Profile name (e.g. work, personal)'
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Info 'Cancelled.'
        return
    }

    if (-not (Validate-ProfileName $Name)) { exit 1 }

    $dir = Get-ProfileDir $Name
    if ((Test-Path $dir) -and (Test-Path (Join-Path $dir $ProfileMarker))) {
        Write-ErrorMsg "Profile '$Name' already exists at $dir"
        exit 1
    }

    if ((Test-Path $dir) -and -not (Test-Path (Join-Path $dir $ProfileMarker))) {
        Write-ErrorMsg "Directory $dir exists but is not a codex-switch profile."
        Write-Dim 'Inspect it manually or choose a different name.'
        exit 1
    }

    Write-Host ""
    Write-Host "Creating profile '$Name'" -ForegroundColor Cyan
    Write-Host ""

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -Path (Join-Path $dir $ProfileMarker) -Value $Name -NoNewline

    foreach ($item in $SharedItems) {
        $source = Join-Path $CodexDefaultHome $item
        $dest = Join-Path $dir $item
        Link-SharedItem -Source $source -Destination $dest
    }

    Write-Host ""
    Write-Success "Profile created at ~/.codex-$Name/"
    Ensure-ProfileAlias -Name $Name -Dir $dir

    Write-Host ""
    Write-Host 'Quick start:' -ForegroundColor Cyan
    Write-Host '  . $PROFILE'
    Write-Host "  codex-switch $Name"
    Write-Host ''
}

function Cmd-List {
    Write-Host ''
    Write-Host 'Profiles' -ForegroundColor Cyan
    Write-Host ''

    $defaultStatus = Get-AuthStatus $CodexDefaultHome
    if ($defaultStatus) {
        Write-Host ("  default          ~/.codex/                  [logged in] {0}" -f $defaultStatus) -ForegroundColor Green
    } else {
        Write-Host '  default          ~/.codex/                  [not logged in]' -ForegroundColor Yellow
    }

    $profiles = Get-AllProfiles
    foreach ($name in $profiles) {
        $dir = Get-ProfileDir $name
        $status = Get-AuthStatus $dir
        if ($status) {
            Write-Host ("  {0,-16} ~/.codex-{0}/             [logged in] {1}" -f $name, $status) -ForegroundColor Green
        } else {
            Write-Host ("  {0,-16} ~/.codex-{0}/             [not logged in]" -f $name) -ForegroundColor Yellow
        }
    }

    $count = 1 + $profiles.Count
    $rotation = Get-RotationList
    $idx = Get-RotationIndex
    if ($idx -ge $rotation.Count) { $idx = 0 }
    $nextProfile = $rotation[$idx]

    Write-Host ''
    Write-Dim "$count profile(s) total  |  auto-switch next: $nextProfile"
    Write-Host ''
}

function Cmd-Delete([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Select-Profile 'delete'
        if (-not $Name) { return }
    }

    if ($Name -eq 'default') {
        Write-ErrorMsg 'Cannot delete the default profile.'
        exit 1
    }

    if (-not (Test-ProfileExists $Name)) {
        Write-ErrorMsg "Profile '$Name' does not exist."
        exit 1
    }

    $dir = Get-ProfileDir $Name
    Write-Host ''
    Write-Warn "This will permanently remove ~/.codex-$Name/ and its auth/session data."
    $answer = Read-Host "Delete profile '$Name'? [y/N]"
    if ($answer -notin @('y', 'Y')) {
        Write-Info 'Cancelled.'
        return
    }

    Remove-Item -Path $dir -Recurse -Force
    Write-Success "Removed ~/.codex-$Name/"

    Remove-ProfileAlias -Name $Name

    Write-Host ''
    Write-Info "Run '. `$PROFILE' to refresh aliases."
    Write-Host ''
}

function Cmd-Launch([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Select-Profile 'launch'
        if (-not $Name) { exit 1 }
    }

    if ($Name -eq 'default') {
        & codex
        exit $LASTEXITCODE
    }

    if (-not (Test-ProfileExists $Name)) {
        Write-ErrorMsg "Profile '$Name' does not exist."
        Write-Dim "Run: codex-switch create $Name"
        exit 1
    }

    $dir = Get-ProfileDir $Name
    $exitCode = Invoke-CodexWithHome -ConfigDir $dir -Args @()
    exit $exitCode
}

function Resolve-ProfileDir([string]$Profile) {
    if ($Profile -eq 'default') { return $CodexDefaultHome }
    return (Get-ProfileDir $Profile)
}

function Cmd-Auto([string[]]$Args) {
    $profiles = Get-RotationList
    $total = $profiles.Count

    if ($total -eq 0) {
        & codex @Args
        exit $LASTEXITCODE
    }

    $idx = Get-RotationIndex
    if ($idx -ge $total) { $idx = 0 }

    $isInteractive = $true
    foreach ($arg in $Args) {
        if ($arg -in @('exec', 'e', 'review')) {
            $isInteractive = $false
            break
        }
    }

    if (-not $isInteractive) {
        $tried = 0
        while ($tried -lt $total) {
            $profile = $profiles[$idx]
            $dir = Resolve-ProfileDir $profile
            $tmpErr = New-TemporaryFile

            $exitCode = 0
            $oldHome = $env:CODEX_HOME
            try {
                if ($profile -eq 'default') {
                    if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
                } else {
                    $env:CODEX_HOME = $dir
                }
                & codex @Args 2> $tmpErr
                $exitCode = $LASTEXITCODE
            }
            finally {
                if ([string]::IsNullOrEmpty($oldHome)) {
                    if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
                } else {
                    $env:CODEX_HOME = $oldHome
                }
            }

            $errText = Get-Content -Path $tmpErr -Raw -ErrorAction SilentlyContinue
            if ($exitCode -ne 0 -and (Test-QuotaError $errText)) {
                if ($errText) { [Console]::Error.WriteLine($errText.TrimEnd()) }
                Write-Host ''
                Write-Warn "Profile '$profile' hit rate limit / quota, switching to next account..."
                Write-Host ''
                Remove-Item -Path $tmpErr -Force -ErrorAction SilentlyContinue
                $idx = ($idx + 1) % $total
                Set-RotationIndex $idx
                $tried++
                continue
            }

            if ($errText) { [Console]::Error.WriteLine($errText.TrimEnd()) }
            Remove-Item -Path $tmpErr -Force -ErrorAction SilentlyContinue
            Set-RotationIndex $idx
            exit $exitCode
        }

        Write-Host ''
        Write-ErrorMsg "All $total profile(s) have hit their quota / rate limit."
        Write-Dim 'Wait for limits to reset, then try again.'
        Write-Host ''
        exit 1
    }

    $profile = $profiles[$idx]
    $dir = Resolve-ProfileDir $profile

    $nextIdx = ($idx + 1) % $total
    Set-RotationIndex $nextIdx
    $nextProfile = $profiles[$nextIdx]

    Write-Info "Launching with profile: $profile"
    if ($total -gt 1) {
        Write-Dim "Next auto-switch profile: $nextProfile"
    }
    Write-Host ''

    $exitCode = 0
    $oldHome = $env:CODEX_HOME
    try {
        if ($profile -eq 'default') {
            if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
        } else {
            $env:CODEX_HOME = $dir
        }
        & codex @Args
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ([string]::IsNullOrEmpty($oldHome)) {
            if (Test-Path Env:CODEX_HOME) { Remove-Item Env:CODEX_HOME }
        } else {
            $env:CODEX_HOME = $oldHome
        }
    }

    if ($exitCode -ne 0 -and $total -gt 1) {
        Write-Host ''
        Write-Warn "Codex exited with error (code $exitCode)."
        $retry = Read-Host "Retry with next profile ($nextProfile)? [y/N]"
        if ($retry -in @('y', 'Y')) {
            Write-Host ''
            Cmd-Auto -Args $Args
            return
        }
    }

    exit $exitCode
}

function Cmd-Next {
    $profiles = Get-RotationList
    $total = $profiles.Count

    if ($total -le 1) {
        Write-Warn 'Only one profile available. Create more with: codex-switch create <name>'
        exit 0
    }

    $idx = Get-RotationIndex
    if ($idx -ge $total) { $idx = 0 }

    $oldProfile = $profiles[$idx]
    $idx = ($idx + 1) % $total
    Set-RotationIndex $idx
    $newProfile = $profiles[$idx]

    Write-Host ''
    Write-Success "Switched from '$oldProfile' -> '$newProfile'"
    Write-Dim "Next codex-switch auto will use: $newProfile"
    Write-Host ''
}

function Cmd-Interactive {
    Write-Host ''
    Write-Host "CODEX SWITCH v$Version" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1] Create a new profile'
    Write-Host '  [2] List all profiles'
    Write-Host '  [3] Launch a profile'
    Write-Host '  [4] Launch with auto-switch'
    Write-Host '  [5] Rotate to next profile'
    Write-Host '  [6] Delete a profile'
    Write-Host '  [7] Exit'

    $choice = Read-Host 'Choose an option'
    switch ($choice) {
        '1' { Cmd-Create '' }
        '2' { Cmd-List }
        '3' { Cmd-Launch '' }
        '4' { Cmd-Auto @() }
        '5' { Cmd-Next }
        '6' { Cmd-Delete '' }
        default { exit 0 }
    }
}

function Cmd-Help {
    Write-Host ""
    Write-Host 'USAGE'
    Write-Host '  codex-switch [command] [name]'
    Write-Host '  codex-switch <profile-name>'
    Write-Host ''
    Write-Host 'COMMANDS'
    Write-Host '  <name>           Launch Codex with that profile'
    Write-Host '  create [name]    Create a new profile'
    Write-Host '  list             List all profiles and auth status'
    Write-Host '  delete [name]    Delete a profile'
    Write-Host '  auto [args...]   Launch with auto account rotation'
    Write-Host '  next             Manually advance to the next profile'
    Write-Host '  help             Show this help message'
    Write-Host '  version          Show version'
    Write-Host ''
}

function Main([string[]]$MainArgs) {
    Ensure-Codex

    $cmd = if ($MainArgs.Count -gt 0) { $MainArgs[0] } else { '' }

    switch ($cmd) {
        'create' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Create $name
        }
        'list' { Cmd-List }
        'ls' { Cmd-List }
        'delete' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Delete $name
        }
        'rm' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Delete $name
        }
        'remove' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Delete $name
        }
        'launch' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Launch $name
        }
        'run' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Launch $name
        }
        'start' {
            $name = if ($MainArgs.Count -gt 1) { $MainArgs[1] } else { '' }
            Cmd-Launch $name
        }
        'auto' {
            $autoArgs = if ($MainArgs.Count -gt 1) { $MainArgs[1..($MainArgs.Count - 1)] } else { @() }
            Cmd-Auto $autoArgs
        }
        'next' { Cmd-Next }
        'help' { Cmd-Help }
        '-h' { Cmd-Help }
        '--help' { Cmd-Help }
        'version' { Write-Host "codex-switch v$Version" }
        '-v' { Write-Host "codex-switch v$Version" }
        '--version' { Write-Host "codex-switch v$Version" }
        '' { Cmd-Interactive }
        default {
            if (Test-ProfileExists $cmd) {
                Cmd-Launch $cmd
            }
            else {
                Write-ErrorMsg "Unknown command or profile: $cmd"
                Cmd-Help
                exit 1
            }
        }
    }
}

Main $args
