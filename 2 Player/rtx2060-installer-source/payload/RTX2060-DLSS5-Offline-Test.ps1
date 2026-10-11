[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$InputVideo,

    [Parameter(Mandatory=$false)]
    [string]$PlayerRoot = (Join-Path $PSScriptRoot 'upstream'),

    [Parameter(Mandatory=$false)]
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'results'),

    [ValidateSet('natural','detail-only','gentle','strong')]
    [string]$Preset = 'natural',

    [ValidateRange(1,1000)]
    [int]$FrameProbeCount = 5,

    [ValidateRange(1,300)]
    [int]$CapabilityProbeFrames = 12,

    [switch]$ProbeOnly,
    [switch]$SkipFrameProbes,
    [switch]$NoScaleFallback,
    [switch]$SkipPackageVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host $Text
    Write-Host ('=' * 72)
}

function Safe-FileStem([string]$Name) {
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $chars = $Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    }
    return (-join $chars)
}

function Find-Executable([string]$Root, [string]$Name) {
    $direct = Join-Path $Root $Name
    if (Test-Path -LiteralPath $direct -PathType Leaf) { return (Resolve-Path -LiteralPath $direct).Path }
    $found = Get-ChildItem -LiteralPath $Root -Filter $Name -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $found) { return $found.FullName }
    return $null
}

function Get-NvidiaSmiPath {
    $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    $default = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path -LiteralPath $default -PathType Leaf) { return $default }
    return $null
}

function Convert-ToDoubleOrNull([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parsed = 0.0
    if ([double]::TryParse($Value.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Test-DriverAtLeast([string]$Actual, [string]$Minimum) {
    try {
        return ([version]$Actual -ge [version]$Minimum)
    } catch {
        return $null
    }
}

function Get-GpuSnapshot([string]$SmiPath) {
    if ([string]::IsNullOrWhiteSpace($SmiPath)) { return $null }
    $query = 'name,driver_version,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu,power.draw'
    $raw = & $SmiPath "--query-gpu=$query" '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $parts = $raw -split ',\s*'
    if ($parts.Count -lt 8) { return $null }
    return [pscustomobject]@{
        Name          = $parts[0]
        DriverVersion = $parts[1]
        MemoryTotalMB = Convert-ToDoubleOrNull $parts[2]
        MemoryUsedMB  = Convert-ToDoubleOrNull $parts[3]
        MemoryFreeMB  = Convert-ToDoubleOrNull $parts[4]
        UtilGpuPct    = Convert-ToDoubleOrNull $parts[5]
        TemperatureC  = Convert-ToDoubleOrNull $parts[6]
        PowerW        = Convert-ToDoubleOrNull $parts[7]
    }
}

function Start-GpuSampler([string]$SmiPath, [string]$CsvPath, [int]$IntervalMs = 500) {
    if ([string]::IsNullOrWhiteSpace($SmiPath)) { return $null }
    'timestamp,name,driver_version,memory_total_mb,memory_used_mb,memory_free_mb,util_gpu_pct,temp_c,power_w' | Set-Content -LiteralPath $CsvPath -Encoding UTF8
    $job = Start-Job -ScriptBlock {
        param($Smi, $Csv, $Ms)
        $query = 'name,driver_version,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu,power.draw'
        while ($true) {
            try {
                $raw = & $Smi "--query-gpu=$query" '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $ts = (Get-Date).ToString('o')
                    Add-Content -LiteralPath $Csv -Value ($ts + ',' + $raw) -Encoding UTF8
                }
            } catch { }
            Start-Sleep -Milliseconds $Ms
        }
    } -ArgumentList $SmiPath, $CsvPath, $IntervalMs
    return $job
}

function Stop-GpuSampler($Job) {
    if ($null -eq $Job) { return }
    try { Stop-Job -Job $Job -ErrorAction SilentlyContinue | Out-Null } catch { }
    try { Receive-Job -Job $Job -ErrorAction SilentlyContinue | Out-Null } catch { }
    try { Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
}

function Append-Event([string]$CsvPath, [string]$Phase, [string]$State, [string]$Detail='') {
    if (-not (Test-Path -LiteralPath $CsvPath)) {
        'timestamp,phase,state,detail' | Set-Content -LiteralPath $CsvPath -Encoding UTF8
    }
    $safeDetail = $Detail.Replace('"','""')
    $line = '"{0}","{1}","{2}","{3}"' -f (Get-Date).ToString('o'), $Phase, $State, $safeDetail
    Add-Content -LiteralPath $CsvPath -Value $line -Encoding UTF8
}

function Invoke-UpstreamRender {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$LogPath,
        [string]$Phase,
        [string]$EventsCsv,
        [string]$WorkingDirectory
    )
    Append-Event $EventsCsv $Phase 'start' (($Arguments -join ' '))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $exitCode = -999
    $locationPushed = $false
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Push-Location -LiteralPath $WorkingDirectory
            $locationPushed = $true
        }
        & $Exe @Arguments 2>&1 | ForEach-Object {
            $line = '[{0}] {1}' -f (Get-Date).ToString('o'), $_
            Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
            Write-Host $line
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $errorLine = '[{0}] HARNESS EXCEPTION: {1}' -f (Get-Date).ToString('o'), $_.Exception.Message
        Add-Content -LiteralPath $LogPath -Value $errorLine -Encoding UTF8
        Write-Host $errorLine
        $exitCode = -998
    } finally {
        if ($locationPushed) { Pop-Location }
    }
    $sw.Stop()
    Append-Event $EventsCsv $Phase 'end' ("exit={0}; elapsed_ms={1}" -f $exitCode, [math]::Round($sw.Elapsed.TotalMilliseconds,1))
    return [pscustomobject]@{
        ExitCode  = $exitCode
        ElapsedMs = [math]::Round($sw.Elapsed.TotalMilliseconds,1)
    }
}

function Copy-LogIfPresent([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return $true
    }
    return $false
}

function Get-NeuralCacheRoots([string]$Root) {
    $candidates = New-Object System.Collections.Generic.List[string]
    $portable = Join-Path $Root 'cache\v1'
    $candidates.Add($portable)

    $ini = Join-Path $Root 'DLSSVideoPlayer.ini'
    if (Test-Path -LiteralPath $ini -PathType Leaf) {
        try {
            $text = Get-Content -LiteralPath $ini -Raw
            $matches = [regex]::Matches($text, '(?im)^\s*CacheDirectory\s*=\s*(.+?)\s*$')
            foreach ($m in $matches) {
                $value = $m.Groups[1].Value.Trim().Trim('"')
                if (-not [string]::IsNullOrWhiteSpace($value)) { $candidates.Add($value) }
            }
        } catch { }
    }

    $log = Join-Path $Root 'DLSSVideoPlayer.log'
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        try {
            $text = Get-Content -LiteralPath $log -Raw
            $matches = [regex]::Matches($text, '(?im)Neural cache directory:\s*(.+?)\s*$')
            foreach ($m in $matches) {
                $value = $m.Groups[1].Value.Trim().Trim('"')
                if (-not [string]::IsNullOrWhiteSpace($value)) { $candidates.Add($value) }
            }
        } catch { }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'DLSSVideoPlayer\NeuralCache\v1'))
    }

    return @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique)
}

function Copy-RenderReceipts([string[]]$Roots, [datetime]$Since, [string]$Destination) {
    $records = @()
    if ($Roots.Count -eq 0) { return $records }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $index = 0
    foreach ($root in $Roots) {
        $files = @(Get-ChildItem -LiteralPath $root -Filter 'receipt.json' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-2) } |
            Sort-Object LastWriteTime)
        foreach ($file in $files) {
            $index++
            $destName = 'receipt-{0:D3}.json' -f $index
            $destPath = Join-Path $Destination $destName
            Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
            $manifest = Join-Path $file.Directory.FullName 'manifest.json'
            $manifestDest = $null
            if (Test-Path -LiteralPath $manifest -PathType Leaf) {
                $manifestDest = Join-Path $Destination ('manifest-{0:D3}.json' -f $index)
                Copy-Item -LiteralPath $manifest -Destination $manifestDest -Force
            }
            $records += [pscustomobject]@{
                SourceReceipt = $file.FullName
                CopiedReceipt = $destPath
                CopiedManifest = $manifestDest
                LastWriteTime = $file.LastWriteTime.ToString('o')
            }
        }
    }
    return $records
}

function Read-AllDiagnosticText([string]$SessionDir) {
    $files = Get-ChildItem -LiteralPath $SessionDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @('.log','.txt','.json') -and $_.Length -lt 25MB
    }
    $sb = New-Object Text.StringBuilder
    foreach ($f in $files) {
        try {
            [void]$sb.AppendLine("===== $($f.FullName) =====")
            [void]$sb.AppendLine((Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop))
        } catch { }
    }
    return $sb.ToString()
}

function Test-Pattern([string]$Text, [string[]]$Patterns) {
    foreach ($p in $Patterns) {
        if ($Text -match $p) { return $true }
    }
    return $false
}


function Export-NativeFrameTimings([string]$Text, [string]$CsvPath) {
    $pattern = '(?im)RTX2060_FRAME_TIMING\s+index=(\d+)\s+neuralGpuMs=([0-9eE+\-.]+)\s+readMs=([0-9eE+\-.]+)\s+guideMs=([0-9eE+\-.]+)\s+renderMs=([0-9eE+\-.]+)\s+evalMs=([0-9eE+\-.]+)\s+writeMs=([0-9eE+\-.]+)\s+latencyMs=([0-9eE+\-.]+)'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -eq 0) { return 0 }
    'index,neural_gpu_ms,read_ms,guide_ms,render_ms,eval_ms,write_ms,latency_ms' | Set-Content -LiteralPath $CsvPath -Encoding UTF8
    foreach ($m in $matches) {
        Add-Content -LiteralPath $CsvPath -Encoding UTF8 -Value ($m.Groups[1].Value + ',' + $m.Groups[2].Value + ',' + $m.Groups[3].Value + ',' + $m.Groups[4].Value + ',' + $m.Groups[5].Value + ',' + $m.Groups[6].Value + ',' + $m.Groups[7].Value + ',' + $m.Groups[8].Value)
    }
    return $matches.Count
}

if ([string]::IsNullOrWhiteSpace($InputVideo)) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose a video for the DLSS 5 offline RTX 2060 test'
    $dlg.Filter = 'Video files|*.mp4;*.mkv;*.mov;*.avi;*.m4v;*.webm;*.mts;*.m2ts|All files|*.*'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        throw 'No input video selected.'
    }
    $InputVideo = $dlg.FileName
}

$InputVideo = (Resolve-Path -LiteralPath $InputVideo).Path
$PlayerRoot = (Resolve-Path -LiteralPath $PlayerRoot).Path
if (-not (Test-Path -LiteralPath $OutputRoot)) { New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null }
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$playerExe = Find-Executable $PlayerRoot 'DLSSVideoPlayer.exe'
if ([string]::IsNullOrWhiteSpace($playerExe)) { throw "DLSSVideoPlayer.exe was not found under: $PlayerRoot" }
# Treat the executable's directory as the effective upstream root even when -PlayerRoot points one level above it.
$PlayerRoot = Split-Path -Parent $playerExe
$neuralWorker = Find-Executable $PlayerRoot 'NeuralWorker.exe'

$sessionStartedAt = Get-Date
$timestamp = $sessionStartedAt.ToString('yyyyMMdd-HHmmss')
$stem = Safe-FileStem ([IO.Path]::GetFileNameWithoutExtension($InputVideo))
$sessionDir = Join-Path $OutputRoot ("{0}-{1}" -f $stem, $timestamp)
$probeDir = Join-Path $sessionDir 'frame-probes'
$logsDir = Join-Path $sessionDir 'logs'
New-Item -ItemType Directory -Path $sessionDir,$probeDir,$logsDir -Force | Out-Null
$eventsCsv = Join-Path $sessionDir 'events.csv'
$gpuCsv = Join-Path $sessionDir 'gpu-samples.csv'
$frameCsv = Join-Path $sessionDir 'frame-probes.csv'

Write-Section 'RTX 2060 / DLSS 5 offline video test'
Write-Host "Input:      $InputVideo"
Write-Host "Player:     $playerExe"
Write-Host "Results:    $sessionDir"
Write-Host "Preset:     $Preset"

$originalHashBefore = (Get-FileHash -LiteralPath $InputVideo -Algorithm SHA256).Hash
$originalLengthBefore = (Get-Item -LiteralPath $InputVideo).Length

$minimumDriver = '610.47'
$smi = Get-NvidiaSmiPath
$gpu = Get-GpuSnapshot $smi
$driverMeetsMinimum = $null
$isRtx2060Family = $false
$isApproximately6GB = $false
if ($null -ne $gpu) {
    $driverMeetsMinimum = Test-DriverAtLeast $gpu.DriverVersion $minimumDriver
    $isRtx2060Family = ($gpu.Name -match '(?i)RTX\s*2060')
    if ($null -ne $gpu.MemoryTotalMB) { $isApproximately6GB = ($gpu.MemoryTotalMB -ge 5500 -and $gpu.MemoryTotalMB -le 7000) }
    Write-Host ("GPU:        {0}" -f $gpu.Name)
    Write-Host ("Driver:     {0} (upstream floor {1}; passes={2})" -f $gpu.DriverVersion, $minimumDriver, $driverMeetsMinimum)
    if ($null -ne $gpu.MemoryTotalMB -and $null -ne $gpu.MemoryFreeMB) {
        Write-Host ("VRAM:       {0:N0} MiB total, {1:N0} MiB free" -f $gpu.MemoryTotalMB, $gpu.MemoryFreeMB)
    }
    if (-not $isRtx2060Family) { Write-Warning "This machine reports '$($gpu.Name)'. The harness will still run, but it will not count as an RTX 2060-family test." }
    if ($driverMeetsMinimum -eq $false) { Write-Warning "Driver $($gpu.DriverVersion) is below the upstream neural-runtime floor of $minimumDriver. Expect the Feature 18 preflight/render to fail." }
} else {
    Write-Warning 'nvidia-smi was not found or did not return a GPU snapshot. The render test can still run, but VRAM telemetry will be unavailable.'
}

$requiredRuntime = @(
    (Join-Path $PlayerRoot 'neural-runtime\NeuralWorker.exe'),
    (Join-Path $PlayerRoot 'neural-runtime\ReShade.ini'),
    (Join-Path $PlayerRoot 'neural-runtime\dxgi.dll'),
    (Join-Path $PlayerRoot 'neural-runtime\renodx-dlss5.addon64'),
    (Join-Path $PlayerRoot 'neural-runtime\nvngx_dlssnr.dll')
)
$runtimeMissing = @($requiredRuntime | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($runtimeMissing.Count -gt 0) {
    Write-Warning 'Some expected neural-runtime files were not found. The complete upstream package is required for the experimental DLSS 5 neural path.'
    $runtimeMissing | ForEach-Object { Write-Warning "Missing: $_" }
}

$verifyExit = $null
$verifyScript = Join-Path $PlayerRoot 'verify_package.ps1'
if (-not $SkipPackageVerify -and (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
    Write-Section 'Verifying upstream package'
    $verifyLog = Join-Path $logsDir 'verify-package.log'
    $verifyResult = Invoke-UpstreamRender -Exe 'powershell.exe' -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$verifyScript) -LogPath $verifyLog -Phase 'verify-package' -EventsCsv $eventsCsv -WorkingDirectory $PlayerRoot
    $verifyExit = $verifyResult.ExitCode
    if ($verifyExit -ne 0) { Write-Warning "Upstream package verification exited with code $verifyExit. The neural test will continue, but treat the result cautiously." }
}

$gpuSampler = Start-GpuSampler $smi $gpuCsv 500

$scaleAttempts = if ($NoScaleFallback) { @(100) } else { @(100,75,50) }
$chosenScale = $null
$capabilityResults = @()

try {
    Write-Section 'Capability probe: can the neural path run at all?'
    foreach ($scale in $scaleAttempts) {
        $probeOut = Join-Path $sessionDir ("capability-probe-{0}pct.mkv" -f $scale)
        $probeLog = Join-Path $logsDir ("capability-probe-{0}pct.log" -f $scale)
        $rangeEnd = [math]::Max(1, $CapabilityProbeFrames)
        $args = @('--render',$InputVideo,'--stages','nr','--processing-scale',"$scale",'--preset',$Preset,'--range',("f0-f{0}" -f $rangeEnd),'--out',$probeOut)
        $r = Invoke-UpstreamRender -Exe $playerExe -Arguments $args -LogPath $probeLog -Phase ("capability-{0}" -f $scale) -EventsCsv $eventsCsv -WorkingDirectory $PlayerRoot
        $ok = ($r.ExitCode -eq 0) -and (Test-Path -LiteralPath $probeOut -PathType Leaf) -and ((Get-Item -LiteralPath $probeOut).Length -gt 0)
        $capabilityResults += [pscustomobject]@{ Scale=$scale; Success=$ok; ExitCode=$r.ExitCode; ElapsedMs=$r.ElapsedMs; Output=$probeOut; Log=$probeLog }
        if ($ok) {
            $chosenScale = $scale
            Write-Host ("Capability probe succeeded at {0}% processing scale in {1:N1} s." -f $scale, ($r.ElapsedMs/1000))
            break
        }
        Write-Warning ("Capability probe failed at {0}% processing scale (exit {1})." -f $scale, $r.ExitCode)
    }

    if ($null -ne $chosenScale -and -not $SkipFrameProbes) {
        Write-Section ("Per-frame diagnostic probes ({0} frames)" -f $FrameProbeCount)
        'frame,scale,exit_code,success,elapsed_ms,vram_before_mb,vram_after_mb,output_bytes' | Set-Content -LiteralPath $frameCsv -Encoding UTF8
        for ($i=0; $i -lt $FrameProbeCount; $i++) {
            $before = Get-GpuSnapshot $smi
            $oneOut = Join-Path $probeDir ("frame-{0:D6}.mkv" -f $i)
            $oneLog = Join-Path $logsDir ("frame-{0:D6}.log" -f $i)
            $args = @('--render',$InputVideo,'--stages','nr','--processing-scale',"$chosenScale",'--preset',$Preset,'--range',("f{0}-f{1}" -f $i,($i+1)),'--out',$oneOut)
            $r = Invoke-UpstreamRender -Exe $playerExe -Arguments $args -LogPath $oneLog -Phase ("frame-{0:D6}" -f $i) -EventsCsv $eventsCsv -WorkingDirectory $PlayerRoot
            $after = Get-GpuSnapshot $smi
            $ok = ($r.ExitCode -eq 0) -and (Test-Path -LiteralPath $oneOut -PathType Leaf) -and ((Get-Item -LiteralPath $oneOut).Length -gt 0)
            $bytes = if (Test-Path -LiteralPath $oneOut) { (Get-Item -LiteralPath $oneOut).Length } else { 0 }
            $vBefore = if ($null -ne $before) { $before.MemoryUsedMB } else { '' }
            $vAfter = if ($null -ne $after) { $after.MemoryUsedMB } else { '' }
            Add-Content -LiteralPath $frameCsv -Value ("{0},{1},{2},{3},{4},{5},{6},{7}" -f $i,$chosenScale,$r.ExitCode,$ok,$r.ElapsedMs,$vBefore,$vAfter,$bytes) -Encoding UTF8
            Write-Host ("Frame {0}: {1} in {2:N2} s" -f $i, $(if($ok){'OK'}else{'FAIL'}), ($r.ElapsedMs/1000))
            if (-not $ok) { break }
        }
    }

    $fullOut = Join-Path $sessionDir ("{0}-dlss5-neural.mkv" -f $stem)
    $fullResult = $null
    if ($null -ne $chosenScale -and -not $ProbeOnly) {
        Write-Section 'Full offline render'
        $fullLog = Join-Path $logsDir 'full-render.log'
        $args = @('--render',$InputVideo,'--stages','nr','--processing-scale',"$chosenScale",'--preset',$Preset,'--out',$fullOut)
        $fullResult = Invoke-UpstreamRender -Exe $playerExe -Arguments $args -LogPath $fullLog -Phase 'full-render' -EventsCsv $eventsCsv -WorkingDirectory $PlayerRoot
        if ($fullResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $fullOut -PathType Leaf)) {
            Write-Host "Full render completed: $fullOut"
        } else {
            Write-Warning "Full render failed (exit $($fullResult.ExitCode))."
        }
    }
} finally {
    Stop-GpuSampler $gpuSampler
}

# Copy upstream logs after all jobs finish so this session is self-contained.
Copy-LogIfPresent (Join-Path $PlayerRoot 'DLSSVideoPlayer.log') (Join-Path $logsDir 'upstream-DLSSVideoPlayer.log') | Out-Null
Copy-LogIfPresent (Join-Path $PlayerRoot 'neural-runtime\NeuralWorker.log') (Join-Path $logsDir 'upstream-NeuralWorker.log') | Out-Null
Copy-LogIfPresent (Join-Path $PlayerRoot 'neural-runtime\ReShade.log') (Join-Path $logsDir 'upstream-ReShade.log') | Out-Null

# Preserve the upstream evidence receipts produced/reused by this session when they can be located.
$cacheRoots = @(Get-NeuralCacheRoots $PlayerRoot)
$receiptDir = Join-Path $logsDir 'receipts'
$receiptRecords = @(Copy-RenderReceipts -Roots $cacheRoots -Since $sessionStartedAt -Destination $receiptDir)
if ($receiptRecords.Count -gt 0) {
    $receiptRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $receiptDir 'index.json') -Encoding UTF8
}

$originalHashAfter = (Get-FileHash -LiteralPath $InputVideo -Algorithm SHA256).Hash
$originalLengthAfter = (Get-Item -LiteralPath $InputVideo).Length
$originalUntouched = ($originalHashBefore -eq $originalHashAfter) -and ($originalLengthBefore -eq $originalLengthAfter)

$diagnostics = Read-AllDiagnosticText $sessionDir
$oom = Test-Pattern $diagnostics @('(?i)out of memory','(?i)E_OUTOFMEMORY','(?i)CUDA.*out of memory','(?i)alloc(ation)?.*fail.*(vram|video memory)','(?i)insufficient.*(vram|video memory)')
$deviceRemoved = Test-Pattern $diagnostics @('(?i)DXGI_ERROR_DEVICE_REMOVED','(?i)device removed','(?i)device hung')
$runtimeInitialized = Test-Pattern $diagnostics @('(?i)DLSSNR.*D3D12 runtime initialized','(?i)neural.*runtime initialized')
$feature18Fail = Test-Pattern $diagnostics @('(?i)feature\s*18.*(create|eval).*(fail|error|refus)','(?i)feature\s*18 create failed','0xbad00002')
$feature18Evidence = Test-Pattern $diagnostics @('(?i)feature\s*18.*(success|created|evaluated|armed)','(?i)verifiedNeuralFrames','(?i)nativeEvaluations')
$runtimeLockFail = Test-Pattern $diagnostics @('(?i)runtime lock drift','(?i)runtime.*lock.*refus','(?i)neural runtime.*missing')
$retryExhausted = Test-Pattern $diagnostics @('(?i)retry-exhausted','(?i)retry exhausted')
$nativeFrameCsv = Join-Path $sessionDir 'native-frame-timings.csv'
$nativeFrameTimingRows = Export-NativeFrameTimings -Text $diagnostics -CsvPath $nativeFrameCsv

$gpuStats = $null
if (Test-Path -LiteralPath $gpuCsv -PathType Leaf) {
    try {
        $samples = Import-Csv -LiteralPath $gpuCsv
        if ($samples.Count -gt 0) {
            $usedVals = @($samples | ForEach-Object { Convert-ToDoubleOrNull $_.memory_used_mb } | Where-Object { $null -ne $_ })
            $freeVals = @($samples | ForEach-Object { Convert-ToDoubleOrNull $_.memory_free_mb } | Where-Object { $null -ne $_ })
            $utilVals = @($samples | ForEach-Object { Convert-ToDoubleOrNull $_.util_gpu_pct } | Where-Object { $null -ne $_ })
            $tempVals = @($samples | ForEach-Object { Convert-ToDoubleOrNull $_.temp_c } | Where-Object { $null -ne $_ })
            $gpuStats = [pscustomobject]@{
                Samples = $samples.Count
                PeakUsedMB = if ($usedVals.Count -gt 0) { ($usedVals | Measure-Object -Maximum).Maximum } else { $null }
                MinFreeMB = if ($freeVals.Count -gt 0) { ($freeVals | Measure-Object -Minimum).Minimum } else { $null }
                PeakUtilPct = if ($utilVals.Count -gt 0) { ($utilVals | Measure-Object -Maximum).Maximum } else { $null }
                PeakTempC = if ($tempVals.Count -gt 0) { ($tempVals | Measure-Object -Maximum).Maximum } else { $null }
            }
        }
    } catch { }
}

$actualRenderAdapter = $null
$adapterMatches = [regex]::Matches($diagnostics, '(?im)^.*D3D12 device adapter\s+"([^"]+)".*$')
if ($adapterMatches.Count -gt 0) {
    $actualRenderAdapter = $adapterMatches[$adapterMatches.Count - 1].Groups[1].Value
}
$actualAdapterIsRtx2060Family = if ($null -ne $actualRenderAdapter) { ($actualRenderAdapter -match '(?i)RTX\s*2060') } else { $null }

$capabilitySuccess = ($null -ne $chosenScale)
$fullOutputPath = Join-Path $sessionDir ("{0}-dlss5-neural.mkv" -f $stem)
$fullOutputExists = (Test-Path -LiteralPath $fullOutputPath -PathType Leaf) -and ((Get-Item -LiteralPath $fullOutputPath).Length -gt 0)
$verdict = 'FAIL_RENDER'
if (-not $originalUntouched) { $verdict = 'FAIL_ORIGINAL_CHANGED' }
elseif ($driverMeetsMinimum -eq $false) { $verdict = 'FAIL_DRIVER_TOO_OLD' }
elseif ($runtimeMissing.Count -gt 0) { $verdict = 'FAIL_RUNTIME_MISSING' }
elseif ($feature18Fail -or $runtimeLockFail) { $verdict = 'FAIL_NEURAL_RUNTIME' }
elseif ($oom) { $verdict = 'FAIL_VRAM_OR_ALLOCATION' }
elseif ($deviceRemoved) { $verdict = 'FAIL_DEVICE_REMOVED' }
elseif ($capabilitySuccess -and $ProbeOnly) { $verdict = 'PASS_CAPABILITY_PROBE' }
elseif ($capabilitySuccess -and $fullOutputExists) { $verdict = 'PASS_FULL_RENDER' }
elseif ($capabilitySuccess) { $verdict = 'PASS_NEURAL_PATH_FULL_RENDER_INCOMPLETE' }

$summary = [ordered]@{
    HarnessVersion = '0.1.1'
    Created = (Get-Date).ToString('o')
    Verdict = $verdict
    InputVideo = $InputVideo
    InputSha256Before = $originalHashBefore
    InputSha256After = $originalHashAfter
    OriginalUntouched = $originalUntouched
    PlayerExe = $playerExe
    NeuralWorkerExe = $neuralWorker
    PlayerRoot = $PlayerRoot
    Preset = $Preset
    ChosenProcessingScale = $chosenScale
    ProbeOnly = [bool]$ProbeOnly
    CapabilityResults = $capabilityResults
    RuntimeMissingFiles = $runtimeMissing
    PackageVerifyExitCode = $verifyExit
    CacheRootsInspected = $cacheRoots
    CopiedReceiptCount = $receiptRecords.Count
    CopiedReceipts = $receiptRecords
    NativePerFrameTimingRows = $nativeFrameTimingRows
    Signals = [ordered]@{
        RuntimeInitializedEvidenceSeen = $runtimeInitialized
        Feature18EvidenceSeen = $feature18Evidence
        Feature18FailureSeen = $feature18Fail
        RuntimeLockFailureSeen = $runtimeLockFail
        OutOfMemorySignalSeen = $oom
        DeviceRemovedSignalSeen = $deviceRemoved
        RetryExhaustedSignalSeen = $retryExhausted
        ValidatedNeuralProbeOutput = $capabilitySuccess
    }
    MinimumDriver = $minimumDriver
    DriverMeetsMinimum = $driverMeetsMinimum
    NvidiaSmiRtx2060Family = $isRtx2060Family
    NvidiaSmiApproximately6GB = $isApproximately6GB
    ActualRenderAdapter = $actualRenderAdapter
    ActualRenderAdapterRtx2060Family = $actualAdapterIsRtx2060Family
    GPU = $gpu
    GPUStats = $gpuStats
    SessionDirectory = $sessionDir
}
$summaryPath = Join-Path $sessionDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$reportPath = Join-Path $sessionDir 'REPORT.md'
$gpuLine = if ($null -ne $gpu) {
    $vramText = if ($null -ne $gpu.MemoryTotalMB) { "$([math]::Round($gpu.MemoryTotalMB)) MiB" } else { 'unavailable' }
    "- GPU: **$($gpu.Name)**; driver **$($gpu.DriverVersion)** (minimum **$minimumDriver**, passes: **$driverMeetsMinimum**); VRAM **$vramText**."
} else { '- GPU telemetry: unavailable (`nvidia-smi` not found or unreadable).' }
$statsLine = if ($null -ne $gpuStats) {
    $peakUsedText = if ($null -ne $gpuStats.PeakUsedMB) { "$([math]::Round($gpuStats.PeakUsedMB)) MiB" } else { 'unavailable' }
    $minFreeText = if ($null -ne $gpuStats.MinFreeMB) { "$([math]::Round($gpuStats.MinFreeMB)) MiB" } else { 'unavailable' }
    $peakUtilText = if ($null -ne $gpuStats.PeakUtilPct) { "$([math]::Round($gpuStats.PeakUtilPct))%" } else { 'unavailable' }
    $peakTempText = if ($null -ne $gpuStats.PeakTempC) { "$([math]::Round($gpuStats.PeakTempC)) C" } else { 'unavailable' }
    "- Sampled peak VRAM use: **$peakUsedText**; minimum free: **$minFreeText**; peak GPU utilization: **$peakUtilText**; peak temperature: **$peakTempText**."
} else { '- GPU sampling summary: unavailable.' }
$adapterLine = if ($null -ne $actualRenderAdapter) { "- Adapter named by the upstream D3D12 render log: **$actualRenderAdapter** (RTX 2060 family: **$actualAdapterIsRtx2060Family**)." } else { '- Adapter named by the upstream D3D12 render log: not found in copied logs.' }
$runtimeLine = if ($runtimeInitialized) { '- Neural runtime initialization marker: **seen** (`D3D12 runtime initialized`).' } else { '- Neural runtime initialization marker: **not seen** in the copied logs/receipts.' }
$featureLine = if ($feature18Fail) { '- Feature 18 / neural runtime: **failure evidence found**. See logs.' } elseif ($capabilitySuccess) { '- Feature 18 / neural runtime: the upstream validated neural render path produced a probe output; this is stronger than runtime initialization alone.' } elseif ($feature18Evidence) { '- Feature 18 / neural runtime: success-like evidence appears in logs, but no validated probe output completed.' } else { '- Feature 18 / neural runtime: no conclusive Feature 18 success evidence was found.' }
$fullLine = if ($ProbeOnly) { '- Full export: skipped by `-ProbeOnly`.' } elseif ($fullOutputExists) { "- Full export: **completed** as `$([IO.Path]::GetFileName((Join-Path $sessionDir ("{0}-dlss5-neural.mkv" -f $stem))))`." } else { '- Full export: did not complete.' }

@"
# RTX 2060 DLSS 5 Offline Video Test Report

**Verdict: `$verdict`**

## Machine and runtime

$gpuLine
$statsLine
$adapterLine
$runtimeLine
$featureLine
- Selected processing scale: **$(if($null -eq $chosenScale){'none'}else{"$chosenScale%"})**.
- Expected neural-runtime files missing: **$($runtimeMissing.Count)**.
- Package verifier exit code: **$(if($null -eq $verifyExit){'not run'}else{$verifyExit})**.
- Upstream render receipts copied into this session: **$($receiptRecords.Count)**.
- Native per-frame timing rows extracted from a patched source build: **$nativeFrameTimingRows**.

## Input safety

- Original input SHA-256 before: `$originalHashBefore`
- Original input SHA-256 after:  `$originalHashAfter`
- Original remained byte-for-byte unchanged: **$originalUntouched**.

## Render result

$fullLine
- Capability probe succeeded: **$capabilitySuccess**.
- Out-of-memory/allocation signal found: **$oom**.
- Device-removed signal found: **$deviceRemoved**.
- Neural runtime initialization marker found: **$runtimeInitialized**.
- Feature-18 failure signal found: **$feature18Fail**.
- Runtime-lock failure signal found: **$runtimeLockFail**.
- Retry-exhausted signal found: **$retryExhausted**.

## What the per-frame CSV means

If `frame-probes.csv` exists, each row is a deliberately isolated one-frame upstream render. Its elapsed time therefore includes process/runtime startup, preroll, neural evaluation, capture and encoder finalization. It is a worst-case wall-clock frame test, not a pure kernel benchmark. The full export uses the upstream sequential offline renderer so temporal state is retained across frames.

## Files to inspect

- `summary.json` — machine-readable verdict and flags.
- `gpu-samples.csv` — 2 Hz whole-GPU VRAM/utilization/temperature/power samples.
- `events.csv` — phase start/end timestamps.
- `frame-probes.csv` — isolated one-frame wall times, when enabled.
- `native-frame-timings.csv` — every captured frame's native GPU/stage timing when the optional source patch is used.
- `logs/` — timestamped harness console logs plus copied upstream player/worker/ReShade logs.
- `logs/receipts/` — upstream `receipt.json` / manifest evidence found for renders created during this session; these preserve the native neural timing/VRAM summary and preflight evidence.
- `capability-probe-*.mkv` — short neural probe(s).
- `*-dlss5-neural.mkv` — full processed export, if completed.

## Interpretation

A `PASS_FULL_RENDER` result is practical evidence that this exact RTX/driver/runtime combination executed the experimental neural path and exported a complete file. It is not evidence of official NVIDIA support: the upstream project is a community experiment using a modified unsigned neural runtime. A failure should be classified from the flags above before concluding that the RTX 2060 itself is incapable; driver floor, runtime lock, VRAM allocation and device-removal failures are different failure modes.
"@ | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Section 'Finished'
Write-Host "Verdict:  $verdict"
Write-Host "Report:   $reportPath"
Write-Host "Summary:  $summaryPath"
Write-Host "Results:  $sessionDir"
if (-not $originalUntouched) {
    Write-Error 'The source file hash or size changed during the test. Do not trust this run.'
}
