<#
.SYNOPSIS
    Bootstrap installer for Electron RTL Patcher.

.DESCRIPTION
    Convenience launcher meant for the one-line install:

        irm https://raw.githubusercontent.com/naor1237-tech/electron-rtl-patcher/main/install.ps1 | iex

    It enables TLS 1.2, makes sure patch.ps1 + apps.json are present (downloading
    them next to each other if you ran via irm|iex), then relaunches patch.ps1
    elevated so it can write to system-wide app folders (Program Files).

    If you cloned the repo, you do NOT need this file - just run:  .\patch.ps1

.NOTES
    TRUST MODEL (read this): irm|iex runs code off the internet. There is no code
    signing here yet, so you are trusting (a) GitHub and (b) the repo owner. The
    safe path is: clone the repo, read patch.ps1, then run it yourself. Only use
    the one-liner if you have reviewed the source.
#>

[CmdletBinding()]
param(
    [switch] $Auto,          # pass through: patch all detected apps, no menu
    [switch] $NoElevate      # skip the UAC elevation step
)

$ErrorActionPreference = 'Stop'
$RepoRaw = 'https://raw.githubusercontent.com/naor1237-tech/electron-rtl-patcher/main'  # placeholder until pushed

# PS 5.1 defaults to TLS 1.0; GitHub requires 1.2+.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Where are we? If patch.ps1 sits next to this script, run it locally.
$here = if ($PSScriptRoot) { $PSScriptRoot }
        elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
        else { $null }

$patchPath = $null
if ($here) {
    $candidate = Join-Path $here 'patch.ps1'
    if (Test-Path $candidate) { $patchPath = $candidate }
}

# Remote (irm|iex) path: fetch patch.ps1 + apps.json into a temp folder.
if (-not $patchPath) {
    $dir = Join-Path $env:TEMP ('electron-rtl-patcher-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "Downloading patcher to $dir ..." -ForegroundColor Cyan
    $wc = New-Object System.Net.WebClient
    try {
        $wc.DownloadFile("$RepoRaw/patch.ps1",  (Join-Path $dir 'patch.ps1'))
        $wc.DownloadFile("$RepoRaw/apps.json",  (Join-Path $dir 'apps.json'))
    } catch {
        Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Check your connection and that the repo URL in install.ps1 is correct." -ForegroundColor Yellow
        return
    }
    $patchPath = Join-Path $dir 'patch.ps1'
}

Write-Host "Patcher: $patchPath" -ForegroundColor Gray

# Build the argument list for patch.ps1.
$inner = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$patchPath`""
if ($Auto) { $inner += ' -Auto' }

if (-not $NoElevate -and -not (Test-Admin)) {
    Write-Host "Requesting administrator privileges (needed for Program Files installs)..." -ForegroundColor Cyan
    Start-Process -FilePath 'PowerShell.exe' -Verb RunAs -ArgumentList $inner
} else {
    # Already elevated, or elevation was declined: run in this session.
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $patchPath)
    if ($Auto) { $argList += '-Auto' }
    & PowerShell.exe @argList
}
