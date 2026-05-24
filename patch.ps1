<#
.SYNOPSIS
    Electron RTL Patcher - universal Hebrew/Arabic RTL support for Electron apps on Windows.

.DESCRIPTION
    Injects a smart, app-agnostic RTL stylesheet + script into Electron desktop
    apps (Claude Desktop, VS Code, Cursor, ChatGPT, Slack, ...). It uses the
    Unicode bidi algorithm (unicode-bidi: plaintext) so each paragraph picks its
    own direction from its first strong character - Hebrew/Arabic flow RTL,
    English and code stay LTR - without rewriting the DOM (which breaks React).

    Every change is backed up first and is fully reversible (Restore).

.PARAMETER Auto
    Patch every detected app without the interactive menu.

.PARAMETER Restore
    Restore mode. With -AppId, restores that app; otherwise restores all.

.PARAMETER AppId
    Operate on a single app id from apps.json (e.g. "claude", "vscode").

.PARAMETER NonInteractive
    Never prompt. Implied by -Auto.

.NOTES
    Author : Naor Hilel - Hilel Solutions (solutions.hilel.link)
    License: MIT. Independent tool, not affiliated with any vendor.
#>

[CmdletBinding()]
param(
    [switch] $Auto,
    [switch] $Restore,
    [string] $AppId,
    [switch] $NonInteractive
)

if ($Auto) { $NonInteractive = $true }
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Globals
# ----------------------------------------------------------------------------
$RepoRaw       = 'https://raw.githubusercontent.com/naor1237-tech/electron-rtl-patcher/main'  # placeholder until pushed
$AsarPackage   = '@electron/asar@4.2.0'
$Marker        = 'electron-rtl-patch'                       # idempotency / detection marker
$StateDir      = Join-Path $env:ProgramData 'ElectronRtlPatch'
$BackupDir     = Join-Path $StateDir 'backups'
$StateFile     = Join-Path $StateDir 'state.json'
$LogFile       = Join-Path $StateDir 'patch.log'
$TmpRoot       = Join-Path ([System.IO.Path]::GetTempPath()) 'electron_rtl_patch'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
             else { $null }

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
function Write-Log([string]$Msg, [string]$Level = 'INFO') {
    try {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        Add-Content -Path $LogFile -Value ("{0}  [{1}]  {2}" -f (Get-Date -Format 's'), $Level, $Msg) -Encoding UTF8
    } catch { }
}
function Info($m)    { Write-Host $m -ForegroundColor Gray;    Write-Log $m 'INFO' }
function Step($m)    { Write-Host $m -ForegroundColor Cyan;    Write-Log $m 'STEP' }
function Good($m)    { Write-Host $m -ForegroundColor Green;   Write-Log $m 'OK'   }
function Warn($m)    { Write-Host $m -ForegroundColor Yellow;  Write-Log $m 'WARN' }
function Err($m)     { Write-Host $m -ForegroundColor Red;     Write-Log $m 'ERR'  }

# ----------------------------------------------------------------------------
# The RTL payload injected into each app (CSS + JS). Pure ASCII on purpose so it
# survives any encoding step. App-agnostic: relies on the Unicode bidi algorithm
# and never rewrites the DOM.
# ----------------------------------------------------------------------------
$RtlPayloadJs = @'
/* Electron RTL Patch - injected. Safe to remove by deleting this <script>. */
(function () {
  if (window.__electronRtlPatch) return;
  window.__electronRtlPatch = true;

  // Strong-RTL Unicode blocks: Hebrew, Arabic, Arabic Supplement,
  // Arabic Extended-A, Hebrew/Arabic presentation forms A & B.
  function isRtlChar(c) {
    return (c >= 0x0590 && c <= 0x05FF) ||
           (c >= 0x0600 && c <= 0x06FF) ||
           (c >= 0x0750 && c <= 0x077F) ||
           (c >= 0x08A0 && c <= 0x08FF) ||
           (c >= 0xFB1D && c <= 0xFDFF) ||
           (c >= 0xFE70 && c <= 0xFEFF);
  }
  function hasRtl(s) {
    if (!s) return false;
    for (var i = 0; i < s.length; i++) {
      if (isRtlChar(s.charCodeAt(i))) return true;
    }
    return false;
  }

  function injectStyle() {
    if (document.getElementById('electron-rtl-style')) return;
    var css = [
      /* Let the Unicode bidi algorithm pick direction per paragraph from the */
      /* first strong character. No DOM rewriting => React stays happy.        */
      'body,p,span,div,li,td,th,h1,h2,h3,h4,h5,h6,label,button,blockquote,',
      '.markdown,[class*="message"],[class*="text"],[class*="content"] {',
      '  unicode-bidi: plaintext;',
      '  text-align: start;',
      '}',
      'input,textarea,[contenteditable="true"],[role="textbox"] {',
      '  unicode-bidi: plaintext;',
      '  text-align: start;',
      '}',
      /* Code must stay strictly LTR so it never mangles. */
      'pre,code,kbd,samp,pre *,code * {',
      '  unicode-bidi: normal !important;',
      '  direction: ltr !important;',
      '  text-align: left !important;',
      '}'
    ].join('\n');
    var s = document.createElement('style');
    s.id = 'electron-rtl-style';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }

  // Belt-and-suspenders for layouts where CSS plaintext alone is not enough:
  // stamp dir="auto" on text-bearing blocks that contain RTL. Setting an
  // attribute does NOT mutate children, so React reconciliation is untouched
  // and the MutationObserver (childList only) does not re-fire on it.
  function stampDir(root) {
    if (!root || !root.querySelectorAll) return;
    var els = root.querySelectorAll('p,li,h1,h2,h3,h4,h5,h6,td,th,blockquote,label');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.closest && el.closest('pre,code')) continue;
      if (el.hasAttribute('dir')) continue;
      var t = el.textContent;
      if (t && hasRtl(t)) el.setAttribute('dir', 'auto');
    }
  }

  function boot() {
    injectStyle();
    try { stampDir(document.body); } catch (e) {}
    var pending = false;
    var schedule = window.requestAnimationFrame || function (f) { return setTimeout(f, 50); };
    var mo = new MutationObserver(function () {
      if (pending) return;
      pending = true;
      schedule(function () {
        pending = false;
        injectStyle();
        try { stampDir(document.body); } catch (e) {}
      });
    });
    try { mo.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
'@

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Expand-Path([string]$p) {
    [System.Environment]::ExpandEnvironmentVariables($p)
}

function Get-AppCatalog {
    # Prefer apps.json next to this script; fall back to downloading it.
    if ($ScriptDir) {
        $local = Join-Path $ScriptDir 'apps.json'
        if (Test-Path $local) {
            return (Get-Content $local -Raw -Encoding UTF8 | ConvertFrom-Json).apps
        }
    }
    Step "apps.json not found locally - downloading from repo..."
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $json = (New-Object System.Net.WebClient).DownloadString("$RepoRaw/apps.json")
    return ($json | ConvertFrom-Json).apps
}

# Resolve the on-disk target (asar file or app dir) for a catalog entry.
function Resolve-AppTarget($app) {
    foreach ($base in $app.bases) {
        $root = Expand-Path $base
        if (-not (Test-Path $root)) { continue }
        # The target ("resources\app.asar" or "resources\app") may sit directly
        # under the base or under a per-version "app-<ver>" subfolder.
        $candidates = @()
        $candidates += (Join-Path $root $app.target)
        Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates += (Join-Path $_.FullName $app.target)
        }
        # Newest first so we patch the most recent installed version.
        # @() forces an array: a single match must NOT collapse to a [string],
        # or $hits[0] would return its first character instead of the path.
        $hits = @($candidates | Where-Object { Test-Path $_ } |
                  Sort-Object { (Get-Item $_).LastWriteTime } -Descending)
        if ($hits.Count -gt 0) { return $hits[0] }
    }
    return $null
}

function New-Backup([string]$appId, [string]$sourcePath) {
    $appBackupDir = Join-Path $BackupDir $appId
    if (-not (Test-Path $appBackupDir)) { New-Item -ItemType Directory -Path $appBackupDir -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name  = Split-Path $sourcePath -Leaf
    $dest  = Join-Path $appBackupDir ("{0}.{1}.bak" -f $name, $stamp)
    Copy-Item -LiteralPath $sourcePath -Destination $dest -Force
    Add-StateRecord -AppId $appId -Target $sourcePath -Backup $dest
    return $dest
}

function Get-State {
    if (Test-Path $StateFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($StateFile)
            if (-not $raw.Trim()) { return @() }
            # Keep only well-formed records (defends against any legacy/corrupt file).
            return @($raw | ConvertFrom-Json | Where-Object { $null -ne $_.app })
        } catch { return @() }
    }
    return @()
}
function Save-State($records) {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $arr  = @($records)
    $json = ConvertTo-Json -InputObject $arr -Depth 6
    # PS 5.1 serializes a single-element array as a bare object; normalize to a JSON array.
    if (-not $json.TrimStart().StartsWith('[')) { $json = "[$json]" }
    [System.IO.File]::WriteAllText($StateFile, $json, (New-Object System.Text.UTF8Encoding($false)))
}
function Add-StateRecord([string]$AppId, [string]$Target, [string]$Backup) {
    # Enumerate with foreach (NOT @(Get-State)): wrapping a function that returns
    # an array in @() nests it, turning each existing record into a sub-array.
    $records = @()
    foreach ($e in (Get-State)) { $records += $e }
    $records += [pscustomobject]@{
        app    = $AppId
        target = $Target
        backup = $Backup
        time   = (Get-Date -Format 's')
    }
    Save-State $records
}

# Insert the <script> before </head> (or </body>, or append). Idempotent.
function Add-Injection([string]$htmlPath) {
    $content = [System.IO.File]::ReadAllText($htmlPath)
    if ($content -like "*id=""$Marker""*") { return $false }   # already patched
    $tag = "<script id=""$Marker"">`n$RtlPayloadJs`n</script>`n"

    foreach ($anchor in @('</head>', '</body>', '</html>')) {
        $idx = $content.IndexOf($anchor, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx -ge 0) {
            $content = $content.Substring(0, $idx) + $tag + $content.Substring($idx)
            [System.IO.File]::WriteAllText($htmlPath, $content, (New-Object System.Text.UTF8Encoding($false)))
            return $true
        }
    }
    # No anchor - append.
    [System.IO.File]::WriteAllText($htmlPath, $content + "`n" + $tag, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Get-Npx {
    $cmd = Get-Command npx -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command npx.cmd -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Asar([string]$Action, [string]$A, [string]$B) {
    $npx = Get-Npx
    if (-not $npx) {
        throw "npx (Node.js) not found in PATH. Install Node.js from https://nodejs.org and retry."
    }
    & $npx --yes $AsarPackage $Action $A $B 2>&1 | ForEach-Object { Write-Log $_ 'ASAR' }
    if ($LASTEXITCODE -ne 0) { throw "asar $Action failed (exit $LASTEXITCODE). See $LogFile." }
}

# ----------------------------------------------------------------------------
# Patch / Restore per app type
# ----------------------------------------------------------------------------
function Get-InjectableHtml([string]$root, [string]$match) {
    Get-ChildItem -Path $root -Recurse -Filter $match -ErrorAction SilentlyContinue |
        Where-Object { Select-String -Path $_.FullName -Pattern '</head>|</body>|</html>' -Quiet -ErrorAction SilentlyContinue }
}

function Test-AlreadyPatched([string]$htmlPath) {
    ([System.IO.File]::ReadAllText($htmlPath)) -like "*id=""$Marker""*"
}

function Invoke-AsarAppPatch($app, [string]$asarPath) {
    $work = Join-Path $TmpRoot ($app.id + '_' + (Get-Date -Format 'HHmmss'))
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work -Force | Out-Null

    Step "  Extracting app.asar..."
    Invoke-Asar -Action 'extract' -A $asarPath -B $work

    $htmls = @(Get-InjectableHtml -root $work -match $app.htmlMatch)
    if ($htmls.Count -eq 0) { Remove-Item $work -Recurse -Force; throw "No injectable HTML (matching '$($app.htmlMatch)') found inside the asar." }

    $patched = 0
    foreach ($h in $htmls) {
        if (Add-Injection $h.FullName) { Info "    + injected into $($h.Name)"; $patched++ }
    }
    if ($patched -eq 0) { Warn "    (already patched - nothing to do)"; Remove-Item $work -Recurse -Force; return }

    # Back up the still-pristine original only now that we know we changed something.
    Step "  Backing up app.asar..."
    $null = New-Backup -appId $app.id -sourcePath $asarPath

    Step "  Repacking app.asar..."
    $newAsar = "$asarPath.new"
    if (Test-Path $newAsar) { Remove-Item $newAsar -Force }
    Invoke-Asar -Action 'pack' -A $work -B $newAsar

    if (-not (Test-Path $newAsar) -or (Get-Item $newAsar).Length -lt 1024) {
        Remove-Item $newAsar -Force -ErrorAction SilentlyContinue
        throw "Repacked asar looks invalid (too small). Original left untouched."
    }
    Move-Item -LiteralPath $newAsar -Destination $asarPath -Force
    Remove-Item $work -Recurse -Force
    Good "  Done - $patched HTML file(s) patched in $($app.name)."
}

function Invoke-DirAppPatch($app, [string]$appDir) {
    $htmls = @(Get-InjectableHtml -root $appDir -match $app.htmlMatch)
    if ($htmls.Count -eq 0) { throw "No injectable HTML (matching '$($app.htmlMatch)') found in $appDir." }

    $patched = 0
    foreach ($h in $htmls) {
        if (Test-AlreadyPatched $h.FullName) { continue }   # don't back up an already-patched file
        $null = New-Backup -appId $app.id -sourcePath $h.FullName
        if (Add-Injection $h.FullName) { Info "    + injected into $($h.Name)"; $patched++ }
    }
    if ($patched -eq 0) { Warn "  (already patched - nothing to do)"; return }
    Good "  Done - $patched HTML file(s) patched in $($app.name)."
}

function Invoke-AppPatch($app) {
    Step "==> $($app.name)"
    $target = Resolve-AppTarget $app
    if (-not $target) { Warn "  Not installed (or path not recognized). Skipping."; return }
    Info "  Found: $target"
    try {
        if ($app.type -eq 'asar') { Invoke-AsarAppPatch $app $target }
        else                      { Invoke-DirAppPatch  $app $target }
    } catch {
        Err "  Failed: $($_.Exception.Message)"
    }
}

function Restore-App($app) {
    Step "==> Restoring $($app.name)"
    $records = @()
    foreach ($e in (Get-State)) { if ($e.app -eq $app.id) { $records += $e } }
    if ($records.Count -eq 0) { Warn "  No backups recorded. Nothing to restore."; return }
    # Newest backup per target.
    $byTarget = $records | Group-Object target
    foreach ($g in $byTarget) {
        $latest = $g.Group | Sort-Object time -Descending | Select-Object -First 1
        if (Test-Path $latest.backup) {
            Copy-Item -LiteralPath $latest.backup -Destination $latest.target -Force
            Good "  Restored $($latest.target)"
        } else {
            Warn "  Backup missing: $($latest.backup)"
        }
    }
}

# ----------------------------------------------------------------------------
# UI
# ----------------------------------------------------------------------------
function Get-AppStatus($app) {
    $target = Resolve-AppTarget $app
    if (-not $target) { return 'not installed' }
    if ($app.type -eq 'asar') { return 'installed' }   # can't cheaply peek inside asar
    $hit = Get-ChildItem -Path $target -Recurse -Filter $app.htmlMatch -ErrorAction SilentlyContinue |
           Where-Object { Select-String -Path $_.FullName -Pattern "id=""$Marker""" -Quiet -ErrorAction SilentlyContinue } |
           Select-Object -First 1
    if ($hit) { return 'PATCHED' } else { return 'installed' }
}

function Show-Banner {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host "    Electron RTL Patcher  -  RTL Hebrew/Arabic for Electron"    -ForegroundColor White
    Write-Host "    by Naor Hilel / Hilel Solutions   (MIT, independent tool)"  -ForegroundColor DarkGray
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    if (-not (Test-Admin)) {
        Write-Host "  (no admin - system-wide installs e.g. Program Files may be read-only)" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

function Show-Menu($apps) {
    Show-Banner
    Write-Host "  Detected apps:" -ForegroundColor White
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $a = $apps[$i]
        $st = Get-AppStatus $a
        $color = switch ($st) { 'PATCHED' {'Green'} 'installed' {'Cyan'} default {'DarkGray'} }
        $flag = if ($a.tested) { '' } else { ' (experimental)' }
        Write-Host ("    {0}. {1,-22} [{2}]{3}" -f ($i+1), $a.name, $st, $flag) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "    A. Patch ALL installed apps" -ForegroundColor White
    Write-Host "    R. Restore an app" -ForegroundColor White
    Write-Host "    Q. Quit" -ForegroundColor White
    Write-Host ""
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
$apps = @(Get-AppCatalog)
if (-not $apps -or $apps.Count -eq 0) { Err "No app catalog available."; return }

# --- Non-interactive paths ---
if ($Restore) {
    $targets = if ($AppId) { @($apps | Where-Object { $_.id -eq $AppId }) } else { $apps }
    foreach ($a in $targets) { Restore-App $a }
    return
}
if ($AppId) {
    $a = $apps | Where-Object { $_.id -eq $AppId } | Select-Object -First 1
    if (-not $a) { Err "Unknown app id '$AppId'."; return }
    Invoke-AppPatch $a
    Good "`nFinished. Fully restart $($a.name) to see the change."
    return
}
if ($Auto) {
    Show-Banner
    foreach ($a in $apps) {
        if ((Resolve-AppTarget $a)) { Invoke-AppPatch $a }
    }
    Good "`nFinished. Fully restart any patched app to see the change."
    return
}

# --- Interactive menu ---
while ($true) {
    Show-Menu $apps
    $choice = Read-Host "  Select"
    $choice = ($choice + '').Trim()
    if ($choice -match '^[Qq]$') { break }
    elseif ($choice -match '^[Aa]$') {
        foreach ($a in $apps) { if ((Resolve-AppTarget $a)) { Invoke-AppPatch $a } }
        Good "`nDone. Fully restart any patched app to see the change."
        Read-Host "`n  Press Enter to continue" | Out-Null
    }
    elseif ($choice -match '^[Rr]$') {
        $rid = Read-Host "  App id to restore (or 'all')"
        if ($rid -eq 'all') { foreach ($a in $apps) { Restore-App $a } }
        else {
            $a = $apps | Where-Object { $_.id -eq $rid } | Select-Object -First 1
            if ($a) { Restore-App $a } else { Warn "  Unknown id." }
        }
        Read-Host "`n  Press Enter to continue" | Out-Null
    }
    elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $apps.Count) {
        Invoke-AppPatch $apps[[int]$choice - 1]
        Good "`nDone. Fully restart the app to see the change."
        Read-Host "`n  Press Enter to continue" | Out-Null
    }
    else { Warn "  Invalid choice." }
}

Write-Host "`n  Bye. Backups & logs: $StateDir" -ForegroundColor DarkGray
