# FadoEXR Pipeline Manager Windows prerequisites (Windows PowerShell 5.1+).
# Installs Python 3.13 side by side and Gyan's full FFmpeg via winget only when needed.
# Upgrades a winget-managed FFmpeg at most once per seven days on normal app launches.
# Does not alter another application's custom FFmpeg or system Python defaults.
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$InstallMissing,
    [switch]$UpgradeFFmpeg,
    [switch]$ForceUpgradeCheck,
    [switch]$LaunchManager
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CheckOnly -and ($InstallMissing -or $UpgradeFFmpeg -or $LaunchManager)) {
    throw 'Use -CheckOnly by itself; it never installs or launches anything.'
}
if ($ForceUpgradeCheck -and -not $UpgradeFFmpeg) {
    throw '-ForceUpgradeCheck requires -UpgradeFFmpeg.'
}
if (-not $env:OS -or $env:OS -ne 'Windows_NT') {
    throw 'This setup script is for Windows 10/11. Linux/macOS should install dependencies using their own package manager.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$data = Join-Path $env:LOCALAPPDATA 'FadoEXR\PipelineManager'
$logFolder = Join-Path $data 'dependency-logs'
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
$logPath = Join-Path $logFolder ('dependencies-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$upgradeStamp = Join-Path $data 'ffmpeg-last-upgrade-check.utc'

function Say([string]$message) {
    $entry = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $message
    Write-Host $entry
    Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8
}

function Run-Exe([string]$file, [string[]]$arguments) {
    # Native programs may write benign diagnostics to stderr, including on PS 5.1.
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $file @arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
        return @{ Code = [int]$code; Output = [string]$output }
    } catch {
        return @{ Code = -1; Output = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $prior
    }
}

function Find-Python313 {
    $candidates = New-Object System.Collections.Generic.List[string]
    $py = Get-Command 'py.exe' -ErrorAction SilentlyContinue
    if ($py) {
        $result = Run-Exe $py.Source @('-3.13', '-c', 'import sys; print(sys.executable)')
        if ($result.Code -eq 0) { $candidates.Add($result.Output.Trim()) }
    }
    foreach ($regPath in @(
        'Registry::HKEY_CURRENT_USER\Software\Python\PythonCore\3.13\InstallPath',
        'Registry::HKEY_LOCAL_MACHINE\Software\Python\PythonCore\3.13\InstallPath',
        'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Python\PythonCore\3.13\InstallPath')) {
        if (Test-Path -LiteralPath $regPath) {
            try {
                $installPath = (Get-Item -LiteralPath $regPath).GetValue('')
                if ($installPath) { $candidates.Add((Join-Path $installPath 'python.exe')) }
            } catch { }
        }
    }
    foreach ($folder in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313'),
        (Join-Path $env:ProgramFiles 'Python313'),
        (Join-Path ${env:ProgramFiles(x86)} 'Python313'))) {
        if ($folder) { $candidates.Add((Join-Path $folder 'python.exe')) }
    }
    foreach ($name in @('python3.13.exe', 'python.exe')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $candidates.Add($command.Source) }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $version = Run-Exe $candidate @('-c', 'import sys; print(str(sys.version_info.major) + "." + str(sys.version_info.minor))')
        if ($version.Code -eq 0 -and $version.Output.Trim() -eq '3.13') {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Find-MediaTools {
    # Prefer the managed WinGet aliases when present; they may not be on the
    # current process PATH immediately after installation.
    $dirs = New-Object System.Collections.Generic.List[string]
    $dirs.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
    $dirs.Add((Join-Path $env:ProgramFiles 'WinGet\Links'))
    $existing = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    if ($existing) { $dirs.Add((Split-Path -Parent $existing.Source)) }
    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $packages -PathType Container) {
        $gyanPackages = @(Get-ChildItem -LiteralPath $packages -Directory -Filter 'Gyan.FFmpeg_*' -ErrorAction SilentlyContinue)
        foreach ($p in $gyanPackages) {
            foreach ($binary in @(Get-ChildItem -LiteralPath $p.FullName -Filter ffmpeg.exe -File -Recurse -ErrorAction SilentlyContinue)) {
                $dirs.Add($binary.DirectoryName)
            }
        }
    }
    foreach ($dir in ($dirs | Select-Object -Unique)) {
        if (-not $dir) { continue }
        $ff = Join-Path $dir 'ffmpeg.exe'
        $probe = Join-Path $dir 'ffprobe.exe'
        if (-not (Test-Path -LiteralPath $ff -PathType Leaf) -or
            -not (Test-Path -LiteralPath $probe -PathType Leaf)) { continue }
        $version = Run-Exe $ff @('-version')
        $probeVersion = Run-Exe $probe @('-version')
        $filters = Run-Exe $ff @('-filters')
        $ffv1 = Run-Exe $ff @('-hide_banner', '-h', 'encoder=ffv1')
        $exr = Run-Exe $ff @('-hide_banner', '-h', 'decoder=exr')
        if ($version.Code -eq 0 -and $probeVersion.Code -eq 0 -and
            $filters.Code -eq 0 -and $filters.Output -match '\bzscale\b' -and
            $filters.Output -match '\btonemap\b' -and
            $ffv1.Code -eq 0 -and $exr.Code -eq 0) {
            $line = ($version.Output -split "`r?`n" | Select-Object -First 1)
            return @{ FFmpeg=$ff; FFprobe=$probe; Directory=$dir; Version=$line }
        }
    }
    return $null
}

function Find-WinGet {
    $cmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function WinGet-Command([string]$winget, [string[]]$arguments) {
    Say ('winget ' + ($arguments -join ' '))
    $result = Run-Exe $winget $arguments
    if ($result.Output.Trim()) {
        Add-Content -LiteralPath $logPath -Value $result.Output -Encoding UTF8
        Write-Host $result.Output.TrimEnd()
    }
    Say ('winget exit code: ' + $result.Code)
    return $result
}

function Require-WinGet([string]$winget) {
    if (-not $winget) {
        throw 'Windows Package Manager (winget) is missing. Install Microsoft App Installer, reopen this window, and rerun Tools\SETUP-DEPENDENCIES.cmd. No files were changed by this script.'
    }
}

function WinGet-Install([string]$winget, [string]$packageId) {
    $argsList = @('install', '--id', $packageId, '--exact', '--source', 'winget',
                  '--accept-source-agreements', '--accept-package-agreements', '--silent')
    $result = WinGet-Command $winget $argsList
    if ($result.Code -ne 0) { throw ('WinGet could not install ' + $packageId + '. See: ' + $logPath) }
}

function Has-WingetFFmpeg([string]$winget) {
    if (-not $winget) { return $false }
    $result = WinGet-Command $winget @('list', '--id', 'Gyan.FFmpeg', '--exact', '--source', 'winget', '--accept-source-agreements')
    return ($result.Code -eq 0 -and $result.Output -match '(?i)\bGyan\.FFmpeg\b')
}

function Upgrade-WinGetFFmpeg([string]$winget) {
    if (-not $winget) { Say 'FFmpeg update skipped: winget unavailable.'; return }
    if (-not (Has-WingetFFmpeg $winget)) {
        Say 'Existing FFmpeg is not registered as Gyan.FFmpeg with winget. Leaving this custom installation intact.'
        return
    }
    $pending = WinGet-Command $winget @('upgrade', '--id', 'Gyan.FFmpeg', '--exact', '--source', 'winget', '--accept-source-agreements')
    if ($pending.Code -eq 0 -and $pending.Output -match '(?i)\bGyan\.FFmpeg\b') {
        Say 'A newer winget-managed Gyan.FFmpeg version is available. Upgrading it now.'
        $done = WinGet-Command $winget @('upgrade', '--id', 'Gyan.FFmpeg', '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements', '--silent')
        if ($done.Code -ne 0) {
            Say 'WARNING: FFmpeg upgrade failed. Keeping the previous installation if usable.'
            return
        }
        Say 'FFmpeg package upgrade completed.'
    } elseif ($pending.Output -match '(?i)no (available|applicable) upgrade|no newer package') {
        Say 'FFmpeg is already at the latest version offered by winget.'
    } else {
        Say 'WARNING: Could not establish FFmpeg upgrade status (for example, offline). Existing binaries were not removed.'
        return
    }
    $tmp = $upgradeStamp + '.tmp'
    [IO.File]::WriteAllText($tmp, [DateTime]::UtcNow.ToString('o'))
    Move-Item -LiteralPath $tmp -Destination $upgradeStamp -Force
}

function Should-CheckUpdates {
    if ($ForceUpgradeCheck) { return $true }
    if (-not (Test-Path -LiteralPath $upgradeStamp -PathType Leaf)) { return $true }
    try {
        $date = [DateTime]::Parse((Get-Content -LiteralPath $upgradeStamp -Raw))
        return ([DateTime]::UtcNow - $date.ToUniversalTime()).TotalDays -ge 7
    } catch { return $true }
}

function Main {
    Say 'Checking Python 3.13, FFmpeg, FFprobe and EXR/FFV1 conversion capabilities.'
    $python = Find-Python313
    $winget = Find-WinGet
    if (-not $python) {
        Say 'Python 3.13 is not currently available; other Python versions will not be changed.'
        if ($InstallMissing) {
            Require-WinGet $winget
            WinGet-Install $winget 'Python.Python.3.13'
            $python = Find-Python313
            if (-not $python) { throw 'Python 3.13 installed but is not discoverable yet. Restart the terminal and run setup again.' }
        }
    }
    if ($python) {
        Say ('Python 3.13: ' + $python)
        $tk = Run-Exe $python @('-c', 'import tkinter; print("Tkinter OK")')
        if ($tk.Code -ne 0) { throw ('Python 3.13 was found but Tkinter is unavailable. Use the standard python.org Python 3.13 installer. Details: ' + $tk.Output) }
    }

    $media = Find-MediaTools
    if (-not $media) {
        Say 'FFmpeg and FFprobe with required zscale, tonemap, FFV1 and EXR support are not available as a working pair.'
        if ($InstallMissing) {
            Require-WinGet $winget
            WinGet-Install $winget 'Gyan.FFmpeg'
            $media = Find-MediaTools
            if (-not $media) { throw 'FFmpeg installation completed, but ffmpeg/ffprobe capabilities were not found. Restart the terminal or inspect the log.' }
        }
    }
    if ($media) {
        Say ('FFmpeg:  ' + $media.FFmpeg)
        Say ('FFprobe: ' + $media.FFprobe)
        Say ('Version: ' + $media.Version)
    }
    if ($UpgradeFFmpeg -and $media -and (Should-CheckUpdates)) {
        Upgrade-WinGetFFmpeg $winget
        $media = Find-MediaTools
        if (-not $media) { throw 'FFmpeg is no longer usable after update. Re-run setup and check the dependency log.' }
    }
    if ($media) {
        # Pass the verified ffmpeg and ffprobe pair to our child Python process.
        # Never persist an altered machine/user PATH or replace other installations.
        $env:PATH = $media.Directory + [IO.Path]::PathSeparator + $env:PATH
    }
    if (-not $python -or -not $media) {
        throw 'Required tools are missing. Run Tools\SETUP-DEPENDENCIES.cmd (or install Python 3.13 and Gyan.FFmpeg manually).'
    }
    Say 'READY: Python 3.13 + Tkinter + FFmpeg + FFprobe + zscale/tonemap + FFV1/EXR checks passed.'
    if ($LaunchManager) {
        $app = Join-Path $repo 'Manager\fadoexr_manager.py'
        if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { throw ('Manager entrypoint missing: ' + $app) }
        Say 'Launching FadoEXR Pipeline Manager...'
        & $python $app
        if ($LASTEXITCODE -ne 0) { throw ('Pipeline Manager exited with code: ' + $LASTEXITCODE) }
    }
}

try {
    Main
    Say ('Dependency log: ' + $logPath)
    exit 0
} catch {
    Say ('ERROR: ' + $_.Exception.Message)
    Say ('Full dependency log: ' + $logPath)
    exit 1
}
