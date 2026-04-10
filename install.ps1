Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = 'jonesfernandess/codex-switch'
$InstallDir = Join-Path $HOME '.local\bin'
$PsScriptName = 'codex-switch.ps1'
$CmdShimName = 'codex-switch.cmd'
$InstallerName = 'install.ps1'

function Write-Info([string]$Message) { Write-Host ":: $Message" -ForegroundColor Cyan }
function Write-Success([string]$Message) { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-ErrorMsg([string]$Message) { Write-Host "[ERR] $Message" -ForegroundColor Red; exit 1 }

function Ensure-ProfileFile {
    if (-not $PROFILE) {
        return (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
    }
    return $PROFILE
}

function Add-AutoAlias {
    $profilePath = Ensure-ProfileFile
    $parent = Split-Path -Path $profilePath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath | Out-Null
    }

    $aliasLine = "function codex { codex-switch auto @args }"
    $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue

    if ($content -match [Regex]::Escape($aliasLine)) {
        Write-Warn "Alias already present in $profilePath"
        return
    }

    Add-Content -Path $profilePath -Value "`n# codex-switch: auto-switch accounts on every codex call`n$aliasLine`n"
    Write-Success "Alias added to $profilePath"
    Write-Host "Run '. `$PROFILE' or open a new PowerShell session to activate."
}

function Install-CmdShim([string]$ScriptPath) {
    $shimPath = Join-Path $InstallDir $CmdShimName
    $shim = "@echo off`r`nsetlocal`r`npwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"$ScriptPath\" %*`r`n"
    Set-Content -Path $shimPath -Value $shim -NoNewline
    Write-Success "Installed $shimPath"
}

function Check-Deps {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-Warn 'Codex CLI not found. Install it first:'
        Write-Host '    https://github.com/openai/codex'
    }

    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Warn 'PowerShell 7+ (pwsh) not found in PATH.'
        Write-Warn 'Install from: https://github.com/PowerShell/PowerShell'
    }
}

function Install {
    Write-Host ''
    Write-Host 'Codex Switch - Windows installer' -ForegroundColor Cyan
    Write-Host ''

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $scriptUrl = "https://raw.githubusercontent.com/$Repo/main/codex-switch.ps1"
    $installerUrl = "https://raw.githubusercontent.com/$Repo/main/install.ps1"
    $scriptPath = Join-Path $InstallDir $PsScriptName
    $installerPath = Join-Path $InstallDir $InstallerName

    Write-Info 'Downloading codex-switch.ps1...'
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -UseBasicParsing
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    }
    catch {
        Write-ErrorMsg "Failed to download installer assets from GitHub."
    }

    Write-Success "Installed $scriptPath"
    Write-Success "Installed $installerPath"
    Install-CmdShim -ScriptPath $scriptPath

    $pathEntries = ($env:PATH -split ';') | ForEach-Object { $_.Trim() }
    if ($pathEntries -notcontains $InstallDir) {
        Write-Warn "$InstallDir is not in your PATH."
        Write-Host 'Add it via System Settings > Environment Variables, or run:'
        Write-Host "  [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';$InstallDir', 'User')"
    }

    Check-Deps

    Write-Host ''
    Write-Host 'Optional: make every codex call auto-switch accounts.'
    $answer = Read-Host "Add PowerShell alias in `$PROFILE? [y/N]"
    if ($answer -in @('y', 'Y')) {
        Add-AutoAlias
    }
    else {
        Write-Info 'Skipped. You can add this manually:'
        Write-Host "  function codex { codex-switch auto @args }"
    }

    Write-Host ''
    Write-Success 'Installation complete!'
    Write-Host ''
    Write-Host 'Get started:'
    Write-Host '  codex-switch create work'
    Write-Host '  codex-switch work'
    Write-Host '  codex-switch auto'
    Write-Host ''
}

function Uninstall {
    Write-Host ''
    Write-Host 'Codex Switch - Windows uninstaller' -ForegroundColor Cyan
    Write-Host ''

    $scriptPath = Join-Path $InstallDir $PsScriptName
    $shimPath = Join-Path $InstallDir $CmdShimName
    $installerPath = Join-Path $InstallDir $InstallerName

    if (Test-Path $scriptPath) {
        Remove-Item -Path $scriptPath -Force
        Write-Success "Removed $scriptPath"
    } else {
        Write-Warn "$scriptPath not found"
    }

    if (Test-Path $shimPath) {
        Remove-Item -Path $shimPath -Force
        Write-Success "Removed $shimPath"
    } else {
        Write-Warn "$shimPath not found"
    }

    if (Test-Path $installerPath) {
        Remove-Item -Path $installerPath -Force
        Write-Success "Removed $installerPath"
    } else {
        Write-Warn "$installerPath not found"
    }

    Write-Host ''
    Write-Info 'Profile directories (~/.codex-*) were not removed.'
    Write-Info 'Remove them manually if needed.'
    Write-Host ''
}

if ($args.Count -gt 0 -and ($args[0] -eq 'uninstall' -or $args[0] -eq '--uninstall')) {
    Uninstall
} else {
    Install
}
