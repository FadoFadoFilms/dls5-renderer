# Download the newest complete 2600th/dlss5-video-player release to upstream\.
# Windows PowerShell 5.1 / Windows 10 and 11. No administrator rights needed.
# Only fetches assets published by the repository's GitHub Releases account.
# This does NOT execute the downloaded player. It runs the published package verifier.
[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = $PSScriptRoot
$upstream = Join-Path $root 'upstream'
$backupRoot = Join-Path $root 'upstream-backups'
$updateLogRoot = Join-Path $root 'update-logs'
New-Item -ItemType Directory -Force -Path $updateLogRoot | Out-Null
$log = Join-Path $updateLogRoot ('update-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$lock = $null
$stage = $null
$headers = @{ 'User-Agent' = 'RTX2060-DLSS5-Offline-Test-Updater'; 'Accept' = 'application/vnd.github+json' }

function Say([string]$message) {
    $line = '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $message
    Write-Host $line
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Fetch([string]$url, [string]$output) {
    Say ('Downloading ' + [IO.Path]::GetFileName($output) + ' from the official GitHub release...')
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $output -Headers @{ 'User-Agent' = 'RTX2060-DLSS5-Offline-Test-Updater' } -MaximumRedirection 5
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'Download produced no file.' }
}

try {
    # Prevent simultaneous manual, shortcut and installer-triggered updates.
    $lockPath = Join-Path $root 'renderer-update.lock'
    try {
        $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch { throw 'Another renderer update is in progress. Wait for it to finish.' }
    $activePlayer = @(Get-Process -Name 'DLSSVideoPlayer','NeuralWorker' -ErrorAction SilentlyContinue)
    if ($activePlayer.Count -gt 0) { throw 'Close DLSS Video Player and NeuralWorker before updating the renderer.' }
    Say 'Checking GitHub for the latest COMPLETE DLSS video player release (including neural runtime).'
    Say 'Source: https://github.com/2600th/dlss5-video-player/releases'

    # GitHub /releases/latest does not include pre-releases; the maintained
    # complete Windows builds currently are pre-releases, so query the release list.
    $api = 'https://api.github.com/repos/2600th/dlss5-video-player/releases?per_page=30'
    $releases = @(Invoke-RestMethod -Uri $api -Headers $headers -Method Get)
    $selected = $null
    $zipAsset = $null
    $hashAsset = $null
    foreach ($candidate in @($releases | Where-Object { -not $_.draft -and $_.published_at } | Sort-Object { [datetime]$_.published_at } -Descending)) {
        $tag = [string]$candidate.tag_name
        if ($tag -cnotmatch '^dlss5-video-player-v[0-9]+\.[0-9]+\.[0-9]+$') { continue }
        $name = $tag + '-win64.zip'
        $assets = @($candidate.assets)
        $z = @($assets | Where-Object { $_.name -ceq $name })
        $h = @($assets | Where-Object { $_.name -ceq ($name + '.sha256') })
        if ($z.Count -eq 1 -and $h.Count -eq 1) {
            $selected = $candidate
            $zipAsset = $z[0]
            $hashAsset = $h[0]
            break
        }
    }
    if ($null -eq $selected) {
        throw 'No published release contains BOTH the complete win64 ZIP and its matching .sha256. Nothing was changed.'
    }

    $tag = [string]$selected.tag_name
    $zipName = [string]$zipAsset.name
    Say ('Latest complete release: ' + $tag)
    if ([long]$zipAsset.size -le 1000000 -or [long]$zipAsset.size -gt 2147483648) {
        throw 'Unexpected complete-package download size. Refusing download.'
    }
    # The upstream verifier is strict: NEVER add metadata inside the package root.
    $stampPath = Join-Path $root 'renderer-version.json'
    if ((Test-Path -LiteralPath $stampPath -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upstream 'DLSSVideoPlayer.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upstream 'neural-runtime\NeuralWorker.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upstream 'PACKAGE_MANIFEST.txt') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upstream 'verify_package.ps1') -PathType Leaf) -and (-not $Force)) {
        try {
            $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
            if ([string]$stamp.tag -ceq $tag) {
                Say 'Already installed: this is the newest complete release. No files were replaced.'
                Say ('Installer log: ' + $log)
                exit 0
            }
        } catch { Say 'Could not read the existing release stamp; preserving the existing runtime as a backup.' }
    }

    $releaseBase = 'https://github.com/2600th/dlss5-video-player/releases/download/' + $tag + '/'
    # Do not trust arbitrary redirect targets supplied in the API response.
    # GitHub's official releases/download URL can redirect to its asset CDN.
    $expectedZipUrl = $releaseBase + $zipName
    $expectedHashUrl = $releaseBase + $zipName + '.sha256'
    if ([string]$zipAsset.browser_download_url -cne $expectedZipUrl -or [string]$hashAsset.browser_download_url -cne $expectedHashUrl) {
        throw 'Unexpected asset URLs in the GitHub API response. Nothing was changed.'
    }
    Say ('Download size: ' + [math]::Round([long]$zipAsset.size / 1MB) + ' MiB')
    Say 'NOTE: The neural runtime is a modified, unsigned community build; it is not an official NVIDIA product.'

    $stage = Join-Path $root ('renderer-update-stage-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $zipPath = Join-Path $stage $zipName
    $shaPath = Join-Path $stage ($zipName + '.sha256')
    # Verify BEFORE extracting or invoking anything from the downloaded ZIP.
    Fetch $expectedHashUrl $shaPath
    Fetch $expectedZipUrl $zipPath
    $shaText = Get-Content -LiteralPath $shaPath -Raw
    $hashMatches = [regex]::Matches($shaText, '(?m)^([a-fA-F0-9]{64})\s+\*?([^\r\n]+)\r?$')
    if ($hashMatches.Count -ne 1 -or $hashMatches[0].Groups[2].Value.Trim() -cne $zipName) {
        throw 'The published SHA-256 file does not name the expected complete-package ZIP.'
    }
    $expectedHash = $hashMatches[0].Groups[1].Value.ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -cne $expectedHash) { throw 'SHA-256 MISMATCH: download rejected and existing player left untouched.' }
    Say ('SHA-256 verified: ' + $actualHash)

    # Validate ZIP names and sizes before extraction (no zip-slip/symlinks/bombs).
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($archive.Entries.Count -gt 20000) { throw 'ZIP contains too many entries.' }
        [long]$unpackedTotal = 0
        foreach ($entry in $archive.Entries) {
            $rel = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($rel) -or $rel.StartsWith('/') -or $rel.Contains(':') -or $rel.Contains('//')) {
                throw ('Unsafe ZIP entry path: ' + $rel)
            }
            if (@($rel.Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw ('ZIP traversal entry rejected: ' + $rel)
            }
            $unixType = ($entry.ExternalAttributes -shr 16) -band 61440
            if ($unixType -eq 40960) { throw ('ZIP symbolic link refused: ' + $rel) }
            if ([long]$entry.Length -gt 2147483648) { throw ('ZIP entry too large: ' + $rel) }
            $unpackedTotal += [long]$entry.Length
            if ($unpackedTotal -gt 6442450944) { throw 'Unpacked ZIP exceeds 6 GiB safety limit.' }
        }
    } finally { $archive.Dispose() }
    Say 'ZIP entries passed path and size checks. Extracting into a separate staging directory...'
    $extractDir = Join-Path $stage 'extracted'
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)

    $players = @(Get-ChildItem -LiteralPath $extractDir -Filter 'DLSSVideoPlayer.exe' -File -Recurse)
    if ($players.Count -ne 1) { throw ('Expected one DLSSVideoPlayer.exe in ZIP, found ' + $players.Count) }
    $newRoot = $players[0].DirectoryName
    foreach ($required in @('verify_package.ps1','PACKAGE_MANIFEST.txt','neural-runtime\NeuralWorker.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $newRoot $required) -PathType Leaf)) {
            throw ('Incomplete runtime package: missing ' + $required)
        }
    }
    Say 'Running the upstream package manifest verifier before activation...'
    $verifyLog = Join-Path $updateLogRoot ('verify-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $newRoot 'verify_package.ps1') *> $verifyLog
    if ($LASTEXITCODE -ne 0) { throw ('Upstream verify_package.ps1 failed. See ' + $verifyLog) }
    Say ('Upstream package verifier passed. Log: ' + $verifyLog)

    # Preserve the entire installed runtime (including any user-added files).
    $backup = $null
    $oldMoved = $false
    if (Test-Path -LiteralPath $upstream) {
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        $backup = Join-Path $backupRoot ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    }
    try {
        if ($null -ne $backup) {
            Move-Item -LiteralPath $upstream -Destination $backup -ErrorAction Stop
            $oldMoved = $true
            Say ('Previous upstream contents preserved at: ' + $backup)
        }
        Move-Item -LiteralPath $newRoot -Destination $upstream -ErrorAction Stop
        $stampData = [ordered]@{
            tag = $tag
            installed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            zip_name = $zipName
            sha256 = $actualHash
            source = '2600th/dlss5-video-player GitHub Releases'
            previous_runtime_backup = $backup
        }
        ($stampData | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $stampPath -Encoding UTF8
    } catch {
        Say ('Activation failed: ' + $_.Exception.Message)
        # Roll back on failure, including failure while writing the release stamp.
        if ($oldMoved -and (Test-Path -LiteralPath $backup)) {
            if (Test-Path -LiteralPath $upstream) {
                try { Remove-Item -LiteralPath $upstream -Force -Recurse -ErrorAction Stop } catch { Say 'Could not delete incomplete new player; manual rollback may be needed.' }
            }
            if (-not (Test-Path -LiteralPath $upstream)) {
                Move-Item -LiteralPath $backup -Destination $upstream -ErrorAction Stop
                Say 'Previous player restored.'
            }
        }
        throw
    }
    Say ('SUCCESS: ' + $tag + ' is ready in upstream\ with the complete neural runtime.')
    Say 'Open the DLSS Player shortcut, or use Probe Only for an RTX 2060 compatibility test.'
    Say ('Update log saved to ' + $log)
    exit 0
} catch {
    Say ('UPDATE FAILED: ' + $_.Exception.Message)
    Say 'Your previously installed upstream renderer and results were not intentionally overwritten.'
    Say ('Read the error log: ' + $log)
    exit 1
} finally {
    if ($null -ne $stage -and (Test-Path -LiteralPath $stage)) {
        try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop }
        catch { Say ('Could not delete staging folder: ' + $stage) }
    }
    if ($null -ne $lock) { $lock.Dispose() }
}
